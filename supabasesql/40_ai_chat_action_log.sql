-- ============================================================
-- 40 — AI chat action log + tool-call audit + undo
-- ============================================================
-- Whenever the AI executes a write (create_medicine, mark_dose,
-- log_water_event, etc.) we record the original args *and* the
-- inverse so the user can Undo from the chat for 60 seconds.
--
-- The table is APPEND-ONLY by convention: rows never get updated
-- after `undo_ai_chat_action` runs — they just get a `undone_at`
-- timestamp. That way the action history stays auditable for
-- support, even after the in-app Undo window expires.
--
-- Idempotency: UNIQUE (p_message_id, p_tool_name) so a retried RPC
-- (e.g. after a network blip on `করুন`) never double-writes.

-- ---------- 1. TABLE ----------
create table if not exists public.ai_chat_action_log (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  thread_id      uuid,
  message_id     uuid,                            -- assistant bubble that emitted the tool call
  tool_name      text not null,                   -- 'create_medicine', 'mark_dose', ...
  tool_args      jsonb not null,                  -- original args as JSON
  inverse_args   jsonb not null,                  -- pre-image to revert (delete id, pre-update row, etc.)
  description    text not null,                  -- Bangla one-liner shown on the summary card
  undone_at      timestamptz,                     -- set when the user taps Undo within the window
  expired_at     timestamptz,                     -- set when the undo window closes
  created_at     timestamptz not null default now()
);

create unique index if not exists ai_chat_action_log_unique_call
  on public.ai_chat_action_log (message_id, tool_name)
  where message_id is not null;

create index if not exists ai_chat_action_log_user_recent
  on public.ai_chat_action_log (user_id, created_at desc);

alter table public.ai_chat_action_log enable row level security;

-- Direct reads: a user can see their own log. Inserts/updates/deletes
-- go through the SECURITY DEFINER RPCs below so the client can never
-- forge an undo.
drop policy if exists "Users read their own AI action log"
  on public.ai_chat_action_log;
create policy "Users read their own AI action log"
  on public.ai_chat_action_log for select
  using (auth.uid() = user_id);


-- ---------- 2. log_ai_chat_action ----------
-- Inserts an audit row capturing a tool call the AI just ran.
-- Returns the row id, which the client uses to Undo later.
drop function if exists public.log_ai_chat_action(
  text, jsonb, jsonb, text, uuid, uuid
);
create or replace function public.log_ai_chat_action(
  p_tool_name      text,
  p_tool_args      jsonb,
  p_inverse_args   jsonb,
  p_description    text,
  p_message_id     uuid default null,
  p_thread_id      uuid default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_id   uuid;
begin
  if v_user is null then raise exception 'not authenticated'; end if;
  if p_tool_name is null or length(trim(p_tool_name)) = 0 then
    raise exception 'tool_name is required';
  end if;
  if p_tool_args is null then p_tool_args := '{}'::jsonb; end if;
  if p_inverse_args is null then p_inverse_args := '{}'::jsonb; end if;

  -- Idempotent: a retry on (p_message_id, p_tool_name) returns the
  -- existing row instead of inserting a second one.
  if p_message_id is not null then
    select id into v_id
      from public.ai_chat_action_log
      where message_id = p_message_id
        and tool_name  = p_tool_name
        and user_id    = v_user
      limit 1;
    if v_id is not null then
      return v_id;
    end if;
  end if;

  insert into public.ai_chat_action_log
    (user_id, thread_id, message_id, tool_name,
     tool_args, inverse_args, description)
  values
    (v_user, p_thread_id, p_message_id, p_tool_name,
     p_tool_args, p_inverse_args, p_description)
  returning id into v_id;
  return v_id;
end;
$$;

grant execute on function public.log_ai_chat_action(
  text, jsonb, jsonb, text, uuid, uuid
) to authenticated;


-- ---------- 3. undo_ai_chat_action ----------
-- Marks the audit row as undone and stamps `undone_at`. The Flutter
-- `action_inverse` module translates `inverse_args` into the actual
-- compensating RPC call. Marking is server-side; the side-effect
-- undo is client-side so we keep RPC contracts stable.
drop function if exists public.undo_ai_chat_action(uuid);
create or replace function public.undo_ai_chat_action(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_undone timestamptz;
begin
  if v_user is null then raise exception 'not authenticated'; end if;
  update public.ai_chat_action_log
    set undone_at = now()
    where id = p_id and user_id = v_user and undone_at is null
    returning undone_at into v_undone;
  if v_undone is null then
    raise exception 'action not found or already undone';
  end if;
end;
$$;

grant execute on function public.undo_ai_chat_action(uuid) to authenticated;


-- ---------- 4. expire_old_actions ----------
-- Sweep the audit table so the read API can offer "Undo (45s left)"
-- with a real deadline. Pure bookkeeping; safe to call from a
-- cron / TTL job — but the client also computes the deadline from
-- `created_at + 60s` so this is optional.
drop function if exists public.expire_old_actions(int);
create or replace function public.expire_old_actions(p_window_seconds int default 60)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_n int;
begin
  if v_user is null then raise exception 'not authenticated'; end if;
  update public.ai_chat_action_log
    set expired_at = now()
    where user_id  = v_user
      and undone_at is null
      and expired_at is null
      and created_at < now() - make_interval(secs => greatest(p_window_seconds, 1));
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

grant execute on function public.expire_old_actions(int) to authenticated;


-- ---------- 5. delete_water_intake ----------
-- Inverse for `log_water_event`. Caller passes the id returned from
-- the original write. Subtracts the liter amount from `daily_metrics`
-- so the running total stays consistent.
drop function if exists public.delete_water_intake(uuid);
create or replace function public.delete_water_intake(p_log_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user uuid := auth.uid();
  v_liters numeric(5,2);
  v_date  date;
begin
  if v_user is null then raise exception 'not authenticated'; end if;
  select liters, (occurred_at at time zone 'Asia/Dhaka')::date
    into v_liters, v_date
    from public.water_intake_log
    where id = p_log_id and user_id = v_user;
  if v_liters is null then
    raise exception 'water log not found';
  end if;

  delete from public.water_intake_log where id = p_log_id and user_id = v_user;

  update public.daily_metrics
    set water_liters = least(greatest(coalesce(water_liters, 0) - v_liters, 0), 20)
    where user_id = v_user and metric_date = v_date;
end;
$$;

grant execute on function public.delete_water_intake(uuid) to authenticated;
