-- ============================================================================
-- 37_fix_12_workouts_only.sql
-- ------------------------------------------------------------
-- CLEAN RESET of the workouts catalogue and 30-day assignment plan.
-- This script leaves ONLY the 12 workouts you specified, with the
-- priorities / durations / weekly frequencies per your table.
--
-- What this does (in order):
--   1. HARD-RESET `public.workouts` — keeps ONLY the 12 ids below,
--      deletes every other workout (and the assignments / sessions
--      that reference them via FK).
--   2. UPSERT the 12 workouts with the FULL signed URLs you provided.
--      NOTE: The Flutter app now automatically re-signs these if they expire.
--   3. REFRESH the `get_today_workout` RPC to ensure `video_url` is
--      definitely returned to the app.
--   4. Reseed workout_assignments for the calling user with a NEW
--      priority-aware 30-day plan.
--
-- ============================================================================

-- ============================================================================
-- 0. DIAGNOSTIC — show what's there now (read-only)
-- ============================================================================
do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.workouts;
  raise notice 'Before fix: public.workouts has % rows', v_count;
end $$;

-- ============================================================================
-- 1. HARD-RESET: keep only the 12 workout ids we want.
-- ============================================================================
do $$
declare
  v_keep constant text[] := array[
    'ex01_band','ex02_walking','ex03_single_leg','ex04_brisk_walk',
    'ex05_cycling','ex06_chair_squats','ex07_jogging','ex08_stair_climb',
    'ex09_shoulder','ex10_neck','ex11_sit_to_stand','ex12_wall_pushup'
  ];
begin
  -- Drop session items pointing at doomed workouts.
  delete from public.workout_session_items
   where workout_id is not null
     and workout_id <> all(v_keep);

  -- Cleanup sessions that are now empty.
  delete from public.workout_sessions ws
   where not exists (
     select 1 from public.workout_session_items wsi
      where wsi.session_id = ws.id
   );

  -- Drop assignments pointing at doomed workouts.
  delete from public.workout_assignments
   where workout_id <> all(v_keep);

  -- Delete the workouts themselves.
  delete from public.workouts
   where id <> all(v_keep);
end $$;

-- ============================================================================
-- 2. UPSERT THE 12 WORKOUTS
--    NOTE: We use the FULL signed URL. If it expires, the app's SupabaseService
--    will catch the 403 error and re-sign it automatically using the filename
--    extracted from the URL.
-- ============================================================================
insert into public.workouts (
  id, name_bn, name_en, category, sub_category, intensity, difficulty,
  target_duration_seconds, duration_min, sets, repetitions, frequency_per_week,
  target_calories_kcal, description_bn, instructions, instructions_bn, equipment,
  beginner, elderly_friendly, chair_supported, low_impact, joint_friendly,
  balance_required, diabetes_suitable, hypertension_suitable, obesity_suitable,
  anemia_suitable, video_url, safety_notes_bn, contraindications, is_active
) values
('ex02_walking',      'হাঁটা',                  'Walking',
 'walking','lifestyle','low','beginner',
 1320, 22, NULL, NULL, 7,
 70,
 'ধীর গতিতে হাঁটা — প্রতিদিনের প্রধান কার্ডিও ব্যায়াম। হৃদস্পন্দন বাড়ায়, গ্লুকোজ নিয়ন্ত্রণে সাহায্য করে।',
 '["সোজা হয়ে দাঁড়ান, পিঠ সোজা", "ধীরে ধীরে ১৫-৩০ মিনিট হাঁটুন (৩-৪ কিমি/ঘণ্টা)", "প্রতি ৫ মিনিটে গভীর শ্বাস নিন", "শেষে ১ মিনিট স্ট্রেচ"]'::jsonb,
 'ফুসফুসে ব্যথা, মাথা ঘোরা বা অতিরিক্ত হৃদস্পন্দন শুরু হলে থামুন।',
 '{}', true, true, true, true, true,
 false, true, true, true, true,
 'https://jjkvoiapufnhydnebdwk.supabase.co/storage/v1/object/sign/exercise/Walking.mp4?token=eyJraWQiOiJmMDA1MDg0MS0yNjYzLTQ5NjYtOGE3Zi1hMWFjZTYyZjJhNDUiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJleGVyY2lzZS9XYWxraW5nLm1wNCIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODcwMTM4NzQsImV4cCI6MjEwMjM3Mzg3NH0.UmXkSkMf1r4nYUFghxe_7uQh9XDALI37TmVyQi-gyB0',
 'রক্তে শর্করা ৭০-এর নিচে হলে হাঁটবেন না — আগে হালকা খাবার খান।',
 'অস্থির কোমর বা হাঁটুর ব্যথা থাকলে বিরতি দিন।',
 true),

('ex04_brisk_walk',   'দ্রুত হাঁটা',              'Brisk Walking',
 'walking','lifestyle','medium','beginner',
 1500, 25, NULL, NULL, 5,
 130,
 'স্বাভাবিকের চেয়ে দ্রুত গতিতে হাঁটা — প্রধান মাঝারি কার্ডিও। হৃদস্পন্দন উল্লেখযোগ্যভাবে বাড়ায়।',
 '["৫ মিনিট ধীরে হেঁটে warm-up", "গতি বাড়ান — যেন কথা বলতে পারেন কিন্তু গান গাইতে না পারেন", "হাত স্বাভাবিক দোলায়", "২০-৩০ মিনিট এই গতিতে", "শেষে ২-৩ মিনিট cool-down"]'::jsonb,
 'রক্তচাপ ১৪০/৯০-এর বেশি হলে আজ হাঁটবেন না।',
 '{}', true, true, false, true, true,
 false, true, true, true, true,
 'https://jjkvoiapufnhydnebdwk.supabase.co/storage/v1/object/sign/exercise/Brisk%20Walking.mp4?token=eyJraWQiOiJmMDA1MDg0MS0yNjYzLTQ5NjYtOGE3Zi1hMWFjZTYyZjJhNDUiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJleGVyY2lzZS9CcmlzayBXYWxraW5nLm1wNCIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODcwMTM5MjIsImV4cCI6MjEwMjM3MzkyMn0.tDkKam167naUf5lCtqvaDR69eW8l8x3C9P9r5OTyFMY',
 'বুকে ব্যথা, মাথা ঘোরা বা হাঁপানে থামুন। জুতো ঢিলেঢালা হলে বদলে নিন।',
 'নিয়ন্ত্রিত হৃদরোগ থাকলে গতি ও সময় কমিয়ে শুরু করুন।',
 true),

('ex01_band',         'রেজিস্ট্যান্স ব্যান্ড ব্যায়াম',  'Resistance Band Exercise',
 'strength','upper_body','low','beginner',
 900, 15, 3, '10-15 reps', 2,
 35,
 'রেজিস্ট্যান্স ব্যান্ড দিয়ে হাত-পা ও কাঁধের পেশি শক্তিশালী করুন। সারা শরীরের জন্য হালকা টানাশক্তি বৃদ্ধি।',
 '["রেজিস্ট্যান্স ব্যান্ড পায়ে ভর দিয়ে রাখুন", "উভয় হাতে ব্যান্ডের দুটি প্রান্ত ধরুর", "front raise — ১০ বার", "upright row — ১০ বার", "tricep press — ১০ বার", "২ সেট, ৩০ সেকেন্ড বিশ্রাম"]'::jsonb,
 'ব্যান্ডের টান সহনীয় মাত্রায় রাখুন। হাঁটু সামান্য বাঁকা রাখুন।',
 '{"resistance_band"}', true, true, false, true, true,
 false, true, true, true, true,
 'https://jjkvoiapufnhydnebdwk.supabase.co/storage/v1/object/sign/exercise/Resistance%20Band%20Exercise.mp4?token=eyJraWQiOiJmMDA1MDg0MS0yNjYzLTQ5NjYtOGE3Zi1hMWFjZTYyZjJhNDUiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJleGVyY2lzZS9SZXNpc3RhbmNlIEJhbmQgRXhlcmNpc2UubXA0Iiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4NzAxMzg1NCwiZXhwIjoyMTAyMzczODU0fQ.dshu1tuAYPV3GvGRQtZ7Cg0wY9YTjTz1upmn3V2ze7s',
 'ব্যান্ড ছিঁড়ে গেলে বন্ধ করুন। খালি পেটে করবেন না।',
 NULL,
 true),

('ex06_chair_squats', 'চেয়ার স্কোয়াট',         'Chair Squats',
 'strength','lower_body','medium','beginner',
 660, 11, 3, '10-12 reps', 2,
 55,
 'চেয়ারের সামনে দাঁড়িয়ে ধীরে বসা ও ওঠা — পায়ের পেশি (কোয়াড্রিসেপস, হ্যামস্ট্রিং) শক্তিশালী করে।',
 '["চেয়ারের ঠিক পেছনে দাঁড়ান", "পা কাঁধ-সমান চওড়া", "পিঠ সোজা", "ধীরে নেমে মাথা ছোঁয়ার আগে থামুন", "গোড়ালি ও কোমরের শক্তিতে উঠুন", "১০-১২ বার, ৩ সেট"]'::jsonb,
 'হাঁটু আঙুলের সামনে যাবে না।',
 '{"chair"}', true, true, true, true, true,
 false, true, true, true, true,
 'https://jjkvoiapufnhydnebdwk.supabase.co/storage/v1/object/sign/exercise/Chair%20Squats.mp4?token=eyJraWQiOiJmMDA1MDg0MS0yNjYzLTQ5NjYtOGE3Zi1hMWFjZTYyZjJhNDUiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJleGVyY2lzZS9DaGFpciBTcXVhdHMubXA0Iiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4NzAxNDE1MywiZXhwIjoxODE4NTUwMTUzfQ.Lyl1-oOTZD-9sRh-rulyckvaxVGLJ-EMArkF6AeRSps',
 'হাঁটুতে ব্যথা বা শব্দ হলে কম গভীরতায় করুন।',
 'সদ্য হাঁটু সার্জারি হলে বিশেষজ্ঞের পরামর্শ নিন।',
 true),

('ex11_sit_to_stand', 'বসা থেকে দাঁড়ানো',       'Sit-to-Stand',
 'strength','lower_body','low','beginner',
 420, 7, 3, '10 reps', 3,
 45,
 'চেয়ার থেকে বারবার উঠে আবার বসা — হাঁটু, নিতম্ব ও কোমরের পেশি শক্তিশালী, দৈনন্দিন কাজের সুবিধা।',
 '["চেয়ারের মাঝখানে সোজা হয়ে বসুন", "গোড়ালি ও কোমরের শক্তিতে উঠুন", "২ সেকেন্ড দাঁড়িয়ে থাকুন", "ধীরে নিয়ন্ত্রিত গতিতে বসুন", "১০ বার, ৩ সেট"]'::jsonb,
 'হাঁটু আঙুলের সামনে যাবে না; নিতম্ব সোজা রাখুন।',
 '{"chair"}', true, true, true, true, true,
 false, true, true, true, true,
 'https://jjkvoiapufnhydnebdwk.supabase.co/storage/v1/object/sign/exercise/Sit-to-Stand.mp4?token=eyJraWQiOiJmMDA1MDg0MS0yNjYzLTQ5NjYtOGE3Zi1hMWFjZTYyZjJhNDUiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJleGVyY2lzZS9TaXQtdG8tU3RhbmQubXA0Iiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4NzAxNDIyNiwiZXhwIjoxODE4NTUwMjI2fQ.xD5PxkoMtlYDfJo7x73OT2RgsF3rkwoXNn_fn_IifqU',
 'হাঁটুতে ব্যথা বা শব্দ হলে কম গভীরতায় করুন।',
 NULL,
 true),

('ex12_wall_pushup',  'দেয়ালে ভর দিয়ে পুশ-আপ', 'Wall Push-Ups',
 'strength','upper_body','medium','beginner',
 420, 7, 3, '10-15 reps', 2,
 60,
 'দেয়ালে হাত রেখে পুশ-আপ — বুক, কাঁধ ও ত্রাইসেপ শক্তিশালী।',
 '["দেয়াল থেকে এক হাত দূরে দাঁড়ান", "হাত কাঁধ-সমান উচ্চতায় দেয়ালে রাখুন", "বুক দেয়ালের কাছে আনুন", "ঠেলে পেছনে যান", "১০-১৫ বার, ৩ সেট"]'::jsonb,
 'মুখ দেয়ালের দিকে, পিঠ সোজা রাখুন।',
 '{}', true, true, true, true, true,
 false, true, true, true, true,
 'https://jjkvoiapufnhydnebdwk.supabase.co/storage/v1/object/sign/exercise/Wall%20Push-Ups.mp4?token=eyJraWQiOiJmMDA1MDg0MS0yNjYzLTQ5NjYtOGE3Zi1hMWFjZTYyZjJhNDUiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJleGVyY2lzZS9XYWxsIFB1c2gtVXBzLm1wNCIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODcwMTQwMzUsImV4cCI6MjEwMjM3NDAzNX0.qjuvWP3ee5fT26i6JrcZlWrVI8UA-YTiePAAa1dmhqM',
 'কাঁধে ব্যথা থাকলে গভীরতা কমান।',
 NULL,
 true),

('ex03_single_leg',   'এক পায়ে দাঁড়ানো',         'Single-Leg Stand',
 'balance','static','low','beginner',
 240, 4, 3, '30 sec/side', 4,
 15,
 'এক পায়ে দাঁড়িয়ে ভারসাম্য বজায় রাখা — পেশী সমন্বয় ও পতন-প্রতিরোধ।',
 '["চেয়ারের পেছনে হাত রেখে দাঁড়ান", "ডান পা মেঝে থেকে তুলুন", "৩০ সেকেন্ড ভারসাম্য রাখুন", "বাম পায়ে পুনরাবৃত্তি", "৩ সেট, প্রতি সেটে উভয় পা"]'::jsonb,
 'চেয়ারের ঠিক পেছনে হাত রাখুন, ভর দেবেন না — সাপোর্ট শুধু নিরাপত্তার জন্য।',
 '{"chair"}', true, true, true, true, true,
 true, true, true, true, true,
 'https://jjkvoiapufnhydnebdwk.supabase.co/storage/v1/object/sign/exercise/Single-Leg%20Stand.mp4?token=eyJraWQiOiJmMDA1MDg0MS0yNjYzLTQ5NjYtOGE3Zi1hMWFjZTYyZjJhNDUiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJleGVyY2lzZS9TaW5nbGUtTGVnIFN0YW5kLm1wNCIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODcwMTM4OTksImV4cCI6MjEwMjM3Mzg5OX0.zVyY9xyLjqUIXA78mibQkmduQbsNhuVblcCDYo26wu8',
 'কোমর বা পায়ে ব্যথা থাকলে চেয়ারে বসে পায়ের স্ট্রেচিং করুন।',
 NULL,
 true),

('ex09_shoulder',     'কাঁধের স্ট্রেচিং',       'Shoulder Stretching',
 'flexibility','upper_body','low','beginner',
 240, 4, 2, '6 exercises', 6,
 18,
 'কাঁধের জড়তা কমায়, মেরুদণ্ডের উপরের অংশের নমনীয়তা বাড়ায়।',
 '["সোজা হয়ে দাঁড়ান বা বসুন", "ডান হাত বুকের ওপর দিয়ে বাম কাঁধে টানুন — ১৫ সেকেন্ড", "বাম হাত দিয়ে পুনরাবৃত্তি", "উভয় হাত পিছনে জোড়া — ১৫ সেকেন্ড", "মাথার ওপরে আঙুল জোড়া — ১৫ সেকেন্ড", "ঘাড়ের পেছনে জোড়া — ১৫ সেকেন্ড"]'::jsonb,
 'টানার সময় হালকা টান অনুভব করুন, ব্যথা নয়।',
 '{}', true, true, true, true, true,
 false, true, true, true, true,
 'https://jjkvoiapufnhydnebdwk.supabase.co/storage/v1/object/sign/exercise/Shoulder%20Stretching.mp4?token=eyJraWQiOiJmMDA1MDg0MS0yNjYzLTQ5NjYtOGE3Zi1hMWFjZTYyZjJhNDUiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJleGVyY2lzZS9TaG91bGRlciBTdHJldGNoaW5nLm1wNCIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODcwMTQyMDAsImV4cCI6MTgxODU1MDIwMH0.NMjk3v67jhUIDpzEpyvzqj-hx2RAL3mvqu9zwfJt7gk',
 'কাঁধে সাম্প্রতিক আঘাত বা অস্ত্রোপচার থাকলে গভীর স্ট্রেচ এড়িয়ে চলুন।',
 NULL,
 true),

('ex10_neck',         'ঘাড়ের স্ট্রেচিং',       'Neck Stretching',
 'flexibility','neck','low','beginner',
 240, 4, 2, '6 exercises', 7,
 10,
 'ঘাড়ের জড়তা কমায়, মাথাব্যথা কমায়, দীর্ঘক্ষণ ফোন/কম্পিউটার ব্যবহারের পর জরুরি।',
 '["সোজা হয়ে বসুন", "মাথা ধীরে ডানে কাত — ১৫ সেকেন্ড", "বামে কাত — ১৫ সেকেন্ড", "সামনে ঝোঁকান — ১৫ সেকেন্ড", "ডানে-বামে ঘুরিয়ে ৫ সেকেন্ড × ২", "কাঁধ ওপরে তুলে শিথিল — ৩ বার"]'::jsonb,
 'ঘাড় ঘোরানোর সময় মাথা ঘুরলে থামুন।',
 '{}', true, true, true, true, true,
 false, true, true, true, true,
 'https://jjkvoiapufnhydnebdwk.supabase.co/storage/v1/object/sign/exercise/Neck%20Stretching.mp4?token=eyJraWQiOiJmMDA1MDg0MS0yNjYzLTQ5NjYtOGE3Zi1hMWFjZTYyZjJhNDUiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJleGVyY2lzZS9OZWNrIFN0cmV0Y2hpbmcubXA0Iiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4NzAxNDIxMywiZXhwIjoxODE4NTUwMjEzfQ.-T6-82AtKzXXULR7utYFQMcpS8u4giRrbTDR15lx9-Q',
 'ঘাড়ের মেরুদণ্ডে আঘাত, মাথা ঘোরা বা ভার্টিগো থাকলে হালকা ঘোরাঘুরি এড়িয়ে চলুন।',
 NULL,
 true),

('ex05_cycling',      'সাইকেল চালানো',         'Cycling',
 'cardio','endurance','medium','intermediate',
 1320, 22, NULL, NULL, 3,
 150,
 'সাইকেল চালানো — হাঁটুর ওপর কম চাপ পড়ে, ক্যালোরি খরচ বেশি, গ্লুকোজ নিয়ন্ত্রণে কার্যকর।',
 '["সাইকেলের সিট উচ্চতা ঠিক করুন", "৫ মিনিট ধীরে প্যাডেলিং", "মাঝারি গতিতে ১৫-৩০ মিনিট", "পাহাড়ে গিয়ার লাইট রাখুন", "শেষে স্ট্রেচিং"]'::jsonb,
 'প্রতিটি পুনরাবৃত্তিতে রেজিস্ট্যান্স একই রাখুন।',
 '{"bicycle"}', false, false, false, true, false,
 false, true, true, true, true,
 'https://jjkvoiapufnhydnebdwk.supabase.co/storage/v1/object/sign/exercise/Cycling.mp4?token=eyJraWQiOiJmMDA1MDg0MS0yNjYzLTQ5NjYtOGE3Zi1hMWFjZTYyZjJhNDUiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJleGVyY2lzZS9DeWNsaW5nLm1wNCIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODcwMTQxMzcsImV4cCI6MjEwMjM3NDEzN30.oDzPVu6OReIBLXg2D8XNdBSAIpZfQXfCca53cfPMn8M',
 'হাঁটুতে ব্যথা থাকলে রেজিস্ট্যান্স কমিয়ে শুরু করুন।',
 'গুরুতর হাঁটুর আর্থ্রাইটিস থাকলে সাইকেল এড়িয়ে চলুন।',
 true),

('ex08_stair_climb',  'সিঁড়ি ওঠানামা',         'Stair Climbing',
 'cardio','endurance','medium','intermediate',
 600, 10, NULL, NULL, 3,
 160,
 'সিঁড়ি দিয়ে ওঠানামা — পায়ের পেশি ও হৃদযন্ত্রের জন্য অত্যন্ত কার্যকর।',
 '["৩ মিনিট ধীরে হেঁটে warm-up", "সিঁড়ির রেলিং ধরে ৫-১৫ মিনিট", "হাঁটু সোজা রাখুন", "বিশ্রাম ৩০ সেকেন্ড"]'::jsonb,
 'রেলিং সবসময় ধরে রাখুন।',
 '{}', false, false, false, true, true,
 true, true, true, true, true,
 'https://jjkvoiapufnhydnebdwk.supabase.co/storage/v1/object/sign/exercise/Stair%20Climbing.mp4?token=eyJraWQiOiJmMDA1MDg0MS0yNjYzLTQ5NjYtOGE3Zi1hMWFjZTYyZjJhNDUiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJleGVyY2lzZS9TdGFpciBDbGltYmluZy5tcDQiLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzg3MDE0MTg2LCJleHAiOjE4MTg1NTAxODZ9.vR4ODHR8xP5vCvX_eKZ_ZKBj5fOX_Fz6MphC4gfZKmE',
 'হাঁটুতে ব্যথা হলে থামুন। খালি পেটে করবেন না।',
 'সদ্য হাঁটু অপারেশন হলে বিশেষজ্ঞের পরামর্শ নিন।',
 true),

('ex07_jogging',      'হালকা জগিং',             'Light Jogging',
 'cardio','endurance','medium','intermediate',
 900, 15, NULL, NULL, 3,
 150,
 'ধীর গতিতে জগিং — ব্রিস্ক ওয়াকের চেয়ে বেশি ক্যালোরি খরচ, ফুসফুসের ক্ষমতা বাড়ায়।',
 '["৫ মিনিট ব্রিস্ক ওয়াক warm-up", "ধীরে জগিং শুরু", "হাত স্বাভাবিক দোলায়", "১০-২০ মিনিট জগিং", "শেষে হাঁটা ও স্ট্রেচিং"]'::jsonb,
 'জগিং বাড়াতে থাকলে প্রতি সপ্তাহে মাত্র ১০% সময় বাড়ান।',
 '{}', false, false, false, false, false,
 false, true, true, true, true,
 'https://jjkvoiapufnhydnebdwk.supabase.co/storage/v1/object/sign/exercise/Light%20Jogging.mp4?token=eyJraWQiOiJmMDA1MDg0MS0yNjYzLTQ5NjYtOGE3Zi1hMWFjZTYyZjJhNDUiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJleGVyY2lzZS9MaWdodCBKb2dnaW5nLm1wNCIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODcwMTQxNjksImV4cCI6MTgxODU1MDE2OX0.FHqJzgtY92eTx5Y-uEq3E7oFeyXwdx4_X-fkJ5lrNI4',
 'বুকে ব্যথা, অতিরিক্ত হাঁপানে বা মাথা ঘোরালে থামুন। শক্ত পৃষ্ঠে জগিং করবেন না।',
 'বাত, হাঁটু সমস্যা বা BMI ৩৫-এর বেশি হলে ব্রিস্ক ওয়াক-এ ফিরে যান।',
 true)

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
-- 3. REFRESH get_today_workout RPC
-- ============================================================================
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
      'sub_category', w.sub_category,
      'intensity', w.intensity,
      'difficulty', w.difficulty,
      'target_duration_seconds', w.target_duration_seconds,
      'duration_min', w.duration_min,
      'sets', w.sets,
      'repetitions', w.repetitions,
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

-- ============================================================================
-- 4. RESEED WORKOUT_ASSIGNMENTS
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

  insert into public.workout_assignments
    (user_id, day_index, workout_id, position, is_active)
  values
    (v_user, 1, 'ex02_walking', 0, true),
    (v_user, 1, 'ex04_brisk_walk', 1, true),
    (v_user, 1, 'ex09_shoulder', 2, true),
    (v_user, 1, 'ex10_neck', 3, true),
    (v_user, 2, 'ex02_walking', 0, true),
    (v_user, 2, 'ex06_chair_squats', 1, true),
    (v_user, 2, 'ex11_sit_to_stand', 2, true),
    (v_user, 2, 'ex10_neck', 3, true),
    (v_user, 3, 'ex02_walking', 0, true),
    (v_user, 3, 'ex01_band', 1, true),
    (v_user, 3, 'ex07_jogging', 2, true),
    (v_user, 3, 'ex09_shoulder', 3, true),
    (v_user, 3, 'ex10_neck', 4, true),
    (v_user, 4, 'ex02_walking', 0, true),
    (v_user, 4, 'ex03_single_leg', 1, true),
    (v_user, 4, 'ex05_cycling', 2, true),
    (v_user, 4, 'ex09_shoulder', 3, true),
    (v_user, 4, 'ex10_neck', 4, true),
    (v_user, 5, 'ex02_walking', 0, true),
    (v_user, 5, 'ex12_wall_pushup', 1, true),
    (v_user, 5, 'ex08_stair_climb', 2, true),
    (v_user, 5, 'ex11_sit_to_stand', 3, true),
    (v_user, 5, 'ex10_neck', 4, true),
    (v_user, 6, 'ex02_walking', 0, true),
    (v_user, 6, 'ex04_brisk_walk', 1, true),
    (v_user, 6, 'ex09_shoulder', 2, true),
    (v_user, 6, 'ex10_neck', 3, true),
    (v_user, 7, 'ex02_walking', 0, true),
    (v_user, 7, 'ex09_shoulder', 1, true),
    (v_user, 7, 'ex10_neck', 2, true),

    (v_user, 8, 'ex02_walking', 0, true),
    (v_user, 8, 'ex06_chair_squats', 1, true),
    (v_user, 8, 'ex03_single_leg', 2, true),
    (v_user, 8, 'ex11_sit_to_stand', 3, true),
    (v_user, 8, 'ex10_neck', 4, true),
    (v_user, 9, 'ex02_walking', 0, true),
    (v_user, 9, 'ex01_band', 1, true),
    (v_user, 9, 'ex04_brisk_walk', 2, true),
    (v_user, 9, 'ex09_shoulder', 3, true),
    (v_user, 9, 'ex10_neck', 4, true),
    (v_user, 10, 'ex02_walking', 0, true),
    (v_user, 10, 'ex12_wall_pushup', 1, true),
    (v_user, 10, 'ex07_jogging', 2, true),
    (v_user, 10, 'ex11_sit_to_stand', 3, true),
    (v_user, 10, 'ex10_neck', 4, true),
    (v_user, 11, 'ex02_walking', 0, true),
    (v_user, 11, 'ex03_single_leg', 1, true),
    (v_user, 11, 'ex05_cycling', 2, true),
    (v_user, 11, 'ex09_shoulder', 3, true),
    (v_user, 11, 'ex10_neck', 4, true),
    (v_user, 12, 'ex02_walking', 0, true),
    (v_user, 12, 'ex06_chair_squats', 1, true),
    (v_user, 12, 'ex08_stair_climb', 2, true),
    (v_user, 12, 'ex09_shoulder', 3, true),
    (v_user, 12, 'ex10_neck', 4, true),
    (v_user, 13, 'ex02_walking', 0, true),
    (v_user, 13, 'ex01_band', 1, true),
    (v_user, 13, 'ex11_sit_to_stand', 2, true),
    (v_user, 13, 'ex03_single_leg', 3, true),
    (v_user, 13, 'ex10_neck', 4, true),
    (v_user, 14, 'ex02_walking', 0, true),
    (v_user, 14, 'ex09_shoulder', 1, true),
    (v_user, 14, 'ex10_neck', 2, true),

    (v_user, 15, 'ex02_walking', 0, true),
    (v_user, 15, 'ex04_brisk_walk', 1, true),
    (v_user, 15, 'ex12_wall_pushup', 2, true),
    (v_user, 15, 'ex03_single_leg', 3, true),
    (v_user, 15, 'ex09_shoulder', 4, true),
    (v_user, 15, 'ex10_neck', 5, true),
    (v_user, 16, 'ex02_walking', 0, true),
    (v_user, 16, 'ex07_jogging', 1, true),
    (v_user, 16, 'ex01_band', 2, true),
    (v_user, 16, 'ex06_chair_squats', 3, true),
    (v_user, 16, 'ex10_neck', 4, true),
    (v_user, 17, 'ex02_walking', 0, true),
    (v_user, 17, 'ex05_cycling', 1, true),
    (v_user, 17, 'ex08_stair_climb', 2, true),
    (v_user, 17, 'ex11_sit_to_stand', 3, true),
    (v_user, 17, 'ex09_shoulder', 4, true),
    (v_user, 17, 'ex10_neck', 5, true),
    (v_user, 18, 'ex02_walking', 0, true),
    (v_user, 18, 'ex04_brisk_walk', 1, true),
    (v_user, 18, 'ex01_band', 2, true),
    (v_user, 18, 'ex03_single_leg', 3, true),
    (v_user, 18, 'ex10_neck', 4, true),
    (v_user, 19, 'ex02_walking', 0, true),
    (v_user, 19, 'ex06_chair_squats', 1, true),
    (v_user, 19, 'ex12_wall_pushup', 2, true),
    (v_user, 19, 'ex11_sit_to_stand', 3, true),
    (v_user, 19, 'ex09_shoulder', 4, true),
    (v_user, 19, 'ex10_neck', 5, true),
    (v_user, 20, 'ex02_walking', 0, true),
    (v_user, 20, 'ex04_brisk_walk', 1, true),
    (v_user, 20, 'ex07_jogging', 2, true),
    (v_user, 20, 'ex08_stair_climb', 3, true),
    (v_user, 20, 'ex10_neck', 4, true),
    (v_user, 21, 'ex02_walking', 0, true),
    (v_user, 21, 'ex09_shoulder', 1, true),
    (v_user, 21, 'ex10_neck', 2, true),

    (v_user, 22, 'ex02_walking', 0, true),
    (v_user, 22, 'ex04_brisk_walk', 1, true),
    (v_user, 22, 'ex01_band', 2, true),
    (v_user, 22, 'ex06_chair_squats', 3, true),
    (v_user, 22, 'ex03_single_leg', 4, true),
    (v_user, 22, 'ex12_wall_pushup', 5, true),
    (v_user, 22, 'ex10_neck', 6, true),
    (v_user, 23, 'ex02_walking', 0, true),
    (v_user, 23, 'ex05_cycling', 1, true),
    (v_user, 23, 'ex11_sit_to_stand', 2, true),
    (v_user, 23, 'ex09_shoulder', 3, true),
    (v_user, 23, 'ex10_neck', 4, true),
    (v_user, 24, 'ex02_walking', 0, true),
    (v_user, 24, 'ex04_brisk_walk', 1, true),
    (v_user, 24, 'ex07_jogging', 2, true),
    (v_user, 24, 'ex06_chair_squats', 3, true),
    (v_user, 24, 'ex10_neck', 4, true),
    (v_user, 25, 'ex02_walking', 0, true),
    (v_user, 25, 'ex01_band', 1, true),
    (v_user, 25, 'ex12_wall_pushup', 2, true),
    (v_user, 25, 'ex03_single_leg', 3, true),
    (v_user, 25, 'ex11_sit_to_stand', 4, true),
    (v_user, 25, 'ex09_shoulder', 5, true),
    (v_user, 25, 'ex10_neck', 6, true),
    (v_user, 26, 'ex02_walking', 0, true),
    (v_user, 26, 'ex04_brisk_walk', 1, true),
    (v_user, 26, 'ex08_stair_climb', 2, true),
    (v_user, 26, 'ex05_cycling', 3, true),
    (v_user, 26, 'ex10_neck', 4, true),
    (v_user, 27, 'ex02_walking', 0, true),
    (v_user, 27, 'ex06_chair_squats', 1, true),
    (v_user, 27, 'ex07_jogging', 2, true),
    (v_user, 27, 'ex12_wall_pushup', 3, true),
    (v_user, 27, 'ex11_sit_to_stand', 4, true),
    (v_user, 27, 'ex09_shoulder', 5, true),
    (v_user, 27, 'ex10_neck', 6, true),
    (v_user, 28, 'ex02_walking', 0, true),
    (v_user, 28, 'ex09_shoulder', 1, true),
    (v_user, 28, 'ex10_neck', 2, true),
    (v_user, 29, 'ex02_walking', 0, true),
    (v_user, 29, 'ex04_brisk_walk', 1, true),
    (v_user, 29, 'ex03_single_leg', 2, true),
    (v_user, 29, 'ex11_sit_to_stand', 3, true),
    (v_user, 29, 'ex10_neck', 4, true),
    (v_user, 30, 'ex02_walking', 0, true),
    (v_user, 30, 'ex09_shoulder', 1, true),
    (v_user, 30, 'ex10_neck', 2, true)
  on conflict (user_id, day_index, workout_id) do update set
    position  = excluded.position,
    is_active = true;
end $$;

grant execute on function public.reseed_full_workout_plan() to authenticated;

-- ============================================================================
-- 5. EXECUTE & RELOAD
-- ============================================================================
do $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is not null then
    perform public.reseed_full_workout_plan();
  end if;
end $$;

NOTIFY pgrst, 'reload schema';
