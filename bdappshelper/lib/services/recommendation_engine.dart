// =====================================================================
// Amar Diet — Meal-time Recommendation Engine
// =====================================================================
//
// Pure-Dart, no Hive / I/O. Inputs come from ApiService.
//
// Output: for each meal slot (breakfast/lunch/dinner/snack) a list of
// the top 3 best-matching foods, ranked by:
//
//   1. Calorie-fit to remaining budget for that slot (0..1)
//   2. Diet-preference filter (hard — not a score)
//   3. Variety: foods already eaten today are excluded
//   4. Soft meal-type bias (e.g. fruits/dairy for breakfast)
//   5. Macro balance tiebreaker for weight-loss goals
//
// Usage:
//   final ctx = RecommendationContext(profile, progress, todayMeals);
//   final recs = RecommendationEngine.suggest(ctx);
// =====================================================================

import '../data/bd_food_library.dart' as bd;
import 'api_service.dart' as api;

class MealSuggestion {
  const MealSuggestion({
    required this.mealType,
    required this.label,
    required this.options,
  });

  /// One of: 'breakfast', 'lunch', 'dinner', 'snack'.
  final String mealType;

  /// Human-readable label, e.g. "Breakfast".
  final String label;

  /// Up to 3 best foods for this slot.
  final List<api.FoodItem> options;
}

class RecommendationContext {
  const RecommendationContext({
    required this.profile,
    required this.progress,
    required this.todayMeals,
  });

  final api.UserProfile profile;
  final api.ProgressReport progress;
  final List<api.MealEntry> todayMeals;
}

class RecommendationEngine {
  RecommendationEngine._();

  /// All four meal slots in display order.
  static const List<String> _mealOrder = [
    'breakfast',
    'lunch',
    'snack',
    'dinner',
  ];

  /// Returns one MealSuggestion per meal slot, in fixed order.
  static List<MealSuggestion> suggest(RecommendationContext ctx) {
    final remaining =
        (ctx.progress.kcalTarget - ctx.progress.kcalIn).clamp(0, 10000);
    final slotsLeft = _slotsRemainingNow();
    final eaten = ctx.todayMeals.map((m) => m.foodId).toSet();

    final out = <MealSuggestion>[];
    for (final type in _mealOrder) {
      final slotTarget = _slotKcalTarget(
        remaining: remaining.toDouble(),
        type: type,
        slotsLeft: slotsLeft,
        dailyTarget: ctx.progress.kcalTarget,
      );

      final ranked = _rank(
        ctx: ctx,
        mealType: type,
        slotTarget: slotTarget,
        eatenIds: eaten,
      );

      out.add(
        MealSuggestion(
          mealType: type,
          label: _labelFor(type),
          options: ranked,
        ),
      );
    }
    return out;
  }

  /// How many meal slots are still "upcoming today" based on the
  /// current hour. Used to evenly split remaining kcal.
  static int _slotsRemainingNow() {
    final h = DateTime.now().hour;
    if (h < 10) return 4; // breakfast, lunch, snack, dinner
    if (h < 14) return 3; // lunch, snack, dinner
    if (h < 19) return 2; // snack, dinner
    return 1; // dinner only
  }

  static double _slotKcalTarget({
    required double remaining,
    required String type,
    required int slotsLeft,
    required double dailyTarget,
  }) {
    // Even split among remaining slots.
    final share = (slotsLeft > 0 ? remaining / slotsLeft : remaining)
        .clamp(0.0, double.infinity);
    return share;
  }

  /// Public helper: the meal slot that is "now" or "next" — used by
  /// the home dashboard to pick a single strip of 3 cards.
  static String currentOrNextMeal() {
    final h = DateTime.now().hour;
    if (h < 10) return 'breakfast';
    if (h < 14) return 'lunch';
    if (h < 19) return 'snack';
    return 'dinner';
  }

  // -------------------------------------------------------------------
  //  Ranking
  // -------------------------------------------------------------------

  static List<api.FoodItem> _rank({
    required RecommendationContext ctx,
    required String mealType,
    required double slotTarget,
    required Set<String> eatenIds,
  }) {
    final goal = (ctx.profile.goal ?? '').toLowerCase();
    final diet = (ctx.profile.dietPref ?? '').toLowerCase();

    final scored = <_Scored>[];

    for (final src in bd.BdFoodLibrary.all) {
      // 1) Variety: drop anything already logged today.
      if (eatenIds.contains(src.id)) continue;

      // 2) Diet-preference hard filter.
      if (!_passesDiet(src, diet)) continue;

      double score = 0;

      // 3) Calorie fit.
      final kcal = src.kcalPerServing;
      if (slotTarget <= 0) {
        // No budget left — accept anything tiny.
        score += kcal <= 100 ? 0.5 : 0;
      } else {
        final diff = (kcal - slotTarget).abs();
        final norm = (diff / slotTarget).clamp(0.0, 1.0);
        score += (1.0 - norm);
        if (kcal <= slotTarget) score += 0.2; // under-budget bonus
      }

      // 4) Meal-type soft bias.
      score += _mealTypeBias(src.category, mealType);

      // 5) Goal-aware macro tiebreaker.
      if (goal == 'lose') {
        final proteinDensity =
            (src.proteinG * 4) / (kcal <= 0 ? 1 : kcal);
        score += proteinDensity * 0.3;
      } else if (goal == 'gain') {
        // Slight kcal-density preference for gainers.
        score += (kcal / 500.0).clamp(0.0, 0.3);
      }

      // 6) Cap food kcal for snack slot (don't suggest 600 kcal as snack).
      if (mealType == 'snack' && kcal > 350) score -= 0.5;

      scored.add(_Scored(src, score));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));

    // Take top 3, but make sure each slot has at least one item even if
    // the diet filter removed most candidates.
    final top = scored.take(3).map((s) => _toLegacy(s.src)).toList();
    if (top.isEmpty) {
      // Fallback: take the first 3 non-eaten items from the BD library
      // regardless of diet (best-available).
      for (final src in bd.BdFoodLibrary.all) {
        if (eatenIds.contains(src.id)) continue;
        top.add(_toLegacy(src));
        if (top.length >= 3) break;
      }
    }
    return top;
  }

  // -------------------------------------------------------------------
  //  Diet filter
  // -------------------------------------------------------------------

  static bool _passesDiet(bd.FoodItem src, String diet) {
    final cat = src.category.toLowerCase();
    final name = src.nameEn.toLowerCase();

    switch (diet) {
      case 'vegan':
        if (cat == 'meat' || cat == 'fish' || cat == 'dairy') return false;
        if (name.contains('egg') ||
            name.contains('milk') ||
            name.contains('curd') ||
            name.contains('cheese') ||
            name.contains('doi')) {
          return false;
        }
        return true;
      case 'vegetarian':
        if (cat == 'meat' || cat == 'fish') return false;
        return true;
      case 'halal':
        // BD food library is implicitly halal — no pork.
        return true;
      case 'none':
      case '':
      default:
        return true;
    }
  }

  // -------------------------------------------------------------------
  //  Meal-type bias
  // -------------------------------------------------------------------

  static double _mealTypeBias(String category, String mealType) {
    final cat = category.toLowerCase();
    switch (mealType) {
      case 'breakfast':
        if (cat == 'dairy' || cat == 'fruit' || cat == 'drink') return 0.15;
        if (cat == 'rice') return 0.10;
        if (cat == 'curry' || cat == 'fish') return -0.10;
        return 0;
      case 'lunch':
        if (cat == 'rice' || cat == 'curry' || cat == 'fish' ||
            cat == 'meat' || cat == 'vegetable') {
          return 0.15;
        }
        if (cat == 'snacks' || cat == 'street_food') return -0.10;
        return 0;
      case 'dinner':
        if (cat == 'curry' || cat == 'fish' || cat == 'vegetable') {
          return 0.15;
        }
        if (cat == 'street_food' || cat == 'snacks') return -0.10;
        return 0;
      case 'snack':
        if (cat == 'snacks' ||
            cat == 'street_food' ||
            cat == 'fruit' ||
            cat == 'drink') {
          return 0.20;
        }
        if (cat == 'rice' || cat == 'curry') return -0.10;
        return 0;
      default:
        return 0;
    }
  }

  static api.FoodItem _toLegacy(bd.FoodItem src) {
    return api.FoodItem(
      id: src.id,
      nameEn: src.nameEn,
      nameBn: src.nameBn,
      category: src.category,
      servingG: src.servingG,
      kcalPerServing: src.kcalPerServing,
      proteinG: src.proteinG,
      carbsG: src.carbsG,
      fatG: src.fatG,
      fiberG: src.fiberG,
    );
  }

  static String _labelFor(String type) {
    switch (type) {
      case 'breakfast':
        return 'Breakfast';
      case 'lunch':
        return 'Lunch';
      case 'dinner':
        return 'Dinner';
      default:
        return 'Snack';
    }
  }
}

class _Scored {
  const _Scored(this.src, this.score);
  final bd.FoodItem src;
  final double score;
}
