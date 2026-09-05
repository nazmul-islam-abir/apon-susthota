/// Caretaker one-tap "doctor-grade" full patient view.
///
/// Single scrollable screen that combines every read-only fragment
/// a caregiver-as-doctor needs to assess a patient.
///
/// Nexora Redesign style: full-bleed hero image with dark overlay.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/caregiver_observation.dart';
import '../../models/caretaker_patient_summary.dart';
import '../../models/mood_entry.dart';
import '../../models/thirty_day_report.dart';
import '../../services/caretaker_data_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/caretaker_viewer_header.dart';
import '../../widgets/mono_widgets.dart';
import '../../widgets/patient_data_realtime_mixin.dart';
import 'caretaker_meal_plan_view.dart';
import 'caretaker_water_view.dart';
import 'caretaker_medicine_view.dart';
import 'caretaker_workout_view.dart';
import 'caretaker_water_analytics_view.dart';
import 'caretaker_analytics_view.dart';
import 'caretaker_report_view.dart';
import 'caretaker_profile_view.dart';
import 'caretaker_charts_screen.dart';

class CaretakerFullPatientView extends StatefulWidget {
  final CaretakerPatientSummary patient;
  const CaretakerFullPatientView({super.key, required this.patient});

  @override
  State<CaretakerFullPatientView> createState() =>
      _CaretakerFullPatientViewState();
}

class _CaretakerFullPatientViewState extends State<CaretakerFullPatientView>
    with PatientDataRealtimeMixin {
  int _cycleIndex = 0;
  late Future<_FullData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    attachPatientDataRealtime(widget.patient.patientUserId, _refresh);
  }

  @override
  void dispose() {
    disposePatientDataRealtime();
    super.dispose();
  }

  Future<_FullData> _load() async {
    final uid = widget.patient.patientUserId;
    final results = await Future.wait([
      CaretakerDataService.getProfile(uid),
      CaretakerDataService.getThirtyDayReport(patientUserId: uid, cycleIndex: _cycleIndex),
      CaretakerDataService.getAnalyticsCycleCount(uid),
      CaretakerDataService.getTodayMood(uid),
      CaretakerDataService.getMealAdherence(patientUserId: uid, days: 7),
      CaretakerDataService.getMedicineAdherence(patientUserId: uid, days: 7),
      CaretakerDataService.getWorkoutAdherence(patientUserId: uid, days: 7),
      SupabaseService.getCaretakerRecentActivities(patientUserId: uid, limit: 30),
    ]);
    return _FullData(
      profile: (results[0] as Map?)?.cast<String, dynamic>() ?? const {},
      report: results[1] as ThirtyDayReport?,
      cycleCount: results[2] as int,
      mood: results[3] as MoodEntry?,
      mealAdh7: (results[4] as num?)?.toDouble() ?? 0,
      medAdh7: (results[5] as num?)?.toDouble() ?? 0,
      woAdh7: (results[6] as num?)?.toDouble() ?? 0,
      activities: results[7] as List<CaregiverObservation>,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  void _goCycle(int delta) {
    final next = (_cycleIndex + delta).clamp(0, 999);
    if (next == _cycleIndex) return;
    setState(() => _cycleIndex = next);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.svcCategoryBg,
      body: RefreshIndicator(
        color: AppColors.svcHero,
        onRefresh: _refresh,
        child: FutureBuilder<_FullData>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done &&
                !snap.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.svcHero),
              );
            }
            final data = snap.data ?? _FullData.empty();
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                CaretakerViewerHeader(
                  patient: widget.patient,
                  screenTitle: 'রোগীর সম্পূর্ণ তথ্য',
                ),
                SliverToBoxAdapter(child: _buildIdentity(data)),
                SliverToBoxAdapter(child: _buildClinical(data)),
                SliverToBoxAdapter(child: _buildAdherence7d(data)),
                SliverToBoxAdapter(child: _buildCycleNav(data)),
                if (data.report != null) ...[
                  SliverToBoxAdapter(child: _buildDayRibbon(data.report!)),
                  SliverToBoxAdapter(child: _buildDonuts(data.report!)),
                ],
                SliverToBoxAdapter(child: _buildMood(data)),
                SliverToBoxAdapter(child: _buildShortcuts()),
                SliverToBoxAdapter(child: _buildRecentActivities(data)),
                SliverToBoxAdapter(child: _buildReportBanner()),
                const SliverToBoxAdapter(child: SizedBox(height: 60)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildIdentity(_FullData data) {
    final p = widget.patient;
    final prof = data.profile;
    final age = prof['age'] as int?;
    final sex = (prof['sex'] as String?) ?? '';
    final ins = prof['on_insulin'] as bool?;
    final ckd = prof['has_ckd'] as bool?;
    final ht = prof['has_heart_disease'] as bool?;
    final an = prof['has_anemia'] as bool?;
    final rel = (p.caretakerRelationship ?? '').trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: MonoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.svcHero,
                    borderRadius: BorderRadius.zero,
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: (p.avatarUrl ?? '').isNotEmpty
                      ? Image.network(
                          p.avatarUrl!,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _initials(p.fullName),
                          loadingBuilder: (_, child, prog) =>
                              prog == null ? child : _initials(p.fullName),
                        )
                      : _initials(p.fullName),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.fullName.isEmpty ? 'রোগী' : p.fullName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.ink,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (age != null) '$age বছর',
                          if (sex.isNotEmpty) sex == 'male' ? 'পুরুষ' : (sex == 'female' ? 'মহিলা' : 'অন্যান্য'),
                          if (rel.isNotEmpty) rel,
                        ].join(' • '),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.smoke,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (ins == true ||
                ckd == true ||
                ht == true ||
                an == true) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (ins == true) _flag('ইনসুলিন', AppColors.amber),
                  if (ckd == true) _flag('কিডনি সমস্যা', AppColors.violetDeep),
                  if (ht == true) _flag('হৃদরোগ', AppColors.rose),
                  if (an == true) _flag('রক্তশূন্যতা', AppColors.cyan),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _flag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.zero,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }

  Widget _initials(String name) {
    final s = name.trim();
    if (s.isEmpty) return const Text('র', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900));
    final parts = s.split(RegExp(r'\s+'));
    final ini = parts.length >= 2 ? (parts[0][0]) + (parts[1][0]) : s.characters.first.toUpperCase();
    return Text(
      ini,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w900,
      ),
    );
  }

  Widget _buildClinical(_FullData data) {
    final p = widget.patient;
    final prof = data.profile;
    final hba1c = _num(prof['hba1c_percent']) ?? p.hba1cPercent;
    final fbg = _num(prof['fasting_glucose_mmol']) ?? p.fastingGlucoseMmol;
    final sbp = _num(prof['systolic_bp'])?.toInt();
    final dbp = _num(prof['diastolic_bp'])?.toInt();
    final bmi = _num(prof['bmi']);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 6, 4, 8),
            child: Text(
              'ক্লিনিক্যাল স্ন্যাপশট',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: AppColors.smoke,
                letterSpacing: 0.5,
              ),
            ),
          ),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.8,
            children: [
              _metric('HbA1c',
                  hba1c == null ? '—' : '${hba1c.toStringAsFixed(1)}%', Icons.bloodtype_rounded, AppColors.cyan),
              _metric('ফাস্টিং গ্লুকোজ',
                  fbg == null ? '—' : '${fbg.toStringAsFixed(1)}', Icons.water_drop_rounded, AppColors.violet),
              _metric('রক্তচাপ',
                  (sbp == null || dbp == null) ? '—' : '$sbp/$dbp', Icons.favorite_rounded, AppColors.rose),
              _metric('BMI',
                  bmi == null ? '—' : bmi.toStringAsFixed(1), Icons.monitor_weight_rounded, AppColors.amber),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
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
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.smoke,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  double? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  Widget _buildAdherence7d(_FullData data) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: MonoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'গত ৭ দিনের আনুগত্য',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: AppColors.smoke,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 10),
            _adherenceRow('খাবার', data.mealAdh7, AppColors.cyan),
            const SizedBox(height: 8),
            _adherenceRow('ওষুধ', data.medAdh7, AppColors.mintDeep),
            const SizedBox(height: 8),
            _adherenceRow('ব্যায়াম', data.woAdh7, AppColors.amber),
          ],
        ),
      ),
    );
  }

  Widget _adherenceRow(String label, double pct, Color color) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
            ),
          ),
        ),
        Expanded(
          child: MonoBar(value: pct.clamp(0.0, 1.0), height: 8, fill: color),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 48,
          child: Text(
            '${(pct * 100).round()}%',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCycleNav(_FullData data) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '৩০ দিনের সাইকেল',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: AppColors.newsInk,
                  ),
                ),
                Text(
                  data.cycleCount > 1
                      ? 'মোট ${data.cycleCount}টি সাইকেল সংরক্ষিত'
                      : 'প্রথম সাইকেল',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.smoke,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed:
                _cycleIndex < data.cycleCount - 1 ? () => _goCycle(1) : null,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.svcHero,
              borderRadius: BorderRadius.zero,
            ),
            child: Text(
              'সাইকেল ${data.cycleCount - _cycleIndex}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: _cycleIndex > 0 ? () => _goCycle(-1) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildDayRibbon(ThirtyDayReport report) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
      child: MonoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'দৈনিক আনুগত্য — ৩০ দিন',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: AppColors.smoke,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: report.days.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final d = report.days[i];
                  final pct = d.adherencePct / 100.0;
                  final color = pct >= 0.75
                      ? AppColors.mint
                      : (pct >= 0.5 ? AppColors.amber : AppColors.rose);
                  return Container(
                    width: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.zero,
                      border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${d.dayOfCycle}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: AppColors.ink,
                          ),
                        ),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.zero,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDonuts(ThirtyDayReport report) {
    final mealsPct = _avg(report.days.map((d) =>
        d.plannedMeals == 0 ? 0.0 : (d.loggedMeals.total / d.plannedMeals).clamp(0.0, 1.0)));
    final medPct = _avg(report.days.map((d) =>
        d.medicine.scheduled == 0 ? 0.0 : (d.medicine.taken / d.medicine.scheduled).clamp(0.0, 1.0)));
    final waterPct = _avg(report.days.map((d) => (d.waterMl / 2500).clamp(0.0, 1.0)));
    final workoutPct = _avg(report.days.map((d) {
      if (d.workouts.doneAny == 0) return 0.0;
      return d.workouts.completed >= 1 ? 1.0 : 0.5;
    }));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.4,
        children: [
          _donutTile('খাবার', mealsPct, AppColors.cyan),
          _donutTile('ওষুধ', medPct, AppColors.mintDeep),
          _donutTile('পানি', waterPct, AppColors.violetDeep),
          _donutTile('ব্যায়াম', workoutPct, AppColors.amber),
        ],
      ),
    );
  }

  Widget _donutTile(String label, double pct, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.line, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: AppColors.smoke,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  value: pct,
                  strokeWidth: 4,
                  color: color,
                  backgroundColor: AppColors.surfaceHigh,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(pct * 100).round()}%',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: color,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '৩০ দিনের গড়',
            style: TextStyle(
              fontSize: 10,
              color: AppColors.smoke,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  double _avg(Iterable<double> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  Widget _buildMood(_FullData data) {
    final mood = data.mood;
    if (mood == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: MonoCard(
        child: Row(
          children: [
            Text(mood.mood.emoji, style: const TextStyle(fontSize: 36)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'আজকের মেজাজ',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: AppColors.smoke,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mood.mood.labelBn,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ঘুম: ${mood.sleepHours.toStringAsFixed(1)} ঘণ্টা • শক্তি ${mood.energyLevel}/5',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.smoke,
                      fontWeight: FontWeight.w800,
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

  Widget _buildShortcuts() {
    final p = widget.patient;
    void go(Widget screen) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    }

    final tiles = <_ShortcutTile>[
      _ShortcutTile(
        icon: Icons.restaurant_menu_rounded,
        label: 'খাবারের পরিকল্পনা',
        color: AppColors.cyan,
        onTap: () => go(CaretakerMealPlanView(patient: p)),
      ),
      _ShortcutTile(
        icon: Icons.water_drop_rounded,
        label: 'পানির খতিয়ান',
        color: AppColors.violetDeep,
        onTap: () => go(CaretakerWaterView(patient: p)),
      ),
      _ShortcutTile(
        icon: Icons.analytics_rounded,
        label: 'পানি বিশ্লেষণ',
        color: Colors.blue,
        onTap: () => go(CaretakerWaterAnalyticsView(patient: p)),
      ),
      _ShortcutTile(
        icon: Icons.medication_rounded,
        label: 'ওষুধ',
        color: AppColors.mintDeep,
        onTap: () => go(CaretakerMedicineView(patient: p)),
      ),
      _ShortcutTile(
        icon: Icons.fitness_center_rounded,
        label: 'ব্যায়াম',
        color: AppColors.amber,
        onTap: () => go(CaretakerWorkoutView(patient: p)),
      ),
      _ShortcutTile(
        icon: Icons.bar_chart_rounded,
        label: 'চার্ট',
        color: AppColors.svcHero,
        onTap: () => go(CaretakerChartsScreen(
          patientUserId: p.patientUserId,
          patientName: p.fullName,
        )),
      ),
      _ShortcutTile(
        icon: Icons.insights_rounded,
        label: 'বিশ্লেষণ',
        color: AppColors.violetDeep,
        onTap: () => go(CaretakerAnalyticsView(patient: p)),
      ),
      _ShortcutTile(
        icon: Icons.person_outline_rounded,
        label: 'প্রোফাইল',
        color: AppColors.smoke,
        onTap: () => go(CaretakerProfileView(patient: p)),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text(
              'বিস্তারিত দেখুন',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: AppColors.smoke,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.0,
            children: tiles,
          ),
        ],
      ),
    );
  }

  Widget _buildReportBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => CaretakerReportView(patient: widget.patient),
          ));
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.svcHero,
            borderRadius: BorderRadius.zero,
          ),
          child: const Row(
            children: [
              Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 28),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ডাক্তারের প্রতিবেদন',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '৩০ দিনের পূর্ণ পিডিএফ প্রতিবেদন দেখুন ও শেয়ার করুন',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentActivities(_FullData data) {
    final list = data.activities;
    if (list.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text(
              'সাম্প্রতিক কার্যকলাপ',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: AppColors.smoke,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 6),
          MonoCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < list.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                  _ActivityRow(obs: list[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FullData {
  final Map<String, dynamic> profile;
  final ThirtyDayReport? report;
  final int cycleCount;
  final MoodEntry? mood;
  final double mealAdh7;
  final double medAdh7;
  final double woAdh7;
  final List<CaregiverObservation> activities;
  _FullData({
    required this.profile,
    required this.report,
    required this.cycleCount,
    required this.mood,
    required this.mealAdh7,
    required this.medAdh7,
    required this.woAdh7,
    required this.activities,
  });
  factory _FullData.empty() => _FullData(
        profile: const {},
        report: null,
        cycleCount: 1,
        mood: null,
        mealAdh7: 0,
        medAdh7: 0,
        woAdh7: 0,
        activities: const [],
      );
}

class _ShortcutTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ShortcutTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: AppColors.line, width: 1.2),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.zero,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink,
                  height: 1.15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final CaregiverObservation obs;
  const _ActivityRow({required this.obs});

  @override
  Widget build(BuildContext context) {
    final tone = _toneColor(obs.tone);
    final icon = _iconFor(obs.kind);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.12),
              borderRadius: BorderRadius.zero,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: tone),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  obs.summaryBn.isEmpty ? obs.kind.labelBn : obs.summaryBn,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('d MMM, HH:mm', 'bn').format(obs.occurredAt.toLocal()),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.smoke,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _toneColor(String tone) {
    switch (tone) {
      case 'good':
        return AppColors.svcHero;
      case 'bad':
        return AppColors.rose;
      case 'warn':
        return AppColors.amber;
      default:
        return AppColors.smoke;
    }
  }

  IconData _iconFor(CaregiverObservationKind k) {
    switch (k) {
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
}
