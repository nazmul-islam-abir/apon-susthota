-- ============================================================
-- 56 — Caretaker-as-Relatives: rename doctor_* columns to
-- caretaker_* and re-purpose the existing storage for the new
-- form fields (relationship / contact phone / address / note).
--
-- Apply AFTER 45_caretaker_care_doctor.sql.
--
-- Why we re-purpose instead of adding 6 new columns:
--   The old "doctor-style" storage was always placeholder data
--   (most rows were empty). Re-purposing keeps the schema lean
--   while giving us exact the right shape for a relatives form:
--
--     OLD column                      NEW label              UI field
--     ----------------------------    -------------------    ------------------
--     doctor_bio                      caretaker_bio          optional "about me"
--     doctor_specialty        (text)  caretaker_specialty    relationship text
--     doctor_license_number  (text)  caretaker_license_number contact phone
--     doctor_clinic_name      (text)  caretaker_clinic_name  address
--     doctor_qualifications   (text)  caretaker_qualifications free-text note
--     doctor_availability     (text)  caretaker_availability contact-hours note
--
--     doctor_years_experience (int)  DROPPED (orphan, not needed)
--     doctor_languages        (text) DROPPED (orphan, not needed)
--     doctor_credentials      (text) DROPPED (orphan, not needed)
--
-- Existing data is preserved on rename. On drop, the columns are
-- gone — but no production row had meaningful data in them
-- (caretakers were never asked for these fields).
--
-- Idempotent — safe to re-apply.
-- ============================================================


-- ============================================================
-- SECTION A — Column renames (only if old column still exists)
-- ============================================================

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='user_profiles'
      AND column_name='doctor_bio'
  ) THEN
    ALTER TABLE public.user_profiles RENAME COLUMN doctor_bio TO caretaker_bio;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='user_profiles'
      AND column_name='doctor_specialty'
  ) THEN
    ALTER TABLE public.user_profiles RENAME COLUMN doctor_specialty TO caretaker_specialty;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='user_profiles'
      AND column_name='doctor_license_number'
  ) THEN
    ALTER TABLE public.user_profiles RENAME COLUMN doctor_license_number TO caretaker_license_number;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='user_profiles'
      AND column_name='doctor_clinic_name'
  ) THEN
    ALTER TABLE public.user_profiles RENAME COLUMN doctor_clinic_name TO caretaker_clinic_name;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='user_profiles'
      AND column_name='doctor_qualifications'
  ) THEN
    ALTER TABLE public.user_profiles RENAME COLUMN doctor_qualifications TO caretaker_qualifications;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='user_profiles'
      AND column_name='doctor_availability'
  ) THEN
    ALTER TABLE public.user_profiles RENAME COLUMN doctor_availability TO caretaker_availability;
  END IF;
END $$;

-- Drop the three orphan columns if they exist. Their data is
-- irrelevant to a relatives profile (years of clinical experience,
-- languages spoken, credentials uploaded).

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='user_profiles'
      AND column_name='doctor_years_experience'
  ) THEN
    ALTER TABLE public.user_profiles DROP COLUMN doctor_years_experience;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='user_profiles'
      AND column_name='doctor_languages'
  ) THEN
    ALTER TABLE public.user_profiles DROP COLUMN doctor_languages;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='user_profiles'
      AND column_name='doctor_credentials'
  ) THEN
    ALTER TABLE public.user_profiles DROP COLUMN doctor_credentials;
  END IF;
END $$;


-- ============================================================
-- SECTION B — Replace the old "doctor profile" RPCs with the
-- caretaker / relatives equivalents. Same SECURITY DEFINER shape.
-- ============================================================

-- Get own profile fragment. Returns the same shape as the old
-- get_my_doctor_profile(), but the JSON keys are renamed to make
-- the UI layer read like "relatives info" instead of clinical info.
drop function if exists public.get_my_doctor_profile();
create or replace function public.get_my_caretaker_profile()
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
           'caretaker_bio',          p.caretaker_bio,
           'caretaker_specialty',    p.caretaker_specialty,
           'caretaker_contact_phone',p.caretaker_license_number,
           'caretaker_address',      p.caretaker_clinic_name,
           'caretaker_note',         p.caretaker_qualifications,
           'caretaker_availability', p.caretaker_availability,
           'updated_at',             p.updated_at
         )
    into v_payload
    from public.user_profiles p
   where p.user_id = v_uid;

  return coalesce(v_payload, '{}'::jsonb);
end;
$$;
grant execute on function public.get_my_caretaker_profile() to authenticated;


-- Update own profile fragment. New parameter shape is relatives-
-- friendly: relationship (text), contact phone (text), address
-- (text), free-text note (text), contact-hours/availability note.
drop function if exists public.update_my_doctor_profile(text, text, text, text, int, text, text, text, text);
create or replace function public.update_my_caretaker_profile(
  p_bio              text default null,
  p_relationship     text default null,
  p_contact_phone    text default null,
  p_address          text default null,
  p_note             text default null,
  p_availability     text default null
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
    raise exception 'Only caretakers may edit the caretaker profile';
  end if;

  update public.user_profiles
    set caretaker_bio          = case when p_bio          is not null
                                        then nullif(trim(p_bio), '') else caretaker_bio end,
        caretaker_specialty    = case when p_relationship is not null
                                        then nullif(trim(p_relationship), '') else caretaker_specialty end,
        caretaker_license_number = case when p_contact_phone is not null
                                        then nullif(trim(p_contact_phone), '') else caretaker_license_number end,
        caretaker_clinic_name    = case when p_address      is not null
                                        then nullif(trim(p_address), '') else caretaker_clinic_name end,
        caretaker_qualifications = case when p_note         is not null
                                        then nullif(trim(p_note), '') else caretaker_qualifications end,
        caretaker_availability   = case when p_availability is not null
                                        then nullif(trim(p_availability), '') else caretaker_availability end,
        updated_at              = now()
  where user_id = v_uid;
end;
$$;
grant execute on function public.update_my_caretaker_profile(text, text, text, text, text, text) to authenticated;
