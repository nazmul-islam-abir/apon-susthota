-- ============================================================
-- Amar Diet — meal details (per-food Bangla recipe/info page)
--
-- Each food in `public.foods` can have a one-to-one details row in
-- `public.food_details` that powers the MealDetailsScreen (mirrors the
-- reference design — hero image, prep time, difficulty, calorie ring,
-- nutritional value bars, "Why Eat This?" intro, and benefit cards).
--
-- This is the Bangladeshi diabetes-app version of that design: every
-- string lives in Bangla, every benefit ties back to the user's
-- clinical picture (HbA1c / BMI / BP / CKD / heart), and the
-- ingredients use locally familiar units (কাপ, বাটি, টুকরা, চা-চামচ).
--
-- Run AFTER 01_schema.sql (creates public.foods) and after the
-- meal_intake SQLs. Re-runnable: every block uses IF NOT EXISTS /
-- ON CONFLICT DO NOTHING.
-- ============================================================


-- ---------- 1. TABLE ----------
create table if not exists public.food_details (
  food_id text primary key
    references public.foods(id) on delete cascade,

  -- Recipe / kitchen facts.
  prep_time_min   int  not null default 10
    check (prep_time_min > 0 and prep_time_min <= 240),
  difficulty      text not null default 'easy'
    check (difficulty in ('easy', 'medium', 'hard')),

  -- Short user-facing summary (the first paragraph under the hero
  -- image in the details screen — "Why eat this?").
  why_eat_this_bn text not null default '',

  -- Ingredient list. Each row is a short Bangla string with local
  -- units ("১ কাপ লাল চাল", "১ টুকরা রুই মাছ"). Used to render a
  -- bullet list in the details page.
  ingredients_bn  text[] not null default '{}',

  -- Cooking steps, ordered. Each step is one short Bangla sentence.
  steps_bn        text[] not null default '{}',

  -- 3 short benefit cards (icon + title + 1-2 line description).
  -- Stored as a single jsonb array so the order is preserved and the
  -- icon + title + body are always kept together.
  benefits        jsonb not null default '[]'::jsonb,

  -- Optional clinician-style cautions (CKD, BP, GI, pregnancy...).
  -- Rendered as a red-bordered strip on the details page when present.
  cautions_bn     text[] not null default '{}',

  -- Optional serving-tip (e.g. "লেবু ও কাঁচা মরিচ দিয়ে খান").
  serving_tip_bn  text,

  -- Audit.
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- Trigger: keep updated_at fresh on UPDATE.
-- ---------- 0b. AUTO-TOUCH updated_at (per-table helper, matches the
-- pattern used by user_meal_plans and meal_plan_overrides) ----------
create or replace function public.touch_food_details_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_food_details_updated_at on public.food_details;
create trigger trg_food_details_updated_at
  before update on public.food_details
  for each row execute function public.touch_food_details_updated_at();

alter table public.food_details enable row level security;

drop policy if exists "Food details readable by any authenticated user"
  on public.food_details;
create policy "Food details readable by any authenticated user"
  on public.food_details for select
  using (auth.role() = 'authenticated');


-- ---------- 2. INDEXES ----------
create index if not exists food_details_difficulty_idx
  on public.food_details (difficulty);


-- ============================================================
-- 3. RPC — get_food_details(p_food_id text)
--
-- Returns a single JSON object joining public.foods + public.food_details
-- so the client can paint the whole MealDetailsScreen in one round trip.
-- Falls back gracefully when no details row exists yet — the screen
-- still renders with a "তথ্য শীঘ্রই আসছে" placeholder.
-- ============================================================
create or replace function public.get_food_details(p_food_id text)
returns jsonb
language plpgsql
stable
security invoker
as $$
declare
  v_food    jsonb;
  v_details jsonb;
  v_out     jsonb;
begin
  if p_food_id is null or btrim(p_food_id) = '' then
    raise exception 'p_food_id is required';
  end if;

  -- Master food row (id, name, category, macros, GI, portion...).
  select to_jsonb(f.*) into v_food
  from public.foods f
  where f.id = p_food_id;

  if v_food is null then
    return jsonb_build_object('found', false, 'food_id', p_food_id);
  end if;

  -- Optional details row. Defaults populated when missing so the
  -- client never has to special-case nulls.
  select jsonb_build_object(
           'prep_time_min',  coalesce(d.prep_time_min, 10),
           'difficulty',     coalesce(d.difficulty, 'easy'),
           'why_eat_this_bn', coalesce(d.why_eat_this_bn, ''),
           'ingredients_bn', coalesce(d.ingredients_bn, '{}'::text[]),
           'steps_bn',       coalesce(d.steps_bn,       '{}'::text[]),
           'benefits',       coalesce(d.benefits,       '[]'::jsonb),
           'cautions_bn',    coalesce(d.cautions_bn,    '{}'::text[]),
           'serving_tip_bn', d.serving_tip_bn,
           'has_details',    true
         )
    into v_details
  from public.food_details d
  where d.food_id = p_food_id;

  if v_details is null then
    v_details := jsonb_build_object(
      'prep_time_min',  10,
      'difficulty',     'easy',
      'why_eat_this_bn', '',
      'ingredients_bn', '{}'::text[],
      'steps_bn',       '{}'::text[],
      'benefits',       '[]'::jsonb,
      'cautions_bn',    '{}'::text[],
      'serving_tip_bn', null,
      'has_details',    false
    );
  end if;

  v_out := v_food || v_details;
  v_out := v_out || jsonb_build_object('found', true);
  return v_out;
end;
$$;

revoke all on function public.get_food_details(text) from public;
grant execute on function public.get_food_details(text) to authenticated;


-- ============================================================
-- 4. SEED — top Bangladeshi foods used by the 30-day rotation
-- ============================================================

-- ---- breakfast ----
insert into public.food_details
  (food_id, prep_time_min, difficulty, why_eat_this_bn, ingredients_bn, steps_bn, benefits, cautions_bn, serving_tip_bn) values
('b_lal_ruti', 10, 'easy',
 'লাল আটার রুটি ডায়াবেটিস-বান্ধব একটি বাংলাদেশি ঐতিহ্যবাহী খাবার। এতে আঁশ বেশি থাকায় রক্তে শর্করা ধীরে ধীরে শোষণ হয় এবং দীর্ঘক্ষণ পেট ভরা থাকে।',
  ARRAY['২ কাপ লাল আটা', '১/২ চা-চামচ লবণ', 'পরিমাণ মতো পানি', '১ চা-চামচ তেল'],
  ARRAY['লাল আটা ও লবণ একসাথে মেখে নিন।','পানি ধীরে ধীরে দিয়ে নরম মাখুন, ১০ মিনিট ঢেকে রাখুন।','ছোট ছোট বল বানিয়ে সমতল করুন।','শুকনো তাওয়ায় দুই পাশে সেঁকে নিন।'],
  '[
    {"icon":"favorite","title":"হৃদযন্ত্রের জন্য ভালো","body":"লাল আটায় সম্পৃক্ত চর্বি কম, ফলে হৃদরোগের ঝুঁকি কমায়।"},
    {"icon":"bolt","title":"ধীরে শর্করা শোষণ","body":"কম গ্লাইসেমিক ইনডেক্সের কারণে রক্তে গ্লুকোজ হঠাৎ বাড়ে না।"},
    {"icon":"restaurant","title":"বাংলাদেশে সহজলভ্য","body":"স্থানীয় বাজারে কম দামে পাওয়া যায়।"}
  ]'::jsonb,
  ARRAY['কিডনি রোগ থাকলে পরিমাণ কমিয়ে খান — লাল আটায় ফসফরাস তুলনামূলক বেশি।'],
  'সবজি ভাজি বা ডিমের ঝোলের সাথে খান।'),
('b_cha_pata', 5, 'easy',
 'সকালের হালকা চায়ের সাথে একটু মুড়ি বা চিড়া — বাংলার চিরন্তন অভ্যাস যা ডায়াবেটিস নিয়ন্ত্রণে সহায়ক।',
  ARRAY['১ কাপ চা (চিনি ছাড়া)', '৩০ গ্রাম মুড়ি বা চিড়া'],
  ARRAY['চা পাতা ফুটিয়ে ছেঁকে নিন।','চিনি ছাড়া বা চিনির বিকল্প (স্টেভিয়া) দিয়ে পান করুন।','মুড়ি/চিড়া আলাদা পাত্রে রেখে সাথে খান।'],
  '[
    {"icon":"local_drink","title":"হাইড্রেশন","body":"সকালে এক কাপ চা শরীরের পানির চাহিদা পূরণে সাহায্য করে।"},
    {"icon":"schedule","title":"দ্রুত প্রস্তুত","body":"৫ মিনিটেই তৈরি — ব্যস্ত সকালের জন্য আদর্শ।"}
  ]'::jsonb,
  ARRAY['চায়ে চিনি একেবারে না দেওয়াই ভালো।','অতিরিক্ত মুড়ি গ্লুকোজ দ্রুত বাড়াতে পারে — অল্প পরিমাণে রাখুন।'],
  null),
('b_sobji_ruti', 15, 'medium',
 'সবজি ভাজি দিয়ে লাল আটার রুটি — আঁশ, ভিটামিন ও খনিজে ভরপুর একটি ভারসাম্যপূর্ণ সকালের খাবার।',
  ARRAY['২টি লাল আটার রুটি', '১ বাটি যেকোনো সবজি ভাজি (লাউ/বেগুন/পটল)', '১ চা-চামচ তেল', 'সামান্য হলুদ ও লবণ'],
  ARRAY['সবজি কেটে নিন।','তেলে হলুদ ও লবণ দিয়ে অল্প পানিতে ভাজি রান্না করুন।','লাল আটার রুটি আলাদাভাবে সেঁকে নিন।','গরম গরম পরিবেশন করুন।'],
  '[
    {"icon":"eco","title":"আঁশে ভরপুর","body":"সবজি ও লাল আটার মিশ্রণ বাড়তি ফাইবার দেয় — কোষ্ঠকাঠিন্য ও গ্লুকোজ স্পাইক দুটোই কমায়।"},
    {"icon":"favorite","title":"রক্তচাপ নিয়ন্ত্রণ","body":"কম সোডিয়ামে রান্না করলে উচ্চ রক্তচাপের রোগীদের জন্য নিরাপদ।"},
    {"icon":"payments","title":"কম খরচে পুষ্টি","body":"সবজি মৌসুম অনুযায়ী বাজার থেকে কিনলে খরচ কম, পুষ্টি বেশি।"}
  ]'::jsonb,
  ARRAY['কিডনি রোগ থাকলে পালং শাক/লাল শাক এড়িয়ে অন্য সবজি ব্যবহার করুন।'],
  'সকালে একটু পানিসহ খান।'),
('b_chira_doi', 5, 'easy',
 'চিড়ার সাথে টক দই — সকালের হালকা খাবার যা প্রোটিন ও ক্যালসিয়াম দেয়, গ্লুকোজও তেমন বাড়ায় না।',
  ARRAY['৩০ গ্রাম চিড়া', 'আধা কাপ টক দই (চিনি ছাড়া)'],
  ARRAY['চিড়া একটি পাত্রে রাখুন।','চিনি ছাড়া টক দই আলাদাভাবে পরিবেশন করুন।','চিড়ায় দই মিশিয়ে খান।'],
  '[
    {"icon":"water_drop","title":"প্রোটিন ও ক্যালসিয়াম","body":"টক দই দাঁত ও হাড়ের জন্য উপকারী।"},
    {"icon":"bolt","title":"দ্রুত তৈরি","body":"৫ মিনিটের নাস্তা — সময় কম, পুষ্টি বেশি।"}
  ]'::jsonb,
  ARRAY['চিনি যুক্ত মিষ্টি দই এড়িয়ে চিন।'],
  null),
('b_mug_chila', 15, 'medium',
 'মুগ ডালের চিলা — উচ্চ প্রোটিন, কম গ্লুকোজ স্পাইক। ডায়াবেটিস রোগীদের জন্য চমৎকার সকালের পছন্দ।',
  ARRAY['১ কাপ মুগ ডাল (৪ ঘণ্টা ভেজানো)', '১ চা-চামচ আদা কুচি', '১টি কাঁচা মরিচ কুচি', 'সামান্য লবণ ও হলুদ', '১ চা-চামচ তেল'],
  ARRAY['ভেজানো ডাল মিক্সিতে পেস্ট বানান।','এতে আদা, মরিচ, লবণ, হলুদ মেশান।','তাওয়ায় তেল দিয়ে ব্যাটার ঢেলে দুই পাশে সেঁকে নিন।'],
  '[
    {"icon":"fitness_center","title":"উচ্চ প্রোটিন","body":"মুগ ডালে উদ্ভিজ্জ প্রোটিন বেশি — দীর্ঘক্ষণ পেট ভরা থাকে।"},
    {"icon":"bolt","title":"স্থিতিশীল শর্করা","body":"কম গ্লাইসেমিক — গ্লুকোজ ধীরে ধীরে বাড়ে।"}
  ]'::jsonb,
  ARRAY['কিডনি রোগ থাকলে পরিমাণ কমিয়ে খান, ডিমের বিকল্প হিসেবে ভাবুন।'],
  'সবুজ চাটনি দিয়ে খান।'),
('b_oats_khichuri', 20, 'medium',
 'ওটস খিচুড়ি — ওটস ও ডাল-সবজির মিশ্রণ, পেট ভরা রাখে এবং গ্লুকোজ নিয়ন্ত্রণে সহায়ক।',
  ARRAY['৪০ গ্রাম ওটস', '৩০ গ্রাম মুগ ডাল', '১/২ কাপ সবজি কুচি (গাজর, বরবটি, লাউ)', '১ চা-চামচ তেল', 'সামান্য হলুদ ও লবণ'],
  ARRAY['ওটস ও ডাল ধুয়ে নিন।','প্রেশার কুকারে সবজিসহ ২ কাপ পানিতে ২-৩ সিটি দিন।','নামিয়ে হালকা তেলে ভেজে নিন।'],
  '[
    {"icon":"eco","title":"আঁশে ভরপুর","body":"ওটসের বিটা-গ্লুকান কোলেস্টেরল কমাতে সাহায্য করে।"},
    {"icon":"restaurant","title":"এক বাটিতে ভারসাম্য","body":"কার্ব + প্রোটিন + সবজি একসাথে — ডায়াবেটিস-বান্ধব খাবার।"}
  ]'::jsonb,
  ARRAY['কিডনি রোগীরা পরিমাণ অর্ধেক করে খেতে পারেন।'],
  'একটু লেবু চিপে খান।')
on conflict (food_id) do nothing;


-- ---- carb ----
insert into public.food_details
  (food_id, prep_time_min, difficulty, why_eat_this_bn, ingredients_bn, steps_bn, benefits, cautions_bn, serving_tip_bn) values
('c_lalchal_bhat', 20, 'easy',
 'লাল চালের ভাত সাদা চালের চেয়ে বেশি আঁশ ও পুষ্টিগুণ সম্পন্ন। গ্লুকোজ স্পাইক কম এবং দীর্ঘক্ষণ পেট ভরা রাখে।',
  ARRAY['১ কাপ লাল চাল', '২ কাপ পানি', 'সামান্য লবণ'],
  ARRAY['লাল চাল ৩০ মিনিট ভিজিয়ে রাখুন।','পানিসহ রান্না করুন, ফোড়ন ছাড়া।','মাঝারি আঁচে ১৫-২০ মিনিট রান্না করুন।'],
  '[
    {"icon":"eco","title":"বেশি ফাইবার","body":"সাদা চালের তুলনায় ৩ গুণ বেশি আঁশ — হজমশক্তি বাড়ায়।"},
    {"icon":"bolt","title":"কম গ্লাইসেমিক","body":"গ্লুকোজ ধীরে শোষণ হয়।"}
  ]'::jsonb,
  ARRAY['অতিরিক্ত ভাত খেলে কার্ব বেড়ে যায় — ১ কাপের বেশি না খাওয়াই ভালো।'],
  'সবজি ও ডালের সাথে একসাথে খান।'),
('c_lal_ruti_3', 20, 'medium',
 '৩টি লাল আটার রুটি দুপুরের খাবারে কার্বোহাইড্রেটের চাহিদা পূরণ করে, সাথে সবজি-ডাল-মাছ পূর্ণ খাবার বানায়।',
  ARRAY['৩ কাপ লাল আটা', '১ চা-চামচ লবণ', 'পরিমাণ মতো পানি'],
  ARRAY['ময়ান মেখে ১৫ মিনিট রাখুন।','বল বানিয়ে রুটি সেঁকে নিন।'],
  '[
    {"icon":"favorite","title":"ভালো কার্ব","body":"কার্বের পাশাপাশি আঁশ ও প্রোটিনও পাওয়া যায়।"}
  ]'::jsonb,
  ARRAY['সোডিয়াম বেশি থাকে — উচ্চ রক্তচাপের রোগীরা অল্প লবণে রাঁধুন।'],
  'সবজি ও ডালের সাথে খান।'),
('c_lal_ruti_2', 15, 'easy',
 'দুটি লাল আটার রুটি — দুপুরের হালকা খাবার বা রাতের হালকা ডিনারের জন্য উপযুক্ত।',
  ARRAY['২ কাপ লাল আটা', '১/২ চা-চামচ লবণ', 'পানি'],
  ARRAY['মাখুন, ১০ মিনিট রাখুন।','রুটি সেঁকে নিন।'],
  '[
    {"icon":"schedule","title":"সহজ ও দ্রুত","body":"১৫ মিনিটে প্রস্তুত।"}
  ]'::jsonb,
  ARRAY[]::text[],
  'ডিম বা সবজি দিয়ে খান।'),
('c_kumra', 15, 'easy',
 'মিষ্টি কুমড়া ভিটামিন A-তে সমৃদ্ধ। এটি সীমিত পরিমাণে খেলে ডায়াবেটিস রোগীদের জন্য ভালো।',
  ARRAY['১ কাপ কুমড়া কুচি', 'পানি'],
  ARRAY['কুমড়া ধুয়ে কুচি করুন।','১ কাপ পানিতে সেদ্ধ করুন।','ভর্তা বা তরকারি করে খান।'],
  '[
    {"icon":"visibility","title":"চোখের জন্য ভালো","body":"বিটা-ক্যারোটিন দৃষ্টিশক্তি ভালো রাখে।"},
    {"icon":"favorite","title":"অ্যান্টিঅক্সিডেন্ট","body":"ফ্রি-র‌্যাডিক্যালের ক্ষতি কমায়।"}
  ]'::jsonb,
  ARRAY['কিডনি রোগে পটাসিয়াম বেশি থাকে — অল্প পরিমাণে খান।'],
  'সামান্য তেলে ভেজে খেলে স্বাদ ভালো হয়।'),
('c_potato_1pc', 10, 'easy',
 'আলু সেদ্ধ — দ্রুত শক্তি জোগায়, তবে পরিমিত পরিমাণে খাওয়া উচিত।',
  ARRAY['১টি মাঝারি আলু', 'পানি'],
  ARRAY['আলু ভালো করে ধুয়ে নিন।','লবণ-পানিতে সেদ্ধ করুন।','খোসা ছাড়িয়ে খান।'],
  '[
    {"icon":"bolt","title":"দ্রুত শক্তি","body":"শর্করা দ্রুত সরবরাহ করে।"}
  ]'::jsonb,
  ARRAY['গ্লাইসেমিক ইনডেক্স মাঝারি — অতিরিক্ত খাবেন না।','কিডনি রোগীরা পটাসিয়ামের কারণে সীমিত রাখুন।'],
  null),
('c_uguni', 15, 'medium',
 'সুজি বা সাগু দিয়ে ভুনি — বাংলাদেশের ঐতিহ্যবাহী মিষ্টি নাস্তা, ডায়াবেটিসে চিনি ছাড়া বানালে ভালো বিকল্প।',
  ARRAY['১ কাপ সুজি', '১ চা-চামচ ঘি', '১ কাপ পানি', 'সামান্য দারুচিনি গুঁড়া'],
  ARRAY['সুজি শুকনো ভেজে নিন।','পানিতে সেদ্ধ করে ঘি দিয়ে মেখে নিন।','দারুচিনি ছিটিয়ে পরিবেশন করুন।'],
  '[
    {"icon":"schedule","title":"সহজে শক্তি","body":"হালকা নাস্তা হিসেবে উপযুক্ত।"}
  ]'::jsonb,
  ARRAY['চিনি যোগ করবেন না।'],
  'কলা বা পেয়ারার সাথে খান।')
on conflict (food_id) do nothing;


-- ---- protein ----
insert into public.food_details
  (food_id, prep_time_min, difficulty, why_eat_this_bn, ingredients_bn, steps_bn, benefits, cautions_bn, serving_tip_bn) values
('p_rui', 20, 'medium',
 'রুই মাছ ভাপা বা ভুকরা — উচ্চমানের প্রোটিন ও ওমেগা-৩ ফ্যাটি অ্যাসিডের চমৎকার উৎস। হৃদযন্ত্র ও মস্তিষ্কের জন্য উপকারী।',
  ARRAY['৮০ গ্রাম রুই মাছের টুকরা', '১ চা-চামচ আদা কুচি', '১ চা-চামচ রসুন কুচি', '১/২ চা-চামচ হলুদ', 'সামান্য লবণ', '১ চা-চামচ সরিষার তেল'],
  ARRAY['মাছ ধুয়ে মশলা মাখুন।','১০ মিনিট রেখে দিন।','বাটিতে রেখে ভাপায় ১০-১২ মিনিট সেদ্ধ করুন অথবা অল্প তেলে ভুকরা করুন।'],
  '[
    {"icon":"favorite","title":"হৃদয়ের জন্য ভালো","body":"ওমেগা-৩ ফ্যাটি অ্যাসিড কোলেস্টেরল কমায়।"},
    {"icon":"bolt","title":"উচ্চ প্রোটিন","body":"মাংসপেশি গঠনে সাহায্য করে।"}
  ]'::jsonb,
  ARRAY['তেলে ভাজলে ক্যালোরি বেড়ে যায় — ভাপায় রান্না করা ভালো।'],
  'লেবু চিপে খান।'),
('p_tilapia', 15, 'medium',
 'তেলাপিয়া মাছ — সহজলভ্য ও সাশ্রয়ী, প্রোটিনের ভালো উৎস।',
  ARRAY['৮০ গ্রাম তেলাপিয়া', 'হলুদ-লবণ', '১ চা-চামচ তেল'],
  ARRAY['মাছে মশলা মাখুন।','কড়াইতে অল্প তেলে দুই পাশে সেঁকে নিন।'],
  '[
    {"icon":"payments","title":"সাশ্রয়ী","body":"সবচেয়ে কম দামের মাছগুলোর একটি।"},
    {"icon":"bolt","title":"প্রোটিন","body":"প্রতি ৮০ গ্রামে ১৭ গ্রাম প্রোটিন।"}
  ]'::jsonb,
  ARRAY[]::text[],
  'সবজি ভাজির সাথে খান।'),
('p_katla', 25, 'medium',
 'কাতলা মাছ ভুকরা — বাংলাদেশের প্রিয় মাছ, ওমেগা-৩ ও প্রোটিনে সমৃদ্ধ।',
  ARRAY['৮০ গ্রাম কাতলা', 'পেঁয়াজ কুচি', 'রসুন কুচি', 'হলুদ-লবণ', 'তেল'],
  ARRAY['মাছে হলুদ-লবণ মাখুন।','পেঁয়াজ-রসুন ভেজে মাছ দিয়ে ভুকরা করুন।'],
  '[
    {"icon":"favorite","title":"ওমেগা-৩","body":"কার্ডিওভাসকুলার সুরক্ষা দেয়।"}
  ]'::jsonb,
  ARRAY['ভাজার চেয়ে ভুকরা বা ভাপায় রান্না করুন।'],
  'ভাত ও সবজির সাথে।'),
('p_shing', 20, 'medium',
 'শিং মাছ — প্রোটিন, আয়রন ও ভিটামিন B12-তে সমৃদ্ধ।',
  ARRAY['৭০ গ্রাম শিং মাছ', 'হলুদ-লবণ', '১ চা-চামচ তেল'],
  ARRAY['মাছে মশলা মাখুন।','তেলে ভেজে নিন।'],
  '[
    {"icon":"bolt","title":"আয়রন সমৃদ্ধ","body":"রক্তস্বল্পতা প্রতিরোধে সহায়ক।"}
  ]'::jsonb,
  ARRAY['কাঁটা বেশি — সাবধানে খান।'],
  null),
('p_murgi', 30, 'medium',
 'চামড়া ছাড়া মুরগির মাংস — উচ্চ প্রোটিন, কম চর্বি। ডায়াবেটিস রোগীদের জন্য চমৎকার প্রোটিনের উৎস।',
  ARRAY['২ টুকরা মুরগির মাংস (চামড়া ছাড়া, ~৯০ গ্রাম)', 'পেঁয়াজ কুচি', 'আদা-রসুন বাটা', 'হলুদ-লবণ-মরিচ', '১ চা-চামচ তেল'],
  ARRAY['মুরগিতে মশলা মাখুন।','১৫ মিনিট রাখুন।','পেঁয়াজ ভেজে মুরগি দিন, অল্প পানিতে ঢেকে রান্না করুন।'],
  '[
    {"icon":"fitness_center","title":"পাতলা প্রোটিন","body":"মাছের মতো প্রোটিন পাওয়া যায়, চর্বি অনেক কম।"},
    {"icon":"favorite","title":"কম কোলেস্টেরল","body":"চামড়া ছাড়ালে কোলেস্টেরল নিয়ন্ত্রণে থাকে।"}
  ]'::jsonb,
  ARRAY['কিডনি রোগে ফসফরাস বেশি — পরিমাণ কমিয়ে খান।'],
  'সালাদের সাথে খান।'),
('p_deshi_murgi', 35, 'medium',
 'দেশি মুরগি — ফার্মের মুরগির চেয়ে বেশি পুষ্টিগুণ ও কম চর্বি।',
  ARRAY['২ টুকরা দেশি মুরগি (~৮৫ গ্রাম)', 'মশলা'],
  ARRAY['মাংসে মশলা মাখুন।','অল্প তেলে ভেজে ঝোলসহ রান্না করুন।'],
  '[
    {"icon":"eco","title":"স্বাভাবিক খাবার","body":"হরমোন/অ্যান্টিবায়োটিকমুক্ত।"}
  ]'::jsonb,
  ARRAY['কিডনি রোগীদের জন্য পরিমিত পরিমাণে খান।'],
  null),
('p_dim', 10, 'easy',
 'ডিম — সবচেয়ে সহজলভ্য ও সস্তায় প্রোটিনের উৎস। ভিটামিন D, B12 ও কোলিনে সমৃদ্ধ।',
  ARRAY['১টি ডিম', 'পানি'],
  ARRAY['পানিতে ৮-১০ মিনিট সেদ্ধ করুন।','ঠান্ডা হলে খোসা ছাড়িয়ে খান।'],
  '[
    {"icon":"bolt","title":"সম্পূর্ণ প্রোটিন","body":"সব অ্যামাইনো অ্যাসিড পাওয়া যায়।"},
    {"icon":"visibility","title":"চোখের জন্য","body":"লুটেইন ও জিয়াক্সান্থিন দৃষ্টিশক্তি রক্ষা করে।"}
  ]'::jsonb,
  ARRAY['কিডনি রোগী দিনে ১টির বেশি না খাওয়াই ভালো।'],
  'লেটুস/শসার সাথে খান।'),
('p_moshur_dal', 25, 'easy',
 'মসুর ডাল — বাংলাদেশের সবচেয়ে জনপ্রিয় ডাল, প্রোটিন ও আয়রনে সমৃদ্ধ, সাশ্রয়ী।',
  ARRAY['১ কাপ মসুর ডাল', 'পেঁয়াজ কুচি', '১ চা-চামচ তেল', 'হলুদ-লবণ', '১ চা-চামচ ধনে গুঁড়া'],
  ARRAY['ডাল ধুয়ে ১৫ মিনিট ভিজিয়ে রাখুন।','পানিসহ সেদ্ধ করুন।','পেঁয়াজ ভেজে ফোড়ন দিন।'],
  '[
    {"icon":"bolt","title":"উদ্ভিজ্জ প্রোটিন","body":"মাছ-মাংস ছাড়াও প্রোটিনের চাহিদা পূরণ করে।"},
    {"icon":"favorite","title":"হৃদযন্ত্র","body":"ফলেট ও পটাসিয়াম রক্তচাপ নিয়ন্ত্রণে সহায়ক।"}
  ]'::jsonb,
  ARRAY['কিডনি রোগে ফসফরাস/পটাসিয়াম বেশি — পরিমিত পরিমাণে খান।'],
  'ভাত-সবজির সাথে।'),
('p_mug_dal', 25, 'medium',
 'মুগ ডাল — হালকা, সহজপাচ্য, প্রোটিনে সমৃদ্ধ। গ্লুকোজ স্পাইক কম।',
  ARRAY['১ কাপ মুগ ডাল', 'পেঁয়াজ', 'হলুদ-লবণ'],
  ARRAY['ডাল ধুয়ে সেদ্ধ করুন।','ফোড়ন দিন।'],
  '[
    {"icon":"schedule","title":"সহজপাচ্য","body":"বদহজমের সমস্যা কমায়।"}
  ]'::jsonb,
  ARRAY['কিডনি রোগীরা পরিমিত পরিমাণে খান।'],
  null),
('p_pabda', 20, 'easy',
 'পাবদা মাছের ঝোল — ক্যালসিয়াম ও প্রোটিনে সমৃদ্ধ, সহজপাচ্য।',
  ARRAY['৮০ গ্রাম পাবদা মাছ', 'হলুদ-লবণ', 'রসুন কুচি', '১ চা-চামচ তেল'],
  ARRAY['মাছ ভেজে তুলে রাখুন।','রসুন ভেজে ঝোল করুন, মাছ দিন।'],
  '[
    {"icon":"water_drop","title":"ক্যালসিয়াম","body":"হাড় ও দাঁতের জন্য উপকারী।"}
  ]'::jsonb,
  ARRAY['কাঁটা বেশি — সাবধানে খান।'],
  null),
('p_liver', 25, 'medium',
 'মুরগির কলিজা — আয়রন, ভিটামিন A ও B12-এর অসাধারণ উৎস। রক্তস্বল্পতা প্রতিরোধে উপকারী।',
  ARRAY['১ টুকরা কলিজা (~৭০ গ্রাম)', 'পেঁয়াজ', 'মশলা'],
  ARRAY['কলিজা ধুয়ে কুচি করুন।','পেঁয়াজ ভেজে কলিজা রান্না করুন।'],
  '[
    {"icon":"favorite","title":"আয়রন","body":"রক্তস্বল্পতা রোধে চমৎকার।"},
    {"icon":"bolt","title":"ভিটামিন A","body":"চোখ ও ত্বকের জন্য উপকারী।"}
  ]'::jsonb,
  ARRAY['কিডনি রোগীরা ফসফরাসের কারণে অল্প পরিমাণে খান।'],
  'সপ্তাহে ১-২ বার।')
on conflict (food_id) do nothing;


-- ---- vegetables ----
insert into public.food_details
  (food_id, prep_time_min, difficulty, why_eat_this_bn, ingredients_bn, steps_bn, benefits, cautions_bn, serving_tip_bn) values
('v_lau', 15, 'easy',
 'লাউ ভাজি — পানিসমৃদ্ধ, ক্যালোরি কম, ফাইবার বেশি। ওজন নিয়ন্ত্রণ ও হজমের জন্য আদর্শ।',
  ARRAY['১ বাটি লাউ কুচি', '১ চা-চামচ তেল', 'হলুদ-লবণ'],
  ARRAY['লাউ কেটে নিন।','তেলে হলুদ দিয়ে ভাজুন।','লবণ দিয়ে নামান।'],
  '[
    {"icon":"water_drop","title":"হাইড্রেশন","body":"পানিশূন্যতা রোধ করে।"},
    {"icon":"eco","title":"কম ক্যালোরি","body":"ওজন নিয়ন্ত্রণে সহায়ক।"}
  ]'::jsonb,
  ARRAY[]::text[],
  'ভাতের সাথে খান।'),
('v_begun', 20, 'easy',
 'বেগুন ভাজি — অ্যান্টিঅক্সিডেন্ট (ন্যাসুনিন) সমৃদ্ধ। হৃদযন্ত্রের জন্য উপকারী।',
  ARRAY['১ বাটি বেগুন কুচি', 'তেল', 'মশলা'],
  ARRAY['বেগুন কেটে নিন।','তেলে ভেজে মশলা দিন।'],
  '[
    {"icon":"favorite","title":"হৃদযন্ত্র","body":"ন্যাসুনিন কোলেস্টেরল কমায়।"}
  ]'::jsonb,
  ARRAY[]::text[],
  null),
('v_potol', 15, 'easy',
 'পটল ভাজি — ফাইবার ও ভিটামিন C সমৃদ্ধ।',
  ARRAY['১ বাটি পটল কুচি', 'তেল', 'মশলা'],
  ARRAY['পটল কেটে নিন।','ভেজে মশলা দিন।'],
  '[
    {"icon":"eco","title":"ফাইবার","body":"হজম ভালো করে।"}
  ]'::jsonb,
  ARRAY[]::text[],
  null),
('v_dhundul', 15, 'easy',
 'ঢেঁড়স ভাজি — ফাইবার ও মিউসিলেজ সমৃদ্ধ, কোষ্ঠকাঠিন্য কমায়।',
  ARRAY['১ বাটি ঢেঁড়স', 'তেল', 'মশলা'],
  ARRAY['ঢেঁড়স কেটে নিন।','ভেজে নিন।'],
  '[
    {"icon":"eco","title":"ফাইবার","body":"কোষ্ঠকাঠিন্য দূর করে।"}
  ]'::jsonb,
  ARRAY[]::text[],
  null),
('v_borboti', 15, 'easy',
 'বরবটি ভাজি — প্রোটিন ও ফাইবারের ভালো উৎস।',
  ARRAY['১ বাটি বরবটি', 'তেল', 'মশলা'],
  ARRAY['বরবটি কেটে নিন।','ভেজে নিন।'],
  '[
    {"icon":"bolt","title":"প্রোটিন","body":"উদ্ভিজ্জ প্রোটিন পাওয়া যায়।"}
  ]'::jsonb,
  ARRAY[]::text[],
  null),
('v_lal_shak', 15, 'easy',
 'লাল শাক — আয়রন ও ফলেটে সমৃদ্ধ, রক্তস্বল্পতা প্রতিরোধে কার্যকর।',
  ARRAY['১ বাটি লাল শাক', 'তেল', 'মশলা'],
  ARRAY['শাক ধুয়ে কুচি করুন।','ভেজে মশলা দিন।'],
  '[
    {"icon":"favorite","title":"আয়রন","body":"রক্তস্বল্পতা রোধ করে।"}
  ]'::jsonb,
  ARRAY['কিডনি রোগে পটাসিয়াম বেশি — সীমিত খান।'],
  null),
('v_palang_shak', 15, 'easy',
 'পালং শাক — আয়রন, ভিটামিন A, C ও ফোলেটে সমৃদ্ধ।',
  ARRAY['১ বাটি পালং শাক', 'তেল', 'মশলা'],
  ARRAY['শাক কুচি করে ভাজুন।'],
  '[
    {"icon":"visibility","title":"চোখের জন্য","body":"লুটেইন ও জিয়াক্সান্থিন দৃষ্টিশক্তি রক্ষা করে।"}
  ]'::jsonb,
  ARRAY['কিডনি রোগীরা পরিমিত পরিমাণে খান।'],
  null),
('v_korola', 20, 'medium',
 'করলা ভাজি — ডায়াবেটিস নিয়ন্ত্রণে ঐতিহ্যবাহী সবজি। তিতা স্বাদ হলেও গ্লুকোজ কমাতে সহায়ক বলে বিশ্বাস করা হয়।',
  ARRAY['১ বাটি করলা কুচি', 'তেল', 'লবণ', 'হলুদ'],
  ARRAY['করলা কেটে লবণ-পানিতে ১০ মিনিট ভিজিয়ে রাখুন (তিতা কমাতে)।','ভেজে মশলা দিন।'],
  '[
    {"icon":"water_drop","title":"গ্লুকোজ নিয়ন্ত্রণ","body":"চারান্টিন ও পলিপেপটাইড-পি গ্লুকোজ শোষণ কমাতে পারে।"}
  ]'::jsonb,
  ARRAY['চিনি-স্বল্পতায় ভুগলে অতিরিক্ত করলা খাবেন না।'],
  'ডিম দিয়ে ভেজে খেলে স্বাদ ভালো হয়।'),
('v_bandhakopi', 15, 'easy',
 'বাধাকপি ভাজি — ভিটামিন C ও K সমৃদ্ধ, ক্যালোরি কম।',
  ARRAY['১ বাটি বাধাকপি কুচি', 'তেল', 'মশলা'],
  ARRAY['কপি কেটে নিন।','ভেজে মশলা দিন।'],
  '[
    {"icon":"eco","title":"ক্যালোরি কম","body":"ওজন নিয়ন্ত্রণে সহায়ক।"}
  ]'::jsonb,
  ARRAY[]::text[],
  null),
('v_shajna', 15, 'easy',
 'শজনে ডাটা — ভিটামিন C, ক্যালসিয়াম ও আয়রনে সমৃদ্ধ।',
  ARRAY['১ বাটি শজনে ডাটা', 'তেল', 'মশলা'],
  ARRAY['ডাটা কেটে নিন।','ভেজে রান্না করুন।'],
  '[
    {"icon":"bolt","title":"ক্যালসিয়াম","body":"হাড়ের জন্য উপকারী।"}
  ]'::jsonb,
  ARRAY[]::text[],
  null),
('v_chichinga', 15, 'easy',
 'চিচিঙ্গা ভাজি — হালকা ও সহজপাচ্য সবজি।',
  ARRAY['১ বাটি চিচিঙ্গা', 'তেল', 'মশলা'],
  ARRAY['চিচিঙ্গা কেটে নিন।','ভেজে রান্না করুন।'],
  '[
    {"icon":"water_drop","title":"হালকা","body":"পেটে চাপ কম দেয়।"}
  ]'::jsonb,
  ARRAY[]::text[],
  null),
('v_kolmi', 15, 'easy',
 'কলমি শাক — আয়রন ও ফাইবারে সমৃদ্ধ।',
  ARRAY['১ বাটি কলমি শাক', 'তেল', 'মশলা'],
  ARRAY['শাক কুচি করে ভাজুন।'],
  '[
    {"icon":"favorite","title":"আয়রন","body":"রক্তস্বল্পতা রোধ।"}
  ]'::jsonb,
  ARRAY[]::text[],
  null),
('v_kochu_shak', 15, 'easy',
 'কচু শাক — ফাইবার ও ভিটামিন K সমৃদ্ধ।',
  ARRAY['১ বাটি কচু শাক', 'তেল', 'মশলা'],
  ARRAY['শাক কেটে রান্না করুন।'],
  '[
    {"icon":"eco","title":"ফাইবার","body":"হজম ভালো করে।"}
  ]'::jsonb,
  ARRAY['কচু শাক কিছু মানুষের গলায় চুলকানি করে — ভালো করে সেদ্ধ করুন।','কিডনি রোগী অল্প পরিমাণে খান।'],
  null),
('v_kancha_morich', 10, 'easy',
 'কাঁচা মরিচসহ সবজি — ক্যাপসাইসিন থাকায় বিপাক বাড়ায়।',
  ARRAY['যেকোনো সবজি', '১-২টি কাঁচা মরিচ'],
  ARRAY['সবজি কেটে ভাজুন।','শেষে কাঁচা মরিচ কুচি দিন।'],
  '[
    {"icon":"local_fire_department","title":"বিপাক","body":"ক্যাপসাইসিন চর্বি পোড়ায়।"}
  ]'::jsonb,
  ARRAY['গ্যাস্ট্রাইটিস থাকলে কম খান।'],
  null)
on conflict (food_id) do nothing;


-- ---- dal ----
insert into public.food_details
  (food_id, prep_time_min, difficulty, why_eat_this_bn, ingredients_bn, steps_bn, benefits, cautions_bn, serving_tip_bn) values
('d_moshur', 25, 'easy',
 'মসুর ডাল — উদ্ভিজ্জ প্রোটিন, আয়রন ও ফলেটের সস্তা উৎস।',
  ARRAY['আধা বাটি মসুর ডাল', 'পেঁয়াজ', 'মশলা'],
  ARRAY['ডাল সেদ্ধ করুন।','ফোড়ন দিন।'],
  '[
    {"icon":"bolt","title":"প্রোটিন","body":"উদ্ভিজ্জ প্রোটিন পাওয়া যায়।"},
    {"icon":"favorite","title":"আয়রন","body":"রক্তস্বল্পতা রোধ।"}
  ]'::jsonb,
  ARRAY['কিডনি রোগী অল্প পরিমাণে খান।'],
  'ভাতের সাথে।'),
('d_mug', 25, 'medium',
 'মুগ ডাল — হালকা ও সহজপাচ্য, প্রোটিনে সমৃদ্ধ।',
  ARRAY['আধা বাটি মুগ ডাল', 'পেঁয়াজ', 'মশলা'],
  ARRAY['ডাল সেদ্ধ করুন।','ফোড়ন দিন।'],
  '[
    {"icon":"schedule","title":"হালকা","body":"সহজপাচ্য।"}
  ]'::jsonb,
  ARRAY['কিডনি রোগী অল্প পরিমাণে খান।'],
  null),
('d_rola', 30, 'medium',
 'ছোলার ডাল — প্রোটিন ও আঁশে সমৃদ্ধ।',
  ARRAY['আধা বাটি ছোলা', 'মশলা'],
  ARRAY['ভিজিয়ে সেদ্ধ করুন।','ফোড়ন দিন।'],
  '[
    {"icon":"bolt","title":"প্রোটিন ও আঁশ","body":"দীর্ঘক্ষণ পেট ভরা রাখে।"}
  ]'::jsonb,
  ARRAY['কিডনি রোগী অল্প পরিমাণে খান।'],
  null)
on conflict (food_id) do nothing;


-- ---- snacks ----
insert into public.food_details
  (food_id, prep_time_min, difficulty, why_eat_this_bn, ingredients_bn, steps_bn, benefits, cautions_bn, serving_tip_bn) values
('s_peyara', 2, 'easy',
 'পেয়ারা — ভিটামিন C-তে অসাধারণ সমৃদ্ধ, গ্লাইসেমিক ইনডেক্স কম। ডায়াবেটিস-বান্ধব ফল।',
  ARRAY['১টি মাঝারি পেয়ারা'],
  ARRAY['ধুয়ে কেটে খান।'],
  '[
    {"icon":"visibility","title":"ভিটামিন C","body":"রোগ প্রতিরোধ ক্ষমতা বাড়ায়।"},
    {"icon":"water_drop","title":"কম গ্লাইসেমিক","body":"গ্লুকোজ ধীরে বাড়ায়।"}
  ]'::jsonb,
  ARRAY['কিডনি রোগী পটাসিয়ামের কারণে পরিমিত খান।'],
  'খোসাসহ খান — আঁশ বেশি।'),
('s_papaya', 2, 'easy',
 'পেঁপে — ভিটামিন A ও C সমৃদ্ধ, হজমে সাহায্য করে।',
  ARRAY['১ কাপ পেঁপে কুচি'],
  ARRAY['কেটে বীজ বাদ দিন।'],
  '[
    {"icon":"schedule","title":"হজমে সহায়ক","body":"পেপেন এনজাইম হজমে সাহায্য করে।"},
    {"icon":"visibility","title":"ভিটামিন A","body":"চোখের জন্য উপকারী।"}
  ]'::jsonb,
  ARRAY[]::text[],
  'দুপুরের পর খান।'),
('s_am', 2, 'easy',
 'আম — ভিটামিন A ও C সমৃদ্ধ, কিন্তু গ্লাইসেমিক ইনডেক্স মাঝারি। পরিমিত পরিমাণে খান।',
  ARRAY['~১০০ গ্রাম আম কুচি'],
  ARRAY['কেটে খান।'],
  '[
    {"icon":"visibility","title":"ভিটামিন A","body":"চোখ ও ত্বকের জন্য।"}
  ]'::jsonb,
  ARRAY['গ্লুকোজ মাঝারি বাড়ায় — বেশি খাবেন না।'],
  'একমুঠোর বেশি না।'),
('s_jambura', 2, 'easy',
 'বাতাবি লেবু — ভিটামিন C সমৃদ্ধ, ক্যালোরি প্রায় শূন্য।',
  ARRAY['২-৩ কোয়া বাতাবি লেবু'],
  ARRAY['কেটে খান বা রস বের করে পানিতে মিশিয়ে খান।'],
  '[
    {"icon":"local_drink","title":"ভিটামিন C","body":"রোগ প্রতিরোধ ক্ষমতা বাড়ায়।"}
  ]'::jsonb,
  ARRAY['কিডনি রোগী অল্প পরিমাণে খান।'],
  'পানিতে মিশিয়ে খান।'),
('s_dalim', 2, 'easy',
 'ডালিম — অ্যান্টিঅক্সিডেন্ট ও ভিটামিন C সমৃদ্ধ।',
  ARRAY['আধা কাপ ডালিম বীজ'],
  ARRAY['বীজ ছাড়িয়ে খান।'],
  '[
    {"icon":"favorite","title":"অ্যান্টিঅক্সিডেন্ট","body":"হৃদযন্ত্রের জন্য উপকারী।"}
  ]'::jsonb,
  ARRAY[]::text[],
  null)
on conflict (food_id) do nothing;
