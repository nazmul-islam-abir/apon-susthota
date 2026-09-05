/// Caretaker write flow — mark a medicine dose on the patient's behalf.
///
/// Lists every active medicine on the patient's catalogue (read via
/// `get_caretaker_medicines`), expands the schedule times for "today",
/// and writes the marked dose through `caretaker_mark_dose_for_patient`.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/medicine.dart';
import '../../services/caretaker_data_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/time_format.dart';
import '../../widgets/mono_widgets.dart';

class LogDoseForPatientScreen extends StatefulWidget {
  final String patientUserId;
  final String? patientName;
  const LogDoseForPatientScreen({
    super.key,
    required this.patientUserId,
    this.patientName,
  });

  @override
  State<LogDoseForPatientScreen> createState() =>
      _LogDoseForPatientScreenState();
}

class _LogDoseForPatientScreenState extends State<LogDoseForPatientScreen> {
  late Future<_DoseData> _future;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DoseData> _load() async {
    final today = DateTime.now();
    final results = await Future.wait([
      CaretakerDataService.listMedicines(widget.patientUserId),
      CaretakerDataService.getMedicineDosesForDate(
        patientUserId: widget.patientUserId,
        date: today,
      ),
    ]);
    return _DoseData(
      medicines: (results[0] as List).cast<Medicine>(),
      doses: (results[1] as List).cast<MedicineDose>(),
      date: today,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _markDose({
    required Medicine medicine,
    required MedicineScheduleSlot slot,
    required String status, // taken | skipped | missed
  }) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await SupabaseService.caretakerMarkDoseForPatient(
        patientUserId: widget.patientUserId,
        medicineId: medicine.id,
        doseDate: DateTime.now(),
        scheduledTime: slot.time,
        status: status,
      );
      if (!mounted) return;
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('লগ করা যায়নি: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.patientName ?? '').trim();
    return Scaffold(
      backgroundColor: AppColors.svcCategoryBg,
      appBar: AppBar(
        backgroundColor: AppColors.svcHero,
        foregroundColor: Colors.white,
        title: Text(
          name.isEmpty
              ? 'রোগীর পক্ষে ওষুধ লগ'
              : '$name-এর পক্ষে ওষুধ লগ',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
        ),
        elevation: 0,
      ),
      body: RefreshIndicator(
        color: AppColors.svcHero,
        onRefresh: _refresh,
        child: FutureBuilder<_DoseData>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done && !snap.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.svcHero),
              );
            }
            final data = snap.data ?? _DoseData.empty();
            if (data.medicines.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 80, 20, 40),
                children: const [
                  Center(
                    child: Icon(Icons.medication_rounded,
                        color: AppColors.lineStrong, size: 56),
                  ),
                  SizedBox(height: 12),
                  Center(
                    child: Text(
                      'রোগীর কোনো ওষুধ নেই',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: AppColors.smoke,
                      ),
                    ),
                  ),
                ],
              );
            }
            return ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 60),
              children: [
                _dateHeader(data.date),
                const SizedBox(height: 14),
                for (final med in data.medicines) ...[
                  _medicineHeader(med),
                  const SizedBox(height: 8),
                  _slotsFor(med, data),
                  const SizedBox(height: 16),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _dateHeader(DateTime d) {
    return Row(
      children: [
        const Icon(Icons.event_rounded, color: AppColors.svcHero, size: 16),
        const SizedBox(width: 8),
        Text(
          DateFormat('EEEE, d MMMM', 'bn').format(d),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: AppColors.newsInk,
          ),
        ),
      ],
    );
  }

  Widget _medicineHeader(Medicine m) {
    return MonoCard(
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.mintDeep.withValues(alpha: 0.12),
              borderRadius: BorderRadius.zero,
            ),
            child: const Icon(Icons.medication_rounded,
                color: AppColors.mintDeep, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.nameBn,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
                if (m.strength != null && m.strength!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${medicineFormBn(m.form)} • ${m.strength}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.smoke,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _slotsFor(Medicine med, _DoseData data) {
    final slots = med.schedule;
    if (slots.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          'কোনো সময়সূচি নেই',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.smoke,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    final sorted = [...slots]
      ..sort((a, b) => a.time.compareTo(b.time));

    return Column(
      children: [
        for (final s in sorted)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _slotRow(med, s, data),
          ),
      ],
    );
  }

  Widget _slotRow(Medicine med, MedicineScheduleSlot s, _DoseData data) {
    final dose = data.doses.firstWhere(
      (d) => d.medicineId == med.id && d.scheduledTime == s.time,
      orElse: () => MedicineDose(
        doseId: '',
        medicineId: med.id,
        nameBn: med.nameBn,
        form: med.form,
        doseAmount: med.doseAmount,
        doseUnit: med.doseUnit,
        mealRelation: med.mealRelation,
        scheduledTime: s.time.isEmpty ? '00:00' : s.time,
        bucket: s.bucket,
      ),
    );
    final logged = dose.status == 'taken';
    final skipped = dose.status == 'skipped';

    return MonoCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(
        children: [
          Container(
            width: 60,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.zero,
            ),
            child: Text(
              // Display in 12-hour AM/PM; storage stays 24h HH:mm.
              s.time.isEmpty ? '--:--' : formatTime12hFromString(s.time),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              s.bucket.labelBn,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: AppColors.smoke,
              ),
            ),
          ),
          if (logged)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.check_circle_rounded,
                  color: AppColors.mintDeep, size: 18),
            )
          else if (skipped)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.do_not_disturb_rounded,
                  color: AppColors.amber, size: 18),
            )
          else
            Row(
              children: [
                _actionBtn(
                  icon: Icons.check_rounded,
                  color: AppColors.mintDeep,
                  onTap: () => _markDose(medicine: med, slot: s, status: 'taken'),
                ),
                const SizedBox(width: 6),
                _actionBtn(
                  icon: Icons.close_rounded,
                  color: AppColors.amber,
                  onTap: () => _markDose(medicine: med, slot: s, status: 'skipped'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.zero,
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}

class _DoseData {
  final List<Medicine> medicines;
  final List<MedicineDose> doses;
  final DateTime date;
  _DoseData({
    required this.medicines,
    required this.doses,
    required this.date,
  });
  factory _DoseData.empty() => _DoseData(
        medicines: const [],
        doses: const [],
        date: DateTime.now(),
      );
}
