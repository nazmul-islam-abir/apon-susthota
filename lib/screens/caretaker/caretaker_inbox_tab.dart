/// Caretaker "ইনবক্স" tab — link-request inbox + live patient activity feed.
///
/// Two stacked sections:
///   1. Link requests — the legacy "আপনার অনুরোধ" inbox (still handled
///      via CaretakerProvider).
///   2. Live activity feed — every meal / water dose / medicine /
///      workout that the patient just logged, populated from
///      `get_caretaker_recent_activities` and refreshed through
///      `PatientDataRealtimeMixin` (the same channel that powers the
///      "আজ" tab).
///
/// The mixin is wired when there is a currently-selected patient —
/// otherwise the inbox just shows pending requests with an empty
/// feed (the caretaker can pick a patient from "রোগী" tab first).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/caregiver_observation.dart';
import '../../models/caretaker_link.dart';
import '../../services/app_errors.dart';
import '../../services/caretaker_provider.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/relative_time.dart';
import '../../widgets/mono_widgets.dart';
import '../../widgets/patient_data_realtime_mixin.dart';

class CaretakerInboxTab extends StatefulWidget {
  const CaretakerInboxTab({super.key});

  @override
  State<CaretakerInboxTab> createState() => _CaretakerInboxTabState();
}

class _CaretakerInboxTabState extends State<CaretakerInboxTab>
    with PatientDataRealtimeMixin {
  List<CaregiverObservation> _activity = const [];
  bool _loadingActivity = false;
  String? _attachedPatientId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumeEvents();
      _attachIfNeeded();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The caretaker may have switched the active patient from the
    // "রোগী" tab — re-target the realtime channel accordingly.
    WidgetsBinding.instance.addPostFrameCallback((_) => _attachIfNeeded());
  }

  @override
  void dispose() {
    disposePatientDataRealtime();
    super.dispose();
  }

  /// Wire the realtime channel to whichever patient is currently
  /// selected. No-op if there is no selection yet (the caretaker
  /// hasn't picked a patient).
  void _attachIfNeeded() {
    if (!mounted) return;
    final pid = context.read<CaretakerProvider>().selectedPatientUserId;
    if (pid == null) {
      // No patient yet — keep the activity feed empty.
      if (_activity.isNotEmpty) setState(() => _activity = const []);
      _attachedPatientId = null;
      return;
    }
    if (_attachedPatientId != pid) {
      attachPatientDataRealtime(pid, _loadActivity);
      _attachedPatientId = pid;
    }
    _loadActivity();
  }

  Future<void> _loadActivity() async {
    if (!mounted) return;
    final pid = context.read<CaretakerProvider>().selectedPatientUserId;
    if (pid == null) return;
    setState(() => _loadingActivity = true);
    try {
      final fresh =
          await SupabaseService.getCaretakerRecentActivities(patientUserId: pid, limit: 30);
      if (!mounted) return;
      setState(() {
        _activity = fresh;
        _loadingActivity = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingActivity = false);
    }
  }

  void _consumeEvents() {
    if (!mounted) return;
    final prov = context.read<CaretakerProvider>();
    final ev = prov.consumeLastEvent();
    if (ev == null) return;
    final isAccepted = ev.kind == 'accepted';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isAccepted ? AppColors.svcHero : AppColors.amber,
        content: Text(isAccepted ? '✅ ${ev.otherName} আপনার অনুরোধ গ্রহণ করেছেন' : '⏳ ${ev.otherName} এখনো সাড়া দেননি', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeEvents());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.svcCategoryBg,
      body: Consumer<CaretakerProvider>(
        builder: (context, prov, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _consumeEvents());
          final pending = prov.pending;
          return RefreshIndicator(
            color: AppColors.svcHero,
            onRefresh: () async {
              await prov.refreshPending();
              await _loadActivity();
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              slivers: [
                _buildHero(prov),
                const SliverToBoxAdapter(child: SizedBox(height: 22)),
                SliverToBoxAdapter(child: _buildSectionTitle('পাঠানো অনুরোধ', 'অপেক্ষমাণ')),
                if (prov.loadingPending && pending.isEmpty)
                  const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: AppColors.svcHero)))
                else if (pending.isEmpty)
                  const SliverToBoxAdapter(child: _EmptyState())
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    sliver: SliverList.separated(
                      itemCount: pending.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _PendingRow(request: pending[i], onWithdraw: () => _confirmWithdraw(context, pending[i])),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 22)),
                SliverToBoxAdapter(child: _buildSectionTitle('রোগীর লাইভ কার্যকলাপ', 'খাবার • ওষুধ • পানি • ব্যায়াম')),
                if (prov.selectedPatientUserId == null)
                  const SliverToBoxAdapter(child: _ActivityHint())
                else if (_loadingActivity && _activity.isEmpty)
                  const SliverToBoxAdapter(child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator(color: AppColors.svcHero)),
                  ))
                else if (_activity.isEmpty)
                  const SliverToBoxAdapter(child: _ActivityEmpty())
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 140),
                    sliver: SliverList.separated(
                      itemCount: _activity.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _ActivityRow(obs: _activity[i]),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHero(CaretakerProvider prov) {
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
                const SafeArea(bottom: false, child: SizedBox(height: 20)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('আপনার ইনবক্স', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -1)),
                      const SizedBox(height: 8),
                      Text(
                        'মোট ${prov.pending.length}টি পেন্ডিং অনুরোধ',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, fontWeight: FontWeight.w800),
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

  Future<void> _confirmWithdraw(BuildContext context, CaretakerLink link) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('অনুরোধ প্রত্যাহার?', style: TextStyle(fontWeight: FontWeight.w900)),
        content: const Text('এই রোগীর সাথে সংযোগ অনুরোধ বাতিল করতে চান?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('না')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), style: TextButton.styleFrom(foregroundColor: AppColors.rose), child: const Text('হ্যাঁ, প্রত্যাহার করুন', style: TextStyle(fontWeight: FontWeight.w900))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await context.read<CaretakerProvider>().revoke(link.id ?? '');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(BanglaError.toBangla(e)), backgroundColor: AppColors.rose));
    }
  }
}

class _PendingRow extends StatelessWidget {
  final CaretakerLink request;
  final VoidCallback onWithdraw;
  const _PendingRow({required this.request, required this.onWithdraw});

  @override
  Widget build(BuildContext context) {
    final rel = request.caretakerRelationship ?? 'পরিচর্যাকারী';
    final tsStr = request.requestedAt == null ? '' : RelativeTime.format(request.requestedAt!);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line, width: 1.2)),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: AppColors.svcCategoryBg, borderRadius: BorderRadius.zero),
            child: const Icon(Icons.hourglass_top_rounded, color: AppColors.svcHero, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rel, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.ink)),
                if (tsStr.isNotEmpty) Text(tsStr, style: const TextStyle(fontSize: 12, color: AppColors.smoke, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          MonoButton(
            label: 'প্রত্যাহার',
            onPressed: onWithdraw,
            color: AppColors.rose,
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.send_rounded, color: AppColors.lineStrong, size: 56),
          SizedBox(height: 12),
          Text('এখনো কোনো অনুরোধ পাঠানো হয়নি', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.ink)),
          SizedBox(height: 6),
          Text('“খোঁজা” ট্যাব থেকে অনুরোধ পাঠান।', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.smoke)),
        ],
      ),
    );
  }
}

/// One row in the live activity feed — mirrors the same visual
/// language as `_FeedRow` in `caretaker_today_tab.dart` so the
/// caretaker sees the same icon / colour for a meal here and on
/// the "আজ" tab.
class _ActivityRow extends StatelessWidget {
  final CaregiverObservation obs;
  const _ActivityRow({required this.obs});

  @override
  Widget build(BuildContext context) {
    final tone = _toneColor(obs.tone);
    final icon = _iconFor(obs.kind);
    final time = _formatTime(obs.occurredAt);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.line, width: 1.0),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.08),
              border: Border.all(color: tone.withValues(alpha: 0.15)),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: tone),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(obs.summaryBn, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.ink, height: 1.2)),
                if (obs.detail != null) ...[
                  const SizedBox(height: 3),
                  Text(_formatDetail(obs.kind, obs.detail!), style: TextStyle(fontSize: 12, color: AppColors.smoke.withValues(alpha: 0.8), fontWeight: FontWeight.w700)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
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

  String _formatTime(DateTime utc) {
    final local = utc.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
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
}

class _ActivityEmpty extends StatelessWidget {
  const _ActivityEmpty();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      child: Column(
        children: [
          Icon(Icons.event_note_rounded, size: 44, color: AppColors.lineStrong),
          SizedBox(height: 10),
          Text('এখনো কোনো লগ নেই', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.smoke)),
          SizedBox(height: 4),
          Text('রোগী কিছু লগ করলে এখানে দেখা যাবে।', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.smoke)),
        ],
      ),
    );
  }
}

class _ActivityHint extends StatelessWidget {
  const _ActivityHint();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.svcCategoryBg,
          border: Border.all(color: AppColors.line, width: 1.0),
        ),
        child: const Row(
          children: [
            Icon(Icons.lightbulb_outline_rounded, color: AppColors.svcHero, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '“রোগী” ট্যাব থেকে একজনকে বেছে নিলে এই ইনবক্সে তাঁর লাইভ খাবার/ওষুধ/পানি/ব্যায়াম লগ দেখতে পাবেন।',
                style: TextStyle(fontSize: 12.5, color: AppColors.smoke, height: 1.4, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
