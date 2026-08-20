import '../models/meal_item.dart';
import 'diet_recommender.dart';

/// Client-side impact classifier.
///
/// Produces a [MealImpact] (good / neutral / bad + a Bengali reason with
/// citation) for a food given the user's classification. The authoritative
/// answer still comes from the server via `record_meal_intake`; this
/// mirrors the server's `_filtered_foods_for` so the UI can give instant
/// feedback offline.
class ImpactEngine {
  /// Modern judge — takes the full [DietClassification].
  static MealImpact judgeV2({
    required MealItem food,
    required MealItem? original,
    required DietClassification cls,
  }) {
    // ---------- HARD BANS ----------
    if (cls.conditions.hasCkd) {
      if (food.potassiumMg > 200) {
        return const MealImpact(
          level: 'bad',
          reason: 'উচ্চ পটাশিয়াম — কিডনি রোগে সীমিত রাখুন (KDIGO 2024)',
        );
      }
      if (food.phosphorusMg > 150) {
        return const MealImpact(
          level: 'bad',
          reason: 'উচ্চ ফসফরাস — কিডনি রোগে সীমিত রাখুন (KDIGO 2024)',
        );
      }
      if (cls.ckdGrade >= 3 && food.proteinG > 25) {
        return const MealImpact(
          level: 'bad',
          reason: 'উচ্চ প্রোটিন — কিডনি রোগে একবেলায় ২৫ গ্রামের বেশি নয় (KDIGO 2024)',
        );
      }
    }

    if (cls.conditions.hasHeartDisease) {
      if (food.fatG > 12) {
        return const MealImpact(
          level: 'bad',
          reason: 'উচ্চ চর্বি — হৃদরোগে সীমিত রাখুন (AHA 2024)',
        );
      }
      if (food.sodiumMg > 200) {
        return const MealImpact(
          level: 'bad',
          reason: 'উচ্চ সোডিয়াম — হৃদরোগে সীমিত রাখুন (AHA 2024)',
        );
      }
    }

    if (cls.conditions.hasHypertension && food.sodiumMg > 250) {
      return const MealImpact(
        level: 'bad',
        reason: 'উচ্চ সোডিয়াম — উচ্চ রক্তচাপে এড়িয়ে চলুন (DASH 2024)',
      );
    }

    // ---------- GLUCOSE ----------
    if (cls.glucoseTier == 'poor' && food.giCategory == 'high') {
      return const MealImpact(
        level: 'bad',
        reason: 'উচ্চ GI — গ্লুকোজ দ্রুত বাড়াবে (ADA 2024)',
      );
    }
    if (food.carbG > cls.maxCarbPerMeal) {
      return MealImpact(
        level: 'bad',
        reason:
            'এক বেলায় সর্বোচ্চ ${cls.maxCarbPerMeal.toInt()} গ্রাম কার্ব সুপারিশ — এটি বেশি',
      );
    }

    // ---------- PREFERENCE ----------
    if (food.tags.contains('beef') && cls.foodPreference == 'no_beef') {
      return const MealImpact(
        level: 'bad',
        reason: 'ব্যক্তিগত পছন্দ — গরুর মাংস বাদ',
      );
    }
    if (food.tags.contains('meat') &&
        (cls.foodPreference == 'vegetarian' ||
            cls.foodPreference == 'fish_only')) {
      return const MealImpact(
        level: 'bad',
        reason: 'ব্যক্তিগত পছন্দ — মাংস বাদ',
      );
    }
    if (food.tags.contains('fish') && cls.foodPreference == 'vegetarian') {
      return const MealImpact(
        level: 'bad',
        reason: 'ব্যক্তিগত পছন্দ — মাছ সীমিত',
      );
    }

    // ---------- COMPARE TO ORIGINAL (SWAP) ----------
    if (original != null && original.id != food.id) {
      if (food.healthiness == 'good' && original.healthiness != 'good') {
        return const MealImpact(
          level: 'good',
          reason: 'ভালো বিকল্প — মূল পরিকল্পনার চেয়ে স্বাস্থ্যকর',
        );
      }
      if (food.healthiness == 'bad' && original.healthiness != 'bad') {
        return const MealImpact(
          level: 'bad',
          reason: 'এই বিকল্পটি কম উপকারী — অন্য বিকল্প বিবেচনা করুন',
        );
      }
    }

    // ---------- DEFAULT ----------
    if (food.healthiness == 'good') {
      return MealImpact(
        level: 'good',
        reason: 'GI: ${giLabel(food.giCategory)} · পরিকল্পনা অনুযায়ী গ্রহণযোগ্য',
      );
    }
    if (food.healthiness == 'bad') {
      return const MealImpact(
        level: 'bad',
        reason: 'এই খাবারটি ডায়াবেটিস-বান্ধব নয় — এড়িয়ে চলুন',
      );
    }
    return const MealImpact(
      level: 'neutral',
      reason: 'মাঝারি প্রভাব — পরিমাণ সীমিত রাখুন',
    );
  }

  /// Legacy judge for callers that still hold a [Classification].
  /// Converts to [DietClassification] and delegates to [judgeV2].
  /// Note: a legacy Classification loses the foodPreference, CKD grade,
  /// and daily targets; if you need full accuracy call judgeV2 directly.
  static MealImpact judge({
    required MealItem food,
    required MealItem? original,
    required Classification cls,
  }) {
    // Build a minimal DietClassification carrying only the legacy fields.
    final dc = DietClassification(
      glucoseTier: cls.glucoseTier,
      bmiTier: cls.bmiTier,
      bpTier: cls.bpTier,
      ckdStage: 'none',
      ckdGrade: 0,
      foodPreference: 'omnivore',
      maxCarbPerMeal: cls.maxCarbPerMeal,
      dailyCarbTargetG: 0,
      dailyProteinTargetG: 0,
      dailyFatTargetG: 0,
      dailyKcalTarget: 0,
      dailySodiumCapMg: 0,
      allowedGi: cls.allowedGi,
      allowedTags: const [],
      restrictedTags: const [],
      restrictionFlags: cls.restrictionFlags,
      warnings: cls.warnings,
      recommendationsBn: const [],
      conditions: UserConditions(
        hasCkd: cls.restrictionFlags
            .any((f) => f.startsWith('ckd_restricted')),
        hasHeartDisease: cls.restrictionFlags.contains('heart_moderate_restricted'),
        hasHypertension: cls.restrictionFlags.contains('low_sodium_required'),
        hasAnemia: false,
        onInsulin: false,
        isObese: false,
        isUnderweight: false,
        isElderly: false,
        foodPreference: 'omnivore',
      ),
    );
    return judgeV2(food: food, original: original, cls: dc);
  }

  static String giLabel(String gi) {
    switch (gi) {
      case 'low':
        return 'কম GI';
      case 'medium':
        return 'মাঝারি GI';
      case 'high':
        return 'উচ্চ GI';
      default:
        return gi;
    }
  }
}

class MealImpact {
  final String level; // 'good' | 'neutral' | 'bad'
  final String reason;
  const MealImpact({required this.level, required this.reason});
}

/// Mirror of the SQL `classify_user()` return shape.
class Classification {
  final String glucoseTier;
  final String bmiTier;
  final String bpTier;
  final double maxCarbPerMeal;
  final List<String> allowedGi;
  final List<String> restrictionFlags;
  final List<String> warnings;

  Classification({
    required this.glucoseTier,
    required this.bmiTier,
    required this.bpTier,
    required this.maxCarbPerMeal,
    required this.allowedGi,
    required this.restrictionFlags,
    required this.warnings,
  });

  factory Classification.fromJson(Map<String, dynamic> json) {
    return Classification(
      glucoseTier: (json['glucose_tier'] ?? 'unknown') as String,
      bmiTier: (json['bmi_tier'] ?? 'unknown') as String,
      bpTier: (json['bp_tier'] ?? 'unknown') as String,
      maxCarbPerMeal: ((json['max_carb_per_meal'] ?? 35) as num).toDouble(),
      allowedGi: (json['allowed_gi'] as List?)?.cast<String>() ?? const [],
      restrictionFlags:
          (json['restriction_flags'] as List?)?.cast<String>() ?? const [],
      warnings: (json['warnings'] as List?)?.cast<String>() ?? const [],
    );
  }
}
