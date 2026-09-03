-- ============================================================
-- 49 — Clean up orphaned BDApps functions/columns from the
--      previous (over-engineered) 46 / 47 / 48 migrations.
-- Apply BEFORE 46_bdapps_login.sql. Safe to re-run.
--
-- Why this file exists:
--   The earlier migrations created RPCs that required Supabase auth
--   (auth.users, bcrypt, gen_salt, gen_random_bytes, auth.sign_in_with_password).
--   The new simplified 46_bdapps_login.sql doesn't touch auth.users at
--   all — it uses a lightweight `bdapps_users` table. We need to drop
--   the old RPCs and columns so they don't conflict with the new ones,
--   and so leftover triggers don't accidentally insert shadow users
--   into auth.users when new signups happen.
--
--   `cascade` is used on every drop so any trigger or view that still
--   references the old function is removed in the same statement.
--   This file is fully idempotent — every `drop if exists` plus
--   `cascade` ensures running it twice is safe.
-- ============================================================


-- ---------- 1. Drop legacy RPCs (cascade = drop dependent triggers/views) ----------
drop function if exists public.bdapps_create_or_get_user(text, text) cascade;
drop function if exists public.bdapps_issue_session(text) cascade;
drop function if exists public.bdapps_lookup(text) cascade;
drop function if exists public.bdapps_normalize_mobile(text) cascade;
drop function if exists public.bdapps_admin_create_user(text, text, jsonb) cascade;
drop function if exists public.bdapps_admin_create_user(text, text, jsonb, text) cascade;
drop function if exists public.bdapps_random_password() cascade;
drop function if exists public.bdapps_mark_profile_completed() cascade;
drop function if exists public.bdapps_mark_profile_completed(boolean) cascade;
drop function if exists public.bdapps_mark_profile_completed(text, boolean) cascade;
drop function if exists public.bdapps_fetch_profile(text) cascade;
drop function if exists public.bdapps_lookup_or_create(text) cascade;
drop function if exists public.bdapps_lookup_or_create(text, text) cascade;
drop function if exists public.bdapps_update_profile(text, text, text, int, numeric, numeric, text, text, numeric, numeric, numeric, boolean, boolean, boolean, text, text, text, boolean) cascade;


-- ---------- 2. Drop the legacy bdapps_* columns on user_profiles ----------
-- (The new design keeps `bdapps_mobile` so existing profile data
--  can be looked up by mobile, but the other columns are gone.)
alter table public.user_profiles drop column if exists bdapps_reference_no;
alter table public.user_profiles drop column if exists bdapps_secret;
alter table public.user_profiles drop column if exists bdapps_role;
alter table public.user_profiles drop column if exists profile_completed;


-- ---------- 3. Drop the legacy unique index on bdapps_mobile ----------
drop index if exists public.uniq_user_profiles_bdapps_mobile;
drop index if exists public.idx_user_profiles_profile_completed;


-- ---------- 4. Drop legacy shadow auth.users rows (if any) ----------
-- These were created with bcrypt-hashed random passwords by the
-- previous migrations. We delete them so the new flow can re-create
-- fresh entries via the new lightweight `bdapps_users` table.
-- WARNING: this deletes any data tied to those auth.users rows
-- (sessions, refresh tokens, etc.). It does NOT touch user_profiles.
delete from auth.users
 where email like '%@bdapps.amar-diet.app';


-- ---------- 5. Re-create the `bdapps_users` table if the old migration created it
--      with a different shape. Drop is safe — 46_bdapps_login.sql will recreate it.
drop table if exists public.bdapps_users cascade;


-- ---------- 6. Drop any leftover grants on the dropped functions (idempotent) ----------
-- `cascade` already removed most of these, but revoke is harmless if
-- they still exist.
do $$
begin
  begin revoke execute on function public.bdapps_lookup(text) from anon, authenticated;
  exception when undefined_function then null; end;
  begin revoke execute on function public.bdapps_create_or_get_user(text, text) from anon, authenticated;
  exception when undefined_function then null; end;
  begin revoke execute on function public.bdapps_issue_session(text) from anon, authenticated;
  exception when undefined_function then null; end;
  begin revoke execute on function public.bdapps_admin_create_user(text, text, jsonb) from anon, authenticated;
  exception when undefined_function then null; end;
  begin revoke execute on function public.bdapps_random_password() from anon, authenticated;
  exception when undefined_function then null; end;
  begin revoke execute on function public.bdapps_mark_profile_completed() from authenticated;
  exception when undefined_function then null; end;
  begin revoke execute on function public.bdapps_mark_profile_completed(boolean) from authenticated;
  exception when undefined_function then null; end;
end $$;
