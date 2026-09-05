/// Horizontal "Voice Messages" banner placed between the dashboard hero
/// and the MoodBanner / MoodSection. Acts as a one-tap entry point into
/// the voice-messaging flow for both patient and caretaker roles.
///
/// • Patient role  → opens [VoiceInboxScreen] (listens to incoming voices,
///                   can record a reply to the sender's thread).
/// • Caretaker role → opens [CaretakerVoiceInboxScreen] for the currently
///                     selected patient. If no patient is selected but
///                     the caretaker has connected patients, a bottom sheet
///                     picker is shown first. If no connected patients at
///                     all, the banner is rendered in an empty/info state
///                     and tapping it shows a SnackBar hint.
///
/// The banner mirrors the dashboard chrome (sharp corners, deep-green
/// gradient with mic icon, animated equalizer bars) so it feels native
/// to the home screen rather than bolted on.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/caretaker_patient_summary.dart';
import '../models/user_profile.dart';
import '../screens/caretaker/caretaker_voice_inbox_screen.dart';
import '../screens/patient/voice_inbox_screen.dart';
import '../services/caretaker_provider.dart';
import '../services/voice_service.dart';
import '../theme/app_theme.dart';

enum VoiceBannerRole { patient, caretaker }

class VoiceMessageBanner extends StatefulWidget {
  final VoiceBannerRole role;
  const VoiceMessageBanner({super.key, required this.role});

  @override
  State<VoiceMessageBanner> createState() => _VoiceMessageBannerState();
}

class _VoiceMessageBannerState extends State<VoiceMessageBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _eqCtrl;
  bool _busy = false;

  // For patient role: unread count badge.
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    // Subtle equalizer animation under the mic — runs forever while the
    // banner is mounted.
    _eqCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);

    if (widget.role == VoiceBannerRole.patient) {
      _refreshUnread();
    }
  }

  @override
  void dispose() {
    _eqCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshUnread() async {
    if (widget.role != VoiceBannerRole.patient) return;
    try {
      final list = await VoiceService.listMyInbox();
      if (!mounted) return;
      // "Unread" = not yet played. VoiceService.listMyInbox returns
      // VoiceMessage items with `playedAt`; we treat `null` as unread.
      final unread = list.where((m) => m.playedAt == null).length;
      setState(() => _unreadCount = unread);
    } catch (_) {
      // Soft-fail — banner still tappable, just no badge.
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Patient tap — straight into the inbox.
  // ─────────────────────────────────────────────────────────────────────
  Future<void> _openPatientInbox() async {
    if (_busy) return;
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const VoiceInboxScreen()),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refreshUnread();
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Caretaker tap — always let the caretaker confirm WHICH patient
  //  gets the voice when more than one is connected. With a single
  //  connected patient we silently use that one (no picker shown).
  //  The session-remembered recipient is held by CaretakerProvider
  //  (`selectedPatient`) so the dashboard's "সংযুক্ত রোগী" tap and
  //  the banner always agree.
  // ─────────────────────────────────────────────────────────────────────
  Future<void> _openCaretakerInbox() async {
    if (_busy) return;
    HapticFeedback.selectionClick();
    final prov = context.read<CaretakerProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    if (prov.patients.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'ভয়েস পাঠাতে প্রথমে “খোঁজা” থেকে একজন রোগী সংযুক্ত করুন।',
          ),
        ),
      );
      return;
    }

    CaretakerPatientSummary? target = prov.selectedPatient;

    // If we have multiple connected patients, ALWAYS force an explicit
    // pick so the caretaker can't accidentally send to the wrong person.
    // With a single patient we trust the only-one choice.
    if (prov.patients.length > 1 || target == null) {
      target = await _pickPatient(
        prov.patients,
        preselectedId: target?.patientUserId,
      );
      if (target == null) return; // user dismissed
      // Persist the pick for this session so taps on the same banner
      // don't re-prompt, while still allowing re-selection via the
      // dashboard's patient list.
      prov.selectPatient(target.patientUserId);
    }

    final picked = target;
    setState(() => _busy = true);
    try {
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => CaretakerVoiceInboxScreen(
            patientUserId: picked.patientUserId,
            patient: picked.fullName.isNotEmpty
                ? UserProfile(fullName: picked.fullName)
                : null,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<CaretakerPatientSummary?> _pickPatient(
    List<CaretakerPatientSummary> patients, {
    String? preselectedId,
  }) async {
    return showModalBottomSheet<CaretakerPatientSummary>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      isScrollControlled: true,
      builder: (ctx) {
        final l = AppLocalizations.of(ctx);
        final isBn = l?.localeName == 'bn';
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drag handle.
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
                  child: Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.lineStrong,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.mic_rounded,
                        color: AppColors.svcHero,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isBn
                              ? 'কোন রোগীকে ভয়েস পাঠাবেন?'
                              : 'Which patient should receive the voice?',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    isBn
                        ? 'আপনার ${patients.length} জন সংযুক্ত রোগী আছে — একজনকে বাছাই করুন।'
                        : 'You have ${patients.length} connected patients — pick one.',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.smoke,
                    ),
                  ),
                ),
                const Divider(height: 1, color: AppColors.line),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: patients.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: AppColors.line),
                    itemBuilder: (_, i) {
                      final p = patients[i];
                      final rawName = p.fullName.trim();
                      final name = rawName.isEmpty
                          ? (isBn ? 'রোগী' : 'Patient')
                          : rawName;
                      final isSelected = preselectedId == p.patientUserId;
                      return ListTile(
                        selected: isSelected,
                        selectedTileColor:
                            AppColors.svcCategoryBg.withValues(alpha: 0.6),
                        leading: CircleAvatar(
                          backgroundColor: isSelected
                              ? AppColors.svcHero
                              : AppColors.svcCategoryBg,
                          child: Text(
                            name.isEmpty ? '?' : name[0].toUpperCase(),
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : AppColors.svcHero,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: Text(
                          isBn
                              ? 'ভয়েস মেসেজ পাঠান'
                              : 'Send a voice message',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(
                                Icons.check_circle_rounded,
                                color: AppColors.svcHero,
                              )
                            : const Icon(
                                Icons.chevron_right_rounded,
                                color: AppColors.lineStrong,
                              ),
                        onTap: () => Navigator.of(ctx).pop(p),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          switch (widget.role) {
            case VoiceBannerRole.patient:
              _openPatientInbox();
              break;
            case VoiceBannerRole.caretaker:
              _openCaretakerInbox();
              break;
          }
        },
        borderRadius: BorderRadius.zero,
        child: Container(
          height: 78,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.svcHero, // dark forest green
                AppColors.svcHeroAccent, // brighter lime accent
              ],
            ),
            borderRadius: BorderRadius.zero,
            boxShadow: [
              BoxShadow(
                color: AppColors.svcHero.withValues(alpha: 0.18),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Faint waveform decoration on the right side.
              Positioned.fill(
                child: ClipRect(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Opacity(
                      opacity: 0.18,
                      child: Icon(
                        Icons.graphic_eq_rounded,
                        size: 96,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Mic badge with animated equalizer bars.
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.zero,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.32),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Icon(
                          Icons.mic_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                        Positioned(
                          right: 4,
                          bottom: 6,
                          child: _AnimatedEqBars(controller: _eqCtrl),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Title + subtitle.
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                _title(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.1,
                                ),
                              ),
                            ),
                            if (widget.role == VoiceBannerRole.patient &&
                                _unreadCount > 0) ...[
                              const SizedBox(width: 8),
                              _UnreadBadge(count: _unreadCount),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _subtitle(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            height: 1.15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.zero,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _ctaLabel(),
                          style: const TextStyle(
                            color: AppColors.svcHero,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: AppColors.svcHero,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _title() {
    final l = AppLocalizations.of(context);
    final isBn = l?.localeName == 'bn';
    switch (widget.role) {
      case VoiceBannerRole.patient:
        return isBn ? 'ভয়েস মেসেজ' : 'Voice Messages';
      case VoiceBannerRole.caretaker:
        return isBn ? 'রোগীকে ভয়েস পাঠান' : 'Send Voice to Patient';
    }
  }

  String _subtitle() {
    final l = AppLocalizations.of(context);
    final isBn = l?.localeName == 'bn';
    switch (widget.role) {
      case VoiceBannerRole.patient:
        if (_unreadCount > 0) {
          return isBn
              ? '$_unreadCountটি নতুন ভয়েস অপেক্ষা করছে'
              : '$_unreadCount new voice${_unreadCount == 1 ? '' : 's'} waiting';
        }
        return isBn
            ? 'পরিচর্যাকারীর ভয়েস শুনুন ও উত্তর দিন'
            : 'Listen & reply to caretaker voices';
      case VoiceBannerRole.caretaker:
        // If a session-remembered recipient is set, surface that name
        // on the banner so the caretaker knows exactly who they're
        // about to send the voice to before tapping.
        final prov = context.read<CaretakerProvider>();
        final selected = prov.selectedPatient;
        if (selected != null) {
          final name = selected.fullName.trim().isEmpty
              ? (isBn ? 'রোগী' : 'Patient')
              : selected.fullName.trim();
          return isBn
              ? '$name-কে পাঠাতে চাপ দিন'
              : 'Tap to send to $name';
        }
        return isBn
            ? 'রেকর্ড করুন, সময় ঠিক করুন, পাঠান'
            : 'Record, schedule & send';
    }
  }

  String _ctaLabel() {
    final l = AppLocalizations.of(context);
    final isBn = l?.localeName == 'bn';
    switch (widget.role) {
      case VoiceBannerRole.patient:
        return isBn ? 'শুনুন' : 'Open';
      case VoiceBannerRole.caretaker:
        return isBn ? 'পাঠান' : 'Send';
    }
  }
}

class _UnreadBadge extends StatelessWidget {
  final int count;
  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.rose,
        borderRadius: BorderRadius.zero,
      ),
      alignment: Alignment.center,
      child: Text(
        count > 9 ? '9+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          height: 1.0,
        ),
      ),
    );
  }
}

class _AnimatedEqBars extends StatelessWidget {
  final AnimationController controller;
  const _AnimatedEqBars({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (ctx, _) {
        final t = controller.value; // 0..1
        final h1 = 4 + 6 * (1 - (t - 0).abs());
        final h2 = 4 + 6 * (1 - (t - 0.5).abs());
        final h3 = 4 + 6 * (1 - (t - 1).abs());
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _bar(h1.clamp(4.0, 10.0)),
            const SizedBox(width: 1.5),
            _bar(h2.clamp(4.0, 10.0)),
            const SizedBox(width: 1.5),
            _bar(h3.clamp(4.0, 10.0)),
          ],
        );
      },
    );
  }

  Widget _bar(double h) {
    return Container(
      width: 2.5,
      height: h,
      color: Colors.white,
    );
  }
}
