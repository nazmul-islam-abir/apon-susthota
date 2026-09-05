/// Patient Detail screen — high-fidelity technical summary for caregivers (Nexora Redesign).
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/caregiver_observation.dart';
import '../../models/caretaker_patient_summary.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/mono_widgets.dart';
import 'log_meal_for_patient_screen.dart';
import 'log_dose_for_patient_screen.dart';
import 'caretaker_charts_screen.dart';
import 'caretaker_full_patient_view.dart';
import 'caretaker_meal_plan_view.dart';
import 'caretaker_water_view.dart';
import 'caretaker_water_analytics_view.dart';
import 'caretaker_medicine_view.dart';
import 'caretaker_workout_view.dart';
import 'caretaker_analytics_view.dart';
import 'caretaker_report_view.dart';
import 'caretaker_profile_view.dart';

class PatientDetailScreen extends StatefulWidget {
  final CaretakerPatientSummary patient;
  const PatientDetailScreen({super.key, required this.patient});

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  late Future<_DetailData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DetailData> _load() async {
    final uid = widget.patient.patientUserId;
    final results = await Future.wait([
      SupabaseService.getCaretakerTodayOverview(patientUserId: uid),
      SupabaseService.getCaretakerClinicalSnapshot(patientUserId: uid),
      SupabaseService.getCaretakerRecentActivities(patientUserId: uid, limit: 30),
    ]);
    return _DetailData(
      overview: (results[0] as Map?)?.cast<String, dynamic>() ?? {},
      snapshot: (results[1] as Map?)?.cast<String, dynamic>() ?? {},
      activities: ((results[2] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => CaregiverObservation.fromRpcJson(m.cast<String, dynamic>()))
          .toList(),
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.patient;
    return Scaffold(
      backgroundColor: AppColors.svcCategoryBg,
      body: RefreshIndicator(
        color: AppColors.svcHero,
        onRefresh: _refresh,
        child: FutureBuilder<_DetailData>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done && !snap.hasData) {
              return const Center(child: CircularProgressIndicator(color: AppColors.svcHero));
            }
            final data = snap.data ?? _DetailData.empty();
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              slivers: [
                _buildHero(p),
                const SliverToBoxAdapter(child: SizedBox(height: 22)),
                SliverToBoxAdapter(child: _LauncherGrid(patient: p)),
                const SliverToBoxAdapter(child: SizedBox(height: 22)),
                SliverToBoxAdapter(child: _buildSectionTitle('ক্লিনিক্যাল স্ন্যাপশট', 'রিয়েল-টাইম ডেটা')),
                SliverToBoxAdapter(child: _ClinicalGrid(snapshot: data.snapshot)),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
                SliverToBoxAdapter(child: _buildSectionTitle('অগ্রগতি', 'আজকের স্ট্যাটাস')),
                SliverToBoxAdapter(child: _TodayCard(overview: data.overview)),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
                SliverToBoxAdapter(child: _buildSectionTitle('সাম্প্রতিক কার্যকলাপ', 'টাইমলাইন')),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList.separated(
                    itemCount: data.activities.take(10).length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _FeedRow(obs: data.activities[i]),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 140)),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: _ActionBar(patientUserId: p.patientUserId, patientName: p.fullName),
    );
  }

  Widget _buildHero(CaretakerPatientSummary p) {
    const url = 'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/app/photo-1564352969906-8b7f46ba4b8b.avif?token=eyJraWQiOiJhZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJhcHAvcGhvdG8tMTU2NDM1Mjk2OTkwNi04YjdmNDZiYTRiOGIuYXZpZiIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODc4Njg2MjksImV4cCI6MTgxOTQwNDYyOX0.Jdl-6cqT6wHh_nv8j-7oD3zjU2KcoR4e5ohJVnZgTNs';
    return SliverToBoxAdapter(
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.svcHero,
          image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover, opacity: 0.7),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: Container(color: Colors.black.withValues(alpha: 0.35))),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 20, 0),
                    child: Row(
                      children: [
                        IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context)),
                        const Expanded(child: Text('রোগীর বিস্তারিত', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5))),
                        IconButton(
                          icon: const Icon(Icons.insights_rounded, color: Colors.white),
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CaretakerChartsScreen(patientUserId: p.patientUserId, patientName: p.fullName))),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: Row(
                    children: [
                      _Avatar(name: p.fullName, size: 64, avatarUrl: p.avatarUrl),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.fullName.isEmpty ? 'রোগী' : p.fullName, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -0.6)),
                            const SizedBox(height: 6),
                            Text(p.subtitleBn, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                      // One-tap full view button
                      Material(
                        color: Colors.white,
                        child: InkWell(
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => CaretakerFullPatientView(patient: p),
                          )),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.zero,
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.dashboard_rounded, color: AppColors.svcHero, size: 16),
                                SizedBox(width: 6),
                                Text(
                                  'সম্পূর্ণ দেখুন',
                                  style: TextStyle(
                                    color: AppColors.svcHero,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
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

  Widget _buildSectionTitle(String title, String sub) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.newsInk, letterSpacing: -0.3)),
          Text(sub, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.newsMuted.withValues(alpha: 0.8))),
        ],
      ),
    );
  }
}

class _DetailData {
  final Map<String, dynamic> overview;
  final Map<String, dynamic> snapshot;
  final List<CaregiverObservation> activities;
  _DetailData({required this.overview, required this.snapshot, required this.activities});
  factory _DetailData.empty() => _DetailData(overview: const {}, snapshot: const {}, activities: const []);
}

class _ClinicalGrid extends StatelessWidget {
  final Map<String, dynamic> snapshot;
  const _ClinicalGrid({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final hba1c = _num(snapshot['hba1c_percent']);
    final fbg = _num(snapshot['fasting_glucose_mmol']);
    final sbp = _num(snapshot['systolic_bp']);
    final dbp = _num(snapshot['diastolic_bp']);
    final bmi = _num(snapshot['bmi']);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.1,
        children: [
          _ClinicalCard(label: 'HbA1c', value: hba1c == null ? '—' : '${hba1c.toStringAsFixed(1)}%', icon: Icons.bloodtype_rounded, color: AppColors.cyan),
          _ClinicalCard(label: 'সুগার', value: fbg == null ? '—' : '${fbg.toStringAsFixed(1)}', icon: Icons.water_drop_rounded, color: AppColors.violet),
          _ClinicalCard(label: 'বিপি', value: (sbp == null || dbp == null) ? '—' : '${sbp.toInt()}/${dbp.toInt()}', icon: Icons.favorite_rounded, color: AppColors.rose),
          _ClinicalCard(label: 'BMI', value: bmi == null ? '—' : bmi.toStringAsFixed(1), icon: Icons.monitor_weight_rounded, color: AppColors.amber),
          _ClinicalCard(label: 'CKD', value: snapshot['ckd_stage'] == null ? '—' : 'G${snapshot['ckd_stage']}', icon: Icons.health_and_safety_rounded, color: AppColors.mint),
          _ClinicalCard(label: 'ইনসুলিন', value: (snapshot['on_insulin'] ?? false) ? 'হ্যাঁ' : 'না', icon: Icons.medication_rounded, color: AppColors.svcHero),
        ],
      ),
    );
  }

  double? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

class _ClinicalCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _ClinicalCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.line, width: 1.2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.zero),
            alignment: Alignment.center,
            child: Icon(icon, size: 14, color: color),
          ),
          const Spacer(),
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.smoke, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.ink, letterSpacing: -0.4)),
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  final Map<String, dynamic> overview;
  const _TodayCard({required this.overview});

  @override
  Widget build(BuildContext context) {
    final planned = (overview['planned'] as num?)?.toInt() ?? 0;
    final good = (overview['good'] as num?)?.toInt() ?? 0;
    final pct = planned == 0 ? 0.0 : (good / planned);
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line, width: 1.2)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('দৈনিক অগ্রগতি', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.smoke, letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  Text('$good / $planned খাবার সম্পন্ন', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.ink)),
                  const SizedBox(height: 12),
                  MonoBar(value: pct, height: 8, fill: AppColors.svcHero),
                ],
              ),
            ),
            const SizedBox(width: 24),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(width: 64, height: 64, child: CircularProgressIndicator(value: pct, strokeWidth: 10, color: AppColors.svcHero, backgroundColor: AppColors.surfaceHigh)),
                Text('${(pct * 100).round()}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.ink)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedRow extends StatelessWidget {
  final CaregiverObservation obs;
  const _FeedRow({required this.obs});

  @override
  Widget build(BuildContext context) {
    final tone = _toneColor(obs.tone);
    final icon = _iconFor(obs.kind);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line, width: 1.0)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: tone.withValues(alpha: 0.1), borderRadius: BorderRadius.zero),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: tone),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(obs.summaryBn, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.ink)),
                Text(DateFormat('d MMM, HH:mm', 'bn').format(obs.occurredAt.toLocal()), style: const TextStyle(fontSize: 11, color: AppColors.smoke, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _toneColor(String tone) => (tone == 'good') ? AppColors.svcHero : (tone == 'bad' ? AppColors.rose : AppColors.amber);
  IconData _iconFor(CaregiverObservationKind k) {
    switch (k) {
      case CaregiverObservationKind.meal: return Icons.restaurant_rounded;
      case CaregiverObservationKind.medicine: return Icons.medication_rounded;
      case CaregiverObservationKind.water: return Icons.water_drop_rounded;
      case CaregiverObservationKind.workout: return Icons.fitness_center_rounded;
      case CaregiverObservationKind.voice: return Icons.mic_rounded;
    }
  }
}

class _ActionBar extends StatelessWidget {
  final String patientUserId, patientName;
  const _ActionBar({required this.patientUserId, required this.patientName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.line, width: 1.2)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -4))],
      ),
      child: Row(
        children: [
          Expanded(
            child: MonoButton(
              label: 'খাবার লগ',
              leading: Icons.restaurant_rounded,
              height: 56,
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LogMealForPatientScreen(patientUserId: patientUserId, patientName: patientName))),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: MonoButton(
              label: 'ওষুধ লগ',
              leading: Icons.medication_rounded,
              color: AppColors.mintDeep,
              height: 56,
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LogDoseForPatientScreen(patientUserId: patientUserId, patientName: patientName))),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final double size;
  final String? avatarUrl;
  const _Avatar({required this.name, this.size = 52, this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    final initials = _initials(name);
    final url = avatarUrl?.trim();
    final hasAvatar = url != null && url.isNotEmpty;

    Widget fallback() => Text(
          initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.35,
            fontWeight: FontWeight.w900,
          ),
        );

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.zero,
        border: Border.all(color: Colors.white24),
      ),
      clipBehavior: Clip.hardEdge,
      alignment: Alignment.center,
      child: hasAvatar
          ? Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback(),
              loadingBuilder: (_, child, p) => p == null ? child : fallback(),
            )
          : fallback(),
    );
  }

  String _initials(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return 'র';
    final parts = s.split(RegExp(r'\s+'));
    if (parts.length >= 2) return (parts[0][0]) + (parts[1][0]);
    return s.characters.first.toUpperCase();
  }
}

/// Launcher grid — caretakers get one-tap access to every read-only
/// viewer for the patient they're watching. Tiles mirror what the
/// patient sees in their own tabs.
class _LauncherGrid extends StatelessWidget {
  final CaretakerPatientSummary patient;
  const _LauncherGrid({required this.patient});

  @override
  Widget build(BuildContext context) {
    final tiles = <_LauncherTile>[
      _LauncherTile(
        icon: Icons.dashboard_rounded,
        label: 'সম্পূর্ণ প্রোফাইল',
        color: AppColors.svcHero,
        onTap: () => _push(context, CaretakerFullPatientView(patient: patient)),
      ),
      _LauncherTile(
        icon: Icons.restaurant_menu_rounded,
        label: 'খাবারের পরিকল্পনা',
        color: AppColors.cyan,
        onTap: () => _push(context, CaretakerMealPlanView(patient: patient)),
      ),
      _LauncherTile(
        icon: Icons.water_drop_rounded,
        label: 'পানির খতিয়ান',
        color: AppColors.violetDeep,
        onTap: () => _push(context, CaretakerWaterView(patient: patient)),
      ),
      _LauncherTile(
        icon: Icons.analytics_rounded,
        label: 'পানি বিশ্লেষণ',
        color: Colors.blue,
        onTap: () => _push(context, CaretakerWaterAnalyticsView(patient: patient)),
      ),
      _LauncherTile(
        icon: Icons.medication_rounded,
        label: 'ওষুধের সময়সূচী',
        color: AppColors.mintDeep,
        onTap: () => _push(context, CaretakerMedicineView(patient: patient)),
      ),
      _LauncherTile(
        icon: Icons.fitness_center_rounded,
        label: 'ব্যায়াম তালিকা',
        color: AppColors.amber,
        onTap: () => _push(context, CaretakerWorkoutView(patient: patient)),
      ),
      _LauncherTile(
        icon: Icons.insights_rounded,
        label: 'বিশ্লেষণ',
        color: AppColors.svcHero,
        onTap: () => _push(context, CaretakerAnalyticsView(patient: patient)),
      ),
      _LauncherTile(
        icon: Icons.picture_as_pdf_rounded,
        label: 'ডাক্তারের প্রতিবেদন',
        color: AppColors.rose,
        onTap: () => _push(context, CaretakerReportView(patient: patient)),
      ),
      _LauncherTile(
        icon: Icons.person_outline_rounded,
        label: 'রোগীর প্রোফাইল',
        color: AppColors.smoke,
        onTap: () => _push(context, CaretakerProfileView(patient: patient)),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'রোগীর সব দেখুন',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.newsInk,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'খাবার, পানি, ওষুধ, ব্যায়াম, বিশ্লেষণ ও আরও',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.newsMuted.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.7,
            children: tiles,
          ),
        ),
      ],
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

class _LauncherTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _LauncherTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: AppColors.line, width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.zero,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
