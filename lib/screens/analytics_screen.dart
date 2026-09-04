/// Analytics screen — Professional health dashboard with Syncfusion trend charts and circular metrics.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../l10n/app_localizations.dart';
import '../models/mood_entry.dart';
import '../models/thirty_day_report.dart';
import '../services/app_events.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';
import '../widgets/tab_history_mixin.dart';
import 'doctor_report_screen.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  int _cycleIndex = 0;
  int _selectedDayIndex = 0;
  int _maxCycleIndex = 1;
  Future<_AnalyticsData>? _future;

  @override
  void initState() {
    super.initState();
    _refresh();
    AppEvents.profileChanged.addListener(_refresh);
    AppEvents.mealLogged.addListener(_refresh);
    AppEvents.medicineChanged.addListener(_refresh);
    AppEvents.workoutChanged.addListener(_refresh);
    AppEvents.waterChanged.addListener(_refresh);
    AppEvents.moodChanged.addListener(_refresh);
  }

  @override
  void dispose() {
    AppEvents.profileChanged.removeListener(_refresh);
    AppEvents.mealLogged.removeListener(_refresh);
    AppEvents.medicineChanged.removeListener(_refresh);
    AppEvents.workoutChanged.removeListener(_refresh);
    AppEvents.waterChanged.removeListener(_refresh);
    AppEvents.moodChanged.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _future = _load();
    });
  }

  Future<_AnalyticsData> _load() async {
    final results = await Future.wait([
      SupabaseService.getThirtyDayReport(cycleIndex: _cycleIndex),
      SupabaseService.getAnalyticsCycleCount(),
      SupabaseService.getTodayMood(),
    ]);
    final report = results[0] as ThirtyDayReport;
    final cycles = results[1] as int;
    final mood = results[2] as MoodEntry?;

    if (_cycleIndex == 0) {
      // Find today's index in the report days
      final todayIdx = report.days.indexWhere((d) => d.isToday);
      if (todayIdx != -1) {
        _selectedDayIndex = todayIdx;
      } else {
        // Fallback to the last day that is not in the future
        final pastIdx = report.days.lastIndexWhere((d) => !d.isFuture);
        _selectedDayIndex = pastIdx != -1 ? pastIdx : 0;
      }
    }

    _maxCycleIndex = cycles.clamp(1, 999);
    return _AnalyticsData(report: report, maxCycleIndex: _maxCycleIndex, todayMood: mood);
  }

  void _setCycle(int idx) {
    if (idx == _cycleIndex) return;
    HapticFeedback.selectionClick();
    setState(() {
      _cycleIndex = idx;
      _selectedDayIndex = 0;
      _future = _load();
    });
  }

  void _setSelectedDay(int idx) {
    if (idx == _selectedDayIndex) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedDayIndex = idx;
    });
  }

  void _handleBack() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      TabHistory.maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
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
          child: FutureBuilder<_AnalyticsData>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: LoadingMark());
              }
              if (snap.hasError) {
                return _ErrorState(message: snap.error.toString(), onRetry: _refresh);
              }
              final d = snap.data!;
              final report = d.report;
              final selectedDay = report.days[_selectedDayIndex];

              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                color: AppColors.svcHero,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 140),
                  children: [
                    _HeroSection(report: report, selectedIndex: _selectedDayIndex, onBack: _handleBack),
                    const SizedBox(height: 24),
                    _CycleNavigator(selected: _cycleIndex, max: _maxCycleIndex, onSelect: _setCycle),
                    const SizedBox(height: 20),
                    _DayRibbon(days: report.days, selectedIndex: _selectedDayIndex, onSelect: _setSelectedDay),
                    
                    const SizedBox(height: 32),
                    _SectionTitle(title: 'দৈনিক প্রগতি', sub: selectedDay.dateLabelBn),
                    _ActivityGrid(day: selectedDay),

                    const SizedBox(height: 40),
                    _SectionTitle(title: 'ধারাবাহিক বিশ্লেষণ', sub: 'গত ৩০ দিনের ট্রেন্ড'),
                    _TrendCharts(report: report),

                    const SizedBox(height: 32),
                    if (selectedDay.isToday && d.todayMood != null) ...[
                      _SectionTitle(title: 'আজকের মানসিক অবস্থা', sub: 'মনোভাব ও স্বাস্থ্য সিগন্যাল'),
                      _MoodSection(entry: d.todayMood!),
                      const SizedBox(height: 32),
                    ],
                    
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _DoctorReportBanner(),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AnalyticsData {
  final ThirtyDayReport report;
  final int maxCycleIndex;
  final MoodEntry? todayMood;
  _AnalyticsData({required this.report, required this.maxCycleIndex, this.todayMood});
}

class _HeroSection extends StatelessWidget {
  final ThirtyDayReport report;
  final int selectedIndex;
  final VoidCallback onBack;
  const _HeroSection({required this.report, required this.selectedIndex, required this.onBack});

  int _calculateCorrectScore(ThirtyDayReportDay d) {
    double totalProgress = 0;
    int weight = 0;

    if (d.plannedMeals > 0) {
      totalProgress += (d.loggedMeals.total / d.plannedMeals).clamp(0.0, 1.0);
      weight++;
    }
    totalProgress += (d.waterMl / 2500.0).clamp(0.0, 1.0);
    weight++;
    totalProgress += (d.workouts.minutes / 30.0).clamp(0.0, 1.0);
    weight++;
    if (d.medicine.scheduled > 0) {
      totalProgress += (d.medicine.taken / d.medicine.scheduled).clamp(0.0, 1.0);
      weight++;
    }

    if (weight == 0) return 0;
    return ((totalProgress / weight) * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    const url = 'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/app/photo-1564352969906-8b7f46ba4b8b.avif?token=eyJraWQiOiJhZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJhcHAvcGhvdG8tMTU2NDM1Mjk2OTkwNi04YjdmNDZiYTRiOGIuYXZpZiIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODc4Njg2MjksImV4cCI6MTgxOTQwNDYyOX0.Jdl-6cqT6wHh_nv8j-7oD3zjU2KcoR4e5ohJVnZgTNs';
    final day = report.days[selectedIndex];
    final score = _calculateCorrectScore(day);
    final color = score >= 80 ? AppColors.svcHeroAccent : score >= 50 ? Colors.amber : AppColors.rose;

    return Container(
      decoration: BoxDecoration(
        gradient: AppGradients.aurora,
        image: const DecorationImage(image: NetworkImage(url), fit: BoxFit.cover, opacity: 0.7),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: Container(color: Colors.black.withValues(alpha: 0.4))),
          Column(
            children: [
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 20, 0),
                  child: Row(
                    children: [
                      IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20), onPressed: onBack),
                      const Expanded(child: Text('স্বাস্থ্য বিশ্লেষণ', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900))),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
                child: Column(
                  children: [
                    const Text('OVERALL HEALTH SCORE', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),
                    const SizedBox(height: 24),
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 160, height: 160,
                          child: CircularProgressIndicator(value: score / 100, strokeWidth: 14, color: color, backgroundColor: Colors.white10),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('$score%', style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w900, letterSpacing: -1.5)),
                            Text(score >= 80 ? 'EXCELLENT' : (score > 0 ? 'KEEP GOING' : 'START TODAY'), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Text(day.isToday ? 'আপনার আজকের রিপোর্ট' : '${day.dateLabelBn} এর রিপোর্ট', style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActivityGrid extends StatelessWidget {
  final ThirtyDayReportDay day;
  const _ActivityGrid({required this.day});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.count(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 0.75,
        children: [
          _ActivityDonut(
            label: 'খাবার',
            value: '${day.loggedMeals.total}',
            target: '${day.plannedMeals}',
            pct: day.plannedMeals == 0 ? 0.0 : (day.loggedMeals.total / day.plannedMeals),
            icon: Icons.restaurant_rounded,
            color: AppColors.amber,
            unit: 'আইটেম',
          ),
          _ActivityDonut(
            label: 'ব্যায়াম',
            value: '${day.workouts.minutes}',
            target: '৩০',
            pct: (day.workouts.minutes / 30.0).clamp(0.0, 1.0),
            icon: Icons.fitness_center_rounded,
            color: AppColors.svcHeroAccent,
            unit: 'মিনিট',
          ),
          _ActivityDonut(
            label: 'পানি',
            value: '${(day.waterMl / 250).round()}',
            target: '১০',
            pct: (day.waterMl / 2500.0).clamp(0.0, 1.0),
            icon: Icons.water_drop_rounded,
            color: Colors.blue,
            unit: 'গ্লাস',
          ),
          _ActivityDonut(
            label: 'ওষুধ',
            value: '${day.medicine.taken}',
            target: '${day.medicine.scheduled}',
            pct: day.medicine.scheduled == 0 ? 0.0 : (day.medicine.taken / day.medicine.scheduled),
            icon: Icons.medication_rounded,
            color: AppColors.violet,
            unit: 'ডোজ',
          ),
        ],
      ),
    );
  }
}

class _ActivityDonut extends StatelessWidget {
  final String label, value, target;
  final double pct;
  final IconData icon;
  final Color color;
  final String unit;

  const _ActivityDonut({required this.label, required this.value, required this.target, required this.pct, required this.icon, required this.color, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line, width: 1.5)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: pct.clamp(0.0, 1.0),
                    strokeWidth: 6,
                    color: color,
                    backgroundColor: AppColors.surfaceHigh,
                    strokeCap: StrokeCap.butt,
                  ),
                ),
                Icon(icon, color: color.withValues(alpha: 0.8), size: 20),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.smoke)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('$value / $target $unit', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.ink)),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
//  TREND CHARTS — Professional Bar Graphs using Syncfusion
// ════════════════════════════════════════════════════════════════════════

class _TrendCharts extends StatelessWidget {
  final ThirtyDayReport report;
  const _TrendCharts({required this.report});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          _ChartCard(
            title: 'পানির ট্রেন্ড (গ্লাস)',
            color: Colors.blue,
            data: report.days.map((d) => _ChartData(d.dayOfCycle, (d.waterMl / 250).toDouble())).toList(),
            target: 10,
          ),
          const SizedBox(height: 20),
          _ChartCard(
            title: 'খাবার ট্রেন্ড (আইটেম)',
            color: AppColors.amber,
            data: report.days.map((d) => _ChartData(d.dayOfCycle, d.loggedMeals.total.toDouble())).toList(),
            target: 5, // Typical target meals
          ),
          const SizedBox(height: 20),
          _ChartCard(
            title: 'ব্যায়াম ট্রেন্ড (মিনিট)',
            color: AppColors.svcHeroAccent,
            data: report.days.map((d) => _ChartData(d.dayOfCycle, d.workouts.minutes.toDouble())).toList(),
            target: 30,
          ),
          const SizedBox(height: 20),
          _ChartCard(
            title: 'ওষুধের ট্রেন্ড (ডোজ)',
            color: AppColors.violet,
            data: report.days.map((d) => _ChartData(d.dayOfCycle, d.medicine.taken.toDouble())).toList(),
            target: 3,
          ),
        ],
      ),
    );
  }
}

class _ChartData {
  final int day;
  final double value;
  _ChartData(this.day, this.value);
}

class _ChartCard extends StatelessWidget {
  final String title;
  final Color color;
  final List<_ChartData> data;
  final double target;

  const _ChartCard({required this.title, required this.color, required this.data, required this.target});

  @override
  Widget build(BuildContext context) {
    // Dynamic Scaling Logic:
    // We find the max value in the current data set.
    // The Y axis maximum is the higher of (Target * 1.5) or (Max_Value * 1.1).
    // This ensures bars always fit in the box and look professional.
    double maxVal = data.map((e) => e.value).fold(0, (prev, curr) => math.max(prev, curr));
    double chartMax = math.max(target * 1.5, maxVal * 1.1);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.ink)),
              Text('লক্ষ্য: ${target.round()}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color.withValues(alpha: 0.7))),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: SfCartesianChart(
              margin: EdgeInsets.zero,
              plotAreaBorderWidth: 0,
              primaryXAxis: NumericAxis(
                interval: 5,
                majorGridLines: const MajorGridLines(width: 0),
                axisLine: const AxisLine(width: 1),
                labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
              ),
              primaryYAxis: NumericAxis(
                minimum: 0,
                maximum: chartMax,
                labelFormat: '{value}',
                majorTickLines: const MajorTickLines(size: 0),
                axisLine: const AxisLine(width: 0),
                majorGridLines: const MajorGridLines(width: 0.5, dashArray: [5, 5]),
                labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
              ),
              series: <CartesianSeries<_ChartData, num>>[
                ColumnSeries<_ChartData, num>(
                  dataSource: data,
                  xValueMapper: (_ChartData d, _) => d.day,
                  yValueMapper: (_ChartData d, _) => d.value,
                  color: color,
                  borderRadius: BorderRadius.zero,
                  width: 0.6,
                  // Show the target line
                  trendlines: [
                    Trendline(
                      type: TrendlineType.linear,
                      color: Colors.red.withValues(alpha: 0.3),
                      dashArray: [2, 2],
                      width: 1,
                    )
                  ],
                ),
              ],
              // Add a constant line for the target
              annotations: <CartesianChartAnnotation>[
                CartesianChartAnnotation(
                  widget: Container(
                    height: 1,
                    width: double.infinity,
                    color: Colors.red.withValues(alpha: 0.3),
                  ),
                  coordinateUnit: CoordinateUnit.point,
                  x: 1,
                  y: target,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MoodSection extends StatelessWidget {
  final MoodEntry entry;
  const _MoodSection({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line, width: 1.5)),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(color: AppColors.svcCategoryBg, borderRadius: BorderRadius.zero),
                  alignment: Alignment.center,
                  child: Text(entry.mood.emoji, style: const TextStyle(fontSize: 32)),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('মনোভাব: ${entry.mood.labelBn}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                      Text('ঘুমের সময়: ${entry.sleepHours.round()} ঘণ্টা', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.smoke)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _MoodStat(label: 'এনার্জি', value: '${entry.energyLevel}/5', icon: Icons.bolt_rounded, color: Colors.orange)),
                Expanded(child: _MoodStat(label: 'স্ট্রেস', value: '${entry.stressLevel}/5', icon: Icons.psychology_outlined, color: Colors.purple)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MoodStat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _MoodStat({required this.label, required this.value, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.smoke)),
      ],
    );
  }
}

class _CycleNavigator extends StatelessWidget {
  final int selected;
  final int max;
  final ValueChanged<int> onSelect;
  const _CycleNavigator({required this.selected, required this.max, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: List.generate(max, (i) {
          final isSel = i == selected;
          return GestureDetector(
            onTap: () => onSelect(i),
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(color: isSel ? AppColors.svcHero : Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: isSel ? AppColors.svcHero : AppColors.line, width: 1.5)),
              child: Text(i == 0 ? 'বর্তমান চক্র' : '$i চক্র আগে', style: TextStyle(color: i == selected ? Colors.white : AppColors.ink, fontWeight: FontWeight.w900, fontSize: 12)),
            ),
          );
        }),
      ),
    );
  }
}

class _DayRibbon extends StatelessWidget {
  final List<ThirtyDayReportDay> days;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  const _DayRibbon({required this.days, required this.selectedIndex, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 70,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: days.length,
        itemBuilder: (context, i) {
          final isSel = i == selectedIndex;
          final isFuture = days[i].isFuture;
          return GestureDetector(
            onTap: isFuture ? null : () => onSelect(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 52,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(color: isSel ? AppColors.svcHeroAccent : (isFuture ? Colors.transparent : Colors.white), borderRadius: BorderRadius.zero, border: Border.all(color: isSel ? AppColors.svcHeroAccent : AppColors.line, width: 1.5)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${days[i].dayOfCycle}', style: TextStyle(color: isSel ? AppColors.svcHero : (isFuture ? AppColors.smoke : AppColors.ink), fontWeight: FontWeight.w900, fontSize: 18)),
                  Text(days[i].bnWeekday, style: TextStyle(color: isSel ? AppColors.svcHero : AppColors.smoke, fontWeight: FontWeight.w800, fontSize: 10)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title, sub;
  const _SectionTitle({required this.title, required this.sub});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.ink, letterSpacing: -0.5)),
          Text(sub, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.smoke)),
        ],
      ),
    );
  }
}

class _DoctorReportBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DoctorReportScreen())),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(color: AppColors.svcHero, borderRadius: BorderRadius.zero),
        child: const Row(
          children: [
            Icon(Icons.description_outlined, color: Colors.white, size: 28),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ডাক্তারের রিপোর্ট', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                  Text('সম্পূর্ণ ৩০ দিনের বিস্তারিত PDF', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 16),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.rose),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          MonoButton(label: 'আবার চেষ্টা করুন', onPressed: onRetry),
        ],
      ),
    );
  }
}
