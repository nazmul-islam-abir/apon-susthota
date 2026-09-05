/// Bangladesh-friendly date picker shown as a bottom sheet.
///
/// Mirrors the layout of [bd_time_picker.dart] so the two pickers
/// feel like the same component. Surfaces:
///
///   * Live preview tile with the picked date as "৫ সেপ্টেম্বর,
///     ২০২৬" plus the Bangla weekday underneath ("শুক্রবার").
///   * Quick-pick chips: "আজ" / "আগামীকাল" / "পরশু" so the common
///     case is one tap and Bangla-speaking caretakers don't have to
///     count days on the grid.
///   * Month grid with previous/next navigation, clamped to
///     [minDate, maxDate]. Day numbers are Bangla so 17 → "১৭" —
///     no mixing of scripts on screen.
///   * Weekday header row in Bangla: রবি, সোম, মঙ্গল, বুধ,
///     বৃহস্পতি, শুক্র, শনি (Sunday-first, the conventional layout
///     for Bangladeshi calendars).
///   * "Today" gets a thin accent border; the selected day gets a
///     solid accent fill; days outside [minDate, maxDate] are
///     dimmed and not tappable.
///
/// Internally we use a single [DateTime] `_selected` field at
/// midnight in the device's local tz. We never round-trip through
/// `intl`'s `DateFormat` so the widget stays zero-dependency beyond
/// `flutter/material.dart`.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/time_format.dart';

/// Show the Bangladesh-friendly date picker as a bottom sheet.
///
///   * [initial]  — seed date. Defaults to today at midnight (in
///                  the device's local timezone).
///   * [titleBn]  — Bangla title shown at the top of the sheet.
///                  Defaults to "তারিখ বাছাই".
///   * [accent]   — color used to fill the selected day chip.
///   * [minDate]  — earliest selectable date (default: today).
///   * [maxDate]  — latest selectable date (default: today + 1y).
///
/// Resolves with the picked date at midnight, or `null` if the user
/// dismissed the sheet without confirming.
Future<DateTime?> showBdDatePicker(
  BuildContext context, {
  DateTime? initial,
  String titleBn = 'তারিখ বাছাই',
  Color? accent,
  DateTime? minDate,
  DateTime? maxDate,
}) {
  final today = _midnight(DateTime.now());
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _BdDatePickerSheet(
      initial: initial ?? today,
      titleBn: titleBn,
      accent: accent ?? AppColors.cyan,
      minDate: minDate ?? today,
      maxDate: maxDate ?? today.add(const Duration(days: 365)),
    ),
  );
}

DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

class _BdDatePickerSheet extends StatefulWidget {
  final DateTime initial;
  final String titleBn;
  final Color accent;
  final DateTime minDate;
  final DateTime maxDate;
  const _BdDatePickerSheet({
    required this.initial,
    required this.titleBn,
    required this.accent,
    required this.minDate,
    required this.maxDate,
  });

  @override
  State<_BdDatePickerSheet> createState() => _BdDatePickerSheetState();
}

class _BdDatePickerSheetState extends State<_BdDatePickerSheet> {
  late DateTime _selected;

  /// First day of the month currently being shown in the grid.
  late DateTime _viewMonth;

  @override
  void initState() {
    super.initState();
    _selected = _midnight(widget.initial);
    _viewMonth = DateTime(_selected.year, _selected.month, 1);
  }

  void _setSelected(DateTime d) {
    final m = _midnight(d);
    if (m.isBefore(_midnight(widget.minDate))) return;
    if (m.isAfter(_midnight(widget.maxDate))) return;
    setState(() => _selected = m);
  }

  void _shiftMonth(int delta) {
    final next = DateTime(_viewMonth.year, _viewMonth.month + delta, 1);
    // Don't navigate into a month whose any day is fully out of
    // range. We allow the view to start on a month that's partially
    // beyond minDate so the user can scroll back to the boundary.
    final firstOfNext = next;
    final lastOfNext = DateTime(next.year, next.month + 1, 0);
    if (lastOfNext.isBefore(_midnight(widget.minDate))) return;
    if (firstOfNext.isAfter(_midnight(widget.maxDate))) return;
    setState(() => _viewMonth = firstOfNext);
  }

  String _previewLabel() => formatBanglaDate(_selected);

  void _confirm() {
    Navigator.of(context).pop(_selected);
  }

  @override
  Widget build(BuildContext context) {
    final today = _midnight(DateTime.now());
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
            // Title.
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

            // Scrollable area for the picker content.
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Live preview tile.
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
                          Icon(Icons.calendar_today_rounded,
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
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.ink,
                                    letterSpacing: -0.4,
                                    fontFeatures: [FontFeature.tabularFigures()],
                                  ),
                                ),
                                Text(
                                  banglaWeekday(_selected),
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
                    const SizedBox(height: 16),
                    // Quick-pick chips.
                    Row(
                      children: [
                        Expanded(
                          child: _QuickPickChip(
                            label: 'আজ',
                            onTap: () => _setSelected(today),
                            accent: widget.accent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _QuickPickChip(
                            label: 'আগামীকাল',
                            onTap: () => _setSelected(
                                today.add(const Duration(days: 1))),
                            accent: widget.accent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _QuickPickChip(
                            label: 'পরশু',
                            onTap: () => _setSelected(
                                today.add(const Duration(days: 2))),
                            accent: widget.accent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Month header.
                    _MonthHeader(
                      month: _viewMonth,
                      accent: widget.accent,
                      onPrev: _viewMonth.year == widget.minDate.year &&
                                  _viewMonth.month == widget.minDate.month ||
                              (_viewMonth.year < widget.minDate.year)
                          ? null
                          : () => _shiftMonth(-1),
                      onNext: _viewMonth.year == widget.maxDate.year &&
                                  _viewMonth.month == widget.maxDate.month ||
                              (_viewMonth.year > widget.maxDate.year)
                          ? null
                          : () => _shiftMonth(1),
                    ),
                    const SizedBox(height: 10),
                    // Weekday header (Sun-first).
                    _WeekdayHeader(accent: widget.accent),
                    const SizedBox(height: 6),
                    // Day grid.
                    _DayGrid(
                      month: _viewMonth,
                      selected: _selected,
                      today: today,
                      minDate: _midnight(widget.minDate),
                      maxDate: _midnight(widget.maxDate),
                      accent: widget.accent,
                      onTap: _setSelected,
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 12),
            // Cancel / Confirm.
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

class _QuickPickChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color accent;
  const _QuickPickChip({
    required this.label,
    required this.onTap,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.graphite, width: 1),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: AppColors.ink,
          ),
        ),
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  final DateTime month;
  final Color accent;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  const _MonthHeader({
    required this.month,
    required this.accent,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final title = '${kBanglaMonths[month.month - 1]} ${intToBangla(month.year)}';
    return Row(
      children: [
        _NavButton(
          icon: Icons.chevron_left_rounded,
          onTap: onPrev,
          accent: accent,
        ),
        Expanded(
          child: Center(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
        _NavButton(
          icon: Icons.chevron_right_rounded,
          onTap: onNext,
          accent: accent,
        ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color accent;
  const _NavButton({
    required this.icon,
    required this.onTap,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled
              ? accent.withValues(alpha: 0.10)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          size: 22,
          color: enabled ? accent : AppColors.smoke,
        ),
      ),
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  final Color accent;
  const _WeekdayHeader({required this.accent});
  @override
  Widget build(BuildContext context) {
    // Sunday-first layout, matching the convention used by the
    // Bangladesh government calendar.
    return Row(
      children: [
        for (final w in kBanglaWeekdays)
          Expanded(
            child: Center(
              child: Text(
                w,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.smoke,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DayGrid extends StatelessWidget {
  final DateTime month;
  final DateTime selected;
  final DateTime today;
  final DateTime minDate;
  final DateTime maxDate;
  final Color accent;
  final ValueChanged<DateTime> onTap;
  const _DayGrid({
    required this.month,
    required this.selected,
    required this.today,
    required this.minDate,
    required this.maxDate,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // First day of the month (e.g. Sep 1, 2026).
    final first = DateTime(month.year, month.month, 1);
    // Last day of the month (DateTime(y, m+1, 0) = last day of m).
    final last = DateTime(month.year, month.month + 1, 0);

    // weekday: 1 = Monday … 7 = Sunday → we want Sun-first offset
    // so the grid lines up with the weekday header.
    // Sun (7) → offset 0; Mon (1) → offset 1; … Sat (6) → offset 6.
    final leadingBlanks = first.weekday % 7;

    final cells = <Widget>[];
    for (var i = 0; i < leadingBlanks; i++) {
      cells.add(const SizedBox(height: 44));
    }
    for (var d = 1; d <= last.day; d++) {
      final day = DateTime(month.year, month.month, d);
      cells.add(_DayCell(
        day: day,
        selected: _sameDay(day, selected),
        isToday: _sameDay(day, today),
        enabled: !day.isBefore(minDate) && !day.isAfter(maxDate),
        accent: accent,
        onTap: onTap,
      ));
    }
    // Pad to a full last row so the grid doesn't end mid-week.
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox(height: 44));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < cells.length; i += 7)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                for (var j = 0; j < 7; j++) ...[
                  Expanded(child: cells[i + j]),
                  if (j < 6) const SizedBox(width: 6),
                ],
              ],
            ),
          ),
      ],
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final bool selected;
  final bool isToday;
  final bool enabled;
  final Color accent;
  final ValueChanged<DateTime> onTap;
  const _DayCell({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.enabled,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? accent
        : (isToday ? accent.withValues(alpha: 0.08) : AppColors.surface);
    final fg = !enabled
        ? AppColors.smoke.withValues(alpha: 0.4)
        : (selected ? AppColors.paper : AppColors.ink);
    final border = selected
        ? accent
        : (isToday ? accent.withValues(alpha: 0.5) : AppColors.graphite);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: enabled ? () => onTap(day) : null,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border, width: selected || isToday ? 1.4 : 1),
        ),
        child: Text(
          intToBangla(day.day),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: fg,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
