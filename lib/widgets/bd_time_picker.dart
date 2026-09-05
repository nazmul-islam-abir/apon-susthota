/// Bangladesh-friendly time picker shown as a bottom sheet.
///
/// Replaces the default Material `showTimePicker` (the 24-hour dial
/// with Bangla numerals that confused caretakers and elderly patients
/// in Bangladesh). It surfaces:
///
///   * An explicit AM / PM toggle (always two large chips, even
///     when the chosen wall-clock happens to be "morning").
///   * A 12-hour grid (1 → 12) of large tap-targets — no fiddly
///     dial, no overflow on small phones, and the numbers stay in
///     Western Arabic 0-9 so "১৭" never appears on screen.
///   * Bangla row labels under the AM/PM chips (সকাল / দুপুর /
///     বিকেল / রাত) to give an at-a-glance hint of where the
///     selected time falls.
///   * A scrollable minute strip with 5-minute quick-pick chips
///     (০, ৫, ১০, …, ৫৫) plus a precise 1-59 minute wheel.
///
/// Internally returns a [TimeOfDay] whose `hour` field is always in
/// the canonical 0-23 range so existing storage (server `HH:mm`,
/// SQL schedules, `MedicineScheduleSlot.fromTime`) stays correct.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Show the Bangladesh-friendly 12-hour AM/PM picker as a bottom
/// sheet and resolve with the user's choice (or `null` if they
/// dismissed the sheet).
///
///   * [initial]       — the seed time. Defaults to 8:00 AM today.
///   * [titleBn]       — Bangla title shown at the top of the sheet.
///                      Defaults to "সময় বাছাই".
///   * [accent]        — color used to fill the selected chips. Pull
///                      the screen's accent color when integrating;
///                      defaults to the app's sage brand color so the
///                      picker reads cleanly even in tests.
Future<TimeOfDay?> showBdTimePicker(
  BuildContext context, {
  TimeOfDay? initial,
  String titleBn = 'সময় বাছাই',
  Color? accent,
}) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _BdTimePickerSheet(
      initial: initial ?? const TimeOfDay(hour: 8, minute: 0),
      titleBn: titleBn,
      accent: accent ?? AppColors.cyan,
    ),
  );
}

class _BdTimePickerSheet extends StatefulWidget {
  final TimeOfDay initial;
  final String titleBn;
  final Color accent;
  const _BdTimePickerSheet({
    required this.initial,
    required this.titleBn,
    required this.accent,
  });

  @override
  State<_BdTimePickerSheet> createState() => _BdTimePickerSheetState();
}

class _BdTimePickerSheetState extends State<_BdTimePickerSheet> {
  /// 1..12 — the visible 12-hour clock face value.
  late int _h12;

  /// AM = true, PM = false.
  late bool _isAm;

  /// 0..59 — minute (we don't snap; user picks exact).
  late int _minute;

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    _isAm = t.hour < 12;
    var h = t.hour % 12;
    if (h == 0) h = 12;
    _h12 = h;
    _minute = t.minute;
  }

  /// Convert the in-sheet (12h + AM/PM + minute) state back into a
  /// canonical `TimeOfDay` (0..23 hour) that the rest of the app
  /// stores on the server as `HH:mm`.
  TimeOfDay _toTimeOfDay() {
    var h24 = _h12 % 12;
    if (!_isAm) h24 += 12;
    return TimeOfDay(hour: h24, minute: _minute);
  }

  String _previewLabel() {
    final mm = _minute.toString().padLeft(2, '0');
    return '$_h12:$mm ${_isAm ? 'AM' : 'PM'}';
  }

  String _banglaHintFor(int h12, bool isAm) {
    // Bangladesh people use these coarse-of-day words as informal
    // anchors. We map:
    //   AM 1-6  → রাত (night, post-midnight)
    //   AM 7-11 → সকাল (morning)
    //   PM 12-4 → দুপুর (noon/afternoon)
    //   PM 5-7  → বিকেল (late afternoon)
    //   PM 8-12 → রাত (night)
    if (isAm) {
      if (h12 <= 6) return 'রাত';
      return 'সকাল';
    }
    if (h12 <= 4) return 'দুপুর';
    if (h12 <= 7) return 'বিকেল';
    return 'রাত';
  }

  void _confirm() {
    Navigator.of(context).pop(_toTimeOfDay());
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Grabber.
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.graphite,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title & Preview.
            // These stay pinned so the user always sees what they are doing.
            Text(
              widget.titleBn,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 14),
            
            // The scrollable heart of the picker.
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Live preview.
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      decoration: BoxDecoration(
                        color: widget.accent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: widget.accent.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.schedule_rounded,
                              size: 22, color: widget.accent),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _previewLabel(),
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.ink,
                                    letterSpacing: -0.5,
                                    fontFeatures: [FontFeature.tabularFigures()],
                                  ),
                                ),
                                Text(
                                  _banglaHintFor(_h12, _isAm),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.smoke,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    // AM / PM toggle.
                    Row(
                      children: [
                        Expanded(
                          child: _AmPmChip(
                            label: 'AM',
                            sublabelBn: 'সকাল / রাত',
                            selected: _isAm,
                            accent: widget.accent,
                            onTap: () => setState(() => _isAm = true),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _AmPmChip(
                            label: 'PM',
                            sublabelBn: 'দুপুর / বিকেল',
                            selected: !_isAm,
                            accent: widget.accent,
                            onTap: () => setState(() => _isAm = false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    // Hour chips 1..12.
                    const _SectionLabel(text: 'ঘণ্টা'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (int h = 1; h <= 12; h++)
                          _HourChip(
                            label: '$h',
                            selected: _h12 == h,
                            accent: widget.accent,
                            onTap: () => setState(() => _h12 = h),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Quick-pick minutes (every 5).
                    const _SectionLabel(text: 'মিনিট (দ্রুত বাছাই)'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final m in const [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55])
                          _HourChip(
                            label: m.toString().padLeft(2, '0'),
                            selected: _minute == m,
                            accent: widget.accent,
                            onTap: () => setState(() => _minute = m),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Exact minute input.
                    const _SectionLabel(text: 'মিনিট (সঠিক)'),
                    const SizedBox(height: 8),
                    TextField(
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                      decoration: InputDecoration(
                        hintText: '0–59',
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppColors.graphite, width: 1),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppColors.graphite, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: widget.accent, width: 1.6),
                        ),
                      ),
                      controller: TextEditingController(
                        text: _minute.toString().padLeft(2, '0'),
                      )
                        ..selection = TextSelection.collapsed(
                            offset: _minute.toString().padLeft(2, '0').length),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                      onSubmitted: (v) {
                        final n = int.tryParse(v);
                        if (n != null && n >= 0 && n < 60) {
                          setState(() => _minute = n);
                        }
                      },
                      onChanged: (v) {
                        final n = int.tryParse(v);
                        if (n != null && n >= 0 && n < 60) {
                          setState(() => _minute = n);
                        }
                      },
                    ),
                    const SizedBox(height: 10), // extra padding before buttons
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 12),
            // Confirm / cancel (sticky at bottom).
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.smoke,
                      side: const BorderSide(
                          color: AppColors.graphite, width: 1.2),
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'বাতিল',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: widget.accent,
                      foregroundColor: AppColors.paper,
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _confirm,
                    child: Text(
                      'ঠিক আছে — ${_previewLabel()}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
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

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: AppColors.smoke,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _AmPmChip extends StatelessWidget {
  final String label;
  final String sublabelBn;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  const _AmPmChip({
    required this.label,
    required this.sublabelBn,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? accent : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? accent : AppColors.graphite,
              width: selected ? 1.4 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: selected ? AppColors.paper : AppColors.ink,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sublabelBn,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected
                    ? AppColors.paper.withValues(alpha: 0.85)
                    : AppColors.smoke,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HourChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  const _HourChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: 56,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? accent : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? accent : AppColors.graphite,
              width: selected ? 1.4 : 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: selected ? AppColors.paper : AppColors.ink,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
