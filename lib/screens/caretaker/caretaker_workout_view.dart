/// Caretaker read-only workout viewer — full mirror of the patient's
/// `WorkoutScreen` so a caretaker can see exactly what the patient
/// sees for the day (planned workouts, completion status, progress
/// bars, time-tracking).
///
/// Nexora Redesign style: full-bleed hero image with dark overlay.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/caretaker_patient_summary.dart';
import '../../models/user_meal_plan.dart';
import '../../models/workout.dart';
import '../../services/caretaker_data_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/caretaker_viewer_header.dart';
import '../../widgets/mono_widgets.dart';
import '../../widgets/patient_data_realtime_mixin.dart';
import 'caretaker_water_view.dart';

class CaretakerWorkoutView extends StatefulWidget {
  final CaretakerPatientSummary patient;
  const CaretakerWorkoutView({super.key, required this.patient});

  @override
  State<CaretakerWorkoutView> createState() => _CaretakerWorkoutViewState();
}

class _CaretakerWorkoutViewState extends State<CaretakerWorkoutView>
    with PatientDataRealtimeMixin {
  late DateTime _today;
  late DateTime _selectedDay;
  final ScrollController _stripController = ScrollController();
  static const int _windowSize = 15;
  static const int _todayIndex = 15;

  late Future<_WorkoutData> _future;
  bool _loading = false;
  PlanProgress? _progress;

  @override
  void initState() {
    super.initState();
    _today = _midnight(DateTime.now());
    _selectedDay = _today;
    _future = _load();
    attachPatientDataRealtime(widget.patient.patientUserId, _refresh);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollStripToIndex(_todayIndex, immediate: true),
    );
  }

  @override
  void dispose() {
    disposePatientDataRealtime();
    _stripController.dispose();
    super.dispose();
  }

  DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

  bool get _isToday => _midnight(_selectedDay).isAtSameMomentAs(_today);

  void _scrollStripToIndex(int index, {bool immediate = false}) {
    if (!_stripController.hasClients) return;
    const cellWidth = 50.0;
    const spacing = 8.0;
    const stride = cellWidth + spacing;
    final screenWidth = MediaQuery.of(context).size.width;
    final offset =
        (index * stride) - (screenWidth / 2) + (cellWidth / 2) + 24.0;
    final clamped = offset.clamp(
      _stripController.position.minScrollExtent,
      _stripController.position.maxScrollExtent,
    );
    if (immediate) {
      _stripController.jumpTo(clamped);
    } else {
      _stripController.animateTo(
        clamped,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  int _dayForDate(DateTime date, PlanProgress progress) {
    final start = progress.planStartDate;
    if (start != null) {
      final daysFromStart = _midnight(date).difference(_midnight(start)).inDays;
      if (daysFromStart >= 0) {
        final mod = daysFromStart % progress.totalDays;
        return (mod + 1).clamp(1, progress.totalDays);
      }
    }
    return progress.day.clamp(1, progress.totalDays);
  }

  Future<_WorkoutData> _load() async {
    final uid = widget.patient.patientUserId;

    if (_progress == null) {
      _progress = await CaretakerDataService.getPlanProgress(uid);
    }
    final dayIndex = _dayForDate(_selectedDay, _progress!);

    final results = await Future.wait([
      CaretakerDataService.getTodayWorkout(
        patientUserId: uid,
        dayIndex: dayIndex,
      ),
      CaretakerDataService.getWorkoutTimeRows(patientUserId: uid, days: _windowSize),
      CaretakerDataService.getTodayExerciseTimeFeedback(uid),
      CaretakerDataService.getDailyMetricsForDate(
        patientUserId: uid,
        date: _selectedDay,
      ),
    ]);
    final data = _WorkoutData(
      today: results[0] as TodaysWorkout,
      timeRows: results[1] as List<WorkoutTimeRow>,
      feedback: results[2] as Map<String, WorkoutExerciseTimeFeedback>,
      metric: results[3] as DailyMetric,
    );
    return data;
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _future = _load();
    });
    try {
      await _future;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSelectDay(DateTime day) {
    setState(() => _selectedDay = _midnight(day));
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.svcCategoryBg,
      body: RefreshIndicator(
        color: AppColors.svcHero,
        onRefresh: _refresh,
        child: FutureBuilder<_WorkoutData>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done && !snap.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.svcHero),
              );
            }
            final viewData = snap.data ?? _WorkoutData.empty();
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                CaretakerViewerHeader(
                  patient: widget.patient,
                  screenTitle: 'ব্যায়াম তালিকা',
                ),
                _buildHeroStrip(viewData),
                const SliverToBoxAdapter(child: SizedBox(height: 22)),
                SliverToBoxAdapter(
                  child: _buildSectionTitle(
                    'ব্যায়ামের অগ্রগতি',
                    'আজকের পরিসংখ্যান',
                  ),
                ),
                SliverToBoxAdapter(child: _buildBreakdownCard(viewData)),
                const SliverToBoxAdapter(child: SizedBox(height: 14)),
                SliverToBoxAdapter(child: _buildStatPair(viewData)),
                const SliverToBoxAdapter(child: SizedBox(height: 22)),
                SliverToBoxAdapter(
                  child: _buildSectionTitle(
                    'আজকের ব্যায়ামসমূহ',
                    'নির্ধারিত তালিকা ও অবস্থা',
                  ),
                ),
                _buildScheduleSection(viewData),
                const SliverToBoxAdapter(child: SizedBox(height: 22)),
                SliverToBoxAdapter(child: _buildWaterRedirectCard()),
                const SliverToBoxAdapter(child: SizedBox(height: 22)),
                SliverToBoxAdapter(
                  child: _buildSectionTitle(
                    'সাম্প্রতিক ব্যায়াম',
                    'গত ৭ দিনের রেকর্ড',
                  ),
                ),
                SliverToBoxAdapter(child: _buildLogStrip(viewData)),
                const SliverToBoxAdapter(child: SizedBox(height: 22)),
                SliverToBoxAdapter(child: _buildTipCard()),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeroStrip(_WorkoutData data) {
    final total = data.today.assignments.length;
    final done = data.today.completedCount;
    final pct = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);

    return SliverToBoxAdapter(
      child: Container(
        color: AppColors.svcHero,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isToday
                        ? 'আজকের $totalটি ব্যায়াম'
                        : 'নির্বাচিত দিনের $totalটি ব্যায়াম',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: CircularProgressIndicator(
                        value: pct,
                        strokeWidth: 6,
                        color: AppColors.svcHeroAccent,
                        backgroundColor: Colors.white12,
                      ),
                    ),
                    Text(
                      '${(pct * 100).round()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildWeekStrip(),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekStrip() {
    final start = _today.subtract(const Duration(days: _windowSize));
    final days = List.generate(
      _windowSize * 2 + 1,
      (i) => start.add(Duration(days: i)),
    );
    return Row(
      children: [
        _navArrow(
          icon: Icons.chevron_left_rounded,
          enabled: _selectedDay.isAfter(start),
          onTap: () {
            final next = _selectedDay.subtract(const Duration(days: 1));
            final index = next.difference(start).inDays;
            if (index >= 0) {
              _onSelectDay(next);
              _scrollStripToIndex(index);
            }
          },
        ),
        Expanded(
          child: SizedBox(
            height: 60,
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
                    _onSelectDay(d);
                    _scrollStripToIndex(i);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 50,
                    decoration: BoxDecoration(
                      color: isSel
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.zero,
                      border: Border.all(
                        color: isSel ? Colors.white : Colors.white24,
                        width: 1.2,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat('E', 'bn').format(d).substring(0, 1),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color:
                                isSel ? AppColors.svcHero : Colors.white70,
                          ),
                        ),
                        Text(
                          '${d.day}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: isSel ? AppColors.svcHero : Colors.white,
                          ),
                        ),
                        if (isToday)
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              color: AppColors.svcHeroAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        _navArrow(
          icon: Icons.chevron_right_rounded,
          enabled: _selectedDay.isBefore(
            start.add(const Duration(days: _windowSize * 2)),
          ),
          onTap: () {
            final next = _selectedDay.add(const Duration(days: 1));
            final index = next.difference(start).inDays;
            if (index <= _windowSize * 2) {
              _onSelectDay(next);
              _scrollStripToIndex(index);
            }
          },
        ),
      ],
    );
  }

  Widget _navArrow({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return IconButton(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, color: enabled ? Colors.white : Colors.white24, size: 20),
    );
  }

  Widget _buildSectionTitle(String title, String sub) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AppColors.newsInk,
              letterSpacing: -0.3,
            ),
          ),
          Text(
            sub,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.newsMuted.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownCard(_WorkoutData data) {
    final breakdown = _computeBreakdown(data);
    final pct = breakdown.overallPct;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Container(
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
                      const Text(
                        'ব্যায়ামের অগ্রগতি',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: AppColors.smoke,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${breakdown.totalActualMinutes} / ${breakdown.totalTargetMinutes} মিনিট',
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
            _buildBreakdownBar(breakdown),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _buildBreakdownTile(
                    Icons.check_circle_rounded,
                    AppColors.svcHero,
                    'সম্পন্ন',
                    breakdown.fullyDoneCount,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildBreakdownTile(
                    Icons.timelapse_rounded,
                    const Color(0xFFF59E0B),
                    'আংশিক',
                    breakdown.partialCount,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildBreakdownTile(
                    Icons.radio_button_unchecked_rounded,
                    AppColors.lineStrong,
                    'বাকি',
                    breakdown.notStartedCount,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreakdownBar(_Breakdown b) {
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

  Widget _buildStatPair(_WorkoutData data) {
    final breakdown = _computeBreakdown(data);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
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
    );
  }

  Widget _buildSimpleStatTile(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.smoke,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleSection(_WorkoutData data) {
    if (data.today.assignments.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.zero,
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.fitness_center_rounded,
                  color: AppColors.smoke,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isToday
                        ? 'আজ কোনো ব্যায়াম নির্ধারিত নেই'
                        : 'এই দিনে কোনো ব্যায়াম নির্ধারিত ছিল না',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.smoke,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final ordered = [...data.today.assignments]
      ..sort((a, b) => a.position.compareTo(b.position));
    return SliverList.builder(
      itemCount: ordered.length,
      itemBuilder: (_, i) => _buildScheduleRow(ordered[i], data),
    );
  }

  Widget _buildScheduleRow(WorkoutAssignment a, _WorkoutData data) {
    final w = a.workout;
    final fb = data.feedback[w.id] ?? WorkoutExerciseTimeFeedback.empty;
    final status = _statusFor(fb, fallback: a.isCompletedInSession(data.today.session));
    final pct = fb.pct.clamp(0.0, 1.0);
    final accent = _statusAccent(status);
    final hasFeedback = fb.targetMinutes > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.zero,
          border: Border.all(
            color: status == _WorkoutStatus.done
                ? AppColors.svcHero
                : AppColors.line,
            width: status == _WorkoutStatus.done ? 1.6 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
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
                        '${fb.targetMinutes > 0 ? fb.targetMinutes : w.durationMin} মিনিট · ${w.intensity.labelBn}',
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
                      '${fb.actualMinutes} / ${fb.targetMinutes} মি · ${_statusLabelBn(status)}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.smoke,
                      ),
                    ),
                  ),
                  if (status == _WorkoutStatus.partial)
                    Text(
                      'আরও ${(fb.targetMinutes - fb.actualMinutes).clamp(0, 99999)} মি বাকি',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFF59E0B),
                      ),
                    )
                  else if (status == _WorkoutStatus.done)
                    const Text(
                      'লক্ষ্য পূরণ',
                      style: TextStyle(
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
    );
  }

  Widget _buildStatusIcon(_WorkoutStatus status) {
    final color = _statusAccent(status);
    IconData icon;
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
        border: Border.all(
          color: status == _WorkoutStatus.pending ? AppColors.line : color,
        ),
      ),
      child: Icon(
        icon,
        color: status == _WorkoutStatus.pending ? AppColors.svcHero : Colors.white,
        size: 20,
      ),
    );
  }

  IconData _categoryIcon(WorkoutCategory c) {
    switch (c) {
      case WorkoutCategory.cardio:
        return Icons.local_fire_department_rounded;
      case WorkoutCategory.strength:
        return Icons.fitness_center_rounded;
      case WorkoutCategory.flexibility:
        return Icons.self_improvement_rounded;
      case WorkoutCategory.balance:
        return Icons.balance_rounded;
      case WorkoutCategory.breathing:
        return Icons.air_rounded;
      case WorkoutCategory.yoga:
        return Icons.spa_rounded;
      case WorkoutCategory.household:
        return Icons.home_work_rounded;
      case WorkoutCategory.walking:
        return Icons.directions_walk_rounded;
    }
  }

  Widget _buildWaterRedirectCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CaretakerWaterView(patient: widget.patient),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.svcHero,
            borderRadius: BorderRadius.zero,
            border: Border.all(color: AppColors.svcHeroAccent, width: 1.2),
          ),
          child: Row(
            children: const [
              Icon(Icons.water_drop_rounded, color: Colors.white, size: 28),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'পর্যাপ্ত পানি পান করেছেন?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'ব্যায়ামের পর হাইড্রেটেড থাকা জরুরি',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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

  Widget _buildLogStrip(_WorkoutData data) {
    final rows = data.timeRows;
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.zero,
            border: Border.all(color: AppColors.line),
          ),
          child: const Text(
            'গত ৭ দিনে কোনো ব্যায়ামের রেকর্ড নেই',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.smoke,
            ),
          ),
        ),
      );
    }
    final reversed = rows.reversed.toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: reversed.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final r = reversed[i];
                  final pct = r.targetMinutes == 0
                      ? 0.0
                      : (r.actualMinutes / r.targetMinutes).clamp(0.0, 1.0);
                  final dowBn = DateFormat('EEE', 'bn').format(r.day);
                  final isSelected = _midnight(r.day) == _midnight(_selectedDay);
                  return GestureDetector(
                    onTap: () => _onSelectDay(r.day),
                    child: Container(
                      width: 60,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.svcHero.withValues(alpha: 0.15)
                            : (pct >= 0.99
                                ? AppColors.mint.withValues(alpha: 0.1)
                                : Colors.white),
                        borderRadius: BorderRadius.zero,
                        border: Border.all(
                          color: isSelected
                              ? AppColors.svcHero
                              : (pct >= 0.99
                                  ? AppColors.mint.withValues(alpha: 0.5)
                                  : AppColors.line),
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            dowBn,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: isSelected
                                  ? AppColors.svcHero
                                  : AppColors.smoke,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${(pct * 100).round()}%',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: isSelected
                                  ? AppColors.svcHero
                                  : (pct >= 0.99 ? AppColors.mintDeep : AppColors.ink),
                              letterSpacing: -0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            for (final r in reversed.take(5)) _logRow(r),
          ],
        ),
      ),
    );
  }

  Widget _logRow(WorkoutTimeRow r) {
    final pct = r.targetMinutes == 0
        ? 0.0
        : (r.actualMinutes / r.targetMinutes).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 86,
            child: Text(
              DateFormat('d MMM', 'bn').format(r.day),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.smoke,
              ),
            ),
          ),
          Expanded(
            child: MonoBar(
              value: pct,
              height: 6,
              fill: pct >= 0.99 ? AppColors.mint : AppColors.cyan,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 80,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${r.completedCount}/${r.plannedCount} • ${r.actualMinutes}মি',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTipCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.svcCategoryBg,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Icon(Icons.tips_and_updates_rounded,
                color: AppColors.svcHero, size: 24),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                'হালকা ব্যায়াম প্রতিদিন ৩০ মিনিট রক্তে শর্করা নিয়ন্ত্রণে সাহায্য করে। ওষুধ ও খাবারের সাথে নিয়মিত ব্যায়াম সবচেয়ে ভালো ফল দেয়।',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  _Breakdown _computeBreakdown(_WorkoutData data) {
    final total = data.today.assignments.length;
    int fully = 0, partial = 0, pending = 0;
    int totalTarget = 0, totalActual = 0;
    for (final a in data.today.assignments) {
      final fb = data.feedback[a.workout.id];
      final targetMin = (fb?.targetMinutes ?? 0) > 0
          ? fb!.targetMinutes
          : a.workout.durationMin;
      final actualMin = fb?.actualMinutes ?? 0;
      totalTarget += targetMin!;
      totalActual += actualMin;
      final st = _statusFor(
        fb ?? WorkoutExerciseTimeFeedback.empty,
        fallback: a.isCompletedInSession(data.today.session),
      );
      switch (st) {
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
    final pct =
        totalTarget == 0 ? 0.0 : (totalActual / totalTarget).clamp(0.0, 1.0);
    return _Breakdown(
      totalAssigned: total,
      fullyDoneCount: fully,
      partialCount: partial,
      notStartedCount: pending,
      totalActualMinutes: totalActual,
      totalTargetMinutes: totalTarget,
      overallPct: pct,
    );
  }

  _WorkoutStatus _statusFor(
    WorkoutExerciseTimeFeedback fb, {
    required bool fallback,
  }) {
    if (fb.targetMinutes <= 0) {
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

  String _statusLabelBn(_WorkoutStatus status) {
    switch (status) {
      case _WorkoutStatus.done:
        return 'সম্পন্ন';
      case _WorkoutStatus.partial:
        return 'আংশিক সম্পন্ন';
      case _WorkoutStatus.pending:
        return 'এখনো শুরু হয়নি';
    }
  }
}

enum _WorkoutStatus { done, partial, pending }

class _Breakdown {
  final int totalAssigned;
  final int fullyDoneCount;
  final int partialCount;
  final int notStartedCount;
  final int totalActualMinutes;
  final int totalTargetMinutes;
  final double overallPct;
  const _Breakdown({
    required this.totalAssigned,
    required this.fullyDoneCount,
    required this.partialCount,
    required this.notStartedCount,
    required this.totalActualMinutes,
    required this.totalTargetMinutes,
    required this.overallPct,
  });
}

class _WorkoutData {
  final TodaysWorkout today;
  final List<WorkoutTimeRow> timeRows;
  final Map<String, WorkoutExerciseTimeFeedback> feedback;
  final DailyMetric metric;
  _WorkoutData({
    required this.today,
    required this.timeRows,
    required this.feedback,
    required this.metric,
  });
  factory _WorkoutData.empty() => _WorkoutData(
        today: TodaysWorkout(
          dayIndex: 1,
          today: DateTime.now(),
          assignments: const [],
        ),
        timeRows: const [],
        feedback: const {},
        metric: DailyMetric.empty,
      );
}

extension on WorkoutAssignment {
  bool isCompletedInSession(WorkoutSession? session) {
    if (session == null) return false;
    for (final it in session.items) {
      if (it.workoutId == workout.id && it.isCompleted) return true;
    }
    return false;
  }
}
