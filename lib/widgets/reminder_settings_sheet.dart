/// Bottom sheet that lets the user opt in/out of each reminder
/// category and verify the custom sound is working.
///
/// Visible from Profile → "বিজ্ঞপ্তি". State is persisted via
/// `MedicineReminderScheduler.setEnabled(...)` (and the matching
/// meal/workout/water setters). A "পরীক্ষা করুন" button fires a
/// test notification 5 seconds from now using the custom sound — so
/// the user can confirm their phone actually rings with our sound,
/// not the default system ding.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/local_notifications.dart';
import '../services/medicine_reminder_scheduler.dart';
import '../services/meal_reminder_scheduler.dart';
import '../services/water_reminder_scheduler.dart';
import '../services/workout_reminder_scheduler.dart';
import '../theme/app_theme.dart';

class ReminderSettingsSheet extends StatefulWidget {
  const ReminderSettingsSheet({super.key});

  /// Convenience helper so callers can `showModalBottomSheet(...)`
  /// without rebuilding the boilerplate each time.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const ReminderSettingsSheet(),
    );
  }

  @override
  State<ReminderSettingsSheet> createState() => _ReminderSettingsSheetState();
}

class _ReminderSettingsSheetState extends State<ReminderSettingsSheet> {
  late bool _medicine;
  late bool _meal;
  late bool _workout;
  late bool _water;

  Timer? _countdown;
  int _secondsLeft = 0;

  /// OS-scheduled alarm count (medicine + meal + workout + water + test).
  /// -1 = "haven't asked the OS yet" sentinel so the footer shows a
  /// spinner on first paint instead of lying about "0 scheduled".
  int _pendingCount = -1;

  /// Guard against double-tapping the battery button and stacking two
  /// system activities on top of each other.
  bool _batteryRequestInFlight = false;

  @override
  void initState() {
    super.initState();
    _medicine = MedicineReminderScheduler.instance.enabled;
    _meal = MealReminderScheduler.instance.enabled;
    _workout = WorkoutReminderScheduler.instance.enabled;
    _water = WaterReminderScheduler.instance.enabled;
    _refreshPendingCount();
  }

  Future<void> _refreshPendingCount() async {
    final n = await LocalNotifications.instance.pendingCount();
    if (!mounted) return;
    setState(() => _pendingCount = n);
  }

  @override
  void dispose() {
    _countdown?.cancel();
    super.dispose();
  }

  Future<void> _toggle({
    required bool value,
    required Future<void> Function(bool) setter,
    required void Function(bool) local,
  }) async {
    setState(() => local(value));
    await setter(value);
    // Re-pull pending count after the OS finishes rescheduling.
    await _refreshPendingCount();
  }

  Future<void> _fireTest() async {
    setState(() => _secondsLeft = 3);
    _countdown?.cancel();
    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _secondsLeft -= 1);
      if (_secondsLeft <= 0) t.cancel();
    });
    // Make sure the permission is granted. If the user denied earlier,
    // this returns false and the call below will be a no-op.
    final granted = await LocalNotifications.instance.requestPermission();
    if (!granted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'বিজ্ঞপ্তির অনুমতি নেই। "সিস্টেম সেটিংসে গিয়ে..." চালু করুন।'),
          backgroundColor: AppColors.rose,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }
    // Fire a *visible* test notification immediately (3s out) so the
    // user can confirm both visual + audio. We also fire one with no
    // delay (just .show()) so they can confirm the channel works right
    // now without waiting.
    await LocalNotifications.instance.fireTestIn(const Duration(seconds: 3));
    await LocalNotifications.instance.fireImmediateTest();
    // Refresh the footer count so the user sees the test entries
    // counted toward "মোট অপেক্ষমাণ" immediately.
    await _refreshPendingCount();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
            'বিজ্ঞপ্তি পাঠানো হয়েছে — স্ক্রিনের উপরে স্ট্যাটাস বার দেখুন'),
        backgroundColor: AppColors.svcHero,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _openSystemSettings() async {
    await openAppSettings();
  }

  /// Ask the OS to whitelist this app from battery optimization.
  /// Critical for scheduled notifications to survive on Xiaomi/Realme/
  /// Vivo/Samsung — those ROMs kill pending AlarmManager entries
  /// after the phone sits idle for a few minutes, even with all
  /// permissions granted. This opens the system dialog directly; if
  /// the user denies or the device doesn't support it, we fall back
  /// to the app-settings screen so they can still grant it manually.
  Future<void> _requestIgnoreBatteryOptimization() async {
    // Guard against double-taps queuing two system activities.
    if (_batteryRequestInFlight) return;
    _batteryRequestInFlight = true;
    try {
      final status = await Permission.ignoreBatteryOptimizations.request();
      if (!mounted) return;
      if (status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ব্যাটারি অপ্টিমাইজেশন বন্ধ করা হয়েছে ✓'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
      // Denied / restricted → point the user at the right screen.
      await _openSystemSettings();
    } catch (_) {
      // Some OEMs throw if the activity is backgrounded mid-request.
      await _openSystemSettings();
    } finally {
      _batteryRequestInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── grabber ────────────────────────────────────────────────
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // ── header ─────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.svcCategoryBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.notifications_active_rounded,
                    color: AppColors.svcHero,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'বিজ্ঞপ্তি',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: AppColors.ink,
                          letterSpacing: -0.3,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'কাজের ২ মিনিট আগে আপনাকে জানানো হবে',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.smoke,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // ── toggles ────────────────────────────────────────────────
            _ReminderToggle(
              icon: Icons.medication_rounded,
              title: 'ওষুধ',
              subtitle: 'নির্ধারিত সময়ের ২ মিনিট আগে জানানো হবে',
              value: _medicine,
              locked: true,
              lockedReason: 'ওষুধের রিমাইন্ডার সবসময় চালু থাকবে',
              onChanged: null,
            ),
            _ReminderToggle(
              icon: Icons.restaurant_rounded,
              title: 'খাবার',
              subtitle: 'নাস্তা, দুপুর ও রাতের খাবারের সময়',
              value: _meal,
              onChanged: (v) => _toggle(
                value: v,
                setter: MealReminderScheduler.instance.setEnabled,
                local: (x) => _meal = x,
              ),
            ),
            _ReminderToggle(
              icon: Icons.fitness_center_rounded,
              title: 'ব্যায়াম',
              subtitle: 'দিনে ৫ বার — শেষ না হওয়া পর্যন্ত',
              value: _workout,
              onChanged: (v) => _toggle(
                value: v,
                setter: WorkoutReminderScheduler.instance.setEnabled,
                local: (x) => _workout = x,
              ),
            ),
            _ReminderToggle(
              icon: Icons.water_drop_rounded,
              title: 'পানি',
              subtitle: 'জেগে ওঠা থেকে ঘুম পর্যন্ত ৮ বার',
              value: _water,
              onChanged: (v) => _toggle(
                value: v,
                setter: WaterReminderScheduler.instance.setEnabled,
                local: (x) => _water = x,
              ),
            ),
            const SizedBox(height: 18),
            // ── test fire button ───────────────────────────────────────
            InkWell(
              onTap: _fireTest,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.svcCategoryBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.volume_up_rounded,
                      color: AppColors.svcHero,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'সাউন্ড পরীক্ষা করুন',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            '৫ সেকেন্ডের মধ্যে একটি পরীক্ষামূলক বিজ্ঞপ্তি পাঠানো হবে',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.smoke,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_secondsLeft > 0)
                      Text(
                        '${_secondsLeft}s',
                        style: const TextStyle(
                          color: AppColors.svcHero,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // ── pending-count footer ──────────────────────────────────
            // Live readout of how many alarms the OS currently holds.
            // Empty list = something upstream is broken (no permissions,
            // no medicines, etc.). Tap the row to refresh.
            TextButton.icon(
              onPressed: _refreshPendingCount,
              icon: const Icon(Icons.schedule_rounded, size: 16),
              label: Text(
                _pendingCount < 0
                    ? 'মোট অপেক্ষমাণ বিজ্ঞপ্তি গণনা হচ্ছে…'
                    : 'মোট অপেক্ষমাণ বিজ্ঞপ্তি: $_pendingCount',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                foregroundColor: AppColors.smoke,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
            const SizedBox(height: 4),
            // ── system-settings links ─────────────────────────────────
            //   1. Notification permission (re-grant in case the OS
            //      dialog was dismissed earlier).
            //   2. Battery-optimization whitelist — critical on MIUI,
            //      One UI, Funtouch. Without it the OS silently drops
            //      scheduled alarms after the device goes idle.
            TextButton.icon(
              onPressed: _openSystemSettings,
              icon: const Icon(Icons.notifications_active_rounded, size: 16),
              label: const Text(
                'সিস্টেম সেটিংসে গিয়ে বিজ্ঞপ্তি চালু করুন',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            TextButton.icon(
              onPressed: _requestIgnoreBatteryOptimization,
              icon: const Icon(Icons.battery_saver_rounded, size: 16),
              label: const Text(
                'ব্যাটারি অপ্টিমাইজেশন বন্ধ করুন (গুরুত্বপূর্ণ)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReminderToggle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool locked;
  final String? lockedReason;

  const _ReminderToggle({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.locked = false,
    this.lockedReason,
  });

  @override
  Widget build(BuildContext context) {
    final isInteractive = !locked && onChanged != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: AppColors.svcCategoryBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.svcHero, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      if (locked) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.lock_rounded,
                          size: 13,
                          color: AppColors.smoke,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    locked ? (lockedReason ?? '') : subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.smoke,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              value: value,
              onChanged: isInteractive ? onChanged : null,
              activeColor: AppColors.svcHero,
            ),
          ],
        ),
      ),
    );
  }
}
