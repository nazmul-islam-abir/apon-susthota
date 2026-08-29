// lib/screens/doctor_report_screen.dart
//
// "ডাক্তারের রিপোর্ট" — overhauled (v5) to match the Nexora technical aesthetic.
// Professional forest-green hero, sharp corners (Radius 0), and technical grids.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../models/doctor_report_input.dart';
import '../models/thirty_day_report.dart';
import '../services/report_pdf.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';

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
    if (report == null) {
      throw StateError('ডেটা পাওয়া যায়নি — পরে আবার চেষ্টা করুন।');
    }
    final input = await _resolveIdentity();
    return _ReportBundle(report: report, identity: input);
  }

  Future<DoctorReportInput> _resolveIdentity() async {
    try {
      final profile = await SupabaseService.fetchProfile();
      final user = SupabaseService.currentUser;
      final meta = (user?.userMetadata ?? const {});
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
      case 'type1': return 'টাইপ ১';
      case 't2':
      case 'type2': return 'টাইপ ২';
      case 'gdm':
      case 'gestational': return 'গর্ভকালীন';
      case 'prediabetes':
      case 'pre': return 'প্রি-ডায়াবেটিস';
      default: return t;
    }
  }

  void _reload() {
    setState(() { _future = _load(); });
  }

  Future<void> _openPdf(_ReportBundle bundle) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: LoadingMark(size: 40)),
    );

    try {
      final bytes = await DoctorReportPdf.build(
        report: bundle.report,
        patientName: bundle.identity.displayNameOrFallback,
        patientAge: bundle.identity.patientAge,
        diabetesType: bundle.identity.diabetesType,
        doctorName: bundle.identity.doctorName,
      );
      
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      final safeName = bundle.identity.displayNameOrFallback.replaceAll(RegExp(r'\s+'), '_');
      await Printing.layoutPdf(
        name: 'doctor_report_${safeName}_${bundle.report.cycleStart.toIso8601String().substring(0, 10)}.pdf',
        onLayout: (_) async => bytes,
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF তৈরি করতে সমস্যা হয়েছে: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.svcCategoryBg,
      body: FutureBuilder<_ReportBundle>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: LoadingMark());
          }
          if (snap.hasError) {
            return _ErrorState(message: snap.error.toString(), onRetry: _reload);
          }
          final bundle = snap.data!;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            color: AppColors.svcHero,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              slivers: [
                _HeaderSliver(report: bundle.report, identity: bundle.identity, onReload: _reload),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _TotalsSection(report: bundle.report),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _PdfDownloadBanner(onTap: () => _openPdf(bundle)),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
                SliverToBoxAdapter(
                  child: _SectionLabel(title: 'দিন-ভিত্তিক ভাঙ্গা রিপোর্ট', sub: 'প্রতিটি দিনের বিস্তারিত রেকর্ড'),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _DayCard(day: bundle.report.days[i]),
                      childCount: bundle.report.days.length,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ReportBundle {
  final ThirtyDayReport report;
  final DoctorReportInput identity;
  const _ReportBundle({required this.report, required this.identity});
}

// ─────────────────────────────────────────────────────────────────────────
// UI COMPONENTS
// ─────────────────────────────────────────────────────────────────────────

class _HeaderSliver extends StatelessWidget {
  final ThirtyDayReport report;
  final DoctorReportInput identity;
  final VoidCallback onReload;
  const _HeaderSliver({required this.report, required this.identity, required this.onReload});

  @override
  Widget build(BuildContext context) {
    const url = 'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/app/photo-1564352969906-8b7f46ba4b8b.avif?token=eyJraWQiOiJhZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJhcHAvcGhvdG8tMTU2NDM1Mjk2OTkwNi04YjdmNDZiYTRiOGIuYXZpZiIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODc4Njg2MjksImV4cCI6MTgxOTQwNDYyOX0.Jdl-6cqT6wHh_nv8j-7oD3zjU2KcoR4e5ohJVnZgTNs';
    final df = DateFormat('d MMM yyyy', 'en');

    return SliverToBoxAdapter(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.svcHero,
          image: const DecorationImage(image: NetworkImage(url), fit: BoxFit.cover, opacity: 0.75),
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
                        IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context)),
                        const Expanded(child: Text('ডাক্তারের রিপোর্ট', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900))),
                        IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 24), onPressed: onReload),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(identity.displayNameOrFallback, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                                const SizedBox(height: 4),
                                Text(
                                  [
                                    if (identity.patientAge != null) 'বয়স: ${identity.patientAge}',
                                    if (identity.diabetesType != null) identity.diabetesType!,
                                  ].join(' · '),
                                  style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.zero, border: Border.all(color: Colors.white24)),
                            child: Text('দিন ${report.dayOfCycle} / ৩০', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      ClipRRect(
                        borderRadius: BorderRadius.zero,
                        child: LinearProgressIndicator(
                          value: report.cycleProgress,
                          minHeight: 10,
                          backgroundColor: Colors.white10,
                          valueColor: const AlwaysStoppedAnimation(AppColors.svcHeroAccent),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${df.format(report.cycleStart)} → ${df.format(report.cycleStart.add(const Duration(days: 29)))}', style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w700)),
                          Text(report.cycleComplete ? 'চক্র সম্পন্ন' : 'আরও ${report.daysRemaining} দিন বাকি', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
                        ],
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

class _TotalsSection extends StatelessWidget {
  final ThirtyDayReport report;
  const _TotalsSection({required this.report});

  @override
  Widget build(BuildContext context) {
    final t = report.totals;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('৩০ দিনের সামগ্রিক সারাংশ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.ink)),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.4,
          children: [
            _TechnicalStat(title: 'গড় অনুপরতি', value: '${t.avgAdherencePct.clamp(0, 100)}%', icon: Icons.auto_graph_rounded, color: _adherenceColor(t.avgAdherencePct)),
            _TechnicalStat(title: 'মোট পানি', value: '${(t.waterMlTotal / 1000).toStringAsFixed(1)}L', icon: Icons.water_drop_rounded, color: Colors.blue),
            _TechnicalStat(title: 'ওষুধের ডোজ', value: '${t.medTakenTotal}/${t.medScheduledTotal}', icon: Icons.medication_rounded, color: AppColors.violet),
            _TechnicalStat(title: 'ব্যায়াম সম্পন্ন', value: '${t.workoutsCompleted}', icon: Icons.fitness_center_rounded, color: AppColors.svcHeroAccent),
          ],
        ),
      ],
    );
  }
}

class _TechnicalStat extends StatelessWidget {
  final String title, value;
  final IconData icon;
  final Color color;
  const _TechnicalStat({required this.title, required this.value, required this.icon, required this.color});

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
              FittedBox(child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.ink, height: 1.1))),
              Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.smoke)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PdfDownloadBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _PdfDownloadBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () { HapticFeedback.heavyImpact(); onTap(); },
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(color: AppColors.svcHero, borderRadius: BorderRadius.zero),
        child: const Row(
          children: [
            Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 32),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('PDF রিপোর্ট ডাউনলোড করুন', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                  Text('ডাক্তারকে দেখানোর জন্য পূর্ণাঙ্গ ফাইল', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Icon(Icons.download_rounded, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }
}

class _DayCard extends StatefulWidget {
  final ThirtyDayReportDay day;
  const _DayCard({required this.day});
  @override
  State<_DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<_DayCard> {
  bool _expanded = false;
  DayFullReport? _detail;
  bool _loading = false;

  Future<void> _toggle() async {
    setState(() => _expanded = !_expanded);
    if (_expanded && _detail == null && !widget.day.isFuture) {
      setState(() => _loading = true);
      try {
        final d = await SupabaseService.getDayFullReport(date: widget.day.date);
        if (mounted) setState(() { _detail = d; _loading = false; });
      } catch (_) {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.day;
    final color = _adherenceColor(d.adherencePct);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: _expanded ? AppColors.svcHero : AppColors.line, width: _expanded ? 2 : 1.2)),
      child: Column(
        children: [
          ListTile(
            onTap: _toggle,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.zero),
              alignment: Alignment.center,
              child: Text('${d.dayOfCycle}', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18)),
            ),
            title: Text('দিন ${d.dayOfCycle} · ${d.bnWeekday}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            subtitle: Text(d.dateLabelBn, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.smoke)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${d.adherencePct.clamp(0, 100)}%', style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 16)),
                const SizedBox(width: 8),
                Icon(_expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: AppColors.smoke),
              ],
            ),
          ),
          if (_expanded) _buildExpandedContent(),
        ],
      ),
    );
  }

  Widget _buildExpandedContent() {
    if (_loading) return const Padding(padding: EdgeInsets.all(20), child: LoadingMark(size: 20));
    if (_detail == null) return const Padding(padding: EdgeInsets.all(20), child: Text('কোনো তথ্য পাওয়া যায়নি'));
    
    final detail = _detail!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(color: AppColors.svcCategoryBg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TechnicalMacroStrip(macros: detail.macros),
          const SizedBox(height: 16),
          if (detail.meals.isNotEmpty) _DetailGroup(title: 'খাবার', items: detail.meals.map((m) => '${m.time} · ${m.nameBn.isEmpty ? m.nameEn : m.nameBn} (${m.impact})').toList(), icon: Icons.restaurant_rounded, color: AppColors.amber),
          if (detail.meds.isNotEmpty) _DetailGroup(title: 'ওষুধ', items: detail.meds.map((m) => '${m.scheduledAt} · ${m.name} (${m.status})').toList(), icon: Icons.medication_rounded, color: AppColors.violet),
          if (detail.workouts.isNotEmpty) _DetailGroup(title: 'ব্যায়াম', items: detail.workouts.map((w) => '${w.name} (${w.durationMin} মিনিট)').toList(), icon: Icons.fitness_center_rounded, color: AppColors.svcHeroAccent),
          if (detail.waterLogs.isNotEmpty) _DetailGroup(title: 'পানি', items: detail.waterLogs.map((w) => '${w.time} · ${w.ml} মিলি').toList(), icon: Icons.water_drop_rounded, color: Colors.blue),
        ],
      ),
    );
  }
}

class _TechnicalMacroStrip extends StatelessWidget {
  final DayMacros macros;
  const _TechnicalMacroStrip({required this.macros});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _m('Kcal', '${macros.kcal}'),
          _m('Carb', '${macros.carbG}g'),
          _m('Prot', '${macros.proteinG}g'),
          _m('Fat', '${macros.fatG}g'),
        ],
      ),
    );
  }
  Widget _m(String k, String v) => Column(children: [Text(k, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.smoke)), Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900))]);
}

class _DetailGroup extends StatelessWidget {
  final String title;
  final List<String> items;
  final IconData icon;
  final Color color;
  const _DetailGroup({required this.title, required this.items, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, size: 14, color: color), const SizedBox(width: 6), Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 13))]),
          const SizedBox(height: 6),
          ...items.map((it) => Padding(padding: const EdgeInsets.only(left: 20, bottom: 2), child: Text(it, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.ink)))),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title, sub;
  const _SectionLabel({required this.title, required this.sub});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.ink, letterSpacing: -0.5)),
          Text(sub, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.smoke)),
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

Color _adherenceColor(int pct) {
  if (pct >= 80) return AppColors.svcHeroAccent;
  if (pct >= 55) return AppColors.amber;
  return AppColors.rose;
}
