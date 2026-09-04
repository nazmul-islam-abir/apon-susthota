/// End-of-day mood-check-in scheduler.
///
/// Mirrors `WaterTaskScheduler` so the two foreground schedulers
/// have identical startup / shutdown semantics:
///
///   • Singleton (`MoodTaskScheduler.instance`) — exactly one
///     scheduler lives in the process; cheap to construct.
///   • `Timer.periodic(minutes: 1)` keeps the check alive even
///     when the app is left running overnight (elderly users
///     sometimes keep the tablet plugged in on a dresser).
///   • `SharedPreferences` "asked on YYYY-MM-DD" gate so a user
///     never gets prompted twice in the same day.
///   • Logs the morning behavior so the next launch / next
///     foreground time can catch up immediately.
///
/// Deliberately does **not** use a platform-level background
/// scheduler (`workmanager`, `flutter_localifications`). Same
/// assumption as the water scheduler: "the app is foreground
/// at least once a day". If that ever changes, this is the
/// place to plug a `WorkManager` worker in.
///
/// Triggered at 10 PM local time. The actual prompt is the same
/// `MoodHealthSheet` the dashboard banner uses — we just hand it
/// a default "ok" mood if the user dismisses without picking.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mood_entry.dart';
import '../widgets/mood_health_sheet.dart';
import 'app_navigator.dart';
import 'bdapps/bdapps_session_service.dart';
import 'supabase_service.dart';

class MoodTaskScheduler {
  MoodTaskScheduler._();
  static final MoodTaskScheduler instance = MoodTaskScheduler._();

  Timer? _tick;
  bool _running = false;

  /// 22:00 local time — the moment the daily nudge can fire.
  static const int _triggerHour = 22;

  // ─── Lifecycle ────────────────────────────────────────────

  /// Start the scheduler. Idempotent — safe to call from `main()`.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => _tickNow());
    // Check immediately on startup so a user who opens the app
    // at 22:05 for the first time today gets the prompt without
    // waiting a minute.
    await _tickNow(reason: 'startup');
  }

  /// Stop the scheduler (mainly for tests).
  void stop() {
    _tick?.cancel();
    _tick = null;
    _running = false;
  }

  // ─── Core logic ────────────────────────────────────────────

  Future<void> _tickNow({String reason = 'tick'}) async {
    final now = DateTime.now();
    if (now.hour < _triggerHour) return;

    // The mood check-in is a post-login nudge. Never pop it on the
    // splash / role-landing / onboarding screens — there's no profile
    // to attach the mood to, and surprising an unregistered visitor
    // with a daily-mood popup is the single fastest way to lose
    // them. We accept either a Supabase session or a hydrated
    // BDApps session as proof of login.
    if (SupabaseService.currentUser == null &&
        !BdappsSessionService.instance.isSignedIn) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final key = _askedKey(now);
    if (prefs.getBool(key) ?? false) {
      // Already nudged today — bail out without checking the
      // server so we don't burn quota on repeat ticks.
      return;
    }

    // If the user already logged their mood today, mark the day
    // as "asked" so the scheduler won't keep firing every minute
    // for the rest of the evening. This is the cheap "all done"
    // branch — most evenings end here.
    try {
      final existing = await SupabaseService.getTodayMood();
      if (existing != null) {
        await prefs.setBool(key, true);
        return;
      }
    } catch (e, st) {
      debugPrint('🌤️ [MoodTaskScheduler] check FAILED: $e\n$st');
      // Offline? Try again next minute rather than spamming the
      // user with a prompt they can't actually save.
      return;
    }

    // Mark the day as asked BEFORE we open the sheet so even if
    // the push fails or the user kills the app mid-prompt, we
    // don't fire again at 22:01, 22:02, etc.
    await prefs.setBool(key, true);

    debugPrint('🌤️ [MoodTaskScheduler] prompting user '
        '(reason=$reason, now=${now.toIso8601String()})');

    final nav = AppNavigator.key.currentState;
    if (nav == null) {
      debugPrint('🌤️ [MoodTaskScheduler] no navigator — skipping prompt');
      return;
    }

    // Push a fullscreen host that opens the sheet on the next
    // frame, then pops itself. This keeps the prompt above any
    // other modal the user might have open (so they can't get
    // trapped by the AI chat sheet, etc.).
    nav.push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const _MoodPromptHost(),
      ),
    );
  }

  /// Reset the "asked today" flag (useful for tests + for users
  /// who cleared their app data and want a fresh nudge).
  Future<void> resetToday() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_askedKey(DateTime.now()));
  }

  // ─── Helpers ───────────────────────────────────────────────

  String _askedKey(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return 'mood.asked.$mm-$dd';
  }
}

/// Tiny fullscreen route that opens `MoodHealthSheet` once mounted,
/// then pops itself. We use a dedicated route (rather than pushing
/// the sheet directly) so the scheduler can wait for the
/// navigator-key to settle before showing UI, and so the sheet
/// inherits a fresh theme + locale.
class _MoodPromptHost extends StatefulWidget {
  const _MoodPromptHost();

  @override
  State<_MoodPromptHost> createState() => _MoodPromptHostState();
}

class _MoodPromptHostState extends State<_MoodPromptHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // We could surface the localisable reminder prompt here
      // (via AppLocalizations.moodReminderPrompt) but the sheet's
      // own header is enough — no need for a separate banner.
      // After the sheet returns, pop ourselves so the user lands
      // back on whatever tab they were on.
      final result = await MoodHealthSheet.show(
        context,
        initialMood: MoodKind.ok,
      );
      if (!mounted) return;
      if (result != null) {
        await SupabaseService.logMood(
          mood: result.mood,
          energyLevel: result.energyLevel,
          stressLevel: result.stressLevel,
          sleepHours: result.sleepHours,
          symptoms: result.symptoms,
        );
      }
      // Always pop — even if the user dismissed the sheet
      // without saving.
      debugPrint('🌤️ [MoodPromptHost] closing (saved=${result != null})');
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Empty scaffold — the bottom sheet is the actual UI. We
    // still need a buildable widget so the navigator can mount.
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: SizedBox.shrink(),
    );
  }
}