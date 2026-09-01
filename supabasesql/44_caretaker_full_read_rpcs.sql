-- ============================================================
-- 44 — Caretaker FULL read RPCs (read-only mirror of patient data)
-- Apply AFTER 29_caretaker_read_rpcs.sql.
--
-- What this file does:
--   Adds the missing caretaker-authorized read RPCs that mirror the
--   patient-only RPCs (which are hard-coded to auth.uid()). Every
--   function here:
--     1. Calls public.assert_caretaker_can_read(p_patient_user_id) first.
--     2. Re-implements the patient query against the supplied
--        patient_user_id instead of auth.uid().
--     3. Returns the same JSON shape the patient-side RPC returns
--        so the Dart models decode without modification.
--
-- Why this exists:
--   The existing caretaker read RPCs in 29_caretaker_read_rpcs.sql
--   cover the high-level Today / week / month / clinical snapshots.
--   They do NOT cover the per-domain RPCs the caretaker viewer
--   screens need:
--     • day_plan, daily_log
--     • today_daily_metrics, water_analytics
--     • list_medicines, get_medicine_doses_for_date
--     • today_workout, workout_logs
--     • meal_adherence / medicine_adherence / workout_adherence
--     • thirty_day_report, analytics_cycle_count
--     • today_mood, mood_history
--     • patient_profile
--   Without these, every viewer screen renders empty because the
--   RPCs raise "function does not exist" and the Dart code falls
--   back to a graceful empty result.
--
-- All functions:
--   * SECURITY DEFINER
--   * search_path = public (or public, auth where the helper needs it)
--   * Granted to authenticated
--   * Authorise via assert_caretaker_can_read(p_patient_user_id)
-- ============================================================


-- ─────────────────────────────────────────────────────────────
-- 1. PROFILE  (PII-stripped, mirrors get_caretaker_clinical_snapshot
--    but with a tighter surface area + the fields the profile
--    viewer renders.)
-- ─────────────────────────────────────────────────────────────
drop function if exists public.get_caretaker_patient_profile(uuid);
create or replace function public.get_caretaker_patient_profile(p_patient_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payload jsonb;
begin
  perform public.assert_caretaker_can_read(p_patient_user_id);

  select jsonb_build_object(
           'user_id',                  p.user_id,
           'full_name',                p.full_name,
           'avatar_url',               p.avatar_url,
           'age',                      p.age,
           'sex',                      p.sex,
           'weight_kg',                p.weight_kg,
           'height_cm',                p.height_cm,
           'bmi',                      p.bmi,
           'on_insulin',               p.on_insulin,
           'medication',               p.medication,
           'has_ckd',                  p.has_ckd,
           'ckd_stage',                p.ckd_stage,
           'has_heart_disease',        p.has_heart_disease,
           'has_anemia',               p.has_anemia,
           'other_conditions',         p.other_conditions,
           'food_preference',          p.food_preference,
           'activity_level',           p.activity_level,
           'meal_size_pref',           p.meal_size_pref,
           'caretaker_relationship',   p.caretaker_relationship,
           -- Latest clinical snapshot values
           'hba1c_percent',            p.hba1c_percent,
           'fasting_glucose_mmol',     p.fasting_glucose_mmol,
           'post_meal_glucose_mmol',   p.post_meal_glucose_mmol,
           'random_glucose_mmol',      p.random_glucose_mmol,
           'systolic_bp',              p.systolic_bp,
           'diastolic_bp',             p.diastolic_bp,
           'plan_start_date',          p.plan_start_date,
           -- PII explicitly excluded:
           --   email, mobile, address, full_address
           -- (They are surfaced via getPublicProfile only when the
           -- patient themselves wants to share them.)
           'as_of_date',               (now() at time zone 'Asia/Dhaka')::date
         )
    into v_payload
    from public.user_profiles p
   where p.user_id = p_patient_user_id;

  return coalesce(v_payload, '{}'::jsonb);
end;
$$;

grant execute on function public.get_caretaker_patient_profile(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- 2. DAY PLAN  (mirrors get_day_plan_with_fallback + user_meal_plan)
-- Returns the cached 30-day-rotation plan for the given plan_day,
-- as a jsonb array of UserMealPlan-shape rows. Falls back to the
-- static plan if no cached row exists.
-- ─────────────────────────────────────────────────────────────
drop function if exists public.get_caretaker_day_plan(uuid, int);
create or replace function public.get_caretaker_day_plan(
  p_patient_user_id uuid,
  p_plan_day int
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'Asia/Dhaka')::date;
  v_payload jsonb;
begin
  perform public.assert_caretaker_can_read(p_patient_user_id);

  -- Try the cached per-user recommendations for today first.
  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb)
    into v_payload
  from (
    select r.id,
           r.plan_date,
           r.plan_day,
           r.slot,
           r.food_id,
           r.food_name_bn,
           r.portion_g,
           r.portion_label,
           r.kcal,
           r.carb_g,
           r.protein_g,
           r.fat_g,
           r.fiber_g,
           r.gi_category,
           r.category,
           r.role,
           f.name_bn            as resolved_name,
           f.portion_label      as resolved_portion,
           f.category           as resolved_category,
           f.gi_category        as resolved_gi
      from public.user_meal_plan_recommendations r
      left join public.foods f on f.id = r.food_id
     where r.user_id = p_patient_user_id
       and r.plan_date = v_today
     order by r.slot, r.role
  ) t;

  -- Fall back to the 30-day rotation template if nothing cached.
  -- We rebuild the same 18-column shape so the JSON matches the
  -- cached branch (id, plan_date, plan_day, slot, food_id,
  -- food_name_bn, portion_g, portion_label, kcal, carb_g,
  -- protein_g, fat_g, fiber_g, gi_category, category, role,
  -- resolved_name, resolved_portion, resolved_category, resolved_gi).
  if v_payload is null or jsonb_array_length(v_payload) = 0 then
    with rotation as (
      select mpd.day as plan_day,
             mpd.breakfast_main    as breakfast,
             mpd.morning_snack     as morning_snack,
             mpd.lunch_carb        as lunch_carb,
             mpd.lunch_protein     as lunch_protein,
             mpd.lunch_vegetable   as lunch_vegetable,
             mpd.lunch_dal         as lunch_dal,
             mpd.evening_snack     as evening_snack,
             mpd.dinner_carb       as dinner_carb,
             mpd.dinner_protein    as dinner_protein,
             mpd.dinner_vegetable  as dinner_vegetable
        from public.meal_plan_days mpd
       where mpd.day = p_plan_day
    ),
    slots(slot, role, food_id, plan_day) as (
      select 'breakfast',     'main',       breakfast,    plan_day from rotation
      union all select 'morning_snack','snack',  morning_snack, plan_day from rotation
      union all select 'lunch',        'carb',    lunch_carb,    plan_day from rotation
      union all select 'lunch',        'protein', lunch_protein, plan_day from rotation
      union all select 'lunch',        'vegetable', lunch_vegetable, plan_day from rotation
      union all select 'lunch',        'dal',      lunch_dal,     plan_day from rotation
      union all select 'evening_snack','snack',    evening_snack, plan_day from rotation
      union all select 'dinner',       'carb',     dinner_carb,   plan_day from rotation
      union all select 'dinner',       'protein',  dinner_protein, plan_day from rotation
      union all select 'dinner',       'vegetable',dinner_vegetable, plan_day from rotation
    )
    select coalesce(jsonb_agg(row_to_json(t) order by t.slot, t.role), '[]'::jsonb)
      into v_payload
    from (
      select null::uuid                          as id,
             null::date                          as plan_date,
             s.plan_day,
             s.slot,
             s.food_id,
             null::text                          as food_name_bn,
             null::numeric                       as portion_g,
             null::text                          as portion_label,
             null::numeric                       as kcal,
             null::numeric                       as carb_g,
             null::numeric                       as protein_g,
             null::numeric                       as fat_g,
             null::numeric                       as fiber_g,
             null::text                          as gi_category,
             null::text                          as category,
             s.role,
             f.name_bn                           as resolved_name,
             f.portion_label                     as resolved_portion,
             f.category                          as resolved_category,
             f.gi_category                       as resolved_gi
        from slots s
        left join public.foods f on f.id = s.food_id
    ) t;
  end if;

  return v_payload;
end;
$$;

grant execute on function public.get_caretaker_day_plan(uuid, int) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- 3. DAILY LOG  (mirrors get_daily_log — meal_intake_log entries
-- for the given calendar date + plan_day)
-- ─────────────────────────────────────────────────────────────
drop function if exists public.get_caretaker_daily_log(uuid, int);
drop function if exists public.get_caretaker_daily_log(uuid, int, date);
create or replace function public.get_caretaker_daily_log(
  p_patient_user_id uuid,
  p_plan_day int default null,
  p_date    date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_date date := coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date);
  v_out  jsonb;
begin
  perform public.assert_caretaker_can_read(p_patient_user_id);

  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb)
    into v_out
  from (
    select id, meal_slot, food_id, food_name_bn, status, impact, notes,
           plan_day, impact_reason, meal_date, created_at
      from public.meal_intake_log
     where user_id  = p_patient_user_id
       and hidden   = false
       and meal_date = v_date
       and (p_plan_day is null or plan_day = p_plan_day)
     order by created_at asc
  ) t;

  return jsonb_build_object('date', v_date, 'plan_day', p_plan_day, 'items', v_out);
end;
$$;

grant execute on function public.get_caretaker_daily_log(uuid, int, date) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- 4. PLAN PROGRESS  (mirrors get_plan_progress)
-- ─────────────────────────────────────────────────────────────
drop function if exists public.get_caretaker_plan_progress(uuid);
create or replace function public.get_caretaker_plan_progress(p_patient_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_start    date;
  v_today    date := (now() at time zone 'Asia/Dhaka')::date;
  v_diff     int;
  v_day      int;
  v_complete bool := false;
begin
  perform public.assert_caretaker_can_read(p_patient_user_id);

  select up.plan_start_date into v_start
    from public.user_profiles up
   where up.user_id = p_patient_user_id;

  if v_start is null then
    v_start := v_today;
  end if;

  v_diff := greatest(0, (v_today - v_start));
  v_day  := (v_diff % 30) + 1;
  v_complete := v_diff >= 30;

  return jsonb_build_object(
    'day',             v_day,
    'total_days',      30,
    'plan_complete',   v_complete,
    'plan_start_date', v_start,
    'days_elapsed',    v_diff
  );
end;
$$;

grant execute on function public.get_caretaker_plan_progress(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- 5. TODAY DAILY METRICS  (mirrors get_today_daily_metrics)
-- Returns { water_liters, heart_rate_bpm, steps, has_data }
-- ─────────────────────────────────────────────────────────────
drop function if exists public.get_caretaker_today_daily_metrics(uuid);
create or replace function public.get_caretaker_today_daily_metrics(p_patient_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_today date := (now() at time zone 'Asia/Dhaka')::date;
  v_payload jsonb;
begin
  perform public.assert_caretaker_can_read(p_patient_user_id);

  select jsonb_build_object(
           'water_liters',   coalesce(dm.water_liters, 0)::numeric(5,2),
           'heart_rate_bpm', coalesce(dm.heart_rate_bpm, 0),
           'steps',          coalesce(dm.steps, 0),
           'has_data',       (dm.user_id is not null)
         )
    into v_payload
    from public.daily_metrics dm
   where dm.user_id = p_patient_user_id
     and dm.metric_date = v_today;

  return coalesce(v_payload, jsonb_build_object(
    'water_liters', 0, 'heart_rate_bpm', 0, 'steps', 0, 'has_data', false
  ));
end;
$$;

grant execute on function public.get_caretaker_today_daily_metrics(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- 6. WATER ANALYTICS  (mirrors get_water_analytics — same JSON
-- shape: { days[], streak_days, days_hit_target, avg_liters,
-- consistency_pct, target_liters, range_start, range_end })
-- ─────────────────────────────────────────────────────────────
drop function if exists public.get_caretaker_water_analytics(uuid, int);
create or replace function public.get_caretaker_water_analytics(
  p_patient_user_id uuid,
  p_days int default 7
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_target     constant numeric := 2.5;
  v_today      date := (now() at time zone 'Asia/Dhaka')::date;
  v_start      date := v_today - (greatest(p_days, 1) - 1);
  v_streak     int := 0;
  v_hit_count  int := 0;
  v_avg_liters numeric(6,2) := 0;
  v_days       int := 0;
  v_payload    jsonb;
begin
  perform public.assert_caretaker_can_read(p_patient_user_id);

  with days as (
    select generate_series(v_start, v_today, '1 day')::date as d
  ),
  agg as (
    select s.occurred_date::date as d,
           count(*)::int as glasses,
           coalesce(sum(s.liters), 0)::numeric(5,2) as liters,
           coalesce(count(*) filter (where s.bucket='morning'),0)::int    as morning,
           coalesce(count(*) filter (where s.bucket='noon'),0)::int       as noon,
           coalesce(count(*) filter (where s.bucket='afternoon'),0)::int  as afternoon,
           coalesce(count(*) filter (where s.bucket='night'),0)::int      as night
      from public.water_intake_log s
     where s.user_id = p_patient_user_id
       and s.occurred_date::date between v_start and v_today
     group by 1
  )
  select jsonb_agg(
           jsonb_build_object(
             'date',         to_char(days.d, 'YYYY-MM-DD'),
             'glasses',      coalesce(agg.glasses, 0),
             'liters',       coalesce(agg.liters, 0)::numeric(5,2),
             'target_hit',   coalesce(agg.liters, 0) >= v_target,
             'buckets',      jsonb_build_object(
               'morning',   coalesce(agg.morning, 0),
               'noon',      coalesce(agg.noon, 0),
               'afternoon', coalesce(agg.afternoon, 0),
               'night',     coalesce(agg.night, 0)
             )
           )
           order by days.d
         ),
         coalesce(sum(coalesce(agg.liters, 0)), 0),
         count(*) filter (where coalesce(agg.liters, 0) >= v_target),
         count(*)
    into v_payload, v_avg_liters, v_hit_count, v_days
  from days
  left join agg on agg.d = days.d;

  for i in 0..greatest(p_days, 1)-1 loop
    if exists (
      select 1 from public.water_intake_log s
       where s.user_id = p_patient_user_id
         and s.occurred_date::date = v_today - i
       group by s.occurred_date
      having coalesce(sum(s.liters), 0) >= v_target
    ) then
      v_streak := v_streak + 1;
    else
      exit;
    end if;
  end loop;

  if v_days > 0 then
    v_avg_liters := round((v_avg_liters / v_days)::numeric, 2);
  end if;

  return jsonb_build_object(
    'days',            coalesce(v_payload, '[]'::jsonb),
    'streak_days',     v_streak,
    'days_hit_target', v_hit_count,
    'avg_liters',      v_avg_liters,
    'consistency_pct', case when v_days = 0 then 0
                            else round((v_hit_count::numeric / v_days) * 100, 1)
                       end,
    'target_liters',   v_target,
    'range_start',     to_char(v_start, 'YYYY-MM-DD'),
    'range_end',       to_char(v_today, 'YYYY-MM-DD')
  );
end;
$$;

grant execute on function public.get_caretaker_water_analytics(uuid, int) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- 7. LIST MEDICINES  (mirrors list_medicines — active + inactive)
-- ─────────────────────────────────────────────────────────────
drop function if exists public.get_caretaker_medicines(uuid);
create or replace function public.get_caretaker_medicines(p_patient_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_caretaker_can_read(p_patient_user_id);

  return coalesce((
    select jsonb_agg(to_jsonb(m) order by m.is_active desc, m.created_at desc)
    from (
      select m.id, m.user_id, m.name_bn, m.name_en, m.form, m.strength,
             m.dose_amount, m.dose_unit, m.meal_relation, m.schedule,
             m.start_date, m.end_date, m.color, m.notes,
             m.is_active, m.created_at, m.updated_at
        from public.medicines m
       where m.user_id = p_patient_user_id
    ) m
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.get_caretaker_medicines(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- 8. MEDICINE DOSES FOR DATE  (mirrors get_medicine_doses)
-- Returns one row per (medicine, scheduled_time) pair for the day,
-- merged with the dose log so the UI gets the taken/skipped/missed
-- status inline.
-- ─────────────────────────────────────────────────────────────
drop function if exists public.get_caretaker_medicine_doses_for_date(uuid, date);
create or replace function public.get_caretaker_medicine_doses_for_date(
  p_patient_user_id uuid,
  p_date date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day date := coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date);
  v_now time := (now() at time zone 'Asia/Dhaka')::time;
begin
  perform public.assert_caretaker_can_read(p_patient_user_id);

  return coalesce((
    select jsonb_agg(to_jsonb(row) order by row.sort_time, row.medicine_name)
    from (
      with slots as (
        select m.id as medicine_id, m.name_bn, m.name_en, m.form, m.strength,
               m.dose_amount, m.dose_unit, m.meal_relation, m.color,
               m.notes as medicine_notes, m.is_active,
               (s->>'time')::time as scheduled_time,
               s->>'bucket' as bucket
          from public.medicines m
          cross join lateral jsonb_array_elements(m.schedule) s
         where m.user_id = p_patient_user_id
           and m.is_active = true
           and m.start_date <= v_day
           and (m.end_date is null or m.end_date >= v_day)
      ),
      merged as (
        select s.medicine_id, s.name_bn, s.name_en, s.form, s.strength,
               s.dose_amount, s.dose_unit, s.meal_relation, s.color,
               s.medicine_notes, s.scheduled_time, s.bucket,
               d.id as dose_id, d.status, d.taken_at, d.note,
               s.scheduled_time as sort_time
          from slots s
          left join public.medicine_doses d
            on d.medicine_id = s.medicine_id
           and d.dose_date = v_day
           and d.scheduled_time = s.scheduled_time
      )
      select
        medicine_id, name_bn, name_en, form, strength,
        dose_amount, dose_unit, meal_relation, color, medicine_notes,
        scheduled_time, bucket, dose_id, status, taken_at, note,
        sort_time,
        name_bn as medicine_name,
        case
          when dose_id is not null then true
          when status = 'missed' then true
          else false
        end as is_resolved,
        case
          when dose_id is null
               and v_now > scheduled_time
               and (scheduled_time + interval '60 min') < v_now
            then true
          else false
        end as is_overdue
      from merged
    ) row
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.get_caretaker_medicine_doses_for_date(uuid, date) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- 9. TODAY WORKOUT  (mirrors get_today_workout)
-- Returns { day_index, today, assignments[], session }
-- ─────────────────────────────────────────────────────────────
drop function if exists public.get_caretaker_today_workout(uuid, int);
create or replace function public.get_caretaker_today_workout(
  p_patient_user_id uuid,
  p_day_index int default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'Asia/Dhaka')::date;
  v_day   int := coalesce(p_day_index, 1);
  v_assignments jsonb;
  v_session jsonb;
begin
  perform public.assert_caretaker_can_read(p_patient_user_id);

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'workout_id', w.id,
      'name_bn', w.name_bn,
      'name_en', w.name_en,
      'category', w.category,
      'sub_category', w.sub_category,
      'intensity', w.intensity,
      'difficulty', w.difficulty,
      'duration_min', w.duration_min,
      'repetitions', w.repetitions,
      'target_duration_seconds', w.target_duration_seconds,
      'target_calories_kcal', w.target_calories_kcal,
      'description_bn', w.description_bn,
      'instructions', w.instructions,
      'instructions_bn', w.instructions_bn,
      'equipment', w.equipment,
      'position', a.position
    ) order by a.position, w.name_bn
  ), '[]'::jsonb)
  into v_assignments
  from public.workout_assignments a
  join public.workouts w on w.id = a.workout_id and w.is_active
  where a.user_id = p_patient_user_id and a.day_index = v_day and a.is_active;

  select jsonb_build_object(
    'id', s.id,
    'session_date', s.session_date,
    'program_day', s.program_day,
    'started_at', s.started_at,
    'finished_at', s.finished_at,
    'total_duration_seconds', s.total_duration_seconds,
    'completed_items', s.completed_items,
    'total_items', s.total_items,
    'is_finished', s.is_finished,
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', i.id,
          'workout_id', i.workout_id,
          'position', i.position,
          'is_completed', i.is_completed,
          'started_at', i.started_at,
          'finished_at', i.finished_at,
          'duration_seconds', i.duration_seconds
        ) order by i.position
      )
      from public.workout_session_items i where i.session_id = s.id
    ), '[]'::jsonb)
  )
  into v_session
  from public.workout_sessions s
  where s.user_id = p_patient_user_id and s.session_date = v_today;

  return jsonb_build_object(
    'day_index',   v_day,
    'today',       v_today,
    'assignments', v_assignments,
    'session',     v_session
  );
end;
$$;

grant execute on function public.get_caretaker_today_workout(uuid, int) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- 10. WORKOUT LOGS  (mirrors get_workout_logs — last N days)
-- Returns one row per session with totals in the WorkoutLogRow shape.
-- ─────────────────────────────────────────────────────────────
drop function if exists public.get_caretaker_workout_logs(uuid, int);
create or replace function public.get_caretaker_workout_logs(
  p_patient_user_id uuid,
  p_days int default 7
)
returns table (
  day date,
  total int,
  completed int,
  total_minutes int,
  total_calories int,
  is_finished boolean
)
language sql
security definer
set search_path = public
as $$
  select s.session_date as day,
         s.total_items as total,
         s.completed_items as completed,
         floor(s.total_duration_seconds / 60) as total_minutes,
         floor(s.total_duration_seconds / 60) * 5 as total_calories,
         s.is_finished
    from public.workout_sessions s
   where s.user_id = p_patient_user_id
     and s.session_date >= (current_date - (greatest(p_days, 1) - 1))
   order by s.session_date desc;
$$;

grant execute on function public.get_caretaker_workout_logs(uuid, int) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- 11. MEAL ADHERENCE  (per-user, mirrors get_meal_adherence)
-- ─────────────────────────────────────────────────────────────
drop function if exists public.get_caretaker_meal_adherence(uuid, int);
create or replace function public.get_caretaker_meal_adherence(
  p_patient_user_id uuid,
  p_days int default 7
)
returns table (
  day date,
  eaten int,
  planned int,
  ratio numeric
)
language sql
security definer
set search_path = public
as $$
  with d as (
    select (current_date - g)::date as day
      from generate_series(0, greatest(p_days, 1) - 1) g
  ),
  eaten_per_day as (
    select l.meal_date as day, count(*)::int as eaten
      from public.meal_intake_log l
     where l.user_id = p_patient_user_id
       and l.status in ('eaten','swap')
       and l.meal_date >= (current_date - (p_days - 1))
     group by l.meal_date
  )
  select d.day,
         coalesce(e.eaten, 0) as eaten,
         coalesce(
           (
             select 1 + (case when lunch_dal is not null then 1 else 0 end)
                    + (case when morning_snack is not null then 1 else 0 end)
                    + (case when evening_snack is not null then 1 else 0 end)
             from public.meal_plan_days
             where day = (((d.day - date '2025-01-01') % 30) + 1)
           ), 0
         ) as planned,
         case
           when coalesce(e.eaten, 0) = 0 then null
           else round(
             (e.eaten::numeric / nullif(
               (
                 select 1 + (case when lunch_dal is not null then 1 else 0 end)
                        + (case when morning_snack is not null then 1 else 0 end)
                        + (case when evening_snack is not null then 1 else 0 end)
                 from public.meal_plan_days
                 where day = (((d.day - date '2025-01-01') % 30) + 1)
               ), 0
             )), 2)
         end as ratio
    from d
    left join eaten_per_day e on e.day = d.day
    order by d.day;
$$;

grant execute on function public.get_caretaker_meal_adherence(uuid, int) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- 12. MEDICINE ADHERENCE  (per-user, mirrors get_medicine_adherence)
-- ─────────────────────────────────────────────────────────────
drop function if exists public.get_caretaker_medicine_adherence(uuid, int);
create or replace function public.get_caretaker_medicine_adherence(
  p_patient_user_id uuid,
  p_days int default 7
)
returns table (
  day date,
  taken int,
  total int,
  ratio numeric
)
language sql
security definer
set search_path = public
as $$
  with d as (
    select (current_date - g)::date as day
      from generate_series(0, greatest(p_days, 1) - 1) g
  ),
  per_day as (
    select d.day,
           coalesce(sum(case when md.status = 'taken' then 1 else 0 end), 0)::int as taken,
           count(md.*)::int as total
      from d
      left join public.medicine_doses md
        on md.user_id = p_patient_user_id and md.dose_date = d.day
     group by d.day
  )
  select day, taken, total,
         case when total = 0 then null else round(taken::numeric / total, 2) end as ratio
    from per_day
    order by day;
$$;

grant execute on function public.get_caretaker_medicine_adherence(uuid, int) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- 13. WORKOUT ADHERENCE  (per-user, mirrors get_workout_adherence)
-- ─────────────────────────────────────────────────────────────
drop function if exists public.get_caretaker_workout_adherence(uuid, int);
create or replace function public.get_caretaker_workout_adherence(
  p_patient_user_id uuid,
  p_days int default 7
)
returns table (
  day date,
  completed int,
  total int,
  ratio numeric
)
language sql
security definer
set search_path = public
as $$
  with d as (
    select (current_date - g)::date as day
      from generate_series(0, greatest(p_days, 1) - 1) g
  )
  select d.day,
         coalesce(s.completed_items, 0) as completed,
         coalesce(s.total_items, 0) as total,
         case
           when s.total_items is null or s.total_items = 0 then null
           else round((s.completed_items::numeric / s.total_items), 2)
         end as ratio
    from d
    left join public.workout_sessions s
      on s.user_id = p_patient_user_id and s.session_date = d.day
    order by d.day;
$$;

grant execute on function public.get_caretaker_workout_adherence(uuid, int) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- 14. THIRTY DAY REPORT  (per-user, mirrors get_thirty_day_report(int))
-- Same JSON shape as the patient-side RPC plus cycle_index.
-- ─────────────────────────────────────────────────────────────
drop function if exists public.get_caretaker_thirty_day_report(uuid, int);
create or replace function public.get_caretaker_thirty_day_report(
  p_patient_user_id uuid,
  p_cycle_index int default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_created_at  timestamptz;
  v_start_date  date;
  v_today       date := current_date;
  v_doc_int     int;
  v_payload     jsonb;
  v_cycle_index int := greatest(0, coalesce(p_cycle_index, 0));
  v_cycle_start_offset int := v_cycle_index * 30;
begin
  perform public.assert_caretaker_can_read(p_patient_user_id);

  select u.created_at into v_created_at
    from auth.users u
   where u.id = p_patient_user_id;

  if v_created_at is null then
    -- Fallback: use plan_start_date, otherwise today.
    select up.plan_start_date into v_start_date
      from public.user_profiles up
     where up.user_id = p_patient_user_id;
    v_start_date := coalesce(v_start_date, v_today);
  else
    v_start_date := ((v_created_at at time zone 'Asia/Dhaka')::date
                     + v_cycle_start_offset);
  end if;

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
     where upr.user_id = p_patient_user_id
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
     where m.user_id = p_patient_user_id
       and m.meal_date between v_start_date and v_start_date + 29
     group by m.meal_date
  ),
  water as (
    select (occurred_at at time zone 'Asia/Dhaka')::date  as d,
           coalesce(sum(liters), 0)::numeric * 1000       as ml
      from public.water_intake_log
     where user_id = p_patient_user_id
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
     where user_id = p_patient_user_id
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
     where user_id = p_patient_user_id
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

grant execute on function public.get_caretaker_thirty_day_report(uuid, int) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- 15. ANALYTICS CYCLE COUNT  (per-user, mirrors get_analytics_cycle_count)
-- ─────────────────────────────────────────────────────────────
drop function if exists public.get_caretaker_analytics_cycle_count(uuid);
create or replace function public.get_caretaker_analytics_cycle_count(p_patient_user_id uuid)
returns int
language sql
stable
security definer
set search_path = public, auth
as $$
  with u as (
    select u.created_at
      from auth.users u
     where u.id = p_patient_user_id
  )
  select greatest(0,
    (
      (current_date - ((u.created_at at time zone 'Asia/Dhaka')::date)) / 30
    ) + 1
  )::int
    from u;
$$;

grant execute on function public.get_caretaker_analytics_cycle_count(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- 16. TODAY MOOD  (per-user, mirrors get_today_mood)
-- ─────────────────────────────────────────────────────────────
drop function if exists public.get_caretaker_today_mood(uuid);
create or replace function public.get_caretaker_today_mood(p_patient_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_today date := (now() at time zone 'Asia/Dhaka')::date;
  v_payload jsonb;
begin
  perform public.assert_caretaker_can_read(p_patient_user_id);

  select jsonb_build_object(
           'mood_kind',    mood_kind,
           'energy_level', energy_level,
           'stress_level', stress_level,
           'sleep_hours',  sleep_hours,
           'symptoms',     symptoms,
           'entry_date',   entry_date,
           'created_at',   created_at
         )
    into v_payload
    from public.mood_entries
   where user_id = p_patient_user_id
     and entry_date = v_today
   limit 1;

  return v_payload;
end;
$$;

grant execute on function public.get_caretaker_today_mood(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- 17. MOOD HISTORY  (per-user, mirrors get_mood_history)
-- ─────────────────────────────────────────────────────────────
drop function if exists public.get_caretaker_mood_history(uuid, int);
create or replace function public.get_caretaker_mood_history(
  p_patient_user_id uuid,
  p_days int default 14
)
returns table (
  entry_date   date,
  mood_kind    text,
  energy_level int,
  stress_level int,
  sleep_hours  numeric
)
language sql
security definer
set search_path = public, auth
as $$
  select entry_date, mood_kind, energy_level, stress_level, sleep_hours
    from public.mood_entries
   where user_id = p_patient_user_id
     and entry_date >= ((now() at time zone 'Asia/Dhaka')::date - greatest(p_days, 1))
   order by entry_date desc;
$$;

grant execute on function public.get_caretaker_mood_history(uuid, int) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- Done. Run AFTER 29_caretaker_read_rpcs.sql in Supabase SQL Editor.
--
-- Grant summary (for copy/paste if needed):
--   grant execute on function public.get_caretaker_patient_profile(uuid)             to authenticated;
--   grant execute on function public.get_caretaker_day_plan(uuid, int)               to authenticated;
--   grant execute on function public.get_caretaker_daily_log(uuid, int, date)        to authenticated;
--   grant execute on function public.get_caretaker_plan_progress(uuid)               to authenticated;
--   grant execute on function public.get_caretaker_today_daily_metrics(uuid)         to authenticated;
--   grant execute on function public.get_caretaker_water_analytics(uuid, int)        to authenticated;
--   grant execute on function public.get_caretaker_medicines(uuid)                  to authenticated;
--   grant execute on function public.get_caretaker_medicine_doses_for_date(uuid, date) to authenticated;
--   grant execute on function public.get_caretaker_today_workout(uuid, int)          to authenticated;
--   grant execute on function public.get_caretaker_workout_logs(uuid, int)           to authenticated;
--   grant execute on function public.get_caretaker_meal_adherence(uuid, int)         to authenticated;
--   grant execute on function public.get_caretaker_medicine_adherence(uuid, int)     to authenticated;
--   grant execute on function public.get_caretaker_workout_adherence(uuid, int)      to authenticated;
--   grant execute on function public.get_caretaker_thirty_day_report(uuid, int)      to authenticated;
--   grant execute on function public.get_caretaker_analytics_cycle_count(uuid)      to authenticated;
--   grant execute on function public.get_caretaker_today_mood(uuid)                  to authenticated;
--   grant execute on function public.get_caretaker_mood_history(uuid, int)           to authenticated;
-- ============================================================
