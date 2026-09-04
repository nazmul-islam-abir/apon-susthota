-- ============================================================
-- DIAGNOSIS: why the caretaker reads 0 even though the
-- patient's row in daily_metrics has 1.75 L.
--
-- Run each query ONE at a time in the Supabase SQL editor.
-- The expected value is shown beneath each query in a comment.
-- ============================================================


-- ─── 1. Does the caretaker-side RPC actually exist? ──────────
-- (If this returns 0 rows, you forgot to run 44_caretaker_full_read_rpcs.sql
--  or 54_fix_caretaker_realtime_sync.sql — run them now.)
select proname, pronargs
  from pg_proc
 where proname in (
   'get_caretaker_today_daily_metrics',
   'get_caretaker_daily_metrics_for_date',
   'get_caretaker_water_analytics',
   'assert_caretaker_can_read'
 )
order by proname;
-- Expected: 4 rows.


-- ─── 2. Does the link row exist for the caretaker? ──────────
-- Replace 'CARETAKER_UUID' with the caretaker user id
-- (visible in Supabase → Authentication → Users), and
-- 'PATIENT_UUID' with the patient user id (892657f6-b6bc-4530-a81c-fa7d2da0eb83).
select *
  from public.caretaker_patient_links
 where caretaker_user_id = 'f7fe89ca-6830-481e-914a-dca631ec52f8'
   and patient_user_id   = '892657f6-b6bc-4530-a81c-fa7d2da0eb83';
-- Expected: at least one row with status = 'active'.


-- ─── 3. Simulate the caretaker's exact RPC call as SQL ──────
-- If this returns 1.75, the data is fine. If it returns 0,
-- then the SECURITY DEFINER RPC is hitting the wrong row, or
-- assert_caretaker_can_read is throwing.
select jsonb_build_object(
         'water_liters',   coalesce(dm.water_liters, 0),
         'heart_rate_bpm', coalesce(dm.heart_rate_bpm, 0),
         'steps',          coalesce(dm.steps, 0),
         'has_data',       (dm.user_id is not null)
       ) as rpc_response
  from public.daily_metrics dm
 where dm.user_id = '892657f6-b6bc-4530-a81c-fa7d2da0eb83'
   and dm.metric_date = (now() at time zone 'Asia/Dhaka')::date;
-- Expected: {"water_liters": 1.75, ... }


-- ─── 4. Most important — actually CALL the caretaker RPC ────
-- Replace 'CARETAKER_UUID' below.
-- (If you don't know how to impersonate auth.uid(), do this:
--   a. Sign in as the caretaker in the app
--   b. Open the caretaker's water view
--   c. Watch the network tab — the RPC payload will tell you
--      whether it returned {water_liters: 1.75} or an error.)
-- For now, run this as a privileged user (postgres role):
select public.get_caretaker_today_daily_metrics(
  '892657f6-b6bc-4530-a81c-fa7d2da0eb83'::uuid
) as result;
-- Expected: {"water_liters": 1.75, "has_data": true, ...}


-- ─── 5. (OPTIONAL) If step 4 throws "No active link to this
--     patient" — that's the smoking gun. The link is missing or
--     not 'active'. Run this to inspect every link for that pair:
select id, caretaker_user_id, patient_user_id, status,
       requested_at, responded_at, last_seen_at
  from public.caretaker_patient_links
 where patient_user_id = '892657f6-b6bc-4530-a81c-fa7d2da0eb83';
-- Expected: at least one row with status='active'.


-- ============================================================
-- NEW QUERIES — work without auth context
-- ============================================================


-- ─── 6. Bypass the SECURITY DEFINER wrapper and read the data
--     the caretaker RPC is supposed to return.
--     This is the actual data the RPC operates on.
select jsonb_build_object(
         'water_liters',   dm.water_liters,
         'heart_rate_bpm', dm.heart_rate_bpm,
         'steps',          dm.steps,
         'metric_date',    dm.metric_date,
         'has_data',       true
       ) as what_caretaker_should_see
  from public.daily_metrics dm
 where dm.user_id = '892657f6-b6bc-4530-a81c-fa7d2da0eb83'
   and dm.metric_date = (now() at time zone 'Asia/Dhaka')::date;
-- Expected: {"water_liters": 1.75, ..., "has_data": true}
-- If this returns 0 rows, the patient is logging on the WRONG date
-- (e.g. UTC date instead of Dhaka date) — fix that first.


-- ─── 7. Inspect EVERY link for this patient. Find the caretaker's
--     UUID and check the status.
select id,
       caretaker_user_id,
       patient_user_id,
       status,
       caretaker_relationship,
       to_char(requested_at, 'YYYY-MM-DD HH24:MI:SS') as requested_at,
       to_char(responded_at, 'YYYY-MM-DD HH24:MI:SS') as responded_at
  from public.caretaker_patient_links
 where patient_user_id = '892657f6-b6bc-4530-a81c-fa7d2da0eb83'
 order by requested_at desc;
-- Expected: at least one row with status='active'.


-- ─── 8. Test the link-lookup logic the RPC uses internally.
--     Replace 'CARETAKER_UUID_FROM_QUERY_7' with the actual
--     caretaker user_id from query 7.
select status
  from public.caretaker_patient_links
 where caretaker_user_id = 'CARETAKER_UUID_FROM_QUERY_7'
   and patient_user_id   = '892657f6-b6bc-4530-a81c-fa7d2da0eb83'
   and status            = 'active';
-- Expected: 1 row with status='active'.
-- If 0 rows: that's the smoking gun — the link is NOT active for
-- that caretaker. Fix with query 9.


-- ─── 9. (FIX) Force the link to active if it exists but the
--     status is wrong. Replace 'CARETAKER_UUID' first.
update public.caretaker_patient_links
   set status      = 'active',
       responded_at = coalesce(responded_at, now())
 where caretaker_user_id = 'CARETAKER_UUID'
   and patient_user_id   = '892657f6-b6bc-4530-a81c-fa7d2da0eb83';
-- Re-run query 7 to confirm.


-- ─── 10. Check if Realtime publication includes the tables.
--      The caretaker's auto-refresh needs these.
select schemaname, tablename
  from pg_publication_tables
 where pubname = 'supabase_realtime'
   and tablename in (
     'meal_intake_log','medicine_doses','water_intake_log',
     'daily_metrics','workout_sessions','workout_session_items',
     'mood_entries'
   )
 order by tablename;
-- Expected: 7 rows.
-- If less than 7, run 55_caretaker_full_visibility_setup.sql.


-- ─── 11. Check that the caretaker SELECT policies still exist
--      on daily_metrics (you said you removed RLS — verify).
select schemaname, tablename, policyname, cmd
  from pg_policies
 where tablename = 'daily_metrics';
-- Expected: at least one policy for SELECT.
-- If empty, run 55_caretaker_full_visibility_setup.sql.
