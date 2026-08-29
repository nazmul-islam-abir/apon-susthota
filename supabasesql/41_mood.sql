-- ============================================================
-- Amar Diet — Daily mood + health-conditions log
-- Apply AFTER 40_ai_chat_action_log.sql.
--
-- What this file does:
--   1. Creates `public.mood_entries` — one row per user per local
--      day (Asia/Dhaka), capturing the daily mood emoji + four
--      short health signals (sleep, energy, stress, symptoms).
--   2. RPCs:
--        • get_today_mood()            — fetch today's row (or none)
--        • log_mood(...)               — upsert today's row
--        • get_mood_history(p_days)    — last N days summary
--   3. RLS so each user only sees / writes their own rows.
-- ============================================================

create table if not exists public.mood_entries (
  id           bigserial primary key,
  user_id      uuid not null references auth.users(id) on delete cascade,
  mood_kind    text not null check (mood_kind in ('sad','meh','ok','good','great')),
  energy_level int  not null check (energy_level between 1 and 5),
  stress_level int  not null check (stress_level between 1 and 5),
  sleep_hours  numeric(4,1) not null check (sleep_hours between 0 and 24),
  symptoms     text,
  entry_date   date not null,
  created_at   timestamptz not null default now(),
  unique (user_id, entry_date)
);

create index if not exists idx_mood_entries_user_date
  on public.mood_entries (user_id, entry_date desc);

alter table public.mood_entries enable row level security;

drop policy if exists "mood_entries self" on public.mood_entries;
create policy "mood_entries self"
  on public.mood_entries for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ─── get_today_mood ──────────────────────────────────────────
-- Returns today's mood + health row (or 0 rows if none yet).
-- Uses Asia/Dhaka for the local-day boundary so it agrees with
-- every other "today" function in this app.
drop function if exists public.get_today_mood();
create or replace function public.get_today_mood()
returns table (
  mood_kind    text,
  energy_level int,
  stress_level int,
  sleep_hours  numeric,
  symptoms     text,
  entry_date   date,
  created_at   timestamptz
)
language sql
security definer
set search_path = public, auth
as $$
  select mood_kind, energy_level, stress_level,
         sleep_hours, symptoms, entry_date, created_at
    from public.mood_entries
   where user_id = auth.uid()
     and entry_date = ((now() at time zone 'Asia/Dhaka')::date)
   limit 1;
$$;

-- ─── log_mood ─────────────────────────────────────────────────
-- Upsert one row for the user's local day. Re-recording on the
-- same day overwrites the previous values and bumps created_at
-- so the dashboard "last edited at HH:mm" stays accurate.
drop function if exists public.log_mood(text, int, int, numeric, text);
create or replace function public.log_mood(
  p_mood_kind text,
  p_energy    int,
  p_stress    int,
  p_sleep     numeric,
  p_symptoms  text default null
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_date date := ((now() at time zone 'Asia/Dhaka')::date);
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  insert into public.mood_entries
    (user_id, mood_kind, energy_level, stress_level, sleep_hours, symptoms, entry_date)
  values
    (v_user, p_mood_kind, p_energy, p_stress, p_sleep, p_symptoms, v_date)
  on conflict (user_id, entry_date) do update set
    mood_kind    = excluded.mood_kind,
    energy_level = excluded.energy_level,
    stress_level = excluded.stress_level,
    sleep_hours  = excluded.sleep_hours,
    symptoms     = excluded.symptoms,
    created_at   = now();
end;
$$;

-- ─── get_mood_history ────────────────────────────────────────
-- Last N days of mood + health signals for analytics / the
-- "mood history" screen. Newest first.
drop function if exists public.get_mood_history(int);
create or replace function public.get_mood_history(p_days int default 14)
returns table (
  entry_date   date,
  mood_kind    text,
  energy_level int,
  stress_level int,
  sleep_hours  numeric
)
language sql
security definer
set search_path = public, auth
as $$
  select entry_date, mood_kind, energy_level, stress_level, sleep_hours
    from public.mood_entries
   where user_id = auth.uid()
     and entry_date >= ((now() at time zone 'Asia/Dhaka')::date - greatest(p_days, 1))
   order by entry_date desc;
$$;

grant execute on function public.get_today_mood()                                to authenticated;
grant execute on function public.log_mood(text, int, int, numeric, text)         to authenticated;
grant execute on function public.get_mood_history(int)                           to authenticated;