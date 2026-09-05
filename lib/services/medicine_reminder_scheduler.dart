/// Medicine reminder scheduler.
///
/// Mirrors the `WaterTaskScheduler` singleton pattern. Responsibilities:
///
///   * On `start()` and on every `AppEvents.medicineChanged` bump,
///     re-fetch today's medicines and the `get_medicine_doses` server
///     data, build the list of pending reminders via
///     `TaskScheduleBuilder.buildMedicineTasks`, and hand them to the
///     facade.
///   * On `onDoseTaken(medicineId, scheduledTime)`, cancel just that
///     one reminder via `LocalNotifications.cancelByGroupKey`. We don't
///     re-schedule here — the next `AppEvents.medicineChanged` bump
///     (which fires when the dose is saved) will reconcile.
///
/// **Default-on**: medicine reminders ship enabled. Users can disable
/// via the settings sheet (`reminders.medicine.enabled` flag), but
/// unlike the other categories the toggle defaults to true.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_events.dart';
import 'local_notifications.dart';
import 'supabase_service.dart';
import 'task_schedule_builder.dart';

class MedicineReminderScheduler {
  MedicineReminderScheduler._();
  static final MedicineReminderScheduler instance =
      MedicineReminderScheduler._();

  static const String _kEnabledKey = 'reminders.medicine.enabled';

  bool _running = false;
  bool _enabled = true;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _enabled = await _readEnabled();
    AppEvents.medicineChanged.addListener(_onChanged);
    // Day rollover: when the calendar flips past midnight, today's
    // slots are all in the past — `buildMedicineTasks` would return an
    // empty list and tomorrow would never get scheduled. The 1-min
    // heartbeat in `WaterTaskScheduler` publishes `dayChanged`; we
    // re-subscribe here so medicine alarms survive a quiet overnight.
    AppEvents.dayChanged.addListener(_onDayChanged);
    await reschedule();
  }

  void stop() {
    _running = false;
    AppEvents.medicineChanged.removeListener(_onChanged);
    AppEvents.dayChanged.removeListener(_onDayChanged);
  }

  bool get enabled => _enabled;

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabledKey, value);
    if (value) {
      await reschedule();
    } else {
      await LocalNotifications.instance.cancelByTaskType(TaskType.medicine);
    }
  }

  /// Called by the medicine screen when a dose is marked taken — drop
  /// just that reminder without disturbing the rest.
  Future<void> onDoseTaken(String medicineId) async {
    await LocalNotifications.instance
        .cancelByGroupKey(TaskType.medicine, medicineId);
  }

  void _onChanged() {
    if (!_running) return;
    unawaited(reschedule());
  }

  /// Fires at midnight (from `WaterTaskScheduler`'s heartbeat). Without
  /// this listener the scheduler only ever ran on app start or on a
  /// medicine edit, so once today's slots passed the next day's
  /// alarms were never queued.
  void _onDayChanged() {
    if (!_running) return;
    unawaited(reschedule());
  }

  Future<void> reschedule() async {
    if (!_enabled) {
      await LocalNotifications.instance.cancelByTaskType(TaskType.medicine);
      return;
    }
    try {
      // Always cancel-and-rebuild so we don't pile up stale reminders
      // across days.
      await LocalNotifications.instance.cancelByTaskType(TaskType.medicine);

      final meds = await SupabaseService.listMedicines();
      final active = meds.where((m) => m.isActive).toList(growable: false);

      // Use today-local so 08:00 is today-not-yesterday.
      final now = DateTime.now();
      final tasks = buildMedicineTasks(
        medicines: active,
        now: now,
      );
      await LocalNotifications.instance.scheduleAll(tasks);
      debugPrint('💊 MedicineReminderScheduler: scheduled ${tasks.length}');
    } catch (e, st) {
      debugPrint('💊 MedicineReminderScheduler.reschedule failed: $e\n$st');
    }
  }

  Future<bool> _readEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Default = true (medicine is always-on).
      return prefs.getBool(_kEnabledKey) ?? true;
    } catch (_) {
      return true;
    }
  }
}
