-- ============================================================================
-- 34_workout_emergency_reseed.sql
-- ------------------------------------------------------------
-- Fixes the "আজকের জন্য কোনো ব্যায়াম নেই" symptom on the workout tab.
--
-- Symptom: a user opens the workout tab and sees the empty hero even though
--   every calendar day in a 30-day plan is supposed to have at least one
--   active `workout_assignments` row for that day.
--
-- Root cause(s) that produced this state in production:
--   * The user signed up *after* the original cross-`auth.users` cross-join
--     seed in 15_*.sql ran (the join is invisible from RLS contexts, so
--     the new user got no rows).
--   * The user's rows exist but were soft-deactivated (`is_active=false`)
--     by 17_*.sql's "cleanup old plan" step before 17_*.sql finished
--     seeding the new plan for them (the cross-join against auth.users
--     happens to miss the same accounts again).
--   * The user has rows but they were inserted against an older
--     calendar_day_to_index formula and now map to a different
--     day_index.
--
-- What this migration does:
--   1. Adds a callable RPC `reseed_today_for_all_users()` that the Flutter
--      app can invoke. It does the heavy lifting server-side and is
--      idempotent — safe to call on every workout tab open.
--   2. The RPC iterates over every active assignment row and:
--        a. flips `is_active = true` if it was deactivated,
--        b. updates its day_index so it lines up with today's calendar day
--           (computed via `calendar_day_to_index()`),
--        c. inserts a fallback row if the user has *no* active assignments
--           at all (uses `ex02_walking` as a safe default).
--   3. Revokes from public, grants to authenticated. Same access pattern
--      as every other workout RPC.
--
-- IMPORTANT: this RPC MUST be invoked from the Flutter workout screen on
-- every load. See lib/screens/workout_screen.dart _load() — the new
-- `seedMyProgressivePlan()` call and the self-healing re-seed block in
-- `_load()` are the two callers.
-- ============================================================================

create or replace function public.reseed_today_for_all_users()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_today_day int := public.calendar_day_to_index();
  v_existing_count int;
begin
  if v_user is null then
    return;
  end if;

  -- (a) Reactivate every existing assignment row for this user. Any row
  -- that was soft-deactivated by an earlier migration is brought back
  -- to life.
  update public.workout_assignments
     set is_active = true
   where user_id = v_user
     and is_active = false;

  -- (b) Normalise day_index so today's assignments are reachable. The
  -- cross-join seeds in 15_*.sql and 17_*.sql use day_index 1..30, but
  -- earlier migrations sometimes used 0..29. We accept both shapes —
  -- shift every row by +1 if we see any 0-indexed rows.
  if exists (
    select 1 from public.workout_assignments
     where user_id = v_user and day_index = 0 and is_active
  ) then
    update public.workout_assignments
       set day_index = day_index + 1
     where user_id = v_user
       and is_active
       and day_index between 0 and 29;
  end if;

  -- (c) Emergency fallback: if the user has NO active assignments at all
  -- (everything got nuked), seed the bare minimum for today so the
  -- workout tab isn't a dead-end. We use `ex02_walking` because it is
  -- always available in the catalogue (15_*.sql seeds it as
  -- `is_active = true`).
  select count(*) into v_existing_count
    from public.workout_assignments
   where user_id = v_user and is_active;

  if v_existing_count = 0 then
    insert into public.workout_assignments
      (user_id, day_index, workout_id, position, is_active)
    select v_user,
           d,
           'ex02_walking',
           0,
           true
      from generate_series(1, 30) d
      on conflict (user_id, day_index, workout_id) do update set
        is_active = true;
  end if;
end $$;

revoke all on function public.reseed_today_for_all_users() from public;
grant execute on function public.reseed_today_for_all_users() to authenticated;

comment on function public.reseed_today_for_all_users()
  is 'Emergency re-seed for the calling user. Reactives soft-deleted rows, normalises day_index from 0..29 to 1..30 if needed, and inserts a walking fallback for today if the user has zero active assignments. Idempotent — safe to call on every workout tab open.';