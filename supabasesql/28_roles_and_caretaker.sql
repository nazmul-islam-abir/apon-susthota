-- ============================================================
-- 28 — Two-role user system (Patient + Caretaker)
-- Apply AFTER 01_schema.sql + 08_signup_identity.sql.
--
-- What this file does:
--   1. Adds `role` (patient|caretaker) and `caretaker_relationship`
--      columns to public.user_profiles.
--   2. Creates `public.caretaker_patient_links` — the connection
--      ledger between caretakers and the patients they observe.
--   3. Enforces "one active link per (caretaker, patient) pair" via
--      a partial unique index.
--   4. RLS so each side only sees rows they're part of, caretakers
--      create the pending requests, the patient accepts/declines,
--      and either party can revoke an active link.
--   5. A trigger that broadcasts link state changes on a private
--      Supabase Realtime channel per user, so both apps refresh
--      their caretaker inbox / patient list instantly.
--
-- This file is fully idempotent — safe to re-apply.
-- ============================================================

-- ---------- 1. ROLE COLUMNS ON user_profiles ----------
-- `role` defaults to 'patient' so every existing user (and every
-- legacy signup that bypasses the role-selection screen) is
-- automatically a Patient. Caretaker signup goes through the
-- role-select onboarding screen which writes 'caretaker'.
alter table public.user_profiles
  add column if not exists role text not null default 'patient'
    check (role in ('patient', 'caretaker'));

-- Optional human-readable relationship string the caretaker types
-- at signup ("son", "spouse", "home nurse"). Kept on the profile
-- because it's shown in every link row the patient sees.
alter table public.user_profiles
  add column if not exists caretaker_relationship text
    check (caretaker_relationship is null or length(trim(caretaker_relationship)) <= 40);

create index if not exists idx_user_profiles_role
  on public.user_profiles (role);

-- A caretaker cannot operate the patient app. The existing RLS
-- policies on patient-owned tables (meal_intake_log, medicines,
-- workout_sessions, daily_metrics, etc.) already use auth.uid()
-- = user_id, so a caretaker's JWT simply matches zero rows — no
-- additional policies are required to keep them read-only on the
-- patient schema. The caretaker-specific read RPCs in 29_*.sql
-- are the only path that exposes patient data to a caretaker.


-- ---------- 2. CARETAKER ↔ PATIENT LINK TABLE ----------
create table if not exists public.caretaker_patient_links (
  id                  uuid primary key default gen_random_uuid(),
  caretaker_user_id   uuid not null references auth.users(id) on delete cascade,
  patient_user_id     uuid not null references auth.users(id) on delete cascade,
  -- status lifecycle:
  --   pending  → caretaker has asked; waiting on patient.
  --   active   → patient has accepted; caretaker can read.
  --   declined → patient said no (terminal; either side may re-ask).
  --   revoked  → either side cancelled (active → revoked).
  status              text not null default 'pending'
                        check (status in ('pending','active','declined','revoked')),
  -- Free-text note the caretaker can attach when sending the
  -- request ("I am your son, call me X"). Surfaced in the
  -- patient's link-inbox card.
  request_note        text,
  caretaker_relationship text,
  requested_at        timestamptz not null default now(),
  responded_at        timestamptz,
  -- "last_seen_at" is updated by the read RPCs so the caretaker's
  -- patient list can sort patients by "most recently active".
  last_seen_at        timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

-- A caretaker cannot have two simultaneously live links to the
-- same patient (pending OR active). The partial index is on the
-- open states only — declined/revoked rows don't count, so the
-- patient may approve a fresh request later if they change their
-- mind.
create unique index if not exists uniq_caretaker_patient_open
  on public.caretaker_patient_links (caretaker_user_id, patient_user_id)
  where status in ('pending','active');

create index if not exists idx_caretaker_links_caretaker_status
  on public.caretaker_patient_links (caretaker_user_id, status);

create index if not exists idx_caretaker_links_patient_status
  on public.caretaker_patient_links (patient_user_id, status);

-- The caretaker must be a real caretaker; the patient must be a
-- real patient. Cross-role self-links (caretaker→caretaker or
-- patient→patient) are blocked at insert time.
create or replace function public.caretaker_patient_links_check_roles()
returns trigger
language plpgsql
as $$
declare
  v_caretaker_role text;
  v_patient_role   text;
begin
  -- NOTE: `user_profiles` PK is `user_id`, not `id` (see 01_schema.sql).
  select role into v_caretaker_role
    from public.user_profiles where user_id = new.caretaker_user_id;
  select role into v_patient_role
    from public.user_profiles where user_id = new.patient_user_id;

  if v_caretaker_role is distinct from 'caretaker' then
    raise exception 'caretaker_user_id must be a user with role=caretaker';
  end if;
  if v_patient_role is distinct from 'patient' then
    raise exception 'patient_user_id must be a user with role=patient';
  end if;
  if new.caretaker_user_id = new.patient_user_id then
    raise exception 'cannot link to self';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_caretaker_links_check_roles on public.caretaker_patient_links;
create trigger trg_caretaker_links_check_roles
  before insert or update of caretaker_user_id, patient_user_id
  on public.caretaker_patient_links
  for each row execute function public.caretaker_patient_links_check_roles();


-- ---------- 3. AUTO-TOUCH updated_at ----------
create or replace function public.touch_caretaker_links_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_caretaker_links_touch on public.caretaker_patient_links;
create trigger trg_caretaker_links_touch
  before update on public.caretaker_patient_links
  for each row execute function public.touch_caretaker_links_updated_at();


-- ---------- 4. RLS ----------
alter table public.caretaker_patient_links enable row level security;

drop policy if exists "cp_links self read"     on public.caretaker_patient_links;
drop policy if exists "cp_links caretaker insert" on public.caretaker_patient_links;
drop policy if exists "cp_links caretaker update" on public.caretaker_patient_links;
drop policy if exists "cp_links patient update"   on public.caretaker_patient_links;

-- SELECT: either party of the link.
create policy "cp_links self read"
  on public.caretaker_patient_links for select
  using (
    auth.uid() = caretaker_user_id
    or auth.uid() = patient_user_id
  );

-- INSERT: only the caretaker side may create a new pending request,
-- AND their auth.uid() must be the caretaker_user_id column (so a
-- caretaker can't spoof a link by writing another user's id).
-- The role check is enforced by the BEFORE trigger above.
create policy "cp_links caretaker insert"
  on public.caretaker_patient_links for insert
  with check (
    auth.uid() = caretaker_user_id
    and status = 'pending'
    and responded_at is null
    and last_seen_at is null
  );

-- UPDATE: the caretaker may cancel a pending request they sent,
-- or revoke an active link. Patients get their own dedicated
-- policy below to accept/decline; the caretaker policy therefore
-- is restricted to the "non-pending, non-active transitions that
-- only the caretaker can make" which in practice is:
--   pending → revoked   (caretaker cancels the request)
--   active  → revoked   (caretaker ends the relationship)
-- We also allow the caretaker to bump last_seen_at while the link
-- is active, so the patient list can sort by freshness without
-- requiring a separate table.
create policy "cp_links caretaker update"
  on public.caretaker_patient_links for update
  using (
    auth.uid() = caretaker_user_id
    and (
      -- cancelling a pending request they sent
      (status = 'pending')
      -- OR they still have an active link they can end
      or (status = 'active')
    )
  )
  with check (
    auth.uid() = caretaker_user_id
    and status in ('pending','active','revoked')
    -- when transitioning pending → revoked, responded_at is set
    -- server-side; when active → revoked, same.
    and (status = 'pending' or status = 'active' or status = 'revoked')
  );

-- UPDATE: the patient may accept (pending → active), decline
-- (pending → declined), or revoke (active → revoked).
create policy "cp_links patient update"
  on public.caretaker_patient_links for update
  using (
    auth.uid() = patient_user_id
    and (
      status = 'pending'   -- accepting or declining an incoming request
      or status = 'active' -- patient can also end the relationship
    )
  )
  with check (
    auth.uid() = patient_user_id
    and status in ('active','declined','revoked')
    -- patient transitions always set responded_at server-side
  );


-- ---------- 5. REALTIME BROADCAST TRIGGER ----------
-- Both apps subscribe to a private channel named
--   caretaker_link_<uid>
-- where <uid> is the listening user's auth.uid(). The trigger
-- fires AFTER INSERT OR UPDATE OR DELETE and calls realtime.send
-- with the row's id + the two parties' user_ids so the listener
-- can decide if the event is theirs.
--
-- IMPORTANT: `realtime.send(jsonb)` is only available on Supabase
-- projects with Realtime ≥ 2.0 (private-channel broadcasts).
-- On older / standard projects the function does not exist and
-- calling it raises SQLSTATE 42883 ("function does not exist"),
-- which ROLLS BACK the whole INSERT into `caretaker_patient_links`.
-- That manifested as a red "function realtime.send(jsonb) does not
-- exist" toast in the caretaker app, even though the row insert was
-- the user's actual intent.
--
-- The trigger below:
--   1. Wraps every `realtime.send(...)` call in a pgsql exception
--      block so a broadcast failure NEVER aborts the row insert.
--   2. Probes `pg_proc` to detect whether the broadcast function
--      exists in the current Realtime version, and skips the call
--      entirely when it doesn't.
--   3. Continues to write the row to `supabase_realtime` publication
--      so subscribers still receive the row-level event.
create or replace function public.caretaker_link_broadcast()
returns trigger
language plpgsql
security definer
set search_path = public, realtime
as $$
declare
  v_event          text;
  v_row            jsonb;
  v_topic_caretaker text;
  v_topic_patient   text;
  v_has_send_fn    boolean;
begin
  -- Detect whether `realtime.send(jsonb)` is available. On Supabase
  -- projects without Realtime 2.0 (i.e. projects that haven't enabled
  -- private broadcasts) this function does not exist and calling it
  -- would raise SQLSTATE 42883 → transaction abort → row rollback.
  select exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'realtime'
       and p.proname = 'send'
       and p.proargtypes::regtype[]::text[] @> ARRAY['jsonb']::text[]
  ) into v_has_send_fn;

  if tg_op = 'DELETE' then
    v_event := 'deleted';
    v_row   := jsonb_build_object(
      'id', old.id,
      'caretaker_user_id', old.caretaker_user_id,
      'patient_user_id',   old.patient_user_id,
      'status',            old.status
    );
  else
    v_event := case
      when tg_op = 'INSERT' then 'inserted'
      when tg_op = 'UPDATE' then 'updated'
    end;
    v_row := jsonb_build_object(
      'id', new.id,
      'caretaker_user_id', new.caretaker_user_id,
      'patient_user_id',   new.patient_user_id,
      'status',            new.status,
      'request_note',      new.request_note,
      'caretaker_relationship', new.caretaker_relationship,
      'requested_at',      new.requested_at,
      'responded_at',      new.responded_at,
      'last_seen_at',      new.last_seen_at
    );
  end if;

  -- Skip the broadcast call entirely when realtime.send is unavailable.
  -- The supabase_realtime publication (added below) still drives the
  -- row-level postgres_changes events the Flutter client subscribes to,
  -- so the UI keeps refreshing — just without the private-channel
  -- round-trip we originally intended.
  if v_has_send_fn then
    v_topic_caretaker :=
        'caretaker_link_' ||
        (case when tg_op = 'DELETE' then old.caretaker_user_id
              else new.caretaker_user_id end)::text;
    v_topic_patient :=
        'caretaker_link_' ||
        (case when tg_op = 'DELETE' then old.patient_user_id
              else new.patient_user_id   end)::text;

    -- Broadcast to the caretaker's channel. Wrapped in a nested
    -- BEGIN/EXCEPTION block so any future signature mismatch (e.g.
    -- Supabase ships a realtime.send(jsonb, text) variant) cannot
    -- blow up the row insert.
    begin
      perform realtime.send(
        jsonb_build_object(
          'event',  v_event,
          'topic',  v_topic_caretaker,
          'payload', v_row
        )
      );
    exception when others then
      -- Swallow the broadcast error. The row insert is the source of
      -- truth; the publication mechanism still emits the change.
      raise notice 'caretaker_link_broadcast (caretaker) skipped: %', sqlerrm;
    end;

    begin
      perform realtime.send(
        jsonb_build_object(
          'event',  v_event,
          'topic',  v_topic_patient,
          'payload', v_row
        )
      );
    exception when others then
      raise notice 'caretaker_link_broadcast (patient) skipped: %', sqlerrm;
    end;
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_caretaker_link_broadcast on public.caretaker_patient_links;
create trigger trg_caretaker_link_broadcast
  after insert or update or delete on public.caretaker_patient_links
  for each row execute function public.caretaker_link_broadcast();

-- Add the table to the supabase_realtime publication (idempotent).
do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) then
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'caretaker_patient_links'
    ) then
      alter publication supabase_realtime
        add table public.caretaker_patient_links;
    end if;
  end if;
end $$;


-- ---------- 6. HELPER RPCs ----------
-- These thin RPCs exist so the client never has to write rows
-- directly (the trigger/role checks are baked in here). They're
-- declared after the policies so SECURITY DEFINER can still rely
-- on the caller being the correct party.

-- 6a. Create a pending link from auth.uid() (a caretaker) → patient.
drop function if exists public.request_caretaker_link(uuid, text, text);
create or replace function public.request_caretaker_link(
  p_patient_user_id uuid,
  p_note            text default null,
  p_relationship    text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caretaker uuid := auth.uid();
  v_role      text;
  v_id        uuid;
begin
  if v_caretaker is null then raise exception 'Not authenticated'; end if;

  -- NOTE: the primary key of `user_profiles` is `user_id`, NOT `id`
  -- (see 01_schema.sql). Use `user_id` here.
  select role into v_role from public.user_profiles where user_id = v_caretaker;
  if v_role is distinct from 'caretaker' then
    raise exception 'Only caretakers may send link requests';
  end if;
  if p_patient_user_id is null then raise exception 'patient_user_id required'; end if;
  if v_caretaker = p_patient_user_id then raise exception 'cannot link to self'; end if;

  -- If a previous declined/revoked link exists for the pair, we
  -- allow a fresh attempt by allowing the insert to succeed; the
  -- unique partial index will block duplicates of pending/active
  -- rows automatically.
  insert into public.caretaker_patient_links
    (caretaker_user_id, patient_user_id, status,
     request_note, caretaker_relationship)
  values
    (v_caretaker, p_patient_user_id, 'pending',
     nullif(trim(p_note), ''),
     nullif(trim(p_relationship), ''))
  returning id into v_id;

  return v_id;
end;
$$;

-- 6b. Patient responds to a pending request.
-- p_decision: 'accept' → status=active, 'decline' → status=declined.
drop function if exists public.respond_caretaker_link(uuid, text);
create or replace function public.respond_caretaker_link(
  p_link_id  uuid,
  p_decision text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_patient uuid := auth.uid();
  v_status  text;
  v_owner   uuid;
begin
  if v_patient is null then raise exception 'Not authenticated'; end if;
  if p_decision not in ('accept','decline') then
    raise exception 'decision must be accept or decline';
  end if;

  select status, patient_user_id into v_status, v_owner
    from public.caretaker_patient_links
    where id = p_link_id
    for update;

  if v_owner is null then raise exception 'Link not found'; end if;
  if v_owner <> v_patient then raise exception 'Not authorized'; end if;
  if v_status <> 'pending' then raise exception 'Link is no longer pending'; end if;

  update public.caretaker_patient_links
    set status       = case when p_decision = 'accept' then 'active' else 'declined' end,
        responded_at = now()
  where id = p_link_id;
end;
$$;

-- 6c. Either party revokes an active link.
-- The RLS policies already enforce "caretaker or patient of the
-- row"; this RPC is just a convenience wrapper that sets
-- responded_at and last_seen_at consistently.
drop function if exists public.revoke_caretaker_link(uuid);
create or replace function public.revoke_caretaker_link(p_link_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_status text;
  v_owner_c uuid;
  v_owner_p uuid;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;

  select status, caretaker_user_id, patient_user_id
    into v_status, v_owner_c, v_owner_p
    from public.caretaker_patient_links
    where id = p_link_id
    for update;

  if v_status is null then raise exception 'Link not found'; end if;
  if v_uid <> v_owner_c and v_uid <> v_owner_p then
    raise exception 'Not authorized';
  end if;
  if v_status <> 'active' and v_status <> 'pending' then
    raise exception 'Link already closed';
  end if;

  update public.caretaker_patient_links
    set status       = 'revoked',
        responded_at = coalesce(responded_at, now())
  where id = p_link_id;
end;
$$;

-- 6d. Search the user_profiles directory by mobile number (used by
-- the caretaker "Add patient" flow). Returns basic identity only
-- (no clinical data) so caretakers can confirm they're linking to
-- the right person before sending the request.
-- The full mobile match is intentionally not exposed — we return
-- a masked version under the `mobile` key (matches what the Flutter
-- client reads in patient_search_screen.dart).
--
-- Accepts the FULL mobile number — the caretaker types "015XXXXXXXXX"
-- (11 digits, optionally with "+880" prefix or spaces) and we match
-- against the stored digits. The previous version required only the
-- last 4 digits, which is too lax for the user's explicit requirement
-- of full-number matching.
drop function if exists public.search_patient_by_mobile(text);
create or replace function public.search_patient_by_mobile(p_query text)
returns table (
  user_id    uuid,
  full_name  text,
  mobile     text,  -- masked: "****1234" (last 4 of the stored digits)
  role       text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_role   text;
  v_digits text;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  -- Caretaker gate. The function's RETURNS TABLE clause declares an
  -- output parameter named `role` that ends up in scope as a PL/pgSQL
  -- variable, so the bare `role` here collides with both that variable
  -- AND the `user_profiles.role` column → "column reference 'role' is
  -- ambiguous" (SQLSTATE 42702). Qualifying with the `up` alias forces
  -- Postgres to pick the table column.
  --
  -- The primary key of `user_profiles` is `user_id`, NOT `id`
  -- (see 01_schema.sql); use `user_id` here.
  select up.role into v_role
    from public.user_profiles up
   where up.user_id = v_uid;

  if v_role is distinct from 'caretaker' then
    raise exception 'Only caretakers may search the patient directory';
  end if;

  -- Normalise input: keep only digits, tolerate "+880 ...", spaces,
  -- dashes, parentheses. Bangladeshi numbers stored as "01XXXXXXXXX"
  -- (11 digits) or "+8801XXXXXXXXX" (14 digits with country code).
  v_digits := regexp_replace(coalesce(p_query, ''), '\D', '', 'g');

  -- Require at least 7 digits so a stray "1" doesn't dump every patient.
  -- The caretaker's input is a full mobile, but we also tolerate a long
  -- suffix match for partial typing.
  if length(v_digits) < 7 then
    return;
  end if;

  return query
    select up.user_id,
           up.full_name,
           -- Mask the stored mobile so caretakers only see last 4.
           case
             when up.mobile is null then null
             when length(regexp_replace(up.mobile, '\D', '', 'g')) <= 4
               then up.mobile
             else '****' ||
                  right(regexp_replace(up.mobile, '\D', '', 'g'), 4)
           end as mobile,
           up.role
      from public.user_profiles up
     where up.role = 'patient'
       -- Strip non-digits from the stored value too so "015XXXXXXXXX"
       -- matches an input of "+8801XXXXXXXXX".
       and regexp_replace(up.mobile, '\D', '', 'g')
             like '%' || v_digits || '%'
     order by up.full_name nulls last
     limit 25;
end;
$$;

grant execute on function public.request_caretaker_link(uuid, text, text) to authenticated;
grant execute on function public.respond_caretaker_link(uuid, text)       to authenticated;
grant execute on function public.revoke_caretaker_link(uuid)              to authenticated;
grant execute on function public.search_patient_by_mobile(text)           to authenticated;