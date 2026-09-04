-- ============================================================
-- 53 — Caretaker realtime: auto-refresh when patient logs data
-- ============================================================
--
-- Problem: When a patient logs a meal / water dose / medicine /
-- workout / mood, the linked caretaker's screens do NOT auto-
-- refresh — the caretaker has to pull-to-refresh manually. This
-- migration adds a Postgres trigger on each data table that the
-- patient writes to. The trigger:
--
--   1. Looks up every active `caretaker_patient_links` row where
--      the patient is the writer.
--   2. Calls realtime.send(jsonb) on a per-caretaker topic so the
--      caretaker's Flutter app receives a private-channel
--      broadcast and re-fetches its screen.
--
-- Why a private broadcast and not `onPostgresChanges`?
-- The data tables are protected by `auth.uid() = user_id` RLS
-- policies, so a caretaker session cannot subscribe to a
-- patient's row directly. The trigger runs SECURITY DEFINER so
-- it can resolve the linked caretakers server-side and notify
-- them out-of-band.
--
-- Project compatibility:
-- realtime.send(jsonb) is only available on Supabase Realtime
-- ≥ 2.0. On older projects the function does not exist and
-- calling it raises SQLSTATE 42883 ("function does not exist"),
-- which would roll back the patient's row insert. The trigger
-- below probes pg_proc and skips the broadcast entirely when
-- the function is missing — the patient's row still inserts,
-- the caretaker just loses the live-update UX.
--
-- We also add the patient-write tables to the
-- `supabase_realtime` publication (idempotent DO block). The
-- patient app already subscribes to those tables via
-- postgres_changes, and the publication is harmless to add for
-- the caretaker side — RLS still blocks the caretaker from
-- reading the rows; the broadcast above is what actually
-- notifies them.
--
-- Reuses the same pattern as `caretaker_link_broadcast()` in
-- 28_roles_and_caretaker.sql.

-- ============================================================
-- 1. Broadcast function (one function, many triggers)
-- ============================================================
create or replace function public.patient_data_broadcast()
returns trigger
language plpgsql
security definer
set search_path = public, realtime
as $$
declare
  v_user uuid;
  v_caretaker_uid uuid;
  v_topic text;
  v_has_send_fn boolean;
  v_payload jsonb;
begin
  -- Resolve the patient (writer) user_id. workout_session_items
  -- has no user_id column of its own — its parent session does.
  if TG_TABLE_NAME = 'workout_session_items' then
    select user_id into v_user
      from public.workout_sessions
     where id = coalesce(NEW.session_id, OLD.session_id);
    if v_user is null then
      return coalesce(NEW, OLD);
    end if;
  else
    v_user := coalesce(NEW.user_id, OLD.user_id);
  end if;

  if v_user is null then
    return coalesce(NEW, OLD);
  end if;

  -- Build the payload once.
  v_payload := jsonb_build_object(
    'event',           'patient_data_changed',
    'table',           TG_TABLE_NAME,
    'op',              TG_OP,
    'patient_user_id', v_user,
    'at',              extract(epoch from now())
  );

  -- Probe pg_proc for realtime.send(jsonb). On Realtime < 2.0
  -- this function does not exist; we must skip the broadcast
  -- entirely rather than raise SQLSTATE 42883 which would abort
  -- the triggering row's INSERT/UPDATE/DELETE.
  select exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'realtime'
       and p.proname = 'send'
       and p.proargtypes::regtype[]::text[] @> ARRAY['jsonb']::text[]
  ) into v_has_send_fn;

  if not v_has_send_fn then
    return coalesce(NEW, OLD);
  end if;

  -- One broadcast per linked active caretaker. SECURITY DEFINER
  -- lets us read caretaker_patient_links across the caregiver
  -- boundary; RLS on that table is bypassed for the lookup.
  for v_caretaker_uid in
    select caretaker_user_id
      from public.caretaker_patient_links
     where patient_user_id = v_user
       and status = 'active'
  loop
    v_topic := 'caretaker_data_' || v_caretaker_uid::text;
    begin
      perform realtime.send(
        jsonb_build_object(
          'event',  'patient_data_changed',
          'topic',  v_topic,
          'payload', v_payload
        )
      );
    exception when others then
      -- Never let a broadcast failure abort the triggering row.
      raise notice 'patient_data_broadcast skipped: %', sqlerrm;
    end;
  end loop;

  return coalesce(NEW, OLD);
end;
$$;

-- ============================================================
-- 2. Triggers — one per patient-write table
-- ============================================================
drop trigger if exists trg_patient_data_broadcast_meal_intake       on public.meal_intake_log;
drop trigger if exists trg_patient_data_broadcast_medicine_doses    on public.medicine_doses;
drop trigger if exists trg_patient_data_broadcast_water_intake     on public.water_intake_log;
drop trigger if exists trg_patient_data_broadcast_daily_metrics    on public.daily_metrics;
drop trigger if exists trg_patient_data_broadcast_workout_sessions on public.workout_sessions;
drop trigger if exists trg_patient_data_broadcast_workout_items    on public.workout_session_items;
drop trigger if exists trg_patient_data_broadcast_mood_entries     on public.mood_entries;

create trigger trg_patient_data_broadcast_meal_intake
  after insert or update or delete on public.meal_intake_log
  for each row execute function public.patient_data_broadcast();

create trigger trg_patient_data_broadcast_medicine_doses
  after insert or update or delete on public.medicine_doses
  for each row execute function public.patient_data_broadcast();

create trigger trg_patient_data_broadcast_water_intake
  after insert or update or delete on public.water_intake_log
  for each row execute function public.patient_data_broadcast();

create trigger trg_patient_data_broadcast_daily_metrics
  after insert or update or delete on public.daily_metrics
  for each row execute function public.patient_data_broadcast();

create trigger trg_patient_data_broadcast_workout_sessions
  after insert or update or delete on public.workout_sessions
  for each row execute function public.patient_data_broadcast();

create trigger trg_patient_data_broadcast_workout_items
  after insert or update or delete on public.workout_session_items
  for each row execute function public.patient_data_broadcast();

create trigger trg_patient_data_broadcast_mood_entries
  after insert or update or delete on public.mood_entries
  for each row execute function public.patient_data_broadcast();

-- ============================================================
-- 3. Publication (idempotent)
-- ============================================================
-- The patient app already subscribes to these tables via
-- postgres_changes on its own session; adding them to the
-- publication is harmless. The caretaker app CANNOT subscribe
-- directly (RLS blocks reading the patient's rows), so this
-- publication entry is just future-proofing — the actual
-- caretaker notification comes from realtime.send above.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'meal_intake_log'
    ) then
      alter publication supabase_realtime add table public.meal_intake_log;
    end if;
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'medicine_doses'
    ) then
      alter publication supabase_realtime add table public.medicine_doses;
    end if;
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'water_intake_log'
    ) then
      alter publication supabase_realtime add table public.water_intake_log;
    end if;
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'daily_metrics'
    ) then
      alter publication supabase_realtime add table public.daily_metrics;
    end if;
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'workout_sessions'
    ) then
      alter publication supabase_realtime add table public.workout_sessions;
    end if;
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'workout_session_items'
    ) then
      alter publication supabase_realtime add table public.workout_session_items;
    end if;
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'mood_entries'
    ) then
      alter publication supabase_realtime add table public.mood_entries;
    end if;
  end if;
end $$;
