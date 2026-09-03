-- ============================================================
-- 52 — Re-create missing BDApps lookup structures.
--
-- Why this file exists:
--   The table public.bdapps_users and the function
--   public.bdapps_lookup_or_create were missing, likely due to
--   a previous cleanup script. This file ensures the base table
--   and the necessary functions are restored.
-- ============================================================

-- ---------- 1. Re-create the table ----------
create table if not exists public.bdapps_users (
  mobile              text primary key,
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

-- ---------- 2. Re-create the lookup function ----------
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
