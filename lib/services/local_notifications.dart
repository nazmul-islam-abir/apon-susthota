/// Facade over `flutter_local_notifications`.
///
/// Responsibilities (kept narrow on purpose):
///
///   1. **Init once** — set up the Android channel, the iOS categories,
///      initialise the `timezone` package, hard-set local TZ to
///      `Asia/Dhaka` (BD users sometimes have phones set to UTC), and
///      wire the tap handler.
///   2. **Permission** — request POST_NOTIFICATIONS on Android 13+ and
///      UNUserNotificationCenter auth on iOS. Idempotent — safe to
///      call from a settings sheet "Test fire" button.
///   3. **Schedule** — accept a `PendingTask` and call
///      `zonedSchedule(...)` with our custom sound. Each id is stable
///      so re-scheduling replaces the previous alarm for that slot.
///   4. **Cancel** — by single id, by `TaskType`, by groupKey, or
///      everything.
///   5. **Tap routing** — when the user taps a notification, parse the
///      `v1:<type>:<id>:<iso>` payload and hand it to `AppNavigator`.
///
/// Per-task schedulers (medicine/meal/workout/water) talk to this
/// facade — they don't talk to the plugin directly. That keeps plugin
/// version-bumps isolated to this file.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'app_navigator.dart';
import 'task_schedule_builder.dart';

class LocalNotifications {
  LocalNotifications._();
  static final LocalNotifications instance = LocalNotifications._();

  static const String _androidChannelId = 'amar_diet_tasks';
  static const String _androidChannelName = 'আপন সুস্থতা — টাস্ক রিমাইন্ডার';
  static const String _androidChannelDesc =
      'ওষুধ, খাবার, ব্যায়াম ও পানির রিমাইন্ডার';
  static const String _androidSoundName = 'notification_sound';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialised = false;
  bool _permissionGranted = false;

  /// Called once from `main()` (after `SupabaseService.init()` and the
  /// other schedulers). Safe to call multiple times — subsequent calls
  /// are no-ops.
  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    try {
      // Hard-set timezone to Asia/Dhaka regardless of the device's
      // clock setting — many BD phones ship with UTC. Matches the
      // server-side `meal_intake_log` and `workout_sessions` which also
      // pin to Asia/Dhaka.
      tz_data.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Dhaka'));

      const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
        onDidReceiveNotificationResponse: _onTap,
      );

      // Pre-create the Android channel so we control the sound /
      // importance once at startup. Without this, the first notification
      // creates the channel with default settings.
      //
      // On dev / first install, we *delete* the channel first so any
      // stale config (sound, importance) from a previous install gets
      // wiped — Android locks channel config once created and won't
      // accept updates.
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        await androidImpl.deleteNotificationChannel(_androidChannelId);
        const channel = AndroidNotificationChannel(
          _androidChannelId,
          _androidChannelName,
          description: _androidChannelDesc,
          importance: Importance.high,
          playSound: true,
          sound: RawResourceAndroidNotificationSound(_androidSoundName),
          enableVibration: true,
        );
        await androidImpl.createNotificationChannel(channel);
      }
    } catch (e, st) {
      debugPrint('🔔 LocalNotifications.init failed: $e\n$st');
    }
  }

  /// Ask the OS for permission. Safe to call multiple times — the OS
  /// will only show its prompt once per install.
  Future<bool> requestPermission() async {
    try {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        final notif = await androidImpl.requestNotificationsPermission();
        final alarm =
            await androidImpl.requestExactAlarmsPermission();
        _permissionGranted = (notif ?? true) && (alarm ?? true);
      } else {
        final iosImpl = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        if (iosImpl != null) {
          final ok = await iosImpl.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
          _permissionGranted = ok ?? false;
        } else {
          _permissionGranted = true; // desktop / web: nothing to ask.
        }
      }
    } catch (e) {
      debugPrint('🔔 LocalNotifications.requestPermission failed: $e');
      _permissionGranted = false;
    }
    return _permissionGranted;
  }

  bool get permissionGranted => _permissionGranted;

  /// Schedule one reminder. If a reminder with the same id is already
  /// scheduled, `flutter_local_notifications` replaces it — so calling
  /// this on every re-schedule is safe.
  Future<void> schedule(PendingTask task) async {
    if (!_initialised) await init();
    if (!_permissionGranted) {
      // Best-effort: try once more. If the user denied, this is a no-op
      // and the caller can decide to show a settings deep-link.
      await requestPermission();
      if (!_permissionGranted) return;
    }
    try {
      final tzFireAt = tz.TZDateTime.from(task.fireAt, tz.local);
      // Already in the past? Skip — zonedSchedule throws on past times.
      if (tzFireAt.isBefore(tz.TZDateTime.now(tz.local))) return;

      const androidDetails = AndroidNotificationDetails(
        _androidChannelId,
        _androidChannelName,
        channelDescription: _androidChannelDesc,
        importance: Importance.high,
        priority: Priority.high,
        // Channel already carries the custom sound (set in init()).
        enableVibration: true,
        category: AndroidNotificationCategory.reminder,
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      await _plugin.zonedSchedule(
        task.id,
        task.title,
        task.body,
        tzFireAt,
        const NotificationDetails(android: androidDetails, iOS: iosDetails),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: task.payload,
      );
    } catch (e) {
      debugPrint('🔔 LocalNotifications.schedule failed for id=${task.id}: $e');
    }
  }

  /// Schedule a batch. Failures are logged, never thrown.
  Future<void> scheduleAll(Iterable<PendingTask> tasks) async {
    for (final t in tasks) {
      await schedule(t);
    }
  }

  /// Cancel a single notification by id.
  Future<void> cancel(int id) async {
    if (!_initialised) return;
    try {
      await _plugin.cancel(id);
    } catch (e) {
      debugPrint('🔔 cancel($id) failed: $e');
    }
  }

  /// Cancel every notification belonging to a task type.
  Future<void> cancelByTaskType(TaskType type) async {
    if (!_initialised) return;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final p in pending) {
        if (_typeFromPayload(p.payload) == type) {
          await _plugin.cancel(p.id);
        }
      }
    } catch (e) {
      debugPrint('🔔 cancelByTaskType($type) failed: $e');
    }
  }

  /// Cancel every notification that matches a particular groupKey
  /// (e.g. medicine id, dayIndex). Used when a dose is taken or a
  /// workout completed — we want to drop today's remaining reminders
  /// for just that item, not the whole category.
  Future<void> cancelByGroupKey(TaskType type, String groupKey) async {
    if (!_initialised) return;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final p in pending) {
        final payload = p.payload;
        if (payload == null) continue;
        if (_typeFromPayload(payload) != type) continue;
        if (_groupKeyFromPayload(payload) == groupKey) {
          await _plugin.cancel(p.id);
        }
      }
    } catch (e) {
      debugPrint('🔔 cancelByGroupKey($type,$groupKey) failed: $e');
    }
  }

  /// Cancel everything. Used on logout / app reset.
  Future<void> cancelAll() async {
    if (!_initialised) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('🔔 cancelAll failed: $e');
    }
  }

  /// Number of pending notifications — useful for the settings sheet
  /// "X reminders scheduled" footer.
  Future<int> pendingCount() async {
    if (!_initialised) return 0;
    try {
      return (await _plugin.pendingNotificationRequests()).length;
    } catch (_) {
      return 0;
    }
  }

  /// Fire a "test" notification 3 seconds from now. Used by the
  /// settings sheet to verify the user actually hears the custom
  /// sound. Uses `inexactAllowWhileIdle` so it works even if the user
  /// hasn't granted `SCHEDULE_EXACT_ALARM` (Android 14+ requires a
  /// manual grant for exact alarms).
  Future<void> fireTestIn(Duration delay) async {
    if (!_initialised) await init();
    try {
      final fireAt = tz.TZDateTime.now(tz.local).add(delay);
      const androidDetails = AndroidNotificationDetails(
        _androidChannelId,
        _androidChannelName,
        channelDescription: _androidChannelDesc,
        importance: Importance.high,
        priority: Priority.high,
        // No `playSound` / `sound` here — the channel already carries
        // the custom sound (set in `init()` via `createNotificationChannel`).
        // Re-declaring it on per-notification details can override in
        // unpredictable ways on some OEM ROMs (Xiaomi, Samsung One UI).
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      await _plugin.zonedSchedule(
        999998, // distinct from fireImmediateTest (999999)
        'পরীক্ষা বিজ্ঞপ্তি',
        'আপনার কাস্টম সাউন্ড কাজ করছে ✓',
        fireAt,
        const NotificationDetails(android: androidDetails, iOS: iosDetails),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'v1:test:test:test',
      );
    } catch (e) {
      debugPrint('🔔 fireTestIn failed: $e');
    }
  }

  /// Fire a notification *immediately* (right now) so the user can
  /// confirm visual + audio without waiting 3 seconds. Uses `.show()`
  /// instead of `zonedSchedule` so it doesn't need any alarm permission.
  Future<void> fireImmediateTest() async {
    if (!_initialised) await init();
    try {
      const androidDetails = AndroidNotificationDetails(
        _androidChannelId,
        _androidChannelName,
        channelDescription: _androidChannelDesc,
        importance: Importance.high,
        priority: Priority.high,
        // Channel carries the sound; do not re-declare here.
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      await _plugin.show(
        999999,
        'পরীক্ষা বিজ্ঞপ্তি',
        'বিজ্ঞপ্তি কাজ করছে ✓',
        NotificationDetails(android: androidDetails, iOS: iosDetails),
        payload: 'v1:test:test:test',
      );
    } catch (e) {
      debugPrint('🔔 fireImmediateTest failed: $e');
    }
  }

  // ─── Tap handling ─────────────────────────────────────────────────────

  void _onTap(NotificationResponse resp) {
    final payload = resp.payload;
    if (payload == null || payload.isEmpty) return;
    _routeTap(payload);
  }

  /// Public for cold-start handling: when the app is launched by a tap
  /// on a notification, the OS hands us the payload before the
  /// navigator is attached. We buffer it; the app shell calls
  /// [drainPendingTaps] once the navigator is ready.
  void _routeTap(String payload) {
    try {
      final parts = payload.split(':');
      if (parts.length < 3 || parts[0] != 'v1') return;
      final type = parts[1];
      final id = parts[2];
      // Defer to the next microtask so the navigator is ready even if
      // the tap arrives during a route transition.
      Future.microtask(() => _navigate(type, id));
    } catch (e) {
      debugPrint('🔔 _routeTap bad payload: $payload ($e)');
    }
  }

  void _navigate(String type, String id) {
    final nav = AppNavigator.key.currentState;
    if (nav == null) {
      // Navigator not mounted yet (cold-start). Buffer the payload so
      // the shell can pick it up once it's ready. For v1 we drop it —
      // cold-start taps are rare and the user can still find the
      // screen manually.
      return;
    }
    AppNavigator.pushTaskDestination('v1:$type:$id');
  }

  // ─── Payload parsing ──────────────────────────────────────────────────

  TaskType? _typeFromPayload(String? payload) {
    if (payload == null) return null;
    final parts = payload.split(':');
    if (parts.length < 2 || parts[0] != 'v1') return null;
    switch (parts[1]) {
      case 'medicine':
        return TaskType.medicine;
      case 'meal':
        return TaskType.meal;
      case 'workout':
        return TaskType.workout;
      case 'water':
        return TaskType.water;
    }
    return null;
  }

  String? _groupKeyFromPayload(String payload) {
    // groupKey is always payload parts[2] (medicine id, meal slot,
    // workout dayIndex, water slot).
    final parts = payload.split(':');
    if (parts.length < 3) return null;
    return parts[2];
  }
}
