-- ============================================================
-- Amar Diet — Daily activity metrics (water / heart rate / steps)
-- Apply AFTER 01_schema.sql.
--
-- What this file does:
--   1. Creates `public.daily_metrics` — one row per user per day.
--   2. Provides `get_today_daily_metrics()` RPC for local day.
--   3. Provides `upsert_daily_metric(p_field, p_value)` RPC.
--   4. Provides `add_water_liters(p_delta)` for atomic increments.
-- ============================================================

create table if not exists public.daily_metrics (
  user_id          uuid references auth.users(id) on delete cascade,
  -- Default uses the user's LOCAL day (Asia/Dhaka) so any future
  -- INSERT that omits `metric_date` stays consistent with
  -- `log_water_event`, `get_today_daily_metrics`, and
  -- `upsert_daily_metric`. Previously `current_date` (UTC server)
  -- meant writes after 18:00 UTC landed on yesterday's row.
  metric_date      date not null default ((now() at time zone 'Asia/Dhaka')::date),
  water_liters     numeric(5,2) not null default 0 check (water_liters >= 0 and water_liters <= 20),
  heart_rate_bpm   int          not null default 0 check (heart_rate_bpm between 0 and 230),
  steps            int          not null default 0 check (steps >= 0 and steps <= 200000),
  updated_at       timestamptz  not null default now(),
  created_at       timestamptz  not null default now(),
  primary key (user_id, metric_date)
);

-- ─── Repair existing CHECK constraints ──────────────────────────────
-- `create table if not exists` does NOT update existing CHECK constraints,
-- so on installs created by an earlier version of this file the
-- heart_rate_bpm and steps columns may still have stricter bounds
-- (e.g. heart_rate_bpm > 40). That rejects any daily_metrics write where
-- the unused columns default to 0, which is exactly what happens when
-- the water RPC inserts a row.
--
-- Drop the named constraints (if they exist) and recreate them with
-- the bounds declared above. Idempotent — safe to re-run.
do $$
begin
  if exists (
    select 1 from pg_constraint
    where conname = 'daily_metrics_heart_rate_bpm_check'
      and conrelid = 'public.daily_metrics'::regclass
  ) then
    alter table public.daily_metrics
      drop constraint daily_metrics_heart_rate_bpm_check;
  end if;
  if exists (
    select 1 from pg_constraint
    where conname = 'daily_metrics_steps_check'
      and conrelid = 'public.daily_metrics'::regclass
  ) then
    alter table public.daily_metrics
      drop constraint daily_metrics_steps_check;
  end if;
  if exists (
    select 1 from pg_constraint
    where conname = 'daily_metrics_water_liters_check'
      and conrelid = 'public.daily_metrics'::regclass
  ) then
    alter table public.daily_metrics
      drop constraint daily_metrics_water_liters_check;
  end if;
end $$;

alter table public.daily_metrics
  add constraint daily_metrics_heart_rate_bpm_check
  check (heart_rate_bpm between 0 and 230);
alter table public.daily_metrics
  add constraint daily_metrics_steps_check
  check (steps >= 0 and steps <= 200000);
alter table public.daily_metrics
  add constraint daily_metrics_water_liters_check
  check (water_liters >= 0 and water_liters <= 20);

-- Migration for existing single-PK installs:
do $$
begin
  if (select count(*) from information_schema.table_constraints
      where table_name = 'daily_metrics' and constraint_type = 'PRIMARY KEY') > 0
     and not exists (
      select 1 from information_schema.key_column_usage
      where table_name = 'daily_metrics' and column_name = 'metric_date'
     )
  then
    alter table public.daily_metrics drop constraint daily_metrics_pkey;
    alter table public.daily_metrics add primary key (user_id, metric_date);
  end if;
end $$;

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
-- Returns one row for today (server local date).
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
      -- Read the row that was written for the user's LOCAL day, not
      -- the UTC server day. `log_water_event` writes with
      -- `(occurred_at at time zone 'Asia/Dhaka')::date`, so this
      -- needs to match — otherwise on a UTC-hosted server after
      -- 18:00 UTC (= 00:00 Asia/Dhaka next day) the read finds no
      -- row and the Flutter client overwrites the optimistic +0.25 L
      -- bump back to zero.
      on dm.user_id = u.uid
     and dm.metric_date = ((now() at time zone 'Asia/Dhaka')::date);
end;
$$;

-- ─── upsert_daily_metric ──────────────────────────────────────────
-- Always returns the row that exists for (auth.uid(), local-day-date)
-- after the call. Uses `insert … on conflict do update … returning *`
-- so v_row is guaranteed to be non-null on every invocation (the
-- earlier insert-then-update pattern returned NULL whenever the
-- update matched zero rows, which made the client think the write
-- failed even when the row was correctly created).
--
-- "local day" = Asia/Dhaka calendar day. `log_water_event` writes
-- with `(occurred_at at time zone 'Asia/Dhaka')::date` and
-- `get_today_daily_metrics` reads by the same key — this function
-- must use the same key or any direct caller (setWaterLiters,
-- setHeartRate, setSteps) will silently write to the wrong day's
-- row on a UTC-hosted server after 18:00 UTC.
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
  v_day  date := ((now() at time zone 'Asia/Dhaka')::date);
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  if p_field = 'water_liters' then
    insert into public.daily_metrics (user_id, metric_date, water_liters)
      values (v_user, v_day, least(greatest(p_value, 0), 20)::numeric(5,2))
      on conflict (user_id, metric_date) do update
        set water_liters = least(greatest(p_value, 0), 20)::numeric(5,2)
      returning * into v_row;
  elsif p_field = 'heart_rate_bpm' then
    insert into public.daily_metrics (user_id, metric_date, heart_rate_bpm)
      values (v_user, v_day, least(greatest(p_value, 0), 230)::int)
      on conflict (user_id, metric_date) do update
        set heart_rate_bpm = least(greatest(p_value, 0), 230)::int
      returning * into v_row;
  elsif p_field = 'steps' then
    insert into public.daily_metrics (user_id, metric_date, steps)
      values (v_user, v_day, least(greatest(p_value, 0), 200000)::int)
      on conflict (user_id, metric_date) do update
        set steps = least(greatest(p_value, 0), 200000)::int
      returning * into v_row;
  else
    raise exception 'invalid field: %', p_field;
  end if;

  return v_row;
end;
$$;

-- ─── add_water_liters ────────────────────────────────────────────
-- Atomic +N liters write. Returns the post-increment row so the
-- client can use it as the new source of truth.
--
-- Writes to the user's LOCAL day (Asia/Dhaka) so any caller — present
-- or future — stays consistent with `log_water_event` and
-- `get_today_daily_metrics`.
drop function if exists public.add_water_liters(numeric);
create or replace function public.add_water_liters(p_delta numeric)
returns public.daily_metrics
language plpgsql security definer set search_path = public, auth as $$
declare
  v_user uuid := auth.uid();
  v_row  public.daily_metrics;
  v_day  date := ((now() at time zone 'Asia/Dhaka')::date);
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  insert into public.daily_metrics (user_id, metric_date, water_liters)
    values (v_user, v_day, least(greatest(p_delta, 0), 20)::numeric(5,2))
    on conflict (user_id, metric_date) do update
    set water_liters = least(greatest(coalesce(public.daily_metrics.water_liters, 0) + p_delta, 0), 20)::numeric(5,2)
    returning * into v_row;

  return v_row;
end;
$$;


-- ============================================================
-- Water intake event log + analytics
-- Run this section AFTER the daily_metrics block above.
--
-- What this section adds:
--   1. `water_intake_log` — one row per glass the user logs,
--      tagged with the time-of-day bucket server-side so the
--      analytics screen can break down "when in the day" the
--      user is falling short.
--   2. `daily_water_summary` — end-of-day snapshot of total
--      glasses + per-bucket distribution. Populated by
--      `reset_daily_water_task()` which runs on a date rollover.
--   3. RPCs:
--        • log_water_event(p_delta, p_occurred_at)  — write one event
--        • get_water_analytics(p_days)              — last N days summary
--        • reset_daily_water_task()                 — daily rollover
-- ============================================================

-- ─── water_intake_log ──────────────────────────────────────────────
-- IMMUTABLE helper: stamp a timestamptz with an Asia/Dhaka calendar
-- date (yyyy-mm-dd text). All arithmetic here uses operators that
-- Postgres marks IMMUTABLE — we avoid `AT TIME ZONE` (which PG marks
-- STABLE) and instead compute the +06:00 date directly from the
-- epoch via `extract`/arithmetic on the timestamptz value. Asia/Dhaka
-- is fixed-offset (UTC+6, no DST) so the math is correct every day.
create or replace function public.bn_date(timestamptz)
returns text
language sql
immutable
parallel safe
strict
as $$
  -- Convert the timestamptz to seconds since the Unix epoch, add the
  -- Asia/Dhaka offset (6 hours = 21600 seconds), then split into
  -- days-since-epoch and remainder. The whole expression is built
  -- out of IMMUTABLE arithmetic.
  with secs as (
    select extract(epoch from $1)::bigint + 21600 as s
  ),
  days as (
    select (s / 86400)::bigint as d, (s % 86400)::int as r from secs
  )
  -- Build the date via `date '1970-01-01' + integer` arithmetic
  -- (note: `date + bigint` is not a built-in — only `date + integer`,
  -- so cast the days-since-epoch down to int before adding). Then
  -- format via the IMMUTABLE `to_char(timestamp, text)`.
  select to_char(
    ((date '1970-01-01' + ((select d from days)::int))::timestamp),
    'YYYY-MM-DD'
  );
$$;

create table if not exists public.water_intake_log (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  occurred_at   timestamptz not null default now(),
  -- Generated Asia/Dhaka calendar date (yyyy-mm-dd text) via the
  -- IMMUTABLE helper above. The column is stored so it can be
  -- indexed directly.
  occurred_date text generated always as (public.bn_date(occurred_at)) stored,
  liters        numeric(5,2) not null check (liters > 0 and liters <= 4),
  bucket        text not null check (bucket in ('morning','noon','afternoon','night'))
);
-- Repair block for installs that already have water_intake_log from
-- an earlier version of this file (the old version had no
-- `occurred_date` column and was indexed on `(occurred_at::date)`,
-- which Postgres rejects as IMMUTABLE-violating). Drop the broken
-- index if it lingered and the stale column if any, then re-add the
-- column with the IMMUTABLE-helper expression. Both statements are
-- no-ops on a fresh install.
drop index if exists public.idx_water_intake_log_user_day;
alter table public.water_intake_log
  drop column if exists occurred_date;
alter table public.water_intake_log
  add column occurred_date text
  generated always as (public.bn_date(occurred_at)) stored;
-- The `occurred_date` column is filled automatically by Postgres
-- (both for new rows on insert and for any pre-existing rows when
-- the column was added above in the repair block). Now create the
-- index that depends on it.
create index if not exists idx_water_intake_log_user_day
  on public.water_intake_log (user_id, occurred_date desc);

alter table public.water_intake_log enable row level security;
drop policy if exists "water_intake_log self read"  on public.water_intake_log;
drop policy if exists "water_intake_log self write" on public.water_intake_log;
create policy "water_intake_log self read"
  on public.water_intake_log for select
  using (auth.uid() = user_id);
create policy "water_intake_log self write"
  on public.water_intake_log for insert
  with check (auth.uid() = user_id);

-- ─── daily_water_summary ───────────────────────────────────────────
create table if not exists public.daily_water_summary (
  user_id        uuid not null references auth.users(id) on delete cascade,
  metric_date    date not null,
  glasses_total  int  not null default 0 check (glasses_total >= 0),
  liters_total   numeric(5,2) not null default 0 check (liters_total >= 0),
  bucket_morning int  not null default 0,
  bucket_noon    int  not null default 0,
  bucket_afternoon int not null default 0,
  bucket_night   int  not null default 0,
  target_hit     boolean not null default false,
  created_at     timestamptz not null default now(),
  primary key (user_id, metric_date)
);
create index if not exists idx_daily_water_summary_user_date
  on public.daily_water_summary (user_id, metric_date desc);

alter table public.daily_water_summary enable row level security;
drop policy if exists "daily_water_summary self read" on public.daily_water_summary;
create policy "daily_water_summary self read"
  on public.daily_water_summary for select
  using (auth.uid() = user_id);

-- ─── log_water_event ───────────────────────────────────────────────
-- Writes one event to water_intake_log AND mirrors the running total
-- into daily_metrics (single source of truth = daily_metrics for the
-- current day's "liters", and the event log for analytics).
drop function if exists public.log_water_event(numeric, timestamptz);
create or replace function public.log_water_event(
  p_delta     numeric,
  p_occurred_at timestamptz default now()
)
returns public.water_intake_log
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user   uuid := auth.uid();
  v_liters numeric := least(greatest(p_delta, 0), 4)::numeric(5,2);
  v_bucket text;
  v_hour   int := extract(hour from (p_occurred_at at time zone 'Asia/Dhaka'));
  v_row    public.water_intake_log;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;
  if v_liters <= 0 then
    raise exception 'delta must be > 0';
  end if;

  -- Bucket by hour in Asia/Dhaka so the analytics view matches the
  -- client's expectations regardless of where Postgres is hosted.
  if v_hour >= 5  and v_hour < 11 then v_bucket := 'morning';
  elsif v_hour >= 11 and v_hour < 15 then v_bucket := 'noon';
  elsif v_hour >= 15 and v_hour < 19 then v_bucket := 'afternoon';
  else v_bucket := 'night';
  end if;

  insert into public.water_intake_log (user_id, occurred_at, liters, bucket)
    values (v_user, p_occurred_at, v_liters, v_bucket)
    returning * into v_row;

  -- Mirror to daily_metrics so the existing "today's total" reads
  -- still work without a schema change for callers.
  insert into public.daily_metrics (user_id, metric_date, water_liters)
    values (v_user, (p_occurred_at at time zone 'Asia/Dhaka')::date, v_liters)
    on conflict (user_id, metric_date) do update
    set water_liters = least(greatest(
      coalesce(public.daily_metrics.water_liters, 0) + v_liters, 0), 20)::numeric(5,2);

  return v_row;
end;
$$;

-- ─── reset_daily_water_task ────────────────────────────────────────
-- Snapshots yesterday's water intake into daily_water_summary so the
-- analytics view can compute streaks and 7-day averages without
-- scanning the per-event log on every load. Idempotent — safe to
-- call repeatedly for the same date.
drop function if exists public.reset_daily_water_task(date);
create or replace function public.reset_daily_water_task(p_for_date date default current_date)
returns public.daily_water_summary
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user     uuid := auth.uid();
  v_target   constant numeric := 2.5;
  v_glasses  int;
  v_liters   numeric;
  v_morning  int;
  v_noon     int;
  v_afternoon int;
  v_night    int;
  v_hit      boolean;
  v_row      public.daily_water_summary;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  select count(*)::int,
         coalesce(sum(liters), 0)::numeric(5,2)
    into v_glasses, v_liters
  from public.water_intake_log
  where user_id = v_user
    and occurred_date = to_char(p_for_date, 'YYYY-MM-DD');

  select coalesce(count(*) filter (where bucket='morning'),0)::int,
         coalesce(count(*) filter (where bucket='noon'),0)::int,
         coalesce(count(*) filter (where bucket='afternoon'),0)::int,
         coalesce(count(*) filter (where bucket='night'),0)::int
    into v_morning, v_noon, v_afternoon, v_night
  from public.water_intake_log
  where user_id = v_user
    and occurred_date = to_char(p_for_date, 'YYYY-MM-DD');

  v_hit := v_liters >= v_target;

  insert into public.daily_water_summary
    (user_id, metric_date, glasses_total, liters_total,
     bucket_morning, bucket_noon, bucket_afternoon, bucket_night, target_hit)
  values
    (v_user, p_for_date, v_glasses, v_liters,
     v_morning, v_noon, v_afternoon, v_night, v_hit)
  on conflict (user_id, metric_date) do update
    set glasses_total  = excluded.glasses_total,
        liters_total   = excluded.liters_total,
        bucket_morning = excluded.bucket_morning,
        bucket_noon    = excluded.bucket_noon,
        bucket_afternoon = excluded.bucket_afternoon,
        bucket_night   = excluded.bucket_night,
        target_hit     = excluded.target_hit
  returning * into v_row;

  return v_row;
end;
$$;

-- ─── get_water_analytics ───────────────────────────────────────────
-- Returns a 7-day (or N-day) summary plus rolling stats in one
-- round-trip. Combines the per-event log for recent days with the
-- daily_water_summary table for older days so the chart never has a
-- missing bar.
drop function if exists public.get_water_analytics(int);
create or replace function public.get_water_analytics(p_days int default 7)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user       uuid := auth.uid();
  v_target     constant numeric := 2.5;
  v_today      date := (now() at time zone 'Asia/Dhaka')::date;
  v_start      date := v_today - (p_days - 1);
  v_streak     int := 0;
  v_hit_count  int := 0;
  v_avg_liters numeric(6,2) := 0;
  v_days       int := 0;
  v_payload    jsonb;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  with days as (
    select generate_series(v_start, v_today, '1 day')::date as d
  ),
  agg as (
    select s.occurred_date::date as d,
           count(*)::int as glasses,
           coalesce(sum(s.liters), 0)::numeric(5,2) as liters,
           coalesce(count(*) filter (where s.bucket='morning'),0)::int    as morning,
           coalesce(count(*) filter (where s.bucket='noon'),0)::int       as noon,
           coalesce(count(*) filter (where s.bucket='afternoon'),0)::int  as afternoon,
           coalesce(count(*) filter (where s.bucket='night'),0)::int      as night
      from public.water_intake_log s
     where s.user_id = v_user
       and s.occurred_date::date
           between v_start and v_today
     group by 1
  )
  select jsonb_agg(
           jsonb_build_object(
             'date',         to_char(days.d, 'YYYY-MM-DD'),
             'glasses',      coalesce(agg.glasses, 0),
             'liters',       coalesce(agg.liters, 0)::numeric(5,2),
             'target_hit',   coalesce(agg.liters, 0) >= v_target,
             'buckets',      jsonb_build_object(
               'morning',   coalesce(agg.morning, 0),
               'noon',      coalesce(agg.noon, 0),
               'afternoon', coalesce(agg.afternoon, 0),
               'night',     coalesce(agg.night, 0)
             )
           )
           order by days.d
         ),
         coalesce(sum(coalesce(agg.liters, 0)), 0),
         count(*) filter (where coalesce(agg.liters, 0) >= v_target),
         count(*)
    into v_payload, v_avg_liters, v_hit_count, v_days
  from days
  left join agg on agg.d = days.d;

  -- Streak: count consecutive days back from today where the user
  -- hit the target. Walk day by day up to p_days.
  for i in 0..p_days-1 loop
    if exists (
      select 1 from public.daily_water_summary s
       where s.user_id = v_user
         and s.metric_date = v_today - i
         and s.target_hit = true
    ) or exists (
      select 1 from public.water_intake_log s
       where s.user_id = v_user
         and s.occurred_date::date = v_today - i
       group by s.occurred_date
      having coalesce(sum(s.liters), 0) >= v_target
    ) then
      v_streak := v_streak + 1;
    else
      exit;
    end if;
  end loop;

  if v_days > 0 then
    v_avg_liters := round((v_avg_liters / v_days)::numeric, 2);
  end if;

  return jsonb_build_object(
    'days',           coalesce(v_payload, '[]'::jsonb),
    'streak_days',    v_streak,
    'days_hit_target', v_hit_count,
    'avg_liters',     v_avg_liters,
    'consistency_pct', case when v_days = 0 then 0
                            else round((v_hit_count::numeric / v_days) * 100, 1)
                       end,
    'target_liters',  v_target,
    'range_start',    to_char(v_start, 'YYYY-MM-DD'),
    'range_end',      to_char(v_today, 'YYYY-MM-DD')
  );
end;
$$;

grant execute on function public.log_water_event(numeric, timestamptz) to authenticated;
grant execute on function public.reset_daily_water_task(date) to authenticated;
grant execute on function public.get_water_analytics(int) to authenticated;
grant execute on function public.get_today_daily_metrics() to authenticated;
grant execute on function public.upsert_daily_metric(text, numeric) to authenticated;
grant execute on function public.add_water_liters(numeric) to authenticated;
