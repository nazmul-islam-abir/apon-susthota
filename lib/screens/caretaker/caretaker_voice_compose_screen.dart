/// Caretaker voice-message compose screen.
///
/// Flow:
///   1. Pick a timezone (default Asia/Dhaka).
///   2. Pick a wall-clock time.
///   3. Record a voice clip via [VoiceRecorderButton].
///   4. Optionally add a short caption.
///   5. Tap "শিডিউল করুন" → uploads to Supabase Storage + inserts
///      a `voice_schedules` row. The pg_cron job in 61_*.sql will
///      materialize it into a `voice_messages` row addressed to the
///      patient at [deliverAt].
///
/// If [threadId] is provided we route to a reply path. By default
/// the reply is sent by the caretaker (calls caretaker_send_voice_reply).
/// If [isPatientReply] is true, the reply is sent by the patient
/// (direct insert gated by the sender-only RLS policy on
/// voice_messages) — used when the patient taps "উত্তর দিন" in their
/// own thread view.
library;

import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../services/voice_recorder_service.dart';
import '../../services/voice_service.dart';
import '../../services/voice_upload_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/time_format.dart';
import '../../widgets/bd_date_picker.dart';
import '../../widgets/bd_time_picker.dart';
import '../../widgets/timezone_picker.dart';
import '../../widgets/voice_recorder_button.dart';
import '../../widgets/voice_send_dialog.dart';

class CaretakerVoiceComposeScreen extends StatefulWidget {
  final String patientUserId;
  final UserProfile? patientProfile;
  final String? threadId;

  /// True when this compose screen was opened by the patient to
  /// reply to a caretaker's voice in a thread. When true, [_submit]
  /// uses the direct patient insert path (VoiceService.patientReply)
  /// instead of the caretaker passthrough RPC, which would otherwise
  /// reject the call with "No active link to this patient" because
  /// the patient isn't a caretaker of themselves.
  final bool isPatientReply;

  const CaretakerVoiceComposeScreen({
    super.key,
    required this.patientUserId,
    this.patientProfile,
    this.threadId,
    this.isPatientReply = false,
  });

  @override
  State<CaretakerVoiceComposeScreen> createState() =>
      _CaretakerVoiceComposeScreenState();
}

class _CaretakerVoiceComposeScreenState
    extends State<CaretakerVoiceComposeScreen> {
  TimezoneOption _tz = findTimezone('Asia/Dhaka');
  TimeOfDay _time = const TimeOfDay(hour: 20, minute: 0);

  /// Calendar date the caretaker is scheduling for. Defaults to
  /// today (device local tz) so the simple "send tonight" path
  /// stays one tap away. The picker lets them roll forward to any
  /// date within a year via [showBdDatePicker].
  late DateTime _date;

  String? _recordedPath;
  int _recordedDurationMs = 0;
  final TextEditingController _captionCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Initialize wall-clock to one hour from now, rounded up to the
    // nearest minute so the cron always sees a future deliver_at.
    final now = DateTime.now();
    _time = TimeOfDay(
      hour: (now.hour + 1) % 24,
      minute: now.minute,
    );
    _date = DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    // Discard any in-progress recording.
    VoiceRecorderService.instance.discard();
    super.dispose();
  }

  bool get _isReply => widget.threadId != null;

  Future<void> _pickTime() async {
    // Use the custom Bangladesh picker: explicit AM/PM toggle, no
    // 24-hour dial, no Bangla-numeral confusion, and no overflow on
    // small phones (the issue the screenshot showed on the previous
    // Material showTimePicker implementation).
    final picked = await showBdTimePicker(
      context,
      initial: _time,
      titleBn: 'পাঠানোর সময়',
      accent: AppColors.cyan,
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _pickDate() async {
    final picked = await showBdDatePicker(
      context,
      initial: _date,
      titleBn: 'পাঠানোর তারিখ',
      accent: AppColors.cyan,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTz() async {
    final picked = await showTimezonePicker(context, selected: _tz);
    if (picked != null) setState(() => _tz = picked);
  }

  /// Convert the picked (date, tz, time) into a UTC [DateTime] the
  /// server-side cron can materialize against.
  ///
  /// The math:
  ///   `utc = wall_clock_in_tz - tz.offset`
  /// where `tz.offset` is the *positive* duration east of UTC. Note
  /// `Duration(hours: -8)` is a valid Duration in Dart, so a simple
  /// `subtract` correctly handles western hemispheres.
  ///
  /// Subtle but important: we construct the wall-clock moment with
  /// [DateTime.utc], not [DateTime]. A plain `DateTime(y, m, d, h, m)`
  /// is created in the *device's* local timezone — so for a Dhaka
  /// caretaker it carries an internal offset of +06:00. Subtracting
  /// `_tz.offset` (+06:00) from a Dhaka-local moment yields another
  /// Dhaka-local moment shifted 6 hours earlier in *wall-clock*
  /// terms, which is NOT the UTC instant we want. Using
  /// `DateTime.utc(...)` makes the moment already UTC, so the same
  /// subtract correctly produces the real UTC instant.
  ///
  /// Returns `null` when the resulting UTC moment has already
  /// passed — the submit button is disabled in that case so the
  /// caretaker is forced to pick a future time.
  DateTime? _computeDeliverAtUtc() {
    final nowUtc = DateTime.now().toUtc();

    // Treat the wall-clock (date + time-of-day) as if it were
    // already UTC, then shift by the picked tz's east-of-UTC
    // offset. The result is the actual UTC instant we need.
    final wallClockAsUtc = DateTime.utc(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );
    final utc = wallClockAsUtc.subtract(_tz.offset);

    // Padding: cron runs every minute, so 60s gives a generous
    // buffer for the round-trip — and lets us safely show the user
    // a friendly "পাঠানো হবে রাত 8:00 এ" before they tap. Compare
    // both sides in UTC so the device's local timezone can't fool
    // us.
    if (!utc.isAfter(nowUtc.add(const Duration(minutes: 1)))) {
      return null;
    }
    return utc;
  }

  bool get _canSubmit {
    if (_recordedPath == null) return false;
    if (_isReply) return true;
    return _computeDeliverAtUtc() != null;
  }

  /// Bangla label for the [_date] tile — e.g. "আজ", "আগামীকাল",
  /// "পরশু", or "৫ সেপ্টেম্বর" for any further-out date. Helps the
  /// caretaker confirm at a glance that they scheduled the right
  /// day.
  String _datePreviewBn() {
    final today = DateTime.now();
    final t = DateTime(today.year, today.month, today.day);
    final diff = _date.difference(t).inDays;
    if (diff == 0) return 'আজ';
    if (diff == 1) return 'আগামীকাল';
    if (diff == 2) return 'পরশু';
    return formatBanglaDate(_date);
  }

  Future<void> _submit() async {
    if (!_canSubmit || _saving) return;
    setState(() => _saving = true);
    try {
      // 1. Upload the audio bytes.
      final path = await VoiceUploadService.upload(
        localPath: _recordedPath!,
        receiverUserId: widget.patientUserId,
        durationMs: _recordedDurationMs,
      );

      // 2. Either create a schedule or send as a direct reply.
      if (_isReply) {
        // Reply branch routes by *who is sending*. The patient
        // cannot use the caretaker passthrough RPC (their
        // assert_caretaker_can_read check rejects them with "No
        // active link to this patient"), so we send via the
        // sender-only RLS INSERT path instead. The server-side
        // RLS policy on voice_messages (60_*.sql) gates insert
        // on auth.uid() = sender_user_id, which is exactly the
        // patient in this branch.
        if (widget.isPatientReply) {
          await VoiceService.patientReply(
            receiverUserId: widget.patientUserId,
            storagePath: path,
            durationMs: _recordedDurationMs,
            caption: _captionCtrl.text.trim().isEmpty
                ? null
                : _captionCtrl.text.trim(),
            threadId: widget.threadId,
          );
        } else {
          await VoiceService.sendReply(
            patientUserId: widget.patientUserId,
            storagePath: path,
            durationMs: _recordedDurationMs,
            caption: _captionCtrl.text.trim().isEmpty
                ? null
                : _captionCtrl.text.trim(),
            threadId: widget.threadId,
          );
        }
        if (!mounted) return;
        // Show a richer visual confirmation than a plain SnackBar so
        // the caretaker can verify the recipient + voice duration
        // before navigating away. Tapping "সময় বদলান" isn't
        // meaningful for a reply (no schedule), so we don't show that
        // button in reply mode — the dialog only renders the single
        // confirm action.
        final replyResult =
            await VoiceSendDialog.showForReply(
          context: context,
          patient: widget.patientProfile,
          durationMs: _recordedDurationMs,
        );
        if (!mounted) return;
        if (replyResult == VoiceSendDialogResult.confirmed) {
          await VoiceRecorderService.instance.discard();
          if (!mounted) return;
          Navigator.of(context).pop(true);
          return;
        }
        // User dismissed without confirming — stay on screen so they
        // can re-record / change caption. We still discard so the
        // recorder is freed, but we don't pop.
        await VoiceRecorderService.instance.discard();
        if (mounted) setState(() => _saving = false);
        return;
      } else {
        final deliverAt = _computeDeliverAtUtc()!;
        await VoiceService.createSchedule(
          patientUserId: widget.patientUserId,
          storagePath: path,
          durationMs: _recordedDurationMs,
          timezone: _tz.iana,
          deliverAt: deliverAt,
          caption: _captionCtrl.text.trim().isEmpty
              ? null
              : _captionCtrl.text.trim(),
        );

        // Safety-net: if the schedule's deliver time is "effectively
        // now" (within ±2 minutes) and the server-side pg_cron job
        // happens to be missing/broken, the patient would otherwise
        // have to wait up to a full minute (or forever) for their
        // voice. Trigger an instant materialize so the message
        // shows up in their inbox within ~1 second.
        //
        // For schedules further in the future this no-ops on the
        // server (deliver_at > now()), so calling it is always safe.
        await VoiceService.materializeDueNow();

        if (!mounted) return;
        // Show a richer visual confirmation than the previous plain
        // SnackBar — the caretaker can verify the recipient, voice
        // duration, wall-clock time, and live remaining-time countdown
        // before navigating away. Two actions:
        //   * "সময় বদলান" — close the dialog, return to the form so
        //     the user can re-pick a wall-clock. We discard nothing
        //     so they can keep their recording + caption.
        //   * "ঠিক আছে, পাঠান ✓" — pop the compose screen back to the
        //     inbox with `true` so the inbox refreshes its list.
        final scheduleResult =
            await VoiceSendDialog.showForScheduled(
          context: context,
          patient: widget.patientProfile,
          deliverAtUtc: deliverAt,
          tzOffset: _tz.offset,
          tzLabelBn: _tz.labelBn,
          durationMs: _recordedDurationMs,
        );
        if (!mounted) return;
        if (scheduleResult == VoiceSendDialogResult.confirmed) {
          await VoiceRecorderService.instance.discard();
          if (!mounted) return;
          Navigator.of(context).pop(true);
          return;
        }
        // "সময় বদলান" — stay on screen so they can re-pick the
        // delivery time. We keep the recording + caption intact.
        if (mounted) setState(() => _saving = false);
        return;
      }
      // Both reply and scheduled branches above return; no further
      // cleanup needed.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('পাঠাতে সমস্যা হয়েছে: $e'),
          backgroundColor: AppColors.rose,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientName =
        widget.patientProfile?.fullName?.trim().isNotEmpty == true
            ? widget.patientProfile!.fullName!
            : 'রোগী';
    return Scaffold(
      backgroundColor: AppColors.void2,
      appBar: AppBar(
        title: Text(_isReply ? 'ভয়েস উত্তর' : 'ভয়েস মেসেজ তৈরি করুন'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Scrollable form area. Pulled out of the pinned submit
            // bar below so the submit button stays reachable above
            // the keyboard even when the caption TextField is
            // focused. `keyboardDismissBehavior: onDrag` lets the
            // caretaker dismiss the keyboard by scrolling the list
            // — a small but useful gesture for one-handed use.
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  _PatientChip(
                    name: patientName,
                    username: widget.patientProfile?.username,
                  ),
                  const SizedBox(height: 22),
                  if (!_isReply) ...[
                    const _SectionLabel(text: 'টাইমজোন'),
                    const SizedBox(height: 8),
                    _PickerTile(
                      icon: Icons.public_rounded,
                      label: _tz.labelBn,
                      subtitle: '${_tz.cityEn} • ${_tz.iana}',
                      onTap: _pickTz,
                    ),
                    const SizedBox(height: 18),
                    const _SectionLabel(text: 'পাঠানোর তারিখ'),
                    const SizedBox(height: 8),
                    _PickerTile(
                      icon: Icons.calendar_today_rounded,
                      label: _datePreviewBn(),
                      subtitle:
                          '${formatBanglaDate(_date, includeYear: true)} • ${banglaWeekday(_date)}',
                      onTap: _pickDate,
                    ),
                    const SizedBox(height: 18),
                    const _SectionLabel(text: 'পাঠানোর সময়'),
                    const SizedBox(height: 8),
                    _PickerTile(
                      icon: Icons.schedule_rounded,
                      // Show wall-clock time in 12-hour AM/PM for Bangladesh.
                      label: formatTime12h(_time),
                      subtitle: _tz.iana,
                      onTap: _pickTime,
                    ),
                    const SizedBox(height: 22),
                  ],
                  _SectionLabel(
                      text: _isReply
                          ? 'উত্তর রেকর্ড করুন'
                          : 'ভয়েস রেকর্ড করুন'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 26, horizontal: 16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Center(
                      child: VoiceRecorderButton(
                        onStopped: (path) {
                          setState(() {
                            _recordedPath = path;
                            _recordedDurationMs = VoiceRecorderService
                                .instance.currentDurationMs;
                          });
                        },
                        onDuration: (ms) {
                          setState(() => _recordedDurationMs = ms);
                        },
                        onPermissionDenied: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'মাইক ব্যবহারের অনুমতি দরকার। সেটিংস থেকে অনুমতি দিন।'),
                              backgroundColor: AppColors.rose,
                            ),
                          );
                        },
                        onCleared: () {
                          setState(() {
                            _recordedPath = null;
                            _recordedDurationMs = 0;
                          });
                        },
                      ),
                    ),
                  ),
                  if (_recordedPath != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'রেকর্ডিং: ${_fmtMs(_recordedDurationMs)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.cyan,
                          ),
                        ),
                        const SizedBox(width: 12),
                        TextButton.icon(
                          onPressed: _saving
                              ? null
                              : () async {
                                  await VoiceRecorderService.instance
                                      .discard();
                                  setState(() {
                                    _recordedPath = null;
                                    _recordedDurationMs = 0;
                                  });
                                },
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 18),
                          label: const Text('মুছে ফেলুন'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 22),
                  const _SectionLabel(text: 'ক্যাপশন (ঐচ্ছিক)'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _captionCtrl,
                    maxLines: 2,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      hintText: 'আজ রাতে মাকে ভালোবাসা জানাতে...',
                    ),
                  ),
                ],
              ),
            ),
            // Pinned submit bar — lives outside the scroll view so
            // it stays visible above the keyboard. Subtle top
            // border + surface color reads as a sticky action footer
            // without feeling like a separate modal.
            Container(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                12 + MediaQuery.of(context).padding.bottom,
              ),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  top: BorderSide(
                    color: AppColors.line,
                    width: 1,
                  ),
                ),
              ),
              child: FilledButton.icon(
                onPressed: _canSubmit && !_saving ? _submit : null,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.void1,
                        ),
                      )
                    : Icon(_isReply
                        ? Icons.send_rounded
                        : Icons.schedule_send_rounded),
                label: Text(
                  _saving
                      ? 'পাঠানো হচ্ছে...'
                      : (_isReply ? 'উত্তর দিন' : 'শিডিউল করুন'),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientChip extends StatelessWidget {
  final String name;
  final String? username;
  const _PatientChip({required this.name, this.username});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cyan.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: AppColors.cyan,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_rounded,
              color: AppColors.void1,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                if (username != null && username!.trim().isNotEmpty)
                  Text(
                    '@$username',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
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

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.textMuted,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  const _PickerTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.cyan.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: AppColors.cyan),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textDim,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _fmtMs(int ms) {
  final s = (ms / 1000).round();
  final m = s ~/ 60;
  final r = s % 60;
  return '$m:${r.toString().padLeft(2, '0')}';
}
