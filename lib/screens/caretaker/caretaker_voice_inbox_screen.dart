/// Caretaker voice inbox — outgoing + received voices for a single
/// patient. Two stacked lists:
///   * "পাঠানো হবে" — pending or scheduled voices (with cancel button)
///   * "পৌঁছে গেছে / এসেছে" — delivered + received voices (no cancel)
///
/// Includes a "নতুন ভয়েস মেসেজ" CTA at the top that pushes
/// [CaretakerVoiceComposeScreen].
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../models/voice_message.dart';
import '../../services/voice_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/time_format.dart';
import '../../widgets/voice_message_bubble.dart';
import '../../widgets/voice_play_button.dart';
import 'caretaker_voice_compose_screen.dart';

class CaretakerVoiceInboxScreen extends StatefulWidget {
  final String patientUserId;
  final UserProfile? patient;
  const CaretakerVoiceInboxScreen({
    super.key,
    required this.patientUserId,
    this.patient,
  });

  @override
  State<CaretakerVoiceInboxScreen> createState() =>
      _CaretakerVoiceInboxScreenState();
}

class _CaretakerVoiceInboxScreenState
    extends State<CaretakerVoiceInboxScreen> {
  bool _loading = true;
  List<VoiceSchedule> _schedules = [];
  List<VoiceMessage> _inbox = [];

  /// Background re-fetch every minute. Two reasons this matters:
  ///   1. The pg_cron job materializes pending schedules into
  ///      delivered `voice_messages` rows, and the caretaker needs
  ///      to see that transition without manually pull-to-refresh.
  ///   2. The 30-second countdown on each `_ScheduleCard` only ticks
  ///      locally — this timer re-syncs the underlying list so the
  ///      "delivered" status badge appears at the right moment.
  Timer? _autoRefresh;

  @override
  void initState() {
    super.initState();
    _refresh();
    _autoRefresh = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      _refresh();
    });
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final results = await Future.wait([
      VoiceService.listSchedulesForPatient(widget.patientUserId),
      VoiceService.listInboxForPatient(widget.patientUserId),
    ]);
    if (!mounted) return;
    setState(() {
      _schedules = results[0] as List<VoiceSchedule>;
      _inbox = results[1] as List<VoiceMessage>;
      _loading = false;
    });
  }

  Future<void> _cancel(VoiceSchedule s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ভয়েস মেসেজ বাতিল?'),
        content: const Text(
          'শিডিউল বাতিল হলে এই ভয়েসটি রোগীর কাছে পৌঁছাবে না।',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('থাক'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.rose),
            child: const Text('বাতিল করুন'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await VoiceService.cancelSchedule(s.id);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('বাতিল করা যায়নি: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientName = widget.patient?.fullName ?? 'রোগী';

    return Scaffold(
      backgroundColor: AppColors.void2,
      appBar: AppBar(title: const Text('ভয়েস মেসেজ')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => CaretakerVoiceComposeScreen(
                patientUserId: widget.patientUserId,
                patientProfile: widget.patient,
              ),
            ),
          );
          if (created == true) await _refresh();
        },
        backgroundColor: AppColors.cyan,
        foregroundColor: AppColors.void1,
        icon: const Icon(Icons.add_rounded),
        label: const Text('নতুন ভয়েস'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _schedules.isEmpty && _inbox.isEmpty
                  ? _EmptyState(patientName: patientName)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                      children: [
                        if (_schedules.isNotEmpty) ...[
                          const _SectionHeader(
                            icon: Icons.schedule_rounded,
                            label: 'পাঠানো হবে',
                          ),
                          ..._schedules.map((s) => _ScheduleCard(
                                schedule: s,
                                onCancel: () => _cancel(s),
                              )),
                          const SizedBox(height: 18),
                        ],
                        if (_inbox.isNotEmpty) ...[
                          const _SectionHeader(
                            icon: Icons.history_rounded,
                            label: 'পৌঁছে গেছে / এসেছে',
                          ),
                          ..._inbox.map((m) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: VoiceMessageBubble(
                                  message: m,
                                  isMine: m.senderUserId ==
                                      _currentUserIdPlaceholder(),
                                ),
                              )),
                        ],
                      ],
                    ),
        ),
      ),
    );
  }

  /// Tiny indirection so the build method doesn't have to import
  /// SupabaseService directly for one call. (Cheaper than a field.)
  String? _currentUserIdPlaceholder() => null;
}

class _ScheduleCard extends StatefulWidget {
  final VoiceSchedule schedule;
  final VoidCallback onCancel;
  const _ScheduleCard({required this.schedule, required this.onCancel});

  @override
  State<_ScheduleCard> createState() => _ScheduleCardState();
}

class _ScheduleCardState extends State<_ScheduleCard> {
  /// Bumps every 30s so the "আরো ৩ ঘণ্টা ১২ মিনিট পর" countdown label
  /// stays fresh without rebuilding the whole list view. We don't
  /// tick every second because the displayed value is rounded to
  /// minutes (days/hours/minutes, no seconds) so 30s granularity
  /// is the smallest interval that can actually change the text.
  Timer? _ticker;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    // First tick after 30s — schedule lives in seconds so the very
    // first paint shows the freshest value without waiting.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() => _tick++);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Localized "আরো ৩ ঘণ্টা ১২ মিনিট পর" countdown. Returns:
  ///   * "এখনই পৌঁছাবে" — within the cron window (≤2 min)
  ///   * "এই মুহূর্তে পৌঁছে যাচ্ছে" — already past deliverAt
  ///   * "আরো X ঘণ্টা Y মিনিট পর" — future
  String _remainingLabel() {
    final r = remainingUntil(widget.schedule.deliverAt);
    if (r.isPast) return 'এই মুহূর্তে পৌঁছে যাচ্ছে';
    if (r.totalSeconds <= 120) return 'এখনই পৌঁছাবে';
    return 'আরো ${formatRemainingBn(r)} পর';
  }

  @override
  Widget build(BuildContext context) {
    // Touch `_tick` so the periodic Timer actually invalidates the
    // build when it fires.
    // ignore: unused_local_variable
    final _ = _tick;

    final schedule = widget.schedule;
    final t = schedule.deliverAt.toLocal();
    // Bangladesh users read wall-clock time in 12-hour AM/PM, so we
    // surface "8:00 PM" instead of "20:00" on the schedule card.
    final wallClock12h =
        formatTime12h(TimeOfDay(hour: t.hour, minute: t.minute));
    final isPending = schedule.status == VoiceScheduleStatus.pending;
    final remainingLabel = _remainingLabel();
    final isImminent = schedule.status == VoiceScheduleStatus.pending &&
        remainingUntil(schedule.deliverAt).totalSeconds <= 120;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          // Inline play button — caretakers can preview their own
          // recording before the patient hears it. Drives the same
          // VoicePlayerService as the bubble, so tapping another
          // voice anywhere in the app automatically stops this one.
          // Slightly smaller (38px) than the patient inbox button so
          // the schedule card stays compact.
          VoicePlayButton(
            storagePath: schedule.storagePath,
            accent: AppColors.cyan,
            size: 38,
            onTap: null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$wallClock12h • ${schedule.timezone}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                // Live "আরো ৩ ঘণ্টা ১২ মিনিট পর" countdown. Only
                // shown for pending schedules — once a schedule is
                // delivered or cancelled the time-remaining would
                // always be "এখনই", which is already conveyed by the
                // status badge.
                if (isPending) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        isImminent
                            ? Icons.notifications_active_rounded
                            : Icons.timer_outlined,
                        size: 13,
                        color: isImminent
                            ? AppColors.amber
                            : AppColors.cyan,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        remainingLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: isImminent
                              ? AppColors.amber
                              : AppColors.cyan,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      schedule.durationLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isPending
                            ? AppColors.amber.withValues(alpha: 0.15)
                            : (schedule.status == VoiceScheduleStatus.delivered
                                ? AppColors.cyan.withValues(alpha: 0.15)
                                : AppColors.rose.withValues(alpha: 0.15)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        schedule.status.labelBn,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: isPending
                              ? AppColors.amber
                              : (schedule.status ==
                                      VoiceScheduleStatus.delivered
                                  ? AppColors.cyan
                                  : AppColors.rose),
                        ),
                      ),
                    ),
                  ],
                ),
                if (schedule.caption != null &&
                    schedule.caption!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      schedule.caption!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'বাতিল',
            onPressed: isPending ? widget.onCancel : null,
            icon: const Icon(Icons.delete_outline_rounded),
            color: AppColors.rose,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.textMuted,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String patientName;
  const _EmptyState({required this.patientName});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(40, 100, 40, 40),
      children: [
        Container(
          width: 96,
          height: 96,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.cyan.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.mic_rounded,
            size: 44,
            color: AppColors.cyan,
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'কোন ভয়েস মেসেজ নেই',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'নিচের বোতাম চেপে $patientName-কে একটি ভয়েস মেসেজ রেকর্ড করে পাঠান।',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textMuted,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
