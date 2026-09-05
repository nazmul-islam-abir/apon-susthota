-- ============================================================
-- 60 — Voice messages: tables, storage bucket, RLS
--
-- Adds the scheduled-voice-message feature:
--   * voice_schedules   — caretaker-queued delivery (timezone + wall-clock)
--   * voice_messages    — materialized rows the patient actually sees,
--                         plus the patient's reply that goes back to the
--                         caretaker
--   * "voice" storage bucket with per-object RLS
--
-- Apply AFTER 28_roles_and_caretaker.sql, 30_caretaker_write_passthrough.sql,
-- 44_caretaker_full_read_rpcs.sql, 45_caretaker_care_doctor.sql,
-- 53_caretaker_patient_data_realtime.sql, 54_caretaker_realtime_subscription.sql.
--
-- The materialize_due_voice_schedules() function + pg_cron job live in
-- 61_voice_cron.sql. Realtime RLS + publication extension live in
-- 62_voice_realtime.sql. Caretaker-side passthrough RPCs live in
-- 63_voice_passthrough.sql.
--
-- Safe to re-run.
-- ============================================================


-- ============================================================
-- SECTION 0 — tg_set_updated_at() trigger helper
-- ============================================================
-- Shared `BEFORE UPDATE` trigger that bumps `updated_at = now()`.
-- Must be created BEFORE any trigger that references it, otherwise
-- PostgreSQL throws `function does not exist` at trigger-creation
-- time. Other migrations in this repo use the same helper, but
-- we redeclare it here so this file is self-contained and
-- idempotent on a fresh project.
create or replace function public.tg_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;


-- ============================================================
-- SECTION A — voice_schedules
-- ============================================================
-- A caretaker records a clip, picks a timezone + wall-clock delivery
-- time, and a row is inserted here. A pg_cron job (61_*.sql) scans
-- this table every minute for pending rows whose deliver_at has
-- passed and copies them into voice_messages.
--
-- timezone is stored for UI round-tripping (display "Asia/Dhaka"
-- back to the user when listing schedules). deliver_at is stored
-- as timestamptz because the actual delivery decision is made by
-- the server clock.
create table if not exists public.voice_schedules (
  id                   uuid primary key default gen_random_uuid(),
  caretaker_user_id    uuid not null references auth.users(id) on delete cascade,
  patient_user_id      uuid not null references auth.users(id) on delete cascade,
  storage_path         text not null,
  duration_ms          int  not null check (duration_ms >= 0),
  timezone             text not null default 'Asia/Dhaka',
  deliver_at           timestamptz not null,
  caption              text,
  status               text not null default 'pending'
                         check (status in ('pending','delivered','cancelled')),
  delivered_message_id uuid,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

create index if not exists idx_voice_schedules_due
  on public.voice_schedules (deliver_at)
  where status = 'pending';

create index if not exists idx_voice_schedules_caretaker
  on public.voice_schedules (caretaker_user_id, created_at desc);

create index if not exists idx_voice_schedules_patient
  on public.voice_schedules (patient_user_id, created_at desc);

-- Auto-update updated_at on UPDATE
drop trigger if exists trg_voice_schedules_touch on public.voice_schedules;
create trigger trg_voice_schedules_touch
  before update on public.voice_schedules
  for each row execute function public.tg_set_updated_at();


-- ============================================================
-- SECTION B — voice_messages
-- ============================================================
-- This is what the patient actually sees in their inbox. Caretaker
-- voices arrive here via the cron materialization. Patient replies
-- are inserted directly by the client (sender = patient).
--
-- thread_id groups a caretaker→patient voice with the patient's
-- reply (and any subsequent back-and-forth). We keep it loose —
-- any voice with a thread_id refers to a related voice. The
-- materialized insert from a schedule sets thread_id = the
-- schedule id so subsequent replies stay in the same thread.
create table if not exists public.voice_messages (
  id               uuid primary key default gen_random_uuid(),
  sender_user_id   uuid not null references auth.users(id) on delete cascade,
  receiver_user_id uuid not null references auth.users(id) on delete cascade,
  storage_path     text not null,
  duration_ms      int  not null check (duration_ms >= 0),
  caption          text,
  thread_id        uuid,
  is_reply         boolean not null default false,
  played_at        timestamptz,
  created_at       timestamptz not null default now()
);

create index if not exists idx_voice_messages_inbox
  on public.voice_messages (receiver_user_id, created_at desc);

create index if not exists idx_voice_messages_outbox
  on public.voice_messages (sender_user_id, created_at desc);

create index if not exists idx_voice_messages_thread
  on public.voice_messages (thread_id)
  where thread_id is not null;


-- ============================================================
-- SECTION C — Storage bucket "voice"
-- ============================================================
-- Private. Voice bytes are read with short-lived signed URLs.
insert into storage.buckets (id, name, public)
values ('voice', 'voice', false)
on conflict (id) do update set public = excluded.public;


-- ============================================================
-- SECTION D — storage.objects RLS
-- ============================================================
-- Object naming convention:
--   {sender_uid}/{receiver_uid}/{epoch_ms}.m4a
-- We require the first path segment to equal the caller's uid so a
-- user can never overwrite another user's voice.
--
-- Read: the sender or receiver of the voice, OR the active
--       caretaker of either side (so the caretaker UI can play
--       outgoing voices they recorded).
-- Write (insert/update): only the sender (first path segment).
-- Delete: only the sender.

drop policy if exists "Voice upload: sender folder only"
  on storage.objects;
create policy "Voice upload: sender folder only"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'voice'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Voice update: sender folder only"
  on storage.objects;
create policy "Voice update: sender folder only"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'voice'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'voice'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Voice delete: sender folder only"
  on storage.objects;
create policy "Voice delete: sender folder only"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'voice'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Voice read: sender / receiver / linked caretaker"
  on storage.objects;
create policy "Voice read: sender / receiver / linked caretaker"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'voice'
    and (
      -- The caller recorded this voice.
      (storage.foldername(name))[1] = auth.uid()::text
      or
      -- The caller is the intended recipient.
      (storage.foldername(name))[2] = auth.uid()::text
      or
      -- The caller is the active caretaker of the sender …
      public.is_active_caretaker_of(((storage.foldername(name))[1])::uuid)
      or
      -- … or the active caretaker of the recipient.
      public.is_active_caretaker_of(((storage.foldername(name))[2])::uuid)
    )
  );


-- ============================================================
-- SECTION E — voice_messages RLS (write path is sender-only;
-- read path mirrors 54_*.sql — sender / receiver / active
-- caretaker of either party)
-- ============================================================

alter table public.voice_messages enable row level security;

drop policy if exists "Voice messages: sender / receiver / linked caretaker may read"
  on public.voice_messages;
create policy "Voice messages: sender / receiver / linked caretaker may read"
  on public.voice_messages for select
  to authenticated
  using (
    auth.uid() = sender_user_id
    or auth.uid() = receiver_user_id
    or public.is_active_caretaker_of(sender_user_id)
    or public.is_active_caretaker_of(receiver_user_id)
  );

-- Only the sender may insert (caretaker replies go via passthrough
-- RPC in 63_*.sql which impersonates auth.uid() for the patient).
drop policy if exists "Voice messages: sender may insert"
  on public.voice_messages;
create policy "Voice messages: sender may insert"
  on public.voice_messages for insert
  to authenticated
  with check (auth.uid() = sender_user_id);

drop policy if exists "Voice messages: receiver may mark played"
  on public.voice_messages;
create policy "Voice messages: receiver may mark played"
  on public.voice_messages for update
  to authenticated
  using (auth.uid() = receiver_user_id)
  with check (auth.uid() = receiver_user_id);


-- ============================================================
-- SECTION F — voice_schedules RLS
-- ============================================================
-- The caretaker who created the schedule can read + cancel it.
-- The patient can read it (so they can preview pending deliveries).
-- Only the caretaker can insert / update.

alter table public.voice_schedules enable row level security;

drop policy if exists "Voice schedules: caretaker and patient may read"
  on public.voice_schedules;
create policy "Voice schedules: caretaker and patient may read"
  on public.voice_schedules for select
  to authenticated
  using (
    auth.uid() = caretaker_user_id
    or auth.uid() = patient_user_id
  );

drop policy if exists "Voice schedules: caretaker may insert own"
  on public.voice_schedules;
create policy "Voice schedules: caretaker may insert own"
  on public.voice_schedules for insert
  to authenticated
  with check (auth.uid() = caretaker_user_id);

-- Caretaker may cancel their own schedule (flip status).
drop policy if exists "Voice schedules: caretaker may cancel own"
  on public.voice_schedules;
create policy "Voice schedules: caretaker may cancel own"
  on public.voice_schedules for update
  to authenticated
  using (auth.uid() = caretaker_user_id)
  with check (auth.uid() = caretaker_user_id);


-- ============================================================
-- SECTION G — tg_set_updated_at() trigger helper
-- ============================================================
-- (Defined in Section 0 above so it's available before any
-- trigger references it. Kept as a section header here for the
-- file's table-of-contents layout; the function definition itself
-- is at the top.)
