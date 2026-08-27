-- ============================================================
-- 31 — Email mirror + unified "people you may know" search.
-- Apply AFTER 28_roles_and_caretaker.sql and 29_caretaker_read_rpcs.sql.
--
-- Why this file exists:
--   The original caretaker search only worked by full mobile number
--   (`search_patient_by_mobile`). Caretakers wanted a Facebook-style
--   "find people by name / email" flow, plus the ability to see rich
--   details (name, role, avatar) on a result row. To make that work
--   without leaking PII:
--
--     1. Mirror `auth.users.email` onto `public.user_profiles.email`.
--     2. Add RPCs that search by name OR email OR mobile (unified).
--     3. Add a public-profile RPC that returns the joinable preview
--        fields any signed-in user may see about any other user.
--
-- All RPCs are SECURITY DEFINER + auth.uid() gated so a user can
-- never read another user's clinical fields (HbA1c, BP, weight, …).
--
-- This file is fully idempotent — safe to re-apply.
-- ============================================================


-- ---------- 1. EMAIL COLUMN ON user_profiles ----------
alter table public.user_profiles
  add column if not exists email text;

create unique index if not exists uniq_user_profiles_email_lower
  on public.user_profiles (lower(email))
  where email is not null;

create index if not exists idx_user_profiles_full_name_trgm
  on public.user_profiles (lower(full_name))
  where full_name is not null;

-- Backfill: copy email from auth.users for any profile that doesn't have one.
-- The trigger in 08_signup_identity.sql handles new signups; this picks up
-- rows that were created before the email mirror existed.
do $$
declare
  v_updated int;
begin
  with src as (
    select u.id as user_id, lower(trim(u.email)) as email
      from auth.users u
     where u.email is not null
  )
  update public.user_profiles up
     set email = src.email
    from src
   where up.user_id = src.user_id
     and (up.email is null or up.email = '');
  get diagnostics v_updated = row_count;
  raise notice '[31] backfilled email on % profile rows', v_updated;
end $$;


-- ============================================================
-- 2. SEARCH PEOPLE — FACEBOOK-STYLE UNIFIED SEARCH
-- ============================================================
--
-- `search_people(p_query text, p_limit int)` returns up to [p_limit]
-- rows of (user_id, full_name, mobile, email, role, age, sex,
-- avatar_url, is_linked) where:
--   * the caller is allowed to see them (patient ↔ caretaker)
--   * they match the query by full_name OR email OR last-4-mobile
--   * `is_linked` is true when the caller already has any
--     (pending|active) link to that user
--
-- "Allowed to see them" means:
--   * caller.role = 'caretaker'  → may see patients
--   * caller.role = 'patient'    → may see caretakers
--
-- In both cases the opposite-role gate is enforced; we never expose
-- peers-of-the-same-role (which would be a privacy leak).

drop function if exists public.search_people(text, int);
create or replace function public.search_people(
  p_query text,
  p_limit int default 25
)
returns table (
  user_id        uuid,
  full_name      text,
  mobile         text,   -- masked: "****1234"
  email          text,   -- masked: "r••••@gmail.com"
  role           text,
  age            int,
  sex            text,
  avatar_url     text,
  is_linked      boolean,
  link_status    text    -- 'active' | 'pending' | null
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller   uuid := auth.uid();
  v_caller_role text;
  v_target_role text;
  v_query    text := trim(coalesce(p_query, ''));
  v_digits   text;
  v_lower_q  text;
begin
  if v_caller is null then raise exception 'Not authenticated'; end if;
  if length(v_query) < 2 then return; end if;

  -- Caller's role drives which side of the directory they can see.
  select up.role into v_caller_role
    from public.user_profiles up
   where up.user_id = v_caller;
  if v_caller_role is null then
    raise exception 'Profile not found for caller';
  end if;

  if v_caller_role = 'caretaker' then
    v_target_role := 'patient';
  else
    v_target_role := 'caretaker';
  end if;

  v_lower_q := lower(v_query);
  v_digits  := regexp_replace(v_query, '\D', '', 'g');

  return query
    select up.user_id,
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
       and (
         -- name match (substring, case-insensitive)
         lower(coalesce(up.full_name, '')) like '%' || v_lower_q || '%'
         -- email match
         or lower(coalesce(up.email, '')) like '%' || v_lower_q || '%'
         -- mobile substring (digits only)
         or (length(v_digits) >= 3
             and regexp_replace(coalesce(up.mobile, ''), '\D', '', 'g')
                 like '%' || v_digits || '%')
       )
     order by
       case when lower(coalesce(up.full_name, '')) = v_lower_q then 0
            when lower(coalesce(up.full_name, '')) like v_lower_q || '%' then 1
            else 2 end,
       up.full_name nulls last
     limit greatest(1, least(coalesce(p_limit, 25), 50));
end;
$$;

grant execute on function public.search_people(text, int) to authenticated;


-- ============================================================
-- 3. PUBLIC PROFILE — read-only preview of any user
-- ============================================================
--
-- Returns the joinable preview columns for a single user_id.
-- No clinical data is exposed; that's gated behind the active-link
-- caretaker RPCs in 29_*.

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

  -- Is the caller linked (any state) to this user?
  select l.status into v_link_status
    from public.caretaker_patient_links l
   where ((l.caretaker_user_id = v_caller and l.patient_user_id = p_user_id)
       or (l.patient_user_id = v_caller and l.caretaker_user_id = p_user_id))
     and l.status in ('pending','active')
   limit 1;
  v_is_linked := v_link_status is not null;

  select jsonb_build_object(
    'user_id',       up.user_id,
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
-- 4. PATIENT INBOX — join caretaker names so the inbox is
--    actually useful (the original implementation showed a
--    generic "কেয়ারটেকার" label because the row didn't carry
--    the caretaker's full_name).
-- ============================================================

-- 4a. Pending incoming requests — JOIN caretaker's full_name.
drop function if exists public.get_inbox_pending_links();
create or replace function public.get_inbox_pending_links()
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
    select l.id                as link_id,
           l.caretaker_user_id,
           l.patient_user_id,
           l.status,
           l.request_note,
           l.caretaker_relationship,
           l.requested_at,
           l.responded_at,
           up.full_name         as caretaker_full_name,
           up.email             as caretaker_email,
           up.avatar_url        as caretaker_avatar_url,
           up.age               as caretaker_age,
           up.sex               as caretaker_sex
      from public.caretaker_patient_links l
      join public.user_profiles up on up.user_id = l.caretaker_user_id
     where l.patient_user_id = v_patient
       and l.status          = 'pending'
  ) t;

  return v_payload;
end;
$$;

grant execute on function public.get_inbox_pending_links() to authenticated;


-- 4b. Active caretakers — also join name + last_seen + avatar.
drop function if exists public.get_inbox_active_caretakers();
create or replace function public.get_inbox_active_caretakers()
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

  select coalesce(jsonb_agg(row_to_json(t) order by t.responded_at desc nulls last), '[]'::jsonb)
    into v_payload
  from (
    select l.id                as link_id,
           l.caretaker_user_id,
           l.patient_user_id,
           l.status,
           l.caretaker_relationship,
           l.requested_at,
           l.responded_at,
           l.last_seen_at,
           up.full_name         as caretaker_full_name,
           up.email             as caretaker_email,
           up.avatar_url        as caretaker_avatar_url,
           up.age               as caretaker_age,
           up.sex               as caretaker_sex
      from public.caretaker_patient_links l
      join public.user_profiles up on up.user_id = l.caretaker_user_id
     where l.patient_user_id = v_patient
       and l.status          = 'active'
  ) t;

  return v_payload;
end;
$$;

grant execute on function public.get_inbox_active_caretakers() to authenticated;


-- ============================================================
-- 5. EMAIL MIRROR ON NEW SIGNUPS
-- ============================================================
-- Updated 08_signup_identity.sql's `handle_new_user` to also copy
-- `new.email` into `public.user_profiles.email` so newly created
-- rows are immediately searchable by email. The backfill above
-- catches anything that already existed.
--
-- The trigger lives in 08_signup_identity.sql; this comment block
-- documents the cross-file contract so future migrations stay
-- aware of the dependency.
-- ============================================================