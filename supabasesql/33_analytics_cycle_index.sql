-- ============================================================================
-- 33_analytics_cycle_index.sql
-- ------------------------------------------------------------
-- Extends `public.get_thirty_day_report` so the analytics screen can paginate
-- across the user's full history of 30-day cycles.
--
-- Before: the function always returned the SINGLE 30-day window anchored on
-- `auth.users.created_at::date`. A user who signed up months ago saw the same
-- 30-day window over and over — they could never inspect any earlier cycle.
--
-- This migration:
--   1. Adds an optional `p_cycle_index` parameter (default 0):
--        p_cycle_index = 0 → current cycle (the one today falls inside)
--        p_cycle_index = 1 → the previous cycle (the 30 days BEFORE current)
--        p_cycle_index = 2 → two cycles ago, etc.
--   2. `cycle_index` and `cycle_start_offset_days` are added to the JSON
--      payload so the client knows which cycle it is rendering (and can
--      build a "cycle 1 of N" tab strip).
--   3. `is_future` is now defined relative to the cycle window — i.e. a
--      day in cycle_index=1 is "future" only if that calendar day hasn't
--      elapsed. That means the previous cycle never has any `is_future=true`
--      rows, so the client no longer needs to filter them.
--   4. `cycle_complete` and `day_of_cycle` are computed against the cycle
--      window (`cycle_index_to_start_offset`) rather than the signup date
--      anchor — for previous cycles they resolve to day 30 / complete=true
--      regardless of `current_date`.
--
-- Backward compatible: callers that don't pass `p_cycle_index` still see the
-- exact same shape they saw before — `cycle_index` is added (clients that
-- ignore extra JSON keys are unaffected).
-- ============================================================================

drop function if exists public.get_thirty_day_report();
create or replace function public.get_thirty_day_report(
  p_cycle_index int default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_user_id     uuid := auth.uid();
  v_created_at  timestamptz;
  v_start_date  date;          -- first day of the requested cycle
  v_today       date := current_date;
  v_doc_int     int;
  v_payload     jsonb;
  v_cycle_index int := greatest(0, coalesce(p_cycle_index, 0));
  v_cycle_start_offset int := v_cycle_index * 30;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select u.created_at
    into v_created_at
    from auth.users u
   where u.id = v_user_id;

  if v_created_at is null then
    raise exception 'auth.users.created_at not found for current user';
  end if;

  v_start_date := ((v_created_at at time zone 'Asia/Dhaka')::date
                   + v_cycle_start_offset);

  -- Compute day-of-cycle against the cycle start (NOT signup date). For
  -- previous cycles (index >= 1) day_of_cycle always resolves to the
  -- (v_today - v_start_date + 1) clamped to 1..30 — past cycles naturally
  -- fall through to 30.
  v_doc_int := greatest(1, least(30, (v_today - v_start_date) + 1));

  with days as (
    select (v_start_date + g)::date as d,
           (g + 1)::int             as day_of_cycle,
           ((v_start_date + g)::date = v_today)               as is_today,
           ((v_start_date + g)::date >  v_today)              as is_future
      from generate_series(0, 29) g
  ),
  plan as (
    select upr.plan_date                          as d,
           count(*)::int                          as planned,
           array_agg(upr.food_id)                 as food_ids
      from public.user_meal_plan_recommendations upr
     where upr.user_id = v_user_id
       and upr.plan_date between v_start_date and v_start_date + 29
     group by upr.plan_date
  ),
  meals as (
    select m.meal_date                                            as d,
           count(*)                                               as total,
           sum(case when m.impact = 'good'     then 1 else 0 end) as good_n,
           sum(case when m.impact = 'moderate' then 1 else 0 end) as mod_n,
           sum(case when m.impact = 'bad'      then 1 else 0 end) as bad_n,
           sum(case when pf.food_ids is not null
                         and not (m.food_id = any(pf.food_ids))
                    then 1 else 0 end)                            as off_n,
           coalesce(sum(round((coalesce(f.carb_g, 0) * 4
                             + coalesce(f.protein_g, 0) * 4
                             + coalesce(f.fat_g,    0) * 9))::int), 0)::int as kcal,
           coalesce(sum(coalesce(f.carb_g, 0)),      0)::int     as carb_g,
           coalesce(sum(coalesce(f.protein_g, 0)),   0)::int     as protein_g,
           coalesce(sum(coalesce(f.fat_g, 0)),       0)::int     as fat_g,
           coalesce(sum(coalesce(f.sodium_mg, 0)),   0)::int     as sodium_mg
      from public.meal_intake_log m
      left join public.foods f on f.id = m.food_id
      left join plan pf        on pf.d  = m.meal_date
     where m.user_id = v_user_id
       and m.meal_date between v_start_date and v_start_date + 29
     group by m.meal_date
  ),
  water as (
    select (occurred_at at time zone 'Asia/Dhaka')::date  as d,
           coalesce(sum(liters), 0)::numeric * 1000       as ml
      from public.water_intake_log
     where user_id = v_user_id
       and (occurred_at at time zone 'Asia/Dhaka')::date
             between v_start_date and v_start_date + 29
     group by 1
  ),
  meds as (
    select dose_date                                       as d,
           count(*)                                        as scheduled,
           sum(case when status = 'taken'  then 1 else 0 end) as taken,
           sum(case when status = 'missed' then 1 else 0 end) as missed
      from public.medicine_doses
     where user_id = v_user_id
       and dose_date between v_start_date and v_start_date + 29
     group by dose_date
  ),
  workouts as (
    select session_date                                            as d,
           sum(case when is_finished                       then 1 else 0 end) as done_n,
           sum(case when is_finished = false
                         and started_at is not null
                         and finished_at is null          then 1 else 0 end) as part_n,
           coalesce(sum(total_duration_seconds / 60.0), 0)::int        as minutes,
           bool_or(is_finished = false
                   and coalesce(total_duration_seconds, 0) = 0
                   and coalesce(completed_items, 0) = 0)              as skipped
      from public.workout_sessions
     where user_id = v_user_id
       and session_date between v_start_date and v_start_date + 29
     group by session_date
  ),
  rolled as (
    select d.day_of_cycle,
           to_char(d.d, 'YYYY-MM-DD')                  as date,
           d.is_today,
           d.is_future,
           coalesce(plan.planned, 0)::int               as planned_meals,
           coalesce(meals.total,  0)::int               as logged_total,
           jsonb_build_object(
             'good',     coalesce(meals.good_n, 0)::int,
             'moderate', coalesce(meals.mod_n,  0)::int,
             'bad',      coalesce(meals.bad_n, 0)::int,
             'offplan',  coalesce(meals.off_n, 0)::int
           )                                            as logged_meals,
           jsonb_build_object(
             'kcal',     coalesce(meals.kcal,      0)::int,
             'carb_g',   coalesce(meals.carb_g,    0)::int,
             'protein_g',coalesce(meals.protein_g, 0)::int,
             'fat_g',    coalesce(meals.fat_g,     0)::int,
             'sodium_mg',coalesce(meals.sodium_mg, 0)::int
           )                                            as macros,
           coalesce(water.ml, 0)::int                   as water_ml,
           jsonb_build_object(
             'scheduled', coalesce(meds.scheduled, 0)::int,
             'taken',     coalesce(meds.taken,     0)::int,
             'missed',    coalesce(meds.missed,    0)::int
           )                                            as medicine,
           jsonb_build_object(
             'completed', coalesce(workouts.done_n,  0)::int,
             'partial',   coalesce(workouts.part_n,  0)::int,
             'minutes',   coalesce(workouts.minutes, 0)::int,
             'skipped',   coalesce(workouts.skipped, false)
           )                                            as workouts,
           round(
             (
               100.0 * case when coalesce(plan.planned, 0) = 0
                              then case when meals.total > 0 then 1.0 else 0.5 end
                              else least(meals.total::numeric / plan.planned, 1.0)
                         end
             + case when coalesce(meds.scheduled, 0) = 0 then 1.0
                    else coalesce(meds.taken, 0)::numeric / meds.scheduled end
             + case when workouts.done_n is null and workouts.part_n is null
                         and coalesce(plan.planned, 0) = 0 then 1.0
                    when coalesce(workouts.done_n, 0)
                       + coalesce(workouts.part_n, 0) > 0 then 1.0
                    when d.is_future then 1.0
                    else 0.0 end
             + least(coalesce(water.ml, 0)::numeric / 1500.0, 1.0)
             ) / 4.0 * 100.0
           , 0)::int                                    as adherence_pct
      from days d
      left join meals    on meals.d    = d.d
      left join water    on water.d    = d.d
      left join meds     on meds.d     = d.d
      left join workouts on workouts.d = d.d
      left join plan     on plan.d     = d.d
  )
  select jsonb_build_object(
           'cycle_index',        v_cycle_index,
           'cycle_start',        to_char(v_start_date, 'YYYY-MM-DD'),
           'today',              to_char(v_today,      'YYYY-MM-DD'),
           'day_of_cycle',       v_doc_int,
           'cycle_complete',     (v_today >= v_start_date + 29),
           'totals', (
             select jsonb_build_object(
               'days_logged',         count(*) filter (where logged_total > 0 or water_ml > 0 or (medicine->>'taken')::int > 0 or (workouts->>'completed')::int > 0),
               'planned_meals_total', sum(planned_meals),
               'logged_meals_total',  sum(logged_total),
               'good_meals',          sum((logged_meals->>'good')::int),
               'moderate_meals',      sum((logged_meals->>'moderate')::int),
               'bad_meals',           sum((logged_meals->>'bad')::int),
               'offplan_meals',       sum((logged_meals->>'offplan')::int),
               'kcal_total',          sum((macros->>'kcal')::int),
               'water_ml_total',      sum(water_ml),
               'med_scheduled_total', sum((medicine->>'scheduled')::int),
               'med_taken_total',     sum((medicine->>'taken')::int),
               'med_missed_total',    sum((medicine->>'missed')::int),
               'workouts_completed',  sum((workouts->>'completed')::int + (workouts->>'partial')::int),
               'workout_minutes_total', sum((workouts->>'minutes')::int),
               'avg_adherence_pct',   coalesce(round(avg(adherence_pct), 0), 0)::int
             )
               from rolled
           ),
           'days', coalesce(jsonb_agg(to_jsonb(rolled) order by day_of_cycle), '[]'::jsonb)
         )
    into v_payload
    from rolled;

  return v_payload;
end;
$$;

revoke all on function public.get_thirty_day_report(int) from public;
grant execute on function public.get_thirty_day_report(int) to authenticated;

comment on function public.get_thirty_day_report(int)
  is '30-day cycle report anchored on auth.users.created_at (Asia/Dhaka TZ). p_cycle_index=0 (default) is the current cycle that contains today; p_cycle_index=1 is the previous 30-day window; p_cycle_index=2 is two cycles back; etc. Adds cycle_index to the JSON payload.';

-- -------- 2. Get the number of completed cycles available for a user --------
-- Used by the analytics screen to render "X cycles উপলব্ধ" and to bound the
-- cycle-picker dropdown. Counts cycles whose END date is on or before today.
create or replace function public.get_analytics_cycle_count()
returns int
language sql
stable
security definer
set search_path = public, auth
as $$
  with u as (
    select u.created_at
      from auth.users u
     where u.id = auth.uid()
  )
  select greatest(0,
    (
      (current_date - ((u.created_at at time zone 'Asia/Dhaka')::date)) / 30
    ) + 1
  )::int
  from u;
$$;

revoke all on function public.get_analytics_cycle_count() from public;
grant execute on function public.get_analytics_cycle_count() to authenticated;

comment on function public.get_analytics_cycle_count()
  is 'Returns how many 30-day cycles of analytics data are available for the current user. 1 means only the current cycle exists (the user is in their first month).';
