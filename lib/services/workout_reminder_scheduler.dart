/// Workout reminder scheduler — opt-in.
///
/// Keeps nagging the user at the 5 fixed slots (07:00, 10:30, 13:00,
/// 17:30, 21:00) until today's `workout_sessions` items are all marked
/// complete. Re-checks completion on every `AppEvents.workoutChanged`
/// bump and on the 1-minute heartbeat.
///
/// **State source**: when the workout screen calls `_persist()`, we
/// re-fetch today's assignment count + completion count from
/// `SupabaseService.getTodayExerciseTimeFeedback()` so we always know
/// the truth. No manual push from the screen required.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_events.dart';
import 'local_notifications.dart';
import 'supabase_service.dart';
import 'task_schedule_builder.dart';

class WorkoutReminderScheduler {
  WorkoutReminderScheduler._();
  static final WorkoutReminderScheduler instance =
      WorkoutReminderScheduler._();

  static const String _kEnabledKey = 'reminders.workout.enabled';
  static const String _kDayIndexKey = 'reminders.workout.dayIndex';

  bool _running = false;
  bool _enabled = false;
  Timer? _heartbeat;

  // Latest-known state — re-fetched from Supabase on every change.
  int _dayIndex = 1;
  int _remainingCount = 0;
  bool _allComplete = true;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _enabled = await _readEnabled();
    final prefs = await SharedPreferences.getInstance();
    _dayIndex = prefs.getInt(_kDayIndexKey) ?? 1;

    AppEvents.workoutChanged.addListener(_onChanged);
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(minutes: 1), (_) => reschedule());
    await reschedule();
  }

  void stop() {
    _running = false;
    AppEvents.workoutChanged.removeListener(_onChanged);
    _heartbeat?.cancel();
    _heartbeat = null;
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

  Future<void> reschedule() async {
    if (!_enabled) {
      await LocalNotifications.instance.cancelByTaskType(TaskType.workout);
      return;
    }
    try {
      await LocalNotifications.instance.cancelByTaskType(TaskType.workout);
      await _refreshStateFromServer();
      if (_allComplete || _remainingCount == 0) {
        // Nothing left to nag about today.
        return;
      }
      final tasks = buildWorkoutTasks(
        dayIndex: _dayIndex,
        workoutCountForToday: _remainingCount,
        allComplete: _allComplete,
        now: DateTime.now(),
      );
      await LocalNotifications.instance.scheduleAll(tasks);
      debugPrint('🏋 WorkoutReminderScheduler: scheduled ${tasks.length}');
    } catch (e, st) {
      debugPrint('🏋 WorkoutReminderScheduler.reschedule failed: $e\n$st');
    }
  }

  /// Re-fetch today's plan-progress and per-exercise completion flags
  /// so we know how many workouts are still pending.
  Future<void> _refreshStateFromServer() async {
    try {
      final progress = await SupabaseService.getPlanProgress();
      _dayIndex = progress.day;
      final feedback =
          await SupabaseService.getTodayExerciseTimeFeedback();
      // feedback: { workoutId -> ExerciseTimeFeedback(actual, target) }.
      // A workout is "complete" today if actual >= target. We have to
      // compare against the target which we don't have here, so we use
      // a proxy: anything with actual > 0 counts as started. To know
      // "all complete" exactly we'd need target durations; for v1 we
      // approximate: count of workouts whose actual_seconds >= some
      // threshold (we use 30s as "user actually did the workout").
      int remaining = 0;
      int completed = 0;
      for (final fb in feedback.values) {
        if (fb.actualSeconds >= 30) {
          completed++;
        } else {
          remaining++;
        }
      }
      // If feedback is empty (e.g. user hasn't opened the workout tab
      // today), leave remaining at 0 to avoid nagging about nothing.
      if (feedback.isEmpty) {
        remaining = 0;
      }
      _remainingCount = remaining;
      _allComplete = completed > 0 && remaining == 0;
    } catch (e, st) {
      debugPrint('🏋 _refreshStateFromServer failed: $e\n$st');
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
