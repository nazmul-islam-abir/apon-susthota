-- ============================================================
-- Amar Diet — Workout completion stickiness + session freshness
-- Apply AFTER 15_diabetes_12ex.sql and 17_workout_progressive_30day.sql.
--
-- Symptom this fixes:
--   User completes a wall push-up (timer crosses target, auto-complete
--   fires `_persist(completed: true)`), but when they return to the
--   "আজকের রুটিন" list, the wall push-up tile still shows unchecked
--   even though the per-exercise feedback pill correctly reports
--   100%+ actual/target.
--
-- Root causes (two):
--
--   1. `get_today_workout()` and `start_workout_session()` both lookup
--      today's session with `WHERE user_id = ... AND session_date = ...`
--      without an `ORDER BY` or `LIMIT 1`. If the user has multiple
--      sessions for today (relaunched the app, network retried, etc.),
--      Postgres returns the rows in arbitrary order. The routine list
--      can then read the items of a stale session whose `workout_session_
--      items` does NOT include the lazy-created wall push-up row the
--      user just persisted — so the per-tile ✓ badge stays missing
--      even though the analytics rollup correctly counts it.
--
--   2. `finish_workout_session_item()` writes
--        is_completed = p_completed
--      unconditionally. A subsequent pause call (e.g. from the PopScope
--      when the user backs out of the screen right after auto-complete
--      fires, or from any path that calls _pause() while `_running` is
--      still true during a one-tick window) re-sends `completed=false`
--      and silently flips the row back to `is_completed = false`. The
--      user sees no ✓ on the routine tile even though they reached the
--      target.
--
-- Fix:
--   • Always pick the LATEST session for today (ORDER BY started_at
--     DESC LIMIT 1) in both `start_workout_session` and
--     `get_today_workout`.
--   • Make `is_completed` monotonic: once true, a later `false` from
--     any caller cannot unset it. We OR with the current value so the
--     flag is sticky.
-- ============================================================

-- ---------- 1. start_workout_session: pick the LATEST session ----------
drop function if exists public.start_workout_session(int);
create or replace function public.start_workout_session(
  p_day_index int
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_today date := (now() at time zone 'Asia/Dhaka')::date;
  v_session_id uuid;
  v_total int;
begin
  -- Reuse the LATEST unfinished session from today if one exists.
  -- ORDER BY started_at DESC LIMIT 1 is the deterministic fix: without
  -- it, Postgres returns rows in arbitrary order when more than one
  -- session exists for (user, today), which causes the routine list
  -- to read a session whose items don't include the lazily-created
  -- row the user just persisted.
  select id into v_session_id
  from public.workout_sessions
  where user_id = v_user and session_date = v_today
  order by started_at desc
  limit 1;
  if v_session_id is not null then
    return v_session_id;
  end if;

  select count(*) into v_total
  from public.workout_assignments
  where user_id = v_user and day_index = p_day_index and is_active;

  insert into public.workout_sessions (user_id, session_date, program_day, total_items, started_at)
  values (v_user, v_today, p_day_index, v_total, now())
  returning id into v_session_id;

  -- Pre-create one session_item per assignment so the timer UI can
  -- update rows in place rather than juggling "current exercise".
  insert into public.workout_session_items (session_id, workout_id, position)
  select v_session_id, a.workout_id, a.position
  from public.workout_assignments a
  where a.user_id = v_user and a.day_index = p_day_index and a.is_active;

  return v_session_id;
end $$;

grant execute on function public.start_workout_session(int) to authenticated;

-- ---------- 2. get_today_workout: pick the LATEST session ----------
drop function if exists public.get_today_workout(int);
create or replace function public.get_today_workout(
  p_day_index int default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_today date := (now() at time zone 'Asia/Dhaka')::date;
  v_day int := coalesce(p_day_index, public.calendar_day_to_index());
  v_assignments jsonb;
  v_session jsonb;
begin
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'workout_id', w.id,
      'name_bn', w.name_bn,
      'name_en', w.name_en,
      'category', w.category,
      'intensity', w.intensity,
      'target_duration_seconds', w.target_duration_seconds,
      'target_calories_kcal', w.target_calories_kcal,
      'description_bn', w.description_bn,
      'instructions', w.instructions,
      'instructions_bn', w.instructions_bn,
      'equipment', w.equipment,
      'video_url', w.video_url,
      'position', a.position
    ) order by a.position, w.name_bn
  ), '[]'::jsonb)
  into v_assignments
  from public.workout_assignments a
  join public.workouts w on w.id = a.workout_id and w.is_active
  where a.user_id = v_user and a.day_index = v_day and a.is_active;

  -- ORDER BY s.started_at DESC LIMIT 1 ensures the routine list reads
  -- the same session that the user has been actively persisting to.
  -- Mirrors the fix in start_workout_session above.
  select jsonb_build_object(
    'id', s.id,
    'session_date', s.session_date,
    'program_day', s.program_day,
    'started_at', s.started_at,
    'finished_at', s.finished_at,
    'total_duration_seconds', s.total_duration_seconds,
    'completed_items', s.completed_items,
    'total_items', s.total_items,
    'is_finished', s.is_finished,
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', i.id,
          'workout_id', i.workout_id,
          'position', i.position,
          'is_completed', i.is_completed,
          'started_at', i.started_at,
          'finished_at', i.finished_at,
          'duration_seconds', i.duration_seconds
        ) order by i.position
      )
      from public.workout_session_items i where i.session_id = s.id
    ), '[]'::jsonb)
  )
  into v_session
  from public.workout_sessions s
  where s.user_id = v_user and s.session_date = v_today
  order by s.started_at desc
  limit 1;

  return jsonb_build_object(
    'day_index', v_day,
    'today', v_today,
    'assignments', v_assignments,
    'session', v_session
  );
end $$;

grant execute on function public.get_today_workout(int) to authenticated;

-- ---------- 3. finish_workout_session_item: make is_completed sticky ----------
drop function if exists public.finish_workout_session_item(uuid, text, uuid, int, boolean);
create or replace function public.finish_workout_session_item(
  p_item_id uuid default null,
  p_workout_id text default null,
  p_session_id uuid default null,
  p_duration_seconds int default 0,
  p_completed boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_session uuid;
  v_item    uuid;
begin
  -- 1. Resolve the parent session.
  if p_session_id is not null then
    select id into v_session
    from public.workout_sessions
    where id = p_session_id and user_id = v_user;
  end if;

  -- 2. Try the legacy path: caller supplied an item_id that still
  --    points at one of the user's existing session_items.
  if p_item_id is not null then
    select i.session_id, i.id into v_session, v_item
    from public.workout_session_items i
    join public.workout_sessions s on s.id = i.session_id
    where i.id = p_item_id and s.user_id = v_user;
  end if;

  -- 3. Look up by (session, workout) — covers the day-navigation case
  --    where the session was opened on a different day_index but the
  --    caller is exercising on a new day.
  if v_item is null and v_session is not null and p_workout_id is not null then
    select id into v_item
    from public.workout_session_items
    where session_id = v_session and workout_id = p_workout_id;

    -- 4. Lazy-create: if the session has no item for this workout yet
    --    (the session was started on a day_index that didn't include
    --    this exercise), insert one on the fly so the user's timer
    --    always succeeds. Position comes from the active assignment
    --    for today so the day's ordering stays consistent.
    if v_item is null then
      insert into public.workout_session_items (session_id, workout_id, position)
      select v_session, p_workout_id,
             coalesce((
               select a.position from public.workout_assignments a
               where a.user_id = v_user
                 and a.is_active
                 and a.workout_id = p_workout_id
               order by a.day_index
               limit 1
             ), 0)
      returning id into v_item;
    end if;
  end if;

  if v_item is null then
    raise exception 'workout item not found (no session for this user)';
  end if;

  -- is_completed is now MONOTONIC: once true, a later call with
  -- p_completed = false (e.g. a pause right after auto-complete, or a
  -- stale client retry) cannot unset it. `p_completed OR is_completed`
  -- gives the desired "sticky completion" behaviour without changing
  -- duration_seconds semantics.
  update public.workout_session_items i
  set is_completed = (p_completed or i.is_completed),
      duration_seconds = greatest(duration_seconds, p_duration_seconds),
      started_at = coalesce(started_at, case when p_duration_seconds > 0 then now() - make_interval(secs => p_duration_seconds) else null end),
      finished_at = case when (p_completed or i.is_completed) then coalesce(i.finished_at, now()) else finished_at end,
      updated_at = now()
  where i.id = v_item;

  -- Roll up totals on the parent session.
  update public.workout_sessions s
  set total_duration_seconds = coalesce((
        select sum(duration_seconds) from public.workout_session_items
        where session_id = s.id
      ), 0),
      completed_items = coalesce((
        select count(*) from public.workout_session_items
        where session_id = s.id and is_completed
      ), 0),
      updated_at = now()
  where s.id = v_session;

  return v_item;
end $$;

grant execute on function public.finish_workout_session_item(uuid, text, uuid, int, boolean) to authenticated;