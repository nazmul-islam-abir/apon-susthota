-- ============================================================
-- 51 — Delete account (wipes bdapps_users + auth.users shadow row).
-- Apply AFTER 50_bdapps_shadow_auth.sql. Safe to re-run.
--
-- Why this file exists:
--   Today the only ways to "leave" the app are Logout (purely local)
--   and Unsubscribe (BDApps operator unsubscribe + local logout). Both
--   leave server-side data intact. Some users — typically a household
--   where one person registered as a patient and the other now needs
--   the same number as a caretaker — need a way to permanently wipe
--   their data so they can re-register the same number with a
--   different role.
--
--   This file creates a single RPC `bdapps_delete_account(p_mobile)`
--   that:
--     1. Confirms the caller is the shadow auth user that matches the
--        provided mobile (defends against deleting somebody else).
--     2. Deletes the auth.users row. ON DELETE CASCADE on every
--        domain table (user_profiles, meal_intake_log, medicines,
--        medicine_intake_log, workout_*, daily_*, water_*, mood_entries,
--        ai_chat_action_log, caretaker_patient_links, notifications, …)
--        wipes every row tied to this shadow user automatically.
--     3. Deletes the standalone bdapps_users row (it has no FK in/out).
--
--   The Flutter caller MUST invoke BDApps `unsubscribe.php` BEFORE
--   calling this RPC, so the operator also stops charging. The RPC is
--   idempotent: it can be run more than once for the same mobile
--   without erroring.
--
--   Run this in your Supabase SQL editor.
-- ============================================================


-- ---------- 1. Delete-account RPC ----------
create or replace function public.bdapps_delete_account(p_mobile text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_digits        text := regexp_replace(coalesce(p_mobile, ''), '\D', '', 'g');
  v_email         text;
  v_shadow_id     uuid;
  v_auth_uid      uuid := auth.uid();
  v_deleted_auth  int  := 0;
  v_deleted_bdap  int  := 0;
begin
  if v_auth_uid is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  -- Normalize to 8801XXXXXXXXX
  if v_digits like '880%' and length(v_digits) = 13 then
    null;
  elsif v_digits like '0%' and length(v_digits) = 11 and v_digits ~ '^01[3-9][0-9]{8}$' then
    v_digits := '88' || v_digits;
  else
    raise exception 'Invalid Bangladeshi mobile number: %', p_mobile;
  end if;

  v_email := v_digits || '@bdapps.app';

  -- Find the shadow user (idempotent: if it doesn't exist, just wipe
  -- bdapps_users and bail).
  select id into v_shadow_id from auth.users where auth.users.email = v_email;

  if v_shadow_id is null then
    delete from public.bdapps_users where mobile = v_digits;
    return jsonb_build_object(
      'ok', true,
      'deleted_auth_user', false,
      'deleted_bdapps_user',
        (select count(*) from public.bdapps_users where mobile = v_digits) = 0,
      'shadow_user_id', null);
  end if;

  if v_shadow_id <> v_auth_uid then
    raise exception 'Cannot delete another user''s account'
      using errcode = '42501';
  end if;

  -- 1. Delete the shadow auth user first. ON DELETE CASCADE on every
  --    domain table wipes every row tied to this id in one shot:
  --    user_profiles, meal_intake_log, medicines, medicine_intake_log,
  --    workout_*, daily_*, water_*, meal_plan_overrides,
  --    ai_chat_action_log, mood_entries, caretaker_patient_links,
  --    notifications, ….
  delete from auth.users where id = v_shadow_id;
  get diagnostics v_deleted_auth = row_count;

  -- 2. bdapps_users has no FK to anything — wipe it explicitly.
  delete from public.bdapps_users where mobile = v_digits;
  get diagnostics v_deleted_bdap = row_count;

  return jsonb_build_object(
    'ok', true,
    'deleted_auth_user',     v_deleted_auth > 0,
    'deleted_bdapps_user',   v_deleted_bdap > 0,
    'shadow_user_id',        v_shadow_id::text);
end;
$$;

grant execute on function public.bdapps_delete_account(text) to authenticated;

-- Permissions note:
--   * The function is SECURITY DEFINER and runs as the owner (postgres
--     role), so deleting from auth.users works without granting the
--     client the supabase_auth_admin role.
--   * The executor must be 'authenticated' (the signed-in BDApps user)
--     so the auth.uid() guard can compare against the shadow id.
