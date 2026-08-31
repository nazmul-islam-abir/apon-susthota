/// Medicine screen — professional high-fidelity redesign (v5).
/// Matches the "Nexora" aesthetic with full-bleed hero, sharp corners,
/// and technical data visualizations.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/medicine.dart';
import '../services/app_events.dart';
import '../services/medicine_reminder_scheduler.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';
import '../widgets/tab_history_mixin.dart';
import 'medicine_editor.dart';

class MedicineScreen extends StatefulWidget {
  const MedicineScreen({super.key});

  @override
  State<MedicineScreen> createState() => _MedicineScreenState();
}

class _MedicineScreenState extends State<MedicineScreen> {
  late DateTime _today;
  late DateTime _selectedDay;
  final ScrollController _stripController = ScrollController();
  
  static const int _windowSize = 15;
  static const int _todayIndex = 15;

  final Map<DateTime, List<MedicineDose>> _dosesByDay = {};
  List<Medicine> _medicines = const [];
  bool _loading = true;
  String? _error;
  TimeBucket? _bucketFilter;

  @override
  void initState() {
    super.initState();
    _today = _midnight(DateTime.now());
    _selectedDay = _today;
    _load();
    AppEvents.medicineChanged.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollStripToIndex(_todayIndex, immediate: true));
  }

  @override
  void dispose() {
    AppEvents.medicineChanged.removeListener(_onChanged);
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
      final meds = await SupabaseService.listMedicines();
      final activeIds = meds.where((m) => m.isActive).map((m) => m.id).toSet();
      
      final byDay = <DateTime, List<MedicineDose>>{};
      final start = _today.subtract(const Duration(days: _windowSize));
      for (var i = 0; i <= _windowSize * 2; i++) {
        final d = start.add(Duration(days: i));
        final list = await SupabaseService.getMedicineDosesForDate(d);
        final filtered = list.where((d) => activeIds.contains(d.medicineId)).toList();
        filtered.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
        byDay[_midnight(d)] = filtered;
      }

      if (mounted) {
        setState(() {
          _medicines = meds;
          _dosesByDay..clear()..addAll(byDay);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _handleBack() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      TabHistory.maybePop();
    }
  }

  Future<void> _openEditor({Medicine? existing}) async {
    final result = await MedicineEditorSheet.show(context, existing: existing);
    if (result == null || !mounted) return;
    final ok = await applyMedicineEdit(result: result, existing: existing);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('সংরক্ষণ করা যায়নি।')));
      return;
    }
    AppEvents.notifyMedicineChanged();
  }

  Future<void> _toggleDose(MedicineDose dose, bool taken) async {
    HapticFeedback.lightImpact();
    try {
      await SupabaseService.markDose(
        medicineId: dose.medicineId,
        date: _selectedDay,
        scheduledTime: dose.scheduledTime,
        status: taken ? 'taken' : 'skipped',
      );
      AppEvents.notifyMedicineChanged();
      // If the user just marked a dose taken, drop the matching
      // reminder so we don't nag them again. If they un-toggled,
      // re-schedule will pick it up on the next medicineChanged bump.
      if (taken) {
        unawaited(MedicineReminderScheduler.instance.onDoseTaken(dose.medicineId));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ব্যর্থ: $e')));
    }
  }

  Future<void> _showDoseActions(MedicineDose dose) async {
    HapticFeedback.mediumImpact();
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 38, height: 4,
                decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                child: Row(
                  children: [
                    Container(width: 6, height: 24, decoration: const BoxDecoration(color: AppColors.svcHero)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(dose.nameBn, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.ink)),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: AppColors.ink),
                title: const Text('সম্পাদনা করুন (Edit)', style: TextStyle(fontWeight: FontWeight.w700)),
                onTap: () => Navigator.pop(ctx, 'edit'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.rose),
                title: const Text('মুছে ফেলুন (Delete)', style: TextStyle(color: AppColors.rose, fontWeight: FontWeight.w700)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    if (action == 'edit') {
      final m = _medicines.firstWhere((med) => med.id == dose.medicineId);
      _openEditor(existing: m);
    } else if (action == 'delete') {
      _confirmDelete(dose);
    }
  }

  Future<void> _confirmDelete(MedicineDose dose) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('ওষুধ মুছবেন?', style: TextStyle(fontWeight: FontWeight.w900)),
        content: Text('"${dose.nameBn}" তালিকা থেকে স্থায়ীভাবে মুছে যাবে।'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('বাতিল')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.rose),
            child: const Text('মুছে ফেলুন', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      try {
        await SupabaseService.deleteMedicine(dose.medicineId);
        AppEvents.notifyMedicineChanged();
        _load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('মুছে ফেলা ব্যর্থ: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    var doses = _dosesByDay[_midnight(_selectedDay)] ?? const [];
    if (_bucketFilter != null) {
      doses = doses.where((d) => d.bucket == _bucketFilter).toList();
    }
    
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.svcCategoryBg,
        body: SafeArea(
          top: false,
          child: RefreshIndicator(
            onRefresh: _load,
            color: AppColors.svcHero,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              slivers: [
                _buildHero(),
                const SliverToBoxAdapter(child: SizedBox(height: 22)),
                SliverToBoxAdapter(child: _buildSectionTitle('দৈনিক লক্ষ্য', 'অনুপরতি')),
                SliverToBoxAdapter(child: _buildProgressCard(doses)),
                const SliverToBoxAdapter(child: SizedBox(height: 22)),
                SliverToBoxAdapter(child: _buildSectionTitle('ওষুধের তালিকা', 'সময়সূচী অনুযায়ী')),
                if (doses.isEmpty)
                  _buildEmpty()
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 140),
                    sliver: SliverList.separated(
                      itemCount: doses.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _DoseCard(
                        dose: doses[i],
                        onToggle: (v) => _toggleDose(doses[i], v),
                        onLongPress: () => _showDoseActions(doses[i]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        floatingActionButton: _buildFab(),
      ),
    );
  }

  Widget _buildHero() {
    const url = 'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/app/photo-1564352969906-8b7f46ba4b8b.avif?token=eyJraWQiOiJhZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJhcHAvcGhvdG8tMTU2NDM1Mjk2OTkwNi04YjdmNDZiYTRiOGIuYXZpZiIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODc4Njg2MjksImV4cCI6MTgxOTQwNDYyOX0.Jdl-6cqT6wHh_nv8j-7oD3zjU2KcoR4e5ohJVnZgTNs';
    final dateLabel = DateFormat('EEEE, d MMMM yyyy', 'bn').format(_selectedDay);

    return SliverToBoxAdapter(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.svcHero,
          image: const DecorationImage(image: NetworkImage(url), fit: BoxFit.cover, opacity: 0.7),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: Container(color: Colors.black.withValues(alpha: 0.35))),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 20, 0),
                    child: Row(
                      children: [
                        IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20), onPressed: _handleBack),
                        const Expanded(child: Text('ওষুধের রুটিন', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5))),
                        _todayPill(),
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
                      Text('সময়মতো ওষুধ সেবন আপনার সুস্থতার চাবিকাঠি', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _buildWeekStrip(),
                const SizedBox(height: 20),
                _buildBucketFilter(),
                const SizedBox(height: 24),
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

  Widget _todayPill() {
    final isToday = _midnight(_selectedDay) == _midnight(_today);
    return InkWell(
      onTap: () {
        setState(() => _selectedDay = _today);
        _scrollStripToIndex(_todayIndex);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: isToday ? AppColors.svcHeroAccent : Colors.white12, borderRadius: BorderRadius.zero, border: Border.all(color: Colors.white24)),
        child: Text('আজ', style: TextStyle(color: isToday ? AppColors.svcHero : Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
      ),
    );
  }

  Widget _buildBucketFilter() {
    Widget chip(String label, TimeBucket? key) {
      final active = _bucketFilter == key;
      return GestureDetector(
        onTap: () => setState(() => _bucketFilter = key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          margin: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.zero,
            border: Border.all(color: active ? Colors.white : Colors.white24, width: 1.2),
          ),
          child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: active ? AppColors.svcHero : Colors.white)),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          chip('সব', null),
          chip('সকাল', TimeBucket.morning),
          chip('দুপুর', TimeBucket.noon),
          chip('বিকেল', TimeBucket.afternoon),
          chip('রাত', TimeBucket.night),
        ],
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

  Widget _buildProgressCard(List<MedicineDose> doses) {
    final total = doses.length;
    final done = doses.where((d) => d.isTaken).length;
    final pct = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);

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
                  const Text('আজকের প্রগতি', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.smoke, letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  Text('$done / $total ডোজ সম্পন্ন', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.ink, letterSpacing: -0.5)),
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

  Widget _buildFab() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20, right: 4),
      child: FloatingActionButton(
        onPressed: () => _openEditor(),
        backgroundColor: AppColors.svcHero,
        elevation: 6,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
      ),
    );
  }

  Widget _buildEmpty() {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.medication_outlined, size: 64, color: AppColors.lineStrong),
            const SizedBox(height: 16),
            const Text('আজ কোনো ওষুধের রুটিন নেই', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.smoke)),
            const SizedBox(height: 24),
            MonoButton(label: 'নতুন ওষুধ যোগ করুন', leading: Icons.add_rounded, onPressed: () => _openEditor()),
          ],
        ),
      ),
    );
  }
}

class _DoseCard extends StatelessWidget {
  final MedicineDose dose;
  final ValueChanged<bool> onToggle;
  final VoidCallback onLongPress;

  const _DoseCard({required this.dose, required this.onToggle, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final taken = dose.isTaken;
    final time = _formatTimeBn(dose.scheduledTime);
    final dosage = _doseLine(dose);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: InkWell(
        onTap: () => onToggle(!taken),
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.zero,
            border: Border.all(color: taken ? AppColors.svcHero : AppColors.line, width: taken ? 1.6 : 1.2),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 12, offset: const Offset(0, 6))],
          ),
          child: Row(
            children: [
              // Medicine Icon Box
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: AppColors.svcCategoryBg,
                  borderRadius: BorderRadius.zero,
                  border: Border.all(color: AppColors.line, width: 0.8),
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(medicineFormIcon(dose.form), color: taken ? AppColors.svcHero : AppColors.smoke, size: 28),
                    const SizedBox(height: 4),
                    Text(time, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.smoke)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Medicine Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dose.nameBn.isNotEmpty ? dose.nameBn : (dose.nameEn ?? ''),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.ink, height: 1.2),
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    // Using Wrap to prevent horizontal overflow for long labels
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.zero),
                          child: Text(dosage, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.smoke)),
                        ),
                        Text(
                          mealRelationBn(dose.mealRelation),
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.smoke.withValues(alpha: 0.7)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Technical Log Indicator
              AnimatedContainer(
                duration: AppMotion.short,
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: taken ? AppColors.svcHero : AppColors.surfaceHigh,
                  borderRadius: BorderRadius.zero,
                  border: Border.all(color: taken ? AppColors.svcHero : AppColors.line, width: 1.5),
                ),
                child: Icon(Icons.check_rounded, color: taken ? Colors.white : AppColors.lineStrong, size: 24),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimeBn(String hhmm) {
    try {
      final parts = hhmm.split(':');
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      final time = TimeOfDay(hour: h, minute: m);
      final h12 = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
      final mStr = time.minute.toString().padLeft(2, '0');
      final period = time.period == DayPeriod.am ? 'AM' : 'PM';
      return '$h12:$mStr $period';
    } catch (_) { return hhmm; }
  }

  String _doseLine(MedicineDose d) {
    final amt = d.doseAmount == d.doseAmount.roundToDouble() ? d.doseAmount.toInt().toString() : d.doseAmount.toString();
    final unit = d.doseUnit.isEmpty || d.doseUnit == 'unit' ? medicineFormBn(d.form) : d.doseUnit;
    return '$amt $unit';
  }
}
