/// Patient-side voice inbox.
///
/// Lists all incoming voice messages addressed to the current user
/// (sender = an active caretaker OR a patient reply from before — we
/// only show incoming-from-caregiver here; replies go into the
/// thread view). Each row has an inline play button so the patient
/// can listen without opening the thread; tapping the row body
/// still opens the thread for back-and-forth context.
///
/// Realtime refresh is wired through
/// [PatientDataRealtimeMixin] — the SQL setup in
/// 62_voice_realtime.sql adds voice_messages to the
/// supabase_realtime publication, and the
/// `subscribeToPatientDataEvents` binding (extended in
/// supabase_service.dart) filters by patient uid.
library;

import 'package:flutter/material.dart';

import '../../models/voice_message.dart';
import '../../services/supabase_service.dart';
import '../../services/voice_service.dart';
import '../../services/voice_player_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/patient_data_realtime_mixin.dart';
import '../../widgets/voice_message_bubble.dart';
import '../../widgets/voice_play_button.dart';
import '../caretaker/caretaker_voice_compose_screen.dart';

class VoiceInboxScreen extends StatefulWidget {
  const VoiceInboxScreen({super.key});

  @override
  State<VoiceInboxScreen> createState() => _VoiceInboxScreenState();
}

class _VoiceInboxScreenState extends State<VoiceInboxScreen>
    with PatientDataRealtimeMixin<VoiceInboxScreen> {
  bool _loading = true;
  List<VoiceMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    attachPatientDataRealtime(
      SupabaseService.currentUser!.id,
      _refresh,
    );
    _refresh();
  }

  @override
  void dispose() {
    disposePatientDataRealtime();
    VoicePlayerService.instance.stop();
    super.dispose();
  }

  Future<void> _refresh() async {
    final list = await VoiceService.listMyInbox();
    if (!mounted) return;
    setState(() {
      _messages = list;
      _loading = false;
    });
  }

  Future<void> _openThread(VoiceMessage m) async {
    await VoiceService.markPlayed(m.id);
    if (!mounted) return;
    final navigator = Navigator.of(context);
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => VoiceThreadScreen(message: m),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _replyTo(VoiceMessage m) async {
    final messenger = ScaffoldMessenger.of(context);
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CaretakerVoiceComposeScreen(
          // The patient IS the sender here; patientUserId in this
          // compose screen doubles as "receiver of the reply" when
          // threadId is set — which is the original caretaker sender.
          patientUserId: m.senderUserId,
          threadId: m.threadId ?? m.id,
          // Mark this compose session as a patient reply so the
          // submit() path bypasses the caretaker passthrough RPC
          // (which would reject with "No active link to this
          // patient") and inserts directly via the patient RLS
          // policy.
          isPatientReply: true,
        ),
      ),
    );
    if (!mounted) return;
    if (created == true) {
      await _refresh();
    } else {
      // No-op; messenger captured above for symmetry.
      messenger.removeCurrentSnackBar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.void2,
      appBar: AppBar(title: const Text('ভয়েস মেসেজ')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _messages.isEmpty
                  ? const _EmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: _messages.length,
                      itemBuilder: (ctx, i) {
                        final m = _messages[i];
                        return _InboxRow(
                          message: m,
                          onTap: () => _openThread(m),
                          onReply: m.threadId == null && m.isReply
                              ? null
                              : () => _replyTo(m),
                        );
                      },
                    ),
        ),
      ),
    );
  }
}

class _InboxRow extends StatefulWidget {
  final VoiceMessage message;
  final VoidCallback onTap;
  final VoidCallback? onReply;
  const _InboxRow({
    required this.message,
    required this.onTap,
    this.onReply,
  });

  @override
  State<_InboxRow> createState() => _InboxRowState();
}

class _InboxRowState extends State<_InboxRow> {
  /// Mark the message as played the moment the patient first taps
  /// the inline play button — this clears the unread dot and tells
  /// the server (via the realtime stream) that the patient has
  /// heard it. Mirrors what `_openThread` does on row tap.
  bool _playedThisSession = false;

  Future<void> _play() async {
    final m = widget.message;
    if (!_playedThisSession) {
      _playedThisSession = true;
      // Fire-and-forget; if it fails we just don't update the dot.
      // ignore: unawaited_futures
      VoiceService.markPlayed(m.id);
    }
    final current =
        VoicePlayerService.instance.playingUrl.value;
    if (current == m.storagePath) {
      await VoicePlayerService.instance.toggle();
    } else {
      await VoicePlayerService.instance.play(m.storagePath);
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    // Locally clear the "unplayed" affordance once the patient has
    // started playing — the server round-trip is async and the
    // optimistic local update makes the UI feel snappy.
    final showUnplayed = message.isUnplayed && !_playedThisSession;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: showUnplayed
                    ? AppColors.cyan.withValues(alpha: 0.4)
                    : AppColors.line,
                width: showUnplayed ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                // Inline play button — replaces the static avatar.
                // Patients (especially elderly ones) can listen to
                // the voice without opening the thread.
                VoicePlayButton(
                  storagePath: message.storagePath,
                  accent: AppColors.cyan,
                  onTap: _play,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              message.senderLabel,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.text,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.cyan.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              message.durationLabel,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppColors.cyan,
                              ),
                            ),
                          ),
                          if (showUnplayed) ...[
                            const SizedBox(width: 6),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.cyan,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (message.caption != null &&
                          message.caption!.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            message.caption!,
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
                if (widget.onReply != null)
                  IconButton(
                    tooltip: 'উত্তর দিন',
                    onPressed: widget.onReply,
                    icon: const Icon(Icons.reply_rounded),
                    color: AppColors.cyan,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(40, 100, 40, 40),
      children: const [
        _CircleIcon(icon: Icons.mic_none_rounded),
        SizedBox(height: 18),
        Text(
          'এখনও কোন ভয়েস মেসেজ নেই',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.text,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'আপনার পরিবারের কেউ ভয়েস মেসেজ পাঠালে এখানে দেখা যাবে।',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textMuted,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _CircleIcon extends StatelessWidget {
  final IconData icon;
  const _CircleIcon({required this.icon});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 96,
        height: 96,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.cyan.withValues(alpha: 0.10),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 44, color: AppColors.cyan),
      ),
    );
  }
}

/// Full-screen thread view: caretakers' voice(s) → patient's reply →
/// caretakers' follow-up → … in vertical order. Mirrors the
/// messaging-style chat pattern.
class VoiceThreadScreen extends StatefulWidget {
  final VoiceMessage message;
  const VoiceThreadScreen({super.key, required this.message});

  @override
  State<VoiceThreadScreen> createState() => _VoiceThreadScreenState();
}

class _VoiceThreadScreenState extends State<VoiceThreadScreen> {
  bool _loading = true;
  List<VoiceMessage> _thread = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tid = widget.message.threadId ?? widget.message.id;
    final list = await VoiceService.listThread(tid);
    if (!mounted) return;
    setState(() {
      _thread = list.isEmpty ? [widget.message] : list;
      _loading = false;
    });
  }

  Future<void> _reply() async {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    final created = await navigator.push<bool>(
      MaterialPageRoute(
        builder: (_) => CaretakerVoiceComposeScreen(
          patientUserId: widget.message.senderUserId,
          threadId: widget.message.threadId ?? widget.message.id,
          // Same patient-reply routing as _replyTo above.
          isPatientReply: true,
        ),
      ),
    );
    if (!mounted) return;
    if (created == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final myUid = SupabaseService.currentUser?.id;
    return Scaffold(
      backgroundColor: AppColors.void2,
      appBar: AppBar(
        title: const Text('ভয়েস থ্রেড'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _reply,
        backgroundColor: AppColors.cyan,
        foregroundColor: AppColors.void1,
        icon: const Icon(Icons.mic_rounded),
        label: const Text('উত্তর দিন'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                itemCount: _thread.length,
                itemBuilder: (ctx, i) {
                  final m = _thread[i];
                  final mine = m.senderUserId == myUid;
                  return VoiceMessageBubble(message: m, isMine: mine);
                },
              ),
      ),
    );
  }
}

// (No additional anchors required — the imports above are used by
// the composing widgets directly.)
