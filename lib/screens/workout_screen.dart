// আমার ডায়েট — Workout screen (v5 Redesign).
library;

import 'package:amar_diet/screens/water_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/workout.dart';
import '../services/app_events.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';
import '../widgets/tab_history_mixin.dart';
import 'workout_details_screen.dart';

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  TodaysWorkout? _todays;
  WorkoutTimeTracking _tracking = WorkoutTimeTracking.empty;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    AppEvents.workoutChanged.addListener(_onChanged);
  }

  @override
  void dispose() {
    AppEvents.workoutChanged.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      await SupabaseService.ensureDefaultWorkoutAssignments();
      await SupabaseService.seedMyWorkoutAssignments();
      await SupabaseService.seedMyProgressivePlan();
      await SupabaseService.reseedTodayForCurrentUser();

      var t = await SupabaseService.getTodayWorkout();
      final rows = await SupabaseService.getWorkoutTimeRows(days: 7);
      final fb = await SupabaseService.getTodayExerciseTimeFeedback();

      if (t.assignments.isEmpty) {
        await SupabaseService.ensureDefaultWorkoutAssignments();
        await SupabaseService.seedMyWorkoutAssignments();
        await SupabaseService.seedMyProgressivePlan();
        await SupabaseService.reseedTodayForCurrentUser();
        t = await SupabaseService.getTodayWorkout();
        if (t.assignments.isEmpty) {
          final lastDay = await SupabaseService.getLastProgramDayForCurrentUser();
          if (lastDay != null) t = await SupabaseService.getTodayWorkout(dayIndex: lastDay);
        }
      }

      if (!mounted) return;
      setState(() {
        _todays = t;
        _tracking = WorkoutTimeTracking(daily: rows, byWorkout: fb);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openDetails(WorkoutAssignment assignment) async {
    final t = _todays;
    if (t == null) return;
    WorkoutSession? session = t.session;
    if (session == null) {
      try {
        await SupabaseService.startWorkoutSession(dayIndex: t.dayIndex);
        await _load();
        if (!mounted) return;
        session = _todays?.session;
        if (session == null) return;
      } catch (_) { return; }
    }
    WorkoutSessionItem? existingItem;
    for (final it in session.items) {
      if (it.workoutId == assignment.workout.id) { existingItem = it; break; }
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkoutDetailsScreen(assignment: assignment, sessionItemId: existingItem?.id, sessionId: session!.id)));
    _load();
  }

  void _handleBack() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      TabHistory.maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.paper,
        body: SafeArea(
          top: false,
          child: RefreshIndicator(
            onRefresh: _load,
            color: AppColors.svcHero,
            child: _loading
                ? const Center(child: LoadingMark())
                : _error != null ? _buildError() : _buildContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final t = _todays!;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        _buildHero(),
        const SliverToBoxAdapter(child: SizedBox(height: 22)),
        SliverToBoxAdapter(child: _buildSectionTitle('আমার কার্যকলাপ', 'স্বাস্থ্য সূচক')),
        SliverToBoxAdapter(child: _buildMyActivity()),
        SliverToBoxAdapter(child: _buildWaterRedirectCard()),
        const SliverToBoxAdapter(child: SizedBox(height: 22)),
        SliverToBoxAdapter(child: _buildSectionTitle('আজকের রুটিন', 'পরিকল্পিত')),
        _buildScheduleSection(),
        const SliverToBoxAdapter(child: SizedBox(height: 140)),
      ],
    );
  }

  Widget _buildHero() {
    const url = 'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/app/photo-1564352969906-8b7f46ba4b8b.avif?token=eyJraWQiOiJhZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJhcHAvcGhvdG8tMTU2NDM1Mjk2OTkwNi04YjdmNDZiYTRiOGIuYXZpZiIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODc4Njg2MjksImV4cCI6MTgxOTQwNDYyOX0.Jdl-6cqT6wHh_nv8j-7oD3zjU2KcoR4e5ohJVnZgTNs';
    final t = _todays!;
    final total = t.assignments.length;
    final done = t.completedCount;
    final pct = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);

    return SliverToBoxAdapter(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.svcHero,
          image: const DecorationImage(image: NetworkImage(url), fit: BoxFit.cover, opacity: 0.8),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: Container(color: Colors.black.withValues(alpha: 0.3))),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 20, 0),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                          onPressed: _handleBack,
                        ),
                        const Expanded(
                          child: Text(
                            'ব্যায়াম পরিকল্পনা',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                          ),
                        ),
                        _buildBellIcon(),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'দিন ${t.dayIndex} / ৩০',
                              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -0.6),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'আজকের $totalটি ব্যায়াম সম্পন্ন করুন',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                      _buildCircularProgress(pct),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircularProgress(double pct) {
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(width: 72, height: 72, child: CircularProgressIndicator(value: pct, strokeWidth: 8, color: AppColors.svcHeroAccent, backgroundColor: Colors.white12)),
        Text('${(pct * 100).round()}%', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
      ],
    );
  }

  Widget _buildBellIcon() {
    return Container(
      width: 44, height: 44,
      decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.zero, border: Border.all(color: Colors.white24)),
      child: const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 22),
    );
  }

  Widget _buildMyActivity() {
    final today = _tracking.today;
    final totalPlanned = today.plannedCount;
    final totalCompleted = today.completedCount;
    final progress = totalPlanned == 0 ? 0.0 : (totalCompleted / totalPlanned).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line, width: 1.2)),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('আজকের অগ্রগতি', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.smoke, letterSpacing: 0.5)),
                      const SizedBox(height: 6),
                      Text('$totalCompleted / $totalPlanned সম্পন্ন', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.ink, letterSpacing: -0.5)),
                      const SizedBox(height: 12),
                      MonoBar(value: progress, height: 8, fill: AppColors.svcHero),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                _buildStatCircle(progress),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildSimpleStatTile('ব্যায়াম সময়', '${today.actualMinutes} মি', Icons.timer_outlined, const Color(0xFF0EA5E9))),
              const SizedBox(width: 12),
              Expanded(child: _buildSimpleStatTile('ক্যালরি', '${_todays?.completedCount ?? 0 * 25} kcal', Icons.local_fire_department_outlined, AppColors.rose)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCircle(double pct) {
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(width: 64, height: 64, child: CircularProgressIndicator(value: pct, strokeWidth: 10, color: AppColors.svcHero, backgroundColor: AppColors.surfaceHigh)),
        Text('${(pct * 100).round()}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.ink)),
      ],
    );
  }

  Widget _buildSimpleStatTile(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.ink)),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.smoke)),
        ],
      ),
    );
  }

  Widget _buildScheduleSection() {
    final t = _todays!;
    final ordered = [...t.assignments]..sort((a, b) => a.position.compareTo(b.position));
    return SliverList.builder(
      itemCount: ordered.length,
      itemBuilder: (context, i) => _buildScheduleRow(ordered[i], _findItem(ordered[i])),
    );
  }

  Widget _buildScheduleRow(WorkoutAssignment assignment, WorkoutSessionItem? item) {
    final w = assignment.workout;
    final completed = item?.isCompleted ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: InkWell(
        onTap: () => _openDetails(assignment),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.zero,
            border: Border.all(color: completed ? AppColors.svcHero : AppColors.line, width: completed ? 1.6 : 1.2),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 12, offset: const Offset(0, 6))],
          ),
          child: Row(
            children: [
              Container(
                width: 60, height: 60,
                decoration: BoxDecoration(color: AppColors.svcCategoryBg, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line, width: 0.8)),
                child: Icon(_categoryIcon(w.category), color: AppColors.svcHero, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(w.nameBn, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.ink)),
                    const SizedBox(height: 4),
                    Text('${w.durationMin} মিনিট · ${w.intensity.labelBn}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.smoke)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: completed ? AppColors.svcHero : AppColors.surfaceHigh, borderRadius: BorderRadius.zero, border: Border.all(color: completed ? AppColors.svcHero : AppColors.line)),
                child: Icon(completed ? Icons.check_rounded : Icons.play_arrow_rounded, color: completed ? Colors.white : AppColors.lineStrong, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, String sub) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.newsInk, letterSpacing: -0.3)),
          Text(sub, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.newsMuted.withValues(alpha: 0.8))),
        ],
      ),
    );
  }

  Widget _buildError() => Center(child: Text('ত্রুটি: $_error'));

  WorkoutSessionItem? _findItem(WorkoutAssignment a) {
    final session = _todays?.session;
    if (session == null) return null;
    for (final it in session.items) {
      if (it.workoutId == a.workout.id) return it;
    }
    return null;
  }

  IconData _categoryIcon(WorkoutCategory c) {
    switch (c) {
      case WorkoutCategory.cardio: return Icons.local_fire_department_rounded;
      case WorkoutCategory.strength: return Icons.fitness_center_rounded;
      case WorkoutCategory.flexibility: return Icons.self_improvement_rounded;
      case WorkoutCategory.balance: return Icons.balance_rounded;
      case WorkoutCategory.breathing: return Icons.air_rounded;
      case WorkoutCategory.yoga: return Icons.spa_rounded;
      case WorkoutCategory.household: return Icons.home_work_rounded;
      case WorkoutCategory.walking: return Icons.directions_walk_rounded;
    }
  }

  Widget _buildWaterRedirectCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WaterScreen())),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: AppColors.svcHero, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.svcHeroAccent, width: 1.2)),
          child: const Row(
            children: [
              Icon(Icons.water_drop_rounded, color: Colors.white, size: 28),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('পর্যাপ্ত পানি পান করেছেন?', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                    Text('ব্যায়ামের পর হাইড্রেটেড থাকা জরুরি', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
