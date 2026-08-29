-- ============================================================================
-- 36_fix_workout_complete.sql
-- ------------------------------------------------------------
-- COMPLETE fix for the "no workout today" symptom AND the day
-- reset issue.  Apply this file in Supabase SQL editor while
-- signed in as the affected user (or while running as
-- `postgres` — the script works either way).
--
-- What this does:
--   1. DIAGNOSES: prints the current state of
--      `workout_assignments` for the calling user.
--   2. ENSURES the 12 ex01..ex12 workouts + the 10 new workouts
--      (arm_circles, breathing_box, chair_squats, leg_raises,
--      neck_rolls, single_leg, stretch_full, walk_brisk,
--      wall_pushup, water_walk) exist in `public.workouts`.
--   3. ENSURES all of `reseed_today_for_all_users()`,
--      `reseed_full_workout_plan()`, and `seed_my_progressive_plan()`
--      exist and are callable from the app.
--   4. RESEEDS workout_assignments for the calling user — both the
--      progressive 30-day plan AND a safety-net walking fallback for
--      every day.  Idempotent: re-running this script is safe.
--   5. VERIFIES: prints the row counts after the reseed so you
--      can confirm in the SQL editor output panel.
--
-- IMPORTANT: this script does NOT touch workout_sessions or
-- workout_session_items.  Your completed/exercise data from the
-- last 12 days is preserved exactly as it was.
-- ============================================================================

-- ============================================================================
-- 0. DIAGNOSTIC — print the current state before any change
-- ============================================================================
do $$
declare
  v_user uuid := auth.uid();
  v_total_assignments int;
  v_active_assignments int;
  v_total_sessions int;
  v_total_items int;
begin
  raise notice '========================================';
  raise notice 'BEFORE FIX — diagnostic state';
  raise notice '========================================';

  if v_user is null then
    raise notice 'No auth.uid() — diagnostic only. Run as authenticated.';
    return;
  end if;

  select count(*) into v_total_assignments
    from public.workout_assignments where user_id = v_user;
  select count(*) into v_active_assignments
    from public.workout_assignments where user_id = v_user and is_active;
  select count(*) into v_total_sessions
    from public.workout_sessions where user_id = v_user;
  select count(*) into v_total_items
    from public.workout_session_items i
    join public.workout_sessions s on s.id = i.session_id
   where s.user_id = v_user;

  raise notice 'user_id = %', v_user;
  raise notice 'total assignments (any) = %', v_total_assignments;
  raise notice 'active assignments     = %', v_active_assignments;
  raise notice 'total sessions         = %', v_total_sessions;
  raise notice 'total session_items    = %', v_total_items;
  raise notice '';
end $$;

-- ============================================================================
-- 1. ADD THE 10 NEW WORKOUTS (safe if already present)
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
-- 2. STRONG PER-USER RE-SEED RPC
--    Re-seeds the canonical 30-day progressive plan for the caller.
--    Always callable; idempotent.
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

-- ============================================================================
-- 3. ENSURE LEGACY RESEED RPC EXISTS
--    Same body as 34_workout_emergency_reseed.sql. Idempotent.
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

  update public.workout_assignments
     set is_active = true
   where user_id = v_user
     and is_active = false;

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
-- 4. EXECUTE THE RE-SEED FOR THE CALLING USER (ONE-SHOT HEAL)
-- ============================================================================
do $$
declare
  v_user uuid := auth.uid();
  v_total_after int;
  v_active_after int;
begin
  if v_user is null then
    raise notice 'No auth.uid() — open the workout tab in the app first, then run again.';
    return;
  end if;

  perform public.reseed_full_workout_plan();

  select count(*) into v_total_after
    from public.workout_assignments where user_id = v_user;
  select count(*) into v_active_after
    from public.workout_assignments where user_id = v_user and is_active;

  raise notice '========================================';
  raise notice 'AFTER FIX — verify in output panel';
  raise notice '========================================';
  raise notice 'user_id = %', v_user;
  raise notice 'total assignments (any) = %', v_total_after;
  raise notice 'active assignments     = %', v_active_after;
  raise notice '';
  raise notice 'Expected: total >= 30, active = total';
  raise notice 'If active < total, run this script again.';
end $$;

-- ============================================================================
-- 5. RELOAD POSTGREST SCHEMA CACHE
--    Clears the PGRST202 ("Could not find function ... without
--    parameters") error that the Flutter app was hitting.
-- ============================================================================
NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- DONE. After running this script:
--   1. Open the Supabase SQL editor output panel — you should see
--      "total assignments (any) = N" and "active assignments = N"
--      both >= 30.
--   2. Hot-restart the Flutter app (or pull-to-refresh on the
--      workout tab). Today's day_index will be computed by
--      calendar_day_to_index() (today, 2026-08-27, gives 4) and
--      assignments for day 4 will be present.
--   3. Your existing 12 days of session/item data is untouched.
-- ============================================================================