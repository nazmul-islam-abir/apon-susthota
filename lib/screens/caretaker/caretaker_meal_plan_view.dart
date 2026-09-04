/// Caretaker read-only meal plan viewer.
///
/// Mirrors the patient's `MealPlanScreen`: shows the ±15-day strip, the
/// slot filter, AI-suggested + custom meals, and kcal target.
///
/// Nexora Redesign style: full-bleed hero image with dark overlay.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/caretaker_patient_summary.dart';
import '../../models/meal_item.dart';
import '../../models/user_meal_plan.dart';
import '../../services/caretaker_data_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/caretaker_viewer_header.dart';
import '../../widgets/mono_widgets.dart';
import '../../widgets/patient_data_realtime_mixin.dart';
import '../meal_details_screen.dart';
import 'caretaker_meal_plan_editor.dart';

class CaretakerMealPlanView extends StatefulWidget {
  final CaretakerPatientSummary patient;
  const CaretakerMealPlanView({super.key, required this.patient});

  @override
  State<CaretakerMealPlanView> createState() => _CaretakerMealPlanViewState();
}

class _CaretakerMealPlanViewState extends State<CaretakerMealPlanView>
    with PatientDataRealtimeMixin {
  late Future<_DayData> _future;
  late DateTime _today;
  late DateTime _selectedDate;
  static const int _windowSize = 15;
  static const int _todayIndex = 15;
  String? _slotFilter; // null = all
  bool _loading = false;
  final ScrollController _stripController = ScrollController();

  PlanProgress? _progress;

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
    _today = _midnight(DateTime.now());
    _selectedDate = _today;
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

  bool get _isToday => _selectedDate.isAtSameMomentAs(_today);

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

  Future<_DayData> _load() async {
    final uid = widget.patient.patientUserId;

    if (_progress == null) {
      _progress = await CaretakerDataService.getPlanProgress(uid);
    }
    final targetDay = _dayForDate(_selectedDate, _progress!);

    final results = await Future.wait([
      CaretakerDataService.getDayPlan(patientUserId: uid, planDay: targetDay),
      CaretakerDataService.getDailyLog(
        patientUserId: uid,
        planDay: targetDay,
        date: _selectedDate,
      ),
      CaretakerDataService.getUserDayPlan(
        patientUserId: uid,
        date: _selectedDate,
      ),
    ]);

    final aiItems = results[0] as List<MealSlotPlan>;
    final log = results[1] as List<MealLogEntry>;
    final userRows = results[2] as List<UserMealPlan>;

    final aiFiltered = aiItems.where((it) {
      return !userRows.any((u) =>
          u.foodId == it.food.id &&
          (u.customFoodName ?? '').startsWith('__removed__'));
    }).toList();

    final customItems = userRows
        .where((u) => !(u.customFoodName ?? '').startsWith('__removed__'))
        .map((u) {
      MealItem food;
      if (u.food != null) {
        food = MealItem.fromJson(Map<String, dynamic>.from(u.food!));
      } else {
        food = MealItem(
          id: 'custom::${u.id}',
          nameBn: u.displayName,
          category: 'custom',
          carbG: 0, proteinG: 0, fatG: 0, fiberG: 0,
          sodiumMg: 0, potassiumMg: 0, phosphorusMg: 0, giCategory: 'low',
        );
      }
      return MealSlotPlan(
        slot: u.slot,
        role: 'custom',
        food: food,
        source: 'custom',
        customId: u.id,
        customTime: u.displayTime.isEmpty ? null : u.displayTime,
        customPortionLabel: u.portionLabel,
      );
    }).toList();

    return _DayData(
      plans: [...aiFiltered, ...customItems],
      log: log,
      progress: _progress ?? PlanProgress.fallback(),
      userRows: userRows,
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
    final next = _selectedDate.add(Duration(days: delta));
    final start = _today.subtract(const Duration(days: _windowSize));
    final index = next.difference(start).inDays;
    if (index >= 0 && index <= _windowSize * 2) {
      setState(() => _selectedDate = next);
      _refresh();
      _scrollStripToIndex(index);
    }
  }

  Future<void> _toggleMeal(MealSlotPlan plan, String? loggedStatus) async {
    if (loggedStatus == 'eaten') return;
    HapticFeedback.lightImpact();
    try {
      await SupabaseService.caretakerLogMealForPatient(
        patientUserId: widget.patient.patientUserId,
        mealSlot: plan.slot,
        foodId: plan.food.id,
        foodNameBn: plan.food.nameBn,
        status: 'eaten',
        impact: 'good',
        planDay: _progress != null ? _dayForDate(_selectedDate, _progress!) : null,
      );
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('লগ করা যায়নি: $e')),
        );
      }
    }
  }

  Future<void> _onMealLongPress(MealSlotPlan plan) async {
    HapticFeedback.mediumImpact();
    if (plan.source == 'custom') {
      final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => CaretakerMealPlanEditorScreen(
          patientUserId: widget.patient.patientUserId,
          patientName: widget.patient.fullName,
          effectiveDate: _selectedDate,
          existingId: plan.customId,
          existingSlot: plan.slot,
          existingScheduledTime: plan.customTime,
          existingCustomName: plan.food.nameBn,
          existingPortionLabel: plan.customPortionLabel,
        ),
      ));
      if (ok == true) _refresh();
      return;
    }

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.svcCategoryBg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_off_rounded, color: AppColors.rose),
              title: const Text('আজকের জন্য সরাবেন?',
                  style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.rose)),
              subtitle: const Text('AI পরামর্শটি আজকের তালিকা থেকে সরিয়ে ফেলা হবে'),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
          ],
        ),
      ),
    );

    if (action == 'remove') {
      try {
        await SupabaseService.caretakerCreateMealPlanEntry(
          patientUserId: widget.patient.patientUserId,
          effectiveDate: _selectedDate,
          slot: plan.slot,
          foodId: plan.food.id,
          customFoodName: '__removed__::${plan.food.id}',
        );
        _refresh();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('সরানো যায়নি: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.svcCategoryBg,
      body: RefreshIndicator(
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
                CaretakerViewerHeader(
                  patient: widget.patient,
                  screenTitle: 'খাবারের পরিকল্পনা',
                ),
                _buildHeroStrip(data),
                const SliverToBoxAdapter(child: SizedBox(height: 22)),
                SliverToBoxAdapter(child: _buildSectionTitle('আজকের অগ্রগতি', 'খাবার সম্পন্ন')),
                SliverToBoxAdapter(child: _buildProgressCard(data)),
                const SliverToBoxAdapter(child: SizedBox(height: 22)),
                SliverToBoxAdapter(child: _buildSlotFilter()),
                _buildMealList(data),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            );
          },
        ),
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
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => CaretakerMealPlanEditorScreen(
        patientUserId: widget.patient.patientUserId,
        patientName: widget.patient.fullName,
        effectiveDate: _selectedDate,
      ),
    ));
    if (ok == true) _refresh();
  }

  Widget _buildHeroStrip(_DayData data) {
    return SliverToBoxAdapter(
      child: Container(
        color: AppColors.svcHero,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'দিন ${_dayForDate(_selectedDate, data.progress)} / ${data.progress.totalDays}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'আপনার রোগীর জন্য পরিকল্পিত সুষম খাবার',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildWeekStrip(data),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekStrip(_DayData data) {
    final start = _today.subtract(const Duration(days: _windowSize));
    final days = List.generate(_windowSize * 2 + 1, (i) => start.add(Duration(days: i)));

    return Row(
      children: [
        _navArrow(
            icon: Icons.chevron_left_rounded,
            enabled: _selectedDate.isAfter(start),
            onTap: () => _goToDay(-1)),
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
                final isSel = _midnight(d).isAtSameMomentAs(_selectedDate);
                final isToday = _midnight(d).isAtSameMomentAs(_today);
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedDate = _midnight(d));
                    _refresh();
                    _scrollStripToIndex(i);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 50,
                    decoration: BoxDecoration(
                      color: isSel ? Colors.white : Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.zero,
                      border: Border.all(color: isSel ? Colors.white : Colors.white24, width: 1.2),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat('E', 'bn').format(d).substring(0, 1),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: isSel ? AppColors.svcHero : Colors.white70,
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
            enabled: _selectedDate.isBefore(start.add(const Duration(days: _windowSize * 2))),
            onTap: () => _goToDay(1)),
      ],
    );
  }

  Widget _navArrow({required IconData icon, required bool enabled, required VoidCallback onTap}) {
    return IconButton(onPressed: enabled ? onTap : null, icon: Icon(icon, color: enabled ? Colors.white : Colors.white24, size: 20));
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

  Widget _buildProgressCard(_DayData data) {
    final total = data.plans.length;
    int eaten = 0;
    for (final p in data.plans) {
      if (data.log.any((l) => l.mealSlot == p.slot && l.foodNameBn == p.food.nameBn && l.status == 'eaten')) {
        eaten++;
      }
    }
    final pct = total == 0 ? 0.0 : (eaten / total).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: AppColors.line, width: 1.2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('আজকের অগ্রগতি', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.smoke, letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  Text('$eaten / $total খাবার সম্পন্ন', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.ink, letterSpacing: -0.5)),
                  const SizedBox(height: 12),
                  MonoBar(value: pct, height: 8, fill: AppColors.svcHero),
                ],
              ),
            ),
            const SizedBox(width: 24),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(width: 64, height: 64, child: CircularProgressIndicator(value: pct, strokeWidth: 10, color: AppColors.svcHero, backgroundColor: AppColors.surfaceHigh)),
                Text('${(pct * 100).round()}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.ink)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlotFilter() {
    Widget chip(String label, String? key) {
      final active = _slotFilter == key;
      return GestureDetector(
        onTap: () => setState(() => _slotFilter = key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.svcHero : Colors.white,
            borderRadius: BorderRadius.zero,
            border: Border.all(color: active ? AppColors.svcHero : AppColors.line, width: 1.2),
          ),
          child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: active ? Colors.white : AppColors.ink)),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: [
          chip('সব', null),
          for (final s in _slots) chip(_slotBn[s] ?? s, s),
        ],
      ),
    );
  }

  Widget _buildMealList(_DayData data) {
    final filtered = _slotFilter == null
        ? data.plans
        : data.plans.where((p) => p.slot == _slotFilter).toList();

    if (filtered.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          child: Center(
            child: Column(
              children: [
                const Icon(Icons.no_meals_rounded, color: AppColors.lineStrong, size: 48),
                const SizedBox(height: 12),
                const Text(
                  'এই দিনের জন্য কোনো খাবার নেই',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.smoke),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final bySlot = <String, List<MealSlotPlan>>{};
    for (final p in filtered) {
      bySlot.putIfAbsent(p.slot, () => []).add(p);
    }

    final children = <Widget>[];
    for (final slot in _slots) {
      final entries = bySlot[slot];
      if (entries == null || entries.isEmpty) continue;
      children.add(_buildSlotSection(slot, entries, data.log, data.userRows));
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      sliver: SliverList(delegate: SliverChildListDelegate(children)),
    );
  }

  Widget _buildSlotSection(String slot, List<MealSlotPlan> entries, List<MealLogEntry> log, List<UserMealPlan> userRows) {
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
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.newsInk),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.svcHero.withValues(alpha: 0.1), borderRadius: BorderRadius.zero),
                  child: Text('${entries.length}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.svcHero)),
                ),
              ],
            ),
          ),
          for (final p in entries) _buildMealRow(p, log, userRows),
        ],
      ),
    );
  }

  Widget _buildMealRow(MealSlotPlan plan, List<MealLogEntry> log, List<UserMealPlan> userRows) {
    final logged = log.where((l) => l.mealSlot == plan.slot && l.foodNameBn == plan.food.nameBn).toList();
    final status = logged.isNotEmpty ? logged.first.status : null;
    final portion = plan.customPortionLabel ?? plan.food.portionLabel;
    final time = plan.customTime;

    final userRow = plan.source == 'custom' ? userRows.where((u) => u.id == plan.customId).firstOrNull : null;
    final displayKcal = userRow != null ? userRow.kcal : plan.food.kcal;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          final userRow = plan.source == 'custom' ? userRows.where((u) => u.id == plan.customId).firstOrNull : null;
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => MealDetailsScreen(
              foodId: plan.food.id.startsWith('custom::') ? '' : plan.food.id,
              fallbackNameBn: plan.food.nameBn,
              seed: plan.food,
              notes: userRow?.notes,
            ),
          ));
        },
        onLongPress: () => _onMealLongPress(plan),
        child: MonoCard(
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: _statusColor(status).withValues(alpha: 0.12), borderRadius: BorderRadius.zero),
                child: Icon(_iconForStatus(status), color: _statusColor(status), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.food.nameBn.isEmpty ? 'কাস্টম খাবার' : plan.food.nameBn,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (displayKcal > 0) '${displayKcal.round()} kcal',
                        if (time != null && time.isNotEmpty) time,
                        if (portion != null && portion.isNotEmpty) portion,
                        if (status != null) _statusLabelBn(status),
                      ].whereType<String>().where((s) => s.isNotEmpty).join(' • '),
                      style: const TextStyle(fontSize: 11.5, color: AppColors.smoke, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              if (status == null)
                IconButton(
                  onPressed: () => _toggleMeal(plan, status),
                  icon: Icon(_iconForStatus(status), color: _statusColor(status).withValues(alpha: 0.5), size: 20),
                ),
              if (status != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(color: _statusColor(status).withValues(alpha: 0.12), borderRadius: BorderRadius.zero),
                  child: Text(_statusLabelBn(status)!, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: _statusColor(status))),
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForSlot(String slot) {
    switch (slot) {
      case 'breakfast': return Icons.wb_sunny_rounded;
      case 'lunch': return Icons.lunch_dining_rounded;
      case 'dinner': return Icons.dinner_dining_rounded;
      case 'morning_snack':
      case 'evening_snack':
      case 'tiffin': return Icons.cookie_rounded;
      default: return Icons.restaurant_rounded;
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
    if (s == 'eaten') return 'খাওয়া হয়েছে';
    if (s == 'swap') return 'বিকল্প';
    if (s == 'off_plan') return 'পরিকল্পনার বাইরে';
    return null;
  }
}

class _DayData {
  final List<MealSlotPlan> plans;
  final List<MealLogEntry> log;
  final PlanProgress progress;
  final List<UserMealPlan> userRows;
  _DayData({required this.plans, required this.log, required this.progress, required this.userRows});
  factory _DayData.empty() => _DayData(
        plans: const [],
        log: const [],
        progress: PlanProgress.fallback(),
        userRows: const [],
      );
}
