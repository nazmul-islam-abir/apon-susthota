/// Bottom sheet that captures the four short health signals that
/// accompany a mood entry: sleep hours, energy level, stress level,
/// and an optional symptoms note.
///
/// Opens immediately after the user taps-and-holds an emoji on the
/// dashboard mood banner, and is also pushed by the 10 PM
/// `MoodTaskScheduler` reminder.
///
/// Mirrors the chrome of `MedicineEditorSheet`
/// (`lib/screens/medicine_editor.dart`):
///   • Static `show()` returning a `Future<MoodHealthResult?>` so
///     callers can `await` the result and dismiss with `null` on
///     a back-gesture / outside-tap.
///   • `isScrollControlled: true` + `viewInsets.bottom` padding so
///     the keyboard never covers the Save button.
///   • Drag handle + max 94% screen height.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/mood_entry.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';

/// What the parent widget learns from the sheet — every field is
/// required so the caller can call `SupabaseService.logMood(...)`
/// without dealing with nullable defaults.
class MoodHealthResult {
  final MoodKind mood;
  final double sleepHours;
  final int energyLevel;
  final int stressLevel;
  final String? symptoms;

  const MoodHealthResult({
    required this.mood,
    required this.sleepHours,
    required this.energyLevel,
    required this.stressLevel,
    this.symptoms,
  });
}

class MoodHealthSheet extends StatefulWidget {
  /// The mood the user just picked — used to display the matching
  /// emoji in the sheet header so the user remembers what they
  /// tapped. Required.
  final MoodKind initialMood;

  /// If the user already logged today and we're editing, seed
  /// the four fields with the existing values so they don't have
  /// to start from scratch.
  final MoodEntry? existing;

  const MoodHealthSheet({
    super.key,
    required this.initialMood,
    this.existing,
  });

  /// Convenience: opens the sheet, awaits the result, returns null
  /// if the user swiped down / tapped outside.
  static Future<MoodHealthResult?> show(
    BuildContext context, {
    required MoodKind initialMood,
    MoodEntry? existing,
  }) {
    return showModalBottomSheet<MoodHealthResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      isDismissible: true,
      enableDrag: true,
      builder: (_) => MoodHealthSheet(
        initialMood: initialMood,
        existing: existing,
      ),
    );
  }

  @override
  State<MoodHealthSheet> createState() => _MoodHealthSheetState();
}

class _MoodHealthSheetState extends State<MoodHealthSheet> {
  late double _sleepHours;
  late int _energy;
  late int _stress;
  late TextEditingController _symptomsCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _sleepHours = e?.sleepHours ?? 7.0;
    _energy = e?.energyLevel ?? 3;
    _stress = e?.stressLevel ?? 3;
    _symptomsCtrl = TextEditingController(text: e?.symptoms ?? '');
  }

  @override
  void dispose() {
    _symptomsCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    if (_saving) return;
    setState(() => _saving = true);
    HapticFeedback.selectionClick();
    final symptoms = _symptomsCtrl.text.trim();
    Navigator.pop(
      context,
      MoodHealthResult(
        mood: widget.initialMood,
        sleepHours: _sleepHours,
        energyLevel: _energy,
        stressLevel: _stress,
        symptoms: symptoms.isEmpty ? null : symptoms,
      ),
    );
  }

  void _onSkip() {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final l = AppLocalizations.of(context)!;
    final isBangla = l.localeName == 'bn';
    final moodLabel = isBangla
        ? '${widget.initialMood.emoji}  ${widget.initialMood.labelBn}'
        : '${widget.initialMood.emoji}  ${widget.initialMood.labelEn}';

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.paper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.94),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.graphite,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header ───────────────────────────────────────
                    Overline(l.moodSheetTitle),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceHigh,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.line),
                          ),
                          child: Text(
                            moodLabel,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),

                    // ── Sleep slider ────────────────────────────────
                    _FieldLabel(
                      text: l.sleepHoursLabel,
                      trailing: '${_sleepHours.toStringAsFixed(1)} h',
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppColors.brandMaroon,
                        inactiveTrackColor: AppColors.line,
                        thumbColor: AppColors.brandMaroon,
                        overlayColor: AppColors.brandMaroon.withValues(
                          alpha: 0.12,
                        ),
                        trackHeight: 4,
                      ),
                      child: Slider(
                        min: 0,
                        max: 14,
                        divisions: 28, // 0.5h steps
                        value: _sleepHours.clamp(0.0, 14.0),
                        onChanged: (v) => setState(() => _sleepHours = v),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Energy ──────────────────────────────────────
                    _FieldLabel(text: l.energyLevelLabel),
                    const SizedBox(height: 8),
                    _ChipRow<int>(
                      values: const [1, 2, 3, 4, 5],
                      selected: _energy,
                      onSelected: (v) {
                        HapticFeedback.selectionClick();
                        setState(() => _energy = v);
                      },
                      labelFor: (v) => '${EnergyChip(v).emoji}  $v',
                    ),
                    const SizedBox(height: 18),

                    // ── Stress ──────────────────────────────────────
                    _FieldLabel(text: l.stressLevelLabel),
                    const SizedBox(height: 8),
                    _ChipRow<int>(
                      values: const [1, 2, 3, 4, 5],
                      selected: _stress,
                      onSelected: (v) {
                        HapticFeedback.selectionClick();
                        setState(() => _stress = v);
                      },
                      labelFor: (v) => '${StressChip(v).emoji}  $v',
                    ),
                    const SizedBox(height: 18),

                    // ── Symptoms (optional) ─────────────────────────
                    _FieldLabel(text: l.symptomsLabel),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _symptomsCtrl,
                      minLines: 2,
                      maxLines: 4,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: l.symptomsHint,
                        filled: true,
                        fillColor: AppColors.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.line),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppColors.brandMaroon,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── Save / skip ─────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: MonoButton(
                            label: _saving ? l.moodSavingToast : l.moodSaveButton,
                            onPressed: _saving ? null : _onSave,
                          ),
                        ),
                        const SizedBox(width: 10),
                        MonoButton(
                          label: l.moodReminderClose,
                          variant: MonoButtonVariant.ghost,
                          onPressed: _saving ? null : _onSkip,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  final String? trailing;
  const _FieldLabel({required this.text, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              letterSpacing: -0.2,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.brandMaroon,
            ),
          ),
      ],
    );
  }
}

class _ChipRow<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final ValueChanged<T> onSelected;
  final String Function(T) labelFor;

  const _ChipRow({
    required this.values,
    required this.selected,
    required this.onSelected,
    required this.labelFor,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in values)
          _ChoiceChip(
            label: labelFor(v),
            selected: v == selected,
            onTap: () => onSelected(v),
          ),
      ],
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.decelerate,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandMaroon : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: selected ? AppColors.brandMaroon : AppColors.line,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            color: selected ? AppColors.paper : AppColors.ink,
            letterSpacing: -0.1,
          ),
        ),
      ),
    );
  }
}