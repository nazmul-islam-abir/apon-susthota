-- ============================================================
-- 32 — Unique username for every user.
-- Apply AFTER 31_email_and_unified_search.sql. Safe to re-run.
--
-- Why this file exists:
--   Two patients may share the same full_name (e.g. "abir" vs
--   "abir"), and the only disambiguator until now was masked
--   mobile + masked email — both heavily obfuscated. Adding a
--   user-chosen username gives every account a stable, copy-
--   paste-able handle, and the people-search RPC switches to
--   exact-match username so caretakers cannot mass-spam connect
--   requests by typing a 2-character prefix.
--
-- Username rules:
--   * 6 characters exactly (locked-in for v1; can relax to 6–10
--     later once we have real usage data)
--   * [A-Za-z0-9_] only
--   * case-insensitive unique
--   * nullable during migration so legacy rows don't violate
-- ============================================================


-- ---------- 1. COLUMN ----------
alter table public.user_profiles
  add column if not exists username text;


-- ---------- 2. CONSTRAINTS ----------
alter table public.user_profiles
  drop constraint if exists user_profiles_username_format;
alter table public.user_profiles
  add constraint user_profiles_username_format
  check (username is null or username ~ '^[A-Za-z0-9_]{6,6}$');


-- ---------- 3. UNIQUE INDEX (case-insensitive) ----------
create unique index if not exists uniq_user_profiles_username
  on public.user_profiles (lower(username))
  where username is not null;


-- ============================================================
-- 4. REWRITE search_people — username-only exact match.
-- ============================================================
--
-- The previous WHERE clause (full_name LIKE, email LIKE, mobile
-- digits LIKE) let a caretaker see every account whose name
-- started with "naz" — way too permissive. The new RPC requires
-- the caller to know the exact 6-char username. No partial /
-- prefix / substring match anywhere.

drop function if exists public.search_people(text, int);
create or replace function public.search_people(
  p_query text,
  p_limit int default 25
)
returns table (
  user_id        uuid,
  username       text,
  full_name      text,
  mobile         text,
  email          text,
  role           text,
  age            int,
  sex            text,
  avatar_url     text,
  is_linked      boolean,
  link_status    text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller      uuid := auth.uid();
  v_caller_role text;
  v_target_role text;
  v_query       text := trim(coalesce(p_query, ''));
  v_lower       text := lower(v_query);
begin
  if v_caller is null then raise exception 'Not authenticated'; end if;
  if length(v_query) < 6 then return; end if;

  select up.role into v_caller_role
    from public.user_profiles up
   where up.user_id = v_caller;
  if v_caller_role is null then
    raise exception 'Profile not found for caller';
  end if;

  v_target_role := case
                     when v_caller_role = 'caretaker' then 'patient'
                     else 'caretaker'
                   end;

  return query
    select up.user_id,
           up.username,
           up.full_name,
           case
             when up.mobile is null then null
             when length(regexp_replace(up.mobile, '\D', '', 'g')) <= 4
               then up.mobile
             else '****' ||
                  right(regexp_replace(up.mobile, '\D', '', 'g'), 4)
           end as mobile,
           case
             when up.email is null then null
             when length(up.email) <= 4 then up.email
             else substr(up.email, 1, 2)
                  || repeat('•', greatest(2, length(up.email) - 4))
                  || '@' || split_part(up.email, '@', 2)
           end as email,
           up.role,
           up.age,
           up.sex,
           up.avatar_url,
           (l.status is not null) as is_linked,
           l.status as link_status
      from public.user_profiles up
      left join public.caretaker_patient_links l
        on ((l.caretaker_user_id = v_caller and l.patient_user_id = up.user_id)
         or (l.patient_user_id = v_caller and l.caretaker_user_id = up.user_id))
       and l.status in ('pending','active')
     where up.role = v_target_role
       and up.username is not null
       and lower(up.username) = v_lower
     order by up.full_name nulls last
     limit greatest(1, least(coalesce(p_limit, 25), 50));
end;
$$;

grant execute on function public.search_people(text, int) to authenticated;


-- ============================================================
-- 5. PUBLIC PROFILE — also expose username.
-- ============================================================
-- Same rationale: anyone who can view the public profile of a
-- user should also be able to see that user's @username so they
-- can share it / copy it for future searches.

drop function if exists public.get_public_profile(uuid);
create or replace function public.get_public_profile(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller uuid := auth.uid();
  v_payload jsonb;
  v_is_linked boolean := false;
  v_link_status text;
begin
  if v_caller is null then raise exception 'Not authenticated'; end if;
  if p_user_id is null then raise exception 'user_id required'; end if;

  select l.status into v_link_status
    from public.caretaker_patient_links l
   where ((l.caretaker_user_id = v_caller and l.patient_user_id = p_user_id)
       or (l.patient_user_id = v_caller and l.caretaker_user_id = p_user_id))
     and l.status in ('pending','active')
   limit 1;
  v_is_linked := v_link_status is not null;

  select jsonb_build_object(
           'user_id',       up.user_id,
           'username',      up.username,
           'full_name',     up.full_name,
           'role',          up.role,
           'caretaker_relationship', up.caretaker_relationship,
           'age',           up.age,
           'sex',           up.sex,
           'avatar_url',    up.avatar_url,
           'mobile',        case
                              when up.mobile is null then null
                              when length(regexp_replace(up.mobile,'\D','','g')) <= 4
                                then up.mobile
                              else '****' ||
                                   right(regexp_replace(up.mobile,'\D','','g'), 4)
                            end,
           'email',         case
                              when up.email is null then null
                              when length(up.email) <= 4 then up.email
                              else substr(up.email, 1, 2)
                                   || repeat('•', greatest(2, length(up.email) - 4))
                                   || '@' || split_part(up.email, '@', 2)
                            end,
           'created_at',    up.created_at,
           'is_linked',     v_is_linked,
           'link_status',   v_link_status,
           'is_self',       (p_user_id = v_caller)
         ) into v_payload
    from public.user_profiles up
   where up.user_id = p_user_id;

  if v_payload is null then
    return jsonb_build_object('found', false);
  end if;

  return v_payload || jsonb_build_object('found', true);
end;
$$;

grant execute on function public.get_public_profile(uuid) to authenticated;


-- ============================================================
-- 6. USERNAME MIRROR ON NEW SIGNUPS — best-effort.
-- ============================================================
-- The auth signup metadata can carry a `username` key from the
-- Flutter client (the onboarding screen collects it before
-- triggering the OTP). We copy it into user_profiles.username if
-- the column exists. If the client forgot to send one, the row
-- is created with username = NULL and the dashboard will nudge
-- the user to claim one later.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_rel  text;
  v_username text;
  v_has_role_cols boolean;
  v_has_username_col boolean;
begin
  -- Detect which optional columns exist in this DB version. Same
  -- pattern as 08_signup_identity.sql: keep the trigger safe to
  -- run against older deploys.
  select exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name   = 'user_profiles'
       and column_name in ('role','caretaker_relationship')
     group by table_name
    having count(*) = 2
  ) into v_has_role_cols;

  select exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name   = 'user_profiles'
       and column_name  = 'username'
  ) into v_has_username_col;

  v_role := lower(trim(coalesce(new.raw_user_meta_data->>'role', '')));
  if v_role not in ('patient', 'caretaker') then
    v_role := 'patient';
  end if;

  v_rel := nullif(trim(coalesce(new.raw_user_meta_data->>'caretaker_relationship', '')), '');
  if v_role = 'caretaker' and v_rel is null then
    v_rel := 'পরিচর্যাকারী';
  end if;
  if v_role = 'patient' then
    v_rel := null;
  end if;

  -- Username — trim/lowercase, then enforce the 6-char regex client-
  -- side already. If invalid or absent, leave NULL so the dashboard
  -- nudge fires.
  if v_has_username_col then
    v_username := nullif(trim(coalesce(new.raw_user_meta_data->>'username', '')), '');
    if v_username is not null and v_username !~ '^[A-Za-z0-9_]{6,6}$' then
      v_username := null;
    end if;
  end if;

  if v_has_role_cols then
    execute $exists$
      select exists (
        select 1 from information_schema.columns
         where table_schema = 'public'
           and table_name   = 'user_profiles'
           and column_name  = 'email'
      )
    $exists$ into v_has_role_cols; -- reuse var for "has email column"

    if v_has_role_cols and v_has_username_col then
      execute $q$
        insert into public.user_profiles (
          user_id, full_name, mobile, email,
          username,
          role, caretaker_relationship,
          age, weight_kg, height_cm
        )
        values (
          $1, $2, $3, lower($7),
          $4,
          $5, $6,
          30, 60.0, 160.0
        )
        on conflict (user_id) do update set
          email = excluded.email
      $q$
      using new.id,
            coalesce(new.raw_user_meta_data->>'full_name', ''),
            coalesce(new.raw_user_meta_data->>'mobile', ''),
            v_username,
            v_role,
            v_rel,
            new.email;
    elsif v_has_role_cols then
      execute $q$
        insert into public.user_profiles (
          user_id, full_name, mobile, email,
          role, caretaker_relationship,
          age, weight_kg, height_cm
        )
        values (
          $1, $2, $3, lower($7),
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
    elsif v_has_username_col then
      execute $q$
        insert into public.user_profiles (
          user_id, full_name, mobile, username,
          age, weight_kg, height_cm
        )
        values (
          $1, $2, $3, $4,
          30, 60.0, 160.0
        )
        on conflict (user_id) do nothing
      $q$
      using new.id,
            coalesce(new.raw_user_meta_data->>'full_name', ''),
            coalesce(new.raw_user_meta_data->>'mobile', ''),
            v_username;
    else
      execute $q$
        insert into public.user_profiles (
          user_id, full_name, mobile,
          age, weight_kg, height_cm
        )
        values (
          $1, $2, $3,
          30, 60.0, 160.0
        )
        on conflict (user_id) do nothing
      $q$
      using new.id,
            coalesce(new.raw_user_meta_data->>'full_name', ''),
            coalesce(new.raw_user_meta_data->>'mobile', '');
    end if;
  else
    -- Pre-28 schema: only legacy columns.
    if v_has_username_col then
      insert into public.user_profiles (
        user_id, full_name, mobile, username, age, weight_kg, height_cm
      )
      values (
        new.id,
        coalesce(new.raw_user_meta_data->>'full_name', ''),
        coalesce(new.raw_user_meta_data->>'mobile', ''),
        v_username,
        30, 60.0, 160.0
      )
      on conflict (user_id) do nothing;
    else
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
  end if;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- ============================================================
-- 7. COMMENTS — keep future migrations aware of the contract.
-- ============================================================
comment on column public.user_profiles.username is
  'User-chosen 6-char handle. Case-insensitive unique. Used by search_people for exact-match lookups. Nullable during migration.';