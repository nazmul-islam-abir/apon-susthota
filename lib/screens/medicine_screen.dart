/// Medicine screen — "MedTracker" redesign.
///
/// Layout (top → bottom):
///   1. Brand bar (gradient mark + title + avatar)
///   2. Page title + subtitle
///   3. Horizontal day-date strip (5 days, today highlighted)
///   4. Daily progress card ("Xটির মধ্যে Yটি সুইজড" + bar)
///   5. Vertical timeline of doses (each with rail, indicator, card)
///   6. Floating + FAB
///   7. (No inline bottom nav — uses the shared AppShellScaffold drawer
///      and the global AnimatedNotchBottomBar from home_shell.)
///
/// Colors come from the existing `AppColors` palette so the screen
/// inherits the app's emerald identity without inventing new tokens.
library;

import 'package:flutter/material.dart';

import '../models/medicine.dart';
import '../services/app_events.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';
import 'medicine_editor.dart';

// Sentinel used by [_doseCopyWith] to distinguish "argument not passed"
// from "argument explicitly passed as null". Declared at top-level so it
// is visible to both the State class and the inline helper.
const Object _kSentinel = Object();

class MedicineScreen extends StatefulWidget {
  const MedicineScreen({super.key});

  @override
  State<MedicineScreen> createState() => _MedicineScreenState();
}

class _MedicineScreenState extends State<MedicineScreen> {
  // ── Palette (uses AppColors so it stays consistent with rest of app) ──
  static const _emerald = AppColors.cyanDeep;
  static const _emeraldSoft = AppColors.cyan;
  static const _emeraldLight = AppColors.mint;
  static const _cardSurface = Colors.white;
  static const _canvas = Color(0xFFF6F7F8);
  static const _textPrimary = Color(0xFF111827);
  static const _textSecondary = Color(0xFF6B7280);
  static const _amber = Color(0xFFD97706);
  static const _amberSoft = Color(0xFFFBBF24);

  // ── State ─────────────────────────────────────────────────────────────
  late DateTime _today;
  late DateTime _selectedDay;
  final Map<DateTime, List<MedicineDose>> _dosesByDay = {};
  List<Medicine> _medicines = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _today = _midnight(DateTime.now());
    _selectedDay = _today;
    _load();
    AppEvents.medicineChanged.addListener(_onChanged);
  }

  @override
  void dispose() {
    AppEvents.medicineChanged.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) _load();
  }

  DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final byDay = <DateTime, List<MedicineDose>>{};
      for (var i = 6; i >= 0; i--) {
        final d = _today.subtract(Duration(days: i));
        final list = await SupabaseService.getMedicineDosesForDate(d);
        // Only show doses whose medicine is still active.
        final activeIds = _medicines.isEmpty
            ? null
            : _medicines.where((m) => m.isActive).map((m) => m.id).toSet();
        final filtered = activeIds == null
            ? list
            : list.where((d) => activeIds.contains(d.medicineId)).toList();
        filtered.sort((a, b) => _timeToMinutes(a.scheduledTime)
            .compareTo(_timeToMinutes(b.scheduledTime)));
        byDay[_midnight(d)] = filtered;
      }
      // Also refresh active medicine list (used to know which medicines
      // belong to the user; first call uses an empty filter, the loop
      // above becomes unfiltered after this assignment).
      final meds = await SupabaseService.listMedicines();
      _medicines = meds;
      if (byDay[_today] != null) {
        final activeIds =
            meds.where((m) => m.isActive).map((m) => m.id).toSet();
        byDay[_today] = byDay[_today]!
            .where((d) => activeIds.contains(d.medicineId))
            .toList();
      }
      if (mounted) {
        setState(() {
          _dosesByDay
            ..clear()
            ..addAll(byDay);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'লোড করা যায়নি: $e';
          _loading = false;
        });
      }
    }
  }

  int _timeToMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return 0;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return h * 60 + m;
  }

  TimeOfDay _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    final h = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return TimeOfDay(hour: h, minute: m);
  }

  String _formatTimeBn(String hhmm) {
    final t = _parseTime(hhmm);
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final p = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $p';
  }

  String _doseLine(MedicineDose d) {
    final amt = d.doseAmount == d.doseAmount.roundToDouble()
        ? d.doseAmount.toInt().toString()
        : d.doseAmount.toString();
    final unit = d.doseUnit.isEmpty || d.doseUnit == 'unit'
        ? medicineFormBn(d.form)
        : d.doseUnit;
    return '$amt $unit';
  }

  // ── Top-level actions ────────────────────────────────────────────────
  Future<void> _openEditor({Medicine? existing}) async {
    final result = await MedicineEditorSheet.show(context, existing: existing);
    if (result == null || !mounted) return;
    final ok = await applyMedicineEdit(result: result, existing: existing);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('সংরক্ষণ করা যায়নি — আবার চেষ্টা করুন।')),
      );
      return;
    }
    AppEvents.notifyMedicineChanged();
  }

  Future<void> _toggleDose(MedicineDose dose, bool taken,
      {required DateTime day}) async {
    final dayKey = _midnight(day);
    setState(() {
      final list = _dosesByDay[dayKey];
      if (list == null) return;
      final i = list.indexWhere((d) =>
          d.medicineId == dose.medicineId &&
          d.scheduledTime == dose.scheduledTime);
      if (i >= 0) {
        list[i] = _doseCopyWith(
          list[i],
          status: taken ? 'taken' : null,
          takenAt: taken ? DateTime.now() : null,
        );
      }
    });
    try {
      await SupabaseService.markDose(
        medicineId: dose.medicineId,
        date: day,
        scheduledTime: dose.scheduledTime,
        status: taken ? 'taken' : 'skipped',
      );
      AppEvents.notifyMedicineChanged();
      if (mounted) await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('সংরক্ষণ ব্যর্থ: $e')),
      );
      if (mounted) await _load();
    }
  }

  MedicineDose _doseCopyWith(
    MedicineDose d, {
    Object? status = _kSentinel,
    DateTime? takenAt,
  }) {
    return MedicineDose(
      doseId: d.doseId,
      medicineId: d.medicineId,
      nameBn: d.nameBn,
      nameEn: d.nameEn,
      form: d.form,
      strength: d.strength,
      doseAmount: d.doseAmount,
      doseUnit: d.doseUnit,
      mealRelation: d.mealRelation,
      color: d.color,
      medicineNotes: d.medicineNotes,
      scheduledTime: d.scheduledTime,
      bucket: d.bucket,
      status: identical(status, _kSentinel) ? d.status : status as String?,
      takenAt: takenAt ?? d.takenAt,
      note: d.note,
      isOverdue: d.isOverdue,
    );
  }

  // ── Build ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final doses =
        _dosesByDay[_midnight(_selectedDay)] ?? const <MedicineDose>[];
    return Scaffold(
      backgroundColor: _canvas,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: _emerald,
          backgroundColor: Colors.white,
          onRefresh: _load,
          child: _loading
              ? const Center(child: LoadingMark(size: 36))
              : _error != null
                  ? _buildError()
                  : _buildBody(doses),
        ),
      ),
      floatingActionButton: _buildFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildBody(List<MedicineDose> doses) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        SliverToBoxAdapter(child: _buildBrandBar()),
        SliverToBoxAdapter(child: _buildTitle()),
        SliverToBoxAdapter(child: _buildDayStrip()),
        SliverToBoxAdapter(child: _buildProgressCard(doses)),
        if (doses.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _buildEmpty(),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 120),
            sliver: SliverList.separated(
              itemCount: doses.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final isCurrent = _isCurrentDose(doses, i);
                return _DoseTimelineRow(
                  dose: doses[i],
                  state: _doseState(doses[i], isCurrent: isCurrent),
                  onLog: isCurrent
                      ? () => _toggleDose(doses[i], true, day: _selectedDay)
                      : null,
                  onToggle: (taken) =>
                      _toggleDose(doses[i], taken, day: _selectedDay),
                  isFirst: i == 0,
                  isLast: i == doses.length - 1,
                  timeLabel: _formatTimeBn(doses[i].scheduledTime),
                  doseLine: _doseLine(doses[i]),
                );
              },
            ),
          ),
      ],
    );
  }

// ── Brand bar ─────────────────────────────────────────────────────────
  Widget _buildBrandBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.cyan, AppColors.mint],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.medical_services_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          const Text(
            'MedTracker',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.cyanDeep,
              letterSpacing: -0.2,
            ),
          ),
          const Spacer(),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _emeraldLight.withValues(alpha: 0.35),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.person_rounded,
                color: AppColors.cyanDeep, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _buildTitle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'আজকের সময়সূচী',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppColors.cyanDeep,
              letterSpacing: -0.4,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'আপনার স্বাস্থ্য রক্ষণাবেক্ষণ সাথে ট্র্যাকে থাকুন।',
            style: TextStyle(
              fontSize: 14.5,
              color: _textSecondary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  // ── Day strip ─────────────────────────────────────────────────────────
  Widget _buildDayStrip() {
    final days =
        List<DateTime>.generate(5, (i) => _today.add(Duration(days: i - 2)));
    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        itemCount: days.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => _buildDayPill(days[i]),
      ),
    );
  }

  Widget _buildDayPill(DateTime d) {
    final selected = _midnight(d) == _midnight(_selectedDay);
    final isToday = _midnight(d) == _midnight(_today);
    final bg = selected ? _emerald : Colors.white;
    final fg = selected ? Colors.white : _textPrimary;
    final sub = selected ? Colors.white70 : _textSecondary;
    return GestureDetector(
      onTap: () => setState(() => _selectedDay = _midnight(d)),
      child: AnimatedContainer(
        duration: AppMotion.short,
        curve: AppMotion.standard,
        width: 56,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? _emerald : Colors.black12,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: _emerald.withValues(alpha: 0.25),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _weekdayShortBn(d.weekday),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: sub,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${d.day}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: fg,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: isToday ? _emerald : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Progress card ─────────────────────────────────────────────────────
  Widget _buildProgressCard(List<MedicineDose> doses) {
    final total = doses.length;
    final done = doses.where((d) => d.isTaken).length;
    final pct = total == 0 ? 0.0 : done / total;
    final allDone = total > 0 && done == total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _cardSurface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'দৈনিক অগ্রগতি',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.cyanDeep,
                    letterSpacing: 0.2,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color:
                        (allDone ? _emerald : _amber).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${(pct * 100).round()}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: allDone ? _emerald : _amber,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                  letterSpacing: -0.6,
                  height: 1.05,
                ),
                children: [
                  TextSpan(text: '$done '),
                  TextSpan(
                    text: 'টির মধ্যে $total',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _textSecondary,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              allDone ? 'সব ওষুধ সময়মতো নেওয়া হয়েছে!' : 'টি সুইজড',
              style: const TextStyle(fontSize: 13.5, color: _textSecondary),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Stack(
                children: [
                  Container(
                    height: 10,
                    color: _emeraldLight.withValues(alpha: 0.35),
                  ),
                  FractionallySizedBox(
                    widthFactor: pct.clamp(0.0, 1.0),
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: allDone
                              ? const [_emeraldSoft, _emerald]
                              : const [_amberSoft, _amber],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Dose state ────────────────────────────────────────────────────────
  bool _isCurrentDose(List<MedicineDose> doses, int i) {
    if (!_midnight(_selectedDay).isAtSameMomentAs(_midnight(_today))) {
      return false;
    }
    final now = DateTime.now();
    for (var j = 0; j < doses.length; j++) {
      final d = doses[j];
      if (d.isTaken) continue;
      final t = _parseTime(d.scheduledTime);
      final dt = DateTime(now.year, now.month, now.day, t.hour, t.minute);
      final diff = dt.difference(now).inMinutes;
      final overdue = diff < 0 && diff.abs() <= 240;
      final dueSoon = diff >= 0 && diff <= 90;
      if (overdue || dueSoon) {
        return j == i;
      }
    }
    return false;
  }

  _DoseState _doseState(MedicineDose d, {required bool isCurrent}) {
    if (d.isTaken) return _DoseState.done;
    if (isCurrent) return _DoseState.current;
    return _DoseState.future;
  }

  // ── FAB ───────────────────────────────────────────────────────────────
  Widget _buildFab() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, right: 4),
      child: GestureDetector(
        onTap: () => _openEditor(),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: _emerald,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _emerald.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _emeraldLight.withValues(alpha: 0.45),
                  _emeraldSoft.withValues(alpha: 0.20),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.medication_rounded,
                size: 64, color: AppColors.cyanDeep),
          ),
          const SizedBox(height: 22),
          const Text(
            'কোনো ওষুধ যোগ করা হয়নি',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.cyanDeep,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'নিচের + বোতাম চেপে আপনার প্রথম ওষুধ যোগ করুন এবং সময়মতো নেওয়ার অভ্যাস গড়ে তুলুন।',
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 13.5, color: _textSecondary, height: 1.4),
          ),
          const SizedBox(height: 24),
          MonoButton(
            label: 'ওষুধ যোগ করুন',
            leading: Icons.add_rounded,
            onPressed: () => _openEditor(),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 56, color: Color(0xFFB91C1C)),
            const SizedBox(height: 12),
            Text(
              _error ?? 'কিছু ভুল হয়েছে',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 18),
            MonoButton(
              label: 'আবার চেষ্টা করুন',
              leading: Icons.refresh_rounded,
              onPressed: _load,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Dose state enum ───────────────────────────────────────────────────
enum _DoseState { done, current, future }

// ── Dose timeline row ─────────────────────────────────────────────────
class _DoseTimelineRow extends StatelessWidget {
  final MedicineDose dose;
  final _DoseState state;
  final VoidCallback? onLog;
  final ValueChanged<bool> onToggle;
  final bool isFirst;
  final bool isLast;
  final String timeLabel;
  final String doseLine;

  const _DoseTimelineRow({
    required this.dose,
    required this.state,
    required this.onLog,
    required this.onToggle,
    required this.isFirst,
    required this.isLast,
    required this.timeLabel,
    required this.doseLine,
  });

  @override
  Widget build(BuildContext context) {
    const emerald = AppColors.cyanDeep;
    const emeraldLight = AppColors.mint;
    const textPrimary = Color(0xFF111827);
    const textSecondary = Color(0xFF6B7280);

    final isCurrent = state == _DoseState.current;
    final isDone = state == _DoseState.done;
    final cardColor = isCurrent ? emerald : const Color(0xFF111827);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Left rail ──────────────────────────────────────────────
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Expanded(
                  flex: 1,
                  child: Container(
                    width: 2,
                    color: isFirst
                        ? Colors.transparent
                        : emeraldLight.withValues(alpha: 0.6),
                  ),
                ),
                _indicator(isDone, isCurrent),
                Expanded(
                  flex: 1,
                  child: Container(
                    width: 2,
                    color: isLast
                        ? Colors.transparent
                        : emeraldLight.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          // ── Card ──────────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Material(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
                elevation: 0,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: isCurrent ? onLog : () => onToggle(!isDone),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              timeLabel,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isCurrent ? Colors.white : textSecondary,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if ((dose.strength ?? '').isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isCurrent
                                      ? Colors.white.withValues(alpha: 0.18)
                                      : emeraldLight.withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  dose.strength!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isCurrent
                                        ? Colors.white
                                        : AppColors.cyanDeep,
                                  ),
                                ),
                              ),
                            const Spacer(),
                            if (isCurrent)
                              Container(
                                height: 36,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                alignment: Alignment.center,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.check_circle_rounded,
                                        color: AppColors.cyanDeep, size: 18),
                                    SizedBox(width: 6),
                                    Text(
                                      'লগ',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.cyanDeep,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else if (isDone)
                              const Icon(Icons.check_circle_rounded,
                                  color: AppColors.cyan, size: 22)
                            else
                              const Icon(
                                Icons.radio_button_unchecked_rounded,
                                color: Color(0xFF6B7280),
                                size: 22,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          dose.nameBn.isNotEmpty
                              ? dose.nameBn
                              : (dose.nameEn ?? ''),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isCurrent ? Colors.white : textPrimary,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$doseLine · ${mealRelationBn(dose.mealRelation)}',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: isCurrent
                                ? Colors.white.withValues(alpha: 0.85)
                                : textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _indicator(bool isDone, bool isCurrent) {
    const emerald = AppColors.cyanDeep;
    Color fill;
    Color border;
    Widget child;
    if (isDone) {
      fill = emerald;
      border = emerald;
      child = const Icon(Icons.check_rounded, size: 16, color: Colors.white);
    } else if (isCurrent) {
      fill = emerald;
      border = emerald;
      child = Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      );
    } else {
      fill = Colors.white;
      border = const Color(0xFFCBD5E1);
      child = const Icon(Icons.schedule_rounded,
          size: 14, color: Color(0xFF94A3B8));
    }
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: border, width: 2),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

// ── Weekday short helper ──────────────────────────────────────────────
String _weekdayShortBn(int weekday) {
  const names = ['সোম', 'মঙ্গল', 'বুধ', 'বৃহ', 'শুক্র', 'শনি', 'রবি'];
  return names[(weekday - 1).clamp(0, 6)];
}
