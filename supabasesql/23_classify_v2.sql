-- ============================================================
-- Amar Diet — classify_user_v2 (full clinical classifier)
-- ============================================================
-- Replaces the legacy public.classify_user().
-- Returns a richer JSON that includes daily macro targets, allowed
-- food tags, restricted tags, and Bengali clinical recommendations.
-- Sources locked to published guidelines — see 22_clinical_rules.sql.
-- ============================================================


-- ---------- 1. CLASSIFICATION (V2) ----------
create or replace function public.classify_user_v2(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  p public.user_profiles;
  glucose_tier text;
  bmi_tier text;
  bp_tier text;
  ckd_stage text;
  ckd_grade int;                       -- 0..5

  -- Daily macro targets (ADA 2024 + ICMR 2024)
  daily_carb_target_g    numeric := 180; -- default adult
  daily_protein_target_g numeric := 60;  -- 1.0 g/kg
  daily_fat_target_g     numeric := 60;
  daily_sodium_cap_mg    numeric := 2300;
  max_carb_per_meal      numeric := 45;
  daily_kcal_target      numeric := 1800;

  -- Dietary restrictions (tags to exclude)
  allowed_gi            text[] := array['low','medium'];
  allowed_tags          text[] := '{}';
  restricted_tags       text[] := '{}';
  restriction_flags     text[] := '{}';
  warnings              text[] := '{}';
  recommendations_bn    text[] := '{}';
  food_preference_text  text;
  conditions_summary    jsonb;
begin
  select * into p from public.user_profiles where user_id = p_user_id;
  if not found then
    raise exception 'No profile found for user %', p_user_id;
  end if;

  food_preference_text := coalesce(p.food_preference, 'omnivore');

  -- ---------- 1.1 GLUCOSE TIER (ADA 2024) ----------
  if p.hba1c_percent is not null then
    if p.hba1c_percent < 7.0          then glucose_tier := 'good';
    elsif p.hba1c_percent <= 8.5      then glucose_tier := 'moderate';
    else                                   glucose_tier := 'poor';
    end if;
  elsif p.fasting_glucose_mmol is not null then
    if p.fasting_glucose_mmol < 7.0     then glucose_tier := 'good';
    elsif p.fasting_glucose_mmol <= 10.0 then glucose_tier := 'moderate';
    else                                      glucose_tier := 'poor';
    end if;
  else
    glucose_tier := 'unknown';
    warnings := array_append(warnings, 'গ্লুকোজ বা HbA1c তথ্য দেওয়া হয়নি — সাধারণ মধ্যম-কার্ব পরিকল্পনা দেখানো হচ্ছে');
  end if;

  -- ---------- 1.2 BMI TIER (WHO SEAR Asian cutoffs) ----------
  if p.bmi < 18.5 then bmi_tier := 'underweight';
  elsif p.bmi < 23 then bmi_tier := 'normal';
  elsif p.bmi < 25 then bmi_tier := 'overweight';
  else bmi_tier := 'obese';
  end if;

  -- ---------- 1.3 BP TIER (ACC/AHA 2017) ----------
  if p.systolic_bp is not null and p.diastolic_bp is not null then
    if p.systolic_bp >= 140 or p.diastolic_bp >= 90 then
      bp_tier := 'stage2';
    elsif p.systolic_bp >= 130 or p.diastolic_bp >= 80 then
      bp_tier := 'stage1';
    elsif p.systolic_bp >= 120 then
      bp_tier := 'elevated';
    else
      bp_tier := 'normal';
    end if;
  else
    bp_tier := 'unknown';
  end if;

  -- ---------- 1.4 CKD (KDIGO 2024) ----------
  if p.has_ckd then
    ckd_stage := case
      when p.ckd_stage between 1 and 2 then 'stage1_2'
      when p.ckd_stage = 3 then 'stage3'
      when p.ckd_stage = 4 then 'stage4'
      when p.ckd_stage = 5 then 'stage5'
      else 'stage3'  -- default conservative
    end;
    ckd_grade := greatest(1, least(5, coalesce(p.ckd_stage, 3)));
    restriction_flags := array_append(restriction_flags, 'ckd_restricted_high_k');
    restriction_flags := array_append(restriction_flags, 'ckd_restricted_high_phos');
    restricted_tags := array_cat(restricted_tags, array['high_potassium','high_phosphorus','high_sodium']);
    warnings := array_append(warnings,
      'কিডনি রোগের কারণে পটাশিয়াম ও ফসফরাসযুক্ত খাবার সীমিত করা হয়েছে — নেফ্রোলজিস্টের পরামর্শ অনুসরণ করুন (KDIGO 2024)');
    -- Reduce protein target for advanced CKD
    if ckd_grade >= 3 then
      daily_protein_target_g := 0.8 * coalesce(p.weight_kg, 60);
      restriction_flags := array_append(restriction_flags, 'ckd_protein_limited');
    end if;
  else
    ckd_stage := 'none';
    ckd_grade := 0;
  end if;

  -- ---------- 1.5 HEART DISEASE (AHA 2024) ----------
  if p.has_heart_disease then
    restriction_flags := array_append(restriction_flags, 'heart_moderate_restricted');
    restricted_tags := array_cat(restricted_tags, array['high_saturated_fat','trans_fat','high_cholesterol','high_sodium']);
    warnings := array_append(warnings, 'হৃদরোগের কারণে সম্পৃক্ত চর্বি, কোলেস্টেরল ও সোডিয়াম সীমিত করা হয়েছে (AHA 2024)');
  end if;

  -- ---------- 1.6 HYPERTENSION (DASH 2024) ----------
  if bp_tier in ('stage1','stage2') then
    restriction_flags := array_append(restriction_flags, 'low_sodium_required');
    restricted_tags := array_cat(restricted_tags, array['high_sodium']);
    daily_sodium_cap_mg := 1500;
    warnings := array_append(warnings, 'উচ্চ রক্তচাপের কারণে সোডিয়াম দৈনিক ১৫০০ মিগ্রায় সীমিত করা হয়েছে (DASH 2024)');
  end if;

  -- ---------- 1.7 INSULIN ----------
  if p.on_insulin then
    warnings := array_append(warnings,
      'আপনি ইনসুলিন গ্রহণ করছেন — খাবারের সময় ও পরিমাণ ধারাবাহিক রাখা জরুরি। কোনো বেলা বাদ দেওয়ার আগে ডাক্তারের পরামর্শ নিন।');
    recommendations_bn := array_append(recommendations_bn,
      'ইনসুলিনের সাথে খাবারের সময় ধারাবাহিক রাখুন — কোনো বেলা বাদ দেবেন না');
  end if;

  -- ---------- 1.8 ANEMIA (ICMR 2024) ----------
  if p.has_anemia then
    warnings := array_append(warnings, 'রক্তস্বল্পতা থাকায় আয়রন সমৃদ্ধ খাবার (শিং মাছ, কচু শাক, ডিম) অগ্রাধিকার দেওয়া হচ্ছে');
    allowed_tags := array_cat(allowed_tags, array['iron_rich']);
    restriction_flags := array_append(restriction_flags, 'prioritize_iron');
  end if;

  -- ---------- 1.9 GLUCOSE TIER → MACRO TARGETS (ADA 2024) ----------
  max_carb_per_meal := case glucose_tier
    when 'good'     then 45
    when 'moderate' then 35
    when 'poor'     then 25
    else                 35
  end;
  if p.meal_size_pref = 'small' then max_carb_per_meal := max_carb_per_meal - 5; end if;
  if p.meal_size_pref = 'large' then max_carb_per_meal := max_carb_per_meal + 5; end if;

  allowed_gi := case glucose_tier
    when 'poor' then array['low']
    else             array['low','medium']
  end;

  -- Daily targets
  if glucose_tier = 'poor' then
    daily_carb_target_g := 130;  -- ADA: minimum for hypoglycemia prevention
    daily_kcal_target   := 1600;
  elsif glucose_tier = 'moderate' then
    daily_carb_target_g := 160;
    daily_kcal_target   := 1800;
  elsif glucose_tier = 'good' then
    daily_carb_target_g := 200;
    daily_kcal_target   := 2000;
  end if;

  -- BMI adjustments
  if bmi_tier = 'obese' then
    daily_kcal_target   := daily_kcal_target - 300;
    daily_carb_target_g := daily_carb_target_g - 30;
    recommendations_bn := array_append(recommendations_bn,
      'প্রতিদিন ৫০০ কিলোক্যালরি ঘাটতি তৈরি করুন — শাকসবজি ও লেবু পানি বাড়ান');
  elsif bmi_tier = 'underweight' then
    daily_kcal_target   := daily_kcal_target + 300;
    daily_carb_target_g := daily_carb_target_g + 30;
    recommendations_bn := array_append(recommendations_bn,
      'ঘন ঘন ছোট ছোট খাবার খান — ডাল, ডিম, কলা, খেজুর যোগ করুন');
  end if;

  -- CKD stage 4-5 further carb/fluid restriction
  if ckd_grade >= 4 then
    daily_protein_target_g := 0.6 * coalesce(p.weight_kg, 60);
    max_carb_per_meal := least(max_carb_per_meal, 30);
  end if;

  -- Protein target as 1 g/kg adjusted
  if ckd_grade = 0 and p.weight_kg is not null then
    daily_protein_target_g := round(p.weight_kg * 0.9)::numeric;
  end if;

  -- Fat target — 25-30% of kcal, 9 kcal/g
  daily_fat_target_g := round((daily_kcal_target * 0.27) / 9)::numeric;

  -- ---------- 1.10 PREFERENCE EXCLUSIONS ----------
  case food_preference_text
    when 'vegetarian' then
      restricted_tags := array_cat(restricted_tags, array['meat','fish']);
    when 'fish_only' then
      restricted_tags := array_cat(restricted_tags, array['meat','beef','chicken','duck']);
    when 'no_beef' then
      restricted_tags := array_cat(restricted_tags, array['beef']);
    else
      -- omnivore: nothing excluded
      null;
  end case;

  -- ---------- 1.11 BUILD RECOMMENDATIONS ----------
  if glucose_tier = 'poor' then
    recommendations_bn := array_append(recommendations_bn,
      'প্রতি বেলায় কার্ব ২৫ গ্রামের বেশি খাবেন না — ভাতের বদলে রুটি বা ওটস বেছে নিন');
  elsif glucose_tier = 'moderate' then
    recommendations_bn := array_append(recommendations_bn,
      'প্রতি বেলায় কার্ব ৩৫ গ্রামের মধ্যে রাখুন — সবজি ও ডালের পরিমাণ বাড়ান');
  elsif glucose_tier = 'good' then
    recommendations_bn := array_append(recommendations_bn,
      'ভালো নিয়ন্ত্রণ বজায় রাখতে প্রতি বেলায় সর্বোচ্চ ৪৫ গ্রাম কার্ব রাখুন');
  end if;

  if bp_tier in ('stage1','stage2') then
    recommendations_bn := array_append(recommendations_bn,
      'একদিনে সোডিয়াম ১৫০০ মিগ্রা-এর বেশি নয় — লবণ, আচার, চিপস এড়িয়ে চলুন');
  end if;
  if p.has_ckd then
    recommendations_bn := array_append(recommendations_bn,
      'একবেলায় পটাশিয়াম ২০০ মিগ্রা ও ফসফরাস ১৫০ মিগ্রার বেশি নয়');
  end if;
  if p.has_heart_disease then
    recommendations_bn := array_append(recommendations_bn,
      'সম্পৃক্ত চর্বি ৭%-এর কম রাখুন — ঘি/মাখনের বদলে সরিষার তেল');
  end if;
  if p.age is not null and p.age >= 60 then
    recommendations_bn := array_append(recommendations_bn,
      'প্রতিদিন ন্যূনতম ২ লিটার পানি পান করুন — প্রস্রাবের রং হালকা হলুদ রাখুন');
  end if;

  -- ---------- 1.12 CONDITIONS SUMMARY ----------
  conditions_summary := jsonb_build_object(
    'has_diabetes',      true,
    'has_ckd',           p.has_ckd,
    'ckd_stage',         ckd_stage,
    'ckd_grade',         ckd_grade,
    'has_heart_disease', p.has_heart_disease,
    'has_hypertension',  bp_tier in ('stage1','stage2'),
    'has_anemia',        p.has_anemia,
    'on_insulin',        p.on_insulin,
    'is_obese',          bmi_tier = 'obese',
    'is_underweight',    bmi_tier = 'underweight',
    'is_elderly',        p.age is not null and p.age >= 60,
    'food_preference',   food_preference_text
  );

  -- ---------- 1.13 RETURN ----------
  return jsonb_build_object(
    'glucose_tier',            glucose_tier,
    'bmi_tier',                bmi_tier,
    'bp_tier',                 bp_tier,
    'ckd_stage',               ckd_stage,
    'food_preference',         food_preference_text,
    'max_carb_per_meal',       max_carb_per_meal,
    'daily_carb_target_g',     daily_carb_target_g,
    'daily_protein_target_g',  daily_protein_target_g,
    'daily_fat_target_g',      daily_fat_target_g,
    'daily_kcal_target',       daily_kcal_target,
    'daily_sodium_cap_mg',     daily_sodium_cap_mg,
    'allowed_gi',              to_jsonb(allowed_gi),
    'allowed_tags',            to_jsonb(allowed_tags),
    'restricted_tags',         to_jsonb(restricted_tags),
    'restriction_flags',       to_jsonb(restriction_flags),
    'warnings',                to_jsonb(warnings),
    'recommendations_bn',      to_jsonb(recommendations_bn),
    'conditions',              conditions_summary
  );
end;
$$;


-- ---------- 2. LEGACY CLASSIFY (backward-compatible shim) ----------
-- Keeps the old classify_user() returning the v1 fields, but derived
-- from the v2 logic so the existing Flutter code keeps working.
create or replace function public.classify_user(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v2 jsonb;
  out jsonb;
begin
  v2 := public.classify_user_v2(p_user_id);
  out := jsonb_build_object(
    'glucose_tier',      v2->>'glucose_tier',
    'bmi_tier',          v2->>'bmi_tier',
    'bp_tier',           v2->>'bp_tier',
    'max_carb_per_meal', (v2->>'max_carb_per_meal')::numeric,
    'allowed_gi',        v2->'allowed_gi',
    'restriction_flags', v2->'restriction_flags',
    'warnings',          v2->'warnings',
    'food_preference',   v2->>'food_preference'
  );
  return out;
end;
$$;


-- ============================================================
-- ✓ Done. Run this in Supabase SQL Editor after 22_clinical_rules.sql.
-- ============================================================