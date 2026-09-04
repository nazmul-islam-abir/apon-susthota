-- ============================================================
-- 55 — Caretaker full visibility (RLS + realtime publication)
-- ============================================================
--
-- Purpose
-- -------
-- The caretaker app uses `onPostgresChanges` (via
-- `PatientDataRealtimeMixin`) and the read-only RPCs in
-- `caretaker_data_service.dart` to mirror every screen the patient
-- sees. For both of those paths to work, the caretaker session
-- must be allowed to SELECT the patient's rows in the relevant
-- data tables. The existing 01..54 migrations only grant
-- `auth.uid() = user_id` SELECT access — which excludes the
-- caretaker by design.
--
-- This migration adds a SECOND SELECT policy per data table:
-- "a row is visible to the signed-in user IF that user is an
-- active caretaker of the row's patient". We reuse the
-- `is_active_caretaker_of(p_patient)` helper from migration 54.
--
-- Then we add every patient-facing table to the
-- `supabase_realtime` publication so `onPostgresChanges` actually
-- fires when the patient writes a row.
--
-- What this fixes
-- ---------------
-- 1) Caretaker analytics / today / charts / medicine / meal plan
--    / water / workout / full-patient viewers stop showing
--    "stale" data — `onPostgresChanges` was silently doing
--    nothing because the SELECT RLS blocked the realtime query
--    server-side.
-- 2) Caretaker inbox / activity feed updates live as the patient
--    logs meals, water doses, medicines, workouts, and mood
--    entries.
-- 3) Caretaker sees the patient's recommendations (what's
--    planned for the day / 30-day plan) and assignments
--    (which workouts are scheduled today).
--
-- Order
-- -----
-- Idempotent. Safe to run on top of 54_*. Run this AFTER:
--   * 28_roles_and_caretaker.sql   (defines caretaker_patient_links)
--   * 54_caretaker_realtime_subscription.sql
--       (defines is_active_caretaker_of; if you haven't run 54
--        yet, this file recreates the helper itself)
--
-- It does NOT depend on the trigger in 53_caretaker_patient_data_realtime.sql
-- (which uses realtime.send — that's a Realtime ≥ 2.0 feature
-- only). All the live updates go through `onPostgresChanges`,
-- which works on every Supabase Realtime version.


-- ============================================================
-- 1. Helper: returns true when the caller is an active caretaker
--    of the given patient. Recreated here as a no-op if 54_*
--    was already applied (CREATE OR REPLACE FUNCTION).
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
-- 2. Patient-write data tables — add caretaker SELECT policies.
--    The patient-own policy stays untouched. Multiple permissive
--    SELECT policies are OR'd by Postgres.
-- ============================================================

-- 2.1 meal_intake_log -------------------------------------------------
drop policy if exists "Caregiver may view linked patient's meal log"
  on public.meal_intake_log;
create policy "Caregiver may view linked patient's meal log"
  on public.meal_intake_log for select
  to authenticated
  using (public.is_active_caretaker_of(user_id));

-- 2.2 medicine_doses --------------------------------------------------
drop policy if exists "Caregiver may view linked patient's medicine doses"
  on public.medicine_doses;
create policy "Caregiver may view linked patient's medicine doses"
  on public.medicine_doses for select
  to authenticated
  using (public.is_active_caretaker_of(user_id));

-- 2.3 water_intake_log ------------------------------------------------
drop policy if exists "Caregiver may view linked patient's water log"
  on public.water_intake_log;
create policy "Caregiver may view linked patient's water log"
  on public.water_intake_log for select
  to authenticated
  using (public.is_active_caretaker_of(user_id));

-- 2.4 daily_metrics ---------------------------------------------------
drop policy if exists "Caregiver may view linked patient's daily metrics"
  on public.daily_metrics;
create policy "Caregiver may view linked patient's daily metrics"
  on public.daily_metrics for select
  to authenticated
  using (public.is_active_caretaker_of(user_id));

-- 2.5 daily_water_summary ---------------------------------------------
drop policy if exists "Caregiver may view linked patient's water summary"
  on public.daily_water_summary;
create policy "Caregiver may view linked patient's water summary"
  on public.daily_water_summary for select
  to authenticated
  using (public.is_active_caretaker_of(user_id));

-- 2.6 workout_sessions ------------------------------------------------
drop policy if exists "Caregiver may view linked patient's workout sessions"
  on public.workout_sessions;
create policy "Caregiver may view linked patient's workout sessions"
  on public.workout_sessions for select
  to authenticated
  using (public.is_active_caretaker_of(user_id));

-- 2.7 workout_session_items — joined via parent session's user_id -----
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

-- 2.8 mood_entries ----------------------------------------------------
drop policy if exists "Caregiver may view linked patient's mood"
  on public.mood_entries;
create policy "Caregiver may view linked patient's mood"
  on public.mood_entries for select
  to authenticated
  using (public.is_active_caretaker_of(user_id));


-- ============================================================
-- 3. Recommendation / assignment tables — caretaker can also see
--    "what's planned for the patient" so they understand what
--    the patient is doing today vs. what's left.
-- ============================================================

-- 3.1 user_meal_plans (custom added meals) ---------------------------
drop policy if exists "Caregiver may view linked patient's custom meal plan"
  on public.user_meal_plans;
create policy "Caregiver may view linked patient's custom meal plan"
  on public.user_meal_plans for select
  to authenticated
  using (public.is_active_caretaker_of(user_id));

-- 3.2 user_meal_plan_recommendations (AI-generated slot/food list) ---
drop policy if exists "Caregiver may view linked patient's meal recommendations"
  on public.user_meal_plan_recommendations;
create policy "Caregiver may view linked patient's meal recommendations"
  on public.user_meal_plan_recommendations for select
  to authenticated
  using (public.is_active_caretaker_of(user_id));

-- 3.3 meal_plan_days (master 30-day rotation template) ---------------
-- meal_plan_days is a STATIC, GLOBAL template (one row per day
-- 1-30, shared by all patients — see 01_schema.sql line ~97: the
-- primary key is just `day` and the table has NO user_id column).
-- The existing migration already grants `select to authenticated
-- using (true)` for this table, which is enough — every
-- authenticated user (including the caretaker) can already read
-- it. We do NOT add a caretaker policy here, because referencing
-- user_id raises "column user_id does not exist" on this table.

-- 3.4 workout_assignments (today's planned exercises) ---------------
drop policy if exists "Caregiver may view linked patient's workout plan"
  on public.workout_assignments;
create policy "Caregiver may view linked patient's workout plan"
  on public.workout_assignments for select
  to authenticated
  using (public.is_active_caretaker_of(user_id));

-- 3.5 medicines (active prescription list) --------------------------
drop policy if exists "Caregiver may view linked patient's medicines"
  on public.medicines;
create policy "Caregiver may view linked patient's medicines"
  on public.medicines for select
  to authenticated
  using (public.is_active_caretaker_of(user_id));


-- ============================================================
-- 4. Add every patient-write / recommendation table to the
--    `supabase_realtime` publication so onPostgresChanges fires.
--    Idempotent — checks pg_publication_tables first.
--    Skips silently if the publication doesn't exist (older
--    projects without Realtime).
-- ============================================================
do $$
declare
  v_has_pub boolean;
begin
  select exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) into v_has_pub;

  if not v_has_pub then
    raise notice 'supabase_realtime publication does not exist. '
                  'Enable Realtime in Supabase Dashboard → Realtime → '
                  'Settings → "Enable Realtime service" and re-run this file.';
    return;
  end if;

  -- Patient-write tables
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

  -- Recommendation / assignment tables
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'user_meal_plans') then
    alter publication supabase_realtime add table public.user_meal_plans;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'user_meal_plan_recommendations') then
    alter publication supabase_realtime add table public.user_meal_plan_recommendations;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'workout_assignments') then
    alter publication supabase_realtime add table public.workout_assignments;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'medicines') then
    alter publication supabase_realtime add table public.medicines;
  end if;
end $$;


-- ============================================================
-- 5. Sanity / verification queries (run after this file succeeds)
-- ============================================================
-- Expected output of each query is shown in the comment.
--
-- 5.1) All caretaker-side SELECT policies were created:
--
--   select schemaname, tablename, policyname, cmd
--     from pg_policies
--    where policyname like 'Caregiver may view%'
--    order by tablename, policyname;
--
-- Expected: 12 rows (meal_plan_days is intentionally excluded
-- because it's a global, static template already readable by every
-- authenticated user via the original 01_schema.sql policy).
--
-- 5.2) All tables were added to the publication:
--
--   select schemaname, tablename
--     from pg_publication_tables
--    where pubname = 'supabase_realtime'
--      and tablename in (
--        'meal_intake_log','medicine_doses','water_intake_log',
--        'daily_metrics','workout_sessions','workout_session_items',
--        'mood_entries','user_meal_plans','user_meal_plan_recommendations',
--        'workout_assignments','medicines'
--      )
--    order by tablename;
--
-- Expected: 11 rows.
--
-- 5.3) Realtime is on (Dashboard → Realtime → Settings):
--       "Enable Realtime service" toggled ON (you already have this
--       per your screenshot).
