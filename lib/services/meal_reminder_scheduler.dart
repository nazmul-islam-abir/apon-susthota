/// Meal reminder scheduler — opt-in.
///
/// Same shape as `MedicineReminderScheduler`. Listens to
/// `AppEvents.mealLogged` so any meal-tracking action triggers a
/// re-schedule (and so the day's reminders are cancelled if the user
/// has logged a meal via another surface — e.g. care-taker).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_events.dart';
import 'local_notifications.dart';
import 'task_schedule_builder.dart';

class MealReminderScheduler {
  MealReminderScheduler._();
  static final MealReminderScheduler instance = MealReminderScheduler._();

  static const String _kEnabledKey = 'reminders.meal.enabled';

  bool _running = false;
  bool _enabled = false;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _enabled = await _readEnabled();
    AppEvents.mealLogged.addListener(_onChanged);
    // Day rollover: see `MedicineReminderScheduler._onDayChanged` for
    // the full rationale — without this, once today's meal slots have
    // all passed (e.g. after dinner at 20:30) the next day's breakfast
    // reminder is never queued.
    AppEvents.dayChanged.addListener(_onDayChanged);
    await reschedule();
  }

  void stop() {
    _running = false;
    AppEvents.mealLogged.removeListener(_onChanged);
    AppEvents.dayChanged.removeListener(_onDayChanged);
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
      await LocalNotifications.instance.cancelByTaskType(TaskType.meal);
      return;
    }
    try {
      await LocalNotifications.instance.cancelByTaskType(TaskType.meal);
      final tasks = buildMealTasks(now: DateTime.now());
      await LocalNotifications.instance.scheduleAll(tasks);
      debugPrint('🍽 MealReminderScheduler: scheduled ${tasks.length}');
    } catch (e, st) {
      debugPrint('🍽 MealReminderScheduler.reschedule failed: $e\n$st');
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
