/// Caretaker read-only meal plan viewer.
///
/// Mirrors the patient's `MealPlanScreen`: shows the ±15-day strip, the
/// slot filter, AI-suggested + custom meals, kcal target, and which
/// meals are already logged. No write controls.
library;

import 'package:flutter/material.dart';

import '../../models/caretaker_patient_summary.dart';
import '../../models/meal_item.dart';
import '../../models/user_meal_plan.dart';
import '../../services/caretaker_data_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/caretaker_viewer_header.dart';
import '../../widgets/mono_widgets.dart';
import 'caretaker_meal_plan_editor.dart';

class CaretakerMealPlanView extends StatefulWidget {
  final CaretakerPatientSummary patient;
  const CaretakerMealPlanView({super.key, required this.patient});

  @override
  State<CaretakerMealPlanView> createState() => _CaretakerMealPlanViewState();
}

class _CaretakerMealPlanViewState extends State<CaretakerMealPlanView> {
  late Future<_DayData> _future;
  int _selectedDay = 1;
  static const int _windowSize = 15;
  String? _slotFilter; // null = all
  bool _loading = false;

  // Hard-coded slot order, mirroring MealPlanScreen.
  static const List<String> _slots = [
    'breakfast',
    'morning_snack',
    'lunch',
    'evening_snack',
    'dinner',
    'tiffin',
    'late_night',
    'pre_workout',
    'post_workout',
  ];

  static const Map<String, String> _slotBn = {
    'breakfast': 'সকালের খাবার',
    'morning_snack': 'সকালের স্ন্যাক',
    'lunch': 'দুপুরের খাবার',
    'evening_snack': 'বিকেলের স্ন্যাক',
    'dinner': 'রাতের খাবার',
    'tiffin': 'তিফিন',
    'late_night': 'রাতের দেরি',
    'pre_workout': 'ব্যায়াম-পূর্ব',
    'post_workout': 'ব্যায়াম-পরবর্তী',
  };

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DayData> _load() async {
    final uid = widget.patient.patientUserId;
    final results = await Future.wait([
      CaretakerDataService.getDayPlan(patientUserId: uid, planDay: _selectedDay),
      CaretakerDataService.getDailyLog(patientUserId: uid, planDay: _selectedDay),
      CaretakerDataService.getPlanProgress(uid),
    ]);
    return _DayData(
      plans: results[0] as List<MealSlotPlan>,
      log: results[1] as List<MealLogEntry>,
      progress: results[2] as PlanProgress,
    );
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final f = _load();
      setState(() => _future = f);
      await f;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goToDay(int delta) {
    final next = (_selectedDay + delta).clamp(1, 30);
    if (next == _selectedDay) return;
    setState(() => _selectedDay = next);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.svcCategoryBg,
      body: Column(
        children: [
          CaretakerViewerHeader(
            patient: widget.patient,
            screenTitle: 'খাবারের পরিকল্পনা',
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.svcHero,
              onRefresh: _refresh,
              child: FutureBuilder<_DayData>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done && !snap.hasData) {
                    return const Center(child: CircularProgressIndicator(color: AppColors.svcHero));
                  }
                  final data = snap.data ?? _DayData.empty();
                  return CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    slivers: [
                      SliverToBoxAdapter(child: _buildStrip(data)),
                      SliverToBoxAdapter(child: _buildSlotFilter()),
                      SliverToBoxAdapter(child: _buildMealList(data)),
                      const SliverToBoxAdapter(child: SizedBox(height: 40)),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: MonoButton(
                label: 'নতুন খাবার যোগ করুন',
                leading: Icons.add_rounded,
                onPressed: () => _openMealEditor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMealEditor(BuildContext context) async {
    // Compute the calendar date for the selected plan day so the
    // entry lands on the user's "today + N" offset.
    final today = DateTime.now();
    final effectiveDate =
        DateTime(today.year, today.month, today.day + (_selectedDay - 1));
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => CaretakerMealPlanEditorScreen(
        patientUserId: widget.patient.patientUserId,
        patientName: widget.patient.fullName,
        effectiveDate: effectiveDate,
      ),
    ));
    if (ok == true) _refresh();
  }

  Widget _buildStrip(_DayData data) {
    final start = (_selectedDay - _windowSize).clamp(1, 30);
    final end = (_selectedDay + _windowSize).clamp(1, 30);
    final days = [for (var i = start; i <= end; i++) i];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'দিন ${_selectedDay} / ${data.progress.totalDays}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: AppColors.newsInk,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${data.progress.daysElapsed} দিন সম্পন্ন',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.smoke,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: _selectedDay > 1 ? () => _goToDay(-1) : null,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: _selectedDay < 30 ? () => _goToDay(1) : null,
                ),
              ],
            ),
          ),
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: days.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final d = days[i];
                final selected = d == _selectedDay;
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedDay = d);
                    _refresh();
                  },
                  child: Container(
                    width: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.svcHero : Colors.white,
                      borderRadius: BorderRadius.zero,
                      border: Border.all(
                        color: selected ? AppColors.svcHero : AppColors.line,
                        width: 1.2,
                      ),
                    ),
                    child: Text(
                      '$d',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: selected ? Colors.white : AppColors.ink,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlotFilter() {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          _slotChip(label: 'সব', value: null),
          for (final s in _slots) _slotChip(label: _slotBn[s] ?? s, value: s),
        ],
      ),
    );
  }

  Widget _slotChip({required String label, required String? value}) {
    final selected = _slotFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _slotFilter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.cyan : Colors.white,
            borderRadius: BorderRadius.zero,
            border: Border.all(
              color: selected ? AppColors.cyan : AppColors.line,
              width: 1.2,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMealList(_DayData data) {
    final filtered = _slotFilter == null
        ? data.plans
        : data.plans.where((p) => p.slot == _slotFilter).toList();

    if (filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Center(
          child: Column(
            children: [
              const Icon(Icons.no_meals_rounded, color: AppColors.lineStrong, size: 48),
              const SizedBox(height: 12),
              const Text(
                'এই দিনের জন্য কোনো খাবার নেই',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: AppColors.smoke,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Group by slot
    final bySlot = <String, List<MealSlotPlan>>{};
    for (final p in filtered) {
      bySlot.putIfAbsent(p.slot, () => []).add(p);
    }

    final widgets = <Widget>[];
    for (final slot in _slots) {
      final entries = bySlot[slot];
      if (entries == null || entries.isEmpty) continue;
      widgets.add(_buildSlotSection(slot, entries, data.log));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: widgets,
      ),
    );
  }

  Widget _buildSlotSection(String slot, List<MealSlotPlan> entries, List<MealLogEntry> log) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Row(
              children: [
                Icon(_iconForSlot(slot), color: AppColors.svcHero, size: 16),
                const SizedBox(width: 6),
                Text(
                  _slotBn[slot] ?? slot,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: AppColors.newsInk,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.svcHero.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.zero,
                  ),
                  child: Text(
                    '${entries.length}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: AppColors.svcHero,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final p in entries) _buildMealRow(p, log),
        ],
      ),
    );
  }

  Widget _buildMealRow(MealSlotPlan plan, List<MealLogEntry> log) {
    final logged = log.where((l) => l.foodNameBn == plan.food.nameBn).toList();
    final status = logged.isNotEmpty ? logged.first.status : null;
    final portion = plan.customPortionLabel ?? plan.food.portionLabel;
    final time = plan.customTime;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MonoCard(
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _statusColor(status).withValues(alpha: 0.12),
                borderRadius: BorderRadius.zero,
              ),
              child: Icon(_iconForStatus(status), color: _statusColor(status), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan.food.nameBn.isEmpty ? 'কাস্টম খাবার' : plan.food.nameBn,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (time != null && time.isNotEmpty) time,
                      if (portion != null && portion.isNotEmpty) portion,
                      _statusLabelBn(status),
                    ].whereType<String>().where((s) => s.isNotEmpty).join(' • '),
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.smoke,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (status != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor(status).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.zero,
                ),
                child: Text(
                  _statusLabelBn(status)!,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: _statusColor(status),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconForSlot(String slot) {
    switch (slot) {
      case 'breakfast':
        return Icons.wb_sunny_rounded;
      case 'lunch':
        return Icons.lunch_dining_rounded;
      case 'dinner':
        return Icons.dinner_dining_rounded;
      case 'morning_snack':
      case 'evening_snack':
      case 'tiffin':
        return Icons.cookie_rounded;
      default:
        return Icons.restaurant_rounded;
    }
  }

  IconData _iconForStatus(String? s) {
    if (s == 'eaten') return Icons.check_circle_rounded;
    if (s == 'swap') return Icons.swap_horiz_rounded;
    if (s == 'off_plan') return Icons.warning_amber_rounded;
    return Icons.restaurant_rounded;
  }

  Color _statusColor(String? s) {
    if (s == 'eaten') return AppColors.mint;
    if (s == 'swap') return AppColors.amber;
    if (s == 'off_plan') return AppColors.rose;
    return AppColors.cyan;
  }

  String? _statusLabelBn(String? s) {
    if (s == 'eaten') return 'খাওয়া হয়েছে';
    if (s == 'swap') return 'বিকল্প';
    if (s == 'off_plan') return 'পরিকল্পনার বাইরে';
    return null;
  }
}

class _DayData {
  final List<MealSlotPlan> plans;
  final List<MealLogEntry> log;
  final PlanProgress progress;
  _DayData({required this.plans, required this.log, required this.progress});
  factory _DayData.empty() => _DayData(
        plans: const [],
        log: const [],
        progress: PlanProgress.fallback(),
      );
}
