-- ============================================================================
-- 27_daily_detail.sql
-- ------------------------------------------------------------
-- Per-day drill-down used by the Doctor Report screen to expand a single day
-- into the underlying transactions (meals / meds / workouts / water). Loaded
-- lazily only when the user opens a day in the report screen.
--
-- p_date defaults to today (''YYYY-MM-DD'') and also accepts a day-of-cycle
-- integer (1..30) anchored on auth.users.created_at. p_user_id defaults to auth.uid().
--
-- Real source tables used (verified against the deployed schema):
--   meal_intake_log           — date=meal_date, time-of-day=created_at,
--                               has food_id, food_name_bn, impact, notes.
--                               Macros JOINed from `foods`. NO eaten_at /
--                               kcal_consumed / is_offplan column.
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
--                               column. Per-exercise rows live in
--                               workout_session_items (workout_id +
--                               duration_seconds + is_completed).
--                               workout_completions table does NOT exist.
--
-- Returns:
-- {
--   "date":           "2025-04-15",
--   "is_today":       false,
--   "is_future":      false,
--   "meals_summary":  { "good_n": 3, "mod_n": 1, "bad_n": 0, "off_n": 0, "logged": 4 },
--   "macros":         { "kcal": ..., "carb_g": ..., "protein_g": ..., "fat_g": ..., "sodium_mg": ... },
--   "meals":          [ {time, slot, name_bn, name_en, impact, kcal, carb_g, protein_g, fat_g, sodium_mg, offplan, note}, ... ],
--   "meds":           [ {name, dose, scheduled_at, taken_at, status}, ... ],
--   "water_logs":     [ {time, ml}, ... ],
--   "workouts":       [ {name, duration_min, status, started_at, finished_at}, ... ]
-- }
--
-- Known assumption: meal_intake_log has no quantity_g, so per-meal macros
-- and the day-aggregate use foods.carb_g/protein_g/fat_g as 100 g values
-- (kcal is derived in-SQL via 4-4-9 because foods has no kcal_per_100g).
-- When a quantity_g column is added, scale by (qty/100) inside the JOIN.
-- ============================================================================

create or replace function public.get_day_full_report(
  p_date    text    default to_char(current_date, 'YYYY-MM-DD'),
  p_user_id uuid    default auth.uid()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_user_id  uuid := coalesce(p_user_id, auth.uid());
  v_today    date := current_date;
  v_date     date;
  v_payload  jsonb;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  if p_date is null or btrim(p_date) = '' then
    raise exception 'p_date is required (YYYY-MM-DD)';
  end if;

  -- Accept either 'YYYY-MM-DD' or a numeric day-of-cycle (1..30) and resolve
  -- it against the user's 30-day cycle anchored on auth.users.created_at.
  -- This makes the RPC robust against clients that accidentally pass the
  -- day index as an integer instead of the calendar date string.
  if p_date ~ '^[0-9]+$' then
    declare
      v_created timestamptz;
      v_start   date;
    begin
      select u.created_at into v_created from auth.users u where u.id = v_user_id;
      if v_created is null then
        raise exception 'auth.users.created_at not found for current user';
      end if;
      v_start := (v_created at time zone 'Asia/Dhaka')::date;
      v_date  := v_start + (greatest(1, least(30, p_date::int)) - 1);
    end;
  else
    begin
      v_date := p_date::date;
    exception when invalid_datetime_format then
      raise exception 'p_date must be YYYY-MM-DD or a day-of-cycle integer; got: %', p_date;
    end;
  end if;

  with plan_ids as (
    -- Off-plan detection: collect food_ids that were *planned* for v_date so
    -- we can flag a meal as off-plan when its food_id isn't in this list.
    select array_agg(upr.food_id) as food_ids
      from public.user_meal_plan_recommendations upr
     where upr.user_id = v_user_id
       and upr.plan_date = v_date
  ),
  meal_rows as (
    -- meal_intake_log has no eaten_at / no per-row macros / no is_offplan.
    -- Time-of-day comes from created_at (timestamptz). Macros are pulled from
    -- `foods` via food_id JOIN (assumes 100 g serving). Off-plan is derived
    -- by comparing m.food_id against plan_ids.food_ids.
    select jsonb_build_object(
             'time',      to_char(m.created_at at time zone 'Asia/Dhaka', 'HH24:MI'),
             'slot',      coalesce(m.meal_slot, ''),
             'name_bn',   coalesce(m.food_name_bn, ''),
             -- foods has no English name column; surfaces empty string.
             'name_en',   '',
             'impact',    coalesce(m.impact, ''),
             -- Derive kcal from the three macros via 4-4-9; foods has no
             -- kcal_per_100g column. Assumes 100 g serving since
             -- meal_intake_log has no quantity_g.
             'kcal',      coalesce(round((coalesce(f.carb_g, 0) * 4
                                       + coalesce(f.protein_g, 0) * 4
                                       + coalesce(f.fat_g,    0) * 9))::int, 0),
             'carb_g',    coalesce(f.carb_g,       0)::int,
             'protein_g', coalesce(f.protein_g,    0)::int,
             'fat_g',     coalesce(f.fat_g,        0)::int,
             'sodium_mg', coalesce(f.sodium_mg,    0)::int,
             'offplan',   case when pi.food_ids is not null
                                  and not (m.food_id = any(pi.food_ids))
                               then true else false end,
             'note',      coalesce(m.notes, '')
           ) as j
      from public.meal_intake_log m
      left join public.foods f on f.id = m.food_id
      cross join plan_ids pi
     where m.user_id = v_user_id
       and m.meal_date = v_date
     order by m.created_at
  ),
  med_rows as (
    -- medicine_doses has scheduled_time (time only — no date), taken_at
    -- (timestamptz). There is no scheduled_for column and no dosage_label
    -- column; we build the dose label from medicines (strength + dose_amount
    -- + dose_unit) using concat_ws so NULL parts collapse cleanly.
    select jsonb_build_object(
             'name',          coalesce(m.name_bn, m.name_en, ''),
             'dose',          concat_ws(' ',
                                nullif(coalesce(m.strength, ''), ''),
                                nullif(coalesce(m.dose_amount::text, ''), ''),
                                nullif(coalesce(m.dose_unit, ''), '')),
             'scheduled_at',  to_char(d.scheduled_time, 'HH24:MI'),
             'taken_at',      case when d.taken_at is not null
                                   then to_char(d.taken_at at time zone 'Asia/Dhaka', 'HH24:MI')
                                   else null
                              end,
             'status',        d.status
           ) as j
      from public.medicine_doses d
      left join public.medicines m on m.id = d.medicine_id
     where d.user_id = v_user_id
       and d.dose_date = v_date
     order by d.scheduled_time
  ),
  water_rows as (
    -- water_intake_log: occurred_at is the timestamp, liters is the amount.
    -- Surface ml = round(liters * 1000) to keep the JSON integer-typed as
    -- the Dart model expects `(j['ml'] as int)`.
    select jsonb_build_object(
             'time', to_char(occurred_at at time zone 'Asia/Dhaka', 'HH24:MI'),
             'ml',   round(coalesce(liters, 0) * 1000)::int
           ) as j
      from public.water_intake_log
     where user_id = v_user_id
       and (occurred_at at time zone 'Asia/Dhaka')::date = v_date
     order by occurred_at
  ),
  workout_rows as (
    -- workout_sessions has NO `status` column and NO `workout_id` /
    -- `duration_seconds` / `start_at` / `end_at` columns. The real shape is:
    --   workout_sessions:         session_date, started_at, finished_at,
    --                             total_duration_seconds, completed_items,
    --                             total_items, is_finished
    --   workout_session_items:    session_id → workout_id, is_completed,
    --                             duration_seconds, started_at, finished_at
    -- So the per-exercise row must come from workout_session_items joined
    -- to workouts for the name, with `status` derived locally.
    select jsonb_build_object(
             'name',         coalesce(w.name_bn, w.name_en, ''),
             'duration_min', coalesce(i.duration_seconds / 60, 0)::int,
             'status',       case
                               when i.is_completed                    then 'completed'
                               when i.started_at is not null
                                    and i.finished_at is null         then 'in_progress'
                               else 'planned'
                             end,
             'started_at',   case when i.started_at is not null
                                  then to_char(i.started_at at time zone 'Asia/Dhaka', 'HH24:MI')
                                  else null end,
             'finished_at',  case when i.finished_at is not null
                                  then to_char(i.finished_at at time zone 'Asia/Dhaka', 'HH24:MI')
                                  else null end
           ) as j
      from public.workout_sessions c
      left join public.workout_session_items i on i.session_id = c.id
      left join public.workouts w              on w.id        = i.workout_id
     where c.user_id = v_user_id
       and c.session_date = v_date
     order by c.started_at, i.position
  ),
  macros as (
    -- Per-day macros: JOIN meals to foods for per-100g values. meal_intake_log
    -- itself has no macro columns. Sum across the day with 100 g serving
    -- assumption (no quantity_g on the log table).
    select jsonb_build_object(
             -- Derive kcal via 4-4-9 from carb/protein/fat (foods has no kcal_per_100g).
             'kcal',     coalesce(sum(round((coalesce(f.carb_g, 0) * 4
                                          + coalesce(f.protein_g, 0) * 4
                                          + coalesce(f.fat_g,    0) * 9))::int), 0)::int,
             'carb_g',   coalesce(sum(coalesce(f.carb_g,      0)), 0)::int,
             'protein_g',coalesce(sum(coalesce(f.protein_g,   0)), 0)::int,
             'fat_g',    coalesce(sum(coalesce(f.fat_g,       0)), 0)::int,
             'sodium_mg',coalesce(sum(coalesce(f.sodium_mg,   0)), 0)::int
           ) as j
      from public.meal_intake_log m
      left join public.foods f on f.id = m.food_id
     where m.user_id = v_user_id
       and m.meal_date = v_date
  ),
  summary as (
    -- Impact totals plus off-plan count derived against the planned
    -- food_ids for the day.
    select
      coalesce(sum(case when m.impact = 'good'     then 1 else 0 end), 0)::int as good_n,
      coalesce(sum(case when m.impact = 'moderate' then 1 else 0 end), 0)::int as mod_n,
      coalesce(sum(case when m.impact = 'bad'      then 1 else 0 end), 0)::int as bad_n,
      coalesce(sum(
        case when pi.food_ids is not null
                  and not (m.food_id = any(pi.food_ids))
             then 1 else 0 end
      ), 0)::int                                                                as off_n,
      count(*)::int as logged
      from public.meal_intake_log m
      cross join plan_ids pi
     where m.user_id = v_user_id
       and m.meal_date = v_date
  )
  select jsonb_build_object(
          'date',     to_char(v_date, 'YYYY-MM-DD'),
          'is_today', (v_date = v_today),
          'is_future',(v_date >  v_today),
          'meals_summary', (select row_to_json(s) from summary s),
          'macros',   (select j from macros),
          'meals',      coalesce((select jsonb_agg(j order by j->>'time') from meal_rows),    '[]'::jsonb),
          'meds',       coalesce((select jsonb_agg(j order by j->>'scheduled_at') from med_rows),  '[]'::jsonb),
          'water_logs', coalesce((select jsonb_agg(j order by j->>'time') from water_rows),  '[]'::jsonb),
          'workouts',   coalesce((select jsonb_agg(j order by j->>'started_at') from workout_rows), '[]'::jsonb)
        )
   into v_payload;

  return v_payload;
end;
$$;

comment on function public.get_day_full_report(p_date text, p_user_id uuid)
  is 'Per-day drill-down for the Doctor Report screen — meals, meds, water, and workouts (with names), plus per-day macros in one round trip. p_date accepts either ''YYYY-MM-DD'' or a day-of-cycle integer (1..30) anchored on auth.users.created_at (Asia/Dhaka TZ). Uses real schema: meal_intake_log.meal_date + foods join for macros, water_intake_log.occurred_at + liters*1000, medicine_doses.scheduled_time + concat dose label, workout_sessions.';
