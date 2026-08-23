/// Analytics screen — single-screen 30-day cycle view.
///
/// Replaces the old 7-day body with a unified cycle anchored on
/// `auth.users.created_at`. Day 1 = signup day. After day 30 the cycle
/// continues rolling forward so the user always has a full overview of
/// their adherence and a Doctor Report banner at the top for monthly
/// visits.
library;

import 'package:flutter/material.dart';

import '../models/thirty_day_report.dart';
import '../services/app_events.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';
import 'doctor_report_screen.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  late Future<_AnalyticsData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    AppEvents.profileChanged.addListener(_onChanged);
    AppEvents.mealLogged.addListener(_onChanged);
    AppEvents.medicineChanged.addListener(_onChanged);
    AppEvents.workoutChanged.addListener(_onChanged);
    AppEvents.waterChanged.addListener(_onChanged);
  }

  @override
  void dispose() {
    AppEvents.profileChanged.removeListener(_onChanged);
    AppEvents.mealLogged.removeListener(_onChanged);
    AppEvents.medicineChanged.removeListener(_onChanged);
    AppEvents.workoutChanged.removeListener(_onChanged);
    AppEvents.waterChanged.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    final newFuture = _load();
    setState(() => _future = newFuture);
  }

  Future<_AnalyticsData> _load() async {
    final report = await SupabaseService.getThirtyDayReport();
    return _AnalyticsData(report: report);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: FutureBuilder<_AnalyticsData>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: LoadingMark());
            }
            if (snap.hasError) {
              return _ErrorState(message: snap.error.toString(), onRetry: _onChanged);
            }
            final d = snap.data!;
            return RefreshIndicator(
              color: AppColors.ink,
              backgroundColor: AppColors.paper,
              onRefresh: () async => _onChanged(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                children: [
                  _Header(report: d.report),
                  const SizedBox(height: AppSpacing.lg),
                  _CycleHero(report: d.report),
                  const SizedBox(height: AppSpacing.lg),
                  _DoctorReportBanner(report: d.report),
                  const SizedBox(height: AppSpacing.lg),
                  _TotalsGrid(report: d.report),
                  const SizedBox(height: AppSpacing.lg),
                  _CycleInsights(report: d.report),
                  const SizedBox(height: AppSpacing.lg),
                  _DaysList(report: d.report),
                  const SizedBox(height: AppSpacing.xxl),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AnalyticsData {
  final ThirtyDayReport report;
  _AnalyticsData({required this.report});
}
// Header + cycle hero
class _Header extends StatelessWidget {
  final ThirtyDayReport report;
  const _Header({required this.report});

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final today = DateTime.now();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Overline(_dateLabel(today)),
              const SizedBox(height: 6),
              Text(
                'বিশ্লেষণ',
                style: t.text.display.copyWith(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: t.colors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                report.cycleRangeLabel,
                style: t.text.body.copyWith(
                  color: t.colors.ink.withValues(alpha: .66),
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        MonoButton(
          label: 'রিফ্রেশ',
          leading: Icons.refresh_rounded,
          onPressed: () => AppEvents.notifyProfileChanged(),
        ),
      ],
    );
  }

  String _dateLabel(DateTime d) {
    const days = ['রোব', 'সোম', 'মঙ্গল', 'বুধ', 'বৃহ', 'শুক্র', 'শনি'];
    const months = [
      'জানু', 'ফেব্রু', 'মার্চ', 'এপ্রি', 'মে', 'জুন',
      'জুলা', 'আগ', 'সেপ্ট', 'অক্টো', 'নভে', 'ডিসে',
    ];
    return '${days[d.weekday - 1]} • ${d.day} ${months[d.month - 1]}';
  }
}

class _CycleHero extends StatelessWidget {
  final ThirtyDayReport report;
  const _CycleHero({required this.report});

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final progress = report.cycleProgress;
    final color = _cycleColor(report.dayOfCycle);
    return MonoCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: Icon(Icons.timeline_rounded,
                      color: Colors.white, size: 28),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'দিন ${report.dayOfCycle} / ৩০',
                      style: t.text.display.copyWith(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: t.colors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${report.totals.avgAdherencePct.toStringAsFixed(0)}% সামগ্রিক অনুগমন',
                      style: t.text.body.copyWith(
                        color: t.colors.ink.withValues(alpha: .66),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (report.cycleComplete)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.mintDeep.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          size: 14, color: AppColors.mintDeep),
                      const SizedBox(width: 4),
                      const Text(
                        'চক্র সম্পন্ন',
                        style: TextStyle(
                          color: AppColors.mintDeep,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Text(
                  '${report.daysRemaining} দিন বাকি',
                  style: t.text.body.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: t.colors.ink.withValues(alpha: 0.06),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'শুরু: ${_shortDate(report.cycleStart)}',
                  style: t.text.body.copyWith(
                    color: t.colors.ink.withValues(alpha: 0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                'আজ: ${_shortDate(report.today)}',
                style: t.text.body.copyWith(
                  color: t.colors.ink.withValues(alpha: 0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _cycleColor(int day) {
    if (day >= 25) return AppColors.mintDeep;
    if (day >= 10) return AppColors.cyan;
    return AppColors.violet;
  }

  String _shortDate(DateTime d) {
    const months = [
      'জানু', 'ফেব্রু', 'মার্চ', 'এপ্রি', 'মে', 'জুন',
      'জুলা', 'আগ', 'সেপ্ট', 'অক্টো', 'নভে', 'ডিসে',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}
// Doctor report banner + totals grid
class _DoctorReportBanner extends StatelessWidget {
  final ThirtyDayReport report;
  const _DoctorReportBanner({required this.report});

  @override
  Widget build(BuildContext context) {
    final pct = report.totals.avgAdherencePct.toStringAsFixed(0);
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.violet, AppColors.cyan],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.violet.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DoctorReportScreen()),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.assignment_rounded,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ডাক্তারের রিপোর্ট',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '৩০ দিনের সারসংক্ষেপ ও PDF ডাউনলোড',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _Pill(text: '$pct% অনুগমন'),
                          const SizedBox(width: 6),
                          _Pill(text: '${report.days.length} দিন'),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  const _Pill({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _TotalsGrid extends StatelessWidget {
  final ThirtyDayReport report;
  const _TotalsGrid({required this.report});

  @override
  Widget build(BuildContext context) {
    final t = report.totals;
    final cards = <_StatTile>[
      _StatTile(
        title: 'খাবার',
        value: '${t.loggedMealsTotal}/${t.plannedMealsTotal}',
        sub: 'আইটেম',
        icon: Icons.restaurant_menu_rounded,
        color: AppColors.cyan,
      ),
      _StatTile(
        title: 'ওষুধ',
        value: '${t.medTakenTotal}/${t.medScheduledTotal}',
        sub: 'ডোজ',
        icon: Icons.medication_rounded,
        color: AppColors.violet,
      ),
      _StatTile(
        title: 'ব্যায়াম',
        value: '${t.workoutsCompleted}/${t.workoutMinutesTotal}',
        sub: 'সেশন',
        icon: Icons.fitness_center_rounded,
        color: AppColors.mintDeep,
      ),
      _StatTile(
        title: 'পানি',
        value: '${t.waterLitres.toStringAsFixed(1)}L',
        sub: 'মোট',
        icon: Icons.water_drop_rounded,
        color: const Color(0xFF0284C7),
      ),
      _StatTile(
        title: 'ক্যালোরি',
        value: t.kcalTotal.toString(),
        sub: 'গড় ${t.kcalAvg.toStringAsFixed(0)}/দিন',
        icon: Icons.local_fire_department_rounded,
        color: AppColors.rose,
      ),
      _StatTile(
        title: 'লগকৃত দিন',
        value: '${t.daysLogged}/${t.daysExpected}',
        sub: 'দিন',
        icon: Icons.event_available_rounded,
        color: AppColors.amber,
      ),
    ];
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > 480;
      if (wide) {
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final card in cards)
              SizedBox(width: (c.maxWidth - AppSpacing.md) / 2, child: card),
          ],
        );
      }
      return Column(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            cards[i],
            if (i != cards.length - 1) const SizedBox(height: AppSpacing.md),
          ],
        ],
      );
    });
  }
}

class _StatTile extends StatelessWidget {
  final String title;
  final String value;
  final String sub;
  final IconData icon;
  final Color color;
  const _StatTile({
    required this.title,
    required this.value,
    required this.sub,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return MonoCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: color,
                height: 1.0,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
// Cycle insights + distribution
class _CycleInsights extends StatelessWidget {
  final ThirtyDayReport report;
  const _CycleInsights({required this.report});

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final breakdown = report.totals.breakdown;
    final good = breakdown.good;
    final mid = breakdown.moderate;
    final bad = breakdown.bad;
    final total = (good + mid + bad).clamp(1, 9999);
    return MonoCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'চক্রের ছবি',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          const SizedBox(height: 14),
          _DistributionBar(good: good, mid: mid, bad: bad),
          const SizedBox(height: 14),
          Row(
            children: [
              _LegendChip(
                label: 'ভালো',
                count: good,
                color: AppColors.mintDeep,
                pct: (good / total * 100).round(),
              ),
              const SizedBox(width: 8),
              _LegendChip(
                label: 'মাঝারি',
                count: mid,
                color: AppColors.amber,
                pct: (mid / total * 100).round(),
              ),
              const SizedBox(width: 8),
              _LegendChip(
                label: 'খারাপ',
                count: bad,
                color: AppColors.rose,
                pct: (bad / total * 100).round(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.colors.ink.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    color: t.colors.ink.withValues(alpha: 0.6), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    report.cycleComplete
                        ? 'এই চক্র সম্পন্ন হয়েছে। পরবর্তী ৩০ দিনের জন্য নতুন লক্ষ্য স্থির করুন।'
                        : 'দিন ${report.dayOfCycle} চলছে — প্রতিদিন খাবার/ওষুধ/ব্যায়াম টিক দিয়ে রিপোর্ট পূর্ণ করুন।',
                    style: TextStyle(
                      fontSize: 13,
                      color: t.colors.ink.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w600,
                      height: 1.4,
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
}

class _DistributionBar extends StatelessWidget {
  final int good;
  final int mid;
  final int bad;
  const _DistributionBar(
      {required this.good, required this.mid, required this.bad});

  @override
  Widget build(BuildContext context) {
    final total = (good + mid + bad).clamp(1, 9999);
    final goodFrac = good / total;
    final midFrac = mid / total;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 14,
        child: Row(
          children: [
            if (goodFrac > 0)
              Expanded(
                flex: (goodFrac * 1000).round(),
                child: Container(color: AppColors.mintDeep),
              ),
            if (midFrac > 0)
              Expanded(
                flex: (midFrac * 1000).round(),
                child: Container(color: AppColors.amber),
              ),
            if ((1 - goodFrac - midFrac) > 0)
              Expanded(
                flex: ((1 - goodFrac - midFrac) * 1000).round(),
                child: Container(color: AppColors.rose),
              ),
          ],
        ),
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final int pct;
  const _LegendChip({
    required this.label,
    required this.count,
    required this.color,
    required this.pct,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$count দিন',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            Text(
              '$pct%',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// Days list + day card
class _DaysList extends StatelessWidget {
  final ThirtyDayReport report;
  const _DaysList({required this.report});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              const Icon(Icons.calendar_view_month_rounded,
                  color: AppColors.cyanDeep, size: 18),
              const SizedBox(width: 8),
              const Text(
                'দিন-ভিত্তিক বিবরণ',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                '${report.days.length} দিন',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ...report.days.asMap().entries.map((e) {
          final i = e.key;
          final day = e.value;
          return Padding(
            padding: EdgeInsets.only(
                bottom: i == report.days.length - 1 ? 0 : AppSpacing.md),
            child: _DayCard(day: day, dayOfCycle: i + 1),
          );
        }),
      ],
    );
  }
}

class _DayCard extends StatefulWidget {
  final ThirtyDayReportDay day;
  final int dayOfCycle;
  const _DayCard({required this.day, required this.dayOfCycle});

  @override
  State<_DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<_DayCard> {
  bool _open = false;
  DayFullReport? _detail;
  bool _loading = false;
  String? _err;

  Future<void> _toggle() async {
    setState(() => _open = !_open);
    if (_open && _detail == null) {
      setState(() {
        _loading = true;
        _err = null;
      });
      try {
        final r = await SupabaseService
            .getDayFullReport(date: widget.day.date);
        if (mounted) {
          setState(() {
            _detail = r;
            _loading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _err = e.toString();
            _loading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.day;
    final isToday = _sameDay(d.date, DateTime.now());
    final isFuture = d.date.isAfter(DateTime.now());
    final color = _qualityColor(d.adherencePct);
    return MonoCard(
      padding: const EdgeInsets.all(0),
      onTap: isFuture ? null : _toggle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _DayBadge(date: d.date, dayOfCycle: widget.dayOfCycle),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              d.dateLabelBn,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (isToday) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.cyan.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'আজ',
                                style: TextStyle(
                                  color: AppColors.cyanDeep,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                          if (isFuture) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.amber.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'ভবিষ্যৎ',
                                style: TextStyle(
                                  color: AppColors.amber,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        d.summaryBn,
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _MiniStats(day: d, color: color),
                SizedBox(width: 4),
                if (!isFuture)
                  Icon(
                    _open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textMuted,
                  ),
              ],
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _ExpandedDetail(
                loading: _loading,
                detail: _detail,
                err: _err,
                day: d,
                onRetry: () {
                  setState(() {
                    _detail = null;
                  });
                  _toggle();
                },
              ),
            ),
        ],
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Color _qualityColor(int q) {
    if (q >= 70) return AppColors.mintDeep;
    if (q >= 40) return AppColors.amber;
    return AppColors.rose;
  }
}

class _DayBadge extends StatelessWidget {
  final DateTime date;
  final int dayOfCycle;
  const _DayBadge({required this.date, required this.dayOfCycle});

  @override
  Widget build(BuildContext context) {
    const months = [
      'জানু', 'ফেব্রু', 'মার্চ', 'এপ্রি', 'মে', 'জুন',
      'জুলা', 'আগ', 'সেপ্ট', 'অক্টো', 'নভে', 'ডিসে',
    ];
    return Container(
      width: 56,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cyan.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.cyan.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            '${date.day}',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppColors.cyanDeep,
              height: 1.0,
            ),
          ),
          Text(
            months[date.month - 1],
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.cyanDeep,
            ),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.cyanDeep,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'D$dayOfCycle',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStats extends StatelessWidget {
  final ThirtyDayReportDay day;
  final Color color;
  const _MiniStats({required this.day, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${day.adherencePct}',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${day.loggedMeals.total}/${day.plannedMeals}',
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
// Expanded detail
class _ExpandedDetail extends StatelessWidget {
  final bool loading;
  final DayFullReport? detail;
  final String? err;
  final ThirtyDayReportDay day;
  final VoidCallback onRetry;

  const _ExpandedDetail({
    required this.loading,
    required this.detail,
    required this.err,
    required this.day,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }
    if (err != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: MonoCard(
          padding: const EdgeInsets.all(12),
          background: AppColors.rose.withValues(alpha: 0.08),
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppColors.rose, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'বিবরণ লোড হয়নি',
                  style: TextStyle(
                    color: AppColors.rose,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              MonoButton(
                label: 'আবার',
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                onPressed: onRetry,
              ),
            ],
          ),
        ),
      );
    }
    final d = detail;
    if (d == null) {
      return const SizedBox.shrink();
    }
    final macros = d.macros;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 1,
          color: AppColors.line.withValues(alpha: 0.6),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _MacroChip(
              icon: Icons.local_fire_department_rounded,
              label: 'ক্যাল',
              value: '${macros.kcal.toStringAsFixed(0)}',
              color: AppColors.rose,
            ),
            _MacroChip(
              icon: Icons.bakery_dining_rounded,
              label: 'কার্ব',
              value: '${macros.carbG.toStringAsFixed(0)}গ্রা',
              color: AppColors.amber,
            ),
            _MacroChip(
              icon: Icons.set_meal_rounded,
              label: 'প্রো',
              value: '${macros.proteinG.toStringAsFixed(0)}গ্রা',
              color: AppColors.mintDeep,
            ),
            _MacroChip(
              icon: Icons.opacity_rounded,
              label: 'ফ্যাট',
              value: '${macros.fatG.toStringAsFixed(0)}গ্রা',
              color: AppColors.violet,
            ),
            _MacroChip(
              icon: Icons.grain_rounded,
              label: 'সোডিয়াম',
              value: '${macros.sodiumMg.toStringAsFixed(0)}মিগ্রা',
              color: AppColors.cyanDeep,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _DetailSection(
          title: 'খাবার',
          icon: Icons.restaurant_menu_rounded,
          accent: AppColors.cyanDeep,
          count: d.meals.length,
          emptyText: 'কোনো খাবার লগ নেই',
          child: Column(
            children: [
              for (final m in d.meals)
                _MealLine(row: m, score: day.adherencePct),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _DetailSection(
          title: 'ওষুধ',
          icon: Icons.medication_rounded,
          accent: AppColors.violet,
          count: d.meds.length,
          emptyText: 'কোনো ওষুধ নেই',
          child: Column(
            children: [
              for (final m in d.meds)
                _MedLine(row: m),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _DetailSection(
          title: 'পানি',
          icon: Icons.water_drop_rounded,
          accent: const Color(0xFF0284C7),
          count: d.waterLogs.length,
          emptyText: 'পানির লগ নেই',
          child: Column(
            children: [
              for (final w in d.waterLogs)
                _WaterLine(row: w),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _DetailSection(
          title: 'ব্যায়াম',
          icon: Icons.fitness_center_rounded,
          accent: AppColors.mintDeep,
          count: d.workouts.length,
          emptyText: 'কোনো ব্যায়াম নেই',
          child: Column(
            children: [
              for (final w in d.workouts)
                _WorkoutLine(row: w),
            ],
          ),
        ),
      ],
    );
  }
}

class _MacroChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _MacroChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          SizedBox(width: 4),
          Text(
            '$label $value',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final int count;
  final String emptyText;
  final Widget child;
  const _DetailSection({
    required this.title,
    required this.icon,
    required this.accent,
    required this.count,
    required this.emptyText,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(







      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: accent),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (count == 0)
          _EmptyLine(text: emptyText)
        else
          child,
      ],
    );
  }
}

class _EmptyLine extends StatelessWidget {
  final String text;
  const _EmptyLine({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 13,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MealLine extends StatelessWidget {
  final DayMealRow row;
  final int score;
  const _MealLine({required this.row, required this.score});

  @override
  Widget build(BuildContext context) {
    final color = row.impact == 'good'
        ? AppColors.mintDeep
        : row.impact == 'bad'
            ? AppColors.rose
            : AppColors.amber;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.nameBn,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (row.note.isNotEmpty)
                  Text(
                    row.note,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              row.impact,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MedLine extends StatelessWidget {
  final DayMedRow row;
  const _MedLine({required this.row});

  @override
  Widget build(BuildContext context) {
    final taken = (row.status == 'taken');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            taken
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 16,
            color: taken ? AppColors.mintDeep : AppColors.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              row.name,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (row.scheduledAt.isNotEmpty)
            Text(
              row.scheduledAt,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

class _WaterLine extends StatelessWidget {
  final DayWaterRow row;
  const _WaterLine({required this.row});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.water_drop_outlined,
              size: 16, color: Color(0xFF0284C7)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${row.ml} মিলি',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (row.time.isNotEmpty)
            Text(
              row.time,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

class _WorkoutLine extends StatelessWidget {
  final DayWorkoutRow row;
  const _WorkoutLine({required this.row});

  @override
  Widget build(BuildContext context) {
    final done = (row.status == 'completed');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            done
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 16,
            color: done ? AppColors.mintDeep : AppColors.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              row.name,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (row.durationMin > 0)
            Text(
              '${row.durationMin} মিনিট',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
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
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 56, color: AppColors.textMuted),
            const SizedBox(height: 16),
            const Text(
              'বিশ্লেষণ লোড হয়নি',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            MonoButton(
              label: 'আবার চেষ্টা',
              leading: Icons.refresh_rounded,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
