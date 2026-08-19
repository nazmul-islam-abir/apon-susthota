-- ============================================================
-- Amar Diet — Daily activity metrics (water / heart rate / steps)
-- Apply AFTER 01_schema.sql.
--
-- What this file does:
--   1. Creates `public.daily_metrics` — one row per user per day for
--      water_liters, heart_rate_bpm, steps. The workout screen
--      "আমার কার্যকলাপ" card reads from this instead of fabricating
--      numbers from completion totals.
--   2. Provides `get_today_daily_metrics()` RPC that returns the
--      authoritative row for "today" (or a zero row if none yet).
--   3. Provides `upsert_daily_metric(p_field, p_value)` RPC so the
--      app can update a single field without round-tripping the
--      whole row. Validates the field name and clamps the value
--      to a sane range.
-- ============================================================

create table if not exists public.daily_metrics (
  user_id          uuid primary key references auth.users(id) on delete cascade,
  metric_date      date not null default current_date,
  water_liters     numeric(5,2) not null default 0 check (water_liters >= 0 and water_liters <= 20),
  heart_rate_bpm   int          not null default 0 check (heart_rate_bpm between 30 and 230),
  steps            int          not null default 0 check (steps >= 0 and steps <= 200000),
  updated_at       timestamptz  not null default now(),
  created_at       timestamptz  not null default now()
);

create index if not exists idx_daily_metrics_date
  on public.daily_metrics (user_id, metric_date desc);

alter table public.daily_metrics enable row level security;

drop policy if exists "daily_metrics self read"  on public.daily_metrics;
drop policy if exists "daily_metrics self write" on public.daily_metrics;

create policy "daily_metrics self read"
  on public.daily_metrics for select
  using (auth.uid() = user_id);

create policy "daily_metrics self write"
  on public.daily_metrics for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Update updated_at automatically on row update
create or replace function public.daily_metrics_touch_updated_at()
returns trigger as $$
begin
  new.updated_at := now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_daily_metrics_touch on public.daily_metrics;
create trigger trg_daily_metrics_touch
  before update on public.daily_metrics
  for each row execute function public.daily_metrics_touch_updated_at();

-- ─── get_today_daily_metrics ─────────────────────────────────────
-- Returns one row for today (server local date is fine — both
-- client and server use Bangladesh time via the auth context).
drop function if exists public.get_today_daily_metrics();
create or replace function public.get_today_daily_metrics()
returns table (
  water_liters   numeric,
  heart_rate_bpm int,
  steps          int,
  has_data       boolean
)
language plpgsql security definer set search_path = public, auth as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    return query select 0::numeric, 0, 0, false;
    return;
  end if;

  return query
    select coalesce(dm.water_liters, 0)::numeric,
           coalesce(dm.heart_rate_bpm, 0),
           coalesce(dm.steps, 0),
           (dm.user_id is not null) as has_data
    from (select v_user as uid) u
    left join public.daily_metrics dm
      on dm.user_id = u.uid and dm.metric_date = current_date;

  -- Synthesize the empty row when the user has no row at all today.
  if not exists (
    select 1 from public.daily_metrics
    where user_id = v_user and metric_date = current_date
  ) then
    return query select 0::numeric, 0, 0, false;
  end if;
end;
$$;

-- ─── upsert_daily_metric ──────────────────────────────────────────
-- Field name is whitelisted — string-concat-into-SQL is unsafe, so
-- we use a CASE expression. p_value is clamped server-side too.
drop function if exists public.upsert_daily_metric(text, numeric);
create or replace function public.upsert_daily_metric(
  p_field text,
  p_value numeric
)
returns public.daily_metrics
language plpgsql security definer set search_path = public, auth as $$
declare
  v_user uuid := auth.uid();
  v_row  public.daily_metrics;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  insert into public.daily_metrics (user_id, metric_date)
    values (v_user, current_date)
    on conflict (user_id) do nothing;

  update public.daily_metrics as dm
    set water_liters   = case when p_field = 'water_liters'
                              then least(greatest(p_value, 0), 20)::numeric(5,2)
                              else dm.water_liters end,
        heart_rate_bpm = case when p_field = 'heart_rate_bpm'
                              then least(greatest(p_value::int, 30), 230)
                              else dm.heart_rate_bpm end,
        steps          = case when p_field = 'steps'
                              then least(greatest(p_value::int, 0), 200000)
                              else dm.steps end
    where dm.user_id = v_user and dm.metric_date = current_date
    returning * into v_row;

  return v_row;
end;
$$;

-- Convenience: log +N liters atomically without round-tripping the
-- current value (saves a read for the common "+0.25L" tap).
drop function if exists public.add_water_liters(numeric);
create or replace function public.add_water_liters(p_delta numeric)
returns public.daily_metrics
language plpgsql security definer set search_path = public, auth as $$
declare
  v_user uuid := auth.uid();
  v_row  public.daily_metrics;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  insert into public.daily_metrics (user_id, metric_date, water_liters)
    values (v_user, current_date, greatest(p_delta, 0)::numeric(5,2))
    on conflict (user_id) do nothing;

  update public.daily_metrics as dm
    set water_liters = least(greatest(coalesce(dm.water_liters,0) + p_delta, 0), 20)::numeric(5,2)
    where dm.user_id = v_user and dm.metric_date = current_date
    returning * into v_row;

  return v_row;
end;
$$;
