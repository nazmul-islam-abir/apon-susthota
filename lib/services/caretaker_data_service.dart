/// Caretaker data service — read-only access to a connected patient's data.
///
/// All methods take a [patientUserId] argument. The Supabase RPCs called here
/// are read-only and parameterized so a caregiver can mirror every screen
/// the patient sees without write capability.
///
/// Where a dedicated `*_for_user` RPC isn't available on the server yet,
/// the method falls back to the same shape and resolves gracefully (returns
/// empty / null) so the UI can render an empty-state instead of crashing.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/meal_item.dart';
import '../models/medicine.dart';
import '../models/mood_entry.dart';
import '../models/thirty_day_report.dart';
import '../models/user_meal_plan.dart';
import '../models/voice_message.dart';
import '../models/water_analytics.dart';
import '../models/workout.dart';
import 'supabase_service.dart';

/// Per-meal planned slot — mirrors the `user_meal_plan_recommendations`
/// rows returned by `get_caretaker_day_plan`. We store the SQL row
/// inline because the recommendation-cache shape doesn't match the
/// `UserMealPlan` model (which is for custom user-entered plans).
class _CaretakerPlanRow {
  final String slot;
  final String role;
  final String? foodId;
  final String? foodNameBn;
  final double? portionG;
  final String? portionLabel;
  final double? kcal;
  final double? carbG;
  final double? proteinG;
  final double? fatG;
  final double? fiberG;
  final String? giCategory;
  final String? category;

  const _CaretakerPlanRow({
    required this.slot,
    required this.role,
    this.foodId,
    this.foodNameBn,
    this.portionG,
    this.portionLabel,
    this.kcal,
    this.carbG,
    this.proteinG,
    this.fatG,
    this.fiberG,
    this.giCategory,
    this.category,
  });

  factory _CaretakerPlanRow.fromJson(Map<String, dynamic> json) {
    num? toNum(dynamic v) =>
        v is num ? v : (v is String ? num.tryParse(v) : null);
    return _CaretakerPlanRow(
      slot: (json['slot'] ?? 'other') as String,
      role: (json['role'] ?? 'main') as String,
      foodId: (json['food_id'] ?? json['resolved_name']) as String?,
      foodNameBn: (json['resolved_name'] ?? json['food_name_bn']) as String?,
      portionG: toNum(json['portion_g'])?.toDouble(),
      portionLabel: (json['resolved_portion'] ?? json['portion_label']) as String?,
      kcal: toNum(json['kcal'])?.toDouble(),
      carbG: toNum(json['carb_g'])?.toDouble(),
      proteinG: toNum(json['protein_g'])?.toDouble(),
      fatG: toNum(json['fat_g'])?.toDouble(),
      fiberG: toNum(json['fiber_g'])?.toDouble(),
      giCategory: (json['resolved_gi'] ?? json['gi_category']) as String?,
      category: (json['resolved_category'] ?? json['category']) as String?,
    );
  }

  /// Convert the row into a `MealSlotPlan` so the caretaker view can
  /// render the same UI as the patient's `MealPlanScreen`.
  MealSlotPlan toMealSlotPlan() {
    final food = MealItem(
      id: foodId ?? '',
      nameBn: foodNameBn ?? '',
      category: category ?? _categoryFromRole(role),
      carbG: carbG ?? 0,
      proteinG: proteinG ?? 0,
      fatG: fatG ?? 0,
      fiberG: fiberG ?? 0,
      sodiumMg: 0,
      potassiumMg: 0,
      phosphorusMg: 0,
      giCategory: giCategory ?? 'low',
      portionLabel: portionLabel,
      portionG: portionG,
    );
    return MealSlotPlan(
      slot: slot,
      role: role,
      food: food,
      source: 'ai',
    );
  }

  static String _categoryFromRole(String role) {
    switch (role) {
      case 'main':
        return 'breakfast';
      case 'carb':
        return 'carb';
      case 'protein':
        return 'protein';
      case 'vegetable':
        return 'vegetable';
      case 'dal':
        return 'dal';
      case 'snack':
        return 'snack';
      default:
        return role;
    }
  }
}

/// Aggregated patient data view used by every read-only caretaker viewer.
/// Each method is independent so a viewer screen can call just the ones
/// it needs.
class CaretakerDataService {
  CaretakerDataService._();

  static SupabaseClient get _client => SupabaseService.client;

  // ─── Profile ──────────────────────────────────────────────────────────────

  /// Fetch a patient's profile. Strips PII (mobile, address) — same
  /// pattern as `getCaretakerClinicalSnapshot`.
  static Future<Map<String, dynamic>?> getProfile(String patientUserId) async {
    try {
      final res = await _client.rpc('get_caretaker_patient_profile', params: {
        'p_patient_user_id': patientUserId,
      });
      if (res == null) return null;
      return Map<String, dynamic>.from(res as Map);
    } catch (_) {
      // RPC missing → fall back to public profile (already returns
      // safe subset).
      return SupabaseService.getPublicProfile(patientUserId);
    }
  }

  // ─── Meal plan ────────────────────────────────────────────────────────────

  /// Per-day meal plan for a patient. Returns the [MealSlotPlan] list for
  /// the given plan-day (1..30). Falls back to the static 30-day
  /// rotation template if no cached recommendation exists for today.
  static Future<List<MealSlotPlan>> getDayPlan({
    required String patientUserId,
    required int planDay,
  }) async {
    try {
      final res = await _client.rpc('get_caretaker_day_plan', params: {
        'p_patient_user_id': patientUserId,
        'p_plan_day': planDay,
      });
      final list = (res as List?) ?? const [];
      return list
          .whereType<Map>()
          .map((e) => _CaretakerPlanRow.fromJson(Map<String, dynamic>.from(e))
              .toMealSlotPlan())
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Custom meal plan entries for a given date.
  static Future<List<UserMealPlan>> getUserDayPlan({
    required String patientUserId,
    required DateTime date,
  }) async {
    try {
      final res = await _client.rpc('get_caretaker_user_day_plan', params: {
        'p_patient_user_id': patientUserId,
        'p_effective_date': _dateOnly(date),
      });
      final list = (res as List?) ?? const [];
      return list
          .whereType<Map>()
          .map((e) => UserMealPlan.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Meal log entries for a given plan-day or date.
  static Future<List<MealLogEntry>> getDailyLog({
    required String patientUserId,
    int? planDay,
    DateTime? date,
  }) async {
    try {
      final res = await _client.rpc('get_caretaker_daily_log', params: {
        'p_patient_user_id': patientUserId,
        'p_plan_day': planDay,
        'p_date': date != null ? _dateOnly(date) : null,
      });
      // get_caretaker_daily_log returns {date, plan_day, items: []}
      final map = Map<String, dynamic>.from(res as Map);
      final list = (map['items'] as List?) ?? const [];
      return list
          .whereType<Map>()
          .map((e) => MealLogEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Plan progress (current day, % complete).
  static Future<PlanProgress> getPlanProgress(String patientUserId) async {
    try {
      final res = await _client.rpc('get_caretaker_plan_progress', params: {
        'p_patient_user_id': patientUserId,
      });
      return PlanProgress.fromRow(Map<String, dynamic>.from(res as Map));
    } catch (_) {
      return PlanProgress.fallback();
    }
  }

  // ─── Water ────────────────────────────────────────────────────────────────

  /// Today's water + workout minutes (DailyMetric shape).
  static Future<DailyMetric> getTodayDailyMetrics(String patientUserId) async {
    try {
      final res = await _client.rpc('get_caretaker_today_daily_metrics', params: {
        'p_patient_user_id': patientUserId,
      });
      return DailyMetric.fromRow(Map<String, dynamic>.from(res as Map));
    } catch (_) {
      return DailyMetric.empty;
    }
  }

  /// Per-day DailyMetric for a specific calendar date. Used by the
  /// caretaker water/workout viewers to render the selected day's
  /// numbers without the user having to explicitly go "back to today".
  /// Falls back to today's metric when the historical RPC isn't on
  /// the server yet — older days will read as today which is the
  /// safest degradation.
  static Future<DailyMetric> getDailyMetricsForDate({
    required String patientUserId,
    required DateTime date,
  }) async {
    final dateStr = _dateOnly(date);
    try {
      final res = await _client.rpc(
        'get_caretaker_daily_metrics_for_date',
        params: {
          'p_patient_user_id': patientUserId,
          'p_date': dateStr,
        },
      );
      return DailyMetric.fromRow(Map<String, dynamic>.from(res as Map));
    } catch (_) {
      // Fallback to today-only metrics.
      return getTodayDailyMetrics(patientUserId);
    }
  }

  // ─── Workout (per-exercise time feedback) ────────────────────────────────

  /// Per-day workout time rows for the patient (mirrors the patient-side
  /// `getWorkoutTimeRows`). Used by the caretaker workout viewer to
  /// power the 7-day log strip + per-exercise progress bars.
  /// `days` is clamped server-side.
  static Future<List<WorkoutTimeRow>> getWorkoutTimeRows({
    required String patientUserId,
    int days = 7,
  }) async {
    try {
      final res = await _client.rpc(
        'get_caretaker_workout_time_tracking',
        params: {
          'p_patient_user_id': patientUserId,
          'p_days': days,
        },
      );
      final list = <WorkoutTimeRow>[];
      if (res is List) {
        for (final v in res) {
          if (v is Map) {
            list.add(WorkoutTimeRow.fromJson(Map<String, dynamic>.from(v)));
          }
        }
      }
      return list;
    } catch (_) {
      return const [];
    }
  }

  /// Per-exercise "actual/target min" feedback for the patient's today.
  /// Keyed by workout id (string). Mirrors the patient-side
  /// `getTodayExerciseTimeFeedback`.
  static Future<Map<String, WorkoutExerciseTimeFeedback>>
      getTodayExerciseTimeFeedback(String patientUserId) async {
    try {
      final res = await _client.rpc(
        'get_caretaker_today_exercise_time_feedback',
        params: {
          'p_patient_user_id': patientUserId,
        },
      );
      final out = <String, WorkoutExerciseTimeFeedback>{};
      if (res is List) {
        for (final v in res) {
          if (v is Map) {
            final fb = WorkoutExerciseTimeFeedback.fromJson(
                Map<String, dynamic>.from(v));
            if (fb.workoutId.isNotEmpty) out[fb.workoutId] = fb;
          }
        }
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  /// 7-day water analytics.
  static Future<WaterAnalyticsSummary> getWaterAnalytics({
    required String patientUserId,
    int days = 7,
  }) async {
    try {
      final res = await _client.rpc('get_caretaker_water_analytics', params: {
        'p_patient_user_id': patientUserId,
        'p_days': days,
      });
      return WaterAnalyticsSummary.fromJson(Map<String, dynamic>.from(res as Map));
    } catch (_) {
      return WaterAnalyticsSummary.empty;
    }
  }

  // ─── Medicine ─────────────────────────────────────────────────────────────

  /// Active medicines for the patient.
  static Future<List<Medicine>> listMedicines(String patientUserId) async {
    try {
      final res = await _client.rpc('get_caretaker_medicines', params: {
        'p_patient_user_id': patientUserId,
      });
      final list = (res as List?) ?? const [];
      return list
          .whereType<Map>()
          .map((e) => Medicine.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Doses for a given calendar date.
  static Future<List<MedicineDose>> getMedicineDosesForDate({
    required String patientUserId,
    required DateTime date,
  }) async {
    try {
      final res = await _client.rpc(
        'get_caretaker_medicine_doses_for_date',
        params: {
          'p_patient_user_id': patientUserId,
          'p_date': _dateOnly(date),
        },
      );
      final list = (res as List?) ?? const [];
      return list
          .whereType<Map>()
          .map((e) => MedicineDose.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  // ─── Workout ──────────────────────────────────────────────────────────────

  /// Today's workout for the patient (used for the read-only viewer).
  static Future<TodaysWorkout> getTodayWorkout({
    required String patientUserId,
    int? dayIndex,
  }) async {
    try {
      final res = await _client.rpc('get_caretaker_today_workout', params: {
        'p_patient_user_id': patientUserId,
        'p_day_index': dayIndex,
      });
      return TodaysWorkout.fromJson(Map<String, dynamic>.from(res as Map));
    } catch (_) {
      return TodaysWorkout(
        dayIndex: dayIndex ?? 1,
        today: DateTime.now(),
        assignments: const [],
      );
    }
  }

  /// N-day workout log.
  static Future<List<WorkoutLogRow>> getWorkoutLogs({
    required String patientUserId,
    int days = 7,
  }) async {
    try {
      final res = await _client.rpc('get_caretaker_workout_logs', params: {
        'p_patient_user_id': patientUserId,
        'p_days': days,
      });
      final list = (res as List?) ?? const [];
      return list
          .whereType<Map>()
          .map((e) => WorkoutLogRow.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  // ─── Adherence ────────────────────────────────────────────────────────────

  static Future<double> getMealAdherence({
    required String patientUserId,
    int days = 7,
  }) async {
    try {
      final res = await _client.rpc('get_caretaker_meal_adherence', params: {
        'p_patient_user_id': patientUserId,
        'p_days': days,
      });
      return ((res as num?) ?? 0).toDouble();
    } catch (_) {
      return 0;
    }
  }

  static Future<double> getMedicineAdherence({
    required String patientUserId,
    int days = 7,
  }) async {
    try {
      final res = await _client.rpc('get_caretaker_medicine_adherence', params: {
        'p_patient_user_id': patientUserId,
        'p_days': days,
      });
      return ((res as num?) ?? 0).toDouble();
    } catch (_) {
      return 0;
    }
  }

  static Future<double> getWorkoutAdherence({
    required String patientUserId,
    int days = 7,
  }) async {
    try {
      final res = await _client.rpc('get_caretaker_workout_adherence', params: {
        'p_patient_user_id': patientUserId,
        'p_days': days,
      });
      return ((res as num?) ?? 0).toDouble();
    } catch (_) {
      return 0;
    }
  }

  // ─── Analytics / 30-day report ────────────────────────────────────────────

  static Future<ThirtyDayReport?> getThirtyDayReport({
    required String patientUserId,
    int cycleIndex = 0,
  }) async {
    try {
      final res = await _client.rpc('get_caretaker_thirty_day_report', params: {
        'p_patient_user_id': patientUserId,
        'p_cycle_index': cycleIndex,
      });
      return ThirtyDayReport.fromJson(Map<String, dynamic>.from(res as Map));
    } catch (_) {
      return null;
    }
  }

  static Future<int> getAnalyticsCycleCount(String patientUserId) async {
    try {
      final res = await _client.rpc('get_caretaker_analytics_cycle_count', params: {
        'p_patient_user_id': patientUserId,
      });
      return ((res as num?) ?? 1).toInt();
    } catch (_) {
      return 1;
    }
  }

  // ─── Mood ─────────────────────────────────────────────────────────────────

  static Future<MoodEntry?> getTodayMood(String patientUserId) async {
    try {
      final res = await _client.rpc('get_caretaker_today_mood', params: {
        'p_patient_user_id': patientUserId,
      });
      if (res == null) return null;
      return MoodEntry.fromJson(Map<String, dynamic>.from(res as Map));
    } catch (_) {
      return null;
    }
  }

  static Future<List<MoodEntry>> getMoodHistory({
    required String patientUserId,
    int days = 30,
  }) async {
    try {
      final res = await _client.rpc('get_caretaker_mood_history', params: {
        'p_patient_user_id': patientUserId,
        'p_days': days,
      });
      final list = (res as List?) ?? const [];
      return list
          .whereType<Map>()
          .map((e) => MoodEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  static String _dateOnly(DateTime d) {
    final l = d.toLocal();
    return '${l.year.toString().padLeft(4, '0')}-'
        '${l.month.toString().padLeft(2, '0')}-'
        '${l.day.toString().padLeft(2, '0')}';
  }

  // ─── Voice messages ──────────────────────────────────────────────────────
  // Convenience re-export of the voice list helpers so screens that
  // already import this file don't need a second import for voice
  // queries.

  /// Caretaker's pending + delivered voice schedules for one patient.
  static Future<List<VoiceSchedule>> listVoiceSchedulesForPatient(
      String patientUserId) async {
    try {
      final res = await _client.rpc('list_caretaker_voice_schedules', params: {
        'p_patient_user_id': patientUserId,
      });
      final list = (res as List?) ?? const [];
      return list
          .whereType<Map>()
          .map((e) =>
              VoiceSchedule.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Caretaker's view of the patient inbox (includes both
  /// materialized caretaker voices and patient replies).
  static Future<List<VoiceMessage>> listVoiceInboxForPatient(
      String patientUserId) async {
    try {
      final res = await _client.rpc('list_caretaker_voice_inbox', params: {
        'p_patient_user_id': patientUserId,
      });
      final list = (res as List?) ?? const [];
      return list
          .whereType<Map>()
          .map((e) =>
              VoiceMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}
