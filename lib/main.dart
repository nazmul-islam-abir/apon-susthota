import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/ai_chat_quota_cache.dart';
import 'services/env.dart';
import 'services/supabase_service.dart';
import 'services/water_task_scheduler.dart';
import 'screens/home_shell.dart';
import 'screens/auth_screen.dart';
import 'screens/setup_error_screen.dart';
import 'widgets/exit_confirmer.dart';
import 'theme/app_theme.dart';
//hi
Future<void> main() async {
  // runZonedGuarded wraps runApp so any uncaught error in the Flutter
  // framework still surfaces to onError instead of silently killing the
  // isolate — critical for a "the app crashes when I run it" report.
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // Lock the chrome to the cosmos scaffold so the gradient backdrop blends
    // seamlessly with the system bars.
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.void2,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
    // Load 'bn' locale data so DateFormat(_, 'bn') in screens can render
    // Bangla month / weekday names without throwing LocaleDataException.
    await initializeDateFormatting('bn');
    // Hard-cap Supabase init so a slow network (or missing creds) can never
    // stall the splash screen long enough for the Android OS to time out
    // and tear down the connection.
    await SupabaseService.init().timeout(const Duration(seconds: 4),
        onTimeout: () {
      // Treat a timeout as "init didn't complete in time" — return whatever
      // `init()` already recorded; if it was empty, set a Bangla hint so
      // the SetupErrorScreen explains what happened.
      if (SupabaseService.initError == null) {
        SupabaseService.initError =
            'Supabase শুরু হয়নি (৪ সেকেন্ড টাইমআউট)। ইন্টারনেট সংযোগ ও .env ফাইল যাচাই করুন।';
      }
      return false;
    });
    // Kick off the daily water-task rollover check. This is cheap and
    // idempotent: it just compares today's local date to the last
    // persisted one and calls `reset_daily_water_task` for any days
    // the app was closed. Must run after `SupabaseService.init()` so
    // the client is ready, but does not require an authenticated user
    // (the RPC short-circuits when there is no session).
    unawaited(WaterTaskScheduler.instance.start());
    // Env diagnostics — confirms whether GROQ_API_KEY was loaded before the
    // first chat attempt (so a misconfigured deploy fails loud instead of
    // silently degrading to the not-configured placeholder).
    Env.debugReport();
    // Warm the AI-chat quota cache from disk + a single non-mutating RPC.
    // Hydrating before runApp() lets the chat screen render the quota pill
    // instantly on first paint instead of flickering from "—" to "0/5".
    unawaited(AiChatQuotaCache.instance.readFromDisk());
    unawaited(AiChatQuotaCache.instance.warmUp());
    runApp(const AmarDietApp());
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error\n$stack');
  });
}

/// Root widget. Reacts to Supabase auth state changes so the user is kept
/// logged in across launches (Supabase persists the session in shared
/// preferences) and so any login/logout action from anywhere in the app
/// routes the user to the correct screen without a full restart.
class AmarDietApp extends StatefulWidget {
  const AmarDietApp({super.key});

  @override
  State<AmarDietApp> createState() => _AmarDietAppState();
}

class _AmarDietAppState extends State<AmarDietApp> {
  // Global key so the exit-confirmation helper can pop routes from anywhere
  // (used by the back-gesture handler in [ExitConfirmer]).
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  // Nullable: hot-restart can leave Supabase un-initialized, in which
  // case we skip attaching the listener entirely and just let the next
  // auth-bearing call (or a full restart) re-establish things.
  StreamSubscription<AuthState>? _authSub;

  // We hold the current auth state in [_signedIn] and rebuild only when it
  // flips. The initial value is read from Supabase right after init so a
  // returning user lands directly on HomeShell without ever seeing
  // AuthScreen.
  bool _signedIn = SupabaseService.currentUser != null;

  @override
  void initState() {
    super.initState();
    // Defer the auth-listener subscription until after the first frame
    // so a not-yet-initialized Supabase client (hot-restart race) never
    // throws synchronously inside `initState` and turns the whole app
    // into a red ErrorWidget overlay.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _attachAuthListener();
    });
  }

  /// Subscribes to `onAuthStateChange`. If the Supabase client can't be
  /// obtained (e.g. the Singleton was wiped by a hot-restart before
  /// `Supabase.initialize()` re-ran), this no-ops silently — the
  /// SetupErrorScreen will already be showing via [build]'s
  /// `initError` guard, and the next auth-bearing call (e.g. tapping
  /// the AI-chat or sign-in) will re-establish things.
  void _attachAuthListener() {
    if (!SupabaseService.isInitialized) {
      debugPrint('⚠️ [AmarDietApp] auth listener skipped — Supabase '
          'not initialized yet (will recover on next auth event).');
      return;
    }
    try {
      _authSub = SupabaseService.client.auth.onAuthStateChange.listen((event) {
        final session = event.session;
        final next = session?.user != null;
        if (next != _signedIn) {
          if (!next) {
            _navKey.currentState?.popUntil((r) => r.isFirst);
          }
          if (next) {
            unawaited(WaterTaskScheduler.instance.ping());
            unawaited(AiChatQuotaCache.instance.warmUp());
          }
          setState(() => _signedIn = next);
        }
      }, onError: (Object e) {
        debugPrint('⚠️ [AmarDietApp] auth stream error: $e');
      });
    } on SupabaseNotInitializedError catch (e) {
      debugPrint('⚠️ [AmarDietApp] attachAuthListener swallowed: $e');
    } catch (e, st) {
      debugPrint('⚠️ [AmarDietApp] attachAuthListener unexpected: $e\n$st');
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'আমার ডায়েট',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      navigatorKey: _navKey,
      // The cosmos lives behind every screen — auth, shell, dialogs.
      builder: (context, child) {
        // Simplified background to isolate GPU crashes on emulators.
        return DecoratedBox(
          decoration: const BoxDecoration(color: AppColors.void2),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: SupabaseService.initError != null
          ? const SetupErrorScreen()
          : (_signedIn
              ? const ExitConfirmer(child: HomeShell())
              : const AuthScreen()),
    );
  }
}
