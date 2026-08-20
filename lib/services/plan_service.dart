import 'package:flutter/foundation.dart';

import '../models/meal_item.dart';
import 'supabase_service.dart';

/// Plan-loading facade used by the meal plan + dashboard screens.
///
/// Wraps the v2 RPCs in `supabasesql/24_daily_recommendation_v2.sql`:
///   • [getDayPlanWithFallback] — read cache, fall back to dynamic generator
///   • [ensureUpcomingPlans]    — pre-bake the next N days
///   • [invalidatePlanCache]    — clear cached plans after a profile update
///   • [getAlternativesV2]      — filtered swap alternatives
///   • [classifyUserV2]         — full clinical classification JSON
///
/// Falls back to the legacy v1 RPCs (`get_daily_recommendation_with_overrides`,
/// `get_daily_recommendation`, `food_alternatives_for`) if the project
/// hasn't run the new SQL files yet. Logs the fallback so it's easy to
/// spot in dev.
class PlanService {
  PlanService._();

  // ── In-memory day cache so we don't re-fetch on every rebuild ─────────
  static final Map<String, _CachedDay> _cache = {};
  static const Duration _ttl = Duration(minutes: 10);

  /// Clears the in-memory cache. Called when the profile changes so we
  /// re-read with the new classification.
  static void clearCache() => _cache.clear();

  /// Loads the plan for [day] (1..30). Reads cache first; on miss calls
  /// the v2 RPC and persists the result. The RPC itself caches into
  /// `user_meal_plan_recommendations`, so subsequent loads are fast even
  /// across devices.
  static Future<DayPlan> getDayPlan(int day) async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) throw StateError('No authenticated user.');
    final key = '$userId::$day';
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.fetchedAt) < _ttl) {
      return hit.plan;
    }
    final plan = await _loadFromServer(day);
    _cache[key] = _CachedDay(plan: plan, fetchedAt: DateTime.now());
    return plan;
  }

  /// Forces a refresh — bypasses the in-memory TTL.
  static Future<DayPlan> refreshDayPlan(int day) async {
    final userId = SupabaseService.currentUser?.id;
    if (userId != null) _cache.remove('$userId::$day');
    final plan = await _loadFromServer(day);
    final id = SupabaseService.currentUser?.id;
    if (id != null) {
      _cache['$id::$day'] = _CachedDay(plan: plan, fetchedAt: DateTime.now());
    }
    return plan;
  }

  static Future<DayPlan> _loadFromServer(int day) async {
    try {
      final raw = await SupabaseService.getDayPlanWithFallback(day);
      return DayPlan.fromV2Json(raw);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PlanService] v2 RPC failed, falling back to v1: $e');
      }
      try {
        final raw = await SupabaseService.getDailyRecommendationWithOverrides(day);
        return DayPlan.fromLegacyJson(raw);
      } catch (e2) {
        if (kDebugMode) {
          debugPrint('[PlanService] v1 fallback also failed: $e2');
        }
        rethrow;
      }
    }
  }

  /// Pre-bakes the next [days] days starting today. Fire-and-forget;
  /// errors are swallowed (logged in debug).
  static Future<void> ensureUpcomingPlans({int days = 7}) async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) return;
    try {
      await SupabaseService.ensureUpcomingPlans(days: days);
    } catch (e) {
      if (kDebugMode) debugPrint('[PlanService] ensureUpcomingPlans failed: $e');
    }
  }

  /// Clears server-side cache for [fromDate] onward. Call after the
  /// user updates their profile so the next load picks up the new
  /// classification.
  static Future<void> invalidateCache({DateTime? fromDate}) async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) return;
    try {
      await SupabaseService.invalidatePlanCache(fromDate: fromDate);
      clearCache();
    } catch (e) {
      if (kDebugMode) debugPrint('[PlanService] invalidateCache failed: $e');
    }
  }

  /// Alternatives filtered through the user's classification.
  /// Falls back to unfiltered v1 alternatives if v2 isn't deployed.
  static Future<List<MealItem>> getAlternatives(String foodId,
      {int limit = 4}) async {
    try {
      return await SupabaseService.getAlternativesV2(foodId, limit: limit);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PlanService] alternatives v2 failed, falling back: $e');
      }
      return SupabaseService.getAlternatives(foodId, limit: limit);
    }
  }

  /// Full clinical classification JSON from the server. Falls back to
  /// v1 if v2 isn't deployed.
  static Future<Map<String, dynamic>> classifyUser() async {
    try {
      return await SupabaseService.classifyUserV2();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PlanService] classify v2 failed, falling back: $e');
      }
      return SupabaseService.classifyUser();
    }
  }
}

class _CachedDay {
  final DayPlan plan;
  final DateTime fetchedAt;
  _CachedDay({required this.plan, required this.fetchedAt});
}

/// Strongly-typed day plan returned by [PlanService.getDayPlan].
class DayPlan {
  final int day;
  final DateTime? date;
  final List<MealSlotPlan> slots;
  final Map<String, dynamic> totals;
  final String? source; // 'cache' | 'generated'
  final String? classificationTier;

  const DayPlan({
    required this.day,
    required this.slots,
    this.date,
    this.totals = const {},
    this.source,
    this.classificationTier,
  });

  double get totalCarb =>
      slots.fold(0.0, (s, p) => s + p.food.carbG);
  double get totalProtein =>
      slots.fold(0.0, (s, p) => s + p.food.proteinG);
  double get totalFat => slots.fold(0.0, (s, p) => s + p.food.fatG);
  double get totalFiber => slots.fold(0.0, (s, p) => s + p.food.fiberG);
  double get totalSodium => slots.fold(0.0, (s, p) => s + p.food.sodiumMg);
  double get totalKcal {
    return slots.fold(0.0, (s, p) {
      final f = p.food;
      return s +
          (f.carbG * 4) +
          (f.proteinG * 4) +
          (f.fatG * 9);
    });
  }

  factory DayPlan.fromV2Json(Map<String, dynamic> json) {
    final rawSlots = (json['slots'] as List?) ?? (json['plan'] as List?) ?? [];
    final slots = rawSlots
        .map((e) => MealSlotPlan.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return DayPlan(
      day: (json['day'] ?? json['plan_day'] ?? 1) as int,
      date: json['date'] != null
          ? DateTime.tryParse(json['date'].toString())
          : null,
      slots: slots,
      totals: (json['totals'] as Map?)?.cast<String, dynamic>() ?? const {},
      source: json['source'] as String?,
      classificationTier: json['classification_tier'] as String?,
    );
  }

  /// Parses the legacy v1 RPC shape (`{plan: [{slot, role, food, alts}]}`)
  /// so callers that haven't yet deployed v2 SQL still work.
  factory DayPlan.fromLegacyJson(Map<String, dynamic> json) {
    final rawSlots = (json['plan'] as List?) ?? (json['slots'] as List?) ?? [];
    final slots = rawSlots
        .map((e) => MealSlotPlan.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return DayPlan(
      day: (json['plan_day'] ?? json['day'] ?? 1) as int,
      slots: slots,
      source: 'legacy',
    );
  }
}