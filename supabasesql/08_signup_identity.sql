-- ============================================================
-- 08_signup_identity.sql
-- Adds full_name + mobile to user_profiles, and a trigger so the
-- client's auth signup raw_user_meta_data gets mirrored into the
-- public profile row automatically.
--
-- Run this AFTER 01_schema.sql. Safe to re-run.
-- ============================================================

-- 1. New columns on user_profiles -------------------------------------------------
alter table public.user_profiles
  add column if not exists full_name text,
  add column if not exists mobile text;

-- 2. Auto-create a profile row when a new auth user signs up ---------------------
-- The Flutter client passes full_name + mobile + role (+ caretaker_relationship
-- when role='caretaker') in raw_user_meta_data; we copy them straight into the
-- public profile so the rest of the app can read them like any other profile
-- field.
--
-- IMPORTANT: `role` and `caretaker_relationship` were added by
-- 28_roles_and_caretaker.sql. If this file is run BEFORE 28, those columns
-- don't exist yet — so we guard the INSERT with a dynamic EXECUTE that only
-- references the new columns when they exist. That keeps the trigger safe to
-- run in any order.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_rel  text;
  v_has_role_cols boolean;
begin
  -- Detect whether the role/caretaker_relationship columns exist yet.
  -- They're added by 28_roles_and_caretaker.sql; if this trigger runs before
  -- that file, we silently skip them instead of erroring out.
  select exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name   = 'user_profiles'
       and column_name in ('role','caretaker_relationship')
     group by table_name
    having count(*) = 2
  ) into v_has_role_cols;

  -- Pull values from the metadata the Flutter client sent during signup.
  -- We lowercase + trim so client typos (' Caretaker ', 'CARETAKER') still work,
  -- and clamp to the CHECK-allowed set so the INSERT can't violate the
  -- `role in ('patient','caretaker')` constraint.
  v_role := lower(trim(coalesce(new.raw_user_meta_data->>'role', '')));
  if v_role not in ('patient', 'caretaker') then
    v_role := 'patient';
  end if;

  v_rel := nullif(trim(coalesce(new.raw_user_meta_data->>'caretaker_relationship', '')), '');
  -- caretakers MUST have a relationship; if the client forgot to send one we
  -- fall back to a generic Bangla label so the profile isn't blank.
  if v_role = 'caretaker' and v_rel is null then
    v_rel := 'পরিচর্যাকারী';
  end if;
  -- patients should never carry a relationship string.
  if v_role = 'patient' then
    v_rel := null;
  end if;

  if v_has_role_cols then
    -- Detect whether the email column exists yet. Added by
    -- 31_email_and_unified_search.sql; if this trigger runs
    -- before that file we still want the signup to succeed.
    execute $exists$
      select exists (
        select 1 from information_schema.columns
         where table_schema = 'public'
           and table_name   = 'user_profiles'
           and column_name  = 'email'
      )
    $exists$ into v_has_role_cols; -- reuse bool variable name in scope
    -- (variable is misnamed; treat as "has email column" from here)
    if v_has_role_cols then
      execute $q$
        insert into public.user_profiles (
          user_id, full_name, mobile, email,
          role, caretaker_relationship,
          age, weight_kg, height_cm
        )
        values (
          $1, $2, $3, lower($6),
          $4, $5,
          30, 60.0, 160.0
        )
        on conflict (user_id) do update set
          email = excluded.email
      $q$
      using new.id,
            coalesce(new.raw_user_meta_data->>'full_name', ''),
            coalesce(new.raw_user_meta_data->>'mobile', ''),
            v_role,
            v_rel,
            new.email;
    else
      execute $q$
        insert into public.user_profiles (
          user_id, full_name, mobile,
          role, caretaker_relationship,
          age, weight_kg, height_cm
        )
        values (
          $1, $2, $3,
          $4, $5,
          30, 60.0, 160.0
        )
        on conflict (user_id) do nothing
      $q$
      using new.id,
            coalesce(new.raw_user_meta_data->>'full_name', ''),
            coalesce(new.raw_user_meta_data->>'mobile', ''),
            v_role,
            v_rel;
    end if;
  else
    -- Pre-28 schema: only the legacy columns exist. Insert without role.
    insert into public.user_profiles (
      user_id, full_name, mobile, age, weight_kg, height_cm
    )
    values (
      new.id,
      coalesce(new.raw_user_meta_data->>'full_name', ''),
      coalesce(new.raw_user_meta_data->>'mobile', ''),
      30, 60.0, 160.0
    )
    on conflict (user_id) do nothing;
  end if;

  return new;
end;
$$;

-- Drop + recreate the trigger so we can re-run this file idempotently.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- ============================================================
-- 3. BACKFILL — fix rows that were created before this trigger
-- knew about role/caretaker_relationship.
--
-- Before this update, any user who signed up as "caretaker" via the
-- Flutter app ended up with `role = 'patient'` in user_profiles
-- because the trigger only copied full_name + mobile from
-- raw_user_meta_data. The caretaker_relationship metadata was
-- discarded entirely.
--
-- This block reads every existing profile whose role is still
-- 'patient', inspects the matching auth.users.raw_user_meta_data,
-- and promotes the row to 'caretaker' + caretaker_relationship
-- when the metadata says so.
--
-- Idempotent: running it again is a no-op once all rows are correct.
-- Safe to re-run after re-deploying the trigger above.
-- ============================================================
do $$
begin
  -- Only run when 28_roles_and_caretaker.sql has been applied (i.e.
  -- the role column exists). The IF wraps the entire backfill.
  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name   = 'user_profiles'
       and column_name  = 'role'
  ) then
    update public.user_profiles up
       set role = case
             when lower(trim(coalesce(u.raw_user_meta_data->>'role', ''))) in ('caretaker','caregiver')
               then 'caretaker'
             else 'patient'
           end,
           caretaker_relationship = case
             when lower(trim(coalesce(u.raw_user_meta_data->>'role', ''))) in ('caretaker','caregiver')
               then coalesce(
                    nullif(trim(u.raw_user_meta_data->>'caretaker_relationship'), ''),
                    'পরিচর্যাকারী'
                  )
             else null
           end
      from auth.users u
     where u.id = up.user_id
       and up.role = 'patient'
       and lower(trim(coalesce(u.raw_user_meta_data->>'role', ''))) in ('caretaker','caregiver');
  end if;
end $$;
