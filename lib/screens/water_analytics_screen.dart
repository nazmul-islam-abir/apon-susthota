/// Professional analytics for the water-tracking screen.
///
/// Reads `SupabaseService.getWaterAnalytics()` and renders:
///
///   • Hero "verdict" card with Bengali coaching copy based on
///     `WaterAnalyticsSummary.verdict()`.
///   • 7-day bar chart (glasses vs. target line).
///   • Bucket-distribution stacked bar (সকাল/দুপুর/বিকেল/রাত).
///   • Streak + consistency chips.
///   • Day-by-day scrollable breakdown.
///
/// The screen is read-only (no editing) and pulls to refresh.
library;

import 'package:flutter/material.dart';

import '../models/water_analytics.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class WaterAnalyticsScreen extends StatefulWidget {
  const WaterAnalyticsScreen({super.key, this.days = 7});

  final int days;

  @override
  State<WaterAnalyticsScreen> createState() => _WaterAnalyticsScreenState();
}

class _WaterAnalyticsScreenState extends State<WaterAnalyticsScreen> {
  late Future<WaterAnalyticsSummary> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<WaterAnalyticsSummary> _load() {
    return SupabaseService.getWaterAnalytics(days: widget.days);
  }

  Future<void> _refresh() async {
    final next = await _load();
    if (!mounted) return;
    setState(() => _future = Future.value(next));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('পানির বিশ্লেষণ'),
        backgroundColor: AppColors.cyan,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        color: AppColors.cyan,
        onRefresh: _refresh,
        child: FutureBuilder<WaterAnalyticsSummary>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  const Center(
                    child: Icon(Icons.cloud_off, size: 56, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      'বিশ্লেষণ লোড হয়নি: ${snap.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: () => setState(() => _future = _load()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('আবার চেষ্টা করুন'),
                    ),
                  ),
                ],
              );
            }
            final summary = snap.data ?? WaterAnalyticsSummary.empty;
            if (summary.isEmpty) {
              return _emptyState(context);
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              children: [
                _verdictCard(summary),
                const SizedBox(height: 16),
                _summaryRow(summary),
                const SizedBox(height: 16),
                _streakRow(summary),
                const SizedBox(height: 16),
                _section(
                  title: 'গত ${widget.days} দিনের গ্লাস',
                  child: _weeklyChart(summary),
                ),
                const SizedBox(height: 16),
                _section(
                  title: 'সময় অনুযায়ী বণ্টন',
                  child: _bucketBreakdown(summary),
                ),
                const SizedBox(height: 16),
                _section(
                  title: 'দিন অনুযায়ী',
                  child: _dayList(summary),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return ListView(
      children: const [
        SizedBox(height: 140),
        Icon(Icons.water_drop_outlined, size: 64, color: Colors.grey),
        SizedBox(height: 12),
        Center(
          child: Text(
            'এখনও কোনো পানির হিসাব নেই।\nআজ এক গ্লাস পানি যোগ করে শুরু করুন।',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, height: 1.4),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Cards
  // ---------------------------------------------------------------------------

  Widget _verdictCard(WaterAnalyticsSummary s) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.cyan, AppColors.cyan.withOpacity(0.78)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'আজকের পানির রিপোর্ট',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            s.verdict(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.local_fire_department,
                  color: Colors.white, size: 20),
              const SizedBox(width: 6),
              Text(
                '${s.streakDays} দিনের ধারা',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 16),
              const Icon(Icons.emoji_events,
                  color: Colors.white, size: 20),
              const SizedBox(width: 6),
              Text(
                'লক্ষ্য পূরণ ${s.daysHitTarget}/${s.days.length} দিন',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(WaterAnalyticsSummary s) {
    return Row(
      children: [
        Expanded(child: _metricTile('মোট গ্লাস', '${s.totalGlasses}', '🫗')),
        const SizedBox(width: 12),
        Expanded(child: _metricTile('মোট লিটার', s.totalLiters.toStringAsFixed(1), '💧')),
        const SizedBox(width: 12),
        Expanded(child: _metricTile('গড়/দিন', s.avgLiters.toStringAsFixed(1), '📊')),
      ],
    );
  }

  Widget _streakRow(WaterAnalyticsSummary s) {
    return Row(
      children: [
        Expanded(
          child: _metricTile(
            'ধারা',
            '${s.streakDays} দিন',
            '🔥',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _metricTile(
            'ধারাবাহিকতা',
            '${s.consistencyPct.toStringAsFixed(0)}%',
            '🎯',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _metricTile(
            'দৈনিক লক্ষ্য',
            '${s.targetLiters.toStringAsFixed(1)} L',
            '⚖️',
          ),
        ),
      ],
    );
  }

  Widget _metricTile(String label, String value, String emoji) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          padding: const EdgeInsets.all(14),
          child: child,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Charts
  // ---------------------------------------------------------------------------

  Widget _weeklyChart(WaterAnalyticsSummary s) {
    final days = s.days;
    if (days.isEmpty) {
      return const Text('কোনো দিনের তথ্য নেই।');
    }
    final maxGlasses = days
        .map((d) => d.glasses)
        .fold<int>(0, (a, b) => a > b ? a : b)
        .clamp(1, 999);
    final targetGlasses = (s.targetLiters / 0.25).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _legendDot(AppColors.cyan, 'গ্লাস'),
            const SizedBox(width: 12),
            _legendDot(Colors.orange, 'লক্ষ্য ($targetGlasses)'),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 160,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final d in days) ...[
                Expanded(child: _barColumn(d, maxGlasses, targetGlasses)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _barColumn(WaterDayStat d, int maxGlasses, int targetGlasses) {
    final ratio = (d.glasses / maxGlasses).clamp(0.0, 1.0);
    final hit = d.targetHit;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            '${d.glasses}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: hit ? AppColors.cyan : Colors.black54,
            ),
          ),
          const SizedBox(height: 4),
          Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Container(
                width: double.infinity,
                height: 100 * ratio,
                decoration: BoxDecoration(
                  color: hit ? AppColors.cyan : AppColors.cyan.withOpacity(0.45),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ),
              if (targetGlasses > 0)
                Positioned(
                  bottom: 100 * (targetGlasses / maxGlasses).clamp(0.0, 1.0),
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 1.5,
                    color: Colors.orange,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _shortDay(d.date),
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _bucketBreakdown(WaterAnalyticsSummary s) {
    final totals = s.bucketTotals;
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final max = entries.fold<int>(0, (a, e) => a > e.value ? a : e.value);
    if (max == 0) {
      return const Text('এই সপ্তাহে কোনো বণ্টন নেই।');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in entries) ...[
          _bucketRow(WaterDayStat.bucketBn(e.key), e.value, max, _bucketColor(e.key)),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _bucketRow(String label, int value, int max, Color color) {
    final pct = max == 0 ? 0.0 : value / max;
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 10,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 36,
          child: Text(
            '$value',
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _dayList(WaterAnalyticsSummary s) {
    final days = s.days.reversed.toList();
    return Column(
      children: [
        for (var i = 0; i < days.length; i++) ...[
          _dayRow(days[i]),
          if (i < days.length - 1) const Divider(height: 16),
        ],
      ],
    );
  }

  Widget _dayRow(WaterDayStat d) {
    final bd = d.bucketDistribution;
    final active = bd.values.where((v) => v > 0).length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: d.targetHit
                  ? AppColors.cyan.withOpacity(0.15)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              d.targetHit ? Icons.check_circle : Icons.water_drop_outlined,
              color: d.targetHit ? AppColors.cyan : Colors.grey,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _prettyDate(d.date),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '$active টাইম বাকেটে · ${d.liters.toStringAsFixed(1)} L',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Text(
            '${d.glasses} গ্লাস',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Color _bucketColor(String key) {
    switch (key) {
      case 'morning':
        return Colors.amber.shade600;
      case 'noon':
        return Colors.orange.shade600;
      case 'afternoon':
        return Colors.blue.shade600;
      case 'night':
        return Colors.indigo.shade600;
      default:
        return Colors.grey;
    }
  }

  String _shortDay(String iso) {
    try {
      final d = DateTime.parse(iso);
      const bn = ['সোম', 'মঙ্গল', 'বুধ', 'বৃহ', 'শুক্র', 'শনি', 'রবি'];
      // ISO weekday: Mon=1..Sun=7
      return bn[(d.weekday - 1) % 7];
    } catch (_) {
      return iso.substring(5);
    }
  }

  String _prettyDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      const bn = [
        'সোমবার',
        'মঙ্গলবার',
        'বুধবার',
        'বৃহস্পতিবার',
        'শুক্রবার',
        'শনিবার',
        'রবিবার'
      ];
      const months = [
        'জানুয়ারি',
        'ফেব্রুয়ারি',
        'মার্চ',
        'এপ্রিল',
        'মে',
        'জুন',
        'জুলাই',
        'আগস্ট',
        'সেপ্টেম্বর',
        'অক্টোবর',
        'নভেম্বর',
        'ডিসেম্বর',
      ];
      return '${d.day} ${months[d.month - 1]}, ${bn[d.weekday - 1]}';
    } catch (_) {
      return iso;
    }
  }
}