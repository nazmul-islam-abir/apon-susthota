/// Dashboard — the landing page (tab index 0).
///
/// Redesigned (v4) to match the reference "service booking" aesthetic:
///   • Top status row (location pin + bell + avatar) inside the dark hero.
///   • Big dark-teal hero banner with greeting + featured copy on the left
///     and an illustrated service-art panel on the right.
///   • "Service Categories" — 2x2 grid of soft rounded cards with
///     outlined-green icons + chevron, matching the reference image.
///   • "Popular Services" — horizontal carousel of full-bleed service cards
///     with rating + price + title.
///   • Floating bottom navbar lives in HomeShell.
///
/// We keep the data fetches intact (profile, classification, plan progress,
/// adherence, water, plan slots) so all the existing pills/stats still work
/// — only the visual chrome changes.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/user_profile.dart';
import '../models/workout.dart' show DailyMetric;
import '../services/app_events.dart';
import '../services/diet_recommender.dart' show DietClassification;
import '../services/locale_provider.dart';
import '../services/nearby_locator.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/clinical_snapshot.dart';
import '../widgets/mono_widgets.dart';
import '../widgets/mood_banner.dart';
import '../widgets/voice_message_banner.dart';
import 'meal_plan_screen.dart';
import 'notification_screen.dart';
import 'water_screen.dart';
import 'workout_screen.dart';
import 'analytics_screen.dart';
import 'medicine_screen.dart';
import 'profile_screen.dart';
import 'details_home_screen.dart';
// WorkoutAdherence / MealAdherence / PlanProgress / DailyMetric are all
// imported transitively via supabase_service.dart + dashboard.dart.

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<_DashboardData> _future;
  int _unreadCount = NotificationService.cachedUnread;
  String _currentLocation = NearbyLocator.cachedLocation ?? 'ঢাকা, বাংলাদেশ';
  bool _detectingLocation = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _refreshUnread();
    _detectLocation();
    AppEvents.profileChanged.addListener(_onChanged);
    AppEvents.mealLogged.addListener(_onChanged);
    AppEvents.medicineChanged.addListener(_onChanged);
    AppEvents.workoutChanged.addListener(_onChanged);
    AppEvents.waterChanged.addListener(_onChanged);
    AppEvents.moodChanged.addListener(_onChanged);
  }

  @override
  void dispose() {
    AppEvents.profileChanged.removeListener(_onChanged);
    AppEvents.mealLogged.removeListener(_onChanged);
    AppEvents.medicineChanged.removeListener(_onChanged);
    AppEvents.workoutChanged.removeListener(_onChanged);
    AppEvents.waterChanged.removeListener(_onChanged);
    AppEvents.moodChanged.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    _future = _load();
    setState(() {});
    _refreshUnread();
  }

  Future<void> _openNotifications() async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationScreen()),
    );
    // When the user returns, refresh the unread badge in case they
    // dismissed or marked items read while inside the page.
    _refreshUnread();
  }

  Future<_DashboardData> _load() async {
    final results = await Future.wait<dynamic>([
      SupabaseService.fetchProfile(),
      SupabaseService.classifyUser(),
      SupabaseService.getPlanProgress(),
      SupabaseService.getWorkoutAdherence(days: 7),
      SupabaseService.getMealAdherence(days: 7),
      SupabaseService.getTodayDailyMetrics(),
    ]);
    final profile = results[0] as UserProfile?;
    final cls = results[1] != null
        ? DietClassification.fromJson(
            Map<String, dynamic>.from(results[1] as Map))
        : null;
    final progress = results[2];
    final todayMetric = results[5];
    final waterLiters = todayMetric is DailyMetric
        ? todayMetric.waterLiters
        : (todayMetric is num ? todayMetric.toDouble() : 0.0);

    int planDayIndex = 1;
    if (progress != null) {
      try {
        planDayIndex = (progress as dynamic).day as int? ?? 1;
      } catch (_) {/* ignore */}
    }

    String avatarUrl = '';
    final rawPath = profile?.avatarUrl;
    if (rawPath != null && rawPath.isNotEmpty) {
      try {
        final signed = await SupabaseService.getProfilePhotoUrl(rawPath);
        if (signed.isNotEmpty) {
          final joiner = signed.contains('?') ? '&' : '?';
          avatarUrl =
              '$signed${joiner}_v=${profile?.photoUploadCount ?? DateTime.now().millisecondsSinceEpoch}';
        }
      } catch (_) {/* keep empty */}
    }

    return _DashboardData(
      profile: profile,
      classification: cls,
      planDayIndex: planDayIndex,
      avatarUrl: avatarUrl,
      waterLiters: waterLiters,
      waterTargetLiters: 2.5,
    );
  }

  Future<void> _refreshUnread() async {
    try {
      // Warm the cache so the bell badge appears even before the user
      // taps it. Force=true bypasses the 30-second TTL on first load.
      await NotificationService.load(force: true);
      final n = await NotificationService.refreshUnread();
      if (!mounted) return;
      setState(() => _unreadCount = n);
    } catch (_) {/* silently keep the cached number */}
  }

  Future<void> _detectLocation() async {
    if (_detectingLocation) return;
    setState(() => _detectingLocation = true);
    try {
      final loc = await NearbyLocator().detectCityName();
      if (mounted) {
        setState(() {
          _currentLocation = loc;
        });
      }
    } catch (_) {
      // Keep Dhaka as fallback
    } finally {
      if (mounted) setState(() => _detectingLocation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.svcCategoryBg,
      body: SafeArea(
        top: false,
        child: FutureBuilder<_DashboardData>(
          future: _future,
          builder: (context, snap) {
            final l = AppLocalizations.of(context);
            if (l == null) return const Center(child: LoadingMark());
            
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: LoadingMark());
            }
            if (snap.hasError) {
              return _ErrorState(
                error: snap.error!,
                onRetry: _onChanged,
              );
            }
            final d = snap.data!;
            return RefreshIndicator(
              color: AppColors.svcHero,
              backgroundColor: Colors.white,
              onRefresh: () async => _onChanged(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(
                  0,
                  0,
                  0,
                  32 + MediaQuery.of(context).padding.bottom + 110,
                ),
                children: [
                  _ServiceHero(
                    profile: d.profile,
                    avatarUrl: d.avatarUrl,
                    unreadCount: _unreadCount,
                    onBellTap: _openNotifications,
                    currentLocation: _currentLocation,
                    detectingLocation: _detectingLocation,
                    onDetectLocation: _detectLocation,
                  ),
                  // ─── Today's mood banner ───────────────────────────────
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: const VoiceMessageBanner(
                      role: VoiceBannerRole.patient,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: MoodBanner(
                      onLogSaved: () {
                        // Re-fetch the dashboard data once the user
                        // saves a mood — currently nothing in the
                        // _DashboardData payload depends on mood, but
                        // future iterations (e.g. "mood vs water
                        // adherence") can hook in here.
                        _onChanged();
                      },
                    ),
                  ),
                  // ─── Categories section ────────────────────────────────
                  const SizedBox(height: 22),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _SectionHeaderRow(
                      title: l.sectionCategories,
                      bangla: 'আপনার প্রয়োজনীয় সব সেবা',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _CategoryGrid(onOpen: _openCategory),
                  ),
                  // ─── AI News Banner ───────────────────────────────────
                  const SizedBox(height: 26),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: _AiDashboardSlider(),
                  ),
                  // ─── Today's Tasks ────────────────────────────────────
                  const SizedBox(height: 26),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _SectionHeaderRow(
                      title: l.localeName == 'bn' ? 'আজকের কাজ' : 'Today\'s Tasks',
                      bangla: l.localeName == 'bn' ? 'আপনার নিয়মিত লক্ষ্যগুলো পূরণ করুন' : 'Complete your daily health goals',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _TaskGrid(
                      onWater: _openWater,
                      onWorkout: _openWorkout,
                      onMeal: _openMealPlan,
                      onMedicine: _openMedicine,
                    ),
                  ),
                  // ─── Popular services section ─────────────────────────
                  const SizedBox(height: 26),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _SectionHeaderRow(
                      title: l.sectionPopular,
                      bangla: l.sectionPopularSub,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const _PopularServicesCarousel(),
                  // ─── Clinical snapshot (kept) ───────────────────────────
                  const SizedBox(height: 26),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _SectionHeaderRow(
                      title: l.sectionHealth,
                      bangla: l.sectionHealthSub,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ClinicalSnapshotCard(classification: d.classification),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ─── Navigation ─────────────────────────────────────────────────────────

  Future<void> _openCategory(_CategoryId id) async {
    HapticFeedback.selectionClick();
    switch (id) {
      case _CategoryId.water:
        await _openWater();
        break;
      case _CategoryId.connected:
        await _openProfile();
        break;
      case _CategoryId.meal:
        await _openMealPlan();
        break;
      case _CategoryId.workout:
        await _openWorkout();
        break;
      case _CategoryId.medicine:
        await _openMedicine();
        break;
      case _CategoryId.analytics:
        await _openAnalytics();
        break;
    }
  }

  Future<void> _openMealPlan() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MealPlanScreen()),
    );
  }

  Future<void> _openWorkout() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WorkoutScreen()),
    );
  }

  Future<void> _openAnalytics() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
    );
  }

  Future<void> _openMedicine() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MedicineScreen()),
    );
  }

  Future<void> _openWater() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WaterScreen()),
    );
  }

  Future<void> _openProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
  }
}

class _DashboardData {
  final UserProfile? profile;
  final DietClassification? classification;
  final int planDayIndex;
  final String avatarUrl;
  final double waterLiters;
  final double waterTargetLiters;
  _DashboardData({
    required this.profile,
    required this.classification,
    required this.planDayIndex,
    required this.avatarUrl,
    required this.waterLiters,
    required this.waterTargetLiters,
  });
}

// ════════════════════════════════════════════════════════════════════════
//  HERO  — dark green banner + status row + search + illustrated panel
// ════════════════════════════════════════════════════════════════════════

class _ServiceHero extends StatelessWidget {
  final UserProfile? profile;
  final String avatarUrl;
  final int unreadCount;
  final VoidCallback onBellTap;
  final String currentLocation;
  final bool detectingLocation;
  final VoidCallback onDetectLocation;

  const _ServiceHero({
    required this.profile,
    required this.avatarUrl,
    required this.unreadCount,
    required this.onBellTap,
    required this.currentLocation,
    required this.detectingLocation,
    required this.onDetectLocation,
  });

  String _displayName(AppLocalizations l) {
    final n = profile?.fullName?.trim();
    if (n == null || n.isEmpty) return l.friendName;
    return n.split(' ').first;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final name = _displayName(l);
    const url =
        'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/app/photo-1564352969906-8b7f46ba4b8b.avif?token=eyJraWQiOiJhZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJhcHAvcGhvdG8tMTU2NDM1Mjk2OTkwNi04YjdmNDZiYTRiOGIuYXZpZiIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODc4Njg2MjksImV4cCI6MTgxOTQwNDYyOX0.Jdl-6cqT6wHh_nv8j-7oD3zjU2KcoR4e5ohJVnZgTNs';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.svcHero,
        image: const DecorationImage(
          image: NetworkImage(url),
          fit: BoxFit.cover,
          opacity: 0.85,
        ),
      ),
      child: Stack(
        children: [
          // Background gradient to ensure text readability over the image
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.2),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.4),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Top status row ─────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: onDetectLocation,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              detectingLocation
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.svcHeroAccent,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.location_on_outlined,
                                      color: AppColors.svcHeroAccent,
                                      size: 16,
                                    ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  currentLocation,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.svcHeroInk,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const _LanguagePill(),
                      const SizedBox(width: 10),
                      _BellButton(
                        unreadCount: unreadCount,
                        onTap: onBellTap,
                      ),
                      const SizedBox(width: 10),
                      _HeroAvatar(name: name, imageUrl: avatarUrl),
                    ],
                  ),
                ),
                // ── Live clock (auto-detected from device timezone) ────
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: _WorldClock(),
                ),
                // ── Big featured copy + illustration panel ──────────────
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
                  child: _HeroFeatured(name: name),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguagePill extends StatefulWidget {
  const _LanguagePill();
  @override
  State<_LanguagePill> createState() => _LanguagePillState();
}

class _LanguagePillState extends State<_LanguagePill> {
  void _onSelect(String code) {
    HapticFeedback.selectionClick();
    context.read<LocaleProvider>().setByCode(code);
  }

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    final l = AppLocalizations.of(context)!;
    final currentLabel =
        localeProvider.languageCode == 'en' ? 'English' : 'বাংলা';

    return PopupMenuButton<String>(
      onSelected: _onSelect,
      offset: const Offset(0, 40),
      color: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: 'bn',
          child: Row(
            children: [
              if (localeProvider.languageCode == 'bn')
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.check, size: 16, color: AppColors.svcHero),
                ),
              Text(l.languageBn,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'en',
          child: Row(
            children: [
              if (localeProvider.languageCode == 'en')
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.check, size: 16, color: AppColors.svcHero),
                ),
              Text(l.languageEn,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.language_rounded,
            color: AppColors.svcHeroInk,
            size: 18,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              currentLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.svcHeroInk,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.1,
              ),
            ),
          ),
          const SizedBox(width: 2),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.svcHeroInk,
            size: 20,
          ),
        ],
      ),
    );
  }
}

class _BellButton extends StatelessWidget {
  final int unreadCount;
  final VoidCallback onTap;
  const _BellButton({required this.unreadCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.notifications_none_rounded,
                    color: AppColors.svcHeroInk,
                    size: 20,
                  ),
                ),
              ),
              if (unreadCount > 0)
                Positioned(
                  right: 2,
                  top: 4,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.rose,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.svcHero,
                        width: 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      unreadCount > 9 ? '9+' : '$unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroAvatar extends StatelessWidget {
  final String name;
  final String imageUrl;
  const _HeroAvatar({required this.name, required this.imageUrl});

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'আ';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = imageUrl.isNotEmpty;
    return Pressable(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        );
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.zero,
          color: Colors.white.withValues(alpha: 0.95),
          border: Border.all(
            color: AppColors.svcHeroAccent,
            width: 2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        child: hasPhoto
            ? Image.network(
                imageUrl,
                fit: BoxFit.cover,
                width: 40,
                height: 40,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => _AvatarFallback(initials: _initials),
                loadingBuilder: (ctx, child, prog) {
                  if (prog == null) return child;
                  return _AvatarFallback(initials: _initials);
                },
              )
            : _AvatarFallback(initials: _initials),
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  final String initials;
  const _AvatarFallback({required this.initials});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.zero,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE8F2EB), Color(0xFFCDE8D8)],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: AppColors.svcHero,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
//  WORLD CLOCK — live time, auto-detected from device timezone.
//  No GPS / location permission required; we use the device's local
//  timezone which is already accurate enough for "Dhaka 10:42 PM".
// ════════════════════════════════════════════════════════════════════════

class _WorldClock extends StatefulWidget {
  const _WorldClock();

  @override
  State<_WorldClock> createState() => _WorldClockState();
}

class _WorldClockState extends State<_WorldClock> {
  late Timer _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    // Tick once per second so the seconds feel live without burning CPU.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  /// Returns the device timezone name, e.g. "Asia/Dhaka".
  /// Safe on all platforms; falls back to an empty string.
  String _zoneName() {
    try {
      // DateTime.now() reflects the device's local zone automatically. We
      // surface a friendly label via a small lookup, otherwise show the
      // numeric GMT offset (e.g. "GMT+06:00").
      final name = DateTime.now().timeZoneName;
      return name;
    } catch (_) {
      return '';
    }
  }

  /// Maps a raw DateTime.timeZoneName (which is usually the abbreviation
  /// like "BDT" or "BST") into a friendlier city where we can. Falls
  /// back to the GMT offset if we don't recognise it.
  String _friendlyZoneLabel(String raw) {
    // Common Bangladesh/South-Asia abbreviations — covers the
    // overwhelming majority of your user base.
    switch (raw.toUpperCase()) {
      case 'BDT':
        return 'Dhaka';
      case 'IST':
        return 'India';
      case 'PKT':
        return 'Karachi';
      case 'NPT':
        return 'Kathmandu';
    }
    // Try to resolve a real IANA name if available (Android/iOS expose
    // it via the intl package). Fall back to the raw abbreviation.
    try {
      final local = DateTime.now();
      final offset = local.timeZoneOffset;
      final sign = offset.isNegative ? '-' : '+';
      final h = offset.inHours.abs().toString().padLeft(2, '0');
      final m = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
      return 'GMT$sign$h:$m';
    } catch (_) {
      return raw.isEmpty ? 'Local' : raw;
    }
  }

  String _dayLabel() {
    // e.g. "Mon, 31 Aug" — locale follows the app's current locale.
    final fmt = DateFormat('EEE, d MMM', Localizations.localeOf(context).toString());
    return fmt.format(_now);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final zoneLabel = _friendlyZoneLabel(_zoneName());
    final timeFmt = DateFormat('hh:mm:ss a', Localizations.localeOf(context).toString());

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.zero,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.22),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Pulsing green dot — small "live" affordance.
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.svcHeroAccent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          // Left side: live HH:MM:SS AM/PM
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  timeFmt.format(_now),
                  style: const TextStyle(
                    color: AppColors.svcHeroInk,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                    height: 1.0,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.public_rounded,
                      color: AppColors.svcHeroInk,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '$zoneLabel • ${_dayLabel()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.svcHeroInk.withValues(alpha: 0.85),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Right side: small clock icon + city name pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.zero,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  color: AppColors.svcHero,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  l.localeName == 'bn' ? 'সময়' : 'Local',
                  style: const TextStyle(
                    color: AppColors.svcHero,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Big featured block on the hero — left: headline + sub + "Explore" CTA,
/// right: illustrated isometric scene (CustomPaint) so we don't need any
/// image assets. The illustration mirrors the reference's isometric
/// service-art panel but uses a meal-plan metaphor (lunchbox + bottle +
/// clipboard) to keep it on-brand for a diabetes-care app.
class _HeroFeatured extends StatelessWidget {
  final String name;
  const _HeroFeatured({required this.name});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l.heroHeadline,
                style: TextStyle(
                  color: AppColors.svcHeroInk,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  height: 1.08,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l.heroSubhead,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.svcHeroInk.withValues(alpha: 0.85),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              _ExplorePill(
                onTap: () {
                  HapticFeedback.selectionClick();
                  // The "অন্বেষণ করুন" CTA opens the in-app blog
                  // (Details Home) so the user can browse every
                  // Bangla explainer for the app's screens. We use
                  // the named route so the same screen is reachable
                  // from Profile and any future surface.
                  Navigator.of(context).pushNamed('/details-home');
                },
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 120,
          height: 130,
          child: CustomPaint(
            painter: _HeroIllustrationPainter(),
          ),
        ),
      ],
    );
  }
}

class _ExplorePill extends StatelessWidget {
  final VoidCallback onTap;
  const _ExplorePill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (l == null) return const SizedBox.shrink();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.zero,
      child: InkWell(
        borderRadius: BorderRadius.zero,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.zero,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l.exploreCta,
                style: const TextStyle(
                  color: AppColors.svcHero,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.arrow_forward_rounded,
                color: AppColors.svcHero,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Isometric illustration painter — three stacked "service cards" + a
/// stylized meal cup + clipboard so it reads like "manage your daily
/// diabetes care" without needing any image assets. Colors are pulled
/// from the brand palette (lime accent, deep green, soft mint).
class _HeroIllustrationPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── Back tile (isometric square, top face) ──────────────────
    final tileBack = Path()
      ..moveTo(w * 0.50, h * 0.32)
      ..lineTo(w * 0.92, h * 0.55)
      ..lineTo(w * 0.50, h * 0.78)
      ..lineTo(w * 0.08, h * 0.55)
      ..close();
    canvas.drawPath(
      tileBack,
      Paint()
        ..color = AppColors.svcHeroAccent.withValues(alpha: 0.95)
        ..style = PaintingStyle.fill,
    );

    // Front face of back tile (vertical strip).
    final frontBack = Path()
      ..moveTo(w * 0.50, h * 0.78)
      ..lineTo(w * 0.92, h * 0.55)
      ..lineTo(w * 0.92, h * 0.62)
      ..lineTo(w * 0.50, h * 0.85)
      ..close();
    canvas.drawPath(frontBack, Paint()..color = const Color(0xFF4A8B33));

    // ── Front tile (offset, slightly smaller, mint) ─────────────
    final tileFront = Path()
      ..moveTo(w * 0.40, h * 0.55)
      ..lineTo(w * 0.78, h * 0.76)
      ..lineTo(w * 0.40, h * 0.97)
      ..lineTo(w * 0.02, h * 0.76)
      ..close();
    canvas.drawPath(
      tileFront,
      Paint()..color = const Color(0xFFBFE2C9),
    );

    // ── Meal cup on top of front tile ───────────────────────────
    final cup = Rect.fromCenter(
      center: Offset(w * 0.30, h * 0.62),
      width: w * 0.22,
      height: h * 0.16,
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        cup,
        topLeft: const Radius.circular(6),
        topRight: const Radius.circular(6),
        bottomLeft: const Radius.circular(2),
        bottomRight: const Radius.circular(2),
      ),
      Paint()..color = Colors.white,
    );
    // Cup band
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(cup.center.dx, cup.top + cup.height * 0.25),
        width: cup.width,
        height: cup.height * 0.18,
      ),
      Paint()..color = AppColors.svcHeroAccent,
    );
    // Steam
    final steam = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final p1 = Path()
      ..moveTo(cup.center.dx - cup.width * 0.18, cup.top - 4)
      ..quadraticBezierTo(
        cup.center.dx - cup.width * 0.30,
        cup.top - 14,
        cup.center.dx - cup.width * 0.10,
        cup.top - 24,
      );
    canvas.drawPath(p1, steam);
    final p2 = Path()
      ..moveTo(cup.center.dx + cup.width * 0.12, cup.top - 4)
      ..quadraticBezierTo(
        cup.center.dx + cup.width * 0.24,
        cup.top - 12,
        cup.center.dx + cup.width * 0.06,
        cup.top - 20,
      );
    canvas.drawPath(p2, steam);

    // ── Clipboard on the back tile ──────────────────────────────
    final board = Rect.fromCenter(
      center: Offset(w * 0.62, h * 0.50),
      width: w * 0.22,
      height: h * 0.22,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(board, const Radius.circular(4)),
      Paint()..color = Colors.white,
    );
    // Lines on clipboard
    final line = Paint()
      ..color = AppColors.svcHero.withValues(alpha: 0.50)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final y = board.top + board.height * (0.35 + i * 0.18);
      canvas.drawLine(
        Offset(board.left + 4, y),
        Offset(board.right - 6, y),
        line,
      );
    }
    // Checkmark
    final check = Path()
      ..moveTo(board.left + board.width * 0.18, board.top + board.height * 0.55)
      ..lineTo(
          board.left + board.width * 0.40, board.top + board.height * 0.72)
      ..lineTo(
          board.left + board.width * 0.78, board.top + board.height * 0.30);
    canvas.drawPath(
      check,
      Paint()
        ..color = AppColors.svcHeroAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // ── Water bottle on side ────────────────────────────────────
    final bottle = Rect.fromLTWH(w * 0.78, h * 0.36, w * 0.10, h * 0.28);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bottle, const Radius.circular(4)),
      Paint()..color = const Color(0xFF8FD7E6),
    );
    final cap = Rect.fromCenter(
      center: Offset(bottle.center.dx, bottle.top - 4),
      width: bottle.width * 0.7,
      height: 8,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(cap, const Radius.circular(2)),
      Paint()..color = Colors.white,
    );
    // Label
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(bottle.center.dx, bottle.top + bottle.height * 0.45),
        width: bottle.width * 0.7,
        height: bottle.height * 0.32,
      ),
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ════════════════════════════════════════════════════════════════════════
//  SECTION HEADER ROW  — "Service Categories   View all >"
// ════════════════════════════════════════════════════════════════════════

class _SectionHeaderRow extends StatelessWidget {
  final String title;
  final String? bangla;
  final VoidCallback? onTap;
  const _SectionHeaderRow({required this.title, this.bangla, this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.newsInk,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
              if (bangla != null) ...[
                const SizedBox(height: 2),
                Text(
                  bangla!,
                  style: const TextStyle(
                    color: AppColors.newsMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (onTap != null)
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l.seeAll,
                    style: const TextStyle(
                      color: AppColors.newsMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.newsMuted,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
//  CATEGORY GRID — 2-column soft cards w/ outlined green icon + chevron
// ════════════════════════════════════════════════════════════════════════

enum _CategoryId { water, connected, meal, workout, medicine, analytics }

class _CategoryDef {
  final _CategoryId id;
  final IconData icon;
  const _CategoryDef({required this.id, required this.icon});

  String title(AppLocalizations l) {
    switch (id) {
      case _CategoryId.water:
        return l.localeName == 'bn' ? 'পানি' : 'Water';
      case _CategoryId.connected:
        return l.localeName == 'bn' ? 'পরিচর্যা' : 'Care';
      case _CategoryId.meal:
        return l.localeName == 'bn' ? 'খাবার' : 'Food';
      case _CategoryId.workout:
        return l.localeName == 'bn' ? 'ব্যায়াম' : 'Workout';
      case _CategoryId.medicine:
        return l.localeName == 'bn' ? 'ওষুধ' : 'Medicine';
      case _CategoryId.analytics:
        return l.localeName == 'bn' ? 'বিশ্লেষণ' : 'Analytics';
    }
  }

  String subtitle(AppLocalizations l) {
    switch (id) {
      case _CategoryId.water:
        return l.serviceWaterSub;
      case _CategoryId.connected:
        return l.serviceCareSub;
      case _CategoryId.meal:
        return l.serviceFoodSub;
      case _CategoryId.workout:
        return l.serviceWorkoutSub;
      case _CategoryId.medicine:
        return l.popularMedicineSub;
      case _CategoryId.analytics:
        return l.popularAnalyticsSub;
    }
  }
}

class _CategoryGrid extends StatelessWidget {
  final ValueChanged<_CategoryId> onOpen;
  const _CategoryGrid({required this.onOpen});

  static const _items = <_CategoryDef>[
    _CategoryDef(id: _CategoryId.water, icon: Icons.water_drop_outlined),
    _CategoryDef(id: _CategoryId.connected, icon: Icons.people_alt_outlined),
    _CategoryDef(id: _CategoryId.meal, icon: Icons.restaurant_menu_outlined),
    _CategoryDef(id: _CategoryId.workout, icon: Icons.fitness_center_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _CategoryCard(def: _items[0], onTap: () => onOpen(_items[0].id))),
            const SizedBox(width: 12),
            Expanded(child: _CategoryCard(def: _items[1], onTap: () => onOpen(_items[1].id))),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _CategoryCard(def: _items[2], onTap: () => onOpen(_items[2].id))),
            const SizedBox(width: 12),
            Expanded(child: _CategoryCard(def: _items[3], onTap: () => onOpen(_items[3].id))),
          ],
        ),
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final _CategoryDef def;
  final VoidCallback onTap;
  const _CategoryCard({required this.def, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.zero,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.zero,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.zero,
            border: Border.all(
              color: AppColors.svcCategoryBorder,
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.svcCategoryBg,
                  borderRadius: BorderRadius.zero,
                ),
                alignment: Alignment.center,
                child: Icon(
                  def.icon,
                  color: AppColors.svcAccentGreen,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      def.title(l),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.newsInk,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      def.subtitle(l),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.newsMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.newsMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiDashboardSlider extends StatefulWidget {
  const _AiDashboardSlider();

  @override
  State<_AiDashboardSlider> createState() => _AiDashboardSliderState();
}

class _AiDashboardSliderState extends State<_AiDashboardSlider> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  late Timer _timer;

  static const _banners = [
    (
      title: 'AI-এর মাধ্যমে খাবার যোগ করুন',
      subtitle: 'সহজেই স্বাস্থ্যকর তথ্য জানুন',
      imageUrl: 'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/dashboard/10.jpg?token=eyJraWQiOiJhZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJkYXNoYm9hcmQvMTAuanBnIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4ODQ5MTIwOSwiZXhwIjoxODIwMDI3MjA5fQ.6Wfon5XkaBHphiOVrbkJ698kh6hDLPgswA3DmLJKLrM',
      route: '/meal-plan',
    ),
    (
      title: 'AI-এর মাধ্যমে ওষুধ যোগ করুন',
      subtitle: 'ওষুধের সঠিক মাত্রা ও তথ্য জানুন',
      imageUrl: 'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/dashboard/11.jpg?token=eyJraWQiOiJhZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJkYXNoYm9hcmQvMTEuanBnIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4ODQ5MjQwOCwiZXhwIjoxODIwMDI4NDA4fQ.UsQyHTt2qREhinfogS6HDGhGullglQtVns2OgiawbMM',
      route: '/medicine',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_pageController.hasClients) {
        final next = (_currentPage + 1) % _banners.length;
        _pageController.animateToPage(
          next,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 180,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (idx) => setState(() => _currentPage = idx),
            itemCount: _banners.length,
            itemBuilder: (ctx, i) {
              final b = _banners[i];
              return _buildBanner(b);
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            _banners.length,
            (idx) => AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: _currentPage == idx ? 18 : 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: _currentPage == idx
                    ? AppColors.svcHero
                    : AppColors.lineStrong,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBanner(dynamic b) {
    return Pressable(
      onTap: () {
        HapticFeedback.selectionClick();
        if (b.route == '/meal-plan') {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MealPlanScreen()),
          );
        } else if (b.route == '/medicine') {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MedicineScreen()),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 4), // slight lift for shadow
        decoration: BoxDecoration(
          color: AppColors.svcHero,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: AppColors.svcCategoryBorder, width: 1.2),
          image: DecorationImage(
            image: NetworkImage(b.imageUrl),
            fit: BoxFit.cover,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        alignment: Alignment.bottomLeft,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black.withValues(alpha: 0.8),
                Colors.transparent,
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                b.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                ),
              ),
              Text(
                b.subtitle,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
//  TASK GRID — 2x2 technical grid for primary participation items
// ════════════════════════════════════════════════════════════════════════

class _TaskGrid extends StatelessWidget {
  final VoidCallback onWater, onWorkout, onMeal, onMedicine;
  const _TaskGrid({required this.onWater, required this.onWorkout, required this.onMeal, required this.onMedicine});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _TaskCard(
                title: l.localeName == 'bn' ? 'পানি পান' : 'Drink Water',
                sub: l.localeName == 'bn' ? 'লক্ষ্য: ২.৫ লিটার' : 'Goal: 2.5 Liters',
                icon: Icons.water_drop_rounded,
                color: Colors.blue,
                onTap: onWater,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TaskCard(
                title: l.localeName == 'bn' ? 'ব্যায়াম করুন' : 'Workout',
                sub: l.localeName == 'bn' ? 'আজকের রুটিন' : 'Daily routine',
                icon: Icons.fitness_center_rounded,
                color: AppColors.svcHeroAccent,
                onTap: onWorkout,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _TaskCard(
                title: l.localeName == 'bn' ? 'খাবার লগ' : 'Log Meals',
                sub: l.localeName == 'bn' ? 'সুষম ডায়েট' : 'Balanced diet',
                icon: Icons.restaurant_rounded,
                color: AppColors.amber,
                onTap: onMeal,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TaskCard(
                title: l.localeName == 'bn' ? 'ওষুধ নিন' : 'Medicine',
                sub: l.localeName == 'bn' ? 'সময়মতো সেবন' : 'Take on time',
                icon: Icons.medication_rounded,
                color: AppColors.violet,
                onTap: onMedicine,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TaskCard extends StatelessWidget {
  final String title, sub;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _TaskCard({required this.title, required this.sub, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: AppColors.line, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.zero,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.ink),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.smoke),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
//  POPULAR SERVICES — horizontal carousel of full-bleed service cards
// ════════════════════════════════════════════════════════════════════════

class _PopularServicesCarousel extends StatelessWidget {
  const _PopularServicesCarousel();

  static const List<_PopularItem> _items = <_PopularItem>[
    _PopularItem(
      id: _PopularId.meal,
      rating: 4.8,
      reviews: 123,
      imageUrl: 'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/dashboard/1.jpg?token=eyJraWQiOiJhZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJkYXNoYm9hcmQvMS5qcGciLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzg3ODY5MjY2LCJleHAiOjE4MTk0MDUyNjZ9.LlLS-RVSnQys5CIKdlkrJOGN6HJEO5qZ68qtSW0LrOw',
    ),
    _PopularItem(
      id: _PopularId.workout,
      rating: 4.6,
      reviews: 98,
      imageUrl: 'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/dashboard/2.jpg?token=eyJraWQiOiJhZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJkYXNoYm9hcmQvMi5qcGciLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzg3ODY5Mjg5LCJleHAiOjE4MTk0MDUyODl9.trg07OGnChO8YCfafXtg76f3Rjq-2t4s217OrcirIvs',
    ),
    _PopularItem(
      id: _PopularId.medicine,
      rating: 4.9,
      reviews: 211,
      imageUrl: 'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/dashboard/3.jpg?token=eyJraWQiOiJhZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJkYXNoYm9hcmQvMy5qcGciLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzg3ODY5MzA3LCJleHAiOjE4MTk0MDUzMDd9.bZla6PaeS1WYXCoPxsYbekVHvkqq4O-hBEwSGTIbcXA',
    ),
    _PopularItem(
      id: _PopularId.analytics,
      rating: 4.7,
      reviews: 156,
      imageUrl: 'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/dashboard/3.jpg?token=eyJraWQiOiJhZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJkYXNoYm9hcmQvMy5qcGciLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzg3ODY5MzA3LCJleHAiOjE4MTk0MDUzMDd9.bZla6PaeS1WYXCoPxsYbekVHvkqq4O-hBEwSGTIbcXA',
    ),
    _PopularItem(
      id: _PopularId.water,
      rating: 4.8,
      reviews: 89,
      imageUrl: 'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/dashboard/water.jpg?token=eyJraWQiOiJhZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJkYXNoYm9hcmQvd2F0ZXIuanBnIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4Nzg2OTM3MiwiZXhwIjoxODE5NDA1MzcyfQ.irg07OGnChO8YCfafXtg76f3Rjq-2t4s217OrcirIvs',
    ),
    _PopularItem(
      id: _PopularId.profile,
      rating: 4.5,
      reviews: 42,
      imageUrl: 'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/dashboard/5.jpg?token=eyJraWQiOiJhZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJkYXNoYm9hcmQvNS5qcGciLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzg3ODY5MzU1LCJleHAiOjE4MTk0MDUzNTV9.y2uDhgk0AcWT4yp1G7sQ3RHV2asG26920hATV-PikAU',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 184,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) => _PopularCard(item: _items[i]),
      ),
    );
  }
}

enum _PopularId { meal, workout, medicine, analytics, water, profile }

class _PopularItem {
  final _PopularId id;
  final double rating;
  final int reviews;
  final String imageUrl;
  const _PopularItem({
    required this.id,
    required this.rating,
    required this.reviews,
    required this.imageUrl,
  });

  String title(AppLocalizations l) {
    switch (id) {
      case _PopularId.meal:
        return l.popularMeal;
      case _PopularId.workout:
        return l.popularWorkout;
      case _PopularId.medicine:
        return l.popularMedicine;
      case _PopularId.analytics:
        return l.popularAnalytics;
      case _PopularId.water:
        return l.popularWater;
      case _PopularId.profile:
        return l.popularProfile;
    }
  }

  String subtitle(AppLocalizations l) {
    switch (id) {
      case _PopularId.meal:
        return l.popularMealSub;
      case _PopularId.workout:
        return l.popularWorkoutSub;
      case _PopularId.medicine:
        return l.popularMedicineSub;
      case _PopularId.analytics:
        return l.popularAnalyticsSub;
      case _PopularId.water:
        return l.popularWaterSub;
      case _PopularId.profile:
        return l.popularProfileSub;
    }
  }
}

class _PopularCard extends StatelessWidget {
  final _PopularItem item;
  const _PopularCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: Border.all(
          color: AppColors.svcCategoryBorder,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top image block.
          Expanded(
            child: Image.network(
              item.imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: AppColors.svcCategoryBg,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined, color: AppColors.svcHero, size: 48),
              ),
            ),
          ),
          // Bottom info.
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      color: Color(0xFFF5B400),
                      size: 16,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${item.rating.toStringAsFixed(1)} (${item.reviews} ${l.reviewsLabel})',
                      style: const TextStyle(
                        color: AppColors.newsMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.title(l),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.newsInk,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l.priceFree,
                  style: const TextStyle(
                    color: AppColors.newsMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Error state (preserved) ──────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(
            Icons.cloud_off_rounded,
            color: AppColors.brandMaroon,
            size: 42,
          ),
          const SizedBox(height: 12),
          Text(
            l.loadFailed,
            style: const TextStyle(
              color: AppColors.brandMaroon,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            error.toString(),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.brandMaroon.withValues(alpha: 0.6),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          MonoButton(
            label: l.retry,
            leading: Icons.refresh_rounded,
            onPressed: onRetry,
          ),
        ]),
      ),
    );
  }
}