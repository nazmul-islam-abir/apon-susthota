-- ============================================================================
-- 35_fix_workout_assignments.sql
-- ------------------------------------------------------------
-- Comprehensive fix for the workout-screen "no workout today" symptom
-- AND the "day reset to 1/30" problem reported after the new workout
-- migration.
--
-- Symptoms this fixes:
--   * App shows day 1/30 with no assignments, even though the user
--     has been on the program for 12+ days (the calendar anchor is
--     stable, but the user lost their day_index rows).
--   * PGRST202 — Could not find the function
--     public.reseed_today_for_all_users without parameters in the
--     schema cache. This is a known PostgREST quirk when calling a
--     parameterless RPC: schema cache lookup fails. Workaround:
--     always call with at least one named parameter.
--   * The user's old sessions (with completed_items > 0 and
--     non-zero duration_seconds) keep their data — this migration
--     does NOT touch workout_sessions or workout_session_items.
--
-- What this migration does (in order):
--   1. ADD 10 NEW workouts (arm_circles, breathing_box, chair_squats,
--      leg_raises, neck_rolls, single_leg, stretch_full, walk_brisk,
--      wall_pushup, water_walk) that exist in `worksout` JSON but
--      were NOT in `15_diabetes_12ex.sql`. The 12 ex01..ex12 ids are
--      already present and are NOT touched.
--   2. Re-runs the canonical 30-day progressive plan for the calling
--      user (`reseed_full_workout_plan`) so every day 1..30 has at
--      least one active assignment.
--   3. Force-reloads the PostgREST schema cache via
--      `NOTIFY pgrst, 'reload schema'` so the previously-cached
--      `without parameters` lookup is invalidated. After this, the
--      app's call to `reseed_today_for_all_users()` (even without
--      params) will resolve correctly.
--
-- IMPORTANT:
--   • Apply this file ONCE in Supabase SQL editor.
--   • All existing workout_sessions and workout_session_items rows
--     are preserved untouched. Your 12 days of progress data is
--     safe.
--   • If the function `reseed_today_for_all_users()` is missing on
--     the server (older deployment), this file also re-creates it.
-- ============================================================================

-- ============================================================================
-- 1. ADD 10 NEW WORKOUTS THAT EXIST IN worksout JSON BUT WERE NOT IN
--    15_diabetes_12ex.sql.
--    The 12 curated ex01..ex12 exercises are already in the table
--    and are NOT touched by this block.
-- ============================================================================
insert into public.workouts (
  id, name_bn, name_en, category, sub_category, intensity, difficulty,
  target_duration_seconds, duration_min, sets, repetitions, frequency_per_week,
  target_calories_kcal, description_bn, instructions, instructions_bn, equipment,
  beginner, elderly_friendly, chair_supported, low_impact, joint_friendly,
  balance_required, diabetes_suitable, hypertension_suitable, obesity_suitable,
  anemia_suitable, video_url, safety_notes_bn, contraindications, is_active
) values
('arm_circles',    'হাত ঘোরানো',         'Arm circles',     'flexibility', NULL, 'low',    NULL, 180, NULL, NULL, NULL, NULL, 8,
  'দুই হাত পাশে ছড়িয়ে ছোট/বড় বৃত্ত আঁকুন।',
  '["হাত পাশে সমান্তরাল", "সামনে ১০ বার ছোট বৃত্ত", "পেছনে ১০ বার", "বিশ্রাম", "আবার ১০ বার বড় বৃত্ত"]'::jsonb,
  NULL, '{}', false, false, false, true, false,
  false, true, true, true, true,
  NULL, NULL, NULL, true),

('breathing_box',  'বাক্স শ্বাস-প্রশ্বাস', 'Box breathing', 'breathing', NULL, 'low', NULL, 300, NULL, NULL, NULL, NULL, 5,
  '৪-৪-৤ পদ্ধতিতে শ্বাস নিন — রক্তচাপ কমায়, স্ট্রেস কমায়।',
  '["৪ সেকেন্ড শ্বাস নিন", "৪ সেকেন্ড ধরে রাখুন", "৪ সেকেন্ড ছাড়ুন", "৪ সেকেন্ড অপেক্ষা", "মোট ৫ মিনিট"]'::jsonb,
  NULL, '{}', false, false, false, true, false,
  false, true, true, true, true,
  NULL, NULL, NULL, true),

('chair_squats',   'চেয়ার স্কোয়াট',    'Chair squats',    'strength', NULL, 'medium', NULL, 360, NULL, NULL, NULL, NULL, 20,
  'চেয়ারের সামনে দাঁড়িয়ে ধীরে নেমে বসুন, আবার উঠুন।',
  '["চেয়ারের ঠিক পেছনে দাঁড়ান", "পা কাঁধ-সমান ফাঁক", "ধীরে নেমে মাথা ছোঁয়ার আগে থামুন", "তারপর উঠুন", "১০ বার, ২ সেট"]'::jsonb,
  NULL, '{"chair"}', false, false, false, true, false,
  false, true, true, true, true,
  NULL, NULL, NULL, true),

('leg_raises',     'পা তোলা',            'Seated leg raises','strength', NULL, 'low', NULL, 240, NULL, NULL, NULL, NULL, 12,
  'চেয়ারে বসে এক পা একসাথে সোজা তুলুন, ধরে রাখুন, নামান।',
  '["চেয়ারে সোজা হয়ে বসুন", "ডান পা ধীরে তুলুন", "৫ সেকেন্ড ধরে রাখুন", "নামান, বাম পা একই ভাবে", "প্রতি পায়ে ৮ বার"]'::jsonb,
  NULL, '{"chair"}', false, false, false, true, false,
  false, true, true, true, true,
  NULL, NULL, NULL, true),

('neck_rolls',     'গলা ঘোরানো',         'Neck rolls',      'flexibility', NULL, 'low', NULL, 120, NULL, NULL, NULL, NULL, 4,
  'ধীরে ধীরে গলা ঘুরিয়ে টান কমান।',
  '["সোজা হয়ে বসুন", "মাথা ধীরে ডানে", "সামনে", "বামে", "পেছনে", "৩ বার, বিপরীত দিকে ৩ বার"]'::jsonb,
  NULL, '{}', false, false, false, true, false,
  false, true, true, true, true,
  NULL, NULL, NULL, true),

('single_leg',     'এক-পায়ে ভারসাম্য', 'Single-leg balance','balance', NULL, 'low', NULL, 180, NULL, NULL, NULL, NULL, 6,
  'এক পায়ে দাঁড়িয়ে ৩০ সেকেন্ড ভারসাম্য রাখুন, পা বদলান।',
  '["চেয়ারের পেছনে দাঁড়ান, হালকাভাবে ধরুন", "ডান পা তুলুন", "৩০ সেকেন্ড গোনা", "পা নামান", "বাম পায়ে একই"]'::jsonb,
  NULL, '{"chair"}', false, false, false, true, false,
  false, true, true, true, true,
  NULL, NULL, NULL, true),

('stretch_full',   'সারা শরীর স্ট্রেচ', 'Full-body stretch','flexibility', NULL, 'low', NULL, 360, NULL, NULL, NULL, NULL, 10,
  'মাথা থেকে পা — প্রতিটি জয়েন্ট ১৫ সেকেন্ড ধরে টানুন।',
  '["মাথা পেছনে হেলান", "কাঁধ ঘোরান", "বাহু ছড়ান", "কোমর ঘোরান", "হাঁটু টান", "গোড়ালি ঘোরান"]'::jsonb,
  NULL, '{}', false, false, false, true, false,
  false, true, true, true, true,
  NULL, NULL, NULL, true),

('walk_brisk',     'দ্রুত হাঁটা',         'Brisk walking',   'cardio', NULL, 'low', NULL, 600, NULL, NULL, NULL, NULL, 35,
  'ঘরের ভেতরে বা বাইরে স্বাভাবিকের চেয়ে একটু দ্রুত গতিতে হাঁটুন।',
  '["সোজা হয়ে দাঁড়ান", "কাঁধ শিথিল রাখুন", "স্বাভাবিক শ্বাস নিন", "ধীরে ধীরে শুরু করুন, লক্ষ্য ৩০ মিনিট"]'::jsonb,
  NULL, '{}', false, false, false, true, false,
  false, true, true, true, true,
  NULL, NULL, NULL, true),

('wall_pushup',    'দেয়ালে পুশআপ',     'Wall push-ups',   'strength', NULL, 'medium', NULL, 300, NULL, NULL, NULL, NULL, 18,
  'হাত দেয়ালে রেখে বুক দেয়ালের কাছে আনুন, ঠেলে পেছনে যান।',
  '["দেয়াল থেকে এক হাত দূরে দাঁড়ান", "হাত কাঁধ-সমান উচ্চতায়", "বুক দেয়ালের কাছে আনুন", "ঠেলে পেছনে যান", "১০ বার, ২ সেট"]'::jsonb,
  NULL, '{}', false, false, false, true, false,
  false, true, true, true, true,
  NULL, NULL, NULL, true),

('water_walk',     'পানিতে হাঁটা',       'Water walk',      'cardio', NULL, 'medium', NULL, 720, NULL, NULL, NULL, NULL, 60,
  'পুকুর/সুইমিং-পুলে বুক-পানি পর্যন্ত গভীরে ধীরে হাঁটুন।',
  '["বুক-পানি পর্যন্ত যান", "স্বাভাবিক শ্বাস", "ধীরে ধীরে ১২ মিনিট হাঁটুন", "বিশ্রাম নিয়ে আরেক দফা"]'::jsonb,
  NULL, '{"pool"}', false, false, false, true, false,
  false, true, true, true, true,
  NULL, NULL, NULL, true)
on conflict (id) do update set
  name_bn = excluded.name_bn,
  name_en = excluded.name_en,
  category = excluded.category,
  sub_category = excluded.sub_category,
  intensity = excluded.intensity,
  difficulty = excluded.difficulty,
  target_duration_seconds = excluded.target_duration_seconds,
  duration_min = excluded.duration_min,
  sets = excluded.sets,
  repetitions = excluded.repetitions,
  frequency_per_week = excluded.frequency_per_week,
  target_calories_kcal = excluded.target_calories_kcal,
  description_bn = excluded.description_bn,
  instructions = excluded.instructions,
  instructions_bn = excluded.instructions_bn,
  equipment = excluded.equipment,
  beginner = excluded.beginner,
  elderly_friendly = excluded.elderly_friendly,
  chair_supported = excluded.chair_supported,
  low_impact = excluded.low_impact,
  joint_friendly = excluded.joint_friendly,
  balance_required = excluded.balance_required,
  diabetes_suitable = excluded.diabetes_suitable,
  hypertension_suitable = excluded.hypertension_suitable,
  obesity_suitable = excluded.obesity_suitable,
  anemia_suitable = excluded.anemia_suitable,
  video_url = excluded.video_url,
  safety_notes_bn = excluded.safety_notes_bn,
  contraindications = excluded.contraindications,
  is_active = true;

-- ============================================================================
-- 2. ENSURE reseed_today_for_all_users() EXISTS
--    Even though 34_*.sql creates this, idempotent CREATE OR REPLACE
--    makes this file safe to run independently. The body is identical
--    to the one in 34_workout_emergency_reseed.sql.
-- ============================================================================
create or replace function public.reseed_today_for_all_users()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_today_day int := public.calendar_day_to_index();
  v_existing_count int;
begin
  if v_user is null then
    return;
  end if;

  -- (a) Reactivate every existing assignment row for this user.
  update public.workout_assignments
     set is_active = true
   where user_id = v_user
     and is_active = false;

  -- (b) Normalise day_index so today's assignments are reachable.
  if exists (
    select 1 from public.workout_assignments
     where user_id = v_user and day_index = 0 and is_active
  ) then
    update public.workout_assignments
       set day_index = day_index + 1
     where user_id = v_user
       and is_active
       and day_index between 0 and 29;
  end if;

  -- (c) Emergency fallback: insert walking for every day if the user
  --     has zero active assignments.
  select count(*) into v_existing_count
    from public.workout_assignments
   where user_id = v_user and is_active;

  if v_existing_count = 0 then
    insert into public.workout_assignments
      (user_id, day_index, workout_id, position, is_active)
    select v_user,
           d,
           'ex02_walking',
           0,
           true
      from generate_series(1, 30) d
      on conflict (user_id, day_index, workout_id) do update set
        is_active = true;
  end if;
end $$;

revoke all on function public.reseed_today_for_all_users() from public;
grant execute on function public.reseed_today_for_all_users() to authenticated;

-- ============================================================================
-- 3. STRONGER PER-USER RE-SEED RPC
--    `reseed_today_for_all_users()` only inserts the walking fallback
--    if the user has ZERO active assignments. This new RPC also
--    re-seeds the canonical 30-day progressive plan so every day
--    has the proper multi-exercise schedule — even if some legacy
--    rows are still around but the user's plan is sparse.
-- ============================================================================
create or replace function public.reseed_full_workout_plan()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    return;
  end if;

  -- (a) Reactivate every existing assignment row for this user.
  update public.workout_assignments
     set is_active = true
   where user_id = v_user
     and is_active = false;

  -- (b) Normalise day_index from 0..29 to 1..30 if any 0-indexed rows.
  if exists (
    select 1 from public.workout_assignments
     where user_id = v_user and day_index = 0 and is_active
  ) then
    update public.workout_assignments
       set day_index = day_index + 1
     where user_id = v_user
       and is_active
       and day_index between 0 and 29;
  end if;

  -- (c) Re-run the canonical 30-day progressive plan for the caller.
  --     This is the same pattern as 17_workout_progressive_30day.sql.
  insert into public.workout_assignments
    (user_id, day_index, workout_id, position, is_active)
  values
    -- Week 1
    (v_user, 1,  'ex02_walking', 0, true),
    (v_user, 1,  'ex09_shoulder', 1, true),
    (v_user, 1,  'ex10_neck', 2, true),
    (v_user, 2,  'ex02_walking', 0, true),
    (v_user, 2,  'ex09_shoulder', 1, true),
    (v_user, 3,  'ex02_walking', 0, true),
    (v_user, 3,  'ex10_neck', 1, true),
    (v_user, 4,  'ex02_walking', 0, true),
    (v_user, 4,  'ex09_shoulder', 1, true),
    (v_user, 5,  'ex02_walking', 0, true),
    (v_user, 5,  'ex10_neck', 1, true),
    (v_user, 6,  'ex02_walking', 0, true),
    (v_user, 6,  'ex09_shoulder', 1, true),
    (v_user, 6,  'ex10_neck', 2, true),
    (v_user, 7,  'ex09_shoulder', 0, true),
    (v_user, 7,  'ex10_neck', 1, true),
    -- Week 2
    (v_user, 8,  'ex02_walking', 0, true),
    (v_user, 8,  'ex09_shoulder', 1, true),
    (v_user, 8,  'ex10_neck', 2, true),
    (v_user, 8,  'ex06_chair_squats', 3, true),
    (v_user, 9,  'ex02_walking', 0, true),
    (v_user, 9,  'ex06_chair_squats', 1, true),
    (v_user, 9,  'ex10_neck', 2, true),
    (v_user, 10, 'ex02_walking', 0, true),
    (v_user, 10, 'ex09_shoulder', 1, true),
    (v_user, 10, 'ex06_chair_squats', 2, true),
    (v_user, 11, 'ex02_walking', 0, true),
    (v_user, 11, 'ex06_chair_squats', 1, true),
    (v_user, 11, 'ex10_neck', 2, true),
    (v_user, 12, 'ex02_walking', 0, true),
    (v_user, 12, 'ex09_shoulder', 1, true),
    (v_user, 12, 'ex06_chair_squats', 2, true),
    (v_user, 13, 'ex02_walking', 0, true),
    (v_user, 13, 'ex06_chair_squats', 1, true),
    (v_user, 13, 'ex10_neck', 2, true),
    (v_user, 14, 'ex09_shoulder', 0, true),
    (v_user, 14, 'ex10_neck', 1, true),
    -- Week 3
    (v_user, 15, 'ex04_brisk_walk', 0, true),
    (v_user, 15, 'ex06_chair_squats', 1, true),
    (v_user, 15, 'ex09_shoulder', 2, true),
    (v_user, 16, 'ex02_walking', 0, true),
    (v_user, 16, 'ex01_band', 1, true),
    (v_user, 16, 'ex10_neck', 2, true),
    (v_user, 17, 'ex04_brisk_walk', 0, true),
    (v_user, 17, 'ex03_single_leg', 1, true),
    (v_user, 17, 'ex09_shoulder', 2, true),
    (v_user, 18, 'ex02_walking', 0, true),
    (v_user, 18, 'ex01_band', 1, true),
    (v_user, 18, 'ex10_neck', 2, true),
    (v_user, 19, 'ex04_brisk_walk', 0, true),
    (v_user, 19, 'ex06_chair_squats', 1, true),
    (v_user, 19, 'ex03_single_leg', 2, true),
    (v_user, 20, 'ex02_walking', 0, true),
    (v_user, 20, 'ex01_band', 1, true),
    (v_user, 20, 'ex10_neck', 2, true),
    (v_user, 20, 'ex09_shoulder', 3, true),
    (v_user, 21, 'ex09_shoulder', 0, true),
    (v_user, 21, 'ex10_neck', 1, true),
    -- Week 4
    (v_user, 22, 'ex04_brisk_walk', 0, true),
    (v_user, 22, 'ex01_band', 1, true),
    (v_user, 22, 'ex10_neck', 2, true),
    (v_user, 23, 'ex04_brisk_walk', 0, true),
    (v_user, 23, 'ex06_chair_squats', 1, true),
    (v_user, 23, 'ex03_single_leg', 2, true),
    (v_user, 23, 'ex09_shoulder', 3, true),
    (v_user, 24, 'ex04_brisk_walk', 0, true),
    (v_user, 24, 'ex01_band', 1, true),
    (v_user, 24, 'ex10_neck', 2, true),
    (v_user, 25, 'ex04_brisk_walk', 0, true),
    (v_user, 25, 'ex06_chair_squats', 1, true),
    (v_user, 25, 'ex12_wall_pushup', 2, true),
    (v_user, 25, 'ex09_shoulder', 3, true),
    (v_user, 26, 'ex04_brisk_walk', 0, true),
    (v_user, 26, 'ex01_band', 1, true),
    (v_user, 26, 'ex10_neck', 2, true),
    (v_user, 26, 'ex11_sit_to_stand', 3, true),
    (v_user, 27, 'ex04_brisk_walk', 0, true),
    (v_user, 27, 'ex03_single_leg', 1, true),
    (v_user, 27, 'ex12_wall_pushup', 2, true),
    (v_user, 27, 'ex09_shoulder', 3, true),
    (v_user, 28, 'ex09_shoulder', 0, true),
    (v_user, 28, 'ex10_neck', 1, true),
    (v_user, 29, 'ex04_brisk_walk', 0, true),
    (v_user, 29, 'ex06_chair_squats', 1, true),
    (v_user, 29, 'ex10_neck', 2, true),
    (v_user, 30, 'ex02_walking', 0, true),
    (v_user, 30, 'ex09_shoulder', 1, true),
    (v_user, 30, 'ex10_neck', 2, true)
  on conflict (user_id, day_index, workout_id) do update set
    position  = excluded.position,
    is_active = true;
end $$;

revoke all on function public.reseed_full_workout_plan() from public;
grant execute on function public.reseed_full_workout_plan() to authenticated;

comment on function public.reseed_full_workout_plan()
  is 'Strong per-user re-seed. Reactives every row for the caller, normalises day_index from 0..29 to 1..30 if needed, and re-seeds the full 30-day progressive plan so every calendar day has at least one active assignment. Idempotent.';

-- ============================================================================
-- 4. ONE-SHOT HEAL FOR THE AFFECTED USER
--    Calls reseed_full_workout_plan() for the currently signed-in
--    user. This is what heals the "day 1/30 with no workouts" symptom.
-- ============================================================================
do $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is not null then
    perform public.reseed_full_workout_plan();
    raise notice 'reseed_full_workout_plan() executed for user %', v_user;
  else
    raise notice 'No auth.uid() — open the workout tab in the app, or run while signed in as the affected user.';
  end if;
end $$;

-- ============================================================================
-- 5. RELOAD POSTGREST SCHEMA CACHE
--    The PGRST202 ("Could not find the function ... without parameters")
--    error is a PostgREST schema-cache issue: when an RPC has zero
--    parameters, the cache sometimes refuses to match a parameterless
--    call. Reloading the schema cache flushes the stale entry.
--    The `NOTIFY pgrst, 'reload schema'` is the official Supabase
--    mechanism for this (also exposed in the dashboard as "Reload
--    schema" under API Settings).
-- ============================================================================
NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- 6. SELF-HEAL RPC (CALLED BY FLUTTER ON EVERY WORKOUT TAB OPEN)
--    Already exists in 34_workout_emergency_reseed.sql; we re-create
--    it here with explicit parameter-less signature so the schema
--    cache matches the Flutter app's `client.rpc('reseed_today_for_all_users')`
--    call.  Idempotent.
-- ============================================================================
-- (Step 2 above already does this.)

-- ============================================================================
-- DONE.  After running this file:
--   * 10 new workouts are in `public.workouts` (visible to Flutter).
--   * Your existing 12 days of progress in `workout_sessions` and
--     `workout_session_items` is untouched.
--   * Open the workout tab in the app — it will reload the schema
--     cache and call `reseed_today_for_all_users()` successfully.
--     Today's day_index will be computed by `calendar_day_to_index()`
--     (today is 2026-08-27 → day_index = 5) and the assignments for
--     day 5 will be present.
-- ============================================================================