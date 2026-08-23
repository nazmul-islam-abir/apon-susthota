// lib/screens/doctor_report_screen.dart
//
// "ডাক্তারের রিপোর্ট" — single screen the user opens just before their
// monthly doctor visit.  Shows:
//   - Cycle hero (Day X / 30, anchor date, days remaining).
//   - Quick totals (meals, water, meds, workouts, avg adherence).
//   - 30 day cards that can be expanded to show every meal / med / workout /
//     water entry for that day.
//   - "PDF / প্রিন্ট" button → preview + share/save.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../models/doctor_report_input.dart';
import '../models/thirty_day_report.dart';
import '../services/report_pdf.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class DoctorReportScreen extends StatefulWidget {
  const DoctorReportScreen({super.key});

  @override
  State<DoctorReportScreen> createState() => _DoctorReportScreenState();
}

class _DoctorReportScreenState extends State<DoctorReportScreen> {
  late Future<_ReportBundle> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ReportBundle> _load() async {
    final report = await SupabaseService.getThirtyDayReport();
    final input = await _resolveIdentity();
    return _ReportBundle(report: report, identity: input);
  }

  Future<DoctorReportInput> _resolveIdentity() async {
    try {
      final profile = await SupabaseService.fetchProfile();
      final user = SupabaseService.currentUser;
      final meta = (user?.userMetadata ?? const {});
      // The base UserProfile model doesn't carry a diabetes_type or doctor_name
      // column yet — those are surfaced via the upcoming clinical v2 surface and
      // a future SQL migration. Until then we resolve diabetes type from the
      // classification and skip doctor name (it shows as "—" in the PDF).
      String? diabetesType;
      try {
        final cls = await SupabaseService.classifyUserV2();
        final t = (cls['tier'] ?? cls['classification'] ?? '').toString();
        if (t.isNotEmpty) diabetesType = _humanizeTier(t);
      } catch (_) {}

      return DoctorReportInput(
        patientName: (profile?.fullName?.isNotEmpty ?? false)
            ? profile!.fullName!
            : (meta['full_name'] as String? ?? 'রোগী'),
        patientAge: profile?.age,
        diabetesType: diabetesType,
        doctorName: meta['doctor_name'] as String?,
        mobile: profile?.mobile ?? meta['mobile'] as String?,
        email: user?.email,
      );
    } catch (_) {
      return DoctorReportInput.guest();
    }
  }

  String _humanizeTier(String t) {
    switch (t.toLowerCase()) {
      case 't1':
      case 'type1':
        return 'টাইপ ১';
      case 't2':
      case 'type2':
        return 'টাইপ ২';
      case 'gdm':
      case 'gestational':
        return 'গর্ভকালীন';
      case 'prediabetes':
      case 'pre':
        return 'প্রি-ডায়াবেটিস';
      default:
        return t;
    }
  }

  void _reload() {
    final next = _load();
    setState(() {
      _future = next;
    });
  }

  Future<void> _openPdf(_ReportBundle bundle) async {
    final bytes = await DoctorReportPdf.build(
      report: bundle.report,
      patientName: bundle.identity.displayNameOrFallback,
      patientAge: bundle.identity.patientAge,
      diabetesType: bundle.identity.diabetesType,
      doctorName: bundle.identity.doctorName,
    );
    final safeName = bundle.identity.displayNameOrFallback
        .replaceAll(RegExp(r'\s+'), '_');
    await Printing.layoutPdf(
      name: 'doctor_report_${safeName}_${bundle.report.cycleStart.toIso8601String().substring(0, 10)}.pdf',
      onLayout: (_) async => bytes,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ডাক্তারের রিপোর্ট'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'রিফ্রেশ',
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<_ReportBundle>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _ErrorState(
              message: snap.error.toString(),
              onRetry: _reload,
            );
          }
          final bundle = snap.data!;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              children: [
                _CycleHero(report: bundle.report, identity: bundle.identity),
                const SizedBox(height: 16),
                _TotalsGrid(report: bundle.report),
                const SizedBox(height: 16),
                _PdfButton(onTap: () => _openPdf(bundle)),
                const SizedBox(height: 20),
                _SectionHeading(
                  title: 'দিন-ভিত্তিক ভাঙ্গা রিপোর্ট',
                  subtitle:
                      'যেকোনো দিনের কার্ডে ট্যাপ করলে সেই দিনের সব লগ দেখা যাবে',
                ),
                const SizedBox(height: 8),
                ..._buildDayCards(bundle),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildDayCards(_ReportBundle bundle) {
    return [
      for (final d in bundle.report.days) _DayCard(day: d),
    ];
  }
}

// ---------------------------------------------------------------------------
// Bundle + identity
// ---------------------------------------------------------------------------

class _ReportBundle {
  final ThirtyDayReport report;
  final DoctorReportInput identity;
  const _ReportBundle({required this.report, required this.identity});
}

// ---------------------------------------------------------------------------
// Cycle hero
// ---------------------------------------------------------------------------

class _CycleHero extends StatelessWidget {
  final ThirtyDayReport report;
  final DoctorReportInput identity;
  const _CycleHero({required this.report, required this.identity});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy', 'en');
    final accent = _adherenceColor(report.totals.avgAdherencePct);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.cyan.withOpacity(0.95),
            AppColors.violet.withOpacity(0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.cyan.withOpacity(0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      identity.displayNameOrFallback,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (identity.patientAge != null) 'বয়স ${identity.patientAge}',
                        if (identity.diabetesType != null &&
                            identity.diabetesType!.isNotEmpty)
                          identity.diabetesType!,
                        if (identity.doctorName != null &&
                            identity.doctorName!.isNotEmpty)
                          'ডাক্তার: ${identity.doctorName}',
                      ].join(' · '),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'দিন ${report.dayOfCycle} / ৩০',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: report.cycleProgress,
              minHeight: 8,
              backgroundColor: Colors.white.withOpacity(0.18),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${df.format(report.cycleStart)}  →  '
                '${df.format(report.cycleStart.add(const Duration(days: 29)))}',
                style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12),
              ),
              Text(
                report.cycleComplete
                    ? 'চক্র সম্পন্ন'
                    : 'আরও ${report.daysRemaining} দিন বাকি',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _HeroStat(
                  label: 'গড় অনুপরতি',
                  value: '${report.totals.avgAdherencePct}%',
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroStat(
                  label: 'সক্রিয় দিন',
                  value: '${report.totals.daysLogged}/৩০',
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _HeroStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Totals grid
// ---------------------------------------------------------------------------

class _TotalsGrid extends StatelessWidget {
  final ThirtyDayReport report;
  const _TotalsGrid({required this.report});

  @override
  Widget build(BuildContext context) {
    final t = report.totals;
    final waterL = (t.waterMlTotal / 1000).toStringAsFixed(1);
    final medPct = (t.medAdherenceRatio * 100).round();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('৩০ দিনের সারাংশ',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _StatTile(
                icon: Icons.restaurant,
                tint: AppColors.mintDeep,
                title: 'খাবার অনুপরতি',
                value: '${t.mealAdherencePct.round()}%',
                sub: '${t.loggedMealsTotal} / ${t.plannedMealsTotal} লগ',
              ),
              _StatTile(
                icon: Icons.local_drink,
                tint: const Color(0xFF1E88E5),
                title: 'মোট পানি',
                value: '$waterL লি',
                sub: 'গড় ${(t.waterMlTotal / 30 / 1000).toStringAsFixed(2)} লি/দিন',
              ),
              _StatTile(
                icon: Icons.medication,
                tint: AppColors.violet,
                title: 'ওষুধ অনুপরতি',
                value: '$medPct%',
                sub: '${t.medTakenTotal} / ${t.medScheduledTotal}',
              ),
              _StatTile(
                icon: Icons.fitness_center,
                tint: AppColors.amber,
                title: 'ব্যায়াম',
                value: '${t.workoutsCompleted}',
                sub: '${t.workoutMinutesTotal} মিনিট মোট',
              ),
              _StatTile(
                icon: Icons.local_fire_department,
                tint: AppColors.rose,
                title: 'মোট ক্যালোরি',
                value: '${t.kcalTotal}',
                sub: 'গড় ${(t.kcalTotal / 30).round()} ক্যাল/দিন',
              ),
              _StatTile(
                icon: Icons.thumb_up_alt,
                tint: _adherenceColor(t.avgAdherencePct),
                title: 'গড় অনুপরতি',
                value: '${t.avgAdherencePct}%',
                sub: t.avgAdherencePct >= 80
                    ? 'চমৎকার!'
                    : (t.avgAdherencePct >= 55 ? 'আরেকটু চেষ্টা' : 'উন্নতি প্রয়োজন'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String title;
  final String value;
  final String sub;
  const _StatTile({
    required this.icon,
    required this.tint,
    required this.title,
    required this.value,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 16 * 2 - 14 * 2 - 10) / 2,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tint.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: tint, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: tint,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(value,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(sub,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Day card (expandable)
// ---------------------------------------------------------------------------

class _DayCard extends StatefulWidget {
  final ThirtyDayReportDay day;
  const _DayCard({required this.day});

  @override
  State<_DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<_DayCard> {
  bool _expanded = false;
  DayFullReport? _detail;
  bool _loadingDetail = false;
  String? _error;

  Future<void> _toggle() async {
    setState(() => _expanded = !_expanded);
    if (_expanded && _detail == null && !widget.day.isFuture) {
      await _fetchDetail();
    }
  }

  Future<void> _fetchDetail() async {
    setState(() {
      _loadingDetail = true;
      _error = null;
    });
    try {
      final d = await SupabaseService.getDayFullReport(date: widget.day.date);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _loadingDetail = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingDetail = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.day;
    final tint = _adherenceColor(d.adherencePct);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _toggle,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tint.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${d.dayOfCycle}',
                        style: TextStyle(
                          color: tint,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'দিন ${d.dayOfCycle}  ·  ${d.bnWeekday}',
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                              if (d.isToday) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.cyan,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'আজ',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                              if (d.isFuture) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.line,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text('আসন্ন',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textMuted)),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            d.dateLabelBn,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${d.adherencePct}%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: tint,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.expand_more, color: AppColors.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _MiniStatsRow(day: d),
                if (_expanded) _ExpandedDetail(
                  loading: _loadingDetail,
                  error: _error,
                  detail: _detail,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniStatsRow extends StatelessWidget {
  final ThirtyDayReportDay day;
  const _MiniStatsRow({required this.day});

  @override
  Widget build(BuildContext context) {
    final d = day;
    return Row(
      children: [
        _miniChip(Icons.restaurant, AppColors.mintDeep,
            '${d.loggedMeals.good + d.loggedMeals.moderate + d.loggedMeals.bad + d.loggedMeals.offplan}/${d.plannedMeals}',
            'খাবার'),
        const SizedBox(width: 6),
        _miniChip(Icons.local_drink, const Color(0xFF1E88E5),
            '${d.waterMl}', 'মিলি'),
        const SizedBox(width: 6),
        _miniChip(Icons.medication, AppColors.violet,
            '${d.medicine.taken}/${d.medicine.scheduled}', 'ওষুধ'),
        const SizedBox(width: 6),
        _miniChip(Icons.fitness_center, AppColors.amber,
            '${d.workouts.doneAny}', 'ব্যায়াম'),
      ],
    );
  }

  Widget _miniChip(IconData icon, Color tint, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: tint.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 12, color: tint),
              const SizedBox(width: 4),
              Text(value,
                  style: TextStyle(
                      color: tint, fontWeight: FontWeight.bold, fontSize: 13)),
            ]),
            Text(label,
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

class _ExpandedDetail extends StatelessWidget {
  final bool loading;
  final String? error;
  final DayFullReport? detail;
  const _ExpandedDetail({
    required this.loading,
    required this.error,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 10),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (error != null)
            _detailRow(Icons.error_outline, AppColors.rose, 'ত্রুটি', error!)
          else if (detail == null)
            const Text('বিস্তারিত পাওয়া যায়নি')
          else ...[
            _macrosBox(detail!),
            const SizedBox(height: 10),
            if (detail!.meals.isNotEmpty) _mealSection(detail!.meals),
            if (detail!.meds.isNotEmpty) _medSection(detail!.meds),
            if (detail!.workouts.isNotEmpty) _workoutSection(detail!.workouts),
            if (detail!.waterLogs.isNotEmpty) _waterSection(detail!.waterLogs),
            if (detail!.meals.isEmpty &&
                detail!.meds.isEmpty &&
                detail!.workouts.isEmpty &&
                detail!.waterLogs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'এই দিনে কোনো লগ নেই',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, Color tint, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: tint, size: 16),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: tint, fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _macrosBox(DayFullReport d) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.cyan.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            _pill('${d.macros.kcal} ক্যাল', 'ক্যালোরি'),
            _pill('${d.macros.carbG} গ্রাম', 'কার্ব'),
            _pill('${d.macros.proteinG} গ্রাম', 'প্রোটিন'),
            _pill('${d.macros.fatG} গ্রাম', 'ফ্যাট'),
            _pill('${d.macros.sodiumMg} মিগ্রা', 'সোডিয়াম'),
          ],
        ),
      );

  Widget _pill(String value, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ],
        ),
      );

  Widget _sectionHeader(String title, IconData icon, Color tint) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Row(
          children: [
            Icon(icon, size: 16, color: tint),
            const SizedBox(width: 6),
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: tint, fontSize: 14)),
          ],
        ),
      );

  Widget _mealSection(List<DayMealRow> meals) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('খাবার (${meals.length})', Icons.restaurant, AppColors.mintDeep),
        for (final m in meals) _mealRow(m),
      ],
    );
  }

  Widget _mealRow(DayMealRow m) {
    Color tint = AppColors.mintDeep;
    if (m.impact == 'bad') tint = AppColors.rose;
    if (m.impact == 'moderate') tint = AppColors.amber;
    if (m.offplan) tint = AppColors.violet;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: tint.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(m.time,
                style: TextStyle(color: tint, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.nameBn.isNotEmpty ? m.nameBn : m.nameEn,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${m.slot} · ${m.impact}'
                  '${m.offplan ? " · অফপ্ল্যান" : ""}'
                  '${m.kcal > 0 ? " · ${m.kcal} ক্যাল" : ""}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
                if (m.note.isNotEmpty)
                  Text(m.note,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textMuted, fontStyle: FontStyle.italic)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _medSection(List<DayMedRow> meds) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('ওষুধ (${meds.length})', Icons.medication, AppColors.violet),
        for (final m in meds) _medRow(m),
      ],
    );
  }

  Widget _medRow(DayMedRow m) {
    final tint = m.status == 'taken'
        ? AppColors.mintDeep
        : (m.status == 'missed' ? AppColors.rose : AppColors.amber);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(Icons.check_circle, size: 14, color: tint),
          const SizedBox(width: 6),
          Text('${m.scheduledAt}',
              style: TextStyle(color: tint, fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              [m.name, if (m.dose.isNotEmpty) m.dose].where((s) => s.isNotEmpty).join(' · '),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (m.takenAt != null)
            Text('নিয়েছেন ${m.takenAt}',
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _workoutSection(List<DayWorkoutRow> workouts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('ব্যায়াম (${workouts.length})', Icons.fitness_center, AppColors.amber),
        for (final w in workouts)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                const Icon(Icons.fitness_center, size: 14, color: AppColors.amber),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(w.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Text('${w.durationMin} মিনিট  ·  ${w.status}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _waterSection(List<DayWaterRow> water) {
    final total = water.fold<int>(0, (sum, w) => sum + w.ml);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('পানি (${water.length} বার, মোট ${total} মিলি)',
            Icons.local_drink, const Color(0xFF1E88E5)),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final w in water)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E88E5).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${w.time} · ${w.ml} মিলি',
                    style: const TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Misc widgets
// ---------------------------------------------------------------------------

class _SectionHeading extends StatelessWidget {
  final String title;
  final String? subtitle;
  const _SectionHeading({required this.title, this.subtitle});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle!,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ],
      ],
    );
  }
}

class _PdfButton extends StatelessWidget {
  final VoidCallback onTap;
  const _PdfButton({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        onPressed: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        icon: const Icon(Icons.picture_as_pdf),
        label: const Text(
          'PDF ডাউনলোড / প্রিন্ট',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.cyan,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
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
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.rose, size: 48),
            const SizedBox(height: 12),
            const Text('রিপোর্ট লোড করা যায়নি',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('আবার চেষ্টা করুন'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Color _adherenceColor(int pct) {
  if (pct >= 80) return AppColors.mintDeep;
  if (pct >= 55) return AppColors.amber;
  return AppColors.rose;
}
