/// Caretaker "আজ" tab — at-a-glance view of the currently-selected
/// patient's day plus a live activity feed.
///
/// Layout (top → bottom):
///   1. CaretakerHeaderStrip              (greeting + counts + role chip)
///   2. _SelectedPatientBanner            (or "select a patient" CTA)
///   3. _OverviewGrid                     (4 stat cards)
///   4. _AtRiskCallouts                   (only when something needs action)
///   5. _ActivityFeed                     (latest 50 CaregiverObservation rows)
///
/// Pull-to-refresh hits `get_caretaker_today_overview` + the feed RPC.
/// No write operations live here — this is read-only.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/caregiver_observation.dart';
import '../../models/caretaker_patient_summary.dart';
import '../../models/user_profile.dart';
import '../../services/caretaker_provider.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import 'caretaker_shell.dart' show CaretakerHeaderStrip;
import 'patient_detail_screen.dart';

class CaretakerTodayTab extends StatefulWidget {
  /// Caretaker's own profile — used in the header strip greeting.
  final UserProfile? profile;
  const CaretakerTodayTab({super.key, this.profile});

  @override
  State<CaretakerTodayTab> createState() => _CaretakerTodayTabState();
}

class _CaretakerTodayTabState extends State<CaretakerTodayTab> {
  Map<String, dynamic>? _overview;
  List<CaregiverObservation> _feed = const [];
  bool _loadingOverview = false;
  bool _loadingFeed = false;
  Object? _overviewError;
  Object? _feedError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final prov = context.read<CaretakerProvider>();
    final pid = prov.selectedPatientUserId;
    if (pid == null) {
      setState(() {
        _overview = null;
        _feed = const [];
        _loadingOverview = false;
        _loadingFeed = false;
      });
      return;
    }
    setState(() {
      _loadingOverview = true;
      _loadingFeed = true;
      _overviewError = null;
      _feedError = null;
    });
    try {
      final ov = await SupabaseService.getCaretakerTodayOverview(patientUserId: pid);
      final feed =
          await SupabaseService.getCaretakerRecentActivities(patientUserId: pid);
      if (!mounted) return;
      setState(() {
        _overview = ov;
        _feed = feed;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _overviewError = e;
        _feedError = e;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingOverview = false;
          _loadingFeed = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CaretakerProvider>(
      builder: (context, prov, _) {
        final selected = prov.selectedPatient;
        return RefreshIndicator(
          color: AppColors.violetDeep,
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: CaretakerHeaderStrip(
                  profile: widget.profile,
                  patientCount: prov.patients.length,
                  pendingCount: prov.pending.length,
                ),
              ),
              SliverToBoxAdapter(
                child: _SelectedPatientBanner(
                  patient: selected,
                  onChanged: () => _refresh(),
                ),
              ),
              if (selected == null)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _NoPatientSelected(),
                )
              else ...[
                if (_loadingOverview)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.violet,
                          strokeWidth: 3,
                        ),
                      ),
                    ),
                  )
                else if (_overviewError != null)
                  SliverToBoxAdapter(child: _ErrorBanner(message: '$_overviewError'))
                else if (_overview != null)
                  SliverToBoxAdapter(
                    child: _OverviewGrid(overview: _overview!),
                  ),
                if (_overview != null)
                  SliverToBoxAdapter(
                    child: _AtRiskCallouts(overview: _overview!),
                  ),
                const SliverToBoxAdapter(
                  child: _Overline(text: 'সাম্প্রতিক কার্যকলাপ'),
                ),
                if (_loadingFeed)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.violet,
                          strokeWidth: 3,
                        ),
                      ),
                    ),
                  )
                else if (_feedError != null)
                  SliverToBoxAdapter(child: _ErrorBanner(message: '$_feedError'))
                else if (_feed.isEmpty)
                  const SliverToBoxAdapter(child: _FeedEmpty())
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    sliver: SliverList.separated(
                      itemBuilder: (_, i) => _FeedRow(obs: _feed[i]),
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemCount: _feed.length,
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------------
// Selected-patient banner + "no patient" CTA
// ------------------------------------------------------------------

class _SelectedPatientBanner extends StatelessWidget {
  final CaretakerPatientSummary? patient;
  final VoidCallback onChanged;
  const _SelectedPatientBanner({required this.patient, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (patient == null) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: AppColors.violet.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.violet.withValues(alpha: 0.22),
          ),
        ),
        child: const Row(
          children: [
            Icon(Icons.touch_app_rounded, color: AppColors.violetDeep, size: 22),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'নিচের “রোগী” ট্যাব থেকে একজনকে নির্বাচন করুন',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final p = patient!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PatientDetailScreen(patient: p),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.violet, AppColors.violetDeep],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
child: Row(
              children: [
                _Avatar(name: p.fullName),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Allow two lines so long Bangla names never
                      // get cropped by the gradient banner.
                      Text(
                        p.fullName.isEmpty ? 'রোগী' : p.fullName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        p.subtitleBn,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoPatientSelected extends StatelessWidget {
  const _NoPatientSelected();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.violet.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_search_rounded,
                color: AppColors.violetDeep,
                size: 32,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'কোনো রোগী নির্বাচিত নেই',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '“রোগী” ট্যাব থেকে একজনকে বেছে নিলে আজকের\nসারাংশ ও সাম্প্রতিক কার্যকলাপ দেখতে পাবেন।',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: AppColors.textMuted,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------
// Overview grid — 4 stat cards (meals, doses, water, workouts)
// ------------------------------------------------------------------

class _OverviewGrid extends StatelessWidget {
  final Map<String, dynamic> overview;
  const _OverviewGrid({required this.overview});

  @override
  Widget build(BuildContext context) {
    // `get_caretaker_today_overview` JSON shape:
    //   meals[]        — array of {meal_slot, status, impact, food_name_bn, created_at}
    //   water_liters   — numeric (0..N)
    //   water_target   — numeric (default 2.5)
    //   sugar          — {fasting_mmol, postprandial_mmol, random_mmol, hba1c_percent}
    //   bp             — {systolic_mmhg, diastolic_mmhg}
    //   medicine       — {taken, total, taken_pct}
    final meals = (overview['meals'] as List?) ?? const [];
    final eatenCount = meals
        .where((m) =>
            m is Map &&
            (m['status'] == 'eaten' || m['status'] == 'swap'))
        .length;
    const plannedSlots = 3; // breakfast, lunch, dinner
    final dosesTaken = _asInt((overview['medicine'] as Map?)?['taken']);
    final dosesPlanned = _asInt((overview['medicine'] as Map?)?['total']);
    final waterL = _asDouble(overview['water_liters']);
    final waterTarget = _asDouble(overview['water_target']) == 0
        ? 2.5
        : _asDouble(overview['water_target']);
    final waterLitersStr =
        waterL <= 0 ? '—' : '${waterL.toStringAsFixed(1)} / ${waterTarget.toStringAsFixed(1)} L';
    final sugar = overview['sugar'] as Map?;
    final glucoseStr = sugar == null
        ? '—'
        : _formatSugar(sugar);
    final bp = overview['bp'] as Map?;
    final bpStr = bp == null ? '—' : _formatBp(bp);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Overline(text: 'আজকের সারাংশ'),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            // 1.7 keeps both the value and the hint visible without
            // truncating the Bangla label.
            childAspectRatio: 1.7,
            children: [
              _StatCard(
                icon: Icons.restaurant_rounded,
                label: 'খাবার',
                value: '$eatenCount / $plannedSlots',
                color: AppColors.cyan,
                hint: 'গ্রহণকৃত খাবার',
              ),
              _StatCard(
                icon: Icons.medication_rounded,
                label: 'ওষুধ',
                value: dosesPlanned == 0
                    ? '$dosesTaken'
                    : '$dosesTaken / $dosesPlanned',
                color: AppColors.mintDeep,
                hint: dosesPlanned == 0
                    ? 'আজ কোনো ডোজ নেই'
                    : 'গ্রহণ করা ডোজ',
              ),
              _StatCard(
                icon: Icons.water_drop_rounded,
                label: 'পানি',
                value: waterLitersStr,
                color: AppColors.cyan,
                hint: 'লক্ষ্য ${waterTarget.toStringAsFixed(1)} L',
              ),
              _StatCard(
                icon: Icons.monitor_heart_outlined,
                label: 'সুগার / বিপি',
                value: glucoseStr,
                color: AppColors.violetDeep,
                hint: bpStr == '—' ? 'গ্লুকোজ mmol/L' : 'বিপি $bpStr mmHg',
              ),
            ],
          ),
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
  final String label;
  final String value;
  final String hint;
  final Color color;
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.hint,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
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
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          // Replace Spacer() with a fixed gap so values never get
          // pushed off the card on tall labels / short labels.
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            hint,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textDim,
              fontWeight: FontWeight.w500,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------
// At-risk callouts — only shown when there's an actionable insight
// ------------------------------------------------------------------

class _AtRiskCallouts extends StatelessWidget {
  final Map<String, dynamic> overview;
  const _AtRiskCallouts({required this.overview});

  @override
  Widget build(BuildContext context) {
    // SQL shape: `meals[]` array, `medicine.{taken,total,taken_pct}`,
    // `sugar.{fasting_mmol, postprandial_mmol, random_mmol, hba1c_percent}`,
    // `water_liters`. Derive callouts from these keys.
    final notes = <_Callout>[];
    final meals = (overview['meals'] as List?) ?? const [];
    final offPlan = meals
        .where((m) => m is Map && m['status'] == 'off_plan')
        .length;
    final med = overview['medicine'] as Map?;
    final dosesTaken = _asInt(med?['taken']);
    final dosesPlanned = _asInt(med?['total']);
    final missedDoses =
        dosesPlanned > 0 ? (dosesPlanned - dosesTaken).clamp(0, dosesPlanned) : 0;
    final sugar = overview['sugar'] as Map?;
    final fasting =
        sugar == null ? null : _OverviewGrid._asDouble(sugar['fasting_mmol']);
    final post = sugar == null
        ? null
        : _OverviewGrid._asDouble(sugar['postprandial_mmol']);
    // Crude thresholds aligned with Bangladesh diabetic guidance:
    // fasting > 7.0 mmol/L or 2-hr post-prandial > 11.1 mmol/L.
    final glucoseHigh = (fasting != null && fasting > 7.0) ||
        (post != null && post > 11.1);
    final waterL = _OverviewGrid._asDouble(overview['water_liters']);
    final noActivity = meals.isEmpty && dosesTaken == 0 && waterL <= 0;

    if (missedDoses > 0) {
      notes.add(_Callout(
        icon: Icons.warning_amber_rounded,
        color: AppColors.rose,
        title: 'বাদ পড়া ওষুধ',
        body: 'আজ $missedDosesটি ডোজ সময়মতো নেওয়া হয়নি',
      ));
    }
    if (offPlan > 0) {
      notes.add(_Callout(
        icon: Icons.no_food_rounded,
        color: AppColors.amber,
        title: 'পরিকল্পনার বাইরে খাবার',
        body: 'আজ $offPlanটি খাবার পরিকল্পনা মেনে হয়নি',
      ));
    }
    if (glucoseHigh) {
      notes.add(_Callout(
        icon: Icons.monitor_heart_outlined,
        color: AppColors.rose,
        title: 'উচ্চ গ্লুকোজ',
        body: 'সর্বশেষ রিডিং লক্ষ্যমাত্রার উপরে',
      ));
    }
    if (noActivity) {
      notes.add(_Callout(
        icon: Icons.notifications_active_outlined,
        color: AppColors.violet,
        title: 'আজ কোনো কার্যকলাপ নেই',
        body: 'খাবার বা ওষুধ এখনো লগ করা হয়নি',
      ));
    }

    if (notes.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Overline(text: 'মনোযোগ দরকার'),
          const SizedBox(height: 6),
          ...notes.map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: c,
              )),
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
}

class _Callout extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  const _Callout({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
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

// ------------------------------------------------------------------
// Activity feed
// ------------------------------------------------------------------

class _FeedRow extends StatelessWidget {
  final CaregiverObservation obs;
  const _FeedRow({required this.obs});

  @override
  Widget build(BuildContext context) {
    final tone = _toneColor(obs.tone);
    final icon = _iconFor(obs.kind);
    final time = _formatTime(obs.occurredAt);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: tone),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  obs.summaryBn,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                    height: 1.3,
                  ),
                ),
                if (obs.detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _formatDetail(obs.kind, obs.detail!),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textMuted,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Constrain width so the timestamp can't consume more
          // than ~56 dp on narrow devices.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 56),
            child: Text(
              time,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textDim,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _toneColor(String tone) {
    switch (tone) {
      case 'good':
        return AppColors.mintDeep;
      case 'warn':
        return AppColors.amber;
      case 'bad':
        return AppColors.rose;
      default:
        return AppColors.violet;
    }
  }

  IconData _iconFor(CaregiverObservationKind k) {
    switch (k) {
      case CaregiverObservationKind.meal:
        return Icons.restaurant_rounded;
      case CaregiverObservationKind.medicine:
        return Icons.medication_rounded;
      case CaregiverObservationKind.water:
        return Icons.water_drop_rounded;
      case CaregiverObservationKind.workout:
        return Icons.fitness_center_rounded;
    }
  }

  /// Render the jsonb `detail` payload as a single short Bangla
  /// caption. Falls back gracefully when fields are missing.
  static String _formatDetail(
      CaregiverObservationKind kind, Map<String, dynamic> detail) {
    switch (kind) {
      case CaregiverObservationKind.meal:
        final slot = detail['meal_slot']?.toString();
        final food = detail['food_name_bn']?.toString();
        if (slot != null && food != null && food.isNotEmpty) {
          return '$slot • $food';
        }
        return food ?? slot ?? '';
      case CaregiverObservationKind.medicine:
        final status = detail['status']?.toString();
        final scheduled = detail['scheduled_time']?.toString();
        if (status != null && scheduled != null) {
          return '$status • $scheduled';
        }
        return status ?? scheduled ?? '';
      case CaregiverObservationKind.water:
        final liters = detail['liters'];
        return liters == null ? '' : '${liters} লিটার';
      case CaregiverObservationKind.workout:
        final done = detail['completed_items'];
        final total = detail['total_items'];
        if (done != null && total != null) {
          return '$done / $total সম্পন্ন';
        }
        final dur = detail['duration_seconds'];
        if (dur != null) return '$dur সেকেন্ড';
        return '';
    }
  }

  String _formatTime(DateTime utc) {
    final local = utc.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

class _FeedEmpty extends StatelessWidget {
  const _FeedEmpty();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        children: [
          Icon(
            Icons.event_note_rounded,
            size: 40,
            color: AppColors.textDim.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 8),
          const Text(
            'এখনো কোনো কার্যকলাপ নেই',
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

// ------------------------------------------------------------------
// Shared bits
// ------------------------------------------------------------------

class _Overline extends StatelessWidget {
  final String text;
  const _Overline({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.violet,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            // letterSpacing breaks Bengali conjuncts — keep at 0.
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.textMuted,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  const _Avatar({required this.name});

  @override
  Widget build(BuildContext context) {
    final initials = _initials(name);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  String _initials(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return 'র';
    final parts = s.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts[0].isNotEmpty ? parts[0][0] : '') +
          (parts[1].isNotEmpty ? parts[1][0] : '');
    }
    return s.characters.first.toUpperCase();
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
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
