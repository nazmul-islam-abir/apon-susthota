/// Drill-down for a single patient.
///
/// Sections:
///   • Header         — name, relationship, age, last seen
///   • Clinical cards — HbA1c, fasting glucose, BP, BMI, CKD
///   • Today overview — meals planned / logged / adherence %
///   • Last 7 days    — mini-bar chart of meal adherence
///   • Recent feed    — merged activity feed (meals, medicine, water,
///                      workout) using CaregiverObservation
///   • Action bar     — log meal / log dose for patient
///
/// Pull-to-refresh and realtime updates via the wrapping
/// CaretakerProvider (selectedPatient is read here).
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/caregiver_observation.dart';
import '../../models/caretaker_patient_summary.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import 'log_meal_for_patient_screen.dart';
import 'log_dose_for_patient_screen.dart';
import 'caretaker_charts_screen.dart';

class PatientDetailScreen extends StatefulWidget {
  final CaretakerPatientSummary patient;
  const PatientDetailScreen({super.key, required this.patient});

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  late Future<_DetailData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DetailData> _load() async {
    final uid = widget.patient.patientUserId;
    final results = await Future.wait([
      SupabaseService.getCaretakerTodayOverview(patientUserId: uid),
      SupabaseService.getCaretakerClinicalSnapshot(patientUserId: uid),
      SupabaseService.getCaretakerRecentActivities(patientUserId: uid, limit: 30),
    ]);
    return _DetailData(
      overview: (results[0] as Map?)?.cast<String, dynamic>() ?? {},
      snapshot: (results[1] as Map?)?.cast<String, dynamic>() ?? {},
      activities: ((results[2] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => CaregiverObservation.fromRpcJson(m.cast<String, dynamic>()))
          .toList(),
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.patient;
    return Scaffold(
      backgroundColor: AppColors.void2,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppColors.text,
        // Allow two lines + ellipsis so long Bangla names don't
        // get truncated to "…" in the AppBar.
        title: Text(
          p.fullName.isEmpty ? 'রোগী' : p.fullName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 16.5,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'দৈনিক / সাপ্তাহিক / মাসিক',
            icon: const Icon(Icons.insights_rounded),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CaretakerChartsScreen(
                    patientUserId: p.patientUserId,
                    patientName: p.fullName.isEmpty ? 'রোগী' : p.fullName,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.violetDeep,
        onRefresh: _refresh,
        child: FutureBuilder<_DetailData>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.violet),
              );
            }
            final data = snap.data ?? _DetailData.empty();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              children: [
                _Header(patient: p),
                const SizedBox(height: 14),
                _ClinicalGrid(snapshot: data.snapshot),
                const SizedBox(height: 14),
                _ConnectionCard(patient: p),
                const SizedBox(height: 14),
                _TodayCard(overview: data.overview),
                const SizedBox(height: 14),
                _RecentFeed(activities: data.activities),
                const SizedBox(height: 24),
                _ActionBar(
                  patientUserId: p.patientUserId,
                  patientName: p.fullName,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DetailData {
  final Map<String, dynamic> overview;
  final Map<String, dynamic> snapshot;
  final List<CaregiverObservation> activities;
  _DetailData({
    required this.overview,
    required this.snapshot,
    required this.activities,
  });
  factory _DetailData.empty() => _DetailData(
        overview: const {},
        snapshot: const {},
        activities: const [],
      );
}

class _Header extends StatelessWidget {
  final CaretakerPatientSummary patient;
  const _Header({required this.patient});

  @override
  Widget build(BuildContext context) {
    final subtitle = patient.subtitleBn;
    final lastSeen = patient.lastSeenAt;
    return Container(
      // Clip the gradient so the rounded corners don't get sliced off
      // by child overflow (especially with long Bangla names).
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.violet.withValues(alpha: 0.10),
            AppColors.cyan.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.violet.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.violet,
                  AppColors.violetDeep,
                ],
              ),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.person,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  patient.fullName.isEmpty ? 'রোগী' : patient.fullName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.text,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                ),
                if (lastSeen != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'শেষ দেখা ${DateFormat('d MMM, HH:mm', 'bn').format(lastSeen.toLocal())}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textDim,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClinicalGrid extends StatelessWidget {
  final Map<String, dynamic> snapshot;
  const _ClinicalGrid({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final hba1c = _num(snapshot['hba1c_percent']);
    final fbg = _num(snapshot['fasting_glucose_mmol']);
    final sbp = _num(snapshot['systolic_bp']);
    final dbp = _num(snapshot['diastolic_bp']);
    final bmi = _num(snapshot['bmi']);
    final ckd = (snapshot['ckd_stage'] as num?)?.toInt();

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // 1.25 keeps the icon + value + label stack readable in
      // three columns on narrow screens (avoids label clipping).
      childAspectRatio: 1.25,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: [
        _ClinicalCard(
          label: 'HbA1c',
          value: hba1c == null ? '—' : '${hba1c.toStringAsFixed(1)}%',
          icon: Icons.bloodtype_rounded,
          color: AppColors.cyan,
        ),
        _ClinicalCard(
          label: 'ফাস্টিং গ্লুকোজ',
          value: fbg == null ? '—' : '${fbg.toStringAsFixed(1)} mmol/L',
          icon: Icons.water_drop_rounded,
          color: AppColors.violet,
        ),
        _ClinicalCard(
          label: 'রক্তচাপ',
          value: (sbp == null || dbp == null)
              ? '—'
              : '${sbp.toStringAsFixed(0)}/${dbp.toStringAsFixed(0)}',
          icon: Icons.favorite_rounded,
          color: AppColors.rose,
        ),
        _ClinicalCard(
          label: 'BMI',
          value: bmi == null ? '—' : bmi.toStringAsFixed(1),
          icon: Icons.monitor_weight_rounded,
          color: AppColors.amber,
        ),
        _ClinicalCard(
          label: 'CKD গ্রেড',
          value: ckd == null ? '—' : 'G$ckd',
          icon: Icons.health_and_safety_rounded,
          color: AppColors.mint,
        ),
        _ClinicalCard(
          label: 'ইনসুলিন',
          value: (snapshot['on_insulin'] ?? false) ? 'হ্যাঁ' : 'না',
          icon: Icons.medication_rounded,
          color: AppColors.violetDeep,
        ),
      ],
    );
  }

  double? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}

class _ClinicalCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _ClinicalCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 6),
          // Allow value to wrap to two lines so wide strings
          // like "120/80 mmHg" don't get truncated on narrow tiles.
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: AppColors.text,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact card showing how this patient was linked. Helps the
/// caretaker confirm at-a-glance that the link is active and
/// whether they themselves sent the request or it was the
/// caretaker style of the patient that initiated it.
class _ConnectionCard extends StatelessWidget {
  final CaretakerPatientSummary patient;
  const _ConnectionCard({required this.patient});

  @override
  Widget build(BuildContext context) {
    final p = patient;
    final initiatedBy = p.initiatedByMe == true
        ? 'আপনি অনুরোধ পাঠিয়েছিলেন'
        : (p.initiatedByMe == false
            ? 'রোগী নিজে সংযোগের অনুরোধ পাঠিয়েছেন'
            : 'সংযোগকারীর তথ্য উপলব্ধ নেই');
    final linkedAt = p.linkedAt;
    final rel = p.subtitleBn.isEmpty ? null : p.subtitleBn;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.cyan.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.link_rounded,
                size: 18,
                color: AppColors.cyanDeep,
              ),
              const SizedBox(width: 8),
              const Text(
                'সংযোগ তথ্য',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.cyan.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'সক্রিয়',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.cyanDeep,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (rel != null) ...[
            Text(
              'সম্পর্ক: $rel',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.text,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            initiatedBy,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          if (linkedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'যুক্ত হয়েছেন: '
              '${DateFormat('d MMM yyyy', 'bn').format(linkedAt.toLocal())}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textDim,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  final Map<String, dynamic> overview;
  const _TodayCard({required this.overview});

  @override
  Widget build(BuildContext context) {
    final planned = (overview['planned'] as num?)?.toInt() ?? 0;
    final logged = (overview['logged'] as num?)?.toInt() ?? 0;
    final good = (overview['good'] as num?)?.toInt() ?? 0;
    final pct = planned == 0 ? 0.0 : (good / planned) * 100;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.today_rounded, color: AppColors.violetDeep),
              const SizedBox(width: 6),
              const Text(
                'আজকের অগ্রগতি',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              const Spacer(),
              Text(
                '${pct.toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.violetDeep,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: (pct / 100).clamp(0.0, 1.0),
              color: AppColors.violetDeep,
              backgroundColor: AppColors.surfaceHigh,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _MiniMetric(label: 'পরিকল্পিত', value: '$planned'),
              const SizedBox(width: 10),
              _MiniMetric(label: 'লগকৃত', value: '$logged'),
              const SizedBox(width: 10),
              _MiniMetric(label: 'ভালো', value: '$good'),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;
  const _MiniMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppColors.text,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentFeed extends StatelessWidget {
  final List<CaregiverObservation> activities;
  const _RecentFeed({required this.activities});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.timeline_rounded, color: AppColors.violetDeep),
              SizedBox(width: 6),
              Text(
                'সাম্প্রতিক কার্যকলাপ',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (activities.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'এখনো কোনো কার্যকলাপ নেই',
                style: TextStyle(color: AppColors.textMuted),
              ),
            )
          else
            ...activities.take(8).map((o) => _FeedRow(o: o)),
        ],
      ),
    );
  }
}

class _FeedRow extends StatelessWidget {
  final CaregiverObservation o;
  const _FeedRow({required this.o});

  /// Maps the kind enum to a left-rail icon. The [tone] string is a
  /// 'good'|'warn'|'bad'|'neutral' color hint that drives the accent
  /// color around the icon. Both are derived here (rather than as
  /// model extensions) because they are UI-only concerns.
  IconData get _iconForKind {
    switch (o.kind) {
      case CaregiverObservationKind.meal:
        return Icons.restaurant_rounded;
      case CaregiverObservationKind.medicine:
        return Icons.medication_rounded;
      case CaregiverObservationKind.water:
        return Icons.water_drop_rounded;
      case CaregiverObservationKind.workout:
        return Icons.fitness_center_rounded;
    }
  }

  Color get _colorForTone {
    switch (o.tone) {
      case 'good':
        return AppColors.cyan;
      case 'warn':
        return AppColors.amber;
      case 'bad':
        return AppColors.rose;
      case 'neutral':
      default:
        return AppColors.violet;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorForTone;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(_iconForKind, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  o.summaryBn,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                    height: 1.25,
                  ),
                ),
                if (o.detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _formatObservationDetail(o.kind, o.detail!),
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  DateFormat('d MMM, HH:mm', 'bn').format(o.occurredAt.toLocal()),
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textDim,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final String patientUserId;
  final String patientName;
  const _ActionBar({
    required this.patientUserId,
    required this.patientName,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.violetDeep,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.restaurant_rounded),
            label: const Text('খাবার লগ'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LogMealForPatientScreen(
                    patientUserId: patientUserId,
                    patientName: patientName,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.cyan,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.medication_rounded),
            label: const Text('ওষুধ লগ'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LogDoseForPatientScreen(
                    patientUserId: patientUserId,
                    patientName: patientName,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Render the jsonb `detail` payload as a single short Bangla
/// caption. Falls back gracefully when fields are missing.
String _formatObservationDetail(
    CaregiverObservationKind kind, Map<String, dynamic> detail) {
  switch (kind) {
    case CaregiverObservationKind.meal:
      final slot = detail['meal_slot']?.toString();
      final food = detail['food_name_bn']?.toString();
      if (slot != null && food != null && food.isNotEmpty) {
        return '$slot • $food';
      }
      return food ?? slot ?? '';
    case CaregiverObservationKind.medicine:
      final status = detail['status']?.toString();
      final scheduled = detail['scheduled_time']?.toString();
      if (status != null && scheduled != null) {
        return '$status • $scheduled';
      }
      return status ?? scheduled ?? '';
    case CaregiverObservationKind.water:
      final liters = detail['liters'];
      return liters == null ? '' : '${liters} লিটার';
    case CaregiverObservationKind.workout:
      final done = detail['completed_items'];
      final total = detail['total_items'];
      if (done != null && total != null) {
        return '$done / $total সম্পন্ন';
      }
      final dur = detail['duration_seconds'];
      if (dur != null) return '$dur সেকেন্ড';
      return '';
  }
}