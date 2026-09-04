/// Caretaker charts screen — daily / weekly / monthly adherence
/// views for the connected patient.
///
/// Uses the existing `get_caretaker_daily_breakdown` RPC
/// (already wired in `SupabaseService`). The RPC returns one row
/// per day with meal/med/water/workout ratios, so the same widget
/// tree works for all three segments — only the window size and
/// chart spacing change.
///
/// Three `fl_chart` widgets:
///   1. Meal adherence bar chart   (0..1 ratio)
///   2. Medicine adherence bar     (0..100%)
///   3. Water + workout line chart (dual axis, liters + ratio)
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/patient_data_realtime_mixin.dart';

class CaretakerChartsScreen extends StatefulWidget {
  final String patientUserId;
  final String? patientName;
  const CaretakerChartsScreen({
    super.key,
    required this.patientUserId,
    this.patientName,
  });

  @override
  State<CaretakerChartsScreen> createState() => _CaretakerChartsScreenState();
}

class _CaretakerChartsScreenState extends State<CaretakerChartsScreen>
    with PatientDataRealtimeMixin {
  /// Selected segment: 1 = daily (today only), 7 = weekly, 30 = monthly.
  int _days = 7;

  List<Map<String, dynamic>> _series = const [];
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      // Auto-refresh daily breakdown when the patient logs
      // meal/water/medicine/workout data — pulls new bars & lines
      // without a manual refresh.
      attachPatientDataRealtime(widget.patientUserId, _load);
    });
  }

  @override
  void dispose() {
    disposePatientDataRealtime();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s =
          await SupabaseService.getCaretakerDailyBreakdown(
        patientUserId: widget.patientUserId,
        days: _days,
      );
      if (!mounted) return;
      setState(() {
        _series = s;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _setDays(int days) {
    if (days == _days) return;
    setState(() => _days = days);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.patientName ?? 'রোগী';
    return Scaffold(
      backgroundColor: AppColors.void2,
      appBar: AppBar(
        backgroundColor: AppColors.void2,
        foregroundColor: AppColors.text,
        elevation: 0,
        title: Text(
          '$name — চার্ট',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.violetDeep,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          children: [
            _SegmentSelector(
              selected: _days,
              onChanged: _setDays,
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppColors.violet,
                    strokeWidth: 3,
                  ),
                ),
              )
            else if (_error != null)
              _ErrorBanner(message: 'চার্ট লোড ব্যর্থ: $_error')
            else if (_series.isEmpty)
              const _EmptyState()
            else ...[
              _MealAdherenceCard(series: _series, days: _days),
              const SizedBox(height: 14),
              _MedicineAdherenceCard(series: _series, days: _days),
              const SizedBox(height: 14),
              _WaterWorkoutCard(series: _series, days: _days),
            ],
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Segmented control: দৈনিক / সাপ্তাহিক / মাসিক
// ----------------------------------------------------------------------

class _SegmentSelector extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;
  const _SegmentSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment(
          value: 1,
          label: Text('দৈনিক',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        ButtonSegment(
          value: 7,
          label: Text('সাপ্তাহিক',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        ButtonSegment(
          value: 30,
          label: Text('মাসিক',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
      selected: {selected},
      onSelectionChanged: (s) => onChanged(s.first),
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.violet.withValues(alpha: 0.14);
          }
          return AppColors.surfaceHigh;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.violetDeep;
          }
          return AppColors.textMuted;
        }),
        side: WidgetStatePropertyAll(
          BorderSide(color: AppColors.violet.withValues(alpha: 0.22)),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 13),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Helpers
// ----------------------------------------------------------------------

double _asDouble(Object? v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

/// Parse the SQL `day` field (ISO date string or Date) into a
/// short Bangla weekday label.
String _dayLabel(Object? day, int days) {
  DateTime? d;
  if (day is DateTime) {
    d = day;
  } else if (day is String && day.isNotEmpty) {
    d = DateTime.tryParse(day);
  }
  if (d == null) return '';
  if (days <= 1) {
    return DateFormat('HH:mm', 'bn').format(d.toLocal());
  }
  if (days <= 7) {
    return DateFormat('EEE', 'bn').format(d.toLocal());
  }
  return DateFormat('d MMM', 'bn').format(d.toLocal());
}

/// Average helper that ignores nulls (when SQL returns null for a
/// metric that wasn't tracked that day).
double? _avg(List<double?> values) {
  final filtered = values.whereType<double>().toList();
  if (filtered.isEmpty) return null;
  return filtered.reduce((a, b) => a + b) / filtered.length;
}

/// Build a list of (x, y) spots for a single numeric metric across
/// the breakdown series.
List<FlSpot> _spotsFor(
  List<Map<String, dynamic>> series,
  double Function(Map<String, dynamic>) extract,
) {
  final spots = <FlSpot>[];
  for (var i = 0; i < series.length; i++) {
    final y = extract(series[i]);
    spots.add(FlSpot(i.toDouble(), y));
  }
  return spots;
}

double _extractMealRatio(Map<String, dynamic> row) =>
    (_asDouble(row['meal_ratio']) * 100).clamp(0, 100);

double _extractMedicinePct(Map<String, dynamic> row) =>
    _asDouble(row['medicine_pct']).clamp(0, 100);

double _extractWaterLiters(Map<String, dynamic> row) =>
    _asDouble(row['water_liters']);

double _extractWorkoutRatio(Map<String, dynamic> row) {
  final r = row['workout_ratio'];
  if (r == null) return 0;
  // Workout ratio is in 0..1; scale to 0..100 to share a single
  // y-axis with the water line. (We show this on a secondary
  // axis label.)
  return _asDouble(r) * 100;
}

// ----------------------------------------------------------------------
// Cards
// ----------------------------------------------------------------------

class _MealAdherenceCard extends StatelessWidget {
  final List<Map<String, dynamic>> series;
  final int days;
  const _MealAdherenceCard({required this.series, required this.days});

  @override
  Widget build(BuildContext context) {
    final avg = _avg(series.map(_extractMealRatio).toList());
    return _ChartCard(
      icon: Icons.restaurant_rounded,
      iconColor: AppColors.cyan,
      title: 'খাবার মেনে চলা',
      subtitle: avg == null
          ? 'তথ্য নেই'
          : 'গড় ${avg.toStringAsFixed(0)}% মেনে চলা',
      child: SizedBox(
        height: 180,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: 100,
            barGroups: List.generate(series.length, (i) {
              return BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: _extractMealRatio(series[i]),
                    width: days <= 7 ? 14 : 5,
                    borderRadius: BorderRadius.circular(4),
                    color: AppColors.cyan,
                  ),
                ],
              );
            }),
            titlesData: FlTitlesData(
              show: true,
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 32,
                  interval: 50,
                  getTitlesWidget: (v, _) => Text(
                    '${v.toInt()}%',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textDim,
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  interval: 1,
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i < 0 || i >= series.length) {
                      return const SizedBox.shrink();
                    }
                    // Avoid label collisions: show every label when ≤ 7
                    // days, every 5th day when ≤ 30.
                    if (days > 7 && i % 5 != 0 && i != series.length - 1) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _dayLabel(series[i]['day'], days),
                        style: const TextStyle(
                          fontSize: 9.5,
                          color: AppColors.textDim,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: 50,
              getDrawingHorizontalLine: (v) => FlLine(
                color: AppColors.line.withValues(alpha: 0.6),
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
          ),
        ),
      ),
    );
  }
}

class _MedicineAdherenceCard extends StatelessWidget {
  final List<Map<String, dynamic>> series;
  final int days;
  const _MedicineAdherenceCard({required this.series, required this.days});

  @override
  Widget build(BuildContext context) {
    final avg = _avg(series.map(_extractMedicinePct).toList());
    return _ChartCard(
      icon: Icons.medication_rounded,
      iconColor: AppColors.mintDeep,
      title: 'ওষুধ গ্রহণ',
      subtitle: avg == null
          ? 'তথ্য নেই'
          : 'গড় ${avg.toStringAsFixed(0)}% গৃহীত',
      child: SizedBox(
        height: 180,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: 100,
            barGroups: List.generate(series.length, (i) {
              return BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: _extractMedicinePct(series[i]),
                    width: days <= 7 ? 14 : 5,
                    borderRadius: BorderRadius.circular(4),
                    color: AppColors.mintDeep,
                  ),
                ],
              );
            }),
            titlesData: FlTitlesData(
              show: true,
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 32,
                  interval: 50,
                  getTitlesWidget: (v, _) => Text(
                    '${v.toInt()}%',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textDim,
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  interval: 1,
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i < 0 || i >= series.length) {
                      return const SizedBox.shrink();
                    }
                    if (days > 7 && i % 5 != 0 && i != series.length - 1) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _dayLabel(series[i]['day'], days),
                        style: const TextStyle(
                          fontSize: 9.5,
                          color: AppColors.textDim,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: 50,
              getDrawingHorizontalLine: (v) => FlLine(
                color: AppColors.line.withValues(alpha: 0.6),
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
          ),
        ),
      ),
    );
  }
}

class _WaterWorkoutCard extends StatelessWidget {
  final List<Map<String, dynamic>> series;
  final int days;
  const _WaterWorkoutCard({required this.series, required this.days});

  @override
  Widget build(BuildContext context) {
    final waterAvg = _avg(series.map(_extractWaterLiters).toList());
    final workoutAvg = _avg(series.map(_extractWorkoutRatio).toList());
    return _ChartCard(
      icon: Icons.water_drop_rounded,
      iconColor: AppColors.violetDeep,
      title: 'পানি ও ব্যায়াম',
      subtitle:
          '${waterAvg == null ? '—' : waterAvg.toStringAsFixed(1)} L পানি  •  ${workoutAvg == null ? '—' : workoutAvg.toStringAsFixed(0)}% ব্যায়াম',
      child: SizedBox(
        height: 200,
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: (series.length - 1).toDouble(),
            minY: 0,
            // Workout is scaled 0..100 (same axis as water liters,
            // since both are small numbers — works for this app).
            maxY: 100,
            lineBarsData: [
              LineChartBarData(
                spots: _spotsFor(series, _extractWaterLiters),
                isCurved: true,
                curveSmoothness: 0.25,
                color: AppColors.cyan,
                barWidth: 2.5,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: days <= 7,
                  getDotPainter: (spot, _, __, ___) =>
                      FlDotCirclePainter(
                    radius: 3,
                    color: AppColors.cyan,
                    strokeWidth: 1.5,
                    strokeColor: Colors.white,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppColors.cyan.withValues(alpha: 0.10),
                ),
              ),
              LineChartBarData(
                spots: _spotsFor(series, _extractWorkoutRatio),
                isCurved: true,
                curveSmoothness: 0.25,
                color: AppColors.violetDeep,
                barWidth: 2.5,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: days <= 7,
                  getDotPainter: (spot, _, __, ___) =>
                      FlDotCirclePainter(
                    radius: 3,
                    color: AppColors.violetDeep,
                    strokeWidth: 1.5,
                    strokeColor: Colors.white,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppColors.violet.withValues(alpha: 0.10),
                ),
              ),
            ],
            titlesData: FlTitlesData(
              show: true,
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 36,
                  interval: 25,
                  getTitlesWidget: (v, _) => Text(
                    v.toInt().toString(),
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textDim,
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  interval: 1,
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i < 0 || i >= series.length) {
                      return const SizedBox.shrink();
                    }
                    if (days > 7 && i % 5 != 0 && i != series.length - 1) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _dayLabel(series[i]['day'], days),
                        style: const TextStyle(
                          fontSize: 9.5,
                          color: AppColors.textDim,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: 25,
              getDrawingHorizontalLine: (v) => FlLine(
                color: AppColors.line.withValues(alpha: 0.6),
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Shared chrome
// ----------------------------------------------------------------------

class _ChartCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget child;
  const _ChartCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 17, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.show_chart_rounded,
            size: 56,
            color: AppColors.textDim.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 10),
          const Text(
            'এই সময়ের জন্য কোনো তথ্য নেই',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.rose.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.rose.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.rose, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.text,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
