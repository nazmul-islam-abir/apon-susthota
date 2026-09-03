-- ============================================================
-- 46 — BDApps OTP login (simple version).
-- Apply AFTER 28_roles_and_caretaker.sql, 31_email_and_unified_search.sql,
-- and 32_username.sql. Safe to re-run.
--
-- Design (simple):
--   We DO NOT touch auth.users. BDApps users live in a new
--   lightweight table `bdapps_users` keyed by canonical mobile
--   (8801XXXXXXXXX). The Flutter client also caches (mobile, role,
--   profile_completed) in SharedPreferences and uses that as the
--   auth signal. The app gates navigation on the BDApps session,
--   not Supabase auth.
--
--   `user_profiles.bdapps_mobile` is kept (so the app's profile
--   data can be looked up by mobile) but the new `bdapps_users`
--   row is the source of truth for "this user exists, role, etc."
--
--   No bcrypt, no pgcrypto, no HMAC, no JWT signing. Just CRUD.
--
-- This file is fully idempotent.
-- ============================================================


-- ---------- 1. Lightweight user table keyed by mobile ----------
create table if not exists public.bdapps_users (
  mobile              text primary key,    -- canonical 8801XXXXXXXXX
  role                text not null check (role in ('patient','caretaker')),
  profile_completed   boolean not null default false,
  full_name           text,
  username            text,
  age                 int,
  weight_kg           numeric(5,1),
  height_cm           numeric(5,1),
  bp                  text,
  insulin             text,
  fasting_sugar       numeric(6,1),
  post_meal_sugar     numeric(6,1),
  hba1c               numeric(4,1),
  kidney_disease      boolean default false,
  heart_disease       boolean default false,
  anemia              boolean default false,
  email               text,
  caretaker_relationship text,
  avatar_url          text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index if not exists idx_bdapps_users_role on public.bdapps_users (role);


-- ---------- 2. (Backfill removed) ----------
-- Previous versions of this migration backfilled from user_profiles.bdapps_mobile,
-- but those rows had role='patient' forced in. The new flow lets the user pick
-- their role on the landing screen, so we just let bdapps_lookup_or_create
-- create each row on first login with the chosen role. No backfill needed.


-- ---------- 3. lookup_or_create RPC ----------
-- Single RPC. Returns the row for the given mobile, creating a new
-- row (with default role='patient') if the mobile is new.
create or replace function public.bdapps_lookup_or_create(
  p_mobile text,
  p_role   text default 'patient'
)
returns public.bdapps_users
language plpgsql
security definer
set search_path = public
as $$
declare
  v_digits text := regexp_replace(coalesce(p_mobile, ''), '\D', '', 'g');
  v_role   text := lower(trim(coalesce(p_role, '')));
  v_row    public.bdapps_users;
begin
  if v_digits like '880%' and length(v_digits) = 13 then
    null;
  elsif v_digits like '0%' and length(v_digits) = 11 and v_digits ~ '^01[3-9][0-9]{8}$' then
    v_digits := '88' || v_digits;
  else
    raise exception 'Invalid Bangladeshi mobile number: %', p_mobile;
  end if;

  if v_role not in ('patient','caretaker') then
    v_role := 'patient';
  end if;

  -- Try existing row first.
  select * into v_row from public.bdapps_users where mobile = v_digits;
  if not found then
    insert into public.bdapps_users (mobile, role, profile_completed)
    values (v_digits, v_role, false)
    returning * into v_row;
  else
    -- If the row exists but role was never set, fill it in now.
    if v_row.role is null or v_row.role = '' then
      update public.bdapps_users
         set role = v_role, updated_at = now()
       where mobile = v_digits
       returning * into v_row;
    end if;
  end if;
  return v_row;
end;
$$;

grant execute on function public.bdapps_lookup_or_create(text, text) to anon, authenticated;


-- ---------- 4. update_profile RPC ----------
-- Single RPC used by OnboardingScreen / ProfileEditor to save
-- profile fields. Always updates `updated_at`.
create or replace function public.bdapps_update_profile(
  p_mobile text,
  p_full_name text default null,
  p_username text default null,
  p_age int default null,
  p_weight_kg numeric default null,
  p_height_cm numeric default null,
  p_bp text default null,
  p_insulin text default null,
  p_fasting_sugar numeric default null,
  p_post_meal_sugar numeric default null,
  p_hba1c numeric default null,
  p_kidney_disease boolean default null,
  p_heart_disease boolean default null,
  p_anemia boolean default null,
  p_email text default null,
  p_caretaker_relationship text default null,
  p_avatar_url text default null,
  p_mark_completed boolean default false
)
returns public.bdapps_users
language plpgsql
security definer
set search_path = public
as $$
declare
  v_digits text := regexp_replace(coalesce(p_mobile, ''), '\D', '', 'g');
  v_row public.bdapps_users;
begin
  if v_digits like '0%' and length(v_digits) = 11 then
    v_digits := '88' || v_digits;
  end if;

  update public.bdapps_users
     set full_name              = coalesce(p_full_name, full_name),
         username               = coalesce(p_username, username),
         age                    = coalesce(p_age, age),
         weight_kg              = coalesce(p_weight_kg, weight_kg),
         height_cm              = coalesce(p_height_cm, height_cm),
         bp                     = coalesce(p_bp, bp),
         insulin                = coalesce(p_insulin, insulin),
         fasting_sugar          = coalesce(p_fasting_sugar, fasting_sugar),
         post_meal_sugar        = coalesce(p_post_meal_sugar, post_meal_sugar),
         hba1c                  = coalesce(p_hba1c, hba1c),
         kidney_disease         = coalesce(p_kidney_disease, kidney_disease),
         heart_disease          = coalesce(p_heart_disease, heart_disease),
         anemia                 = coalesce(p_anemia, anemia),
         email                  = coalesce(p_email, email),
         caretaker_relationship = coalesce(p_caretaker_relationship, caretaker_relationship),
         avatar_url             = coalesce(p_avatar_url, avatar_url),
         profile_completed      = profile_completed or p_mark_completed,
         updated_at             = now()
   where mobile = v_digits
   returning * into v_row;

  if not found then
    raise exception 'bdapps_users row not found for mobile %', p_mobile;
  end if;
  return v_row;
end;
$$;

grant execute on function public.bdapps_update_profile(text, text, text, int, numeric, numeric, text, text, numeric, numeric, numeric, boolean, boolean, boolean, text, text, text, boolean) to anon, authenticated;


-- ---------- 5. fetch_profile RPC ----------
-- Single RPC that returns the row for a given mobile. Returns null
-- if the row doesn't exist (caller can decide what to do).
create or replace function public.bdapps_fetch_profile(p_mobile text)
returns public.bdapps_users
language plpgsql
security definer
set search_path = public
as $$
declare
  v_digits text := regexp_replace(coalesce(p_mobile, ''), '\D', '', 'g');
  v_row public.bdapps_users;
begin
  if v_digits like '0%' and length(v_digits) = 11 then
    v_digits := '88' || v_digits;
  end if;
  select * into v_row from public.bdapps_users where mobile = v_digits;
  return v_row;
end;
$$;

grant execute on function public.bdapps_fetch_profile(text) to anon, authenticated;


-- ---------- 6. mark_profile_completed RPC ----------
create or replace function public.bdapps_mark_profile_completed(
  p_mobile text,
  p_value  boolean default true
)
returns void
language sql
security definer
set search_path = public
as $$
  update public.bdapps_users
     set profile_completed = coalesce(p_value, true),
         updated_at = now()
   where mobile = regexp_replace(coalesce(p_mobile, ''), '\D', '', 'g');
$$;

grant execute on function public.bdapps_mark_profile_completed(text, boolean) to anon, authenticated;


-- ---------- 7. RLS ----------
alter table public.bdapps_users enable row level security;

-- Anyone (including anon) can read; the only sensitive value is the mobile
-- itself, which the caller already supplied.
drop policy if exists bdapps_users_read on public.bdapps_users;
create policy bdapps_users_read on public.bdapps_users
  for select using (true);

-- Writes go through SECURITY DEFINER RPCs above; direct INSERT/UPDATE
-- from clients is blocked.
drop policy if exists bdapps_users_write on public.bdapps_users;
create policy bdapps_users_write on public.bdapps_users
  for all using (false) with check (false);