-- ============================================================
-- 61 — Scheduled-voice delivery: materialize + pg_cron
--
-- This file provides the SERVER-SIDE scheduled delivery that makes
-- the voice-message feature work even when the caretaker's phone
-- is off.
--
-- How it works:
--   1. Caretaker records a voice and inserts a row into
--      voice_schedules with deliver_at = future timestamp.
--   2. Every minute, the pg_cron job calls
--      public.materialize_due_voice_schedules().
--   3. That function selects up to 100 pending rows whose
--      deliver_at <= now() FOR UPDATE SKIP LOCKED, copies each
--      one into voice_messages (sender = caretaker,
--      receiver = patient), and flips the schedule's status to
--      'delivered' with delivered_message_id set to the new
--      voice_messages.id.
--   4. The patient's existing realtime subscription (extended in
--      62_*.sql) fires onPostgresChanges and the patient's inbox
--      auto-refreshes within ~1 second.
--
-- Safe to re-run.
-- ============================================================


-- ============================================================
-- SECTION A — materialize_due_voice_schedules()
-- ============================================================
-- SECURITY DEFINER so it can bypass the sender-only INSERT policy
-- on voice_messages (we need to insert with sender = the schedule's
-- caretaker_user_id, not auth.uid()).
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
           storage_path, duration_ms, caption, thread_id
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
    returning id, sender_user_id, receiver_user_id, storage_path,
              duration_ms, caption, thread_id, is_reply
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
-- Deliberately NOT granted to authenticated. Only the cron job
-- (running as the postgres role) calls this. If you ever need to
-- invoke it manually for debugging, GRANT temporarily then REVOKE.


-- ============================================================
-- SECTION B — pg_cron job
-- ============================================================
-- Requires the pg_cron extension to be enabled in Supabase
-- Dashboard → Database → Extensions. The job runs every minute.
--
-- Idempotent: if a job with the same name already exists, we
-- drop it first then re-create. This makes the file safe to
-- re-apply without piling up duplicate cron entries.
do $$
declare
  v_jobid bigint;
begin
  -- Bail out cleanly if pg_cron isn't installed on this project.
  if not exists (
    select 1 from pg_extension where extname = 'pg_cron'
  ) then
    raise notice 'pg_cron extension is not installed. Enable it in Dashboard → Database → Extensions, then re-run this file.';
    return;
  end if;

  -- Remove any pre-existing job with our name (idempotency).
  select jobid into v_jobid
    from cron.job
   where jobname = 'materialize-voice-schedules';

  if v_jobid is not null then
    perform cron.unschedule(v_jobid);
  end if;

  -- Every minute, "* * * * *"
  perform cron.schedule(
    'materialize-voice-schedules',
    '* * * * *',
    $cron$ select public.materialize_due_voice_schedules(); $cron$
  );
end $$;


-- ============================================================
-- SECTION C — helper RPC for the Flutter client
-- ============================================================
-- Public wrapper that just calls materialize once. Useful for
-- manual testing from the SQL editor (since we revoked direct
-- access to the internal function above).
create or replace function public.run_materialize_due_voice_schedules()
returns int
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.materialize_due_voice_schedules();
end;
$$;
grant execute on function public.run_materialize_due_voice_schedules() to authenticated;
