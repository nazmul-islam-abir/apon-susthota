/// Caretaker read-only medicine viewer.
///
/// Mirrors the patient's `MedicineScreen`: shows ±15-day strip, time-bucket
/// filter, and today's doses.
///
/// Nexora Redesign style: full-bleed hero image with dark overlay.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/caretaker_patient_summary.dart';
import '../../models/medicine.dart';
import '../../services/caretaker_data_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/time_format.dart';
import '../../widgets/caretaker_viewer_header.dart';
import '../../widgets/mono_widgets.dart';
import '../../widgets/patient_data_realtime_mixin.dart';
import 'caretaker_medicine_editor.dart';

class CaretakerMedicineView extends StatefulWidget {
  final CaretakerPatientSummary patient;
  const CaretakerMedicineView({super.key, required this.patient});

  @override
  State<CaretakerMedicineView> createState() => _CaretakerMedicineViewState();
}

class _CaretakerMedicineViewState extends State<CaretakerMedicineView>
    with PatientDataRealtimeMixin {
  late DateTime _today;
  late DateTime _selectedDate;
  TimeBucket? _bucketFilter;
  late Future<_MedData> _future;
  _MedData? _lastData;
  static const int _windowSize = 15;
  static const int _todayIndex = 15;
  final ScrollController _stripController = ScrollController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = _midnight(now);
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

  bool get _isToday => _midnight(_selectedDate).isAtSameMomentAs(_today);

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

  Future<_MedData> _load() async {
    final uid = widget.patient.patientUserId;
    final results = await Future.wait([
      CaretakerDataService.listMedicines(uid),
      CaretakerDataService.getMedicineDosesForDate(
        patientUserId: uid,
        date: _selectedDate,
      ),
    ]);
    final data = _MedData(
      medicines: results[0] as List<Medicine>,
      doses: results[1] as List<MedicineDose>,
    );
    _lastData = data;
    return data;
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  void _goToDay(int delta) {
    final next = _selectedDate.add(Duration(days: delta));
    final start = _today.subtract(const Duration(days: _windowSize));
    final end = _today.add(const Duration(days: _windowSize));
    if (next.isBefore(start) || next.isAfter(end)) return;
    
    setState(() => _selectedDate = _midnight(next));
    final index = next.difference(start).inDays;
    _scrollStripToIndex(index);
    _refresh();
  }

  Future<void> _toggleDose(MedicineDose dose, bool taken) async {
    HapticFeedback.lightImpact();
    try {
      await SupabaseService.caretakerMarkDoseForPatient(
        patientUserId: widget.patient.patientUserId,
        medicineId: dose.medicineId,
        doseDate: _selectedDate,
        scheduledTime: dose.scheduledTime,
        status: taken ? 'taken' : 'skipped',
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

  Future<void> _showDoseActions(MedicineDose dose) async {
    HapticFeedback.mediumImpact();
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.svcCategoryBg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_rounded, color: AppColors.svcHero),
                title: const Text('ওষুধ সম্পাদনা',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                onTap: () => Navigator.pop(ctx, 'edit'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: AppColors.rose),
                title: const Text('ওষুধ মুছে ফেলুন',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: AppColors.rose)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
            ],
          ),
        );
      },
    );

    if (action == 'edit') {
      final m = _lastData?.medicines.firstWhere((med) => med.id == dose.medicineId);
      if (m != null) _openEditor(context, existing: m);
    } else if (action == 'delete') {
      _confirmDelete(dose);
    }
  }

  Future<void> _confirmDelete(MedicineDose dose) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ওষুধ মুছবেন?'),
        content: Text('"${dose.nameBn}" তালিকা থেকে স্থায়ীভাবে মুছে যাবে।'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('বাতিল')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.rose),
            child: const Text('মুছে ফেলুন'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await SupabaseService.caretakerDeleteMedicine(dose.medicineId);
        _refresh();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('মুছে ফেলা যায়নি: $e')));
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
        child: FutureBuilder<_MedData>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done && !snap.hasData) {
              return const Center(child: CircularProgressIndicator(color: AppColors.svcHero));
            }
            final viewData = snap.data ?? _MedData.empty();
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              slivers: [
                CaretakerViewerHeader(
                  patient: widget.patient,
                  screenTitle: 'ওষুধের সময়সূচী',
                ),
                _buildHeroStrip(viewData),
                const SliverToBoxAdapter(child: SizedBox(height: 22)),
                SliverToBoxAdapter(child: _buildSectionTitle('আজকের অগ্রগতি', 'ডোজ স্ট্যাটাস')),
                SliverToBoxAdapter(child: _buildProgressCard(viewData)),
                const SliverToBoxAdapter(child: SizedBox(height: 22)),
                SliverToBoxAdapter(child: _buildSectionTitle('ওষুধের তালিকা', 'সময়সূচী অনুযায়ী')),
                _buildDoseList(viewData),
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
                label: 'নতুন ওষুধ যোগ করুন',
                leading: Icons.add_rounded,
                onPressed: () => _openEditor(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MonoButton(
                label: 'ওষুধের তালিকা',
                leading: Icons.edit_rounded,
                onPressed: () => _openManageList(context, _lastData ?? _MedData.empty()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroStrip(_MedData data) {
    final dateLabel =
        DateFormat('EEEE, d MMMM yyyy', 'bn').format(_selectedDate);

    return SliverToBoxAdapter(
      child: Container(
        color: AppColors.svcHero,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dateLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _isToday
                  ? 'সময়মতো ওষুধ সেবন আপনার সুস্থতার চাবিকাঠি'
                  : 'নির্বাচিত দিনের ওষুধের তালিকা',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            _buildWeekStrip(),
            const SizedBox(height: 16),
            _buildBucketFilter(),
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
          enabled: _selectedDate.isAfter(start),
          onTap: () => _goToDay(-1),
        ),
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
                final isSel = _midnight(d) == _midnight(_selectedDate);
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
          enabled: _selectedDate.isBefore(
            start.add(const Duration(days: _windowSize * 2)),
          ),
          onTap: () => _goToDay(1),
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

  void _onSelectDay(DateTime day) {
    setState(() => _selectedDate = _midnight(day));
    _refresh();
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

  Widget _buildProgressCard(_MedData data) {
    final doses = data.doses;
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
                  const Text('আজকের অগ্রগতি', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.smoke, letterSpacing: 0.5)),
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

  Future<void> _openEditor(BuildContext context, {Medicine? existing}) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => CaretakerMedicineEditorScreen(
        patientUserId: widget.patient.patientUserId,
        patientName: widget.patient.fullName,
        existing: existing,
      ),
    ));
    if (ok == true) _refresh();
  }

  Future<void> _openManageList(BuildContext context, _MedData data) async {
    final meds = data.medicines;
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.svcCategoryBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ওষুধের তালিকা',
                  style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w900,
                    color: AppColors.newsInk,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'টোকা দিয়ে সম্পাদনা বা মুছে ফেলুন',
                  style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w800,
                    color: AppColors.smoke,
                  ),
                ),
                const SizedBox(height: 12),
                if (meds.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'কোনো ওষুধ নেই',
                        style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w900,
                          color: AppColors.smoke,
                        ),
                      ),
                    ),
                  )
                else
                  for (final m in meds)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.medication_rounded,
                          color: AppColors.svcHero),
                      title: Text(
                        m.nameBn,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: AppColors.ink,
                        ),
                      ),
                      subtitle: Text(
                        [
                          medicineFormBn(m.form),
                          if (m.strength != null && m.strength!.isNotEmpty)
                            m.strength!,
                          m.scheduleSummary,
                        ].where((s) => s.isNotEmpty).join(' • '),
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.smoke,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _openEditor(context, existing: m);
                      },
                    ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDoseList(_MedData data) {
    if (data.medicines.isEmpty) {
      return SliverToBoxAdapter(child: _empty('কোনো ওষুধ নিবন্ধিত নেই'));
    }
    var filtered = _bucketFilter == null
        ? data.doses
        : data.doses.where((d) => d.bucket == _bucketFilter).toList();

    if (filtered.isEmpty) {
      return SliverToBoxAdapter(child: _empty('এই ব্যাচে কোনো ডোজ নেই'));
    }

    // Group by bucket
    final byBucket = <TimeBucket, List<MedicineDose>>{};
    for (final d in filtered) {
      byBucket.putIfAbsent(d.bucket, () => []).add(d);
    }

    final children = <Widget>[];
    for (final b in TimeBucket.values) {
      final list = byBucket[b];
      if (list == null || list.isEmpty) continue;
      children.add(_buildBucketSection(b, list));
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      sliver: SliverList(
        delegate: SliverChildListDelegate(children),
      ),
    );
  }

  Widget _buildBucketSection(TimeBucket bucket, List<MedicineDose> doses) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Row(
              children: [
                Icon(_iconForBucket(bucket), color: AppColors.svcHero, size: 16),
                const SizedBox(width: 6),
                Text(
                  _bucketBn(bucket),
                  style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w900,
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
                    '${doses.length}',
                    style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w900,
                      color: AppColors.svcHero,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final d in doses) _buildDoseRow(d),
        ],
      ),
    );
  }

  Widget _buildDoseRow(MedicineDose d) {
    final (color, label) = _statusVisual(d);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _toggleDose(d, !d.isTaken),
        onLongPress: () => _showDoseActions(d),
        child: MonoCard(
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.zero,
                ),
                child: Icon(
                  d.isTaken
                      ? Icons.check_circle_rounded
                      : (d.isMissed
                          ? Icons.cancel_rounded
                          : (d.isSkipped
                              ? Icons.do_not_disturb_rounded
                              : Icons.medication_rounded)),
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.nameBn.isEmpty ? 'ওষুধ' : d.nameBn,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w900,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        // Display the scheduled dose time in 12-hour
                        // AM/PM (stored value is 24h HH:mm).
                        formatTime12hFromString(d.scheduledTime),
                        d.doseLabel,
                        if (d.strength != null && d.strength!.isNotEmpty) d.strength!,
                      ].where((s) => s.isNotEmpty).join(' • '),
                      style: const TextStyle(
                        fontSize: 11.5, color: AppColors.smoke,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.zero,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.medication_outlined, color: AppColors.lineStrong, size: 48),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800,
                color: AppColors.smoke,
              ),
            ),
          ],
        ),
      ),
    );
  }

  (Color, String) _statusVisual(MedicineDose d) {
    if (d.isTaken) return (AppColors.mint, 'নেওয়া হয়েছে');
    if (d.isSkipped) return (AppColors.amber, 'এড়িয়ে যাওয়া');
    if (d.isMissed) return (AppColors.rose, 'মিস হয়েছে');
    return (AppColors.cyan, 'অপেক্ষমান');
  }

  IconData _iconForBucket(TimeBucket b) {
    switch (b) {
      case TimeBucket.morning: return Icons.wb_twilight_rounded;
      case TimeBucket.noon: return Icons.wb_sunny_rounded;
      case TimeBucket.afternoon: return Icons.wb_cloudy_rounded;
      case TimeBucket.night: return Icons.nightlight_round;
    }
  }

  String _bucketBn(TimeBucket b) {
    switch (b) {
      case TimeBucket.morning: return 'সকাল';
      case TimeBucket.noon: return 'দুপুর';
      case TimeBucket.afternoon: return 'বিকেল';
      case TimeBucket.night: return 'রাত';
    }
  }
}

class _MedData {
  final List<Medicine> medicines;
  final List<MedicineDose> doses;
  _MedData({required this.medicines, required this.doses});
  factory _MedData.empty() => _MedData(medicines: const [], doses: const []);
}
