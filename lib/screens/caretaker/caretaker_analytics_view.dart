/// Caretaker read-only analytics view.
///
/// Mirrors the patient's `AnalyticsScreen`: hero score, 30-day cycle
/// navigator, day ribbon, 4 donut stats (meal/med/water/workout),
/// today's mood, doctor-report banner.
///
/// Nexora Redesign style: full-bleed hero image with dark overlay.
library;

import 'package:flutter/material.dart';

import '../../models/caretaker_patient_summary.dart';
import '../../models/mood_entry.dart';
import '../../models/thirty_day_report.dart';
import '../../services/caretaker_data_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/caretaker_viewer_header.dart';
import '../../widgets/mono_widgets.dart';
import '../../widgets/patient_data_realtime_mixin.dart';
import 'caretaker_report_view.dart';

class CaretakerAnalyticsView extends StatefulWidget {
  final CaretakerPatientSummary patient;
  const CaretakerAnalyticsView({super.key, required this.patient});

  @override
  State<CaretakerAnalyticsView> createState() => _CaretakerAnalyticsViewState();
}

class _CaretakerAnalyticsViewState extends State<CaretakerAnalyticsView>
    with PatientDataRealtimeMixin {
  int _cycleIndex = 0;
  late Future<_AnalyticsData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    // Live-refresh the 30-day analysis (meal/water/workout/medicine)
    // whenever the patient logs anything — not just on pull-to-refresh.
    attachPatientDataRealtime(widget.patient.patientUserId, _refresh);
  }

  @override
  void dispose() {
    disposePatientDataRealtime();
    super.dispose();
  }

  Future<_AnalyticsData> _load() async {
    final uid = widget.patient.patientUserId;
    final results = await Future.wait([
      CaretakerDataService.getThirtyDayReport(patientUserId: uid, cycleIndex: _cycleIndex),
      CaretakerDataService.getAnalyticsCycleCount(uid),
      CaretakerDataService.getTodayMood(uid),
    ]);
    return _AnalyticsData(
      report: results[0] as ThirtyDayReport?,
      cycleCount: results[1] as int,
      mood: results[2] as MoodEntry?,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  void _goCycle(int delta) {
    setState(() => _cycleIndex = (_cycleIndex + delta).clamp(0, 999));
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.svcCategoryBg,
      body: RefreshIndicator(
        color: AppColors.svcHero,
        onRefresh: _refresh,
        child: FutureBuilder<_AnalyticsData>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done && !snap.hasData) {
              return const Center(child: CircularProgressIndicator(color: AppColors.svcHero));
            }
            final data = snap.data ?? _AnalyticsData.empty();
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              slivers: [
                CaretakerViewerHeader(
                  patient: widget.patient,
                  screenTitle: 'বিশ্লেষণ',
                ),
                SliverToBoxAdapter(child: _buildHero(data)),
                SliverToBoxAdapter(child: _buildCycleNav(data)),
                if (data.report != null) ...[
                  SliverToBoxAdapter(child: _buildDayRibbon(data.report!)),
                  SliverToBoxAdapter(child: _buildDonuts(data.report!)),
                ],
                SliverToBoxAdapter(child: _buildMood(data)),
                SliverToBoxAdapter(child: _buildReportBanner()),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHero(_AnalyticsData data) {
    final report = data.report;
    final score = report?.days.fold<int>(0, (acc, d) => acc + d.adherencePct) ?? 0;
    final scorePct = report == null || report.days.isEmpty
        ? 0.0
        : ((score / report.days.length) / 100).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: MonoCard(
        child: Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 84, height: 84,
                  child: CircularProgressIndicator(
                    value: scorePct,
                    strokeWidth: 10,
                    color: AppColors.svcHero,
                    backgroundColor: AppColors.surfaceHigh,
                  ),
                ),
                Text(
                  '${(scorePct * 100).round()}',
                  style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w900,
                    color: AppColors.ink, letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'সামগ্রিক স্কোর',
                    style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w900,
                      color: AppColors.smoke, letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    report == null
                        ? 'কোনো তথ্য পাওয়া যায়নি'
                        : 'সাইকেল ${data.cycleCount - _cycleIndex} / ${data.cycleCount}',
                    style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w900,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'দৈনিক গড় ভিত্তিক',
                    style: const TextStyle(
                      fontSize: 11, color: AppColors.smoke,
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

  Widget _buildCycleNav(_AnalyticsData data) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '৩০ দিনের সাইকেল',
                  style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w900,
                    color: AppColors.newsInk,
                  ),
                ),
                Text(
                  data.cycleCount > 1
                      ? 'মোট ${data.cycleCount}টি সাইকেল সংরক্ষিত'
                      : 'প্রথম সাইকেল',
                  style: const TextStyle(
                    fontSize: 11, color: AppColors.smoke,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () => _openCyclePicker(data.cycleCount),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: _cycleIndex < data.cycleCount - 1 ? () => _goCycle(1) : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: _cycleIndex > 0 ? () => _goCycle(-1) : null,
          ),
        ],
      ),
    );
  }

  Future<void> _openCyclePicker(int total) async {
    final selected = await showModalBottomSheet<int>(
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
                  'সাইকেল বাছাই করুন',
                  style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w900,
                    color: AppColors.newsInk,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'সর্বশেষ সাইকেলটি বর্তমান ৩০ দিনের',
                  style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w800,
                    color: AppColors.smoke,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 320,
                  child: ListView.separated(
                    itemCount: total,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final isCurrent = i == _cycleIndex;
                      return InkWell(
                        onTap: () => Navigator.pop(ctx, i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isCurrent ? AppColors.svcHero : Colors.white,
                            borderRadius: BorderRadius.zero,
                            border: Border.all(
                              color: isCurrent ? AppColors.svcHero : AppColors.line,
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  i == 0
                                      ? 'সর্বশেষ সাইকেল (বর্তমান)'
                                      : 'সাইকেল ${total - i}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: isCurrent ? Colors.white : AppColors.ink,
                                  ),
                                ),
                              ),
                              if (isCurrent)
                                const Icon(Icons.check_rounded,
                                    color: Colors.white, size: 16),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null && selected != _cycleIndex) {
      setState(() => _cycleIndex = selected);
      _refresh();
    }
  }

  Widget _buildDayRibbon(ThirtyDayReport report) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
      child: MonoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'দৈনিক সারসংক্ষেপ',
              style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w900,
                color: AppColors.smoke, letterSpacing: 0.5,
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
                            fontSize: 12, fontWeight: FontWeight.w900,
                            color: AppColors.ink,
                          ),
                        ),
                        Container(
                          width: 6, height: 6,
                          decoration: BoxDecoration(
                            color: color, borderRadius: BorderRadius.zero,
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
    final mealsPct = _avgAdherence(report.days.map((d) =>
        d.plannedMeals == 0 ? 0.0 : (d.loggedMeals.total / d.plannedMeals).clamp(0.0, 1.0)));
    final medPct = _avgAdherence(report.days.map((d) =>
        d.medicine.scheduled == 0 ? 0.0 : (d.medicine.taken / d.medicine.scheduled).clamp(0.0, 1.0)));
    final waterPct = _avgAdherence(report.days.map((d) =>
        (d.waterMl / 2500).clamp(0.0, 1.0)));
    final workoutPct = _avgAdherence(report.days.map((d) {
      if (d.workouts.doneAny == 0) return 0.0;
      if (d.workouts.completed >= 1) return 1.0;
      return 0.5;
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
              fontSize: 12, fontWeight: FontWeight.w900,
              color: AppColors.smoke, letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              SizedBox(
                width: 32, height: 32,
                child: CircularProgressIndicator(
                  value: pct, strokeWidth: 4,
                  color: color, backgroundColor: AppColors.surfaceHigh,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(pct * 100).round()}%',
                style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w900,
                  color: color, letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '৩০ দিনের গড়',
            style: TextStyle(
              fontSize: 10, color: AppColors.smoke,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMood(_AnalyticsData data) {
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
                      fontSize: 12, fontWeight: FontWeight.w900,
                      color: AppColors.smoke, letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mood.mood.labelBn,
                    style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w900,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ঘুম: ${mood.sleepHours.toStringAsFixed(1)} ঘণ্টা • শক্তি ${mood.energyLevel}/5',
                    style: const TextStyle(
                      fontSize: 11, color: AppColors.smoke,
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

  Widget _buildReportBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
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
          child: Row(
            children: [
              const Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 28),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ডাক্তারের প্রতিবেদন',
                      style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '৩০ দিনের পূর্ণ পিডিএফ প্রতিবেদন দেখুন',
                      style: TextStyle(
                        fontSize: 11, color: Colors.white70,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  double _avgAdherence(Iterable<double> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }
}

class _AnalyticsData {
  final ThirtyDayReport? report;
  final int cycleCount;
  final MoodEntry? mood;
  _AnalyticsData({required this.report, required this.cycleCount, required this.mood});
  factory _AnalyticsData.empty() => _AnalyticsData(
        report: null, cycleCount: 1, mood: null,
      );
}
