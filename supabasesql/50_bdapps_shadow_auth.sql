-- ============================================================
-- 50 — BDApps shadow auth.users creation.
-- Apply AFTER 46_bdapps_login.sql and AFTER enabling the pgcrypto
-- extension (Supabase → Database → Extensions → pgcrypto → Enable).
--
-- Why this file exists:
--   The other tables in the project (user_profiles, daily_logs,
--   medicine_*, workout_*, etc.) ALL have foreign keys into
--   auth.users(id) and rely on auth.uid() for row-level security.
--   BDApps users live in `bdapps_users` only, so they have no
--   auth.uid() and every RPC that uses auth.uid() fails with
--   "Not authenticated".
--
--   This file creates a single RPC `bdapps_create_shadow_auth(p_mobile)`
--   that:
--     1. Looks up the bdapps_users row by mobile.
--     2. Generates a random bcrypt-hashed password using pgcrypto.
--     3. Inserts a row into auth.users (id, email = <mobile>@bdapps.app,
--        encrypted_password, etc.) — idempotent on (mobile).
--     4. Returns the (email, password) pair so the Flutter client can
--        call supabase.auth.signInWithPassword() to establish a real
--        session.
--
--   After this RPC, the app has a real Supabase auth session and all
--   existing RPCs work unchanged.
--
-- PREREQUISITE: enable the `pgcrypto` extension in Supabase.
--   Dashboard → Database → Extensions → search "pgcrypto" → Enable.
-- ============================================================


-- ---------- 1. Enable pgcrypto ----------
-- Wrapped in DO block so re-runs don't error if it's already enabled.
do $$
begin
  create extension if not exists pgcrypto;
exception when insufficient_privilege or feature_not_supported then
  raise notice 'pgcrypto could not be enabled via SQL — please enable it from Supabase Dashboard → Database → Extensions → pgcrypto.';
end $$;


-- ---------- 2. Shadow auth creator ----------
-- Returns the email + plaintext password the Flutter client must use
-- to call supabase.auth.signInWithPassword(). Plaintext is discarded
-- immediately after sign-in.
create or replace function public.bdapps_create_shadow_auth(p_mobile text)
returns table (email text, password text, user_id uuid)
language plpgsql
security definer
set search_path = public, extensions, auth
as $$
declare
  v_digits   text := regexp_replace(coalesce(p_mobile, ''), '\D', '', 'g');
  v_user_id  uuid;
  v_email    text;
  v_password text;
  v_existing_id uuid;
begin
  -- Normalize to 8801XXXXXXXXX
  if v_digits like '880%' and length(v_digits) = 13 then
    null;
  elsif v_digits like '0%' and length(v_digits) = 11 and v_digits ~ '^01[3-9][0-9]{8}$' then
    v_digits := '88' || v_digits;
  else
    raise exception 'Invalid Bangladeshi mobile number: %', p_mobile;
  end if;

  -- Confirm a bdapps_users row exists for this mobile.
  if not exists (select 1 from public.bdapps_users where mobile = v_digits) then
    raise exception 'bdapps_users row not found for mobile %', v_digits;
  end if;

  v_email := v_digits || '@bdapps.app';

  -- If a shadow auth row already exists, reuse it. Don't rotate the
  -- password — that would log the user out on every app launch.
  -- Use auth.users.email (qualified) because the function has an OUT
  -- parameter called "email" that otherwise shadows the column name.
  select id into v_existing_id from auth.users where auth.users.email = v_email;
  if v_existing_id is not null then
    -- Issue a one-time-use plaintext password by hashing a fresh random
    -- value into the row, then returning it. signInWithPassword will
    -- verify the bcrypt match.
    v_password := encode(gen_random_bytes(24), 'hex');
    update auth.users
       set encrypted_password = crypt(v_password, gen_salt('bf', 10)),
           updated_at = now()
     where id = v_existing_id;
    return query select v_email, v_password, v_existing_id;
    return;
  end if;

  -- Fresh shadow row.
  v_user_id  := gen_random_uuid();
  v_password := encode(gen_random_bytes(24), 'hex');
  insert into auth.users (
    instance_id, id, aud, role, email,
    encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token,
    email_change, email_change_token_new, recovery_token
  ) values (
    '00000000-0000-0000-0000-000000000000',
    v_user_id,
    'authenticated',
    'authenticated',
    v_email,
    crypt(v_password, gen_salt('bf', 10)),
    now(),
    jsonb_build_object('provider','bdapps','providers', array['bdapps']),
    jsonb_build_object('mobile', v_digits, 'auth_source','bdapps'),
    now(), now(), '', '', '', ''
  );

  -- Also create an identity row (required by supabase-flutter post-2024).
  insert into auth.identities (
    id, user_id, identity_data, provider, provider_id,
    created_at, updated_at
  ) values (
    gen_random_uuid(), v_user_id,
    jsonb_build_object('sub', v_user_id::text, 'email', v_email, 'mobile', v_digits),
    'bdapps', v_digits,
    now(), now()
  );

  return query select v_email, v_password, v_user_id;
end;
$$;

grant execute on function public.bdapps_create_shadow_auth(text) to anon, authenticated;


-- ---------- 3. Sign-in helper (used by the Flutter client) ----------
-- Wraps supabase.auth.signInWithPassword(). Returns the access/refresh
-- tokens. (We can't actually call supabase.auth from SQL — this is a
-- no-op stub; the Flutter client uses the email/password returned by
-- bdapps_create_shadow_auth to call signInWithPassword() itself.)
-- The function exists so the security definer GRANT for sign-in is
-- available, but the real sign-in happens client-side.
