/// Caretaker home dashboard — the landing page (tab index 0).
///
/// Mirrors the patient `DashboardScreen` structure section-by-section so the
/// caretaker app feels like the patient app, while keeping the
/// *read-only* semantics the role requires:
///
///   • Top hero — same forest-green gradient + image overlay. Includes a
///     language pill, a notification bell with unread badge, and the
///     caretaker's own avatar (tap → CaretakerProfileScreen).
///   • "Today's tasks" — read-only 2x2 grid that aggregates today's water,
///     meal, medicine and workout counts across **all** connected patients.
///     Tapping any card deep-links into the matching per-patient view for
///     the currently-selected patient (if any).
///   • "Categories" — soft-bordered 2x2 cards for notification, notice,
///     blog, and the caretaker's own profile.
///   • "Connected patients" — vertical list of patient cards (same widget
///     as the patients tab, pulled from `lib/widgets/caretaker_patient_card.dart`).
///   • "Popular services" — horizontal carousel of full-bleed cards for
///     analytics, doctor report, SOS, and the app guide.
///
/// Patients can give data (water/meal/medicine/workout). Caretakers cannot
/// — they only see the data. The dashboard makes that distinction obvious
/// by labelling every input section "শুধুমাত্র দেখুন" (read-only) and
/// routing taps to view-only screens, never to the input screens.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/user_profile.dart';
import '../../services/caretaker_provider.dart';
import '../../services/notification_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/caretaker_patient_card.dart';
import '../analytics_screen.dart';
import '../doctor_report_screen.dart';
import '../notification_screen.dart';
import 'caretaker_profile_screen.dart';
import 'caretaker_meal_plan_view.dart';
import 'caretaker_medicine_view.dart';
import 'caretaker_notice_screen.dart';
import 'caretaker_shell.dart' show bnGreeting;
import 'caretaker_water_view.dart';
import 'caretaker_workout_view.dart';

const String _kCaretakerHeroUrl =
    'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/app/photo-1564352969906-8b7f46ba4b8b.avif?token=eyJraWQiOiJhZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJhcHAvcGhvdG8tMTU2NDM1Mjk2OTkwNi04YjdmNDZiYTRiOGIuYXZpZiIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODc4Njg2MjksImV4cCI6MTgxOTQwNDYyOX0.Jdl-6cqT6wHh_nv8j-7oD3zjU2KcoR4e5ohJVnZgTNs';

class CaretakerHomeDashboard extends StatefulWidget {
  final UserProfile? profile;
  final ValueChanged<int>? onSwitchTab;
  const CaretakerHomeDashboard({
    super.key,
    this.profile,
    this.onSwitchTab,
  });

  @override
  State<CaretakerHomeDashboard> createState() => _CaretakerHomeDashboardState();
}

class _CaretakerHomeDashboardState extends State<CaretakerHomeDashboard> {
  late Future<_DashboardData> _future;
  int _unreadCount = NotificationService.cachedUnread;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _refreshUnread();
  }

  Future<_DashboardData> _load() async {
    final prov = context.read<CaretakerProvider>();
    if (prov.patients.isEmpty) {
      return _DashboardData(aggregated: _AggregatedCounts.empty());
    }
    final pids = prov.patients.map((p) => p.patientUserId).toList();
    final overviews = await Future.wait(
      pids.map((id) async {
        try {
          return await SupabaseService.getCaretakerTodayOverview(patientUserId: id);
        } catch (_) {
          return <String, dynamic>{};
        }
      }),
    );
    return _DashboardData(
      aggregated: _AggregatedCounts.fromOverviews(overviews),
    );
  }

  Future<void> _refreshUnread() async {
    try {
      await NotificationService.load(force: true);
      final n = await NotificationService.refreshUnread();
      if (!mounted) return;
      setState(() => _unreadCount = n);
    } catch (_) {/* keep cached number */}
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _future = _load());
    _refreshUnread();
  }

  Future<void> _openNotifications() async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationScreen()),
    );
    _refreshUnread();
  }

  void _openOwnProfile() {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CaretakerProfileScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (l == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: AppColors.svcCategoryBg,
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: AppColors.svcHero,
          backgroundColor: Colors.white,
          onRefresh: () async {
            await context.read<CaretakerProvider>().refresh();
            _reload();
          },
          child: FutureBuilder<_DashboardData>(
            future: _future,
            builder: (context, snap) {
              final data = snap.data ??
                  _DashboardData(aggregated: _AggregatedCounts.empty());
              return ListView(
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
                  _Hero(
                    profile: widget.profile,
                    unreadCount: _unreadCount,
                    onBellTap: _openNotifications,
                    onAvatarTap: _openOwnProfile,
                  ),
                  const SizedBox(height: 22),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: MoodSection(
                      onMoodSaved: _reload,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _SectionHeaderRow(
                      title: 'পরিষেবা বিভাগ',
                      bangla: 'আপনার প্রয়োজনীয় সব সেবা',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _CategoryGrid(
                      onOpen: (id) => _openCategory(context, id),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _SectionHeaderRow(
                      title: 'আজকের সারাংশ',
                      bangla: 'সংযুক্ত রোগীদের সম্মিলিত তথ্য — শুধুমাত্র দেখুন',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _TaskGrid(
                      aggregated: data.aggregated,
                      onTaskTap: (id) => _openTask(context, id),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _SectionHeaderRow(
                      title: 'জনপ্রিয় পরিষেবা',
                      bangla: 'আরও দেখুন',
                    ),
                  ),
                  const SizedBox(height: 14),
                  const _PopularServicesCarousel(),
                  const SizedBox(height: 26),
                  _PatientsList(),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _openCategory(BuildContext context, _CategoryId id) async {
    HapticFeedback.selectionClick();
    switch (id) {
      case _CategoryId.notifications:
        await _openNotifications();
        break;
      case _CategoryId.notice:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CaretakerNoticeScreen()),
        );
        break;
      case _CategoryId.blog:
        await Navigator.of(context).pushNamed('/details-home');
        break;
      case _CategoryId.profile:
        _openOwnProfile();
        break;
    }
  }

  Future<void> _openTask(BuildContext context, _TaskId id) async {
    HapticFeedback.selectionClick();
    final prov = context.read<CaretakerProvider>();
    final selected = prov.selectedPatient;
    if (selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('প্রথমে একজন রোগী নির্বাচন করুন (তালিকা থেকে)'),
        ),
      );
      return;
    }
    switch (id) {
      case _TaskId.water:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CaretakerWaterView(patient: selected)),
        );
        break;
      case _TaskId.meal:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CaretakerMealPlanView(patient: selected)),
        );
        break;
      case _TaskId.workout:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CaretakerWorkoutView(patient: selected)),
        );
        break;
      case _TaskId.medicine:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CaretakerMedicineView(patient: selected)),
        );
        break;
    }
  }
}

class _DashboardData {
  final _AggregatedCounts aggregated;
  _DashboardData({required this.aggregated});
}

class _AggregatedCounts {
  final int mealsPlanned;
  final int mealsEaten;
  final int dosesPlanned;
  final int dosesTaken;
  final double waterLiters;
  final double waterTarget;
  final int workoutSeconds;

  const _AggregatedCounts({
    required this.mealsPlanned,
    required this.mealsEaten,
    required this.dosesPlanned,
    required this.dosesTaken,
    required this.waterLiters,
    required this.waterTarget,
    required this.workoutSeconds,
  });

  factory _AggregatedCounts.empty() => const _AggregatedCounts(
        mealsPlanned: 0,
        mealsEaten: 0,
        dosesPlanned: 0,
        dosesTaken: 0,
        waterLiters: 0,
        waterTarget: 2.5,
        workoutSeconds: 0,
      );

  factory _AggregatedCounts.fromOverviews(List<Map<String, dynamic>> overviews) {
    int mp = 0, me = 0, dp = 0, dt = 0, ws = 0;
    double wl = 0, wt = 0;
    for (final ov in overviews) {
      final meals = (ov['meals'] as List?) ?? const [];
      mp += meals.length;
      me += meals
          .where((m) => m is Map && (m['status'] == 'eaten' || m['status'] == 'swap'))
          .length;
      final med = ov['medicine'] as Map?;
      dp += _asInt(med?['total']);
      dt += _asInt(med?['taken']);
      wl += _asDouble(ov['water_liters']);
      wt += _asDouble(ov['water_target']);
      final wo = ov['workout'] as Map?;
      if (wo != null) {
        ws += _asInt(wo['duration_seconds']);
      }
    }
    if (wt <= 0) wt = 2.5 * overviews.length;
    return _AggregatedCounts(
      mealsPlanned: mp,
      mealsEaten: me,
      dosesPlanned: dp,
      dosesTaken: dt,
      waterLiters: wl,
      waterTarget: wt,
      workoutSeconds: ws,
    );
  }

  static int _asInt(Object? v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static double _asDouble(Object? v) {
    if (v == null) return 0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

class _Hero extends StatelessWidget {
  final UserProfile? profile;
  final int unreadCount;
  final VoidCallback onBellTap;
  final VoidCallback onAvatarTap;
  const _Hero({
    required this.profile,
    required this.unreadCount,
    required this.onBellTap,
    required this.onAvatarTap,
  });

  String _name() {
    final raw = (profile?.fullName ?? '').trim();
    if (raw.isEmpty) return bnGreeting();
    return '${bnGreeting()}, ${raw.split(' ').first}';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CaretakerProvider>(
      builder: (context, prov, _) {
        final patientCount = prov.patients.length;
        final pendingCount = prov.pending.length;
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.svcHero,
            image: DecorationImage(
              image: NetworkImage(_kCaretakerHeroUrl),
              fit: BoxFit.cover,
              opacity: 0.7,
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(color: Colors.black.withValues(alpha: 0.35)),
              ),
              SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Expanded(child: _LanguagePill()),
                          const SizedBox(width: 10),
                          _BellButton(
                            unreadCount: unreadCount,
                            onTap: onBellTap,
                          ),
                          const SizedBox(width: 10),
                          _HeroAvatar(onTap: onAvatarTap),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _name(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              height: 1.08,
                              letterSpacing: -0.6,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'আপনার $patientCount জন সংযুক্ত রোগী'
                            '${pendingCount > 0 ? ' • $pendingCountটি অনুরোধ অপেক্ষমাণ' : ''}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white12,
                              borderRadius: BorderRadius.zero,
                              border: Border.all(color: Colors.white24),
                            ),
                            child: const Text(
                              'পরিচর্যাকারী মোড • শুধুমাত্র দেখুন',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LanguagePill extends StatelessWidget {
  const _LanguagePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(
            Icons.language_rounded,
            color: Colors.white,
            size: 16,
          ),
          SizedBox(width: 6),
          Text(
            'বাংলা',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
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
                    color: Colors.white,
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
                      horizontal: 4,
                      vertical: 1,
                    ),
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
  final VoidCallback onTap;
  const _HeroAvatar({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.svcHeroAccent, width: 2),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.medical_services_rounded,
            color: AppColors.svcHero,
            size: 22,
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
//  SECTION HEADER ROW
// ════════════════════════════════════════════════════════════════════════

class _SectionHeaderRow extends StatelessWidget {
  final String title;
  final String? bangla;
  const _SectionHeaderRow({required this.title, this.bangla});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
//  CATEGORIES
// ════════════════════════════════════════════════════════════════════════

enum _CategoryId { notifications, notice, blog, profile }

class _CategoryDef {
  final _CategoryId id;
  final IconData icon;
  const _CategoryDef({required this.id, required this.icon});

  String title() {
    switch (id) {
      case _CategoryId.notifications:
        return 'বিজ্ঞপ্তি';
      case _CategoryId.notice:
        return 'নোটিশ';
      case _CategoryId.blog:
        return 'ব্লগ';
      case _CategoryId.profile:
        return 'প্রোফাইল';
    }
  }

  String subtitle() {
    switch (id) {
      case _CategoryId.notifications:
        return 'ইনবক্স ও আপডেট';
      case _CategoryId.notice:
        return 'সিস্টেম ঘোষণা';
      case _CategoryId.blog:
        return 'অ্যাপ গাইড';
      case _CategoryId.profile:
        return 'আমার তথ্য';
    }
  }
}

class _CategoryGrid extends StatelessWidget {
  final ValueChanged<_CategoryId> onOpen;
  const _CategoryGrid({required this.onOpen});

  static const _items = <_CategoryDef>[
    _CategoryDef(id: _CategoryId.notifications, icon: Icons.notifications_active_outlined),
    _CategoryDef(id: _CategoryId.notice, icon: Icons.campaign_outlined),
    _CategoryDef(id: _CategoryId.blog, icon: Icons.menu_book_outlined),
    _CategoryDef(id: _CategoryId.profile, icon: Icons.person_outline_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _CategoryCard(
                def: _items[0],
                onTap: () => onOpen(_items[0].id),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CategoryCard(
                def: _items[1],
                onTap: () => onOpen(_items[1].id),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _CategoryCard(
                def: _items[2],
                onTap: () => onOpen(_items[2].id),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CategoryCard(
                def: _items[3],
                onTap: () => onOpen(_items[3].id),
              ),
            ),
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
    return Material(
      color: Colors.white,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.zero,
            border: Border.all(color: AppColors.svcCategoryBorder, width: 1),
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
                      def.title(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.newsInk,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      def.subtitle(),
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

// ════════════════════════════════════════════════════════════════════════
//  TODAY'S TASKS (aggregated, read-only)
// ════════════════════════════════════════════════════════════════════════

enum _TaskId { water, meal, workout, medicine }

class _TaskGrid extends StatelessWidget {
  final _AggregatedCounts aggregated;
  final ValueChanged<_TaskId> onTaskTap;
  const _TaskGrid({required this.aggregated, required this.onTaskTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _TaskCard(
                title: 'পানি',
                sub: aggregated.waterLiters <= 0
                    ? 'আজকের সারাংশ'
                    : '${aggregated.waterLiters.toStringAsFixed(1)} / ${aggregated.waterTarget.toStringAsFixed(1)} L',
                icon: Icons.water_drop_rounded,
                color: Colors.blue,
                onTap: () => onTaskTap(_TaskId.water),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TaskCard(
                title: 'খাবার',
                sub: aggregated.mealsPlanned == 0
                    ? 'কোনো তথ্য নেই'
                    : '${aggregated.mealsEaten} / ${aggregated.mealsPlanned} সম্পন্ন',
                icon: Icons.restaurant_rounded,
                color: AppColors.amber,
                onTap: () => onTaskTap(_TaskId.meal),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _TaskCard(
                title: 'ব্যায়াম',
                sub: aggregated.workoutSeconds == 0
                    ? 'কোনো তথ্য নেই'
                    : '${(aggregated.workoutSeconds / 60).round()} মিনিট',
                icon: Icons.fitness_center_rounded,
                color: AppColors.svcHeroAccent,
                onTap: () => onTaskTap(_TaskId.workout),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TaskCard(
                title: 'ওষুধ',
                sub: aggregated.dosesPlanned == 0
                    ? 'কোনো তথ্য নেই'
                    : '${aggregated.dosesTaken} / ${aggregated.dosesPlanned} ডোজ',
                icon: Icons.medication_rounded,
                color: AppColors.violet,
                onTap: () => onTaskTap(_TaskId.medicine),
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
  const _TaskCard({
    required this.title,
    required this.sub,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
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
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.smoke,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(
                    Icons.visibility_outlined,
                    color: AppColors.lineStrong,
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'শুধুমাত্র দেখুন',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: AppColors.smoke,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
//  POPULAR SERVICES CAROUSEL
// ════════════════════════════════════════════════════════════════════════

class _PopularServicesCarousel extends StatelessWidget {
  const _PopularServicesCarousel();

  Future<void> _open(BuildContext context, _PopularId id) async {
    HapticFeedback.selectionClick();
    switch (id) {
      case _PopularId.analytics:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
        );
        break;
      case _PopularId.doctorReport:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DoctorReportScreen()),
        );
        break;
      case _PopularId.sos:
        await Navigator.of(context).pushNamed('/sos');
        break;
      case _PopularId.appGuide:
        await Navigator.of(context).pushNamed('/details-home');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = <_PopularItem>[
      const _PopularItem(
        id: _PopularId.analytics,
        title: 'বিশ্লেষণ',
        subtitle: '৭ দিনের প্রবণতা',
        color: AppColors.svcHero,
      ),
      const _PopularItem(
        id: _PopularId.doctorReport,
        title: 'ডাক্তারের রিপোর্ট',
        subtitle: '৩০ দিনের সারসংক্ষেপ',
        color: AppColors.rose,
      ),
      const _PopularItem(
        id: _PopularId.sos,
        title: 'জরুরি যোগাযোগ',
        subtitle: 'দ্রুত সাহায্য',
        color: AppColors.violet,
      ),
      const _PopularItem(
        id: _PopularId.appGuide,
        title: 'অ্যাপ গাইড',
        subtitle: 'কীভাবে ব্যবহার করবেন',
        color: AppColors.amber,
      ),
    ];
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _PopularCard(
          item: items[i],
          onTap: () => _open(context, items[i].id),
        ),
      ),
    );
  }
}

enum _PopularId { analytics, doctorReport, sos, appGuide }

class _PopularItem {
  final _PopularId id;
  final String title;
  final String subtitle;
  final Color color;
  const _PopularItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.color,
  });
}

class _PopularCard extends StatelessWidget {
  final _PopularItem item;
  final VoidCallback onTap;
  const _PopularCard({required this.item, required this.onTap});

  IconData get _icon {
    switch (item.id) {
      case _PopularId.analytics:
        return Icons.bar_chart_rounded;
      case _PopularId.doctorReport:
        return Icons.picture_as_pdf_rounded;
      case _PopularId.sos:
        return Icons.sos_rounded;
      case _PopularId.appGuide:
        return Icons.menu_book_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 200,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.zero,
            border: Border.all(color: AppColors.svcCategoryBorder, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.zero,
                ),
                alignment: Alignment.center,
                child: Icon(
                  _icon,
                  color: item.color,
                  size: 22,
                ),
              ),
              const Spacer(),
              Text(
                item.title,
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
                item.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.newsMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
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
//  CONNECTED PATIENTS LIST
// ════════════════════════════════════════════════════════════════════════

class _PatientsList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<CaretakerProvider>(
      builder: (context, prov, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: _SectionHeaderRow(
                title: 'সংযুক্ত রোগী',
                bangla: 'আপনার তত্ত্বাবধানে (${prov.patients.length} জন)',
              ),
            ),
            if (prov.loadingPatients && prov.patients.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.svcHero),
                ),
              )
            else if (prov.patients.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.zero,
                    border: Border.all(color: AppColors.line, width: 1.2),
                  ),
                  child: Column(
                    children: const [
                      Icon(
                        Icons.people_outline_rounded,
                        color: AppColors.lineStrong,
                        size: 56,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'এখনো কোনো রোগী সংযুক্ত নেই',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: AppColors.ink,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '“খোঁজা” ট্যাব থেকে মোবাইল নম্বর দিয়ে\nরোগীকে খুঁজে সংযোগের অনুরোধ পাঠান।',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.smoke,
                          fontWeight: FontWeight.w700,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: Column(
                  children: [
                    for (var i = 0; i < prov.patients.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      CaretakerPatientCard(patient: prov.patients[i]),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
//  MOOD SECTION — caretaker-side mood check-in (lightweight banner).
// ════════════════════════════════════════════════════════════════════════

class MoodSection extends StatelessWidget {
  final VoidCallback onMoodSaved;
  const MoodSection({super.key, required this.onMoodSaved});

  @override
  Widget build(BuildContext context) {
    // Caretakers don't have a per-day mood requirement, so we render a
    // compact "তথ্য শীঘ্রই আসছে" banner instead of the patient's mood
    // recorder. This keeps the chrome consistent with the patient
    // dashboard (same section position + spacing) without pulling in a
    // mood-recording UI that wouldn't make sense for the role.
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.line, width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.svcCategoryBg,
              borderRadius: BorderRadius.zero,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.tips_and_updates_outlined,
              color: AppColors.svcHero,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'পরিচর্যা পরামর্শ',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'রোগীর দৈনিক তথ্যের উপর ভিত্তি করে স্বয়ংক্রিয় পরামর্শ',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.smoke,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.lineStrong,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}

