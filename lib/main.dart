import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/ai_chat_quota_cache.dart';
import 'services/app_navigator.dart';
import 'services/blog_service.dart';
import 'services/caretaker_provider.dart';
import 'services/env.dart';
import 'services/locale_provider.dart';
import 'services/mood_task_scheduler.dart';
import 'services/supabase_service.dart';
import 'services/water_task_scheduler.dart';
import 'blog/blog_repository.dart';
import 'l10n/app_localizations.dart';
import 'screens/auth_screen.dart';
import 'screens/details_home_screen.dart';
import 'screens/details_screen.dart';
import 'screens/role_router.dart';
import 'screens/setup_error_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/sos_directory_screen.dart';
import 'services/sos_directory_service.dart';
import 'widgets/exit_confirmer.dart';
import 'theme/app_theme.dart';
import 'package:provider/provider.dart';

//hi
Future<void> main() async {
  // runZonedGuarded wraps runApp so any uncaught error in the Flutter
  // framework still surfaces to onError instead of silently killing the
  // isolate — critical for a "the app crashes when I run it" report.
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Show splash screen immediately while we initialize services.
    runApp(const MaterialApp(
      home: SplashScreen(),
      debugShowCheckedModeBanner: false,
    ));

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
    // Kick off the end-of-day mood-check scheduler. Same pattern as
    // the water scheduler: 1-min timer, no-op when not 10 PM, bails
    // if the user already logged today. Foreground only.
    unawaited(MoodTaskScheduler.instance.start());
    // Env diagnostics — confirms whether GROQ_API_KEY was loaded before the
    // first chat attempt (so a misconfigured deploy fails loud instead of
    // silently degrading to the not-configured placeholder).
    Env.debugReport();
    // Warm the AI-chat quota cache from disk + a single non-mutating RPC.
    // Hydrating before runApp() lets the chat screen render the quota pill
    // instantly on first paint instead of flickering from "—" to "0/5".
    unawaited(AiChatQuotaCache.instance.readFromDisk());
    unawaited(AiChatQuotaCache.instance.warmUp());
    // Warm the blog cache so the Details Home renders the DB-backed
    // list immediately on first paint. Falls back silently to the
    // bundled `kBlogArticles` if Supabase is unreachable.
    unawaited(BlogService.warm());
    unawaited(SosDirectoryService.warm());
    // Read the persisted locale choice (Bangla / English) so the
    // dashboard pill picks up the user's previous selection on launch.
    final localeProvider = LocaleProvider();
    unawaited(localeProvider.hydrate());
    runApp(AponSusthotaApp(localeProvider: localeProvider));
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error\n$stack');
  });
}

/// Root widget. Reacts to Supabase auth state changes so the user is kept
/// logged in across launches (Supabase persists the session in shared
/// preferences) and so any login/logout action from anywhere in the app
/// routes the user to the correct screen without a full restart.
class AponSusthotaApp extends StatefulWidget {
  final LocaleProvider localeProvider;
  const AponSusthotaApp({super.key, required this.localeProvider});

  @override
  State<AponSusthotaApp> createState() => _AponSusthotaAppState();
}

class _AponSusthotaAppState extends State<AponSusthotaApp> {
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
    // Hand the same navigator key to `AppNavigator` so the mood
    // scheduler (and any future foreground scheduler) can push
    // routes from outside the widget tree.
    AppNavigator.attach(_navKey);
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
      debugPrint('⚠️ [AponSusthotaApp] auth listener skipped — Supabase '
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
        debugPrint('⚠️ [AponSusthotaApp] auth stream error: $e');
      });
    } on SupabaseNotInitializedError catch (e) {
      debugPrint('⚠️ [AponSusthotaApp] attachAuthListener swallowed: $e');
    } catch (e, st) {
      debugPrint('⚠️ [AponSusthotaApp] attachAuthListener unexpected: $e\n$st');
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<LocaleProvider>.value(
      value: widget.localeProvider,
      child: Consumer<LocaleProvider>(
        builder: (context, localeProvider, _) {
          return MaterialApp(
            title: 'আপন সুস্থতা',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            locale: localeProvider.locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            navigatorKey: _navKey,
            // Named routes so the Details / Blog flow can be opened from
            // anywhere (e.g. a help button, a notification deep-link, or
            // the Profile screen's "আরও জানুন" link). The home of the
            // blog is the list, and 'details' takes an `id` argument that
            // matches the keys in `kBlogArticles` / `kArticleImages`.
            routes: {
              '/details-home': (_) => const DetailsHomeScreen(),
              '/sos': (_) => const SosDirectoryScreen(),
            },
            onGenerateRoute: (settings) {
              if (settings.name == '/details') {
                final args = settings.arguments;
                // `args` is expected to be the article ID; fall back to the
                // not-found screen instead of returning null so we never
                // throw a generic "could not build route" at the user.
                return MaterialPageRoute(
                  builder: (_) =>
                      _ArticleRouteLoader(id: args is String ? args : ''),
                );
              }
              return null;
            },
            // The cosmos lives behind every screen — auth, shell, dialogs.
            builder: (context, child) {
              // The patient-side caretaker inbox provider is mounted HERE,
              // above the Navigator (not inside any one route). Reason:
              // Provider scope is widget-tree based, not route based — if we
              // wrap inside a single shell (e.g. HomeShell), pushed routes
              // like PatientInboxScreen cannot resolve `CaretakerProvider`
              // because their ancestor chain stops at the home route
              // boundary, and tapping "গ্রহণ করুন" throws
              // "Could not find the correct Provider above this Consumer".
              //
              // `attachRealtime` is idempotent — re-calling on subsequent
              // rebuilds is a no-op. The provider is created once per app
              // instance and lives for the lifetime of the MaterialApp.
              return ChangeNotifierProvider(
                create: (_) => CaretakerProvider(
                  variant: CaretakerProviderVariant.patient,
                )..attachRealtime(),
                child: DecoratedBox(
                  decoration: const BoxDecoration(color: AppColors.void2),
                  child: child ?? const SizedBox.shrink(),
                ),
              );
            },
            home: SupabaseService.initError != null
                ? const SetupErrorScreen()
                : (_signedIn
                    ? const ExitConfirmer(child: RoleRouter())
                    : const AuthScreen()),
          );
        },
      ),
    );
  }
}

/// Resolves a route-style push to the Details screen by article ID.
///
/// We can't navigate directly from a deep link / pushNamed call without
/// resolving the article first, so this widget does the lookup once and
/// either renders the real Details page or a graceful "not found"
/// placeholder.
class _ArticleRouteLoader extends StatelessWidget {
  final String id;
  const _ArticleRouteLoader({required this.id});

  @override
  Widget build(BuildContext context) {
    final pair = BlogRepository.byId(id);
    if (pair == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('পাওয়া যায়নি')),
        body: const Center(
          child: Text('এই নিবন্ধটি আর পাওয়া যাচ্ছে না।'),
        ),
      );
    }
    return DetailsScreen(data: pair);
  }
}
