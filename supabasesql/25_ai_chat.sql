-- ============================================================
-- Amar Diet — AI Chat (Groq-backed)
-- ============================================================
-- Persists the per-user daily prompt quota (5 prompts/day) and the chat
-- transcript so:
--   * the quota is enforced server-side (a client app cannot bypass it)
--   * the bot can recall the last few turns for context
--   * an admin can audit usage / abuse
-- Also exposes `get_ai_chat_context()` which the Flutter client injects
-- into the system prompt so the bot can answer personalised questions
-- (HbA1c, medicines, today's meal adherence, water, workouts).
-- Run AFTER 24_daily_recommendation_v2.sql.
-- ============================================================

-- ---------- 1. PROMPT QUOTA ----------
-- One row per (user, calendar-day, Asia/Dhaka). The `date` is generated
-- by the RPC (in Asia/Dhaka) so the client doesn't have to guess the
-- server's timezone.
create table if not exists public.ai_chat_prompts (
  user_id          uuid    not null references public.user_profiles(user_id) on delete cascade,
  prompt_date      date    not null,
  count            int     not null default 0,
  last_prompt_at   timestamptz,
  primary key (user_id, prompt_date)
);

alter table public.ai_chat_prompts enable row level security;

-- Users can read their own quota row (the client renders a 0/5 pill).
drop policy if exists ai_chat_prompts_select_self on public.ai_chat_prompts;
create policy ai_chat_prompts_select_self
  on public.ai_chat_prompts for select
  using (auth.uid() = user_id);

-- Writes happen only through the security-definer RPCs below; deny
-- direct client inserts/updates so the quota can't be tampered with.
drop policy if exists ai_chat_prompts_no_writes on public.ai_chat_prompts;
create policy ai_chat_prompts_no_writes
  on public.ai_chat_prompts for all
  to authenticated
  using (false) with check (false);

-- ---------- 2. CHAT TRANSCRIPT ----------
create table if not exists public.ai_chat_messages (
  id          uuid        primary key default gen_random_uuid(),
  user_id     uuid        not null references public.user_profiles(user_id) on delete cascade,
  role        text        not null check (role in ('user','assistant','system')),
  content     text        not null,
  model       text,           -- groq model id used for assistant rows
  thread_id   uuid,           -- nullable: links the message to a chat thread
  created_at  timestamptz not null default now()
);

-- Forward-compat migration: add thread_id + index on existing databases
-- where 25_ai_chat.sql was applied before threads were introduced.
-- The FK from thread_id -> ai_chat_threads.id is created further down
-- (right after `ai_chat_threads` is created), so the column add itself
-- can't fail with "relation does not exist".
alter table public.ai_chat_messages
  add column if not exists thread_id uuid;

create index if not exists ai_chat_messages_user_time
  on public.ai_chat_messages (user_id, created_at desc);

create index if not exists ai_chat_messages_thread_time
  on public.ai_chat_messages (thread_id, created_at desc)
  where thread_id is not null;

alter table public.ai_chat_messages enable row level security;

drop policy if exists ai_chat_messages_select_self on public.ai_chat_messages;
create policy ai_chat_messages_select_self
  on public.ai_chat_messages for select
  using (auth.uid() = user_id);

drop policy if exists ai_chat_messages_no_writes on public.ai_chat_messages;
create policy ai_chat_messages_no_writes
  on public.ai_chat_messages for all
  to authenticated
  using (false) with check (false);

-- ---------- 3. FEEDBACK ----------
-- Lightweight 👍/👎 on assistant responses. Forward-compatible with
-- future fine-tuning; not surfaced in the MVP UI flow.
create table if not exists public.ai_chat_feedback (
  id          uuid        primary key default gen_random_uuid(),
  message_id  uuid        not null references public.ai_chat_messages(id) on delete cascade,
  user_id     uuid        not null references public.user_profiles(user_id) on delete cascade,
  rating      smallint    not null check (rating in (-1, 1)),
  created_at  timestamptz not null default now()
);

alter table public.ai_chat_feedback enable row level security;

drop policy if exists ai_chat_feedback_select_self on public.ai_chat_feedback;
create policy ai_chat_feedback_select_self
  on public.ai_chat_feedback for select
  using (auth.uid() = user_id);

drop policy if exists ai_chat_feedback_insert_self on public.ai_chat_feedback;
create policy ai_chat_feedback_insert_self
  on public.ai_chat_feedback for insert
  to authenticated
  with check (auth.uid() = user_id);

-- ============================================================
-- Helpers
-- ============================================================

-- Return today's date in Asia/Dhaka as a `date`. Used by every quota RPC
-- so a user in BST (UTC+6) doesn't get an extra 5 prompts by traveling
-- across the server's UTC midnight.
create or replace function public._ai_chat_today_dhaka()
returns date
language sql
stable
as $$
  select (now() at time zone 'Asia/Dhaka')::date;
$$;

-- Tomorrow's date in Asia/Dhaka — used for the `resets_at` timestamp so the
-- client can show a "resets in 4h 12m" countdown.
create or replace function public._ai_chat_next_dhaka_midnight()
returns timestamptz
language sql
stable
as $$
  select ((now() at time zone 'Asia/Dhaka')::date + 1)
         at time zone 'Asia/Dhaka';
$$;

-- ============================================================
-- 1. check_and_increment_prompt_quota
-- ============================================================
-- Atomically: if quota not yet full, increment and return success.
-- Returns the *new* count plus the time the slot frees up.
-- SECURITY DEFINER — runs as the table owner so the RLS deny policy
-- above doesn't block the upsert.

create or replace function public.check_and_increment_prompt_quota(
  p_user_id uuid,
  p_limit   int default 5
)
returns table (
  allowed    bool,
  used       int,
  remaining  int,
  limit_val  int,
  resets_at  timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today   date := public._ai_chat_today_dhaka();
  v_used    int;
  v_inserted bool;
begin
  -- Upsert: create today's row if it doesn't exist, otherwise grab the
  -- current count. We use ON CONFLICT DO NOTHING + a follow-up SELECT
  -- so we never lose a row to a race between two concurrent requests.
  insert into public.ai_chat_prompts(user_id, prompt_date, count, last_prompt_at)
    values (p_user_id, v_today, 0, null)
    on conflict (user_id, prompt_date) do nothing;

  select count into v_used
    from public.ai_chat_prompts
    where user_id = p_user_id and prompt_date = v_today
    for update;

  if v_used >= p_limit then
    return query
      select false, v_used, 0, p_limit, public._ai_chat_next_dhaka_midnight();
    return;
  end if;

  update public.ai_chat_prompts
    set count = count + 1,
        last_prompt_at = now()
    where user_id = p_user_id and prompt_date = v_today;

  return query
    select true, v_used + 1, p_limit - (v_used + 1), p_limit,
           public._ai_chat_next_dhaka_midnight();
end;
$$;

revoke all on function public.check_and_increment_prompt_quota(uuid, int) from public;
grant execute on function public.check_and_increment_prompt_quota(uuid, int) to authenticated;

-- ============================================================
-- 2. get_prompt_quota
-- ============================================================
-- Read-only: show the current count for today without mutating.
-- Used by the client to render the "৩/৫ আজ" pill on cold start.

create or replace function public.get_prompt_quota(
  p_user_id uuid,
  p_limit   int default 5
)
returns table (
  used       int,
  remaining  int,
  limit_val  int,
  resets_at  timestamptz
)
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_today date := public._ai_chat_today_dhaka();
  v_used  int := 0;
begin
  select count into v_used
    from public.ai_chat_prompts
    where user_id = p_user_id and prompt_date = v_today;

  return query
    select v_used,
           greatest(p_limit - v_used, 0),
           p_limit,
           public._ai_chat_next_dhaka_midnight();
end;
$$;

revoke all on function public.get_prompt_quota(uuid, int) from public;
grant execute on function public.get_prompt_quota(uuid, int) to authenticated;

-- ============================================================
-- 2b. refund_prompt_quota
-- ============================================================
-- Decrements today's count by 1 (clamped at 0) when the AI never
-- produced a valid reply — e.g. the stream returned zero tokens, the
-- router hit the every-model-silent budget, or the response was
-- indistinguishable from a refusal. This keeps the 5/day limit fair:
-- we only charge for prompts that actually answered something.
--
-- Idempotent: if the row is missing the user never consumed a quota
-- slot, so there's nothing to refund. Same shape as get_prompt_quota
-- so the client can refresh the pill in one place.
create or replace function public.refund_prompt_quota(
  p_user_id uuid,
  p_limit   int default 5
)
returns table (
  used       int,
  remaining  int,
  limit_val  int,
  resets_at  timestamptz,
  refunded   bool
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := public._ai_chat_today_dhaka();
  v_used  int := 0;
  v_did_refund bool := false;
begin
  -- Lock today's row so two concurrent refunds can't both succeed.
  select count into v_used
    from public.ai_chat_prompts
    where user_id = p_user_id and prompt_date = v_today
    for update;

  if v_used is not null and v_used > 0 then
    update public.ai_chat_prompts
      set count = count - 1
      where user_id = p_user_id and prompt_date = v_today;
    v_used := v_used - 1;
    v_did_refund := true;
  else
    v_used := coalesce(v_used, 0);
  end if;

  return query
    select v_used,
           greatest(p_limit - v_used, 0),
           p_limit,
           public._ai_chat_next_dhaka_midnight(),
           v_did_refund;
end;
$$;

revoke all on function public.refund_prompt_quota(uuid, int) from public;
grant execute on function public.refund_prompt_quota(uuid, int) to authenticated;

-- ============================================================
-- 3. get_ai_chat_context
-- ============================================================
-- Builds the JSON blob the Flutter client prepends to the system prompt.
-- Pulls from existing tables (user_profiles, medicines, meal log,
-- workout log, daily_metrics, classify_user_v2 RPC) so the bot can
-- answer personalised questions without the user re-typing their values.

create or replace function public.get_ai_chat_context(p_user_id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_profile   jsonb;
  v_classify  jsonb;
  v_meds      jsonb;
  v_meals     jsonb;
  v_workouts  jsonb;
  v_water     jsonb;
  v_today     date := public._ai_chat_today_dhaka();
begin
  -- Profile
  select to_jsonb(up.*) into v_profile
    from public.user_profiles up
    where up.user_id = p_user_id;

  -- Existing classification (v2) — if the function isn't installed yet
  -- for some reason, swallow the error and return null.
  begin
    v_classify := public.classify_user_v2(p_user_id);
  exception when others then
    v_classify := null;
  end;

  -- Today's medicine schedule (pending + taken)
  select coalesce(jsonb_agg(jsonb_build_object(
      'name_bn',  m.name_bn,
      'strength', m.strength,
      'scheduled_time', to_char(d.scheduled_time, 'HH24:MI'),
      'status',   d.status
    ) order by d.scheduled_time), '[]'::jsonb)
    into v_meds
  from public.medicine_doses d
  join public.medicines m on m.id = d.medicine_id
  where d.user_id = p_user_id
    and d.dose_date = v_today;

  -- Today's meal adherence (planned / eaten) — single-day window so the
  -- result is a 1-row set. `p_days=1` matches the existing RPC signature.
  begin
    select jsonb_build_object(
             'planned', planned,
             'eaten',   eaten,
             'pct',     case when planned = 0 then 0
                              else round(100.0 * eaten::numeric / planned) end
           )
      into v_meals
    from public.get_meal_adherence(1)
     where day = v_today
     limit 1;
  exception when others then
    v_meals := null;
  end;

  if v_meals is null then
    v_meals := jsonb_build_object('planned', 0, 'eaten', 0, 'pct', 0);
  end if;

  -- Today's workout completion — derive from the 7-day window.
  begin
    select jsonb_build_object(
             'total',     total,
             'completed', completed,
             'pct',       case when total = 0 then 0
                                else round(100.0 * completed::numeric / total) end
           )
      into v_workouts
    from public.get_workout_logs(7)
     where day = v_today
     limit 1;
  exception when others then
    v_workouts := null;
  end;

  if v_workouts is null then
    v_workouts := jsonb_build_object('total', 0, 'completed', 0, 'pct', 0);
  end if;

  -- Today's water/HR/steps row (single object). The existing RPC ignores
  -- `p_user_id` and uses auth.uid(), which is what we want here.
  begin
    select jsonb_build_object(
             'water_liters',   water_liters,
             'heart_rate_bpm', heart_rate_bpm,
             'steps',          steps
           )
      into v_water
    from public.get_today_daily_metrics()
     limit 1;
  exception when others then
    v_water := null;
  end;

  if v_water is null then
    v_water := jsonb_build_object(
      'water_liters', 0, 'heart_rate_bpm', 0, 'steps', 0);
  end if;

  return jsonb_build_object(
    'profile',     v_profile,
    'classification', v_classify,
    'medicines_today', v_meds,
    'meal_today', v_meals,
    'workout_today', v_workouts,
    'water_today', v_water,
    'as_of',  now()
  );
end;
$$;

revoke all on function public.get_ai_chat_context(uuid) from public;
grant execute on function public.get_ai_chat_context(uuid) to authenticated;

-- ============================================================
-- 4. save_ai_chat_message
-- ============================================================
-- Append a single message to the transcript. Fire-and-forget from the
-- client (we don't want the response to block on the DB write).

create or replace function public.save_ai_chat_message(
  p_user_id uuid,
  p_role    text,
  p_content text,
  p_model   text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if p_role not in ('user','assistant','system') then
    raise exception 'invalid role: %', p_role using errcode = '22000';
  end if;

  insert into public.ai_chat_messages(user_id, role, content, model)
    values (p_user_id, p_role, p_content, p_model)
    returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.save_ai_chat_message(uuid, text, text, text) from public;
grant execute on function public.save_ai_chat_message(uuid, text, text, text) to authenticated;

-- ============================================================
-- 5. clear_ai_chat_history
-- ============================================================
-- Wipe the user's transcript. Quota isn't touched.

create or replace function public.clear_ai_chat_history(p_user_id uuid)
returns int
language sql
security definer
set search_path = public
as $$
  with d as (
    delete from public.ai_chat_messages
    where user_id = p_user_id
    returning 1
  )
  select count(*)::int from d;
$$;

revoke all on function public.clear_ai_chat_history(uuid) from public;
grant execute on function public.clear_ai_chat_history(uuid) to authenticated;

-- ============================================================
-- 6. save_ai_chat_feedback
-- ============================================================

create or replace function public.save_ai_chat_feedback(
  p_user_id    uuid,
  p_message_id uuid,
  p_rating     smallint
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if p_rating not in (-1, 1) then
    raise exception 'rating must be -1 or 1' using errcode = '22000';
  end if;

  insert into public.ai_chat_feedback(user_id, message_id, rating)
    values (p_user_id, p_message_id, p_rating)
    returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.save_ai_chat_feedback(uuid, uuid, smallint) from public;
grant execute on function public.save_ai_chat_feedback(uuid, uuid, smallint) to authenticated;

-- ============================================================
-- 7. last_n_ai_chat_messages
-- ============================================================
-- Return the last N user/assistant turns for conversation memory.
-- Default 8 (≈ 4 exchanges) — enough to keep "earlier you said…"
-- coherent without bloating the system prompt.

create or replace function public.last_n_ai_chat_messages(
  p_user_id uuid,
  p_n       int default 8
)
returns table (
  role    text,
  content text,
  model   text
)
language sql
security definer
stable
set search_path = public
as $$
  with recent as (
    select m.role, m.content, m.model, m.created_at
      from public.ai_chat_messages m
     where m.user_id = p_user_id
     order by m.created_at desc
     limit greatest(p_n, 1)
  )
  select role, content, model from recent order by created_at asc;
$$;

revoke all on function public.last_n_ai_chat_messages(uuid, int) from public;
grant execute on function public.last_n_ai_chat_messages(uuid, int) to authenticated;

-- ============================================================
-- 8. CONVERSATION THREADS (history sidebar)
-- ============================================================
-- One row per conversation the user has with the AI assistant.
-- A thread groups many `ai_chat_messages` rows so the history
-- sidebar can list past conversations (like ChatGPT/Claude/Gemini),
-- and tapping one reopens the full transcript.
--
-- Title is auto-generated from the first user message (first 60 chars),
-- and the user can rename/delete a thread from the UI.

create table if not exists public.ai_chat_threads (
  id              uuid        primary key default gen_random_uuid(),
  user_id         uuid        not null references public.user_profiles(user_id) on delete cascade,
  title           text        not null default '' ,
  created_at      timestamptz not null default now(),
  last_message_at timestamptz not null default now(),
  message_count   int         not null default 0
);

create index if not exists ai_chat_threads_user_recent
  on public.ai_chat_threads (user_id, last_message_at desc);

alter table public.ai_chat_threads enable row level security;

drop policy if exists ai_chat_threads_select_self on public.ai_chat_threads;
create policy ai_chat_threads_select_self
  on public.ai_chat_threads for select
  using (auth.uid() = user_id);

drop policy if exists ai_chat_threads_modify_self on public.ai_chat_threads;
create policy ai_chat_threads_modify_self
  on public.ai_chat_threads for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
-- FK from ai_chat_messages.thread_id -> ai_chat_threads(id).
-- Idempotent: if the constraint already exists it is a no-op,
-- and it only runs once both tables exist.
do $$
begin
  if to_regclass('public.ai_chat_messages') is not null
     and to_regclass('public.ai_chat_threads') is not null
     and not exists (
       select 1 from pg_constraint
        where conname = 'ai_chat_messages_thread_id_fkey'
     ) then
    alter table public.ai_chat_messages
      add constraint ai_chat_messages_thread_id_fkey
      foreign key (thread_id)
      references public.ai_chat_threads(id)
      on delete cascade;
  end if;
end $$;

-- ============================================================
-- 9. list_ai_chat_threads
-- ============================================================
-- Returns the user``s threads newest-first, with a snippet preview of
-- the first user message so the sidebar can render `"title + preview"`.

create or replace function public.list_ai_chat_threads(
  p_user_id uuid,
  p_limit   int default 100
)
returns table (
  id              uuid,
  title           text,
  created_at      timestamptz,
  last_message_at timestamptz,
  message_count   int,
  preview         text
)
language sql
security definer
stable
set search_path = public
as $$
  select t.id,
         t.title,
         t.created_at,
         t.last_message_at,
         t.message_count,
         coalesce(
           (
             select m.content
             from public.ai_chat_messages m
             where m.user_id = t.user_id
               and m.role = 'user'
               and m.created_at >= t.created_at
               and m.created_at <  t.last_message_at + interval '1 day'
             order by m.created_at asc
             limit 1
           ),
           ''
         ) as preview
    from public.ai_chat_threads t
   where t.user_id = p_user_id
   order by t.last_message_at desc
   limit greatest(p_limit, 1);
$$;

revoke all on function public.list_ai_chat_threads(uuid, int) from public;
grant execute on function public.list_ai_chat_threads(uuid, int) to authenticated;

-- ============================================================
-- 10. create_ai_chat_thread
-- ============================================================
-- Make a new thread for the user. Optionally takes the first user
-- message as p_title_seed so we can auto-title from the prompt.

create or replace function public.create_ai_chat_thread(
  p_user_id    uuid,
  p_title_seed text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id    uuid;
  v_title text;
begin
  v_title := coalesce(
    nullif(btrim(p_title_seed), ''),
    'New chat'
  );
  -- Truncate title to 80 chars so the sidebar stays tidy.
  v_title := left(v_title, 80);

  insert into public.ai_chat_threads(user_id, title)
    values (p_user_id, v_title)
    returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.create_ai_chat_thread(uuid, text) from public;
grant execute on function public.create_ai_chat_thread(uuid, text) to authenticated;

-- ============================================================
-- 11. rename_ai_chat_thread
-- ============================================================

create or replace function public.rename_ai_chat_thread(
  p_thread_id uuid,
  p_user_id   uuid,
  p_title     text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok boolean;
begin
  update public.ai_chat_threads
     set title = left(btrim(coalesce(p_title, '''')), 80)
   where id = p_thread_id
     and user_id = p_user_id;
  get diagnostics v_ok = row_count;
  return v_ok > 0;
end;
$$;

revoke all on function public.rename_ai_chat_thread(uuid, uuid, text) from public;
grant execute on function public.rename_ai_chat_thread(uuid, uuid, text) to authenticated;

-- ============================================================
-- 12. delete_ai_chat_thread
-- ============================================================
-- Deletes one thread + all of its messages. Returns true if the row
-- existed. The quota is untouched.

create or replace function public.delete_ai_chat_thread(
  p_thread_id uuid,
  p_user_id   uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok boolean;
begin
  delete from public.ai_chat_messages
   where user_id = p_user_id
     and thread_id = p_thread_id;

  delete from public.ai_chat_threads
   where id = p_thread_id
     and user_id = p_user_id;
  get diagnostics v_ok = row_count;
  return v_ok > 0;
end;
$$;

revoke all on function public.delete_ai_chat_thread(uuid, uuid) from public;
grant execute on function public.delete_ai_chat_thread(uuid, uuid) to authenticated;
-- ============================================================
-- 8. CONVERSATION THREADS (history sidebar)
-- ============================================================
-- One row per conversation the user has with the AI assistant.
-- A thread groups many ai_chat_messages rows so the history
-- sidebar can list past conversations (like ChatGPT/Claude/Gemini),
-- and tapping one reopens the full transcript.
--
-- Title is auto-generated from the first user message (first 60 chars),
-- and the user can rename/delete a thread from the UI.

create table if not exists public.ai_chat_threads (
  id              uuid        primary key default gen_random_uuid(),
  user_id         uuid        not null references public.user_profiles(user_id) on delete cascade,
  title           text        not null default '',
  created_at      timestamptz not null default now(),
  last_message_at timestamptz not null default now(),
  message_count   int         not null default 0
);

create index if not exists ai_chat_threads_user_recent
  on public.ai_chat_threads (user_id, last_message_at desc);

alter table public.ai_chat_threads enable row level security;

drop policy if exists ai_chat_threads_select_self on public.ai_chat_threads;
create policy ai_chat_threads_select_self
  on public.ai_chat_threads for select
  using (auth.uid() = user_id);

drop policy if exists ai_chat_threads_modify_self on public.ai_chat_threads;
create policy ai_chat_threads_modify_self
  on public.ai_chat_threads for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
-- FK from ai_chat_messages.thread_id -> ai_chat_threads(id).
-- Idempotent: if the constraint already exists it is a no-op,
-- and it only runs once both tables exist.
do $$
begin
  if to_regclass('public.ai_chat_messages') is not null
     and to_regclass('public.ai_chat_threads') is not null
     and not exists (
       select 1 from pg_constraint
        where conname = 'ai_chat_messages_thread_id_fkey'
     ) then
    alter table public.ai_chat_messages
      add constraint ai_chat_messages_thread_id_fkey
      foreign key (thread_id)
      references public.ai_chat_threads(id)
      on delete cascade;
  end if;
end $$;

-- ============================================================
-- 9. list_ai_chat_threads
-- ============================================================
-- Returns the user``s threads newest-first, with a snippet preview of
-- the first user message so the sidebar can render "title + preview".

create or replace function public.list_ai_chat_threads(
  p_user_id uuid,
  p_limit   int default 100
)
returns table (
  id              uuid,
  title           text,
  created_at      timestamptz,
  last_message_at timestamptz,
  message_count   int,
  preview         text
)
language sql
security definer
stable
set search_path = public
as $$
  select t.id,
         t.title,
         t.created_at,
         t.last_message_at,
         t.message_count,
         coalesce(
           (
             select m.content
             from public.ai_chat_messages m
             where m.user_id = t.user_id
               and m.role = 'user'
               and m.created_at >= t.created_at
               and m.created_at <  t.last_message_at + interval '1 day'
             order by m.created_at asc
             limit 1
           ),
           ''
         ) as preview
    from public.ai_chat_threads t
   where t.user_id = p_user_id
   order by t.last_message_at desc
   limit greatest(p_limit, 1);
$$;

revoke all on function public.list_ai_chat_threads(uuid, int) from public;
grant execute on function public.list_ai_chat_threads(uuid, int) to authenticated;

-- ============================================================
-- 10. create_ai_chat_thread
-- ============================================================
-- Make a new thread for the user. Optionally takes the first user
-- message as p_title_seed so we can auto-title from the prompt.

create or replace function public.create_ai_chat_thread(
  p_user_id    uuid,
  p_title_seed text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id    uuid;
  v_title text;
begin
  v_title := coalesce(
    nullif(btrim(p_title_seed), ''),
    'New chat'
  );
  -- Truncate title to 80 chars so the sidebar stays tidy.
  v_title := left(v_title, 80);

  insert into public.ai_chat_threads(user_id, title)
    values (p_user_id, v_title)
    returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.create_ai_chat_thread(uuid, text) from public;
grant execute on function public.create_ai_chat_thread(uuid, text) to authenticated;

-- ============================================================
-- 11. rename_ai_chat_thread
-- ============================================================

create or replace function public.rename_ai_chat_thread(
  p_thread_id uuid,
  p_user_id   uuid,
  p_title     text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok boolean;
begin
  update public.ai_chat_threads
     set title = left(btrim(coalesce(p_title, '')), 80)
   where id = p_thread_id
     and user_id = p_user_id;
  get diagnostics v_ok = row_count;
  return v_ok > 0;
end;
$$;

revoke all on function public.rename_ai_chat_thread(uuid, uuid, text) from public;
grant execute on function public.rename_ai_chat_thread(uuid, uuid, text) to authenticated;

-- ============================================================
-- 12. delete_ai_chat_thread
-- ============================================================
-- Deletes one thread + all of its messages. Returns true if the row
-- existed. The quota is untouched.

create or replace function public.delete_ai_chat_thread(
  p_thread_id uuid,
  p_user_id   uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok boolean;
begin
  delete from public.ai_chat_messages
   where user_id = p_user_id
     and thread_id = p_thread_id;

  delete from public.ai_chat_threads
   where id = p_thread_id
     and user_id = p_user_id;
  get diagnostics v_ok = row_count;
  return v_ok > 0;
end;
$$;

revoke all on function public.delete_ai_chat_thread(uuid, uuid) from public;
grant execute on function public.delete_ai_chat_thread(uuid, uuid) to authenticated;

-- ============================================================
-- 13. save_ai_chat_message (with optional thread_id)
-- ============================================================
-- Backwards-compatible overload: if p_thread_id is provided we tag
-- the row with the thread, otherwise the row stays untagged.
-- Also bumps last_message_at + message_count on the thread row.

create or replace function public.save_ai_chat_message(
  p_user_id   uuid,
  p_role      text,
  p_content   text,
  p_model     text default null,
  p_thread_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if p_role not in ('user','assistant','system') then
    raise exception 'invalid role: %', p_role using errcode = '22000';
  end if;

  insert into public.ai_chat_messages(user_id, role, content, model, thread_id)
    values (p_user_id, p_role, p_content, p_model, p_thread_id)
    returning id into v_id;

  if p_thread_id is not null then
    update public.ai_chat_threads
       set last_message_at = now(),
           message_count   = message_count + 1
     where id = p_thread_id
       and user_id = p_user_id;
  end if;

  return v_id;
end;
$$;

revoke all on function public.save_ai_chat_message(uuid, text, text, text, uuid) from public;
grant execute on function public.save_ai_chat_message(uuid, text, text, text, uuid) to authenticated;

-- ============================================================
-- 14. last_n_ai_chat_messages (thread-aware)
-- ============================================================
-- Return the last N user/assistant turns within the active thread.
-- p_thread_id is required so we never bleed turns between chats.

create or replace function public.last_n_ai_chat_messages(
  p_user_id   uuid,
  p_n         int default 8,
  p_thread_id uuid default null
)
returns table (
  role    text,
  content text,
  model   text
)
language sql
security definer
stable
set search_path = public
as $$
  with recent as (
    select m.role, m.content, m.model, m.created_at
      from public.ai_chat_messages m
     where m.user_id = p_user_id
       and (p_thread_id is null or m.thread_id = p_thread_id)
     order by m.created_at desc
     limit greatest(p_n, 1)
  )
  select role, content, model from recent order by created_at asc;
$$;

revoke all on function public.last_n_ai_chat_messages(uuid, int, uuid) from public;
grant execute on function public.last_n_ai_chat_messages(uuid, int, uuid) to authenticated;

-- ============================================================
-- 15. load_thread_messages
-- ============================================================
-- Full transcript for a thread (oldest first), used when reopening a
-- past conversation in the history sidebar.

create or replace function public.load_thread_messages(
  p_user_id   uuid,
  p_thread_id uuid,
  p_limit     int default 500
)
returns table (
  id          uuid,
  role        text,
  content     text,
  model       text,
  created_at  timestamptz
)
language sql
security definer
stable
set search_path = public
as $$
  select m.id, m.role, m.content, m.model, m.created_at
    from public.ai_chat_messages m
   where m.user_id   = p_user_id
     and m.thread_id = p_thread_id
   order by m.created_at asc
   limit greatest(p_limit, 1);
$$;

revoke all on function public.load_thread_messages(uuid, uuid, int) from public;
grant execute on function public.load_thread_messages(uuid, uuid, int) to authenticated;

-- ============================================================
-- 16. clear_ai_chat_history (now thread-aware)
-- ============================================================
-- Wipes every thread + every message for the user. The quota is
-- untouched (matches the old behaviour for callers that still pass
-- no thread id).

create or replace function public.clear_ai_chat_history(p_user_id uuid)
returns int
language sql
security definer
set search_path = public
as $$
  with d as (
    delete from public.ai_chat_messages
     where user_id = p_user_id
     returning 1
  ),
  t as (
    delete from public.ai_chat_threads
     where user_id = p_user_id
     returning 1
  )
  select (select count(*) from d)::int;
$$;

revoke all on function public.clear_ai_chat_history(uuid) from public;
grant execute on function public.clear_ai_chat_history(uuid) to authenticated;

-- ============================================================
-- 17. thread_id column on ai_chat_messages (for old rows)
-- ============================================================
-- Add a nullable thread_id column so legacy rows still load.
alter table public.ai_chat_messages
  add column if not exists thread_id uuid
    references public.ai_chat_threads(id) on delete cascade;

create index if not exists ai_chat_messages_thread_time
  on public.ai_chat_messages (thread_id, created_at asc);
