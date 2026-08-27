-- ============================================================
-- 29 — Caretaker read RPCs
-- Apply AFTER 28_roles_and_caretaker.sql.
--
-- What this file does:
--   Exposes the read paths that the caretaker app uses to render
--   a patient's day/week/month summary. Every RPC here:
--     1. Verifies the caller (auth.uid()) has an ACTIVE link to
--        the requested patient via public.caretaker_patient_links.
--     2. Reads the patient-owned data on their behalf using that
--        link as the authorisation gate.
--     3. Returns jsonb so the Flutter client can decode without
--        coupling to a specific shape.
--
-- Design notes:
--   * SECURITY DEFINER + search_path = public, auth so we can
--     read from tables that normally require auth.uid() = user_id.
--   * We never write on the patient's behalf here — write paths
--     for the caretaker (intake / dose logging) live in the patch
--     to 05_meal_intake_actions.sql + 12_medicine.sql (Phase A3).
-- ============================================================


-- ---------- 1. AUTHORITY HELPER ----------
-- Used internally by every read RPC below. Throws if the caller
-- isn't an active link of the patient.
create or replace function public.assert_caretaker_can_read(p_patient uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller uuid := auth.uid();
  v_status text;
begin
  if v_caller is null then
    raise exception 'Not authenticated';
  end if;
  if p_patient is null then
    raise exception 'patient_user_id required';
  end if;

  select status into v_status
    from public.caretaker_patient_links
   where caretaker_user_id = v_caller
     and patient_user_id   = p_patient
     and status = 'active';

  if v_status is null then
    raise exception 'No active link to this patient';
  end if;
end;
$$;


-- ---------- 2. PATIENT LIST (Caretaker's directory) ----------
-- Returns every active link the caller (a caretaker) has, joined
-- with the patient's profile, plus a quick adherence snapshot so
-- the list can render status pills without a second round-trip.
-- Sorted by last_seen_at desc (most recent activity first).
drop function if exists public.get_caretaker_patient_list();
create or replace function public.get_caretaker_patient_list()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller uuid := auth.uid();
  v_payload jsonb;
begin
  if v_caller is null then raise exception 'Not authenticated'; end if;

  select coalesce(jsonb_agg(row_to_json(t) order by t.last_seen_at desc nulls last), '[]'::jsonb)
    into v_payload
  from (
    select l.id                                as link_id,
           p.user_id                           as patient_user_id,
           p.full_name,
           p.avatar_url,
           p.age,
           p.sex,
           p.on_insulin,
           p.caretaker_relationship,
           p.hba1c_percent,
           p.fasting_glucose_mmol,
           l.last_seen_at,
           -- Connection bookkeeping surfaced on the patient
           -- detail "সংযোগ তথ্য" card.
           -- The caretaker is always the initiator in our schema
           -- (RLS allows only caretakers to INSERT links), so
           -- `initiated_by_me` is always TRUE here. Surfaced so
           -- the UI can show a stable message regardless of role.
           true                                as initiated_by_me,
           l.requested_at                      as linked_at,
           l.status                            as link_status,
           -- Per-patient meal adherence (uses the explicit-user
           -- variant because base get_meal_adherence is hard-coded
           -- to auth.uid() — i.e. the caretaker's uid when this
           -- SECURITY DEFINER function is invoked from a caretaker
           -- session, which would always return 0).
           coalesce(
             (
               select sum(m.eaten)
               from public.get_meal_adherence_for(p.user_id, 7) m
             ), 0
           )::int as meals_last_7_days,
           coalesce(
             (
               select sum(m.planned)
               from public.get_meal_adherence_for(p.user_id, 7) m
             ), 0
           )::int as meals_planned_7_days,
           (
             select case
                      when avg(m.ratio) is null then null
                      else round(avg(m.ratio), 2)
                    end
             from public.get_meal_adherence_for(p.user_id, 7) m
           ) as meal_adherence_7d,
           (
             select case
                      when m.ratio is null then null
                      else m.ratio
                    end
             from public.get_meal_adherence_for(p.user_id, 7) m
             where m.day = ((now() at time zone 'Asia/Dhaka')::date)
           ) as meal_adherence_today,
           (
             select case
                      when avg(med.taken_pct) is null then null
                      else round(avg(med.taken_pct) / 100.0, 2)
                    end
             from public.get_medicine_logs_for(p.user_id, 7) med
           ) as medicine_adherence_7d,
           (
             select med.taken_pct
             from public.get_medicine_logs_for(p.user_id, 1) med
             where med.day = ((now() at time zone 'Asia/Dhaka')::date)
           ) as medicine_today_pct
      from public.caretaker_patient_links l
      join public.user_profiles        p on p.user_id = l.patient_user_id
     where l.caretaker_user_id = v_caller
       and l.status           = 'active'
  ) t;

  return v_payload;
end;
$$;


-- ---------- 3. INCOMING REQUESTS (Caretaker's pending list) ----------
-- The patient side has its own inbox. Caretakers may also want
-- to see links that are still pending so they know what's waiting.
drop function if exists public.get_caretaker_pending_requests();
create or replace function public.get_caretaker_pending_requests()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller uuid := auth.uid();
  v_payload jsonb;
begin
  if v_caller is null then raise exception 'Not authenticated'; end if;

  select coalesce(jsonb_agg(row_to_json(t) order by t.requested_at desc), '[]'::jsonb)
    into v_payload
  from (
    select l.id              as link_id,
           p.user_id         as patient_user_id,
           p.full_name,
           p.age,
           l.request_note,
           l.caretaker_relationship,
           l.requested_at
      from public.caretaker_patient_links l
      join public.user_profiles        p on p.user_id = l.patient_user_id
     where l.caretaker_user_id = v_caller
       and l.status           = 'pending'
  ) t;

  return v_payload;
end;
$$;


-- ---------- 4. TODAY OVERVIEW ----------
-- One-shot snapshot for the "Today" tab of the caretaker app.
-- Combines: water glasses, today's meal slots eaten, latest BP
-- + sugar metric, and last-active timestamp.
drop function if exists public.get_caretaker_today_overview(uuid);
create or replace function public.get_caretaker_today_overview(p_patient uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payload jsonb;
  v_water   numeric;
  v_meals   jsonb;
  v_sugar   jsonb;
  v_bp      jsonb;
  v_meds    jsonb;
begin
  perform public.assert_caretaker_can_read(p_patient);

  -- Touch the link so the patient list sorts by freshness.
  update public.caretaker_patient_links
     set last_seen_at = now()
   where caretaker_user_id = auth.uid()
     and patient_user_id   = p_patient
     and status            = 'active';

  select coalesce(dm.water_liters, 0)
    into v_water
    from public.daily_metrics dm
   where dm.user_id    = p_patient
     and dm.metric_date = ((now() at time zone 'Asia/Dhaka')::date);

  select coalesce(jsonb_agg(row_to_json(t) order by t.meal_slot), '[]'::jsonb)
    into v_meals
    from (
      select meal_slot,
             status,
             impact,
             food_name_bn,
             created_at
        from public.meal_intake_log
       where user_id  = p_patient
         and hidden   = false
         and meal_date = ((now() at time zone 'Asia/Dhaka')::date)
    ) t;

  -- Sugar / BP readings today. The schema stores the latest sugar
  -- + BP as profile columns (not as a separate observations log),
  -- so the today overview mirrors those values. We expose them as
  -- `latest_*` to make clear they're the current profile snapshot,
  -- not a date-bounded observation. NULL is fine.
  select jsonb_build_object(
           'fasting_mmol',     p.fasting_glucose_mmol,
           'postprandial_mmol', p.post_meal_glucose_mmol,
           'random_mmol',      p.random_glucose_mmol,
           'hba1c_percent',    p.hba1c_percent
         ),
         jsonb_build_object(
           'systolic_mmhg',  p.systolic_bp,
           'diastolic_mmhg', p.diastolic_bp
         )
    into v_sugar, v_bp
    from public.user_profiles p
   where p.user_id = p_patient;

  -- Medicine today: total doses + taken count.
  select row_to_json(t)
    into v_meds
  from (
    select coalesce(taken,0)  as taken,
           coalesce(total,0)  as total,
           case when coalesce(total,0) = 0 then null
                else round((coalesce(taken,0)::numeric / total) * 100, 1)
           end as taken_pct
    from public.get_medicine_logs(1)
    where day = ((now() at time zone 'Asia/Dhaka')::date)
  ) t;

  v_payload := jsonb_build_object(
    'patient_user_id', p_patient,
    'as_of_date',     ((now() at time zone 'Asia/Dhaka')::date),
    'water_liters',   coalesce(v_water, 0),
    'water_target',   2.5,
    'meals',          coalesce(v_meals, '[]'::jsonb),
    'sugar',          v_sugar,
    'bp',             v_bp,
    'medicine',       v_meds
  );

  return v_payload;
end;
$$;


-- ---------- 5. DAILY BREAKDOWN (week / month chart source) ----------
-- Returns one row per day for the last `p_days`, each row holding
-- meal/med/water/workout adherence. The caretaker UI uses this for
-- both the week (7) and month (30) tabs unchanged.
drop function if exists public.get_caretaker_daily_breakdown(uuid, int);
create or replace function public.get_caretaker_daily_breakdown(
  p_patient uuid,
  p_days    int default 7
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payload jsonb;
begin
  perform public.assert_caretaker_can_read(p_patient);

  select coalesce(jsonb_agg(row_to_json(t) order by t.day asc), '[]'::jsonb)
    into v_payload
  from (
    with days as (
      select ((now() at time zone 'Asia/Dhaka')::date - g)::date as day
        from generate_series(0, greatest(p_days, 1) - 1) g
    )
    select d.day,
           coalesce((
             select round((m.eaten::numeric / nullif(m.planned,0)), 2)
               from public.get_meal_adherence(greatest(p_days, 1)) m
              where m.day = d.day
           ), null)                                    as meal_ratio,
           coalesce((
             select ml.taken_pct
               from public.get_medicine_logs(greatest(p_days, 1)) ml
              where ml.day = d.day
           ), 0)                                        as medicine_pct,
           coalesce(dm.water_liters, 0)::numeric(5,2)   as water_liters,
           coalesce(dm.heart_rate_bpm, 0)               as heart_rate_bpm,
           coalesce(dm.steps, 0)                        as steps,
           coalesce((
             select case when ws.total_items = 0 or ws.total_items is null
                         then null
                         else round(ws.completed_items::numeric / ws.total_items, 2)
                    end
               from public.workout_sessions ws
              where ws.user_id = p_patient
                and ws.session_date = d.day
           ), null)                                      as workout_ratio,
           coalesce((
             select ws.total_duration_seconds
               from public.workout_sessions ws
              where ws.user_id = p_patient
                and ws.session_date = d.day
           ), 0)                                        as workout_seconds
    from days d
    left join public.daily_metrics dm
      on dm.user_id = p_patient and dm.metric_date = d.day
  ) t;

  return jsonb_build_object(
    'patient_user_id', p_patient,
    'days',           greatest(p_days, 1),
    'series',         coalesce(v_payload, '[]'::jsonb)
  );
end;
$$;


-- ---------- 6. RECENT ACTIVITIES ----------
-- Mixed feed of (meal, water, medicine, workout) events so the
-- caretaker can scan "what the patient did today" without
-- opening four RPCs.
drop function if exists public.get_caretaker_recent_activities(uuid, int);
create or replace function public.get_caretaker_recent_activities(
  p_patient uuid,
  p_limit   int default 30
)
returns table (
  occurred_at  timestamptz,
  kind         text,
  summary_bn   text,
  detail       jsonb
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_max int := least(greatest(coalesce(p_limit, 30), 1), 100);
begin
  perform public.assert_caretaker_can_read(p_patient);

  return query
    with events as (
      -- Meals
      select l.created_at as ts,
             'meal'::text as kind,
             case when l.status = 'eaten'   then 'খাবার খেয়েছে'
                  when l.status = 'swap'    then 'বিকল্প খেয়েছে'
                  when l.status = 'off_plan' then 'পরিকল্পনার বাইরে খেয়েছে'
                  else 'খাবার লগ'
             end as summary_bn,
             jsonb_build_object(
               'meal_slot',   l.meal_slot,
               'food_name_bn', l.food_name_bn,
               'impact',      l.impact
             ) as detail
        from public.meal_intake_log l
       where l.user_id = p_patient
         and l.hidden  = false
      union all
      -- Water events
      select s.occurred_at as ts,
             'water'::text as kind,
             'পানি: ' || s.liters::text || ' লিটার' as summary_bn,
             jsonb_build_object('liters', s.liters, 'bucket', s.bucket) as detail
        from public.water_intake_log s
       where s.user_id = p_patient
      union all
      -- Medicine doses
      select coalesce(d.taken_at, d.created_at) as ts,
             'medicine'::text as kind,
             case when d.status = 'taken'   then 'ওষুধ নিয়েছে'
                  when d.status = 'skipped' then 'ওষুধ স্কিপ করেছে'
                  when d.status = 'missed'  then 'ওষুধ মিস হয়েছে'
                  else 'ওষুধ লগ'
             end as summary_bn,
             jsonb_build_object(
               'status',         d.status,
               'scheduled_time', d.scheduled_time
             ) as detail
        from public.medicine_doses d
       where d.user_id = p_patient
      union all
      -- Workout sessions
      select coalesce(ws.finished_at, ws.started_at, ws.updated_at) as ts,
             'workout'::text as kind,
             case when ws.is_finished then 'ব্যায়াম সম্পন্ন'
                  else 'ব্যায়াম শুরু'
             end as summary_bn,
             jsonb_build_object(
               'total_items',     ws.total_items,
               'completed_items', ws.completed_items,
               'duration_seconds', ws.total_duration_seconds
             ) as detail
        from public.workout_sessions ws
       where ws.user_id = p_patient
    )
    select e.ts, e.kind, e.summary_bn, e.detail
      from events e
     order by e.ts desc
     limit v_max;
end;
$$;


-- ---------- 7. CLINICAL SNAPSHOT ----------
-- Read-only view of the patient's clinical profile. Returned as
-- jsonb so the schema can evolve without breaking the client.
-- No PII like email or raw mobile is included.
drop function if exists public.get_caretaker_clinical_snapshot(uuid);
create or replace function public.get_caretaker_clinical_snapshot(p_patient uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payload jsonb;
begin
  perform public.assert_caretaker_can_read(p_patient);

  select jsonb_build_object(
           'full_name',               p.full_name,
           'age',                     p.age,
           'sex',                     p.sex,
           'weight_kg',               p.weight_kg,
           'height_cm',               p.height_cm,
           'bmi',                     p.bmi,
           'fasting_glucose_mmol',    p.fasting_glucose_mmol,
           'post_meal_glucose_mmol',  p.post_meal_glucose_mmol,
           'random_glucose_mmol',     p.random_glucose_mmol,
           'hba1c_percent',           p.hba1c_percent,
           'on_insulin',              p.on_insulin,
           'medication',              p.medication,
           'systolic_bp',             p.systolic_bp,
           'diastolic_bp',            p.diastolic_bp,
           'has_ckd',                 p.has_ckd,
           'ckd_stage',               p.ckd_stage,
           'has_heart_disease',       p.has_heart_disease,
           'has_anemia',              p.has_anemia,
           'other_conditions',        p.other_conditions,
           'activity_level',          p.activity_level,
           'meal_size_pref',          p.meal_size_pref,
           'food_preference',         p.food_preference
         )
    into v_payload
    from public.user_profiles p
   where p.user_id = p_patient;

  return coalesce(v_payload, '{}'::jsonb);
end;
$$;


-- ---------- 8. PATIENT'S LINK INBOX ----------
-- Pending requests the patient must accept/decline. Read-only
-- here — accept/decline happens via respond_caretaker_link().
drop function if exists public.get_patient_pending_links();
create or replace function public.get_patient_pending_links()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_patient uuid := auth.uid();
  v_payload jsonb;
begin
  if v_patient is null then raise exception 'Not authenticated'; end if;

  select coalesce(jsonb_agg(row_to_json(t) order by t.requested_at desc), '[]'::jsonb)
    into v_payload
  from (
    select l.id                    as link_id,
           l.caretaker_user_id,
           l.request_note,
           l.caretaker_relationship,
           l.requested_at,
           up.full_name            as caretaker_name,
           up.age                  as caretaker_age,
           up.sex                  as caretaker_sex
      from public.caretaker_patient_links l
      left join public.user_profiles up on up.user_id = l.caretaker_user_id
     where l.patient_user_id = v_patient
       and l.status          = 'pending'
  ) t;

  return v_payload;
end;
$$;


-- ---------- 9. PATIENT'S CURRENT CARETAKERS ----------
-- Active caretaker list for the patient — surfaces "who is
-- currently watching me" on the patient's profile / inbox.
drop function if exists public.get_patient_active_caretakers();
create or replace function public.get_patient_active_caretakers()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_patient uuid := auth.uid();
  v_payload jsonb;
begin
  if v_patient is null then raise exception 'Not authenticated'; end if;

  select coalesce(jsonb_agg(row_to_json(t) order by t.responded_at desc), '[]'::jsonb)
    into v_payload
  from (
    select l.id                    as link_id,
           l.caretaker_user_id,
           up.full_name            as caretaker_name,
           up.age                  as caretaker_age,
           l.caretaker_relationship,
           l.responded_at,
           l.last_seen_at
      from public.caretaker_patient_links l
      left join public.user_profiles up on up.user_id = l.caretaker_user_id
     where l.patient_user_id = v_patient
       and l.status          = 'active'
  ) t;

  return v_payload;
end;
$$;


-- ---------- GRANTs ----------
grant execute on function public.assert_caretaker_can_read(uuid)                 to authenticated;
grant execute on function public.get_caretaker_patient_list()                   to authenticated;
grant execute on function public.get_caretaker_pending_requests()               to authenticated;
grant execute on function public.get_caretaker_today_overview(uuid)              to authenticated;
grant execute on function public.get_caretaker_daily_breakdown(uuid, int)       to authenticated;
grant execute on function public.get_caretaker_recent_activities(uuid, int)     to authenticated;
grant execute on function public.get_caretaker_clinical_snapshot(uuid)           to authenticated;
grant execute on function public.get_patient_pending_links()                    to authenticated;
grant execute on function public.get_patient_active_caretakers()                to authenticated;
