import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'services/ai_chat_quota_cache.dart';
import 'services/app_navigator.dart';
import 'services/bdapps/bdapps_session_service.dart';
import 'services/blog_service.dart';
import 'services/caretaker_provider.dart';
import 'services/env.dart';
import 'services/locale_provider.dart';
import 'services/mood_task_scheduler.dart';
import 'services/onboarding_gate.dart';
import 'services/supabase_service.dart';
import 'services/water_task_scheduler.dart';
import 'services/local_notifications.dart';
import 'services/medicine_reminder_scheduler.dart';
import 'services/meal_reminder_scheduler.dart';
import 'services/workout_reminder_scheduler.dart';
import 'services/water_reminder_scheduler.dart';
import 'blog/blog_repository.dart';
import 'l10n/app_localizations.dart';
import 'screens/auth/role_landing_screen.dart';
import 'screens/onboarding/onboarding_intro_screen.dart';
import 'screens/onboarding/onboarding_video_screen.dart';
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

    // Preload the Bangla font the theme uses so the role-landing
    // screen — the first screen after login — renders in Hind
    // Siliguri on its very first frame. Without this the device
    // briefly falls back to its system font (Roboto on Android) and
    // Bangla glyphs look thinner/squarer than the dashboard (which
    // mounts later, after the font has downloaded).
    GoogleFonts.config.allowRuntimeFetching = true;
    await GoogleFonts.pendingFonts([
      GoogleFonts.hindSiliguri(),
    ]);

    // Show splash screen immediately while we initialize services.
    // We hand the same navigator key through to AponSusthotaApp so the
    // swap from splash → main shell doesn't lose the navigator state.
    final splashNavKey = GlobalKey<NavigatorState>();
    runApp(MaterialApp(
      home: SplashScreen(navigatorKey: splashNavKey),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      // Use the device locale during the brief splash window so we
      // don't flash Bangla for English users before the real locale
      // hydrates from disk.
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
    // Local-notification pipeline: init the plugin + timezone, ask for
    // permission (idempotent), then boot each per-task scheduler.
    // Medicine is default-on; meal/workout/water default-off until the
    // user toggles them in the Profile → Notifications sheet.
    unawaited(LocalNotifications.instance.init());
    unawaited(LocalNotifications.instance.requestPermission());
    unawaited(MedicineReminderScheduler.instance.start());
    unawaited(MealReminderScheduler.instance.start());
    unawaited(WorkoutReminderScheduler.instance.start());
    unawaited(WaterReminderScheduler.instance.start());
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

    // First-launch gate: cold-start users go through intro → video →
    // role-landing. SharedPreferences tracks which steps have been
    // seen; the in-memory `OnboardingGate.flow` controller drives the
    // step-to-step transitions inside the app so we never replace the
    // root `MaterialApp.home` route.
    final introSeen = await OnboardingGate.isIntroSeen();
    final videoSeen = await OnboardingGate.isVideoSeen();
    if (!introSeen) {
      OnboardingGate.flow.reset();
    } else if (!videoSeen) {
      OnboardingGate.flow.markIntroDone();
    } else {
      OnboardingGate.flow.markVideoDone();
    }

    runApp(AponSusthotaApp(
      localeProvider: localeProvider,
      splashNavKey: splashNavKey,
    ));
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error\n$stack');
  });
}

/// Root widget. Auth is BDApps-only — no Supabase auth involved.
/// Reads the BDApps session cache on start; exposes a [ValueNotifier]
/// so the login screen (and any logout button) can flip the gate
/// without rebuilding the whole app.
class AponSusthotaApp extends StatefulWidget {
  final LocaleProvider localeProvider;
  final GlobalKey<NavigatorState>? splashNavKey;

  const AponSusthotaApp({
    super.key,
    required this.localeProvider,
    this.splashNavKey,
  });

  @override
  State<AponSusthotaApp> createState() => _AponSusthotaAppState();
}

class _AponSusthotaAppState extends State<AponSusthotaApp> {
  // Reuse the splash navigator key so the swap from SplashScreen →
  // main shell is seamless (the navigator state survives the rebuild).
  // Falls back to a fresh key if main() didn't pass one in (e.g. tests).
  late final GlobalKey<NavigatorState> _navKey =
      widget.splashNavKey ?? GlobalKey<NavigatorState>();

  /// A notifier any screen can `signInNotifier.value = true` to
  /// trigger the gate to flip. We start with the hydrated value so a
  /// returning user lands directly on the role-appropriate shell.
  final ValueNotifier<bool> signedInNotifier =
      ValueNotifier(BdappsSessionService.instance.isSignedIn);

  @override
  void initState() {
    super.initState();
    // Hand the same navigator key to `AppNavigator` so the mood
    // scheduler (and any future foreground scheduler) can push
    // routes from outside the widget tree.
    AppNavigator.attach(_navKey);
    AppNavigator.attachSignedInNotifier(signedInNotifier);

    // Global Reset Logic: Whenever the user signs out (notifier flips to false),
    // we must clear the navigator stack. If we don't do this, pushed screens
    // (like Profile) stay visible on top of the login home.
    signedInNotifier.addListener(() {
      if (!signedInNotifier.value) {
        // Use postFrameCallback to avoid the "!_debugLocked" error (navigating during build)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _navKey.currentState?.popUntil((route) => route.isFirst);
        });
      }
    });

    // Hydrate the BDApps session cache BEFORE first build so a
    // returning user lands directly on the role-appropriate shell
    // without ever seeing the landing screen.
    BdappsSessionService.instance.hydrate().then((_) {
      if (!mounted) return;
      signedInNotifier.value = BdappsSessionService.instance.isSignedIn;
      if (signedInNotifier.value) {
        unawaited(WaterTaskScheduler.instance.ping());
        unawaited(AiChatQuotaCache.instance.warmUp());
      }
    });
  }

  @override
  void dispose() {
    signedInNotifier.dispose();
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
                : ListenableBuilder(
                    listenable: OnboardingGate.flow,
                    builder: (context, _) {
                      // First-run onboarding gate. `flow.step` flips
                      // from intro → video → done as the user advances
                      // (via the screens calling
                      // `OnboardingGate.flow.markIntroDone` /
                      // `markVideoDone`). When `done`, we drop through
                      // to the auth gate — the value-listener
                      // notifier handles signedIn.
                      switch (OnboardingGate.flow.step) {
                        case OnboardingFlowStep.intro:
                          return const OnboardingIntroScreen();
                        case OnboardingFlowStep.video:
                          return const OnboardingVideoScreen();
                        case OnboardingFlowStep.done:
                          return ValueListenableBuilder<bool>(
                            valueListenable: signedInNotifier,
                            builder: (_, signedIn, ___) => signedIn
                                ? const ExitConfirmer(child: RoleRouter())
                                : const RoleLandingScreen(),
                          );
                      }
                    },
                  ),
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
