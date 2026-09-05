/// Caretaker "আজ" tab — professional technical summary of the selected patient (Nexora Redesign).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/caregiver_observation.dart';
import '../../models/caretaker_patient_summary.dart';
import '../../models/user_profile.dart';
import '../../services/caretaker_provider.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/mono_widgets.dart';
import '../../widgets/patient_data_realtime_mixin.dart';
import 'caretaker_shell.dart' show bnGreeting;
import 'patient_detail_screen.dart';

class CaretakerTodayTab extends StatefulWidget {
  final UserProfile? profile;
  const CaretakerTodayTab({super.key, this.profile});

  @override
  State<CaretakerTodayTab> createState() => _CaretakerTodayTabState();
}

class _CaretakerTodayTabState extends State<CaretakerTodayTab>
    with PatientDataRealtimeMixin {
  Map<String, dynamic>? _overview;
  List<CaregiverObservation> _feed = const [];
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pid = context
          .read<CaretakerProvider>()
          .selectedPatientUserId;
      if (pid != null) {
        attachPatientDataRealtime(pid, _refresh);
      }
      _refresh();
    });
  }

  @override
  void dispose() {
    disposePatientDataRealtime();
    super.dispose();
  }

  Future<void> _refresh() async {
    final prov = context.read<CaretakerProvider>();
    final pid = prov.selectedPatientUserId;
    if (pid == null) {
      if (mounted) setState(() { _overview = null; _feed = const []; _loading = false; });
      return;
    }
    // If the caretaker switched patients, retarget the realtime
    // subscription so callbacks fire for the new patient's rows
    // instead of the old one.
    switchPatientDataRealtime(pid);
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        SupabaseService.getCaretakerTodayOverview(patientUserId: pid),
        SupabaseService.getCaretakerRecentActivities(patientUserId: pid),
      ]);
      if (mounted) setState(() { _overview = results[0] as Map<String, dynamic>; _feed = results[1] as List<CaregiverObservation>; });
    } catch (e) {
      if (mounted) setState(() { _error = e; });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.svcCategoryBg,
      body: Consumer<CaretakerProvider>(
        builder: (context, prov, _) {
          final selected = prov.selectedPatient;
          return RefreshIndicator(
            color: AppColors.svcHero,
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              slivers: [
                _buildHero(selected),
                const SliverToBoxAdapter(child: SizedBox(height: 22)),
                
                if (selected == null)
                  const SliverFillRemaining(hasScrollBody: false, child: _NoPatientSelected())
                else ...[
                  if (_loading && _overview == null)
                    const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: AppColors.svcHero)))
                  else if (_error != null)
                    SliverToBoxAdapter(child: _ErrorBanner(message: '$_error'))
                  else if (_overview != null) ...[
                    SliverToBoxAdapter(child: _buildSectionTitle('আজকের সারাংশ', 'রিয়েল-টাইম স্ন্যাপশট')),
                    SliverToBoxAdapter(child: _OverviewGrid(overview: _overview!)),
                    SliverToBoxAdapter(child: _AtRiskCallouts(overview: _overview!)),
                  ],

                  const SliverToBoxAdapter(child: SizedBox(height: 22)),
                  SliverToBoxAdapter(child: _buildSectionTitle('সাম্প্রতিক কার্যকলাপ', 'টাইমলাইন')),
                  if (_feed.isEmpty && !_loading)
                    const SliverToBoxAdapter(child: _FeedEmpty())
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 140),
                      sliver: SliverList.separated(
                        itemCount: _feed.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _FeedRow(obs: _feed[i]),
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHero(CaretakerPatientSummary? selected) {
    const url = 'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/app/photo-1564352969906-8b7f46ba4b8b.avif?token=eyJraWQiOiJhZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJhcHAvcGhvdG8tMTU2NDM1Mjk2OTkwNi04YjdmNDZiYTRiOGIuYXZpZiIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODc4Njg2MjksImV4cCI6MTgxOTQwNDYyOX0.Jdl-6cqT6wHh_nv8j-7oD3zjU2KcoR4e5ohJVnZgTNs';
    final name = (widget.profile?.fullName ?? '').trim();
    final greeting = name.isEmpty ? bnGreeting() : '${bnGreeting()}, ${name.split(' ').first}';

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
                const SafeArea(bottom: false, child: SizedBox(height: 20)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(greeting, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -1)),
                      const SizedBox(height: 24),
                      if (selected != null)
                        InkWell(
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PatientDetailScreen(patient: selected))),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.zero, border: Border.all(color: Colors.white24)),
                            child: Row(
                              children: [
                                _Avatar(name: selected.fullName, size: 52),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(selected.fullName, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                                      Text('পরিচর্যাকারী হিসেবে দেখছেন', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 14),
                              ],
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.zero, border: Border.all(color: Colors.white24)),
                          child: const Row(
                            children: [
                              Icon(Icons.touch_app_rounded, color: Colors.white, size: 20),
                              SizedBox(width: 12),
                              Text('“রোগী” ট্যাব থেকে একজনকে নির্বাচন করুন', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                            ],
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

class _OverviewGrid extends StatelessWidget {
  final Map<String, dynamic> overview;
  const _OverviewGrid({required this.overview});

  @override
  Widget build(BuildContext context) {
    final meals = (overview['meals'] as List?) ?? const [];
    final eatenCount = meals.where((m) => m is Map && (m['status'] == 'eaten' || m['status'] == 'swap')).length;
    const plannedSlots = 3;
    final dosesTaken = _asInt((overview['medicine'] as Map?)?['taken']);
    final dosesPlanned = _asInt((overview['medicine'] as Map?)?['total']);
    final waterL = _asDouble(overview['water_liters']);
    final waterTarget = _asDouble(overview['water_target']) == 0 ? 2.5 : _asDouble(overview['water_target']);
    final waterLitersStr = waterL <= 0 ? '—' : '${waterL.toStringAsFixed(1)} / ${waterTarget.toStringAsFixed(1)} L';
    final sugar = overview['sugar'] as Map?;
    final glucoseStr = sugar == null ? '—' : _formatSugar(sugar);
    final bp = overview['bp'] as Map?;
    final bpStr = bp == null ? '—' : _formatBp(bp);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.1,
        children: [
          _StatCard(icon: Icons.restaurant_rounded, label: 'খাবার', value: '$eatenCount / $plannedSlots', color: AppColors.svcHero, hint: 'আজকের মিল সম্পন্ন'),
          _StatCard(icon: Icons.medication_rounded, label: 'ওষুধ', value: dosesPlanned == 0 ? '$dosesTaken' : '$dosesTaken / $dosesPlanned', color: AppColors.mintDeep, hint: dosesPlanned == 0 ? 'রুটিন চেক' : 'আজকের ডোজ'),
          _StatCard(icon: Icons.water_drop_rounded, label: 'পানি', value: waterLitersStr, color: Colors.blue, hint: 'লক্ষ্য ${waterTarget.toStringAsFixed(1)} L'),
          _StatCard(icon: Icons.monitor_heart_outlined, label: 'ভাইটালস', value: glucoseStr, color: AppColors.rose, hint: bpStr == '—' ? 'সুগার লেভেল' : 'বিপি $bpStr'),
        ],
      ),
    );
  }

  static int _asInt(Object? v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static double _asDouble(Object? v) {
    if (v == null) return 0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  static String _formatSugar(Map sugar) {
    final fasting = sugar['fasting_mmol'];
    final post = sugar['postprandial_mmol'];
    final random = sugar['random_mmol'];
    if (fasting != null) return '${_fmt(fasting)} mmol/L';
    if (post != null) return '${_fmt(post)} mmol/L';
    if (random != null) return '${_fmt(random)} mmol/L';
    return '—';
  }

  static String _fmt(Object v) {
    if (v is num) return v.toStringAsFixed(v is int ? 0 : 1);
    return v.toString();
  }

  static String _formatBp(Map bp) {
    final s = bp['systolic_mmhg'];
    final d = bp['diastolic_mmhg'];
    if (s == null || d == null) return '—';
    return '${_fmt(s)}/${_fmt(d)}';
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label, value, hint;
  final Color color;
  const _StatCard({required this.icon, required this.label, required this.value, required this.hint, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.line, width: 1.2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.zero),
            alignment: Alignment.center,
            child: Icon(icon, size: 16, color: color),
          ),
          const Spacer(),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.smoke, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.ink, letterSpacing: -0.6)),
          Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: AppColors.smoke, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _AtRiskCallouts extends StatelessWidget {
  final Map<String, dynamic> overview;
  const _AtRiskCallouts({required this.overview});

  @override
  Widget build(BuildContext context) {
    final notes = <_Callout>[];
    final meals = (overview['meals'] as List?) ?? const [];
    final offPlan = meals.where((m) => m is Map && m['status'] == 'off_plan').length;
    final med = overview['medicine'] as Map?;
    final dosesTaken = _asInt(med?['taken']);
    final dosesPlanned = _asInt(med?['total']);
    final missedDoses = dosesPlanned > 0 ? (dosesPlanned - dosesTaken).clamp(0, dosesPlanned) : 0;
    final sugar = overview['sugar'] as Map?;
    final fasting = sugar == null ? null : _asDouble(sugar['fasting_mmol']);
    final post = sugar == null ? null : _asDouble(sugar['postprandial_mmol']);
    final glucoseHigh = (fasting != null && fasting > 7.0) || (post != null && post > 11.1);
    final waterL = _asDouble(overview['water_liters']);
    final noActivity = meals.isEmpty && dosesTaken == 0 && waterL <= 0;

    if (missedDoses > 0) notes.add(_Callout(icon: Icons.warning_amber_rounded, color: AppColors.rose, title: 'বাদ পড়া ওষুধ', body: 'আজ $missedDosesটি ডোজ সময়মতো নেওয়া হয়নি'));
    if (offPlan > 0) notes.add(_Callout(icon: Icons.no_food_rounded, color: AppColors.amber, title: 'পরিকল্পনার বাইরে খাবার', body: 'আজ $offPlanটি খাবার পরিকল্পনা মেনে হয়নি'));
    if (glucoseHigh) notes.add(_Callout(icon: Icons.monitor_heart_outlined, color: AppColors.rose, title: 'উচ্চ গ্লুকোজ', body: 'সর্বশেষ রিডিং লক্ষ্যমাত্রার উপরে'));
    if (noActivity) notes.add(_Callout(icon: Icons.notifications_active_outlined, color: AppColors.svcHero, title: 'আজ কোনো কার্যকলাপ নেই', body: 'খাবার বা ওষুধ এখনো লগ করা হয়নি'));

    if (notes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: notes.map((c) => Padding(padding: const EdgeInsets.only(bottom: 8), child: c)).toList(),
      ),
    );
  }

  static int _asInt(Object? v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static double _asDouble(Object? v) {
    if (v == null) return 0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

class _Callout extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, body;
  const _Callout({required this.icon, required this.color, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.zero, border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.ink)),
                Text(body, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.smoke)),
              ],
            ),
          ),
        ],
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
    final time = _formatTime(obs.occurredAt);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.line, width: 1.0),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: tone.withValues(alpha: 0.08), borderRadius: BorderRadius.zero, border: Border.all(color: tone.withValues(alpha: 0.15))),
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: tone),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(obs.summaryBn, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.ink, height: 1.2)),
                if (obs.detail != null) ...[
                  const SizedBox(height: 4),
                  Text(_formatDetail(obs.kind, obs.detail!), style: TextStyle(fontSize: 12, color: AppColors.smoke.withValues(alpha: 0.8), fontWeight: FontWeight.w700)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(time, style: const TextStyle(fontSize: 11, color: AppColors.smoke, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Color _toneColor(String tone) {
    if (tone == 'good') return AppColors.svcHero;
    if (tone == 'warn') return AppColors.amber;
    if (tone == 'bad') return AppColors.rose;
    return AppColors.svcHero;
  }

  IconData _iconFor(CaregiverObservationKind k) {
    switch (k) {
      case CaregiverObservationKind.meal: return Icons.restaurant_rounded;
      case CaregiverObservationKind.medicine: return Icons.medication_rounded;
      case CaregiverObservationKind.water: return Icons.water_drop_rounded;
      case CaregiverObservationKind.workout: return Icons.fitness_center_rounded;
      case CaregiverObservationKind.voice: return Icons.mic_rounded;
    }
  }

  static String _formatDetail(CaregiverObservationKind kind, Map<String, dynamic> detail) {
    switch (kind) {
      case CaregiverObservationKind.meal:
        final slot = detail['meal_slot']?.toString();
        final food = detail['food_name_bn']?.toString();
        return (slot != null && food != null) ? '$slot • $food' : (food ?? slot ?? '');
      case CaregiverObservationKind.medicine:
        final status = detail['status']?.toString();
        final scheduled = detail['scheduled_time']?.toString();
        return (status != null && scheduled != null) ? '$status • $scheduled' : (status ?? scheduled ?? '');
      case CaregiverObservationKind.water:
        return '${detail['liters'] ?? ''} লিটার';
      case CaregiverObservationKind.workout:
        if (detail['completed_items'] != null) return '${detail['completed_items']} / ${detail['total_items']} সম্পন্ন';
        return '${detail['duration_seconds'] ?? ''} সেকেন্ড';
      case CaregiverObservationKind.voice:
        final dur = detail['duration_ms'];
        if (dur is num) {
          final s = (dur.toInt() / 1000).round();
          final m = s ~/ 60;
          final r = s % 60;
          return 'ভয়েস মেসেজ ($m:${r.toString().padLeft(2, '0')})';
        }
        return 'ভয়েস মেসেজ';
    }
  }

  String _formatTime(DateTime utc) {
    final local = utc.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _NoPatientSelected extends StatelessWidget {
  const _NoPatientSelected();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.person_search_rounded, color: AppColors.lineStrong, size: 72),
          const SizedBox(height: 16),
          const Text('কোনো রোগী নির্বাচিত নেই', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.ink)),
          const SizedBox(height: 8),
          const Text('“রোগী” ট্যাব থেকে একজনকে বেছে নিলে আজকের\nসারাংশ ও সাম্প্রতিক কার্যকলাপ দেখতে পাবেন।', textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: AppColors.smoke, height: 1.4)),
        ],
      ),
    );
  }
}

class _FeedEmpty extends StatelessWidget {
  const _FeedEmpty();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.event_note_rounded, size: 48, color: AppColors.lineStrong.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          const Text('এখনো কোনো কার্যকলাপ নেই', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.smoke)),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final double size;
  const _Avatar({required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    final initials = _initials(name);
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.zero, border: Border.all(color: Colors.white24)),
      alignment: Alignment.center,
      child: Text(initials, style: TextStyle(color: Colors.white, fontSize: size * 0.35, fontWeight: FontWeight.w900)),
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

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.rose.withValues(alpha: 0.08), borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.rose.withValues(alpha: 0.3))),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.rose, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(fontSize: 13, color: AppColors.ink, fontWeight: FontWeight.w700))),
          ],
        ),
      ),
    );
  }
}
