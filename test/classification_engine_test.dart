// Rule-boundary tests for [DietRecommender.classify].
//
// These tests pin the published clinical thresholds used by the
// recommender to its Dart mirror. If a guideline value moves, the
// build should break until [DietRecommender.classify] + the SQL
// counterpart in `supabasesql/23_classify_v2.sql` are updated
// together. The mirror lives in lib/services/diet_recommender.dart
// under the [Guidelines] class.

import 'package:flutter_test/flutter_test.dart';

import 'package:amar_diet/models/user_profile.dart';
import 'package:amar_diet/services/diet_recommender.dart';

/// Build a baseline healthy profile that callers then mutate.
UserProfile _base({double weight = 65, double height = 165}) {
  return UserProfile(
    age: 45,
    sex: 'male',
    weightKg: weight,
    heightCm: height,
    fastingGlucoseMmol: 5.5,
    postMealGlucoseMmol: 7.0,
    hba1cPercent: 5.5,
    systolicBp: 115,
    diastolicBp: 75,
    onInsulin: false,
    hasCkd: false,
    hasHeartDisease: false,
    hasAnemia: false,
    activityLevel: 'moderate',
    mealSizePref: 'medium',
    foodPreference: 'omnivore',
  );
}

/// Profile with NO HbA1c — used by fasting-glucose-only tests.
UserProfile _noA1c({double weight = 65, double height = 165}) {
  return UserProfile(
    age: 45,
    sex: 'male',
    weightKg: weight,
    heightCm: height,
    fastingGlucoseMmol: 5.5,
    systolicBp: 115,
    diastolicBp: 75,
    onInsulin: false,
    hasCkd: false,
    hasHeartDisease: false,
    hasAnemia: false,
    activityLevel: 'moderate',
    mealSizePref: 'medium',
    foodPreference: 'omnivore',
  );
}

void main() {
  group('HbA1c tier (ADA 2024)', () {
    test('< 7.0% → good', () {
      final c = DietRecommender.classify(_base().copyWith(hba1cPercent: 6.4));
      expect(c.glucoseTier, 'good');
      expect(c.maxCarbPerMeal, Guidelines.carbGood);
    });

    test('7.0% → moderate (boundary)', () {
      final c =
          DietRecommender.classify(_base().copyWith(hba1cPercent: 7.0));
      expect(c.glucoseTier, 'moderate');
      expect(c.maxCarbPerMeal, Guidelines.carbModerate);
    });

    test('8.5% → moderate (inclusive boundary)', () {
      // Per `classify`: a < 7 good, a <= 8.5 moderate, a > 8.5 poor.
      final c =
          DietRecommender.classify(_base().copyWith(hba1cPercent: 8.5));
      expect(c.glucoseTier, 'moderate');
      expect(c.maxCarbPerMeal, Guidelines.carbModerate);
    });

    test('> 8.5% → poor', () {
      final c =
          DietRecommender.classify(_base().copyWith(hba1cPercent: 8.6));
      expect(c.glucoseTier, 'poor');
      expect(c.maxCarbPerMeal, Guidelines.carbPoor);
    });
  });

  group('Fasting glucose tier (ADA 2024, mmol/L)', () {
    test('5.5 → good', () {
      final c = DietRecommender.classify(
          _noA1c().copyWith(fastingGlucoseMmol: 5.5));
      expect(c.glucoseTier, 'good');
    });

    test('7.0 → moderate (inclusive boundary)', () {
      // Per `classify`: fg < 7 good, fg <= 10 moderate, fg > 10 poor.
      final c = DietRecommender.classify(
          _noA1c().copyWith(fastingGlucoseMmol: 7.0));
      expect(c.glucoseTier, 'moderate');
    });

    test('10.0 → moderate (inclusive upper boundary)', () {
      final c = DietRecommender.classify(
          _noA1c().copyWith(fastingGlucoseMmol: 10.0));
      expect(c.glucoseTier, 'moderate');
    });

    test('10.1 → poor', () {
      final c = DietRecommender.classify(
          _noA1c().copyWith(fastingGlucoseMmol: 10.1));
      expect(c.glucoseTier, 'poor');
    });
  });

  group('BMI tier (WHO SEAR Asian)', () {
    test('BMI 17 → underweight', () {
      final c = DietRecommender.classify(
          _base().copyWith(weightKg: 47, heightCm: 165)); // 17.2
      expect(c.bmiTier, 'underweight');
    });

    test('BMI 22 → normal (just below Asian cutoff)', () {
      // height 165 → BMI 22 → 60kg
      final c = DietRecommender.classify(
          _base().copyWith(weightKg: 60, heightCm: 165));
      expect(c.bmiTier, 'normal');
    });

    test('BMI 25 → overweight', () {
      // height 165 → BMI 25 → 68kg
      final c = DietRecommender.classify(
          _base().copyWith(weightKg: 68, heightCm: 165));
      expect(c.bmiTier, 'overweight');
    });

    test('BMI 27.5 → obese', () {
      // height 165 → BMI 27.5 → 75kg
      final c = DietRecommender.classify(
          _base().copyWith(weightKg: 75, heightCm: 165));
      expect(c.bmiTier, 'obese');
      expect(c.conditions.isObese, isTrue);
    });
  });

  group('BP tier (ACC/AHA 2017)', () {
    test('SBP 119/79 → normal', () {
      final c = DietRecommender.classify(
          _base().copyWith(systolicBp: 119, diastolicBp: 79));
      expect(c.bpTier, 'normal');
    });

    test('SBP 120/79 → elevated', () {
      final c = DietRecommender.classify(
          _base().copyWith(systolicBp: 120, diastolicBp: 79));
      expect(c.bpTier, 'elevated');
    });

    test('SBP 129/79 → elevated (below stage 1)', () {
      final c = DietRecommender.classify(
          _base().copyWith(systolicBp: 129, diastolicBp: 79));
      expect(c.bpTier, 'elevated');
    });

    test('SBP 130/79 → stage1', () {
      final c = DietRecommender.classify(
          _base().copyWith(systolicBp: 130, diastolicBp: 79));
      expect(c.bpTier, 'stage1');
    });

    test('SBP 140/80 → stage2', () {
      final c = DietRecommender.classify(
          _base().copyWith(systolicBp: 140, diastolicBp: 80));
      expect(c.bpTier, 'stage2');
    });
  });

  group('CKD stage (KDIGO 2024)', () {
    test('hasCkd=false → none', () {
      final c = DietRecommender.classify(
          _base().copyWith(hasCkd: false, ckdStage: null));
      expect(c.ckdStage, 'none');
      expect(c.ckdGrade, 0);
      expect(c.conditions.hasCkd, isFalse);
    });

    test('stage 2 → stage1_2 (grade 2)', () {
      final c = DietRecommender.classify(
          _base().copyWith(hasCkd: true, ckdStage: 2));
      expect(c.ckdStage, 'stage1_2');
      expect(c.ckdGrade, 2);
    });

    test('stage 3 → stage3 (grade 3)', () {
      final c = DietRecommender.classify(
          _base().copyWith(hasCkd: true, ckdStage: 3));
      expect(c.ckdStage, 'stage3');
      expect(c.ckdGrade, 3);
    });

    test('stage 4 → stage4 (grade 4)', () {
      final c = DietRecommender.classify(
          _base().copyWith(hasCkd: true, ckdStage: 4));
      expect(c.ckdStage, 'stage4');
    });

    test('stage 5 → stage5 (grade 5)', () {
      final c = DietRecommender.classify(
          _base().copyWith(hasCkd: true, ckdStage: 5));
      expect(c.ckdStage, 'stage5');
      expect(c.ckdGrade, 5);
    });
  });

  group('Age flag', () {
    test('age >= 60 → isElderly', () {
      final c = DietRecommender.classify(_base().copyWith(age: 60));
      expect(c.conditions.isElderly, isTrue);
    });

    test('age 59 → not elderly', () {
      final c = DietRecommender.classify(_base().copyWith(age: 59));
      expect(c.conditions.isElderly, isFalse);
    });
  });

  group('Food preference passthrough', () {
    test('vegetarian → no meat', () {
      final c = DietRecommender.classify(
          _base().copyWith(foodPreference: 'vegetarian'));
      expect(c.foodPreference, 'vegetarian');
      expect(c.conditions.foodPreference, 'vegetarian');
    });

    test('no_beef → no beef', () {
      final c = DietRecommender.classify(
          _base().copyWith(foodPreference: 'no_beef'));
      expect(c.foodPreference, 'no_beef');
    });

    test('omnivore → unrestricted', () {
      final c = DietRecommender.classify(
          _base().copyWith(foodPreference: 'omnivore'));
      expect(c.foodPreference, 'omnivore');
    });
  });

  group('Sodium cap', () {
    test('hypertension → restricted sodium cap', () {
      final c = DietRecommender.classify(
          _base().copyWith(systolicBp: 145, diastolicBp: 92));
      expect(c.dailySodiumCapMg, Guidelines.dailySodiumRestrictedMg);
    });

    test('no hypertension → standard sodium cap', () {
      final c = DietRecommender.classify(
          _base().copyWith(systolicBp: 115, diastolicBp: 75));
      expect(c.dailySodiumCapMg, Guidelines.dailySodiumStandardMg);
    });
  });
}
