/// Local mirror of the server's classify_user_v2 + get_daily_recommendation_v2.
///
/// Why: instant UI feedback (warnings, restricted-foods card, portion caps)
/// must not wait for a network round-trip. Keep this in sync with the SQL
/// in supabasesql/22_clinical_rules.sql + 23_classify_v2.sql +
/// 24_daily_recommendation_v2.sql. If you change a threshold on one side,
/// mirror it on the other.
///
/// All thresholds are taken from published guidelines (ADA 2024, KDIGO
/// 2024, ACC/AHA 2017, WHO SEAR Asian BMI, ICMR 2024, DASH 2024,
/// AHA 2024). A clinical reviewer should sign off before production.
library;

import '../models/meal_item.dart';
import '../models/user_profile.dart';
import 'impact_engine.dart' show Classification;

/// Source-cited thresholds used by the recommender.
class Guidelines {
  // ADA 2024 — HbA1c
  static const double a1cGood = 7.0;        // < 7.0% = good
  static const double a1cPoor = 8.5;        // > 8.5% = poor
  // ADA 2024 — Fasting glucose (mmol/L)
  static const double fgGood = 7.0;         // < 7.0
  static const double fgPoor = 10.0;        // > 10.0
  // ADA 2024 — Per-meal carb cap
  static const double carbGood = 45;        // g/meal
  static const double carbModerate = 35;
  static const double carbPoor = 25;

  // ACC/AHA 2017 — BP
  static const int bpElevated = 120;        // systolic
  static const int bpStage1 = 130;
  static const int bpStage2 = 140;
  static const int bpDStage1 = 80;          // diastolic
  static const int bpDStage2 = 90;

  // WHO SEAR Asian cutoffs — BMI
  static const double bmiUnderweight = 18.5;
  static const double bmiNormal = 23;
  static const double bmiOverweight = 25;

  // KDIGO 2024 — CKD per-meal caps
  static const double ckdPotassiumCapMg = 200;
  static const double ckdPhosphorusCapMg = 150;
  static const double ckdProteinCapG = 25;

  // AHA 2024 — Heart per-meal caps
  static const double heartFatCapG = 12;
  static const double heartSodiumCapMg = 200;

  // DASH 2024 — Hypertension per-meal sodium cap
  static const double htSodiumCapMg = 250;

  // Daily sodium cap
  static const double dailySodiumStandardMg = 2300;
  static const double dailySodiumRestrictedMg = 1500;
}

/// Full classification mirror of SQL classify_user_v2.
class DietClassification {
  final String glucoseTier;       // good | moderate | poor | unknown
  final String bmiTier;           // underweight | normal | overweight | obese
  final String bpTier;            // normal | elevated | stage1 | stage2 | unknown
  final String ckdStage;          // none | stage1_2 | stage3 | stage4 | stage5
  final int ckdGrade;
  final String foodPreference;    // omnivore | vegetarian | fish_only | no_beef

  final double maxCarbPerMeal;
  final double dailyCarbTargetG;
  final double dailyProteinTargetG;
  final double dailyFatTargetG;
  final double dailyKcalTarget;
  final double dailySodiumCapMg;

  final List<String> allowedGi;
  final List<String> allowedTags;
  final List<String> restrictedTags;
  final List<String> restrictionFlags;
  final List<String> warnings;
  final List<String> recommendationsBn;

  final UserConditions conditions;

  const DietClassification({
    required this.glucoseTier,
    required this.bmiTier,
    required this.bpTier,
    required this.ckdStage,
    required this.ckdGrade,
    required this.foodPreference,
    required this.maxCarbPerMeal,
    required this.dailyCarbTargetG,
    required this.dailyProteinTargetG,
    required this.dailyFatTargetG,
    required this.dailyKcalTarget,
    required this.dailySodiumCapMg,
    required this.allowedGi,
    required this.allowedTags,
    required this.restrictedTags,
    required this.restrictionFlags,
    required this.warnings,
    required this.recommendationsBn,
    required this.conditions,
  });

  /// Parses the JSON returned by the server `classify_user_v2` RPC.
  /// Tolerates missing fields by falling back to safe defaults.
  factory DietClassification.fromJson(Map<String, dynamic> j) {
    double _d(String k, double fb) =>
        j[k] is num ? (j[k] as num).toDouble() : fb;
    String _s(String k, String fb) {
      final v = j[k];
      return v is String && v.isNotEmpty ? v : fb;
    }
    List<String> _ls(String k) =>
        (j[k] as List?)?.cast<String>() ?? const <String>[];
    return DietClassification(
      glucoseTier: _s('glucose_tier', 'unknown'),
      bmiTier: _s('bmi_tier', 'unknown'),
      bpTier: _s('bp_tier', 'unknown'),
      ckdStage: _s('ckd_stage', 'none'),
      ckdGrade: (j['ckd_grade'] is num)
          ? (j['ckd_grade'] as num).toInt()
          : 0,
      foodPreference: _s('food_preference', 'omnivore'),
      maxCarbPerMeal: _d('max_carb_per_meal', 45),
      dailyCarbTargetG: _d('daily_carb_target_g', 0),
      dailyProteinTargetG: _d('daily_protein_target_g', 0),
      dailyFatTargetG: _d('daily_fat_target_g', 0),
      dailyKcalTarget: _d('daily_kcal_target', 0),
      dailySodiumCapMg: _d('daily_sodium_cap_mg', 0),
      allowedGi: _ls('allowed_gi'),
      allowedTags: _ls('allowed_tags'),
      restrictedTags: _ls('restricted_tags'),
      restrictionFlags: _ls('restriction_flags'),
      warnings: _ls('warnings'),
      recommendationsBn: _ls('recommendations_bn'),
      conditions: UserConditions.fromJson(
          (j['conditions'] as Map?)?.cast<String, dynamic>() ?? {}),
    );
  }
}

class UserConditions {
  final bool hasCkd;
  final bool hasHeartDisease;
  final bool hasHypertension;
  final bool hasAnemia;
  final bool onInsulin;
  final bool isObese;
  final bool isUnderweight;
  final bool isElderly;
  final String foodPreference;
  const UserConditions({
    required this.hasCkd,
    required this.hasHeartDisease,
    required this.hasHypertension,
    required this.hasAnemia,
    required this.onInsulin,
    required this.isObese,
    required this.isUnderweight,
    required this.isElderly,
    required this.foodPreference,
  });
  factory UserConditions.fromJson(Map<String, dynamic> j) {
    bool _b(String k) => j[k] == true;
    String _s(String k, String fb) {
      final v = j[k];
      return v is String && v.isNotEmpty ? v : fb;
    }
    return UserConditions(
      hasCkd: _b('has_ckd'),
      hasHeartDisease: _b('has_heart_disease'),
      hasHypertension: _b('has_hypertension'),
      hasAnemia: _b('has_anemia'),
      onInsulin: _b('on_insulin'),
      isObese: _b('is_obese'),
      isUnderweight: _b('is_underweight'),
      isElderly: _b('is_elderly'),
      foodPreference: _s('food_preference', 'omnivore'),
    );
  }
}

class DietRecommender {
  /// Mirror of `public.classify_user_v2` — keep thresholds in sync with SQL.
  static DietClassification classify(UserProfile p) {
    // ---------- GLUCOSE (ADA 2024) ----------
    String glucoseTier;
    if (p.hba1cPercent != null) {
      final a = p.hba1cPercent!;
      glucoseTier = a < Guidelines.a1cGood
          ? 'good'
          : (a <= Guidelines.a1cPoor ? 'moderate' : 'poor');
    } else if (p.fastingGlucoseMmol != null) {
      final fg = p.fastingGlucoseMmol!;
      glucoseTier = fg < Guidelines.fgGood
          ? 'good'
          : (fg <= Guidelines.fgPoor ? 'moderate' : 'poor');
    } else {
      glucoseTier = 'unknown';
    }

    // ---------- BMI (WHO SEAR Asian) ----------
    final bmi = p.bmi;
    final bmiTier = bmi < Guidelines.bmiUnderweight
        ? 'underweight'
        : (bmi < Guidelines.bmiNormal
            ? 'normal'
            : (bmi < Guidelines.bmiOverweight ? 'overweight' : 'obese'));

    // ---------- BP (ACC/AHA 2017) ----------
    String bpTier = 'unknown';
    if (p.systolicBp != null && p.diastolicBp != null) {
      final s = p.systolicBp!;
      final d = p.diastolicBp!;
      if (s >= Guidelines.bpStage2 || d >= Guidelines.bpDStage2) {
        bpTier = 'stage2';
      } else if (s >= Guidelines.bpStage1 || d >= Guidelines.bpDStage1) {
        bpTier = 'stage1';
      } else if (s >= Guidelines.bpElevated) {
        bpTier = 'elevated';
      } else {
        bpTier = 'normal';
      }
    }

    // ---------- CKD ----------
    bool hasCkd = p.hasCkd;
    String ckdStage = 'none';
    int ckdGrade = 0;
    if (hasCkd) {
      final s = p.ckdStage ?? 3;
      ckdGrade = s.clamp(1, 5);
      ckdStage = switch (ckdGrade) {
        1 || 2 => 'stage1_2',
        3 => 'stage3',
        4 => 'stage4',
        5 => 'stage5',
        _ => 'stage3',
      };
    }

    // ---------- INITIAL TARGETS ----------
    double dailyKcal = 1800;
    double dailyCarb = 180;
    double dailyProtein = p.weightKg! * 0.9;
    double dailyFat = (dailyKcal * 0.27 / 9);
    double maxCarbPerMeal = 45;
    double dailySodiumCap = Guidelines.dailySodiumStandardMg;
    var allowedGi = <String>['low', 'medium'];
    final allowedTags = <String>[];
    final restrictedTags = <String>[];
    final restrictionFlags = <String>[];
    final warnings = <String>[];
    final recommendationsBn = <String>[];

    // ---------- HYPO WARNING ----------
    if (glucoseTier == 'unknown') {
      warnings.add(
          'গ্লুকোজ বা HbA1c তথ্য দেওয়া হয়নি — সাধারণ মধ্যম-কার্ব পরিকল্পনা দেখানো হচ্ছে');
    }

    // ---------- HYPERTENSION (DASH) ----------
    bool hasHypertension = bpTier == 'stage1' || bpTier == 'stage2';
    if (hasHypertension) {
      restrictionFlags.add('low_sodium_required');
      restrictedTags.add('high_sodium');
      dailySodiumCap = Guidelines.dailySodiumRestrictedMg;
      warnings.add(
          'উচ্চ রক্তচাপের কারণে সোডিয়াম দৈনিক ১৫০০ মিগ্রায় সীমিত করা হয়েছে (DASH 2024)');
    }

    // ---------- CKD (KDIGO 2024) ----------
    if (hasCkd) {
      restrictionFlags.addAll(['ckd_restricted_high_k', 'ckd_restricted_high_phos']);
      restrictedTags.addAll(['high_potassium', 'high_phosphorus', 'high_sodium']);
      warnings.add(
          'কিডনি রোগের কারণে পটাশিয়াম ও ফসফরাসযুক্ত খাবার সীমিত করা হয়েছে — নেফ্রোলজিস্টের পরামর্শ অনুসরণ করুন (KDIGO 2024)');
      if (ckdGrade >= 3) {
        dailyProtein = (p.weightKg! * 0.8)!;
        restrictionFlags.add('ckd_protein_limited');
      }
      if (ckdGrade >= 4) {
        dailyProtein = (p.weightKg! * 0.6)!;
        maxCarbPerMeal = maxCarbPerMeal < 30 ? maxCarbPerMeal : 30;
      }
    }

    // ---------- HEART (AHA 2024) ----------
    bool hasHeart = p.hasHeartDisease;
    if (hasHeart) {
      restrictionFlags.add('heart_moderate_restricted');
      restrictedTags.addAll([
        'high_saturated_fat',
        'trans_fat',
        'high_cholesterol',
        'high_sodium'
      ]);
      warnings.add(
          'হৃদরোগের কারণে সম্পৃক্ত চর্বি, কোলেস্টেরল ও সোডিয়াম সীমিত করা হয়েছে (AHA 2024)');
    }

    // ---------- INSULIN ----------
    bool onInsulin = p.onInsulin;
    if (onInsulin) {
      warnings.add(
          'আপনি ইনসুলিন গ্রহণ করছেন — খাবারের সময় ও পরিমাণ ধারাবাহিক রাখা জরুরি। কোনো বেলা বাদ দেওয়ার আগে ডাক্তারের পরামর্শ নিন।');
      recommendationsBn.add(
          'ইনসুলিনের সাথে খাবারের সময় ধারাবাহিক রাখুন — কোনো বেলা বাদ দেবেন না');
    }

    // ---------- ANEMIA (ICMR 2024) ----------
    bool hasAnemia = p.hasAnemia;
    if (hasAnemia) {
      warnings.add(
          'রক্তস্বল্পতা থাকায় আয়রন সমৃদ্ধ খাবার (শিং মাছ, কচু শাক, ডিম) অগ্রাধিকার দেওয়া হচ্ছে');
      allowedTags.add('iron_rich');
      restrictionFlags.add('prioritize_iron');
    }

    // ---------- GLUCOSE → TARGETS ----------
    switch (glucoseTier) {
      case 'good':
        maxCarbPerMeal = 45;
        allowedGi = ['low', 'medium'];
        dailyCarb = 200;
        dailyKcal = 2000;
        break;
      case 'moderate':
        maxCarbPerMeal = 35;
        allowedGi = ['low', 'medium'];
        dailyCarb = 160;
        dailyKcal = 1800;
        break;
      case 'poor':
        maxCarbPerMeal = 25;
        allowedGi = ['low'];
        dailyCarb = 130;
        dailyKcal = 1600;
        break;
      default:
        maxCarbPerMeal = 35;
        allowedGi = ['low', 'medium'];
    }
    if (p.mealSizePref == 'small') maxCarbPerMeal -= 5;
    if (p.mealSizePref == 'large') maxCarbPerMeal += 5;

    // ---------- BMI ADJUSTMENTS ----------
    bool isObese = bmiTier == 'obese';
    bool isUnderweight = bmiTier == 'underweight';
    if (isObese) {
      dailyKcal -= 300;
      dailyCarb -= 30;
      recommendationsBn.add(
          'প্রতিদিন ৫০০ কিলোক্যালরি ঘাটতি তৈরি করুন — শাকসবজি ও লেবু পানি বাড়ান');
    }
    if (isUnderweight) {
      dailyKcal += 300;
      dailyCarb += 30;
      recommendationsBn.add(
          'ঘন ঘন ছোট ছোট খাবার খান — ডাল, ডিম, কলা, খেজুর যোগ করুন');
    }

    // ---------- PREFERENCE EXCLUSIONS ----------
    final pref = p.foodPreference;
    switch (pref) {
      case 'vegetarian':
        restrictedTags.addAll(['meat', 'fish']);
        break;
      case 'fish_only':
        restrictedTags.addAll(['meat', 'beef', 'chicken', 'duck']);
        break;
      case 'no_beef':
        restrictedTags.add('beef');
        break;
    }

    // ---------- RECOMMENDATIONS ----------
    if (glucoseTier == 'poor') {
      recommendationsBn.add(
          'প্রতি বেলায় কার্ব ২৫ গ্রামের বেশি খাবেন না — ভাতের বদলে রুটি বা ওটস বেছে নিন');
    } else if (glucoseTier == 'moderate') {
      recommendationsBn.add(
          'প্রতি বেলায় কার্ব ৩৫ গ্রামের মধ্যে রাখুন — সবজি ও ডালের পরিমাণ বাড়ান');
    } else if (glucoseTier == 'good') {
      recommendationsBn.add(
          'ভালো নিয়ন্ত্রণ বজায় রাখতে প্রতি বেলায় সর্বোচ্চ ৪৫ গ্রাম কার্ব রাখুন');
    }
    if (hasHypertension) {
      recommendationsBn.add(
          'একদিনে সোডিয়াম ১৫০০ মিগ্রা-এর বেশি নয় — লবণ, আচার, চিপস এড়িয়ে চলুন');
    }
    if (hasCkd) {
      recommendationsBn.add(
          'একবেলায় পটাশিয়াম ২০০ মিগ্রা ও ফসফরাস ১৫০ মিগ্রার বেশি নয়');
    }
    if (hasHeart) {
      recommendationsBn.add(
          'সম্পৃক্ত চর্বি ৭%-এর কম রাখুন — ঘি/মাখনের বদলে সরিষার তেল');
    }
    bool isElderly = p.age! >= 60;
    if (isElderly) {
      recommendationsBn.add(
          'প্রতিদিন ন্যূনতম ২ লিটার পানি পান করুন — প্রস্রাবের রং হালকা হলুদ রাখুন');
    }

    dailyFat = (dailyKcal * 0.27 / 9);

    final conditions = UserConditions(
      hasCkd: hasCkd,
      hasHeartDisease: hasHeart,
      hasHypertension: hasHypertension,
      hasAnemia: hasAnemia,
      onInsulin: onInsulin,
      isObese: isObese,
      isUnderweight: isUnderweight,
      isElderly: isElderly,
      foodPreference: pref,
    );

    return DietClassification(
      glucoseTier: glucoseTier,
      bmiTier: bmiTier,
      bpTier: bpTier,
      ckdStage: ckdStage,
      ckdGrade: ckdGrade,
      foodPreference: pref,
      maxCarbPerMeal: maxCarbPerMeal,
      dailyCarbTargetG: dailyCarb,
      dailyProteinTargetG: dailyProtein,
      dailyFatTargetG: dailyFat,
      dailyKcalTarget: dailyKcal,
      dailySodiumCapMg: dailySodiumCap,
      allowedGi: allowedGi,
      allowedTags: allowedTags,
      restrictedTags: restrictedTags,
      restrictionFlags: restrictionFlags,
      warnings: warnings,
      recommendationsBn: recommendationsBn,
      conditions: conditions,
    );
  }

  /// Returns true if the given food violates the classification.
  /// Mirrors SQL `_filtered_foods_for` so offline judging matches server.
  static bool isFoodAllowed(MealItem food, DietClassification cls) {
    if (!cls.allowedGi.contains(food.giCategory)) return false;
    final restricted = cls.restrictedTags.toSet();
    if (food.tags.toSet().intersection(restricted).isNotEmpty) return false;
    if (cls.conditions.hasCkd) {
      if (food.potassiumMg > Guidelines.ckdPotassiumCapMg) return false;
      if (food.phosphorusMg > Guidelines.ckdPhosphorusCapMg) return false;
      if (food.proteinG > Guidelines.ckdProteinCapG) return false;
    }
    if (cls.conditions.hasHeartDisease) {
      if (food.fatG > Guidelines.heartFatCapG) return false;
      if (food.sodiumMg > Guidelines.heartSodiumCapMg) return false;
    }
    if (cls.conditions.hasHypertension && food.sodiumMg > Guidelines.htSodiumCapMg) {
      return false;
    }
    return true;
  }

  /// Filters a list of foods to those allowed under the classification.
  /// Mirrors SQL `_filtered_foods_for`.
  static List<MealItem> allowedFoods(List<MealItem> foods, DietClassification cls) {
    return foods.where((f) => isFoodAllowed(f, cls)).toList();
  }

  /// Foods that the user should specifically AVOID, with Bengali reasons.
  /// Each entry has the food and a short Bengali reason explaining why.
  static List<RestrictedFood> restrictedFoods(List<MealItem> foods, DietClassification cls) {
    final out = <RestrictedFood>[];
    for (final f in foods) {
      final reason = _reasonForRestriction(f, cls);
      if (reason != null) {
        out.add(RestrictedFood(food: f, reason: reason));
      }
    }
    return out;
  }

  static String? _reasonForRestriction(MealItem food, DietClassification cls) {
    if (cls.conditions.hasCkd) {
      if (food.potassiumMg > Guidelines.ckdPotassiumCapMg) {
        return 'উচ্চ পটাশিয়াম (${food.potassiumMg.toInt()} মিগ্রা) — কিডনি রোগে সীমিত রাখুন (KDIGO 2024)';
      }
      if (food.phosphorusMg > Guidelines.ckdPhosphorusCapMg) {
        return 'উচ্চ ফসফরাস (${food.phosphorusMg.toInt()} মিগ্রা) — কিডনি রোগে সীমিত রাখুন (KDIGO 2024)';
      }
      if (food.proteinG > Guidelines.ckdProteinCapG) {
        return 'উচ্চ প্রোটিন — কিডনি রোগে একবেলায় ২৫ গ্রামের বেশি নয়';
      }
    }
    if (cls.conditions.hasHeartDisease) {
      if (food.fatG > Guidelines.heartFatCapG) {
        return 'উচ্চ চর্বি (${food.fatG.toStringAsFixed(1)} গ্রাম) — হৃদরোগে এড়িয়ে চলুন (AHA 2024)';
      }
      if (food.sodiumMg > Guidelines.heartSodiumCapMg) {
        return 'উচ্চ সোডিয়াম (${food.sodiumMg.toInt()} মিগ্রা) — হৃদরোগে সীমিত রাখুন';
      }
    }
    if (cls.conditions.hasHypertension && food.sodiumMg > Guidelines.htSodiumCapMg) {
      return 'উচ্চ সোডিয়াম (${food.sodiumMg.toInt()} মিগ্রা) — উচ্চ রক্তচাপে এড়িয়ে চলুন (DASH 2024)';
    }
    if (cls.glucoseTier == 'poor' && food.giCategory == 'high') {
      return 'উচ্চ GI — গ্লুকোজ দ্রুত বাড়াবে (ADA 2024)';
    }
    if (food.carbG > cls.maxCarbPerMeal) {
      return 'এক বেলায় সর্বোচ্চ ${cls.maxCarbPerMeal.toInt()} গ্রাম কার্ব — এটি বেশি';
    }
    if (food.tags.contains('beef') && cls.foodPreference == 'no_beef') {
      return 'ব্যক্তিগত পছন্দ — গরুর মাংস বাদ';
    }
    if (food.tags.contains('meat') &&
        (cls.foodPreference == 'vegetarian' || cls.foodPreference == 'fish_only')) {
      return 'ব্যক্তিগত পছন্দ — মাংস বাদ';
    }
    if (food.tags.contains('fish') && cls.foodPreference == 'vegetarian') {
      return 'ব্যক্তিগত পছন্দ — মাছ সীমিত';
    }
    return null;
  }

  /// Convert this to the legacy `Classification` shape so legacy
  /// ImpactEngine.judge() keeps working unchanged.
  static Classification toLegacy(DietClassification c) {
    return Classification(
      glucoseTier: c.glucoseTier,
      bmiTier: c.bmiTier,
      bpTier: c.bpTier,
      maxCarbPerMeal: c.maxCarbPerMeal,
      allowedGi: c.allowedGi,
      restrictionFlags: c.restrictionFlags,
      warnings: c.warnings,
    );
  }
}

class RestrictedFood {
  final MealItem food;
  final String reason;
  const RestrictedFood({required this.food, required this.reason});
}