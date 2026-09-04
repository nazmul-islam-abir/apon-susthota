-- ============================================================
-- 54 — Caretaker realtime subscription: RLS + publication
-- ============================================================
--
-- Background:
-- This Supabase project (per Realtime Inspector screenshot) is on
-- Realtime < 2.0 private broadcasts, so `realtime.send(jsonb)` is
-- unavailable. The trigger in `53_caretaker_patient_data_realtime.sql`
-- still probes for that function and skips the broadcast when it's
-- missing — meaning live updates would NOT fire for caretakers.
--
-- This file provides the alternative path that DOES work on this
-- project: let the caretaker's auth session subscribe to the patient's
-- data tables directly via `onPostgresChanges`. To do that we have
-- to:
--
--   1. Add a SECOND RLS SELECT policy on each data table that grants
--      read access to a caretaker who is linked to that patient
--      (status = 'active'). Existing INSERT/UPDATE/DELETE policies
--      are unchanged — patients stay the only writers, and only on
--      their own rows.
--
--   2. Add each data table to the `supabase_realtime` publication
--      (idempotent DO block).
--
-- Safety:
--   * A caretaker's SELECT is restricted to rows whose user_id maps
--     to an active `caretaker_patient_links` row owned by the same
--     auth.uid(). They cannot read anyone's data they're not linked
--     to, and they cannot write anything.
--   * The patient's app already filters its queries by auth.uid()
--     (existing policy), so the patient's UI is unaffected.
--   * Cross-table exposure is limited to those 7 tables — the policy
--     is per-table, so it doesn't accidentally widen visibility on
--     user_profiles, foods, clinical_rules, etc.
--
-- IMPORTANT:
-- Run this AFTER `28_roles_and_caretaker.sql` and AFTER
-- `53_caretaker_patient_data_realtime.sql`. Order doesn't strictly
-- matter — they don't depend on each other — but applying all three
-- in sequence keeps the migration log tidy.

-- ============================================================
-- 1. Helper: returns true when the caller is an active caretaker
--    of the given patient. Used by every per-table policy below
--    so the policy bodies stay short and identical.
-- ============================================================
create or replace function public.is_active_caretaker_of(p_patient uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
      from public.caretaker_patient_links
     where caretaker_user_id = auth.uid()
       and patient_user_id   = p_patient
       and status            = 'active'
  );
$$;

grant execute on function public.is_active_caretaker_of(uuid) to authenticated;

-- ============================================================
-- 2. Per-table SELECT policy: caregiver-of-patient may read rows.
-- ============================================================

-- meal_intake_log ---------------------------------------------------
drop policy if exists "Caregiver may view linked patient's meal log"
  on public.meal_intake_log;
create policy "Caregiver may view linked patient's meal log"
  on public.meal_intake_log for select
  to authenticated
  using (public.is_active_caretaker_of(user_id));

-- medicine_doses ----------------------------------------------------
drop policy if exists "Caregiver may view linked patient's medicine doses"
  on public.medicine_doses;
create policy "Caregiver may view linked patient's medicine doses"
  on public.medicine_doses for select
  to authenticated
  using (public.is_active_caretaker_of(user_id));

-- water_intake_log --------------------------------------------------
drop policy if exists "Caregiver may view linked patient's water log"
  on public.water_intake_log;
create policy "Caregiver may view linked patient's water log"
  on public.water_intake_log for select
  to authenticated
  using (public.is_active_caretaker_of(user_id));

-- daily_metrics -----------------------------------------------------
drop policy if exists "Caregiver may view linked patient's daily metrics"
  on public.daily_metrics;
create policy "Caregiver may view linked patient's daily metrics"
  on public.daily_metrics for select
  to authenticated
  using (public.is_active_caretaker_of(user_id));

-- workout_sessions --------------------------------------------------
drop policy if exists "Caregiver may view linked patient's workout sessions"
  on public.workout_sessions;
create policy "Caregiver may view linked patient's workout sessions"
  on public.workout_sessions for select
  to authenticated
  using (public.is_active_caretaker_of(user_id));

-- workout_session_items: joined via session_id, not user_id ---------
drop policy if exists "Caregiver may view linked patient's workout items"
  on public.workout_session_items;
create policy "Caregiver may view linked patient's workout items"
  on public.workout_session_items for select
  to authenticated
  using (
    exists (
      select 1
        from public.workout_sessions s
       where s.id = workout_session_items.session_id
         and public.is_active_caretaker_of(s.user_id)
    )
  );

-- mood_entries ------------------------------------------------------
drop policy if exists "Caregiver may view linked patient's mood"
  on public.mood_entries;
create policy "Caregiver may view linked patient's mood"
  on public.mood_entries for select
  to authenticated
  using (public.is_active_caretaker_of(user_id));

-- ============================================================
-- 3. Publication: add each table to supabase_realtime so
--    onPostgresChanges fires. Idempotent — checks pg_publication_tables
--    first. The existing caretaker_link_broadcast trigger in 28_*.sql
--    already added `caretaker_patient_links`; we don't touch that.
-- ============================================================
do $$
begin
  if not exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) then
    -- Realtime is not enabled on this project at all. Skip silently —
    -- the user must enable it in Dashboard → Realtime → Settings.
    -- Without the publication, the policies above still work for
    -- direct SELECT calls; realtime updates simply won't fire until
    -- Realtime is turned on.
    raise notice 'supabase_realtime publication does not exist. Enable Realtime in Supabase Dashboard to receive live updates.';
    return;
  end if;

  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'meal_intake_log') then
    alter publication supabase_realtime add table public.meal_intake_log;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'medicine_doses') then
    alter publication supabase_realtime add table public.medicine_doses;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'water_intake_log') then
    alter publication supabase_realtime add table public.water_intake_log;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'daily_metrics') then
    alter publication supabase_realtime add table public.daily_metrics;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'workout_sessions') then
    alter publication supabase_realtime add table public.workout_sessions;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'workout_session_items') then
    alter publication supabase_realtime add table public.workout_session_items;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'mood_entries') then
    alter publication supabase_realtime add table public.mood_entries;
  end if;
end $$;
