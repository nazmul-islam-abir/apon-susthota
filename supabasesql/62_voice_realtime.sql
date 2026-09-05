-- ============================================================
-- 62 — Voice realtime publication
--
-- Adds voice_messages + voice_schedules to the supabase_realtime
-- publication so the patient's existing realtime subscription
-- (extended in supabase_service.dart to bind voice_messages) fires
-- onPostgresChanges when a new voice is materialized.
--
-- RLS SELECT policies for voice_messages and voice_schedules
-- already exist (60_*.sql) — they are the gate; the publication
-- here just wires them up for Realtime.
--
-- The pattern is identical to 54_caretaker_realtime_subscription.sql:
-- idempotent DO block, bail cleanly if the publication doesn't
-- exist on this project.
--
-- Safe to re-run.
-- ============================================================

do $$
begin
  if not exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) then
    raise notice 'supabase_realtime publication does not exist. Enable Realtime in Supabase Dashboard to receive live updates.';
    return;
  end if;

  -- voice_messages — the inbox table. Patient subscribes to rows
  -- where receiver_user_id = auth.uid(); caretaker subscribes to
  -- rows where they're the active caretaker of the patient.
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'voice_messages'
  ) then
    alter publication supabase_realtime add table public.voice_messages;
  end if;

  -- voice_schedules — caretaker UI shows "pending / delivered /
  -- cancelled" status. Adding to the publication lets the
  -- caretaker inbox auto-update when a schedule flips to
  -- delivered or is cancelled.
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'voice_schedules'
  ) then
    alter publication supabase_realtime add table public.voice_schedules;
  end if;
end $$;
