/// Water reminder scheduler — opt-in.
///
/// Spreads 8 reminders between the user's inferred wake window (or
/// 08:00–22:00 default). Inferring the window from medicine times
/// means the user doesn't have to configure wake hours — we just
/// match their existing day rhythm.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_events.dart';
import 'local_notifications.dart';
import 'supabase_service.dart';
import 'task_schedule_builder.dart';

class WaterReminderScheduler {
  WaterReminderScheduler._();
  static final WaterReminderScheduler instance = WaterReminderScheduler._();

  static const String _kEnabledKey = 'reminders.water.enabled';

  bool _running = false;
  bool _enabled = false;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _enabled = await _readEnabled();
    AppEvents.waterChanged.addListener(_onChanged);
    AppEvents.waterDayChanged.addListener(_onDayChanged);
    await reschedule();
  }

  void stop() {
    _running = false;
    AppEvents.waterChanged.removeListener(_onChanged);
    AppEvents.waterDayChanged.removeListener(_onDayChanged);
  }

  bool get enabled => _enabled;

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabledKey, value);
    await reschedule();
  }

  void _onChanged() {
    if (!_running) return;
    unawaited(reschedule());
  }

  void _onDayChanged() {
    if (!_running) return;
    unawaited(reschedule());
  }

  Future<void> reschedule() async {
    if (!_enabled) {
      await LocalNotifications.instance.cancelByTaskType(TaskType.water);
      return;
    }
    try {
      await LocalNotifications.instance.cancelByTaskType(TaskType.water);

      final today = DateTime.now();
      final meds = await SupabaseService.listMedicines();
      final inferred = inferWakeWindowFromMeds(meds, today);
      final window = inferred ?? defaultWakeWindow(today);

      final tasks = buildWaterTasks(
        now: DateTime.now(),
        wakeFrom: window.wakeFrom,
        wakeTo: window.wakeTo,
      );
      await LocalNotifications.instance.scheduleAll(tasks);
      debugPrint('💧 WaterReminderScheduler: scheduled ${tasks.length}');
    } catch (e, st) {
      debugPrint('💧 WaterReminderScheduler.reschedule failed: $e\n$st');
    }
  }

  Future<bool> _readEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kEnabledKey) ?? false;
    } catch (_) {
      return false;
    }
  }
}
