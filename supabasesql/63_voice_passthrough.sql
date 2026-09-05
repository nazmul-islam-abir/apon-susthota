-- ============================================================
-- 63 — Caretaker voice passthrough RPCs
--
-- Lets a caretaker:
--   * Schedule a voice message for a patient
--   * Cancel a still-pending schedule
--   * List their own schedules / inbox for a patient
--
-- The actual storage upload happens client-side (Flutter reads the
-- .m4a bytes, calls storage.from('voice').uploadBinary, then calls
-- these RPCs with the returned storage_path).
--
-- Pattern mirrors 45_caretaker_care_doctor.sql: assert the
-- caretaker link first, then route the write through SECURITY
-- DEFINER RPCs that impersonate via _caretaker_act_as(). We don't
-- need impersonation for the schedule INSERT (auth.uid() is the
-- caretaker), but we DO use it for any patient-side "play voice"
-- updates (mark_played passthrough) so the patient doesn't have
-- to be online at the moment of marking.
--
-- Apply AFTER 60_voice_messages.sql, 61_voice_cron.sql,
-- 62_voice_realtime.sql.
--
-- Safe to re-run.
-- ============================================================


-- ============================================================
-- SECTION A — caretaker_create_voice_schedule
-- ============================================================
-- Caretaker uploads the .m4a bytes to storage first (path
-- convention enforced by storage.objects RLS), then calls this
-- RPC with the resulting storage_path + duration + timezone +
-- deliver_at. Returns the new schedule id.
drop function if exists public.caretaker_create_voice_schedule(uuid, text, int, text, timestamptz, text);
create or replace function public.caretaker_create_voice_schedule(
  p_patient_user_id uuid,
  p_storage_path    text,
  p_duration_ms     int,
  p_timezone        text,
  p_deliver_at      timestamptz,
  p_caption         text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  perform public.assert_caretaker_can_read(p_patient_user_id);

  if p_storage_path is null or length(trim(p_storage_path)) = 0 then
    raise exception 'storage_path is required';
  end if;
  if p_duration_ms is null or p_duration_ms < 0 then
    raise exception 'duration_ms must be >= 0';
  end if;
  if p_deliver_at is null then
    raise exception 'deliver_at is required';
  end if;
  if p_deliver_at <= now() - interval '5 minutes' then
    raise exception 'deliver_at must be in the future (or near-now)';
  end if;

  insert into public.voice_schedules
    (caretaker_user_id, patient_user_id, storage_path,
     duration_ms, timezone, deliver_at, caption)
  values
    (auth.uid(), p_patient_user_id, p_storage_path,
     p_duration_ms, coalesce(nullif(trim(p_timezone), ''), 'Asia/Dhaka'),
     p_deliver_at, nullif(trim(p_caption), ''))
  returning id into v_id;

  return v_id;
end;
$$;
grant execute on function public.caretaker_create_voice_schedule(uuid, text, int, text, timestamptz, text)
  to authenticated;


-- ============================================================
-- SECTION B — caretaker_cancel_voice_schedule
-- ============================================================
drop function if exists public.caretaker_cancel_voice_schedule(uuid);
create or replace function public.caretaker_cancel_voice_schedule(p_schedule_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_status text;
begin
  select caretaker_user_id, status
    into v_owner, v_status
    from public.voice_schedules
   where id = p_schedule_id;

  if v_owner is null then
    raise exception 'Schedule not found';
  end if;
  if v_owner <> auth.uid() then
    raise exception 'Only the caretaker who created the schedule may cancel it';
  end if;
  if v_status <> 'pending' then
    raise exception 'Only pending schedules may be cancelled (current: %)', v_status;
  end if;

  update public.voice_schedules
     set status     = 'cancelled',
         updated_at = now()
   where id = p_schedule_id;
end;
$$;
grant execute on function public.caretaker_cancel_voice_schedule(uuid) to authenticated;


-- ============================================================
-- SECTION C — caretaker_send_voice_reply
-- ============================================================
-- Patient replies are inserted client-side (sender = auth.uid()).
-- But if a caretaker wants to send a follow-up voice to a patient
-- in response to a reply they received, they can use this RPC.
-- It's just a regular insert into voice_messages — the "is_reply"
-- flag distinguishes it from a freshly materialized schedule.
drop function if exists public.caretaker_send_voice_reply(uuid, text, int, text, uuid);
create or replace function public.caretaker_send_voice_reply(
  p_patient_user_id uuid,
  p_storage_path    text,
  p_duration_ms     int,
  p_caption         text,
  p_thread_id       uuid
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  perform public.assert_caretaker_can_read(p_patient_user_id);

  if p_storage_path is null or length(trim(p_storage_path)) = 0 then
    raise exception 'storage_path is required';
  end if;
  if p_duration_ms is null or p_duration_ms < 0 then
    raise exception 'duration_ms must be >= 0';
  end if;

  insert into public.voice_messages
    (sender_user_id, receiver_user_id, storage_path,
     duration_ms, caption, thread_id, is_reply)
  values
    (auth.uid(), p_patient_user_id, p_storage_path,
     p_duration_ms, nullif(trim(p_caption), ''), p_thread_id, true)
  returning id into v_id;

  return v_id;
end;
$$;
grant execute on function public.caretaker_send_voice_reply(uuid, text, int, text, uuid)
  to authenticated;


-- ============================================================
-- SECTION D — mark_voice_played
-- ============================================================
-- The receiver taps play → server flips played_at. Works for both
-- patient (marking a caretaker voice) and caretaker (marking a
-- patient reply). SECURITY DEFINER so we can update regardless of
-- RLS — the policy in 60_*.sql already restricts to the receiver,
-- but the SECURITY DEFINER wrapper gives us a single RPC name to
-- call from the Flutter side and lets us validate cleanly.
drop function if exists public.mark_voice_played(uuid);
create or replace function public.mark_voice_played(p_message_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_receiver uuid;
begin
  select receiver_user_id into v_receiver
    from public.voice_messages
   where id = p_message_id;

  if v_receiver is null then
    raise exception 'Voice message not found';
  end if;
  if v_receiver <> auth.uid() then
    raise exception 'Only the receiver may mark a voice as played';
  end if;

  update public.voice_messages
     set played_at = now()
   where id = p_message_id
     and played_at is null;
end;
$$;
grant execute on function public.mark_voice_played(uuid) to authenticated;


-- ============================================================
-- SECTION E — read helpers (lists the caretaker UI needs)
-- ============================================================
-- These return jsonb so the Flutter client can map directly.

-- List schedules for one patient (the caretaker's view).
drop function if exists public.list_caretaker_voice_schedules(uuid);
create or replace function public.list_caretaker_voice_schedules(p_patient_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payload jsonb;
begin
  perform public.assert_caretaker_can_read(p_patient_user_id);

  select coalesce(jsonb_agg(row_to_json(s) order by s.deliver_at asc), '[]'::jsonb)
    into v_payload
    from (
      select id, caretaker_user_id, patient_user_id, storage_path,
             duration_ms, timezone, deliver_at, caption, status,
             delivered_message_id, created_at, updated_at
        from public.voice_schedules
       where caretaker_user_id = auth.uid()
         and patient_user_id   = p_patient_user_id
       order by deliver_at asc
    ) s;

  return v_payload;
end;
$$;
grant execute on function public.list_caretaker_voice_schedules(uuid) to authenticated;


-- List incoming voices for a patient (the caretaker's view of the
-- patient's inbox). Includes both materialized caretaker voices
-- AND any replies the patient sent back.
drop function if exists public.list_caretaker_voice_inbox(uuid);
create or replace function public.list_caretaker_voice_inbox(p_patient_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payload jsonb;
begin
  perform public.assert_caretaker_can_read(p_patient_user_id);

  select coalesce(jsonb_agg(row_to_json(m) order by m.created_at desc), '[]'::jsonb)
    into v_payload
    from (
      select vm.id, vm.sender_user_id, vm.receiver_user_id,
             vm.storage_path, vm.duration_ms, vm.caption,
             vm.thread_id, vm.is_reply, vm.played_at, vm.created_at,
             up.full_name as sender_name,
             up.username  as sender_username,
             up.avatar_url as sender_avatar_url
        from public.voice_messages vm
        left join public.user_profiles up
               on up.user_id = vm.sender_user_id
       where (vm.sender_user_id   = p_patient_user_id
              or vm.receiver_user_id = p_patient_user_id)
         and (vm.sender_user_id = auth.uid()
              or vm.receiver_user_id = auth.uid())
       order by vm.created_at desc
       limit 200
    ) m;

  return v_payload;
end;
$$;
grant execute on function public.list_caretaker_voice_inbox(uuid) to authenticated;


-- List the patient's own inbox (the patient calls this for their
-- VoiceInboxScreen).
drop function if exists public.list_my_voice_inbox();
create or replace function public.list_my_voice_inbox()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payload jsonb;
begin
  select coalesce(jsonb_agg(row_to_json(m) order by m.created_at desc), '[]'::jsonb)
    into v_payload
    from (
      select vm.id, vm.sender_user_id, vm.receiver_user_id,
             vm.storage_path, vm.duration_ms, vm.caption,
             vm.thread_id, vm.is_reply, vm.played_at, vm.created_at,
             up.full_name as sender_name,
             up.username  as sender_username,
             up.avatar_url as sender_avatar_url
        from public.voice_messages vm
        left join public.user_profiles up
               on up.user_id = vm.sender_user_id
       where vm.receiver_user_id = auth.uid()
       order by vm.created_at desc
       limit 200
    ) m;

  return v_payload;
end;
$$;
grant execute on function public.list_my_voice_inbox() to authenticated;


-- List all voice messages in a thread (for the chat-style thread
-- view inside VoiceInboxScreen).
drop function if exists public.list_voice_thread(uuid);
create or replace function public.list_voice_thread(p_thread_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payload jsonb;
begin
  select coalesce(jsonb_agg(row_to_json(m) order by m.created_at asc), '[]'::jsonb)
    into v_payload
    from (
      select vm.id, vm.sender_user_id, vm.receiver_user_id,
             vm.storage_path, vm.duration_ms, vm.caption,
             vm.thread_id, vm.is_reply, vm.played_at, vm.created_at,
             up.full_name as sender_name,
             up.username  as sender_username,
             up.avatar_url as sender_avatar_url
        from public.voice_messages vm
        left join public.user_profiles up
               on up.user_id = vm.sender_user_id
       where vm.thread_id = p_thread_id
         and (auth.uid() = vm.sender_user_id
              or auth.uid() = vm.receiver_user_id
              or public.is_active_caretaker_of(vm.sender_user_id)
              or public.is_active_caretaker_of(vm.receiver_user_id))
       order by vm.created_at asc
    ) m;

  return v_payload;
end;
$$;
grant execute on function public.list_voice_thread(uuid) to authenticated;
