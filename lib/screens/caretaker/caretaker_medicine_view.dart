/// Caretaker read-only medicine viewer.
///
/// Mirrors the patient's `MedicineScreen`: shows ±15-day strip, time-bucket
/// filter, and today's doses. Tap-to-toggle is disabled (read-only).
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/caretaker_patient_summary.dart';
import '../../models/medicine.dart';
import '../../services/caretaker_data_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/caretaker_viewer_header.dart';
import '../../widgets/mono_widgets.dart';
import 'caretaker_medicine_editor.dart';

class CaretakerMedicineView extends StatefulWidget {
  final CaretakerPatientSummary patient;
  const CaretakerMedicineView({super.key, required this.patient});

  @override
  State<CaretakerMedicineView> createState() => _CaretakerMedicineViewState();
}

class _CaretakerMedicineViewState extends State<CaretakerMedicineView> {
  late DateTime _selectedDate;
  TimeBucket? _bucketFilter;
  late Future<_MedData> _future;
  _MedData? _lastData;
  static const int _windowSize = 15;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _future = _load();
  }

  Future<_MedData> _load() async {
    final uid = widget.patient.patientUserId;
    final results = await Future.wait([
      CaretakerDataService.listMedicines(uid),
      CaretakerDataService.getMedicineDosesForDate(
        patientUserId: uid, date: _selectedDate,
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
    setState(() => _selectedDate = next);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final data = _lastData ?? _MedData.empty();
    return Scaffold(
      backgroundColor: AppColors.svcCategoryBg,
      body: Column(
        children: [
          CaretakerViewerHeader(
            patient: widget.patient,
            screenTitle: 'ওষুধের সময়সূচী',
          ),
          Expanded(
            child: RefreshIndicator(
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
                      SliverToBoxAdapter(child: _buildStrip()),
                      SliverToBoxAdapter(child: _buildBucketFilter()),
                      SliverToBoxAdapter(child: _buildDoseList(viewData)),
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
                onPressed: () => _openManageList(context, data),
              ),
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
                        'কোনো ও�ুধ নেই',
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

  Widget _buildStrip() {
    final start = _selectedDate.subtract(Duration(days: _windowSize));
    final end = _selectedDate.add(Duration(days: _windowSize));
    final days = [for (var i = 0; i <= _windowSize * 2; i++) start.add(Duration(days: i))];
    if (end.isBefore(start)) days.clear();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    DateFormat('d MMM, yyyy', 'bn').format(_selectedDate),
                    style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900,
                      color: AppColors.newsInk,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: () => _goToDay(-1),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: () => _goToDay(1),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 60,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: days.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final d = days[i];
                final selected = _sameDate(d, _selectedDate);
                final dowBn = DateFormat('EEE', 'bn').format(d);
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedDate = DateTime(d.year, d.month, d.day));
                    _refresh();
                  },
                  child: Container(
                    width: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.svcHero : Colors.white,
                      borderRadius: BorderRadius.zero,
                      border: Border.all(
                        color: selected ? AppColors.svcHero : AppColors.line,
                        width: 1.2,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          dowBn,
                          style: TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w800,
                            color: selected ? Colors.white : AppColors.smoke,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${d.day}',
                          style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w900,
                            color: selected ? Colors.white : AppColors.ink,
                          ),
                        ),
                      ],
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

  Widget _buildBucketFilter() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          _bucketChip(label: 'সব', value: null),
          for (final b in TimeBucket.values) _bucketChip(label: bucketBn(b), value: b),
        ],
      ),
    );
  }

  Widget _bucketChip({required String label, required TimeBucket? value}) {
    final selected = _bucketFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _bucketFilter = value),
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
              fontSize: 12, fontWeight: FontWeight.w800,
              color: selected ? Colors.white : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDoseList(_MedData data) {
    if (data.medicines.isEmpty) {
      return _empty('কোনো ওষুধ নিবন্ধিত নেই');
    }
    final filtered = _bucketFilter == null
        ? data.doses
        : data.doses.where((d) => d.bucket == _bucketFilter).toList();

    if (filtered.isEmpty) {
      return _empty('এই ব্যাচে কোনো ডোজ নেই');
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
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
                  bucketBn(bucket),
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
                      d.scheduledTime,
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
    if (d.isTaken) return (AppColors.mint, 'নেওয়া হয়েছে');
    if (d.isSkipped) return (AppColors.amber, 'এড়িয়ে যাওয়া');
    if (d.isMissed) return (AppColors.rose, 'মিস হয়েছে');
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

  bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String bucketBn(TimeBucket b) {
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
