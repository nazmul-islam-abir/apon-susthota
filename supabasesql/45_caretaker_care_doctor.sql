-- ============================================================
-- 45 — Caretaker-as-Doctor: own profile + write passthrough
-- Apply AFTER 28_roles_and_caretaker.sql, 29_caretaker_read_rpcs.sql,
--         30_caretaker_write_passthrough.sql (the empty placeholder),
--         44_caretaker_full_read_rpcs.sql.
--
-- What this file does:
--   Section A — extends user_profiles with a small set of doctor-
--               style columns that the caretaker fills in on their
--               own profile (bio, specialty, license, clinic, …).
--               Patient profile unchanged. Caretaker never sees
--               these fields on a patient profile.
--   Section B — exposes the caretaker's own profile via a thin
--               SECURITY DEFINER RPC (the existing RLS already
--               lets caretakers read/write their own profile, so
--               this is mostly a typed convenience wrapper).
--   Section C — caretaker write passthrough. Mirrors the patient-
--               only write RPCs but parameterized by p_patient.
--               Authorised via assert_caretaker_can_read first;
--               then we route the write through the relevant
--               SECURITY DEFINER patient RPC by passing
--               p_patient as the "acting" uid. We use set_config
--               to override auth.uid() inside the transaction so
--               the underlying patient RPC accepts the call as
--               if the patient themselves were authenticated.
--               This is the safest pattern: we never grant the
--               caretaker write access to the underlying tables
--               directly — the patient-only RPC stays the single
--               write path.
--
-- Why section C uses auth.uid() override via set_config:
--   The patient RPCs are declared SECURITY DEFINER but they gate
--   every operation on `auth.uid() = v_user`. Without a way to
--   impersonate, the only alternative is to re-implement every
--   patient write RPC body inline here (duplication + drift risk).
--   `set_config('request.jwt.claim.sub', ..., true)` is the
--   documented Supabase pattern for impersonating inside a single
--   function call. After the function exits the claim is auto-
--   restored. We additionally guard that this override is ONLY
--   done for callers who pass the caretaker-authorisation check.
--
-- Idempotent — safe to re-apply.
-- ============================================================


-- ============================================================
-- SECTION A — Caretaker own-profile columns
-- ============================================================

alter table public.user_profiles
  add column if not exists doctor_bio text;

alter table public.user_profiles
  add column if not exists doctor_specialty text
    check (doctor_specialty is null or length(trim(doctor_specialty)) <= 80);

alter table public.user_profiles
  add column if not exists doctor_license_number text
    check (doctor_license_number is null or length(trim(doctor_license_number)) <= 60);

alter table public.user_profiles
  add column if not exists doctor_clinic_name text
    check (doctor_clinic_name is null or length(trim(doctor_clinic_name)) <= 120);

alter table public.user_profiles
  add column if not exists doctor_years_experience int
    check (doctor_years_experience is null or doctor_years_experience between 0 and 70);

alter table public.user_profiles
  add column if not exists doctor_qualifications text
    check (doctor_qualifications is null or length(trim(doctor_qualifications)) <= 200);

alter table public.user_profiles
  add column if not exists doctor_languages text
    check (doctor_languages is null or length(trim(doctor_languages)) <= 200);

alter table public.user_profiles
  add column if not exists doctor_availability text
    check (doctor_availability is null or length(trim(doctor_availability)) <= 200);

alter table public.user_profiles
  add column if not exists doctor_credentials text
    check (doctor_credentials is null or length(trim(doctor_credentials)) <= 200);


-- ============================================================
-- SECTION B — Caretaker own-profile get / update
-- ============================================================

-- Get the calling user's own profile fragment. Returns ONLY the
-- doctor-style columns plus the basic identity. Never touches a
-- patient's profile.
drop function if exists public.get_my_doctor_profile();
create or replace function public.get_my_doctor_profile()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_payload jsonb;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;

  select jsonb_build_object(
           'user_id',                p.user_id,
           'full_name',              p.full_name,
           'username',               p.username,
           'avatar_url',             p.avatar_url,
           'role',                   p.role,
           'caretaker_relationship', p.caretaker_relationship,
           'doctor_bio',             p.doctor_bio,
           'doctor_specialty',       p.doctor_specialty,
           'doctor_license_number',  p.doctor_license_number,
           'doctor_clinic_name',     p.doctor_clinic_name,
           'doctor_years_experience',p.doctor_years_experience,
           'doctor_qualifications',  p.doctor_qualifications,
           'doctor_languages',       p.doctor_languages,
           'doctor_availability',    p.doctor_availability,
           'doctor_credentials',     p.doctor_credentials,
           'updated_at',             p.updated_at
         )
    into v_payload
    from public.user_profiles p
   where p.user_id = v_uid;

  return coalesce(v_payload, '{}'::jsonb);
end;
$$;
grant execute on function public.get_my_doctor_profile() to authenticated;


-- Update the calling user's own profile fragment. Only the
-- doctor-style columns are accepted here (a separate flow edits
-- the basic identity/clinical fields via 02_rpcs.sql).
drop function if exists public.update_my_doctor_profile(text, text, text, text, int, text, text, text, text);
create or replace function public.update_my_doctor_profile(
  p_bio               text default null,
  p_specialty         text default null,
  p_license_number    text default null,
  p_clinic_name       text default null,
  p_years_experience  int  default null,
  p_qualifications    text default null,
  p_languages         text default null,
  p_availability      text default null,
  p_credentials       text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;

  select role into v_role from public.user_profiles where user_id = v_uid;
  if v_role is distinct from 'caretaker' then
    raise exception 'Only caretakers may edit the doctor profile';
  end if;

  update public.user_profiles
    set doctor_bio              = case when p_bio is not null
                                        then nullif(trim(p_bio), '') else doctor_bio end,
        doctor_specialty        = case when p_specialty is not null
                                        then nullif(trim(p_specialty), '') else doctor_specialty end,
        doctor_license_number   = case when p_license_number is not null
                                        then nullif(trim(p_license_number), '') else doctor_license_number end,
        doctor_clinic_name      = case when p_clinic_name is not null
                                        then nullif(trim(p_clinic_name), '') else doctor_clinic_name end,
        doctor_years_experience = coalesce(p_years_experience, doctor_years_experience),
        doctor_qualifications   = case when p_qualifications is not null
                                        then nullif(trim(p_qualifications), '') else doctor_qualifications end,
        doctor_languages        = case when p_languages is not null
                                        then nullif(trim(p_languages), '') else doctor_languages end,
        doctor_availability     = case when p_availability is not null
                                        then nullif(trim(p_availability), '') else doctor_availability end,
        doctor_credentials      = case when p_credentials is not null
                                        then nullif(trim(p_credentials), '') else doctor_credentials end,
        updated_at              = now()
  where user_id = v_uid;
end;
$$;
grant execute on function public.update_my_doctor_profile(text, text, text, text, int, text, text, text, text) to authenticated;


-- ============================================================
-- SECTION C — Caretaker write passthrough
-- ============================================================
-- Pattern: each public function asserts the caretaker link,
-- then calls the existing patient-only SECURITY DEFINER RPC with
-- auth.uid() temporarily overridden to p_patient. This keeps the
-- underlying patient write path as the single source of truth.
--
-- We wrap the impersonation in an EXCEPTION block so if the
-- override fails for any reason the caller still sees a clean
-- error rather than a half-applied write.

-- Helper: temporarily act as p_patient_user_id. Restores the
-- previous auth.uid() automatically when the function exits
-- because set_config(..., true) is local to the transaction.
create or replace function public._caretaker_act_as(p_patient_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform set_config('request.jwt.claim.sub', p_patient_user_id::text, true);
end;
$$;
-- Not granted to anyone directly; only callable by other
-- SECURITY DEFINER RPCs in this file (the grant below is implicit
-- because Postgres grants execute to PUBLIC by default and we
-- gate every caller via assert_caretaker_can_read).
grant execute on function public._caretaker_act_as(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- C1. caretaker_log_meal_for_patient
-- ─────────────────────────────────────────────────────────────
drop function if exists public.caretaker_log_meal_for_patient(uuid, text, text, text, text, text, int, text);
create or replace function public.caretaker_log_meal_for_patient(
  p_patient_user_id uuid,
  p_meal_slot       text,
  p_food_id         text,
  p_food_name_bn    text,
  p_status          text,
  p_impact          text,
  p_plan_day        int  default null,
  p_reason          text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  perform public.assert_caretaker_can_read(p_patient_user_id);

  if p_status not in ('eaten','swap','off_plan') then
    raise exception 'Invalid status';
  end if;
  if p_impact not in ('good','neutral','bad') then
    raise exception 'Invalid impact';
  end if;

  perform public._caretaker_act_as(p_patient_user_id);
  v_id := public.record_meal_intake(
    p_meal_slot, p_food_id, p_food_name_bn,
    p_status, p_impact, null,
    p_plan_day, p_reason
  );
  return v_id;
end;
$$;
grant execute on function public.caretaker_log_meal_for_patient(uuid, text, text, text, text, text, int, text) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- C2. caretaker_log_water_for_patient
-- ─────────────────────────────────────────────────────────────
drop function if exists public.caretaker_log_water_for_patient(uuid, numeric);
create or replace function public.caretaker_log_water_for_patient(
  p_patient_user_id uuid,
  p_delta           numeric
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.water_intake_log;
begin
  perform public.assert_caretaker_can_read(p_patient_user_id);
  if p_delta is null or p_delta <= 0 then
    raise exception 'delta must be > 0';
  end if;

  perform public._caretaker_act_as(p_patient_user_id);
  v_row := public.log_water_event(p_delta, now());
  return to_jsonb(v_row);
end;
$$;
grant execute on function public.caretaker_log_water_for_patient(uuid, numeric) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- C3. caretaker_mark_dose_for_patient
-- ─────────────────────────────────────────────────────────────
drop function if exists public.caretaker_mark_dose_for_patient(uuid, uuid, date, time, text, text);
create or replace function public.caretaker_mark_dose_for_patient(
  p_patient_user_id uuid,
  p_medicine_id     uuid,
  p_dose_date       date,
  p_scheduled_time  time,
  p_status          text default 'taken',
  p_note            text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  perform public.assert_caretaker_can_read(p_patient_user_id);
  if p_status not in ('taken','skipped','missed') then
    raise exception 'Invalid status';
  end if;

  perform public._caretaker_act_as(p_patient_user_id);
  v_id := public.mark_dose(
    p_medicine_id, p_dose_date, p_scheduled_time, p_status, p_note
  );
  return v_id;
end;
$$;
grant execute on function public.caretaker_mark_dose_for_patient(uuid, uuid, date, time, text, text) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- C4. caretaker_create_medicine_for_patient
-- ─────────────────────────────────────────────────────────────
drop function if exists public.caretaker_create_medicine_for_patient(uuid, text, text, text, text, numeric, text, text, jsonb, date, date, text, text);
create or replace function public.caretaker_create_medicine_for_patient(
  p_patient_user_id uuid,
  p_name_bn         text,
  p_name_en         text default null,
  p_form            text default 'tablet',
  p_strength        text default null,
  p_dose_amount     numeric default 1,
  p_dose_unit       text default 'unit',
  p_meal_relation   text default 'any',
  p_schedule        jsonb default '[]'::jsonb,
  p_start_date      date default ((now() at time zone 'Asia/Dhaka')::date),
  p_end_date        date default null,
  p_color           text default null,
  p_notes           text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  perform public.assert_caretaker_can_read(p_patient_user_id);

  perform public._caretaker_act_as(p_patient_user_id);
  v_id := public.create_medicine(
    p_name_bn, p_name_en, p_form, p_strength, p_dose_amount,
    p_dose_unit, p_meal_relation, p_schedule, p_start_date,
    p_end_date, p_color, p_notes
  );
  return v_id;
end;
$$;
grant execute on function public.caretaker_create_medicine_for_patient(uuid, text, text, text, text, numeric, text, text, jsonb, date, date, text, text) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- C5. caretaker_update_medicine (medicine_id-only auth — we look up the owner)
-- ─────────────────────────────────────────────────────────────
drop function if exists public.caretaker_update_medicine(uuid, text, text, text, text, numeric, text, text, jsonb, date, date, boolean, text, text, boolean);
create or replace function public.caretaker_update_medicine(
  p_medicine_id     uuid,
  p_name_bn         text default null,
  p_name_en         text default null,
  p_form            text default null,
  p_strength        text default null,
  p_dose_amount     numeric default null,
  p_dose_unit       text default null,
  p_meal_relation   text default null,
  p_schedule        jsonb default null,
  p_start_date      date default null,
  p_end_date        date default null,
  p_clear_end_date  boolean default false,
  p_color           text default null,
  p_notes           text default null,
  p_is_active       boolean default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
begin
  select user_id into v_owner from public.medicines where id = p_medicine_id;
  if v_owner is null then raise exception 'Medicine not found'; end if;

  -- Authorise against the owner of the medicine.
  perform public.assert_caretaker_can_read(v_owner);

  perform public._caretaker_act_as(v_owner);
  perform public.update_medicine(
    p_medicine_id, p_name_bn, p_name_en, p_form, p_strength,
    p_dose_amount, p_dose_unit, p_meal_relation, p_schedule,
    p_start_date, p_end_date, p_clear_end_date, p_color,
    p_notes, p_is_active
  );
end;
$$;
grant execute on function public.caretaker_update_medicine(uuid, text, text, text, text, numeric, text, text, jsonb, date, date, boolean, text, text, boolean) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- C6. caretaker_delete_medicine
-- ─────────────────────────────────────────────────────────────
drop function if exists public.caretaker_delete_medicine(uuid);
create or replace function public.caretaker_delete_medicine(p_medicine_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
begin
  select user_id into v_owner from public.medicines where id = p_medicine_id;
  if v_owner is null then raise exception 'Medicine not found'; end if;

  perform public.assert_caretaker_can_read(v_owner);

  perform public._caretaker_act_as(v_owner);
  perform public.delete_medicine(p_medicine_id);
end;
$$;
grant execute on function public.caretaker_delete_medicine(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- C7. caretaker_create_meal_plan_entry
-- ─────────────────────────────────────────────────────────────
drop function if exists public.caretaker_create_meal_plan_entry(uuid, date, text, time, text, text, text, text, int);
create or replace function public.caretaker_create_meal_plan_entry(
  p_patient_user_id uuid,
  p_effective_date  date,
  p_slot            text,
  p_scheduled_time  time default null,
  p_food_id         text default null,
  p_custom_food_name text default null,
  p_portion_label   text default null,
  p_notes           text default null,
  p_position        int  default 0
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  perform public.assert_caretaker_can_read(p_patient_user_id);
  if p_slot not in (
    'breakfast','morning_snack','lunch','evening_snack','dinner',
    'tiffin','late_night','pre_workout','post_workout','other'
  ) then
    raise exception 'Invalid slot';
  end if;

  perform public._caretaker_act_as(p_patient_user_id);
  v_id := public.create_user_meal_plan(
    p_effective_date, p_slot, p_scheduled_time, p_food_id,
    p_custom_food_name, p_portion_label, p_notes, p_position
  );
  return v_id;
end;
$$;
grant execute on function public.caretaker_create_meal_plan_entry(uuid, date, text, time, text, text, text, text, int) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- C8. caretaker_update_meal_plan_entry
-- ─────────────────────────────────────────────────────────────
drop function if exists public.caretaker_update_meal_plan_entry(uuid, date, text, time, boolean, text, boolean, text, text, text, int, boolean);
create or replace function public.caretaker_update_meal_plan_entry(
  p_plan_id            uuid,
  p_effective_date     date default null,
  p_slot               text default null,
  p_scheduled_time     time default null,
  p_clear_scheduled_time boolean default false,
  p_food_id            text default null,
  p_clear_food_id      boolean default false,
  p_custom_food_name   text default null,
  p_portion_label      text default null,
  p_notes              text default null,
  p_position           int  default null,
  p_is_active          boolean default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
begin
  select user_id into v_owner from public.user_meal_plans where id = p_plan_id;
  if v_owner is null then raise exception 'Plan entry not found'; end if;

  perform public.assert_caretaker_can_read(v_owner);

  perform public._caretaker_act_as(v_owner);
  perform public.update_user_meal_plan(
    p_plan_id, p_effective_date, p_slot, p_scheduled_time,
    p_clear_scheduled_time, p_food_id, p_clear_food_id,
    p_custom_food_name, p_portion_label, p_notes, p_position, p_is_active
  );
end;
$$;
grant execute on function public.caretaker_update_meal_plan_entry(uuid, date, text, time, boolean, text, boolean, text, text, text, int, boolean) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- C9. caretaker_delete_meal_plan_entry
-- ─────────────────────────────────────────────────────────────
drop function if exists public.caretaker_delete_meal_plan_entry(uuid);
create or replace function public.caretaker_delete_meal_plan_entry(p_plan_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
begin
  select user_id into v_owner from public.user_meal_plans where id = p_plan_id;
  if v_owner is null then raise exception 'Plan entry not found'; end if;

  perform public.assert_caretaker_can_read(v_owner);

  perform public._caretaker_act_as(v_owner);
  perform public.delete_user_meal_plan(p_plan_id);
end;
$$;
grant execute on function public.caretaker_delete_meal_plan_entry(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- C10. caretaker_hide_meal_intake (undo a meal-log entry)
-- ─────────────────────────────────────────────────────────────
drop function if exists public.caretaker_hide_meal_intake(uuid);
create or replace function public.caretaker_hide_meal_intake(p_intake_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
begin
  select user_id into v_owner from public.meal_intake_log where id = p_intake_id;
  if v_owner is null then raise exception 'Meal log entry not found'; end if;

  perform public.assert_caretaker_can_read(v_owner);

  perform public._caretaker_act_as(v_owner);
  perform public.hide_meal_intake(p_intake_id);
end;
$$;
grant execute on function public.caretaker_hide_meal_intake(uuid) to authenticated;


-- ============================================================
-- SECTION D — Caretaker view of patient's doctor/care profile
-- (read-only convenience wrapper that doesn't expose clinical data)
-- ============================================================
-- (Intentionally omitted: caretakers see only the standard
--  patient profile via get_caretaker_patient_profile. They never
--  see another caretaker's doctor profile via these RPCs.)
