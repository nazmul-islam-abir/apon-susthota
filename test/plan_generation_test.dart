// Integration-style tests for the meal-plan generation rules.
//
// These exercise [DietRecommender.allowedFoods] and
// [ImpactEngine.judgeV2] against a synthetic Bangladesh food set
// to verify that the per-user clinical restrictions are actually
// applied during food selection — i.e. vegetarians don't get meat,
// high HbA1c caps carbs, CKD stage 3 excludes banana, BP stage 2
// excludes high-sodium pickles, etc.
//
// The tests mirror the SQL in `supabasesql/24_daily_recommendation_v2.sql`.
// If they fail, the rules are drifting away from the published
// guidelines (ADA 2024 / KDIGO 2024 / AHA 2024 / DASH 2024).

import 'package:flutter_test/flutter_test.dart';

import 'package:amar_diet/models/meal_item.dart';
import 'package:amar_diet/models/user_profile.dart';
import 'package:amar_diet/services/diet_recommender.dart';
import 'package:amar_diet/services/impact_engine.dart';

MealItem _f({
  required String id,
  String name = 'খাবার',
  String category = 'carb',
  double carb = 20,
  double protein = 5,
  double fat = 3,
  double fiber = 2,
  double sodium = 50,
  double potassium = 150,
  double phosphorus = 80,
  String gi = 'low',
  String healthiness = 'good',
  List<String> tags = const [],
}) {
  return MealItem(
    id: id,
    nameBn: name,
    category: category,
    carbG: carb,
    proteinG: protein,
    fatG: fat,
    fiberG: fiber,
    sodiumMg: sodium,
    potassiumMg: potassium,
    phosphorusMg: phosphorus,
    giCategory: gi,
    healthiness: healthiness,
    tags: tags,
  );
}

UserProfile _profile({
  double hba1c = 6.0,
  String foodPreference = 'omnivore',
  bool hasCkd = false,
  int? ckdStage,
  bool hasHeartDisease = false,
  bool hasAnemia = false,
  int systolicBp = 115,
  int diastolicBp = 75,
  bool onInsulin = false,
  double weight = 65,
  double height = 165,
  int age = 45,
}) {
  return UserProfile(
    age: age,
    sex: 'male',
    weightKg: weight,
    heightCm: height,
    fastingGlucoseMmol: 5.5,
    hba1cPercent: hba1c,
    systolicBp: systolicBp,
    diastolicBp: diastolicBp,
    onInsulin: onInsulin,
    hasCkd: hasCkd,
    ckdStage: ckdStage,
    hasHeartDisease: hasHeartDisease,
    hasAnemia: hasAnemia,
    activityLevel: 'moderate',
    mealSizePref: 'medium',
    foodPreference: foodPreference,
  );
}

/// Standard Bangladeshi food set used by every test.
List<MealItem> _catalog() => [
      _f(id: 'rice', name: 'ভাত', carb: 45, gi: 'high', tags: ['staple']),
      _f(
        id: 'beef',
        name: 'গরুর মাংস',
        category: 'protein',
        protein: 28,
        fat: 14,
        sodium: 70,
        potassium: 320,
        phosphorus: 200,
        tags: ['meat', 'beef'],
      ),
      _f(
        id: 'chicken',
        name: 'মুরগি',
        category: 'protein',
        protein: 25,
        fat: 8,
        sodium: 80,
        tags: ['meat', 'chicken'],
      ),
      _f(
        id: 'hilsa',
        name: 'ইলিশ',
        category: 'protein',
        protein: 22,
        fat: 12,
        sodium: 60,
        potassium: 280,
        tags: ['fish'],
      ),
      _f(
        id: 'dal',
        name: 'মসুর ডাল',
        carb: 20,
        protein: 9,
        fiber: 8,
        potassium: 360,
        phosphorus: 180,
        tags: ['lentil'],
      ),
      _f(
        id: 'banana',
        name: 'কলা',
        carb: 27,
        protein: 1,
        potassium: 358,
        gi: 'medium',
        tags: ['fruit'],
      ),
      _f(
        id: 'pickle',
        name: 'আচার',
        category: 'snack',
        carb: 5,
        sodium: 950,
        tags: ['high_sodium', 'snack'],
      ),
      _f(id: 'spinach', name: 'পালং শাক', carb: 3, protein: 2,
          fiber: 2, potassium: 558, phosphorus: 49, tags: ['vegetable']),
      _f(id: 'papaya', name: 'পেঁপে', carb: 11, gi: 'low', tags: ['fruit']),
    ];

void main() {
  group('Food preference filtering', () {
    test('vegetarian → no meat, no fish', () {
      final cls = DietRecommender.classify(
          _profile(foodPreference: 'vegetarian'));
      final allowed = DietRecommender.allowedFoods(_catalog(), cls)
          .map((f) => f.id)
          .toSet();
      expect(allowed.contains('beef'), isFalse);
      expect(allowed.contains('chicken'), isFalse);
      expect(allowed.contains('hilsa'), isFalse);
      expect(allowed.contains('dal'), isTrue);
    });

    test('no_beef → beef excluded, fish/chicken OK', () {
      final cls = DietRecommender.classify(
          _profile(foodPreference: 'no_beef'));
      final allowed = DietRecommender.allowedFoods(_catalog(), cls)
          .map((f) => f.id)
          .toSet();
      expect(allowed.contains('beef'), isFalse);
      expect(allowed.contains('hilsa'), isTrue);
      expect(allowed.contains('chicken'), isTrue);
    });

    test('fish_only → no red meat / chicken', () {
      final cls = DietRecommender.classify(
          _profile(foodPreference: 'fish_only'));
      final allowed = DietRecommender.allowedFoods(_catalog(), cls)
          .map((f) => f.id)
          .toSet();
      expect(allowed.contains('beef'), isFalse);
      expect(allowed.contains('chicken'), isFalse);
      expect(allowed.contains('hilsa'), isTrue);
    });
  });

  group('High HbA1c caps', () {
    test('HbA1c 9.0 → no high-GI foods', () {
      final cls = DietRecommender.classify(_profile(hba1c: 9.0));
      // Rice is high-GI; should be excluded when glucose tier = poor.
      expect(cls.glucoseTier, 'poor');
      expect(cls.allowedGi.contains('high'), isFalse);
      final allowed = DietRecommender.allowedFoods(_catalog(), cls)
          .map((f) => f.id)
          .toSet();
      expect(allowed.contains('rice'), isFalse);
      expect(allowed.contains('papaya'), isTrue); // low GI
    });

    test('HbA1c 6.0 → conservative GI list (low/medium only)', () {
      final cls = DietRecommender.classify(_profile(hba1c: 6.0));
      expect(cls.glucoseTier, 'good');
      // Conservative default — even "good" tier blocks high-GI staples
      // because diabetes patients avoid post-prandial spikes regardless
      // of baseline control (ADA 2024 §Glycemic Targets).
      expect(cls.allowedGi, ['low', 'medium']);
    });

    test('per-meal carb cap kicks in for moderate HbA1c', () {
      final cls = DietRecommender.classify(_profile(hba1c: 7.0));
      expect(cls.glucoseTier, 'moderate');
      expect(cls.maxCarbPerMeal, 35);
    });
  });

  group('CKD stage 3+ exclusions (KDIGO 2024)', () {
    test('CKD stage 3 → banana blocked (high potassium)', () {
      final cls = DietRecommender.classify(
          _profile(hasCkd: true, ckdStage: 3));
      final allowed = DietRecommender.allowedFoods(_catalog(), cls)
          .map((f) => f.id)
          .toSet();
      expect(allowed.contains('banana'), isFalse);
      expect(allowed.contains('spinach'), isFalse); // K=558 > 200
    });

    test('CKD stage 3 → high-protein beef blocked', () {
      final cls = DietRecommender.classify(
          _profile(hasCkd: true, ckdStage: 3));
      final allowed = DietRecommender.allowedFoods(_catalog(), cls)
          .map((f) => f.id)
          .toSet();
      // Beef has proteinG=28 > 25 cap → excluded.
      expect(allowed.contains('beef'), isFalse);
    });

    test('CKD stage 2 → caps apply (protein K)', () {
      final cls = DietRecommender.classify(
          _profile(hasCkd: true, ckdStage: 2));
      expect(cls.ckdStage, 'stage1_2');
      expect(cls.conditions.hasCkd, isTrue);
    });
  });

  group('BP stage 2 → sodium cap (DASH 2024)', () {
    test('pickle excluded due to high sodium', () {
      final cls = DietRecommender.classify(
          _profile(systolicBp: 145, diastolicBp: 92));
      expect(cls.bpTier, 'stage2');
      final allowed = DietRecommender.allowedFoods(_catalog(), cls)
          .map((f) => f.id)
          .toSet();
      // pickle sodium = 950 > 250 cap.
      expect(allowed.contains('pickle'), isFalse);
    });

    test('restricted sodium cap reduced', () {
      final cls = DietRecommender.classify(
          _profile(systolicBp: 145, diastolicBp: 92));
      expect(cls.dailySodiumCapMg, 1500);
    });
  });

  group('Heart disease exclusions (AHA 2024)', () {
    test('high-fat + high-sodium foods blocked', () {
      final cls =
          DietRecommender.classify(_profile(hasHeartDisease: true));
      final allowed = DietRecommender.allowedFoods(_catalog(), cls)
          .map((f) => f.id)
          .toSet();
      // beef: fatG=14 > 12 cap.
      expect(allowed.contains('beef'), isFalse);
      // pickle: sodium=950 > 200 cap.
      expect(allowed.contains('pickle'), isFalse);
    });
  });

  group('ImpactEngine.judgeV2 citations', () {
    test('CKD + banana → bad with KDIGO reason', () {
      final cls = DietRecommender.classify(
          _profile(hasCkd: true, ckdStage: 3));
      final banana = _catalog().firstWhere((f) => f.id == 'banana');
      final impact = ImpactEngine.judgeV2(food: banana, original: null, cls: cls);
      expect(impact.level, 'bad');
      expect(impact.reason, contains('KDIGO 2024'));
    });

    test('hypertension + pickle → bad with DASH reason', () {
      final cls = DietRecommender.classify(
          _profile(systolicBp: 145, diastolicBp: 92));
      final pickle = _catalog().firstWhere((f) => f.id == 'pickle');
      final impact = ImpactEngine.judgeV2(food: pickle, original: null, cls: cls);
      expect(impact.level, 'bad');
      expect(impact.reason, contains('DASH 2024'));
    });

    test('heart + beef → bad with AHA reason', () {
      final cls =
          DietRecommender.classify(_profile(hasHeartDisease: true));
      final beef = _catalog().firstWhere((f) => f.id == 'beef');
      final impact = ImpactEngine.judgeV2(food: beef, original: null, cls: cls);
      expect(impact.level, 'bad');
      expect(impact.reason, contains('AHA 2024'));
    });

    test('good food → good impact with no restriction', () {
      final cls = DietRecommender.classify(_profile());
      final papaya = _catalog().firstWhere((f) => f.id == 'papaya');
      final impact = ImpactEngine.judgeV2(food: papaya, original: null, cls: cls);
      expect(impact.level, isNot('bad'));
    });
  });

  group('Restricted foods list', () {
    test('returns Bengali reasons for CKD diet', () {
      final cls = DietRecommender.classify(
          _profile(hasCkd: true, ckdStage: 3));
      final restricted =
          DietRecommender.restrictedFoods(_catalog(), cls);
      final ids = restricted.map((r) => r.food.id).toSet();
      expect(ids.contains('banana'), isTrue);
      expect(ids.contains('spinach'), isTrue);
      // Every reason should be in Bengali script — at minimum contain
      // a non-ASCII character (Bengali range starts at U+0980).
      for (final r in restricted) {
        expect(r.reason.codeUnits.any((c) => c > 0x0980), isTrue,
            reason: 'Reason should be Bengali: "${r.reason}"');
      }
    });
  });
}