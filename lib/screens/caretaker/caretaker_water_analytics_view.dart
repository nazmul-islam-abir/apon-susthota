/// Caretaker read-only water analytics view.
///
/// 7-day + 30-day toggle, bucket distribution, streak + consistency
/// stats. Mirrors `WaterAnalyticsScreen`.
library;

import 'package:flutter/material.dart';

import '../../models/caretaker_patient_summary.dart';
import '../../models/water_analytics.dart';
import '../../services/caretaker_data_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/caretaker_viewer_header.dart';
import '../../widgets/mono_widgets.dart';

class CaretakerWaterAnalyticsView extends StatefulWidget {
  final CaretakerPatientSummary patient;
  const CaretakerWaterAnalyticsView({super.key, required this.patient});

  @override
  State<CaretakerWaterAnalyticsView> createState() => _CaretakerWaterAnalyticsViewState();
}

class _CaretakerWaterAnalyticsViewState extends State<CaretakerWaterAnalyticsView> {
  int _days = 7;
  late Future<WaterAnalyticsSummary> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<WaterAnalyticsSummary> _load() {
    return CaretakerDataService.getWaterAnalytics(
      patientUserId: widget.patient.patientUserId,
      days: _days,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  void _setDays(int d) {
    if (d == _days) return;
    setState(() => _days = d);
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
            screenTitle: 'পানি বিশ্লেষণ',
          ),
          // Toggle
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Row(
              children: [
                _toggle('৭ দিন', 7),
                const SizedBox(width: 10),
                _toggle('৩০ দিন', 30),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.svcHero,
              onRefresh: _refresh,
              child: FutureBuilder<WaterAnalyticsSummary>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done && !snap.hasData) {
                    return const Center(child: CircularProgressIndicator(color: AppColors.svcHero));
                  }
                  final data = snap.data ?? WaterAnalyticsSummary.empty;
                  return CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    slivers: [
                      SliverToBoxAdapter(child: _buildHero(data)),
                      SliverToBoxAdapter(child: _buildStatsGrid(data)),
                      SliverToBoxAdapter(child: _buildDayList(data)),
                      const SliverToBoxAdapter(child: SizedBox(height: 40)),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggle(String label, int days) {
    final selected = days == _days;
    return Expanded(
      child: GestureDetector(
        onTap: () => _setDays(days),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
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
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: selected ? Colors.white : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHero(WaterAnalyticsSummary data) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: MonoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'সারসংক্ষেপ',
              style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w900,
                color: AppColors.smoke, letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              data.verdict(),
              style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w900,
                color: AppColors.ink, height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            MonoBar(
              value: (data.consistencyPct / 100).clamp(0.0, 1.0),
              height: 8, fill: AppColors.cyan,
            ),
            const SizedBox(height: 6),
            Text(
              'ধারাবাহিকতা ${data.consistencyPct.toStringAsFixed(0)}%',
              style: const TextStyle(
                fontSize: 11, color: AppColors.smoke,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid(WaterAnalyticsSummary data) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.7,
        children: [
          _stat('গড়', '${data.avgLiters.toStringAsFixed(1)} L', 'প্রতিদিন', AppColors.cyan),
          _stat('লক্ষ্য পূরণ', '${data.daysHitTarget}', 'দিন', AppColors.mint),
          _stat('�ারাবাহিকতা', '${data.streakDays}', 'দিনের স্�্রিক', AppColors.amber),
          _stat('মোট', '${data.totalLiters.toStringAsFixed(1)} L', '${data.totalGlasses} গ্লাস', AppColors.violetDeep),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, String hint, Color color) {
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
              fontSize: 11, fontWeight: FontWeight.w900,
              color: AppColors.smoke, letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w900,
              color: color, letterSpacing: -0.5,
            ),
          ),
          Text(
            hint,
            style: const TextStyle(
              fontSize: 10, color: AppColors.smoke,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayList(WaterAnalyticsSummary data) {
    if (data.days.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.all(20),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.zero,
            border: Border.all(color: AppColors.line),
          ),
          child: const Text(
            'কোনো দৈনিক তথ্য নেই',
            style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w800,
              color: AppColors.smoke,
            ),
          ),
        ),
      );
    }

    final reversed = data.days.reversed.toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: MonoCard(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                'দৈনিক বিবরণ',
                style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w900,
                  color: AppColors.newsInk,
                ),
              ),
            ),
            for (final d in reversed) _dayRow(d, data.targetLiters),
          ],
        ),
      ),
    );
  }

  Widget _dayRow(WaterDayStat d, double target) {
    final pct = target == 0 ? 0.0 : (d.liters / target).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(
              d.date,
              style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800,
                color: AppColors.smoke,
              ),
            ),
          ),
          Expanded(
            child: MonoBar(
              value: pct, height: 6,
              fill: d.targetHit ? AppColors.mint : AppColors.cyan,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 56,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${d.liters.toStringAsFixed(1)} L',
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w900,
                  color: d.targetHit ? AppColors.mintDeep : AppColors.ink,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (d.targetHit)
            const Icon(Icons.check_circle_rounded, color: AppColors.mint, size: 14)
          else
            const SizedBox(width: 14),
        ],
      ),
    );
  }
}
