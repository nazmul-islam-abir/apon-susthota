/// Dashboard — the landing page (tab index 0).
///
/// Layout, top to bottom (news / blog style — matches the reference design):
///  • Brand top bar — "Amar Diet" wordmark + Bengali tagline, search & bell
///  • Horizontal category pill row (৪ × "সকাল / দুপুর / সন্ধ্যা / রাত")
///    with circular food thumbnails
///  • Big serif-feel header "Recent news" → "আজকের বিশেষ" (featured meal
///    carousel: full-bleed image + dark gradient + category badge +
///    headline + chef avatar)
///  • Big serif-feel header "Trending news" → "আজকের পরিকল্পনা" (list of
///    thumb + category + headline + author rows)
///  • Compact clinical snapshot card (glucose tier, BP tier, carb/sodium caps)
///  • Tap anywhere on a card → routes to the corresponding screen
///
/// Color palette: warm off-white canvas, near-black ink, white cards with
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/dashboard.dart';
import '../models/meal_item.dart';
import '../models/user_meal_plan.dart';
import '../models/user_profile.dart';
import '../models/workout.dart';
import '../services/app_events.dart';
import '../services/diet_recommender.dart';
import '../services/plan_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/clinical_snapshot.dart';
import '../widgets/mono_widgets.dart';
import 'meal_plan_screen.dart';
import 'profile_screen.dart';
import 'workout_screen.dart';
import 'analytics_screen.dart';
import 'medicine_screen.dart';
import 'water_screen.dart';
import 'water_analytics_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<_DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    AppEvents.profileChanged.addListener(_onChanged);
    AppEvents.mealLogged.addListener(_onChanged);
    AppEvents.medicineChanged.addListener(_onChanged);
    AppEvents.workoutChanged.addListener(_onChanged);
    AppEvents.waterChanged.addListener(_onChanged);
  }

  @override
  void dispose() {
    AppEvents.profileChanged.removeListener(_onChanged);
    AppEvents.mealLogged.removeListener(_onChanged);
    AppEvents.medicineChanged.removeListener(_onChanged);
    AppEvents.workoutChanged.removeListener(_onChanged);
    AppEvents.waterChanged.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    _future = _load();
    setState(() {});
  }

  Future<_DashboardData> _load() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final results = await Future.wait<dynamic>([
      SupabaseService.fetchProfile(),
      PlanService.classifyUser(),
      SupabaseService.getPlanProgress(),
      SupabaseService.getDashboardSummary(days: 7),
      SupabaseService.getWorkoutAdherence(days: 7),
      SupabaseService.getMealAdherence(days: 7),
      SupabaseService.getTodayDailyMetrics(),
    ]);
    final profile = results[0] as UserProfile?;
    final cls = results[1] != null
        ? DietClassification.fromJson(Map<String, dynamic>.from(results[1] as Map))
        : null;
    final progress = results[2] as PlanProgress?;
    final summary = results[3] as DashboardSummary?;
    final workoutAdherence = results[4] as WorkoutAdherence? ??
        (results[4] != null
            ? _adherenceFromAny(results[4])
            : WorkoutAdherence.empty);
    final mealAdherence = results[5] as MealAdherence? ??
        (results[5] != null
            ? _mealAdherenceFromAny(results[5])
            : MealAdherence.empty);
    final todayMetric = results[6];
    final waterLiters = todayMetric is DailyMetric
        ? todayMetric.waterLiters
        : (todayMetric is num ? todayMetric.toDouble() : 0.0);
    final plan = await _safeFetchDailyRecommendation(progress?.day ?? 1);

    // 7. Signed avatar URL with cache-busting.
    // We re-fetch the signed URL every time the dashboard reloads.
    String avatarUrl = '';
    final rawPath = profile?.avatarUrl;
    if (rawPath != null && rawPath.isNotEmpty) {
      try {
        final signed = await SupabaseService.getProfilePhotoUrl(rawPath);
        if (signed.isNotEmpty) {
          final joiner = signed.contains('?') ? '&' : '?';
          avatarUrl = '$signed${joiner}_v=${profile?.photoUploadCount ?? DateTime.now().millisecondsSinceEpoch}';
        }
      } catch (e) {
        debugPrint('Dashboard avatar fetch error: $e');
      }
    }

    return _DashboardData(
      profile: profile,
      classification: cls,
      planDayIndex: progress?.day ?? 1,
      streakDays: summary?.streakDays ?? 0,
      today: today,
      plan: plan,
      workoutAdherence: workoutAdherence,
      mealAdherence: mealAdherence,
      avatarUrl: avatarUrl,
      waterLiters: waterLiters,
      waterTargetLiters: 2.5, // diabetic default; matches WaterScreen
    );
  }

  /// Defensive coercion — `WorkoutAdherence.fromJson` wants a `Map<String,
  /// dynamic>`. Some RPCs return a list-of-rows; this collapses them
  /// into a single object so the profile header always has a number.
  WorkoutAdherence _adherenceFromAny(dynamic raw) {
    if (raw is WorkoutAdherence) return raw;
    if (raw is List) {
      int total = 0;
      int completed = 0;
      int daysActive = 0;
      for (final row in raw) {
        if (row is! Map) continue;
        final m = Map<String, dynamic>.from(row);
        final c = (m['completed'] ?? 0) as int;
        completed += c;
        total += (m['total'] ?? 0) as int;
        if (c > 0) daysActive++;
      }
      return WorkoutAdherence(
        totalSessions: total,
        completed: completed,
        completedPct: total == 0 ? 0 : (completed / total) * 100,
        currentStreakDays: 0,
        windowDays: 7,
        daysActive: daysActive,
      );
    }
    if (raw is Map) {
      return WorkoutAdherence.fromJson(Map<String, dynamic>.from(raw));
    }
    return WorkoutAdherence.empty;
  }

  /// Same defensive coercion for [MealAdherence].
  MealAdherence _mealAdherenceFromAny(dynamic raw) {
    if (raw is MealAdherence) return raw;
    if (raw is List) {
      int planned = 0;
      int eaten = 0;
      for (final row in raw) {
        if (row is! Map) continue;
        final m = Map<String, dynamic>.from(row);
        planned += (m['planned'] ?? 0) as int;
        eaten += (m['eaten'] ?? 0) as int;
      }
      return MealAdherence(
        planned: planned,
        eaten: eaten,
        eatenPct: planned == 0 ? 0 : (eaten / planned) * 100,
        currentStreakDays: 0,
        windowDays: 7,
      );
    }
    if (raw is Map) {
      return MealAdherence.fromJson(Map<String, dynamic>.from(raw));
    }
    return MealAdherence.empty;
  }

  /// Best-effort fetch — never breaks the dashboard if the RPC fails.
  /// Returns `[]` on any error so the featured carousel falls back to a
  /// curated default set.
  Future<List<MealSlotPlan>> _safeFetchDailyRecommendation(int day) async {
    try {
      final plan = await PlanService.getDayPlan(day);
      return plan.slots;
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.newsCanvas,
      body: SafeArea(
        child: FutureBuilder<_DashboardData>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                child: LoadingMark(),
              );
            }
            if (snap.hasError) {
              return _ErrorState(
                error: snap.error!,
                onRetry: _onChanged,
              );
            }
            final d = snap.data!;
            return RefreshIndicator(
              color: AppColors.newsInk,
              backgroundColor: AppColors.newsSurface,
              onRefresh: () async => _onChanged(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  _BrandTopBar(onBellTap: _openProfile),
                  const _BrandHairline(),
                  _ProfileHeader(
                    profile: d.profile,
                    avatarUrl: d.avatarUrl,
                    workoutAdherence: d.workoutAdherence,
                    mealAdherence: d.mealAdherence,
                    planDayIndex: d.planDayIndex,
                    onEdit: _openProfile,
                  ),
                  const SizedBox(height: 16),
                  _WaterEntryCard(
                    waterLiters: d.waterLiters,
                    targetLiters: d.waterTargetLiters,
                    onTap: _openWater,
                    onAnalyticsTap: _openWaterAnalytics,
                  ),
                  const SizedBox(height: 22),
                  _SectionSlider(
                    onSlideTap: _handleSlideTap,
                  ),
                  const SizedBox(height: 22),
                  const _CategoryPills(),
                  const SizedBox(height: 26),
                  const _SectionHeader(
                    title: 'ক্লিনিক্যাল সারসংক্ষেপ',
                    subtitle: 'আপনার বর্তমান স্বাস্থ্য অবস্থা',
                  ),
                  const SizedBox(height: 12),
                  ClinicalSnapshotCard(classification: d.classification),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openMealPlan() async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MealPlanScreen()),
    );
  }

  Future<void> _openWorkout() async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WorkoutScreen()),
    );
  }

  Future<void> _openAnalytics() async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
    );
  }

  Future<void> _openMedicine() async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MedicineScreen()),
    );
  }

  Future<void> _openWater() async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WaterScreen()),
    );
  }

  Future<void> _openWaterAnalytics() async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WaterAnalyticsScreen()),
    );
  }

  Future<void> _openProfile() async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
  }

  Future<void> _handleSlideTap(int i) async {
    switch (i) {
      case 0:
        await _openMealPlan();
        break;
      case 1:
        await _openWorkout();
        break;
      case 2:
        await _openAnalytics();
        break;
      case 3:
        await _openMedicine();
        break;
      case 4:
        await _openProfile();
        break;
    }
  }
}

class _DashboardData {
  final UserProfile? profile;
  final DietClassification? classification;
  final int planDayIndex;
  final int streakDays;
  final DateTime today;
  final List<MealSlotPlan> plan;
  final WorkoutAdherence workoutAdherence;
  final MealAdherence mealAdherence;
  final String avatarUrl;
  final double waterLiters;
  final double waterTargetLiters;
  _DashboardData({
    required this.profile,
    required this.classification,
    required this.planDayIndex,
    required this.streakDays,
    required this.today,
    required this.plan,
    required this.workoutAdherence,
    required this.mealAdherence,
    required this.avatarUrl,
    required this.waterLiters,
    required this.waterTargetLiters,
  });
}

// ────────────────────────────── Brand top bar ─────────────────────────────

/// Slim brand bar at the very top of the dashboard: gradient logo mark,
/// bold "Amar Diet" wordmark + Bengali tagline, and a right-side action
/// cluster (search + notification bell with a magenta unread dot).
class _BrandTopBar extends StatelessWidget {
  final VoidCallback onBellTap;
  const _BrandTopBar({required this.onBellTap});

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    // Small detail: the logo mark and the dot pulse softly to draw the
    // eye without dominating the calm news canvas.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 14, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const _LogoMark(size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    const Text(
                      'Amar',
                      style: TextStyle(
                        color: AppColors.newsInk,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.6,
                        height: 1.0,
                      ),
                    ),
                    // ignore: prefer_const_constructors
                    Text(
                      ' Diet',
                      style: TextStyle(
                        color: brightness == Brightness.dark
                            ? AppColors.newsInk
                            : AppColors.brandPinkDeep,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'আপনার দৈনিক ডায়াবেটিক সহকারী',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.newsMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          _IconAction(
            icon: Icons.search_rounded,
            onTap: () {
              HapticFeedback.selectionClick();
            },
            tooltip: 'খাবার খুঁজুন',
          ),
          const SizedBox(width: 6),
          _IconAction(
            icon: Icons.notifications_none_rounded,
            onTap: () {
              HapticFeedback.selectionClick();
              onBellTap();
            },
            tooltip: 'নোটিফিকেশন',
            showDot: true,
          ),
        ],
      ),
    );
  }
}

/// Gradient rounded-square logo with a tiny leaf glyph — the "A" of
/// Amar Diet, abstracted. The mark uses the brand pink-to-pink-deep
/// gradient and a small white "A" on top so it stays legible at any size.
class _LogoMark extends StatelessWidget {
  final double size;
  const _LogoMark({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brandPink, AppColors.brandPinkDeep],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandPinkDeep.withValues(alpha: 0.28),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft white leaf — the "A" mark is just decorative; readability
          // comes from the gradient and the bold weight of the wordmark.
          Icon(
            Icons.eco_rounded,
            size: size * 0.55,
            color: Colors.white.withValues(alpha: 0.95),
          ),
          // Tiny serif "A" tucked in the bottom-right of the mark.
          Positioned(
            right: size * 0.18,
            bottom: size * 0.10,
            child: Text(
              'A',
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.34,
                fontWeight: FontWeight.w900,
                fontFamily: 'Georgia',
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Round tappable icon button used in the brand bar.
class _IconAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool showDot;
  const _IconAction({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.showDot = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.newsSurfaceSoft.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 22,
                color: AppColors.newsInk,
              ),
            ),
            if (showDot)
              Positioned(
                top: 9,
                right: 9,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: AppColors.brandPinkDeep,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.newsCanvas,
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Thin gradient hairline used as the visual base for the brand bar.
class _BrandHairline extends StatelessWidget {
  const _BrandHairline();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.only(top: 10, bottom: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            AppColors.newsDivider,
            AppColors.brandPink.withValues(alpha: 0.45),
            AppColors.newsDivider,
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}

// ────────────────────────────── Profile header ────────────────────────────

/// Instagram-style profile block: avatar + identity + three live stats
/// (workouts done, meal adherence %, current plan day) and a small
/// meta strip (classification / activity level) underneath.
///
/// All numbers come from the dashboard payload — no extra fetches.
class _ProfileHeader extends StatelessWidget {
  final UserProfile? profile;
  final String avatarUrl;
  final WorkoutAdherence workoutAdherence;
  final MealAdherence mealAdherence;
  final int planDayIndex;
  final VoidCallback onEdit;
  const _ProfileHeader({
    required this.profile,
    required this.avatarUrl,
    required this.workoutAdherence,
    required this.mealAdherence,
    required this.planDayIndex,
    required this.onEdit,
  });

  /// Initials for the avatar fallback when the photo isn't loaded.
  String _initials(String? name) {
    final raw = (name ?? '').trim();
    if (raw.isEmpty) return 'ব্�ব';
    // Pick the first two non-whitespace Bangla / Latin characters so
    // names like "Al sajmun saju" render as "AS" or similar. Falls back
    // to the first letter of the trimmed string if no whitespace.
    final parts = raw.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts[0].isNotEmpty ? parts[0][0] : '') +
          (parts[1].isNotEmpty ? parts[1][0] : '');
    }
    return raw.characters.first.toUpperCase();
  }

  /// Short Bangla role/goal line — pulled from classification-style
  /// heuristics the user already filled in during onboarding.
  String _roleLine(UserProfile? p) {
    if (p == null) return 'আপনার স্বাস্�্য সহকারী';
    final activity = switch (p.activityLevel) {
      'high' => 'উচ্চ সক্রিয়',
      'moderate' => 'মাঝারি সক্রিয়',
      _ => 'হালকা সক্রিয়',
    };
    final pref = switch (p.foodPreference) {
      'vegetarian' => 'নিরামিশাশী',
      'fish_only' => 'শুধু মাছ',
      'no_beef' => 'গরু ছাড়া',
      _ => 'সব খাবার',
    };
    return '$activity • $pref খাবার';
  }

  @override
  Widget build(BuildContext context) {
    final name = profile?.fullName?.trim();
    final display = (name?.isNotEmpty ?? false) ? name! : 'বন্ধু';
    final hasPhoto = avatarUrl.isNotEmpty;
    final mealPct = mealAdherence.eatenPct.round();
    final workoutsDone = workoutAdherence.completed;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Avatar(
                key: ValueKey(hasPhoto ? avatarUrl : 'no-photo'),
                initials: _initials(display),
                imageUrl: hasPhoto ? avatarUrl : null,
                size: 78,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            display,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.newsInk,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.verified_rounded,
                          size: 18,
                          color: AppColors.brandPinkDeep,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _roleLine(profile),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.newsMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _EditPill(onTap: onEdit),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: AppColors.newsDivider),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  value: '$workoutsDone',
                  label: 'Workouts',
                  caption: 'গত ৭ দিনে সম্পন্ন',
                ),
              ),
              _StatDivider(),
              Expanded(
                child: _StatTile(
                  value: '$mealPct%',
                  label: 'Meal plan',
                  caption: mealPct >= 80
                      ? 'দারুণ চালিয়ে যান'
                      : mealPct >= 40
                          ? 'আরেকটু মনোযোগ দিন'
                          : 'এখনো শুরু হয়নি',
                  highlight: mealPct >= 80,
                ),
              ),
              _StatDivider(),
              Expanded(
                child: _StatTile(
                  value: '${planDayIndex.clamp(1, 30)}/30',
                  label: 'Day',
                  caption: '৩০ দিনের পরিকল্পনা',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Round photo with a fallback initial avatar when the signed URL is
/// empty. Mirrors the "Instagram ring" feel — two layers of color so
/// the silhouette always reads as a profile circle even before the
/// image loads.
class _Avatar extends StatelessWidget {
  final String initials;
  final String? imageUrl;
  final double size;
  const _Avatar({
    super.key,
    required this.initials,
    required this.imageUrl,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size + 6,
      height: size + 6,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brandPink, AppColors.brandPinkDeep],
        ),
      ),
      alignment: Alignment.center,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.newsSurface,
        ),
        alignment: Alignment.center,
        clipBehavior: Clip.antiAlias,
        child: imageUrl != null && imageUrl!.isNotEmpty
            ? Image.network(
                imageUrl!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                // gaplessPlayback keeps the previous frame visible while
                // the new photo loads, instead of flashing the fallback.
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => _Fallback(initials: initials),
                loadingBuilder: (ctx, child, prog) {
                  if (prog == null) return child;
                  return _Fallback(initials: initials);
                },
              )
            : _Fallback(initials: initials),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  final String initials;
  const _Fallback({required this.initials});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE2C2), Color(0xFFCBE7C5)],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials.isEmpty ? '👤' : initials,
        style: const TextStyle(
          color: AppColors.newsInk,
          fontSize: 26,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// "Follow"-style pill that opens the profile screen.
class _EditPill extends StatelessWidget {
  final VoidCallback onTap;
  const _EditPill({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.newsInk,
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_outlined,
                size: 14, color: AppColors.newsOnPill),
            SizedBox(width: 6),
            Text(
              'Edit profile',
              style: TextStyle(
                color: AppColors.newsOnPill,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Single stat in the Instagram-style three-up row.
class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  final String caption;
  final bool highlight;
  const _StatTile({
    required this.value,
    required this.label,
    required this.caption,
    this.highlight = false,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: highlight
                ? AppColors.newsAccent
                : AppColors.newsInk,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1.1,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.newsInk,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          caption,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.newsMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

/// Hairline divider used between the three stat tiles.
class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 38,
      color: AppColors.newsDivider,
    );
  }
}

/// Dark, gradient-filled card used for the brand magenta dashboard.
/// News/blog dashboard widgets follow. The legacy magenta `DarkCard` /
/// `_HeroHeader` / `_ProfileCard` / `_FeatureGrid` / `_DateDetailCard` block
/// was removed during the v2 redesign — see commit notes for the diff.

// ────────────────────────────── Section slider ────────────────────────────

/// Auto-advancing PageView with 5 slides — one per major section of the
/// app (Meal Plan / Workouts / Analytics / Medicine / Profile). Each
/// slide is a full-bleed photo card styled like the featured carousel:
/// image → dark gradient → category badge + headline + tap-to-open.
///
/// Tapping a slide pushes the relevant screen via the supplied
/// [onTapMeal] / [onTapProfile] callbacks (wired in build()). Dots
/// beneath the slider show progress.
class _SectionSlider extends StatefulWidget {
  final ValueChanged<int> onSlideTap;
  const _SectionSlider({required this.onSlideTap});

  @override
  State<_SectionSlider> createState() => _SectionSliderState();
}

class _SectionSliderState extends State<_SectionSlider> {
  final PageController _ctrl = PageController(viewportFraction: 0.92);
  int _page = 0;

  static const _items = <_SectionSlide>[
    _SectionSlide(
      title: 'আজকের খাবারের পরিকল্পনা',
      caption: 'সকাল থেকে রাত — সব খাবার এক জায়গায়',
      category: 'Meal Plan',
      imageUrl:
          'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/dashboard/Gemini_Generated_Image_xji90jxji90jxji9.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV9hZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJkYXNoYm9hcmQvR2VtaW5pX0dlbmVyYXRlZF9JbWFnZV94amk5MGp4amk5MGp4amk5LmpwZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODcxOTE0OTQsImV4cCI6MTgxODcyNzQ5NH0.wXfEIfieKwlDXKGDFAR_pvjZPgYDZlmLolKWrz0B66M',
    ),
    _SectionSlide(
      title: 'ব্যায়াম',
      caption: '৩০ দিনের প্রগ্রেসিভ প্ল্যান',
      category: 'Workouts',
      imageUrl:
          'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/dashboard/Gemini_Generated_Image_kqmnbhkqmnbhkqmn.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV9hZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJkYXNoYm9hcmQvR2VtaW5pX0dlbmVyYXRlZF9JbWFnZV9rcW1uYmhrcW1uYmhrcW1uLmpwZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODcxOTE1ODUsImV4cCI6MTgxODcyNzU4NX0.fddA96fZA44N7JTVQIH7adNYIuer-EeJT_2Pg1EDQVI',
    ),
    _SectionSlide(
      title: 'বিশ্লেষণ',
      caption: 'সাপ্তাহিক অনুপাত ও ম্যাক্রো গড়',
      category: 'Analytics',
      imageUrl:
          'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/dashboard/Gemini_Generated_Image_1e73cr1e73cr1e73.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV9hZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJkYXNoYm9hcmQvR2VtaW5pX0dlbmVyYXRlZF9JbWFnZV8xZTczY3IxZTczY3IxZTczLmpwZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODcxOTE2MzYsImV4cCI6MTgxODcyNzYzNn0.LGt7dfIVJI_wLWh5de9lUncPmKmIL3ayRs1PpAOp2UQ',
    ),
    _SectionSlide(
      title: 'ওষুধ',
      caption: 'সময়সূচী ও ডোজ লগ',
      category: 'Medicine',
      imageUrl:
          'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/dashboard/Gemini_Generated_Image_oqo152oqo152oqo1.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV9hZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJkYXNoYm9hcmQvR2VtaW5pX0dlbmVyYXRlZF9JbWFnZV9vcW8xNTJvcW8xNTJvcW8xLmpwZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODcxOTE1MzIsImV4cCI6MTgxODcyNzUzMn0.iX0ncXWvA7CluXqdFdD6S_k1fpdnVxAMMB6WedFzoRM',
    ),
    _SectionSlide(
      title: 'প্রোফাইল',
      caption: 'আপনার স্বাস্থ্য তথ্য ও সেটিংস',
      category: 'Profile',
      imageUrl:
          'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/dashboard/Gemini_Generated_Image_49r3ls49r3ls49r3.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV9hZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJkYXNoYm9hcmQvR2VtaW5pX0dlbmVyYXRlZF9JbWFnZV80OXIzbHM0OXIzbHM0OXIzLmpwZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODcxOTE2MTMsImV4cCI6MTgxODcyNzYxM30.hRDAojuwrMnPxz7DhZD7TOsu5J_5XNA8PVtqzELnFSQ',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onScroll);
    _ctrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    final p = (_ctrl.page ?? 0).round();
    if (p != _page) setState(() => _page = p);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 200,
          child: PageView.builder(
            controller: _ctrl,
            itemCount: _items.length,
            itemBuilder: (_, i) {
              final s = _items[i];
              return _SectionSlideCard(
                slide: s,
                onTap: () => _handleTap(i),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        _DotIndicator(count: _items.length, active: _page),
      ],
    );
  }

  void _handleTap(int i) {
    HapticFeedback.selectionClick();
    widget.onSlideTap(i);
  }
}

class _SectionSlide {
  final String title;
  final String caption;
  final String category;
  final String imageUrl;
  const _SectionSlide({
    required this.title,
    required this.caption,
    required this.category,
    required this.imageUrl,
  });
}

class _SectionSlideCard extends StatelessWidget {
  final _SectionSlide slide;
  final VoidCallback onTap;
  const _SectionSlideCard({required this.slide, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                slide.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFCBE7C5), Color(0xFF1F3D2B)],
                    ),
                  ),
                ),
                loadingBuilder: (ctx, child, prog) {
                  if (prog == null) return child;
                  return const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFE2E0DC), Color(0xFF8E8E93)],
                      ),
                    ),
                  );
                },
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xCC0F1015)],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.newsAccent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          slide.category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          slide.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          slide.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xCCFFFFFF),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DotIndicator extends StatelessWidget {
  final int count;
  final int active;
  const _DotIndicator({required this.count, required this.active});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++) ...[
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            width: i == active ? 22 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == active
                  ? AppColors.newsInk
                  : AppColors.newsInk.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          if (i != count - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

// ────────────────────────────── Category pills ─────────────────────────────

/// Horizontal row of circular category pills (সকাল / দুপুর / সন্ধ্যা / রাত)
/// with category icon, label, and caption. Matches the reference design's
/// "Tech / Crypto / Business" chip row.
class _CategoryPills extends StatelessWidget {
  const _CategoryPills();

  static const _items = <_CategoryDef>[
    _CategoryDef(
      label: 'সকাল',
      caption: 'Breakfast',
      color: Color(0xFFFFE2C2),
      icon: Icons.wb_sunny_outlined,
    ),
    _CategoryDef(
      label: 'দুপুর',
      caption: 'Lunch',
      color: Color(0xFFCBE7C5),
      icon: Icons.rice_bowl_outlined,
    ),
    _CategoryDef(
      label: 'সন্ধ্যা',
      caption: 'Snack',
      color: Color(0xFFF5C9D2),
      icon: Icons.local_cafe_outlined,
    ),
    _CategoryDef(
      label: 'রাত',
      caption: 'Dinner',
      color: Color(0xFFCFD8EE),
      icon: Icons.nightlight_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) => _CategoryChip(def: _items[i]),
      ),
    );
  }
}

class _CategoryDef {
  final String label;
  final String caption;
  final Color color;
  final IconData icon;
  const _CategoryDef({
    required this.label,
    required this.caption,
    required this.color,
    required this.icon,
  });
}

class _CategoryChip extends StatelessWidget {
  final _CategoryDef def;
  const _CategoryChip({required this.def});
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: def.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Icon(def.icon, size: 30, color: AppColors.newsInk),
        ),
        const SizedBox(height: 8),
        Text(
          def.label,
          style: const TextStyle(
            color: AppColors.newsInk,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          def.caption,
          style: const TextStyle(
            color: AppColors.newsMuted,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────── Section header ────────────────────────────

/// Big bold header used for "আজকের বিশেষ" / "আজকের পরিকল্পনা" sections.
class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const _SectionHeader({required this.title, this.subtitle});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.newsInk,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            height: 1.1,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: const TextStyle(
              color: AppColors.newsMuted,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}
// ─────────────────────────────── Error state ───────────────────────────────

class _ErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_rounded,
              color: AppColors.brandMaroon, size: 42),
          const SizedBox(height: 12),
          const Text('ডেটা লোড করা যাচ্ছে না',
              style: TextStyle(
                color: AppColors.brandMaroon,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              )),
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
            label: 'আবার চেষ্টা করুন',
            leading: Icons.refresh_rounded,
            onPressed: onRetry,
          ),
        ]),
      ),
    );
  }
}

// ──────────────────────────── Water entry card ──────────────────────────────

/// Compact dashboard card that bridges to [WaterScreen]. Shows the
/// user's water progress today with a glass icon, a mini progress
/// ring, and a "+1 glass" hint chip — matches the visual rhythm of
/// the other dashboard tiles.
class _WaterEntryCard extends StatelessWidget {
  final double waterLiters;
  final double targetLiters;
  final VoidCallback onTap;
  final VoidCallback? onAnalyticsTap;
  const _WaterEntryCard({
    required this.waterLiters,
    required this.targetLiters,
    required this.onTap,
    this.onAnalyticsTap,
  });

  @override
  Widget build(BuildContext context) {
    final glassesDrank = (waterLiters / 0.25).round();
    final glassesTarget = (targetLiters / 0.25).round();
    final pct = targetLiters <= 0
        ? 0.0
        : (waterLiters / targetLiters).clamp(0.0, 1.0);
    final done = pct >= 1.0;

    return Pressable(
      onTap: onTap,
      pressScale: 0.985,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: AppColors.newsSurface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.newsDivider, width: 1),
          boxShadow: AppGlass.shadow(opacity: 0.05, blur: 18, y: 6),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _MiniGlass(progress: pct, done: done),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'পানি',
                          style: TextStyle(
                            color: AppColors.newsInk,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                            height: 1.0,
                          ),
                        ),
                        SizedBox(width: 8),
                        Padding(
                          padding: EdgeInsets.only(bottom: 1),
                          child: Text(
                            'আজকের লক্ষ্য',
                            style: TextStyle(
                              color: AppColors.newsMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text.rich(
                      TextSpan(
                        style: const TextStyle(
                          color: AppColors.newsInk,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          height: 1.0,
                        ),
                        children: [
                          TextSpan(text: waterLiters.toStringAsFixed(2)),
                          const TextSpan(
                            text: ' / ',
                            style: TextStyle(
                              color: AppColors.newsMuted,
                              fontSize: 14,
                            ),
                          ),
                          TextSpan(text: targetLiters.toStringAsFixed(1)),
                          const TextSpan(
                            text: ' L',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.newsMuted,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        // 8 little glass dots so the elderly user can see
                        // progress countably (one dot per glass target).
                        for (var i = 0; i < glassesTarget; i++) ...[
                          _GlassDot(
                            filled: i < glassesDrank,
                            doneTint: done,
                          ),
                          if (i != glassesTarget - 1) const SizedBox(width: 4),
                        ],
                        const SizedBox(width: 10),
                        Text(
                          '$glassesDrank/$glassesTarget গ্লাস',
                          style: const TextStyle(
                            color: AppColors.newsMuted,
                            fontWeight: FontWeight.w800,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _CtaChip(done: done),
            if (onAnalyticsTap != null) ...[
              const SizedBox(width: 6),
              Pressable(
                onTap: onAnalyticsTap!,
                pressScale: 0.92,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.newsAccent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.bar_chart_rounded,
                    color: AppColors.newsAccent,
                    size: 20,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Minimalist glass icon. Renders a tulip silhouette (matching the
/// hero on the water screen) plus a fill that grows as `progress`
/// climbs from 0..1.
class _MiniGlass extends StatelessWidget {
  final double progress;
  final bool done;
  const _MiniGlass({required this.progress, required this.done});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: CustomPaint(
        painter: _MiniGlassPainter(progress: progress, done: done),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _MiniGlassPainter extends CustomPainter {
  final double progress;
  final bool done;
  _MiniGlassPainter({required this.progress, required this.done});
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final outline = Path()
      ..moveTo(w * 0.18, h * 0.12)
      ..lineTo(w * 0.24, h * 0.88)
      ..quadraticBezierTo(w * 0.50, h * 0.94, w * 0.76, h * 0.88)
      ..lineTo(w * 0.82, h * 0.12)
      ..quadraticBezierTo(w * 0.50, h * 0.06, w * 0.18, h * 0.12)
      ..close();

    final glass = Paint()..color = const Color(0xFFF8FAFC);
    canvas.drawPath(outline, glass);

    final waterTop = h * (1 - progress * 0.82);
    canvas.save();
    canvas.clipPath(outline);
    final water = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: done
            ? const [Color(0xFFA7F3D0), Color(0xFF10B981)]
            : const [Color(0xFFBFE3F2), Color(0xFF7FB8D6)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, waterTop, w, h), water);
    canvas.restore();

    final stroke = Paint()
      ..color = AppColors.newsInk.withValues(alpha: 0.78)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawPath(outline, stroke);
  }

  @override
  bool shouldRepaint(covariant _MiniGlassPainter old) =>
      old.progress != progress || old.done != done;
}

class _GlassDot extends StatelessWidget {
  final bool filled;
  final bool doneTint;
  const _GlassDot({required this.filled, required this.doneTint});

  @override
  Widget build(BuildContext context) {
    final color = !filled
        ? AppColors.newsDivider
        : (doneTint ? AppColors.newsAccent : AppColors.cyan);
    return Container(
      width: 10,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(3),
          bottomRight: Radius.circular(3),
          topLeft: Radius.circular(1),
          topRight: Radius.circular(1),
        ),
      ),
    );
  }
}

class _CtaChip extends StatelessWidget {
  final bool done;
  const _CtaChip({required this.done});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: done
            ? AppColors.newsAccent.withValues(alpha: 0.10)
            : AppColors.newsInk,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? Icons.check_rounded : Icons.add_rounded,
            color: done ? AppColors.newsAccent : Colors.white,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            done ? 'হয়েছে' : 'লগ করুন',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.1,
              color: done ? AppColors.newsAccent : Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
