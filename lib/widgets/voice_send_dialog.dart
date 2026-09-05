/// Voice send confirmation dialog — shown after a caretaker taps
/// "শিডিউল করুন" / "উত্তর দিন" in [CaretakerVoiceComposeScreen].
///
/// Replaces the previous plain `SnackBar` ("পাঠানো হবে …") with a
/// richer visual confirmation the caretaker can verify before they
/// navigate away:
///
///   * Recipient chip (avatar + name + handle).
///   * Voice duration with a small wave icon.
///   * Bangla wall-clock time in 12-hour AM/PM format (using
///     [formatTime12h]) — never 24-hour.
///   * Bangla time-remaining string ("আরো ৩ ঘণ্টা ১২ মিনিট পর")
///     derived from the live countdown.
///
/// Returns `true` if the user tapped "ঠিক আছে, পাঠান" — the caller
/// (compose screen) uses this to decide whether to also pop the
/// compose route.
library;

import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../theme/app_theme.dart';
import '../utils/time_format.dart';

/// Result of the confirmation dialog.
enum VoiceSendDialogResult { confirmed, editTime }

class VoiceSendDialog {
  /// Show the confirmation sheet for a scheduled voice (not a reply).
  ///
  /// [patient]           — recipient (null-safe; falls back to "রোগী").
  /// [deliverAtUtc]      — when the server will deliver the voice.
  /// [tzOffset]          — the picked timezone's offset east of UTC;
  ///                       used to compute the wall-clock the patient
  ///                       will see and the remaining-time string.
  /// [tzLabelBn]         — Bangla label for the timezone ("ঢাকা সময়").
  /// [durationMs]        — recorded voice length, for the duration row.
  static Future<VoiceSendDialogResult> showForScheduled({
    required BuildContext context,
    required UserProfile? patient,
    required DateTime deliverAtUtc,
    required Duration tzOffset,
    required String tzLabelBn,
    required int durationMs,
  }) {
    return _show(
      context: context,
      patient: patient,
      deliverAtUtc: deliverAtUtc,
      tzOffset: tzOffset,
      tzLabelBn: tzLabelBn,
      durationMs: durationMs,
      mode: _Mode.scheduled,
    );
  }

  /// Show the confirmation sheet for an in-thread reply voice.
  /// No scheduling/remaining-time data — the reply goes straight into
  /// the patient's inbox.
  static Future<VoiceSendDialogResult> showForReply({
    required BuildContext context,
    required UserProfile? patient,
    required int durationMs,
  }) {
    return _show(
      context: context,
      patient: patient,
      durationMs: durationMs,
      mode: _Mode.reply,
    );
  }

  static Future<VoiceSendDialogResult> _show({
    required BuildContext context,
    required UserProfile? patient,
    required int durationMs,
    required _Mode mode,
    DateTime? deliverAtUtc,
    Duration? tzOffset,
    String? tzLabelBn,
  }) {
    return showDialog<VoiceSendDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _SendConfirmationSheet(
        patient: patient,
        deliverAtUtc: deliverAtUtc,
        tzOffset: tzOffset,
        tzLabelBn: tzLabelBn,
        durationMs: durationMs,
        mode: mode,
      ),
    ).then((v) => v ?? VoiceSendDialogResult.confirmed);
  }
}

enum _Mode { scheduled, reply }

class _SendConfirmationSheet extends StatelessWidget {
  final UserProfile? patient;
  final DateTime? deliverAtUtc;
  final Duration? tzOffset;
  final String? tzLabelBn;
  final int durationMs;
  final _Mode mode;

  const _SendConfirmationSheet({
    required this.patient,
    required this.deliverAtUtc,
    required this.tzOffset,
    required this.tzLabelBn,
    required this.durationMs,
    required this.mode,
  });

  String _fmtMs(int ms) {
    final s = (ms / 1000).round();
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final patientName = patient?.fullName?.trim().isNotEmpty == true
        ? patient!.fullName!
        : 'রোগী';
    final patientHandle = patient?.username?.trim();

    final isReply = mode == _Mode.reply;
    final isNow = !isReply &&
        VoiceServiceTimeHelpers.isEffectivelyNow(deliverAtUtc);

    // Compute wall-clock + remaining-time in the picked tz.
    String wallClock12h = '';
    String remainingBn = '';
    String dateBn = '';
    if (!isReply && deliverAtUtc != null) {
      final localDateInTz = deliverAtUtc!.add(tzOffset ?? Duration.zero);
      wallClock12h = formatTime12h(
        TimeOfDay(hour: localDateInTz.hour, minute: localDateInTz.minute),
      );
      final r = remainingUntil(deliverAtUtc!);
      remainingBn = formatRemainingBn(r);
      // Use the shared Bangla calendar helper so the dialog and the
      // bd_date_picker stay in sync — no need to maintain a
      // duplicate `monthsBn` array here.
      dateBn = formatBanglaDate(localDateInTz);
    }

    return Dialog(
      backgroundColor: AppColors.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── success badge ──
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.cyan.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppColors.cyan.withValues(alpha: 0.4),
                      width: 2),
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  size: 38,
                  color: AppColors.cyan,
                ),
              ),
            ),
            const SizedBox(height: 14),
            // ── title ──
            Center(
              child: Text(
                isReply
                    ? 'উত্তর পাঠানো হবে'
                    : (isNow ? 'এখনই পৌঁছে যাবে' : 'ভয়েস শিডিউল হয়েছে'),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                isReply
                    ? 'রোগীর কাছে সরাসরি পৌঁছে যাবে'
                    : (isNow
                        ? 'রোগী এখনই শুনতে পাবে'
                        : 'নির্ধারিত সময়ে রোগীর কাছে পৌঁছে যাবে'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.smoke,
                ),
              ),
            ),
            const SizedBox(height: 18),

            // ── recipient row ──
            _Row(
              icon: Icons.person_rounded,
              label: 'প্রাপক',
              value: patientHandle != null && patientHandle.isNotEmpty
                  ? '$patientName  •  @$patientHandle'
                  : patientName,
            ),
            const SizedBox(height: 10),
            // ── duration row ──
            _Row(
              icon: Icons.graphic_eq_rounded,
              label: 'ভয়েসের দৈর্ঘ্য',
              value: _fmtMs(durationMs),
            ),
            if (!isReply) ...[
              const SizedBox(height: 10),
              // ── wall-clock row ──
              _Row(
                icon: Icons.schedule_rounded,
                label: 'পৌঁছানোর সময়',
                value: wallClock12h,
                sub: '$tzLabelBn সময় • $dateBn',
              ),
              const SizedBox(height: 10),
              // ── remaining time row (highlighted) ──
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.cyan.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.cyan.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.timer_outlined,
                        size: 18, color: AppColors.cyan),
                    const SizedBox(width: 8),
                    const Text(
                      'আরো',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.smoke,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isNow ? 'এখনই' : remainingBn,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: AppColors.cyan,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 22),
            // ── actions ──
            Row(
              children: [
                if (!isReply)
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.ink,
                        side: const BorderSide(
                            color: AppColors.graphite, width: 1.2),
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.of(context)
                          .pop(VoiceSendDialogResult.editTime),
                      child: const Text(
                        'সময় বদলান',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                if (!isReply) const SizedBox(width: 10),
                Expanded(
                  flex: isReply ? 1 : 2,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.cyan,
                      foregroundColor: AppColors.paper,
                      padding:
                          const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.of(context)
                        .pop(VoiceSendDialogResult.confirmed),
                    child: Text(
                      isReply ? 'ঠিক আছে ✓' : 'ঠিক আছে, পাঠান ✓',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
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

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? sub;
  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: AppColors.smoke),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.smoke,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink,
                  letterSpacing: -0.2,
                ),
              ),
              if (sub != null && sub!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  sub!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.smoke,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Helpers used by the dialog that don't otherwise live in this file.
/// Kept here so the dialog can be a drop-in widget without dragging in
/// the full VoiceService import surface.
class VoiceServiceTimeHelpers {
  /// Mirror of [VoiceService.isEffectivelyNow] — copied locally to
  /// keep this dialog independent and easy to test.
  static bool isEffectivelyNow(DateTime? deliverAtUtc) {
    if (deliverAtUtc == null) return false;
    final now = DateTime.now().toUtc();
    final diff = deliverAtUtc.difference(now).abs();
    return diff <= const Duration(minutes: 2);
  }
}
