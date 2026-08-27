/// Bangla-friendly relative time formatter.
///
/// Examples:
///   * < 1 minute  → "এইমাত্র"
///   * 1 minute    → "১ মিনিট আগে"
///   * 30 minutes  → "৩০ মিনিট আগে"
///   * 1 hour      → "১ ঘণ্টা আগে"
///   * yesterday   → "গতকাল"
///   * 5 days      → "৫ দিন আগে"
///
/// Bangla numerals are used throughout for parity with the rest of
/// the app's UI.

library;

import 'dart:math' as math;

class RelativeTime {
  RelativeTime._();

  /// Bengali numerals 0..9 → ০..৯.
  static const _bnDigits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];

  static String _bn(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (final ch in s.codeUnits) {
      if (ch >= 0x30 && ch <= 0x39) {
        buf.write(_bnDigits[ch - 0x30]);
      } else {
        buf.write(String.fromCharCode(ch));
      }
    }
    return buf.toString();
  }

  static String format(DateTime past, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final p = past.toLocal();
    final diff = n.difference(p);

    // Future or now → "এইমাত্র"
    if (diff.inSeconds < 0) return 'এইমাত্র';
    if (diff.inSeconds < 45) return 'এইমাত্র';

    final mins = diff.inMinutes;
    if (mins < 1) return 'এইমাত্র';
    if (mins == 1) return '১ মিনিট আগে';
    if (mins < 60) return '${_bn(mins)} মিনিট আগে';

    final hours = diff.inHours;
    if (hours == 1) return '১ ঘণ্টা আগে';
    if (hours < 24) return '${_bn(hours)} ঘণ্টা আগে';

    // Yesterday?
    final yesterday = DateTime(n.year, n.month, n.day)
        .subtract(const Duration(days: 1));
    final pDay = DateTime(p.year, p.month, p.day);
    if (pDay == yesterday) return 'গতকাল';

    final days = diff.inDays;
    if (days < 7) return '${_bn(days)} দিন আগে';

    final weeks = days ~/ 7;
    if (weeks == 1) return '১ সপ্তাহ আগে';
    if (weeks < 5) return '${_bn(weeks)} সপ্তাহ আগে';

    final months = days ~/ 30;
    if (months < 12) return '${_bn(math.max(1, months))} মাস আগে';

    final years = days ~/ 365;
    return years <= 1 ? '১ বছর আগে' : '${_bn(years)} বছর আগে';
  }
}
