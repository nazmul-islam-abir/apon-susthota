-- ============================================================
-- 53 — Ensure correct Role synchronization between BDApps and User Profiles.
--
-- Updates:
-- 1. Alters user_profiles table to make mandatory fields nullable
--    so that initial registration succeeds before onboarding.
-- 2. Updates the handle_new_user trigger to correctly fetch the
--    role from bdapps_users.
-- ============================================================

-- ---------- 1. Make necessary columns nullable ----------
-- This ensures the registration trigger doesn't fail before
-- the onboarding flow completes.
ALTER TABLE public.user_profiles ALTER COLUMN age DROP NOT NULL;
ALTER TABLE public.user_profiles ALTER COLUMN weight_kg DROP NOT NULL;
ALTER TABLE public.user_profiles ALTER COLUMN height_cm DROP NOT NULL;
ALTER TABLE public.user_profiles ALTER COLUMN bmi DROP NOT NULL;
ALTER TABLE public.user_profiles ALTER COLUMN activity_level DROP NOT NULL;
ALTER TABLE public.user_profiles ALTER COLUMN meal_size_pref DROP NOT NULL;
ALTER TABLE public.user_profiles ALTER COLUMN food_preference DROP NOT NULL;

-- ---------- 2. Fix the new user profile trigger ----------
create or replace function public.handle_new_user()
returns trigger as $$
declare
  v_role text;
begin
  -- Fetch the role assigned during the BDApps login flow
  select role into v_role from public.bdapps_users where mobile = new.raw_user_meta_data->>'mobile';

  -- Fallback to 'patient' if no role found
  v_role := coalesce(v_role, 'patient');

  insert into public.user_profiles (
    user_id,
    mobile,
    role,
    updated_at
  )
  values (
    new.id,
    new.raw_user_meta_data->>'mobile',
    v_role,
    now()
  );

  return new;
end;
$$ language plpgsql security definer;

-- Ensure the trigger exists
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ---------- 3. Manual Fix for existing incorrectly assigned profiles ----------
update public.user_profiles up
set role = bu.role
from public.bdapps_users bu
where up.mobile = bu.mobile
  and up.role != bu.role;
