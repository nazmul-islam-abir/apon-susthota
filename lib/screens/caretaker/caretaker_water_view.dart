/// Caretaker read-only water viewer — full mirror of the patient's
/// `WaterScreen` so a caretaker can see exactly what the patient sees
/// for any chosen day (±15 days).
///
/// Nexora Redesign style: full-bleed hero image with dark overlay.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/caretaker_patient_summary.dart';
import '../../models/water_analytics.dart';
import '../../models/workout.dart';
import '../../services/caretaker_data_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/caretaker_viewer_header.dart';
import '../../widgets/mono_widgets.dart';
import '../../widgets/patient_data_realtime_mixin.dart';

class CaretakerWaterView extends StatefulWidget {
  final CaretakerPatientSummary patient;
  const CaretakerWaterView({super.key, required this.patient});

  @override
  State<CaretakerWaterView> createState() => _CaretakerWaterViewState();
}

class _CaretakerWaterViewState extends State<CaretakerWaterView>
    with PatientDataRealtimeMixin {
  late DateTime _today;
  late DateTime _selectedDay;
  final ScrollController _stripController = ScrollController();
  static const int _windowSize = 15;
  static const int _todayIndex = 15;
  static const double _targetLiters = 2.5;

  late Future<_WaterData> _future;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _today = _midnight(DateTime.now());
    _selectedDay = _today;
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

  bool get _isToday => _midnight(_selectedDay).isAtSameMomentAs(_today);

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

  Future<_WaterData> _load() async {
    final uid = widget.patient.patientUserId;
    final results = await Future.wait([
      CaretakerDataService.getDailyMetricsForDate(
        patientUserId: uid,
        date: _selectedDay,
      ),
      CaretakerDataService.getWaterAnalytics(patientUserId: uid, days: _windowSize),
    ]);
    final data = _WaterData(
      metric: results[0] as DailyMetric,
      analytics: results[1] as WaterAnalyticsSummary,
    );
    return data;
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _future = _load();
    });
    try {
      await _future;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSelectDay(DateTime day) {
    setState(() => _selectedDay = _midnight(day));
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.svcCategoryBg,
      body: RefreshIndicator(
        color: AppColors.svcHero,
        onRefresh: _refresh,
        child: FutureBuilder<_WaterData>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done && !snap.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.svcHero),
              );
            }
            final data = snap.data ?? _WaterData.empty();
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                CaretakerViewerHeader(
                  patient: widget.patient,
                  screenTitle: 'পানির খতিয়ান',
                ),
                _buildDayStripSliver(),
                const SliverToBoxAdapter(child: SizedBox(height: 22)),
                SliverToBoxAdapter(
                  child: _buildSectionTitle('আজকের লক্ষ্য', 'হাইড্রেশন সূচক'),
                ),
                SliverToBoxAdapter(child: _buildDailyTargetCard(data)),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
                SliverToBoxAdapter(
                  child: _buildSectionTitle('পানির বিবরণ', 'দিনের সারসংক্ষেপ'),
                ),
                SliverToBoxAdapter(child: _buildInteractiveGlassCard(data)),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
                SliverToBoxAdapter(
                  child: _buildSectionTitle('সময় অনুযায়ী গাইড', 'আপনার রুটিন'),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _BucketRow(
                        bucket: _Bucket.values[i],
                        current: _bucketCountFor(
                          _Bucket.values[i],
                          data,
                        ),
                      ),
                      childCount: _Bucket.values.length,
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: _buildBucketBreakdown(data)),
                SliverToBoxAdapter(child: _buildTipCard()),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildDayStripSliver() {
    return SliverToBoxAdapter(
      child: Container(
        color: AppColors.svcHero,
        padding: const EdgeInsets.only(bottom: 16),
        child: _buildWeekStrip(),
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
          enabled: _selectedDay.isAfter(start),
          onTap: () {
            final next = _selectedDay.subtract(const Duration(days: 1));
            final index = next.difference(start).inDays;
            if (index >= 0) {
              _onSelectDay(next);
              _scrollStripToIndex(index);
            }
          },
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
                final isSel = _midnight(d) == _midnight(_selectedDay);
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
          enabled: _selectedDay.isBefore(
            start.add(const Duration(days: _windowSize * 2)),
          ),
          onTap: () {
            final next = _selectedDay.add(const Duration(days: 1));
            final index = next.difference(start).inDays;
            if (index <= _windowSize * 2) {
              _onSelectDay(next);
              _scrollStripToIndex(index);
            }
          },
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

  Widget _buildSectionTitle(String title, String sub) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AppColors.newsInk,
              letterSpacing: -0.3,
            ),
          ),
          Text(
            sub,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.newsMuted.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyTargetCard(_WaterData data) {
    final glasses = (data.metric.waterLiters / 0.25).round();
    final progress = (data.metric.waterLiters / _targetLiters).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: AppColors.line, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'পানির লক্ষ্যমাত্রা',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: AppColors.smoke,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${data.metric.waterLiters.toStringAsFixed(2)} / $_targetLiters L',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  MonoBar(value: progress, height: 8, fill: Colors.blue),
                  const SizedBox(height: 6),
                  Text(
                    'গ্লাস সংখ্যা: $glasses',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.smoke,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 10,
                    color: Colors.blue,
                    backgroundColor: AppColors.surfaceHigh,
                  ),
                ),
                Text(
                  '${(progress * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInteractiveGlassCard(_WaterData data) {
    final pct = (data.metric.waterLiters / _targetLiters).clamp(0.0, 1.0);
    final glasses = (data.metric.waterLiters / 0.25).round();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: AppColors.line, width: 1.2),
        ),
        child: Column(
          children: [
            SizedBox(
              width: 160,
              height: 220,
              child: CustomPaint(
                painter: _StaticGlassPainter(fill: pct),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _isToday
                  ? (glasses == 0
                      ? 'আজ এখনও পানি যোগ করা হয়নি'
                      : 'আজ $glasses গ্লাস পান করা হয়েছে')
                  : 'নির্বাচিত দিনে $glasses গ্লাস',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.smoke,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBucketBreakdown(_WaterData data) {
    final totals = data.analytics.bucketTotals;
    final hasAny = totals.values.any((v) => v > 0);
    if (!hasAny) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'সময় অনুযায়ী বিতরণ (৭ দিন)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: AppColors.newsInk,
              ),
            ),
            const SizedBox(height: 12),
            for (final entry in totals.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(
                        WaterDayStat.bucketBn(entry.key),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    Expanded(
                      child: MonoBar(
                        value: data.analytics.totalGlasses == 0
                            ? 0
                            : entry.value / data.analytics.totalGlasses,
                        height: 6,
                        fill: AppColors.cyan,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 36,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${entry.value}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: AppColors.ink,
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

  Widget _buildTipCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.svcCategoryBg,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Icon(
              Icons.tips_and_updates_rounded,
              color: AppColors.svcHero,
              size: 24,
            ),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                'ডায়াবেটিক রোগীদের জন্য খাবারের ৩০ মিনিট আগে এক গ্লাস পানি রক্তে শর্করা নিয়ন্ত্রণে সাহায্য করে।',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _bucketCountFor(_Bucket b, _WaterData data) {
    final total = (data.metric.waterLiters / 0.25).round();
    if (total == 0) return 0;
    var rem = total;
    for (final v in _Bucket.values) {
      final take = v.recommendation < rem ? v.recommendation : rem;
      if (v == b) return take;
      rem -= take;
    }
    return 0;
  }
}

enum _Bucket { morning, noon, afternoon, night }

extension on _Bucket {
  String get bn {
    switch (this) {
      case _Bucket.morning: return 'সকাল';
      case _Bucket.noon: return 'দুপুর';
      case _Bucket.afternoon: return 'বিকেল';
      case _Bucket.night: return 'রাত';
    }
  }

  String get hint {
    switch (this) {
      case _Bucket.morning: return 'ঘুম থেকে উঠে ১ গ্লাস';
      case _Bucket.noon: return 'দুপুরের খাবারের সাথে';
      case _Bucket.afternoon: return 'বিকেলে ২ গ্লাস';
      case _Bucket.night: return 'ঘুমের ১ ঘণ্টা আগে';
    }
  }

  int get recommendation {
    switch (this) {
      case _Bucket.morning: return 1;
      case _Bucket.noon: return 1;
      case _Bucket.afternoon: return 2;
      case _Bucket.night: return 1;
    }
  }
}

class _BucketRow extends StatelessWidget {
  final _Bucket bucket;
  final int current;
  const _BucketRow({required this.bucket, required this.current});

  @override
  Widget build(BuildContext context) {
    final done = current >= bucket.recommendation;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.zero,
          border: Border.all(
            color: done ? AppColors.svcHero : AppColors.line,
            width: done ? 1.4 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.svcCategoryBg,
                borderRadius: BorderRadius.zero,
              ),
              alignment: Alignment.center,
              child: Text(
                bucket.bn,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: AppColors.svcHero,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                bucket.hint,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$current / ${bucket.recommendation}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: done ? AppColors.svcHero : AppColors.smoke,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
              size: 20,
              color: done ? AppColors.svcHero : AppColors.lineStrong,
            ),
          ],
        ),
      ),
    );
  }
}

class _StaticGlassPainter extends CustomPainter {
  final double fill;
  _StaticGlassPainter({required this.fill});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final glassPath = Path()
      ..moveTo(w * 0.1, 0)
      ..lineTo(w * 0.2, h)
      ..lineTo(w * 0.8, h)
      ..lineTo(w * 0.9, 0)
      ..close();

    canvas.drawPath(
      glassPath,
      Paint()..color = AppColors.surfaceHigh..style = PaintingStyle.fill,
    );

    final level = h * (1 - fill);
    final waterPath = Path()
      ..moveTo(w * 0.15, level)
      ..lineTo(w * 0.2, h)
      ..lineTo(w * 0.8, h)
      ..lineTo(w * 0.85, level)
      ..close();

    canvas.drawPath(
      waterPath,
      Paint()
        ..color = const Color(0xFF0EA5E9).withValues(alpha: 0.5)
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      glassPath,
      Paint()
        ..color = AppColors.lineStrong
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _StaticGlassPainter oldDelegate) =>
      oldDelegate.fill != fill;
}

class _WaterData {
  final DailyMetric metric;
  final WaterAnalyticsSummary analytics;
  _WaterData({required this.metric, required this.analytics});
  factory _WaterData.empty() => _WaterData(
        metric: DailyMetric.empty,
        analytics: WaterAnalyticsSummary.empty,
      );
}
