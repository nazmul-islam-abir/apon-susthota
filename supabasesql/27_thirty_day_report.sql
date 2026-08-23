-- ============================================================================
-- 27_thirty_day_report.sql
-- ------------------------------------------------------------
-- Single source of truth for the 30-day patient cycle.
--
-- Day 1 anchor:  auth.users.created_at::date   (signup day, in user's local TZ)
-- Today anchor:  current_date
-- Window:        [anchor, anchor + 29 days]  (always 30 days, including future
--               days where the user is still inside the cycle).  Days with no
--               logged activity return zeros — the cycle is the contract, the
--               data inside it is what the user actually did.
--
-- Real source tables used (verified against the deployed schema):
--   meal_intake_log           — date=meal_date, slot=meal_slot, has food_id,
--                               food_name_bn, status, impact, notes, created_at.
--                               NO eaten_at / kcal_consumed / is_offplan /
--                               quantity_g. Macros are pulled from `foods`.
--   foods                     — carb_g, protein_g, fat_g, sodium_mg (and
--                               fiber_g, potassium_mg, phosphorus_mg) per
--                               100 g. NO kcal_per_100g column — kcal is
--                               derived in this function via 4-4-9 rule.
--                               NO English name column (only name_bn).
--   water_intake_log          — occurred_at timestamptz, liters numeric.
--                               NO logged_at / amount_ml.
--   medicine_doses            — dose_date date, scheduled_time time, status,
--                               taken_at timestamptz. NO scheduled_for /
--                               dosage_label. dose label is built from
--                               medicines (strength + dose_amount + dose_unit).
--   workout_sessions          — session_date, started_at, finished_at,
--                               total_duration_seconds, completed_items,
--                               total_items, is_finished. NO `status`
--                               column — completion is derived from
--                               is_finished + aggregates.
--                               workout_completions table does NOT exist.
--   user_meal_plan_recommendations — plan_date, slot, food_id, quantity_g.
--                               daily_meal_plan table does NOT exist.
--
-- Returns ONE row of JSON shaped like:
-- {
--   "cycle_start":   "2025-04-12",
--   "today":         "2025-05-03",
--   "day_of_cycle":  22,
--   "cycle_complete": false,
--   "totals":        { "days_logged": ..., "planned_meals_total": ..., ... },
--   "days": [
--     {
--       "date":          "2025-04-12",
--       "day_of_cycle":  1,
--       "is_today":      false,
--       "is_future":     false,
--       "planned_meals": 4,
--       "logged_meals":  { "good": 3, "moderate": 1, "bad": 0, "offplan": 0 },
--       "macros":        { "kcal": 1620, "carb_g": 198, "protein_g": 62, "fat_g": 38, "sodium_mg": 1980 },
--       "water_ml":      1800,
--       "medicine":      { "scheduled": 2, "taken": 2, "missed": 0 },
--       "workouts":      { "completed": 1, "partial": 0, "minutes": 18, "skipped": false },
--       "adherence_pct": 87
--     },
--     ... 30 rows
--   ]
-- }
--
-- Known assumption:
--   meal_intake_log has no `quantity_g` column, so per-meal macros assume a
--   100 g serving. Kcal is derived from foods.carb_g/protein_g/fat_g via
--   the 4-4-9 rule (foods has no kcal_per_100g column). When quantity_g is
--   added to meal_intake_log, multiply each macro and the derived kcal by
--   (qty / 100) to scale.
--
-- Idempotent. Run AFTER 26_meal_details.sql (which references the same source
-- tables).
-- ============================================================================

create or replace function public.get_thirty_day_report()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_user_id    uuid := auth.uid();
  v_created_at timestamptz;
  v_start_date date;
  v_today      date := current_date;
  v_doc_int    int;
  v_payload    jsonb;
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

  v_start_date := (v_created_at at time zone 'Asia/Dhaka')::date;
  -- Compute day-of-cycle as an integer so we never rely on the implicit
  -- integer -> date cast, which Postgres raises as
  -- "22007 invalid input syntax for type date: \"<n>\"" in some versions
  -- when the prepared statement path goes through PostgREST.
  v_doc_int    := greatest(1, least(30, (v_today - v_start_date) + 1));

  -- Build a per-day JSON payload using generate_series so we always have 30
  -- rows, even days the user is yet to live through or skipped.
  with days as (
    select (v_start_date + g)::date as d,
           (g + 1)::int             as day_of_cycle,
           ((v_start_date + g)::date = v_today)               as is_today,
           ((v_start_date + g)::date >  v_today)              as is_future
      from generate_series(0, 29) g
  ),
  plan as (
    -- user_meal_plan_recommendations is the canonical "what was planned"
    -- source for the user on a given day.  We aggregate food_ids into an
    -- array so the meals CTE can flag off-plan rows by comparison.
    select upr.plan_date                          as d,
           count(*)::int                          as planned,
           array_agg(upr.food_id)                 as food_ids
      from public.user_meal_plan_recommendations upr
     where upr.user_id = v_user_id
       and upr.plan_date between v_start_date and v_start_date + 29
     group by upr.plan_date
  ),
  meals as (
    -- meal_intake_log has no eaten_at / no macros / no is_offplan column.
    --   1. bucket by meal_date (date column) directly,
    --   2. JOIN foods on food_id to get per-100g macros (assumes 100 g
    --      serving per intake row, since meal_intake_log has no quantity_g),
    --   3. derive off-plan by comparing food_id against the day's planned
    --      food_ids array from `plan`.
    select m.meal_date                                            as d,
           count(*)                                               as total,
           sum(case when m.impact = 'good'     then 1 else 0 end) as good_n,
           sum(case when m.impact = 'moderate' then 1 else 0 end) as mod_n,
           sum(case when m.impact = 'bad'      then 1 else 0 end) as bad_n,
           sum(case when pf.food_ids is not null
                         and not (m.food_id = any(pf.food_ids))
                    then 1 else 0 end)                            as off_n,
           -- kcal is derived client-side via the 4-4-9 rule because the
           -- foods table stores only the three raw macros (no kcal_per_100g).
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
    -- water_intake_log: occurred_at is the timestamp, liters is the amount.
    -- Sum liters across the day, multiply by 1000 to produce millilitres.
    select (occurred_at at time zone 'Asia/Dhaka')::date  as d,
           coalesce(sum(liters), 0)::numeric * 1000       as ml
      from public.water_intake_log
     where user_id = v_user_id
       and (occurred_at at time zone 'Asia/Dhaka')::date
             between v_start_date and v_start_date + 29
     group by 1
  ),
  meds as (
    -- medicine_doses.date column is dose_date (date); scheduled_time is
    -- `time without time zone`, so bucketing by dose_date is correct.
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
    -- workout_completions does not exist; workout_sessions is the source.
    -- workout_sessions has NO `status` column — instead it carries:
    --   is_finished boolean   — did the user mark the day complete?
    --   total_duration_seconds int — aggregate seconds across all items
    --   completed_items / total_items — completion ratio for the day
    -- "done_n"  = sessions where is_finished = true
    -- "part_n"  = sessions where the user started but did NOT finish
    --             (started_at set + is_finished = false)
    -- "minutes" = sum(total_duration_seconds) / 60 across all sessions
    --             on that date (counted whether finished or partial)
    -- "skipped" = true if a session row exists for that date with NO
    --             completed items AND total_duration_seconds = 0
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
             'bad',      coalesce(meals.bad_n,  0)::int,
             'offplan',  coalesce(meals.off_n,  0)::int
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
           -- 0..100 adherence score combining meal + med + workout + water
           round(
             (
               -- meals: proportion of planned meals logged (good or moderate ok)
               100.0 * case when coalesce(plan.planned, 0) = 0
                              then case when meals.total > 0 then 1.0 else 0.5 end
                              else least(meals.total::numeric / plan.planned, 1.0)
                         end
               -- meds
             + case when coalesce(meds.scheduled, 0) = 0 then 1.0
                    else coalesce(meds.taken, 0)::numeric / meds.scheduled end
               -- workouts (1 if any workout done or partially done)
             + case when workouts.done_n is null and workouts.part_n is null
                         and coalesce(plan.planned, 0) = 0 then 1.0
                    when coalesce(workouts.done_n, 0)
                       + coalesce(workouts.part_n, 0) > 0 then 1.0
                    when d.is_future then 1.0
                    else 0.0 end
               -- water: 1500 ml target
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
           'cycle_start',   to_char(v_start_date, 'YYYY-MM-DD'),
           'today',         to_char(v_today,      'YYYY-MM-DD'),
           'day_of_cycle',  v_doc_int,
           'cycle_complete', (v_today >= v_start_date + 29),
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

-- Owners can call their own RPC.
revoke all on function public.get_thirty_day_report() from public;
grant execute on function public.get_thirty_day_report() to authenticated;

comment on function public.get_thirty_day_report()
  is 'Single 30-day cycle report anchored on auth.users.created_at (Asia/Dhaka TZ). Returns 30 rows (one per day of the cycle, including future days) plus totals. Uses real schema: meal_intake_log.meal_date + foods join for macros, water_intake_log.occurred_at + liters*1000, medicine_doses.dose_date + scheduled_time, workout_sessions, user_meal_plan_recommendations.';
