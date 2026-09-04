-- ============================================================
-- 54. CARETAKER REAL-TIME SYNC FIX
-- Fixes missing data fields and historical viewing for caretakers.
-- Ensures caretakers see exactly what patients see.
-- ============================================================

-- ─── 1. Enhanced Daily Metrics ──────────────────────────────────────
-- Updates the RPC to include workout_minutes and correctly filter.
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
           'metric_date',    dm.metric_date,
           'water_liters',   coalesce(dm.water_liters, 0)::numeric(5,2),
           'heart_rate_bpm', coalesce(dm.heart_rate_bpm, 0),
           'steps',          coalesce(dm.steps, 0),
           'workout_minutes', coalesce(dm.workout_minutes, 0),
           'has_data',       (dm.user_id is not null)
         )
    into v_payload
    from public.daily_metrics dm
   where dm.user_id = p_patient_user_id
     and dm.metric_date = v_today;

  return coalesce(v_payload, jsonb_build_object(
    'metric_date', v_today, 'water_liters', 0, 'heart_rate_bpm', 0,
    'steps', 0, 'workout_minutes', 0, 'has_data', false
  ));
end;
$$;

-- New RPC for historical metrics viewing.
drop function if exists public.get_caretaker_daily_metrics_for_date(uuid, date);
create or replace function public.get_caretaker_daily_metrics_for_date(
  p_patient_user_id uuid,
  p_date date
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_payload jsonb;
begin
  perform public.assert_caretaker_can_read(p_patient_user_id);

  select jsonb_build_object(
           'metric_date',    dm.metric_date,
           'water_liters',   coalesce(dm.water_liters, 0)::numeric(5,2),
           'heart_rate_bpm', coalesce(dm.heart_rate_bpm, 0),
           'steps',          coalesce(dm.steps, 0),
           'workout_minutes', coalesce(dm.workout_minutes, 0),
           'has_data',       (dm.user_id is not null)
         )
    into v_payload
    from public.daily_metrics dm
   where dm.user_id = p_patient_user_id
     and dm.metric_date = p_date;

  return coalesce(v_payload, jsonb_build_object(
    'metric_date', p_date, 'water_liters', 0, 'heart_rate_bpm', 0,
    'steps', 0, 'workout_minutes', 0, 'has_data', false
  ));
end;
$$;

-- ─── 2. Exercise Time Feedback (Per patient) ────────────────────────
-- Mirrors public.get_today_exercise_time_feedback for caretakers.
drop function if exists public.get_caretaker_today_exercise_time_feedback(uuid);
create or replace function public.get_caretaker_today_exercise_time_feedback(p_patient_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'Asia/Dhaka')::date;
  v_day int;
begin
  perform public.assert_caretaker_can_read(p_patient_user_id);

  -- Calculate day index relative to patient's start date
  select coalesce(
    ((v_today - (plan_start_date::date)) % 30) + 1,
    ((extract(day from v_today)::int - 1) % 30) + 1
  ) into v_day
  from public.user_profiles
  where id = p_patient_user_id;

  return (
    with today_assign as (
      select a.workout_id, w.target_duration_seconds
      from public.workout_assignments a
      join public.workouts w on w.id = a.workout_id and w.is_active
      where a.user_id = p_patient_user_id
        and a.is_active
        and a.day_index = v_day
    ),
    actual_per_workout as (
      select i.workout_id,
             coalesce(sum(i.duration_seconds), 0)::int as actual_seconds
      from public.workout_session_items i
      join public.workout_sessions s
        on s.id = i.session_id
      where s.user_id = p_patient_user_id
        and s.session_date = v_today
      group by i.workout_id
    )
    select coalesce(jsonb_agg(t), '[]'::jsonb)
    from (
      select
        ta.workout_id,
        ta.target_duration_seconds as target_seconds,
        coalesce(a.actual_seconds, 0) as actual_seconds,
        (ta.target_duration_seconds / 60)::int as target_minutes,
        (coalesce(a.actual_seconds, 0) / 60)::int as actual_minutes,
        case
          when ta.target_duration_seconds = 0 then 0.0
          else round((coalesce(a.actual_seconds, 0)::numeric / ta.target_duration_seconds)::numeric, 2)
        end as pct,
        format(
          '%s / %s মিনিট',
          (coalesce(a.actual_seconds, 0) / 60)::int,
          (ta.target_duration_seconds / 60)::int
        ) as hint_bn,
        case
          when coalesce(a.actual_seconds, 0) >= ta.target_duration_seconds then 'met'
          when coalesce(a.actual_seconds, 0) > 0 then 'partial'
          else 'pending'
        end as status
      from today_assign ta
      left join actual_per_workout a on a.workout_id = ta.workout_id
    ) t
  );
end $$;

-- ─── 3. Workout Time Tracking (Per patient) ─────────────────────────
-- Mirrors public.get_workout_time_tracking for caretakers.
drop function if exists public.get_caretaker_workout_time_tracking(uuid, int);
create or replace function public.get_caretaker_workout_time_tracking(
  p_patient_user_id uuid,
  p_days int default 7
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'Asia/Dhaka')::date;
begin
  perform public.assert_caretaker_can_read(p_patient_user_id);

  return (
    with series as (
      select (v_today - gs)::date as d
      from generate_series(0, greatest(p_days, 1) - 1) gs
    ),
    actual_per_day as (
      select s.session_date as d,
             coalesce(sum(s.total_duration_seconds), 0)::int as actual,
             coalesce(sum(s.completed_items), 0)::int as done
      from public.workout_sessions s
      where s.user_id = p_patient_user_id
        and s.session_date >= v_today - greatest(p_days, 1)
      group by s.session_date
    )
    select coalesce(jsonb_agg(t), '[]'::jsonb)
    from (
      select
        series.d as day,
        coalesce(ap.actual, 0)::int          as actual_seconds,
        (coalesce(ap.actual, 0) / 60)::int   as actual_minutes,
        coalesce(ap.done, 0)::int            as completed_count
      from series
      left join actual_per_day ap on ap.d = series.d
      order by series.d asc
    ) t
  );
end;
$$;

-- ─── 4. Grants ──────────────────────────────────────────────────────
grant execute on function public.get_caretaker_today_daily_metrics(uuid) to authenticated;
grant execute on function public.get_caretaker_daily_metrics_for_date(uuid, date) to authenticated;
grant execute on function public.get_caretaker_today_exercise_time_feedback(uuid) to authenticated;
grant execute on function public.get_caretaker_workout_time_tracking(uuid, int) to authenticated;
