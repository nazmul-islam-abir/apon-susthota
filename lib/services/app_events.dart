import 'package:flutter/foundation.dart';

/// Simple in-process pub/sub. Screens subscribe in `initState` and refresh
/// themselves when the relevant counter changes.
///
/// We keep this intentionally minimal — no streams, no codegen. A single
/// `ValueNotifier<int>` per topic is enough: bumping the value triggers
/// every listener, which can then re-fetch whatever it needs.
class AppEvents {
  AppEvents._();

  /// Bumped whenever the user saves their clinical profile. Listeners
  /// (meal plan, dashboard) should re-fetch and re-classify.
  static final ValueNotifier<int> profileChanged = ValueNotifier<int>(0);

  /// Bumped whenever the user logs a meal (eaten / swap / off-plan).
  /// Listeners can re-pull aggregates.
  static final ValueNotifier<int> mealLogged = ValueNotifier<int>(0);

  /// Bumped whenever a medicine is created / updated / deleted or a
  /// dose is marked taken. The medicine screen and the dashboard
  /// adherence tile both listen and re-fetch.
  static final ValueNotifier<int> medicineChanged = ValueNotifier<int>(0);

  /// Bumped whenever a workout session is started, an item is finished
  /// or the session is wrapped up. The workout screen and dashboard
  /// adherence tile both listen and re-fetch.
  static final ValueNotifier<int> workoutChanged = ValueNotifier<int>(0);

  /// Bumped whenever the user logs water (tap-and-hold on the water
  /// screen). The dashboard water card listens and re-fetches today's
  /// intake without round-tripping the whole dashboard.
  static final ValueNotifier<int> waterChanged = ValueNotifier<int>(0);

  /// Bumped whenever the user transitions to a new calendar day.
  /// Both the water screen and dashboard subscribe so they can reset
  /// their local "today" state and re-fetch from a clean slate.
  static final ValueNotifier<DateTime> waterDayChanged =
      ValueNotifier<DateTime>(_todayLocal());

  /// Bumped whenever today's AI-chat prompt quota changes (after a
  /// successful send or after `AiChatQuotaCache.warmUp()` resolves).
  /// Listeners can refresh a "৩/৫ আজ" badge or disable the input.
  static final ValueNotifier<int> aiChatQuotaChanged = ValueNotifier<int>(0);

  /// Bumped whenever the user logs or edits today's mood + health
  /// check-in. The dashboard banner listens and re-fetches so the
  /// "logged 🙂 at 9:14 PM" row updates instantly.
  static final ValueNotifier<int> moodChanged = ValueNotifier<int>(0);

  /// Returns today's date at midnight in the device's local time.
  /// Used by both the publisher and subscribers so they all agree on
  /// what "today" means (Postgres queries server-side use Asia/Dhaka).
  static DateTime _todayLocal() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Day rollover helper: if [previous] and [current] differ in
  /// calendar day, fire [waterDayChanged] and return `true`. The
  /// caller is expected to also persist yesterday's snapshot via
  /// `SupabaseService.resetDailyWaterTask` if needed.
  static bool maybeNotifyDayChange({
    required DateTime previous,
    required DateTime current,
  }) {
    final prev = DateTime(previous.year, previous.month, previous.day);
    final curr = DateTime(current.year, current.month, current.day);
    if (prev.isAtSameMomentAs(curr)) return false;
    waterDayChanged.value = curr;
    return true;
  }

  static void notifyProfileChanged() => profileChanged.value++;
  static void notifyMealLogged() => mealLogged.value++;
  static void notifyMedicineChanged() => medicineChanged.value++;
  static void notifyWorkoutChanged() => workoutChanged.value++;
  static void notifyWaterChanged() => waterChanged.value++;
  static void notifyAiChatQuotaChanged() => aiChatQuotaChanged.value++;
  static void notifyMoodChanged() => moodChanged.value++;
}
