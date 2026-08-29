/// Analytics screen — Professional health tracker with full-bleed Nexora hero.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  }

  @override
  void dispose() {
    AppEvents.profileChanged.removeListener(_refresh);
    AppEvents.mealLogged.removeListener(_refresh);
    AppEvents.medicineChanged.removeListener(_refresh);
    AppEvents.workoutChanged.removeListener(_refresh);
    AppEvents.waterChanged.removeListener(_refresh);
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
    ]);
    final report = results[0] as ThirtyDayReport;
    final cycles = results[1] as int;

    if (_cycleIndex == 0) {
      _selectedDayIndex = (report.dayOfCycle - 1).clamp(0, report.days.length - 1);
    }

    _maxCycleIndex = cycles.clamp(1, 999);
    return _AnalyticsData(report: report, maxCycleIndex: _maxCycleIndex);
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
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  slivers: [
                    _HeroSection(
                      report: report,
                      selectedIndex: _selectedDayIndex,
                      onBack: _handleBack,
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    SliverToBoxAdapter(
                      child: _CycleNavigator(selected: _cycleIndex, max: _maxCycleIndex, onSelect: _setCycle),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 20)),
                    SliverToBoxAdapter(
                      child: _DayRibbon(days: report.days, selectedIndex: _selectedDayIndex, onSelect: _setSelectedDay),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 32)),
                    SliverToBoxAdapter(
                      child: _SectionTitle(title: 'দৈনিক অ্যাক্টিভিটি', sub: selectedDay.dateLabelBn),
                    ),
                    SliverToBoxAdapter(
                      child: _ActivityGrid(day: selectedDay),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 32)),
                    SliverToBoxAdapter(
                      child: _SectionTitle(title: 'প্রগ্রেস ট্রেন্ড', sub: 'বিগত ৩০ দিন'),
                    ),
                    SliverToBoxAdapter(
                      child: _TrendsSection(report: report, selectedIndex: _selectedDayIndex, onDayTap: _setSelectedDay),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 32)),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _DoctorReportBanner(),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 140)),
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
  _AnalyticsData({required this.report, required this.maxCycleIndex});
}

class _HeroSection extends StatelessWidget {
  final ThirtyDayReport report;
  final int selectedIndex;
  final VoidCallback onBack;
  const _HeroSection({required this.report, required this.selectedIndex, required this.onBack});

  @override
  Widget build(BuildContext context) {
    const url = 'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/app/photo-1564352969906-8b7f46ba4b8b.avif?token=eyJraWQiOiJhZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJhcHAvcGhvdG8tMTU2NDM1Mjk2OTkwNi04YjdmNDZiYTRiOGIuYXZpZiIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODc4Njg2MjksImV4cCI6MTgxOTQwNDYyOX0.Jdl-6cqT6wHh_nv8j-7oD3zjU2KcoR4e5ohJVnZgTNs';
    final day = report.days[selectedIndex];
    final score = day.adherencePct.clamp(0, 100);
    final color = score >= 80 ? AppColors.svcHeroAccent : score >= 50 ? Colors.amber : AppColors.rose;

    return SliverToBoxAdapter(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.svcHero,
          image: const DecorationImage(image: NetworkImage(url), fit: BoxFit.cover, opacity: 0.7),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: Container(color: Colors.black.withValues(alpha: 0.4))),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 20, 0),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                          onPressed: onBack,
                        ),
                        const Expanded(
                          child: Text(
                            'স্বাস্থ্য বিশ্লেষণ',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 22),
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
                  child: Column(
                    children: [
                      const Text('HEALTH SCORE', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),
                      const SizedBox(height: 24),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 150, height: 150,
                            child: CircularProgressIndicator(value: score / 100, strokeWidth: 12, color: color, backgroundColor: Colors.white10),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('$score%', style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w900, letterSpacing: -1.5)),
                              Text(score >= 80 ? 'EXCELLENT' : (score >= 50 ? 'STABLE' : 'ACTION NEEDED'), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      Text(
                        day.isToday ? 'আজকের সংক্ষিপ্ত সারসংক্ষেপ' : '${day.dateLabelBn} এর রিপোর্ট',
                        style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
              decoration: BoxDecoration(
                color: isSel ? AppColors.svcHero : Colors.white,
                borderRadius: BorderRadius.zero,
                border: Border.all(color: isSel ? AppColors.svcHero : AppColors.line, width: 1.5),
              ),
              child: Text(
                i == 0 ? 'বর্তমান চক্র' : '$i চক্র আগে',
                style: TextStyle(color: i == selected ? Colors.white : AppColors.ink, fontWeight: FontWeight.w900, fontSize: 12),
              ),
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
              decoration: BoxDecoration(
                color: isSel ? AppColors.svcHeroAccent : (isFuture ? Colors.transparent : Colors.white),
                borderRadius: BorderRadius.zero,
                border: Border.all(color: isSel ? AppColors.svcHeroAccent : AppColors.line, width: 1.5),
              ),
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

class _ActivityGrid extends StatelessWidget {
  final ThirtyDayReportDay day;
  const _ActivityGrid({required this.day});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.all(20),
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.4,
      children: [
        _ActivityTile(label: 'খাবার', value: '${day.loggedMeals.total}/${day.plannedMeals}', icon: Icons.restaurant_rounded, color: AppColors.amber),
        _ActivityTile(label: 'ব্যায়াম', value: '${day.workouts.minutes} মি', icon: Icons.fitness_center_rounded, color: AppColors.svcHeroAccent),
        _ActivityTile(label: 'পানি', value: '${(day.waterMl / 1000).toStringAsFixed(1)}L', icon: Icons.water_drop_rounded, color: Colors.blue),
        _ActivityTile(label: 'ওষুধ', value: '${day.medicine.taken}/${day.medicine.scheduled}', icon: Icons.medication_rounded, color: AppColors.violet),
      ],
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _ActivityTile({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line, width: 1.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.zero), child: Icon(icon, color: color, size: 18)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.ink, height: 1.1))),
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.smoke)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrendsSection extends StatelessWidget {
  final ThirtyDayReport report;
  final int selectedIndex;
  final ValueChanged<int> onDayTap;
  const _TrendsSection({required this.report, required this.selectedIndex, required this.onDayTap});

  @override
  Widget build(BuildContext context) {
    final activeDays = report.days.where((d) => !d.isFuture).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          _ChartCard(
            title: 'সামগ্রিক ধারাবাহিকতা',
            icon: Icons.auto_graph_rounded,
            child: SizedBox(
              height: 180,
              child: ClipRect(
                child: BarChart(
                  BarChartData(
                    maxY: 100,
                    barTouchData: BarTouchData(touchCallback: (e, r) {
                      if (e is FlTapUpEvent && r?.spot != null) onDayTap(r!.spot!.touchedBarGroupIndex);
                    }),
                    titlesData: _titles(activeDays),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    barGroups: List.generate(activeDays.length, (i) => BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: activeDays[i].adherencePct.toDouble().clamp(5, 100),
                          width: 6,
                          color: i == selectedIndex ? AppColors.svcHeroAccent : AppColors.svcHero.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.zero,
                          backDrawRodData: BackgroundBarChartRodData(show: true, toY: 100, color: AppColors.svcCategoryBg),
                        ),
                      ],
                    )),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _ChartCard(
            title: 'পানি পান (লিটার)',
            icon: Icons.water_drop_outlined,
            child: SizedBox(
              height: 160,
              child: LineChart(
                LineChartData(
                  maxY: 4.0,
                  gridData: const FlGridData(show: false),
                  titlesData: _titles(activeDays, isLine: true),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: List.generate(activeDays.length, (i) => FlSpot(i.toDouble(), activeDays[i].waterMl / 1000)),
                      isCurved: true, color: Colors.blue, barWidth: 3, dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: true, color: Colors.blue.withValues(alpha: 0.1)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  FlTitlesData _titles(List<ThirtyDayReportDay> days, {bool isLine = false}) {
    return FlTitlesData(
      show: true,
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (v, _) => Text('${v.toInt()}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.smoke)))),
      bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) {
        final i = v.toInt();
        if (i < 0 || i >= days.length || i % 5 != 0) return const SizedBox.shrink();
        return Text('${days[i].dayOfCycle}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.smoke));
      })),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _ChartCard({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line, width: 1.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.svcHero, size: 18),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.ink)),
            ],
          ),
          const SizedBox(height: 24),
          child,
        ],
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
