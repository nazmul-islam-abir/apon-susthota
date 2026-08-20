/// Daily water-task scheduler.
///
/// Responsible for two related jobs:
///
///   1. **Day rollover detection.** When the app starts (or resumes
///      after a long background stretch), we compare the device's
///      current local date against the last-known date persisted in
///      `SharedPreferences`. If they differ, we treat the previous
///      date as "done" and:
///
///        a. Call `SupabaseService.resetDailyWaterTask(forDate: yest)`
///           so the server-side `daily_water_summary` row is finalised
///           for that day (so analytics can show it).
///        b. Fire `AppEvents.waterDayChanged` so any listening screen
///           (water screen, dashboard card) clears its local
///           "today" state and re-fetches from zero.
///
///   2. **Self-rescheduling timer.** A 1-minute periodic timer keeps
///      re-checking the date so the rollover happens even if the app
///      is left running overnight (e.g. user keeps the tablet plugged
///      in on the dresser). The timer is cheap (one date compare per
///      tick) and lives for the lifetime of the singleton.
///
/// We deliberately do not use any platform-level background scheduler
/// (`workmanager`, `flutter_local_notifications`): the app's intended
/// usage pattern is "elderly user opens the app once in the morning",
/// so we only need to catch the rollover when the app is foregrounded.
/// If that assumption changes later, plug a `WorkManager` worker in
/// here.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_events.dart';
import 'supabase_service.dart';

/// SharedPreferences key for the last calendar day on which the
/// scheduler ran. Stored as an ISO yyyy-MM-dd string so we don't have
/// to worry about timezones — the value is whatever the device's local
/// "midnight" was when we last checked.
const String _kLastRolloverDateKey = 'water.last_rollover_date';

class WaterTaskScheduler {
  WaterTaskScheduler._();
  static final WaterTaskScheduler instance = WaterTaskScheduler._();

  Timer? _tick;
  bool _running = false;

  /// Last calendar day (midnight, local) we saw during a tick. Cached
  /// in-memory so we don't hit SharedPreferences on every 1-minute
  /// heartbeat once we've already rolled over.
  DateTime? _lastSeenDay;

  /// Start the scheduler. Idempotent — safe to call from `main()`.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _lastSeenDay = await _readPersistedDay();
    await _checkAndRollover(reason: 'startup');
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) async {
      await _checkAndRollover(reason: 'tick');
    });
  }

  /// Stop the scheduler (mainly for tests).
  void stop() {
    _tick?.cancel();
    _tick = null;
    _running = false;
  }

  /// Manually force a re-check. Useful right after login (in case the
  /// user authenticated after `start()`) and on `AppLifecycleState`
  /// `resumed`.
  Future<void> ping() => _checkAndRollover(reason: 'manual');

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<void> _checkAndRollover({required String reason}) async {
    final today = _localToday();
    final last = _lastSeenDay;
    if (last != null && !_isDifferentDay(last, today)) {
      return; // Still the same day — nothing to do.
    }

    debugPrint('💧 WaterTaskScheduler: rollover detected (reason=$reason, '
        'last=${last?.toIso8601String()}, today=${today.toIso8601String()})');

    if (last != null) {
      // We crossed a day boundary. Persist yesterday's snapshot on the
      // server so analytics can show the now-closed day.
      // We retry each missing day in case the app was off for >1 day.
      var cursor = last.add(const Duration(days: 1));
      while (!_isDifferentDay(cursor, today)) {
        try {
          final summary = await SupabaseService.resetDailyWaterTask(
            forDate: cursor,
          );
          debugPrint('💧 WaterTaskScheduler: reset summary for '
              '${cursor.toIso8601String().substring(0, 10)} -> $summary');
        } catch (e, st) {
          debugPrint('💧 WaterTaskScheduler: reset FAILED for '
              '${cursor.toIso8601String().substring(0, 10)}: $e\n$st');
          // Don't break the loop — try the next day. The RPC is
          // idempotent so we'll catch up eventually.
        }
        cursor = cursor.add(const Duration(days: 1));
      }
    }

    _lastSeenDay = today;
    await _persistDay(today);
    // Notify any listening screen so they wipe local "today" state.
    AppEvents.waterDayChanged.value = today;
  }

  DateTime _localToday() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  bool _isDifferentDay(DateTime a, DateTime b) {
    return a.year != b.year || a.month != b.month || a.day != b.day;
  }

  Future<DateTime?> _readPersistedDay() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kLastRolloverDateKey);
      if (raw == null) return null;
      final parsed = DateTime.tryParse(raw);
      if (parsed == null) return null;
      return DateTime(parsed.year, parsed.month, parsed.day);
    } catch (e) {
      debugPrint('💧 WaterTaskScheduler: read prefs failed: $e');
      return null;
    }
  }

  Future<void> _persistDay(DateTime day) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kLastRolloverDateKey,
        day.toIso8601String().substring(0, 10),
      );
    } catch (e) {
      debugPrint('💧 WaterTaskScheduler: persist prefs failed: $e');
    }
  }
}
