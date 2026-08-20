-- ============================================================
-- Amar Diet — Clinical Rules Reference + Food Exclusion Rules
-- ============================================================
-- Sources:
--   * ADA Standards of Care in Diabetes — 2024
--   * KDIGO 2024 Clinical Practice Guideline for Diabetes & CKD
--   * ACC/AHA 2017 Guideline for High Blood Pressure
--   * WHO South-East Asia dietary targets (overweight BMI ≥ 23)
--   * ICMR 2024 Dietary Guidelines for Indians
--   * DASH (Dietary Approaches to Stop Hypertension) 2024
-- All thresholds are explicit — do NOT change without a clinical review.
-- ============================================================


-- ---------- 1. RULES REFERENCE TABLE ----------
create table if not exists public.clinical_rules (
  id           serial primary key,
  condition    text not null,           -- diabetes | hypertension | ckd | heart | anemia | obesity | underweight
  parameter    text not null,           -- hba1c | fasting_glucose | systolic_bp | bmi | potassium_mg | sodium_mg | fat_g | carb_g | protein_g
  comparator   text not null,           -- lt | lte | gt | gte | between
  threshold    numeric,
  threshold_hi numeric,                 -- for comparator = 'between'
  action       text not null,           -- classify_good | classify_moderate | classify_poor | restrict_high_k | restrict_high_phos | restrict_high_sodium | restrict_high_fat | allow_only_low_gi | prioritize_iron
  source       text not null,           -- ADA 2024 | KDIGO 2024 | ACC/AHA 2017 | WHO SEAR | ICMR 2024 | DASH 2024
  notes_bn     text,                    -- Bengali clinical note
  created_at   timestamptz not null default now()
);

-- Read-only for authenticated users; reference data.
alter table public.clinical_rules enable row level security;
drop policy if exists cr_read on public.clinical_rules;
create policy cr_read on public.clinical_rules for select to authenticated using (true);


-- ---------- 2. SEED RULES ----------
insert into public.clinical_rules (condition, parameter, comparator, threshold, threshold_hi, action, source, notes_bn) values
-- Glucose control (ADA 2024)
('diabetes', 'hba1c',           'lt',  7.0, null, 'classify_good',    'ADA 2024', 'HbA1c ৭%-এর কম হলে গ্লুকোজ নিয়ন্ত্রণ ভালো'),
('diabetes', 'hba1c',           'between', 7.0, 8.5, 'classify_moderate', 'ADA 2024', 'HbA1c ৭-৮.৫% মাঝারি নিয়ন্ত্রণ'),
('diabetes', 'hba1c',           'gt',  8.5, null, 'classify_poor',     'ADA 2024', 'HbA1c ৮.৫%-এর বেশি হলে নিয়ন্ত্রণ দুর্বল — কঠোর কার্ব সীমা'),
('diabetes', 'fasting_glucose', 'lt',  7.0, null, 'classify_good',    'ADA 2024', 'খালি পেটে গ্লুকোজ ৭ mmol/L-এর কম'),
('diabetes', 'fasting_glucose', 'between', 7.0, 10.0, 'classify_moderate', 'ADA 2024', 'খালি পেটে গ্লুকোজ ৭-১০ mmol/L'),
('diabetes', 'fasting_glucose', 'gt',  10.0, null, 'classify_poor',    'ADA 2024', 'খালি পেটে গ্লুকোজ ১০ mmol/L-এর বেশি'),

-- Blood pressure (ACC/AHA 2017)
('hypertension', 'systolic_bp',  'lt',  120, null, 'classify_normal',   'ACC/AHA 2017', 'স্বাভাবিক রক্তচাপ'),
('hypertension', 'systolic_bp',  'between', 120, 130, 'classify_elevated', 'ACC/AHA 2017', 'উচ্চ-স্বাভাবিক (Elevated)'),
('hypertension', 'systolic_bp',  'between', 130, 140, 'classify_stage1',  'ACC/AHA 2017', 'হাইপারটেনশন পর্যায় ১ — সোডিয়াম সীমিত করুন'),
('hypertension', 'systolic_bp',  'gte', 140, null, 'classify_stage2',   'ACC/AHA 2017', 'হাইপারটেনশন পর্যায় ২ — কঠোর সোডিয়াম সীমা'),

-- BMI (WHO South-East Asia / Asian cutoffs)
('obesity', 'bmi', 'lt',    18.5, null, 'underweight', 'WHO SEAR', 'এশীয় কাটঅফ অনুযায়ী কম ওজন'),
('obesity', 'bmi', 'between', 18.5, 23, 'normal', 'WHO SEAR', 'এশীয় কাটঅফ অনুযায়ী স্বাভাবিক'),
('obesity', 'bmi', 'between', 23, 25, 'overweight', 'WHO SEAR', 'এশীয় কাটঅফ অনুযায়ী অতিরিক্ত ওজন'),
('obesity', 'bmi', 'gte',    25,    null, 'obese', 'WHO SEAR', 'এশীয় কাটঅফ অনুযায়ী স্থূলতা — কার্ব সীমা কঠোর করুন'),

-- CKD (KDIGO 2024)
('ckd', 'potassium_mg',  'gt', 200, null, 'restrict_high_k',   'KDIGO 2024', 'কিডনি রোগে পটাশিয়াম ২০০ মিগ্রা-এর বেশি একবেলায় সীমিত'),
('ckd', 'phosphorus_mg', 'gt', 150, null, 'restrict_high_phos', 'KDIGO 2024', 'কিডনি রোগে ফসফরাস ১৫০ মিগ্রা-এর বেশি একবেলায় সীমিত'),
('ckd', 'protein_g',     'gt', 25,  null, 'restrict_high_protein', 'KDIGO 2024', 'কিডনি রোগে প্রোটিন প্রতি বেলায় ২৫ গ্রামের বেশি নয় (stage 3-5)'),

-- Heart disease (DASH/AHA)
('heart', 'fat_g',   'gt', 12, null, 'restrict_high_fat', 'AHA 2024', 'হৃদরোগে প্রতি বেলায় চর্বি ১২ গ্রামের কম'),
('heart', 'sodium_mg', 'gt', 200, null, 'restrict_high_sodium', 'DASH 2024', 'হৃদরোগে একবেলায় সোডিয়াম ২০০ মিগ্রা-এর বেশি সীমিত'),

-- Anemia
('anemia', 'iron', 'always', null, null, 'prioritize_iron', 'ICMR 2024', 'রক্তস্বল্পতায় আয়রন-সমৃদ্ধ খাবার (শিং, কলিজা, ডিম, কচু শাক) প্রাধান্য দিন'),

-- Daily macro targets (ADA + ICMR)
('diabetes', 'max_carb_per_meal_g', 'good',     45, null, 'carb_cap', 'ADA 2024', 'ভালো নিয়ন্ত্রণে একবেলায় সর্বোচ্চ ৪৫ গ্রাম কার্ব'),
('diabetes', 'max_carb_per_meal_g', 'moderate', 35, null, 'carb_cap', 'ADA 2024', 'মাঝারি নিয়ন্ত্রণে একবেলায় সর্বোচ্চ ৩৫ গ্রাম কার্ব'),
('diabetes', 'max_carb_per_meal_g', 'poor',     25, null, 'carb_cap', 'ADA 2024', 'দুর্বল নিয়ন্ত্রণে একবেলায় সর্বোচ্চ ২৫ গ্রাম কার্ব');

-- Index for fast condition lookups
create index if not exists cr_condition_idx on public.clinical_rules (condition, parameter);


-- ---------- 3. FOOD EXCLUSION RULES ----------
-- Maps user conditions to food tags/categories that should be EXCLUDED.
create table if not exists public.food_exclusion_rules (
  id           serial primary key,
  condition    text not null,           -- ckd | hypertension | heart | diabetes_poor | pregnancy (reserved)
  tag          text not null,           -- food tag to exclude (fk to foods.tags)
  severity     text not null default 'strict', -- strict | moderate | advisory
  reason_bn    text not null,
  source       text not null,
  created_at   timestamptz not null default now()
);

alter table public.food_exclusion_rules enable row level security;
drop policy if exists fer_read on public.food_exclusion_rules;
create policy fer_read on public.food_exclusion_rules for select to authenticated using (true);

create index if not exists fer_condition_idx on public.food_exclusion_rules (condition);


-- ---------- 4. SEED EXCLUSIONS ----------
insert into public.food_exclusion_rules (condition, tag, severity, reason_bn, source) values
-- CKD (KDIGO 2024) — exclude high potassium + high phosphorus tags
('ckd', 'high_potassium',  'strict',   'কিডনি রোগে পটাশিয়াম-সমৃদ্ধ খাবার (কলা, আলু, টমেটো, কমলা) সীমিত করুন — KDIGO 2024 অনুযায়ী', 'KDIGO 2024'),
('ckd', 'high_phosphorus', 'strict',   'কিডনি রোগে ফসফরাস-সমৃদ্ধ খাবার (দুধ, ডিমের কুসুম, কলিজা, বাদাম) সীমিত করুন — KDIGO 2024 অনুযায়ী', 'KDIGO 2024'),
('ckd', 'high_sodium',     'strict',   'কিডনি রোগে সোডিয়াম সীমিত করুন — প্রক্রিয়াজাত খাবার এড়িয়ে চলুন', 'KDIGO 2024'),

-- Hypertension (DASH 2024)
('hypertension', 'high_sodium', 'strict',   'উচ্চ রক্তচাপে সোডিয়াম সীমিত করুন — লবণাক্ত ও প্রক্রিয়াজাত খাবার এড়িয়ে চলুন', 'DASH 2024'),
('hypertension', 'high_saturated_fat', 'moderate', 'উচ্চ রক্তচাপে সম্পৃক্ত চর্বি সীমিত করুন', 'DASH 2024'),

-- Heart disease (AHA 2024)
('heart', 'high_saturated_fat', 'strict',   'হৃদরোগে সম্পৃক্ত চর্বি এড়িয়ে চলুন (ঘি, মাখন, চর্বিযুক্ত মাংস)', 'AHA 2024'),
('heart', 'high_cholesterol',   'strict',   'হৃদরোগে কোলেস্টেরল-সমৃদ্ধ খাবার (কলিজা, ডিমের কুসুম) সীমিত করুন', 'AHA 2024'),
('heart', 'high_sodium',        'strict',   'হৃদরোগে সোডিয়াম সীমিত করুন', 'AHA 2024'),
('heart', 'trans_fat',          'strict',   'হৃদরোগে ট্রান্স-ফ্যাট একেবারে এড়িয়ে চলুন (ভাজাপোড়া, প্যাকেটজাত)', 'AHA 2024'),

-- Poor glucose control — exclude high GI
('diabetes_poor', 'high_gi', 'strict', 'গ্লুকোজ দুর্বল নিয়ন্ত্রণে উচ্চ-জিআই খাবার (সাদা ভাত, আলু, চিনি) এড়িয়ে চলুন', 'ADA 2024'),

-- No_beef preference
('no_beef', 'beef', 'strict', 'ব্যক্তিগত পছন্দ — গরুর মাংস বাদ দেওয়া হয়েছে', 'user_preference'),

-- Vegetarian preference
('vegetarian', 'meat', 'strict',  'ব্যক্তিগত পছন্দ — মাংস বাদ দেওয়া হয়েছে', 'user_preference'),
('vegetarian', 'fish', 'moderate', 'ব্যক্তিগত পছন্দ — মাছ সীমিত (ডিম ও দুধ গ্রহণযোগ্য)', 'user_preference'),

-- Fish-only preference
('fish_only', 'meat', 'strict',  'ব্যক্তিগত পছন্দ — শুধু মাছ ও শাকসবজি গ্রহণযোগ্য', 'user_preference'),
('fish_only', 'beef', 'strict',  'ব্যক্তিগত পছন্দ — গরুর মাংস বাদ', 'user_preference');


-- ---------- 5. RECOMMENDATION TABLE (Bengali clinical nudges) ----------
-- Per condition, the system emits one Bengali recommendation string.
create table if not exists public.clinical_recommendations_bn (
  id           serial primary key,
  condition    text not null,
  recommendation_bn text not null,
  source       text not null,
  priority     int not null default 5   -- 1=highest, 10=lowest
);

alter table public.clinical_recommendations_bn enable row level security;
drop policy if exists crb_read on public.clinical_recommendations_bn;
create policy crb_read on public.clinical_recommendations_bn for select to authenticated using (true);

insert into public.clinical_recommendations_bn (condition, recommendation_bn, source, priority) values
('diabetes_poor',        'প্রতি বেলায় কার্ব ২৫ গ্রামের বেশি খাবেন না — ভাতের বদলে রুটি বা ওটস বেছে নিন', 'ADA 2024', 1),
('diabetes_moderate',    'প্রতি বেলায় কার্ব ৩৫ গ্রামের মধ্যে রাখুন — সবজি ও ডালের পরিমাণ বাড়ান', 'ADA 2024', 2),
('diabetes_good',        'ভালো নিয়ন্ত্রণ বজায় রাখতে প্রতি বেলায় সর্বোচ্চ ৪৫ গ্রাম কার্ব রাখুন', 'ADA 2024', 3),
('hypertension',         'একদিনে সোডিয়াম ১৫০০ মিগ্রা-এর বেশি নয় — লবণ, আচার, চিপস এড়িয়ে চলুন', 'DASH 2024', 2),
('ckd',                  'একবেলায় পটাশিয়াম ২০০ মিগ্রা ও ফসফরাস ১৫০ মিগ্রার বেশি নয় — KDIGO 2024', 'KDIGO 2024', 1),
('ckd',                  'ডাক্তারের পরামর্শ অনুযায়ী প্রোটিন সীমিত করুন (০.৮ গ্রাম/কেজি)', 'KDIGO 2024', 2),
('heart',                'সম্পৃক্ত চর্বি ৭%-এর কম রাখুন — ঘি/মাখনের বদলে সরিষার তেল ব্যবহার করুন', 'AHA 2024', 1),
('heart',                'একদিনে সোডিয়াম ১৫০০ মিগ্রা-এর বেশি নয়', 'DASH 2024', 2),
('anemia',               'আয়রন-সমৃদ্ধ খাবার (শিং, কলিজা, ডিম, কচু শাক) প্রতিদিন খান — ভিটামিন C যোগ করুন (লেবু, পেয়ারা)', 'ICMR 2024', 2),
('on_insulin',           'ইনসুলিনের সাথে খাবারের সময় ধারাবাহিক রাখুন — কোনো বেলা বাদ দেবেন না', 'ADA 2024', 1),
('obese',                'প্রতিদিন ৫০০ কিলোক্যালরি ঘাটতি তৈরি করুন — শাকসবজি ও লেবু পানি বাড়ান', 'ADA 2024', 2),
('underweight',          'ঘন ঘন ছোট ছোট খাবার খান — ডাল, ডিম, কলা, খেজুর যোগ করুন', 'ICMR 2024', 3),
('elderly',              'প্রতিদিন ন্যূনতম ২ লিটার পানি পান করুন — প্রস্রাবের রং হালকা হলুদ রাখুন', 'ICMR 2024', 4);


-- ============================================================
-- ✓ Done. Run this in Supabase SQL Editor.
-- ============================================================
