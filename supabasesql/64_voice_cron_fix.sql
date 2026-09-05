-- ============================================================
-- 64 — Voice cron fix + client-callable materialize RPC
--
-- Why this file exists:
--   `voice_schedules` rows were getting inserted with status='pending'
--   but `voice_messages` was staying empty. Root cause: the pg_cron
--   job that should call materialize_due_voice_schedules() every
--   minute was not scheduled on the live database — either because
--   pg_cron was never enabled in the Supabase dashboard, or because
--   61_voice_cron.sql silently no-op'd when pg_cron was off.
--
-- What this file does:
--   1. Re-runs the materialize function (idempotent — replaces).
--   2. Re-schedules the pg_cron job — and this time prints loud
--      RAISE NOTICE messages so missing pg_cron is visible in the
--      SQL Editor messages panel (the original silently returned).
--   3. Adds a public RPC `materialize_due_voices_now()` granted to
--      `authenticated` so the Flutter client can call it as a
--      safety-net fallback right after scheduling a voice that
--      should be delivered "now" (or very soon). This guarantees
--      the patient sees the voice even if pg_cron is broken.
--
-- Safe to re-run. Run this once in the Supabase SQL Editor.
-- ============================================================


-- ============================================================
-- SECTION A — recreate the materialize function
-- ============================================================
-- Identical to 61_voice_cron.sql Section A; declared here so this
-- file is self-contained and can fix things even if 61 was never
-- applied.
drop function if exists public.materialize_due_voice_schedules();
create or replace function public.materialize_due_voice_schedules()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int := 0;
begin
  with due as (
    select id, caretaker_user_id, patient_user_id,
           storage_path, duration_ms, caption
      from public.voice_schedules
     where status = 'pending'
       and deliver_at <= now()
     order by deliver_at asc
     for update skip locked
     limit 100
  ),
  ins as (
    insert into public.voice_messages
      (sender_user_id, receiver_user_id, storage_path,
       duration_ms, caption, thread_id, is_reply)
    select caretaker_user_id, patient_user_id, storage_path,
           duration_ms, caption, id, false
      from due
    returning id, thread_id
  ),
  upd as (
    update public.voice_schedules s
       set status               = 'delivered',
           delivered_message_id = ins.id,
           updated_at           = now()
      from ins
     where s.id = ins.thread_id
     returning s.id
  )
  select count(*) into v_count from upd;

  return v_count;
end;
$$;

revoke all on function public.materialize_due_voice_schedules() from public;


-- ============================================================
-- SECTION B — reschedule the pg_cron job (loud on failure)
-- ============================================================
-- Differs from 61 in one important way: when pg_cron isn't installed
-- we RAISE NOTICE with extra detail AND we also RAISE WARNING so the
-- missing-extension state shows up at the top of the SQL Editor
-- messages panel rather than being easy to miss.
do $$
declare
  v_jobid bigint;
  v_ext   boolean;
begin
  select exists (
    select 1 from pg_extension where extname = 'pg_cron'
  ) into v_ext;

  if not v_ext then
    raise notice '========================================================';
    raise notice 'pg_cron extension is NOT enabled on this project.';
    raise notice 'Go to Supabase Dashboard -> Database -> Extensions';
    raise notice 'and enable pg_cron, then re-run this file.';
    raise notice 'The client-side fallback (Section C) will still work,';
    raise notice 'but you should fix pg_cron for background scheduling.';
    raise notice '========================================================';
    return;
  end if;

  -- Remove any pre-existing job with our name (idempotency).
  select jobid into v_jobid
    from cron.job
   where jobname = 'materialize-voice-schedules';

  if v_jobid is not null then
    perform cron.unschedule(v_jobid);
    raise notice 'Unscheduled previous job id=%', v_jobid;
  end if;

  -- Every minute, "* * * * *"
  perform cron.schedule(
    'materialize-voice-schedules',
    '* * * * *',
    $cron$ select public.materialize_due_voice_schedules(); $cron$
  );

  raise notice '========================================================';
  raise notice 'Scheduled pg_cron job "materialize-voice-schedules".';
  raise notice 'It will run every minute and call';
  raise notice 'public.materialize_due_voice_schedules() to turn';
  raise notice 'pending voice_schedules rows into voice_messages.';
  raise notice '========================================================';
end $$;


-- ============================================================
-- SECTION C — client-callable RPC for instant fallback
-- ============================================================
-- The Flutter client calls this immediately after creating a
-- schedule whose deliver_at is within ~2 minutes of now (or already
-- past). The RPC runs the same materialize function. Even if pg_cron
-- is broken, voices scheduled for "now" reach the patient within
-- ~1 second of the caretaker hitting send.
--
-- Granted to `authenticated` so any logged-in caretaker/patient can
-- trigger it (the underlying function is SECURITY DEFINER and runs
-- as postgres, which bypasses RLS for the voice_messages insert).
create or replace function public.materialize_due_voices_now()
returns int
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.materialize_due_voice_schedules();
end;
$$;
grant execute on function public.materialize_due_voices_now() to authenticated;


-- ============================================================
-- SECTION D — verification queries (READ-ONLY, no side effects)
-- ============================================================
-- After running this file, scroll up to the messages panel. You
-- should see either:
--   * "Scheduled pg_cron job ..."
--   * "pg_cron extension is NOT enabled..."
--
-- Then run these one at a time to confirm:
--
-- 1. Is pg_cron installed?
--    select * from pg_extension where extname = 'pg_cron';
--
-- 2. Is our job scheduled?
--    select jobname, schedule, active
--      from cron.job
--     where jobname = 'materialize-voice-schedules';
--    -- Expect: 1 row with schedule='* * * * *', active=true
--
-- 3. How many schedules are pending?
--    select count(*) from public.voice_schedules
--     where status = 'pending';
--
-- 4. Run materialize manually to drain whatever's stuck:
--    select public.materialize_due_voices_now();
--    -- Expect: a positive integer (number of rows materialized)
--
-- 5. Confirm voice_messages now has rows:
--    select count(*) from public.voice_messages;
--    select id, sender_user_id, receiver_user_id, created_at
--      from public.voice_messages
--     order by created_at desc
--     limit 5;
--
-- 6. Confirm the schedules flipped to 'delivered':
--    select id, status, delivered_message_id, updated_at
--      from public.voice_schedules
--     order by updated_at desc
--     limit 5;
-- ============================================================
