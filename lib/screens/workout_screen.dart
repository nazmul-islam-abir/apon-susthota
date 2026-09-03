// আমার ডায়েট — Workout screen (v5 Redesign).
library;

import 'package:amar_diet/screens/water_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../l10n/app_localizations.dart';
import '../models/thirty_day_report.dart';
import '../models/workout.dart';
import '../services/app_events.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';
import '../widgets/tab_history_mixin.dart';
import 'workout_details_screen.dart';

class WorkoutScreen extends StatefulWidget {
  final bool isReadOnly;
  const WorkoutScreen({super.key, this.isReadOnly = false});

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  late DateTime _today;
  late DateTime _selectedDay;
  final ScrollController _stripController = ScrollController();
  
  static const int _windowSize = 15;
  static const int _todayIndex = 15;

  TodaysWorkout? _todays;
  // Map from date to a specific snapshot for that day
  final Map<DateTime, TodaysWorkout> _workoutsByDay = {};
  WorkoutTimeTracking _tracking = WorkoutTimeTracking.empty;
  ThirtyDayReport? _trendReport;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _today = _midnight(DateTime.now());
    _selectedDay = _today;
    _load();
    AppEvents.workoutChanged.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollStripToIndex(_todayIndex, immediate: true));
  }

  @override
  void dispose() {
    AppEvents.workoutChanged.removeListener(_onChanged);
    _stripController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) _load();
  }

  DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

  void _scrollStripToIndex(int index, {bool immediate = false}) {
    if (!_stripController.hasClients) return;
    const cellWidth = 50.0;
    const spacing = 8.0;
    const stride = cellWidth + spacing;
    final screenWidth = MediaQuery.of(context).size.width;
    final offset = (index * stride) - (screenWidth / 2) + (cellWidth / 2) + 24.0;
    
    if (immediate) {
      _stripController.jumpTo(offset.clamp(
        _stripController.position.minScrollExtent,
        _stripController.position.maxScrollExtent,
      ));
    } else {
      _stripController.animateTo(
        offset.clamp(
          _stripController.position.minScrollExtent,
          _stripController.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      // 1. Ensure workout assignments exist (Self-healing re-seed).
      // This fixes the "no workout visible" issue for new users or missing plans.
      await SupabaseService.reseedTodayForCurrentUser();

      // 2. Fetch today's workout to find the correct anchor dayIndex (1..30)
      // from the server's calendar-aware logic.
      final actualToday = await SupabaseService.getTodayWorkout();
      final anchorDayIndex = actualToday.dayIndex;

      final start = _today.subtract(const Duration(days: _windowSize));
      final dates = List.generate(_windowSize * 2 + 1, (i) => start.add(Duration(days: i)));
      
      final workoutsByDay = <DateTime, TodaysWorkout>{};
      
      // We already have today's workout result.
      workoutsByDay[_midnight(_today)] = actualToday;

      await Future.wait(dates.map((d) async {
        final mid = _midnight(d);
        if (mid == _midnight(_today)) return;

        final rel = d.difference(_today).inDays;
        // Map to 1..30 cycle relative to the anchor day index.
        int targetIdx = anchorDayIndex + rel;
        while (targetIdx < 1) targetIdx += 30;
        while (targetIdx > 30) targetIdx -= 30;

        final t = await SupabaseService.getTodayWorkout(dayIndex: targetIdx);
        workoutsByDay[mid] = t;
      }));

      // Keep existing tracking and trend for the "selected" day or overall
      final rows = await SupabaseService.getWorkoutTimeRows(days: 7);
      final fb = await SupabaseService.getTodayExerciseTimeFeedback();
      final trend = await SupabaseService.getThirtyDayReport();

      if (mounted) {
        setState(() {
          _workoutsByDay..clear()..addAll(workoutsByDay);
          _todays = _workoutsByDay[_midnight(_selectedDay)];
          _tracking = WorkoutTimeTracking(daily: rows, byWorkout: fb);
          _trendReport = trend;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openDetails(WorkoutAssignment assignment) async {
    if (widget.isReadOnly) return;
    final t = _workoutsByDay[_midnight(_selectedDay)];
    if (t == null) return;
    WorkoutSession? session = t.session;
    if (session == null) {
      try {
        await SupabaseService.startWorkoutSession(dayIndex: t.dayIndex);
        await _load();
        if (!mounted) return;
        session = _workoutsByDay[_midnight(_selectedDay)]?.session;
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
    final l = AppLocalizations.of(context)!;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        _buildHero(),
        const SliverToBoxAdapter(child: SizedBox(height: 22)),
        SliverToBoxAdapter(
          child: _buildSectionTitle(l.workoutProgressTitle, l.workoutProgressPctLabel),
        ),
        SliverToBoxAdapter(child: _buildMyActivity()),
        // Chart removed as requested.
        SliverToBoxAdapter(child: _buildWaterRedirectCard()),
        const SliverToBoxAdapter(child: SizedBox(height: 22)),
        SliverToBoxAdapter(
          child: _buildSectionTitle(l.workoutHeroSectionTitle, l.workoutAggregateOfLabel),
        ),
        _buildScheduleSection(),
        const SliverToBoxAdapter(child: SizedBox(height: 140)),
      ],
    );
  }

  Widget _buildHero() {
    const url = 'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/app/photo-1564352969906-8b7f46ba4b8b.avif?token=eyJraWQiOiJhZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJhcHAvcGhvdG8tMTU2NDM1Mjk2OTkwNi04YjdmNDZiYTRiOGIuYXZpZiIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODc4Njg2MjksImV4cCI6MTgxOTQwNDYyOX0.Jdl-6cqT6wHh_nv8j-7oD3zjU2KcoR4e5ohJVnZgTNs';
    final dateLabel = DateFormat('EEEE, d MMMM yyyy', 'bn').format(_selectedDay);

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
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dateLabel, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -0.6)),
                      const SizedBox(height: 6),
                      Text('আজকের ${_workoutsByDay[_midnight(_selectedDay)]?.assignments.length ?? 0}টি ব্যায়াম সম্পন্ন করুন', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _buildWeekStrip(),
                const SizedBox(height: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekStrip() {
    final start = _today.subtract(const Duration(days: _windowSize));
    final days = List.generate(_windowSize * 2 + 1, (i) => start.add(Duration(days: i)));
    
    return Row(
      children: [
        _navArrow(icon: Icons.chevron_left, enabled: _selectedDay.isAfter(start), onTap: () {
          final next = _selectedDay.subtract(const Duration(days: 1));
          final index = next.difference(start).inDays;
          if (index >= 0) {
            setState(() => _selectedDay = next);
            _scrollStripToIndex(index);
          }
        }),
        Expanded(
          child: SizedBox(
            height: 70,
            child: ListView.separated(
              controller: _stripController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              physics: const BouncingScrollPhysics(),
              itemCount: days.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final d = days[i];
                final isSel = _midnight(d) == _midnight(_selectedDay);
                final isToday = _midnight(d) == _midnight(_today);
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedDay = _midnight(d));
                    _scrollStripToIndex(i);
                  },
                  child: AnimatedContainer(
                    duration: AppMotion.short,
                    width: 50,
                    decoration: BoxDecoration(
                      color: isSel ? Colors.white : Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.zero,
                      border: Border.all(color: isSel ? Colors.white : Colors.white24, width: 1.2),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(DateFormat('E', 'bn').format(d).substring(0, 1), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: isSel ? AppColors.svcHero : Colors.white70)),
                        Text('${d.day}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: isSel ? AppColors.svcHero : Colors.white)),
                        if (isToday) Container(margin: const EdgeInsets.only(top: 2), width: 4, height: 4, decoration: const BoxDecoration(color: AppColors.svcHeroAccent, shape: BoxShape.circle)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        _navArrow(icon: Icons.chevron_right, enabled: _selectedDay.isBefore(start.add(Duration(days: _windowSize * 2))), onTap: () {
          final next = _selectedDay.add(const Duration(days: 1));
          final index = next.difference(start).inDays;
          if (index <= _windowSize * 2) {
            setState(() => _selectedDay = next);
            _scrollStripToIndex(index);
          }
        }),
      ],
    );
  }

  Widget _navArrow({required IconData icon, required bool enabled, required VoidCallback onTap}) {
    return IconButton(onPressed: enabled ? onTap : null, icon: Icon(icon, color: enabled ? Colors.white : Colors.white24, size: 20));
  }

  Widget _buildBellIcon() {
    return Container(
      width: 44, height: 44,
      decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.zero, border: Border.all(color: Colors.white24)),
      child: const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 22),
    );
  }

  Widget _buildError() {
    return Center(
      child: Text('ত্রুটি: $_error', style: const TextStyle(color: AppColors.smoke)),
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

  WorkoutSessionItem? _findItem(WorkoutAssignment a) {
    final session = _workoutsByDay[_midnight(_selectedDay)]?.session;
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

  Widget _buildMyActivity() {
    final l = AppLocalizations.of(context)!;
    final breakdown = _computeBreakdown();
    final pct = breakdown.overallPct;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        children: [
          // Aggregate breakdown card.
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.zero,
              border: Border.all(color: AppColors.line, width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.workoutProgressTitle,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: AppColors.smoke,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            l.workoutProgressOfTotal(
                              breakdown.totalActualMinutes,
                              breakdown.totalTargetMinutes,
                              (pct * 100).round(),
                            ),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppColors.ink,
                              letterSpacing: -0.5,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 68,
                      height: 68,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 68,
                            height: 68,
                            child: CircularProgressIndicator(
                              value: pct,
                              strokeWidth: 9,
                              color: AppColors.svcHero,
                              backgroundColor: AppColors.surfaceHigh,
                            ),
                          ),
                          Text(
                            '${(pct * 100).round()}%',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Stacked progress strip showing the three completion states.
                _buildBreakdownBar(breakdown),
                const SizedBox(height: 14),
                // Three label rows.
                Row(
                  children: [
                    Expanded(
                      child: _buildBreakdownTile(
                        Icons.check_circle_rounded,
                        AppColors.svcHero,
                        l.workoutAggregateDoneLabel,
                        breakdown.fullyDoneCount,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildBreakdownTile(
                        Icons.timelapse_rounded,
                        const Color(0xFFF59E0B),
                        l.workoutAggregatePartialLabel,
                        breakdown.partialCount,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildBreakdownTile(
                        Icons.radio_button_unchecked_rounded,
                        AppColors.lineStrong,
                        l.workoutAggregatePendingLabel,
                        breakdown.notStartedCount,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildSimpleStatTile(
                  'ব্যায়াম সময়',
                  '${breakdown.totalActualMinutes} মি',
                  Icons.timer_outlined,
                  const Color(0xFF0EA5E9),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSimpleStatTile(
                  'ক্যালরি',
                  '${breakdown.totalActualMinutes * 5} kcal',
                  Icons.local_fire_department_outlined,
                  AppColors.rose,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Stacked horizontal bar showing fully-done / partial / not-started as
  /// proportional widths. Pure render — math lives in [_computeBreakdown].
  Widget _buildBreakdownBar(_WorkoutBreakdown b) {
    final total = b.totalAssigned;
    if (total == 0) {
      return Container(
        height: 8,
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.zero,
        ),
      );
    }
    return Row(
      children: [
        if (b.fullyDoneCount > 0)
          Expanded(
            flex: (b.fullyDoneCount * 1000).round(),
            child: Container(height: 8, color: AppColors.svcHero),
          ),
        if (b.partialCount > 0)
          Expanded(
            flex: (b.partialCount * 1000).round(),
            child: Container(height: 8, color: const Color(0xFFF59E0B)),
          ),
        if (b.notStartedCount > 0)
          Expanded(
            flex: (b.notStartedCount * 1000).round(),
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.zero,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBreakdownTile(IconData icon, Color color, String label, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.svcCategoryBg,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.line, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
              letterSpacing: -0.4,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.smoke,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
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
    final t = _workoutsByDay[_midnight(_selectedDay)];
    if (t == null) return const SliverToBoxAdapter(child: SizedBox());
    final ordered = [...t.assignments]..sort((a, b) => a.position.compareTo(b.position));
    return SliverList.builder(
      itemCount: ordered.length,
      itemBuilder: (context, i) => _buildScheduleRow(ordered[i], _findItem(ordered[i])),
    );
  }

  /// Per-workout row: shows status icon + per-workout progress + hint.
  Widget _buildScheduleRow(WorkoutAssignment assignment, WorkoutSessionItem? item) {
    final l = AppLocalizations.of(context)!;
    final w = assignment.workout;
    final feedback = _tracking.byWorkout[w.id] ?? WorkoutExerciseTimeFeedback.empty;
    final status = _statusFor(feedback, fallback: item?.isCompleted ?? false);
    final pct = feedback.pct.clamp(0.0, 1.0);
    final accent = _statusAccent(status);
    final hasFeedback = feedback.targetMinutes > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: InkWell(
        onTap: widget.isReadOnly ? null : () => _openDetails(assignment),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.zero,
            border: Border.all(
              color: status == _WorkoutStatus.done ? AppColors.svcHero : AppColors.line,
              width: status == _WorkoutStatus.done ? 1.6 : 1.2,
            ),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 12, offset: const Offset(0, 6))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.svcCategoryBg,
                      borderRadius: BorderRadius.zero,
                      border: Border.all(color: AppColors.line, width: 0.8),
                    ),
                    child: Icon(_categoryIcon(w.category), color: accent, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          w.nameBn,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: AppColors.ink,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${feedback.targetMinutes > 0 ? feedback.targetMinutes : w.durationMin} মিনিট · ${w.intensity.labelBn}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.smoke,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _buildStatusIcon(status),
                ],
              ),
              if (hasFeedback) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.zero,
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 6,
                          backgroundColor: AppColors.surfaceHigh,
                          color: accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${(pct * 100).round()}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${feedback.actualMinutes} / ${feedback.targetMinutes} মি · ${_statusLabel(l, status)}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.smoke,
                        ),
                      ),
                    ),
                    if (status == _WorkoutStatus.partial)
                      Text(
                        l.workoutProgressHintPartial(
                          (feedback.targetMinutes - feedback.actualMinutes).clamp(0, 99999),
                        ),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFF59E0B),
                        ),
                      )
                    else if (status == _WorkoutStatus.done)
                      Text(
                        l.workoutProgressHintDone,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: AppColors.svcHero,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Small circular status indicator on the right edge of each row.
  Widget _buildStatusIcon(_WorkoutStatus status) {
    final color = _statusAccent(status);
    final IconData icon;
    switch (status) {
      case _WorkoutStatus.done:
        icon = Icons.check_rounded;
        break;
      case _WorkoutStatus.partial:
        icon = Icons.timelapse_rounded;
        break;
      case _WorkoutStatus.pending:
        icon = Icons.play_arrow_rounded;
        break;
    }
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: status == _WorkoutStatus.pending ? AppColors.surfaceHigh : color,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: status == _WorkoutStatus.pending ? AppColors.line : color),
      ),
      child: Icon(icon, color: status == _WorkoutStatus.pending ? AppColors.svcHero : Colors.white, size: 20),
    );
  }

  /// Pure: derive the day's completion breakdown from the loaded data.
  /// Counts assignments into 3 buckets and computes an overall % weighted
  /// by planned minutes (so partials contribute their fraction).
  _WorkoutBreakdown _computeBreakdown() {
    final t = _workoutsByDay[_midnight(_selectedDay)];
    if (t == null) {
      return const _WorkoutBreakdown(
        totalAssigned: 0,
        fullyDoneCount: 0,
        partialCount: 0,
        notStartedCount: 0,
        totalActualMinutes: 0,
        totalTargetMinutes: 0,
        overallPct: 0,
      );
    }
    int fully = 0;
    int partial = 0;
    int pending = 0;
    int totalTarget = 0;
    int totalActual = 0;
    for (final a in t.assignments) {
      final fb = _tracking.byWorkout[a.workout.id];
      final targetMin = (fb?.targetMinutes ?? 0) > 0
          ? fb!.targetMinutes
          : a.workout.durationMin;
      final actualMin = fb?.actualMinutes ?? 0;
      totalTarget += (targetMin as num).toInt();
      totalActual += (actualMin as num).toInt();
      final status = _statusFor(fb ?? WorkoutExerciseTimeFeedback.empty, fallback: false);
      switch (status) {
        case _WorkoutStatus.done:
          fully++;
          break;
        case _WorkoutStatus.partial:
          partial++;
          break;
        case _WorkoutStatus.pending:
          pending++;
          break;
      }
    }
    final pct = totalTarget == 0 ? 0.0 : (totalActual / totalTarget).clamp(0.0, 1.0);
    return _WorkoutBreakdown(
      totalAssigned: t.assignments.length,
      fullyDoneCount: fully,
      partialCount: partial,
      notStartedCount: pending,
      totalActualMinutes: totalActual,
      totalTargetMinutes: totalTarget,
      overallPct: pct,
    );
  }

  _WorkoutStatus _statusFor(WorkoutExerciseTimeFeedback fb, {required bool fallback}) {
    if (fb.targetMinutes <= 0) {
      // No time-tracking data — fall back to the binary isCompleted flag.
      return fallback ? _WorkoutStatus.done : _WorkoutStatus.pending;
    }
    if (fb.pct >= 1.0) return _WorkoutStatus.done;
    if (fb.pct > 0) return _WorkoutStatus.partial;
    return _WorkoutStatus.pending;
  }

  Color _statusAccent(_WorkoutStatus status) {
    switch (status) {
      case _WorkoutStatus.done:
        return AppColors.svcHero;
      case _WorkoutStatus.partial:
        return const Color(0xFFF59E0B);
      case _WorkoutStatus.pending:
        return AppColors.lineStrong;
    }
  }

  String _statusLabel(AppLocalizations l, _WorkoutStatus status) {
    switch (status) {
      case _WorkoutStatus.done:
        return l.workoutStatusDone;
      case _WorkoutStatus.partial:
        return l.workoutStatusPartial;
      case _WorkoutStatus.pending:
        return l.workoutStatusPending;
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

class _WorkoutTrendAnalysis extends StatelessWidget {
  final ThirtyDayReport report;
  const _WorkoutTrendAnalysis({required this.report});

  @override
  Widget build(BuildContext context) {
    const double target = 30; // 30 minutes daily target
    final data = report.days.where((d) => !d.isFuture).map((d) => _ChartData(d.dayOfCycle, d.workouts.minutes.toDouble())).toList();
    
    // Dynamic Scaling:
    double maxVal = data.isEmpty ? 0 : data.map((e) => e.value).fold(0, (p, c) => (p > c) ? p : c);
    double chartMax = (maxVal > target * 1.5) ? maxVal * 1.1 : target * 1.5;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Removed chart as requested.
        ],
      ),
    );
  }
}

class _ChartData {
  final int day;
  final double value;
  _ChartData(this.day, this.value);
}

/// Three-state completion classifier for one workout.
///
/// `done`     — target minutes reached or exceeded.
/// `partial`  — some progress recorded, target not met.
/// `pending`  — no progress recorded.
enum _WorkoutStatus { done, partial, pending }

/// Aggregated completion snapshot for a single day. Computed by
/// [_WorkoutScreenState._computeBreakdown] from the loaded
/// `TodaysWorkout` + `WorkoutTimeTracking` payload — *not* stored on the
/// backend. Refreshed whenever the screen reloads.
class _WorkoutBreakdown {
  final int totalAssigned;
  final int fullyDoneCount;
  final int partialCount;
  final int notStartedCount;
  final int totalActualMinutes;
  final int totalTargetMinutes;
  final double overallPct;

  const _WorkoutBreakdown({
    required this.totalAssigned,
    required this.fullyDoneCount,
    required this.partialCount,
    required this.notStartedCount,
    required this.totalActualMinutes,
    required this.totalTargetMinutes,
    required this.overallPct,
  });
}
