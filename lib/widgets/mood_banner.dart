/// Horizontal "Today's mood" banner that sits between the hero and
/// the "পরিষেবা বিভাগ" section on the dashboard.
///
/// Redesigned to match the high-fidelity Nexora aesthetic:
///   • Dark forest-green background with technical borders.
///   • Sharp corners (Radius 0) to match the new design system.
///   • Larger interactive elements for professional visibility.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/mood_entry.dart';
import '../services/app_events.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'mono_widgets.dart';
import 'mood_health_sheet.dart';
import 'mood_record_button.dart';

class MoodBanner extends StatefulWidget {
  final VoidCallback? onLogSaved;
  const MoodBanner({super.key, this.onLogSaved});

  @override
  State<MoodBanner> createState() => _MoodBannerState();
}

class _MoodBannerState extends State<MoodBanner> {
  MoodEntry? _today;
  bool _loading = true;
  bool _editing = false;
  bool _busy = false;

  static const List<MoodKind> _allKinds = MoodKind.values;

  @override
  void initState() {
    super.initState();
    _refresh();
    AppEvents.moodChanged.addListener(_refresh);
  }

  @override
  void dispose() {
    AppEvents.moodChanged.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    try {
      final entry = await SupabaseService.getTodayMood();
      if (!mounted) return;
      setState(() { _today = entry; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _enterEditMode() {
    if (_busy) return;
    HapticFeedback.selectionClick();
    setState(() => _editing = true);
  }

  Future<void> _onRecorded(String kindCode) async {
    if (!mounted || _busy) return;
    final mood = moodKindFromCode(kindCode);
    final existing = _today;
    setState(() => _busy = true);
    try {
      final result = await MoodHealthSheet.show(context, initialMood: mood, existing: existing);
      if (!mounted) return;
      if (result != null) {
        await SupabaseService.logMood(
          mood: result.mood,
          energyLevel: result.energyLevel,
          stressLevel: result.stressLevel,
          sleepHours: result.sleepHours,
          symptoms: result.symptoms,
        );
        AppEvents.notifyMoodChanged();
        widget.onLogSaved?.call();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(AppLocalizations.of(context)!.moodSavedToast)));
        }
      }
    } finally {
      if (mounted) setState(() { _busy = false; _editing = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (l == null) return const SizedBox.shrink();

    final logged = _today != null;
    final showPicker = _editing || !logged;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.svcHero,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: Colors.white12, width: 1.2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: _loading
          ? const SizedBox(height: 88, child: Center(child: LoadingMark()))
          : showPicker ? _buildPicker(l) : _buildLogged(l),
    );
  }

  Widget _buildPicker(AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.mood_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l.moodBannerTitle,
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: -0.5),
              ),
            ),
            if (_editing && _today != null)
              IconButton(onPressed: () => setState(() => _editing = false), icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20)),
          ],
        ),
        const SizedBox(height: 2),
        Text(l.moodBannerSubtitle, style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        Center(
          child: Wrap(
            spacing: 20,
            runSpacing: 20,
            alignment: WrapAlignment.center,
            children: [
              for (final kind in _allKinds)
                MoodRecordButton(
                  emoji: kind.emoji,
                  kind: kind.code,
                  onRecorded: _onRecorded,
                  size: 80, // Significant increase for "easy to handle"
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLogged(AppLocalizations l) {
    final t = _today!;
    final isBangla = l.localeName == 'bn';
    final timeStr = isBangla ? t.loggedAtBn : t.loggedAtEn;

    return Row(
      children: [
        Container(
          width: 80, height: 80, // Increased
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.zero, border: Border.all(color: Colors.white24, width: 0.8)),
          alignment: Alignment.center,
          child: Text(t.mood.emoji, style: const TextStyle(fontSize: 40)),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${l.moodLoggedPrefix} ${t.mood.emoji}  ·  $timeStr',
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _MiniStat(icon: Icons.bedtime_outlined, text: '${t.sleepHours.round()}h'),
                  const SizedBox(width: 12),
                  _MiniStat(icon: Icons.bolt_rounded, text: '${t.energyLevel}/5'),
                  const SizedBox(width: 12),
                  _MiniStat(icon: Icons.psychology_outlined, text: '${t.stressLevel}/5'),
                ],
              ),
            ],
          ),
        ),
        IconButton(onPressed: _enterEditMode, icon: const Icon(Icons.edit_note_rounded, color: Colors.white, size: 24)),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MiniStat({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.svcHeroAccent),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w900)),
      ],
    );
  }
}
