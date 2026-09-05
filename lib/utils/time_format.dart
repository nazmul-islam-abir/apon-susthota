/// Time formatting helpers shared across meal, medicine, and voice flows.
///
/// Bangladesh users overwhelmingly read wall-clock time in 12-hour
/// "AM/PM" (সকাল/দুপুর/বিকেল/রাত) instead of 24-hour. The Flutter
/// `showTimePicker` widget defaults to the device's locale preference,
/// so we *force* 12-hour mode on every picker by wrapping it in a
/// `MediaQuery` with `alwaysUse24HourFormat: false`. The internal
/// storage on Supabase stays 24-hour `HH:mm` because every server-side
/// schedule / cron / SQL function expects that format. These helpers
/// convert from a stored `HH:mm` string or a `TimeOfDay` to a friendly
/// display string.
library;

import 'package:flutter/material.dart';

/// Parse a 24-hour `HH:mm` string into a [TimeOfDay]. Returns
/// `null` if the input is empty or malformed so callers can
/// fall back to a sensible default.
TimeOfDay? parseHhMm(String? hhmm) {
  if (hhmm == null || hhmm.isEmpty) return null;
  final parts = hhmm.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  if (h < 0 || h > 23 || m < 0 || m > 59) return null;
  return TimeOfDay(hour: h, minute: m);
}

/// Format a 24-hour `HH:mm` string as a 12-hour wall-clock string
/// with English AM/PM (e.g. `08:00` → `"8:00 AM"`,
/// `20:30` → `"8:30 PM"`, `00:00` → `"12:00 AM"`).
///
/// Returns an empty string for null / malformed input.
String formatTime12hFromString(String? hhmm) {
  final t = parseHhMm(hhmm);
  if (t == null) return '';
  return formatTime12h(t);
}

/// Format a [TimeOfDay] as a 12-hour wall-clock string with
/// English AM/PM. AM/PM is left in English because the words are
/// universally understood in Bangladesh and mixing Bangla
/// suffixes here looks broken in the picker chips.
///
///   00:00 → "12:00 AM"   (মধ্যরাত)
///   08:05 → "8:05 AM"
///   12:00 → "12:00 PM"   (দুপুর)
///   20:30 → "8:30 PM"
String formatTime12h(TimeOfDay t) {
  final h24 = t.hour;
  final m = t.minute;
  final ampm = h24 < 12 ? 'AM' : 'PM';
  var h12 = h24 % 12;
  if (h12 == 0) h12 = 12;
  final mm = m.toString().padLeft(2, '0');
  return '$h12:$mm $ampm';
}

/// Wrap a [child] (typically the result of `showTimePicker`) in a
/// `MediaQuery` that forces 12-hour AM/PM mode regardless of the
/// device locale. This is the single source of truth for the
/// Bangladesh-friendly time picker behavior.
///
/// **Heads up:** Material 3's `showTimePicker` reads
/// `alwaysUse24HourFormat` from `MediaQuery`, but in some
/// locales (notably Bangla `bn` on certain Android builds) the
/// picker still renders a 24-hour dial. We therefore recommend
/// `showBdTimePicker` from `widgets/bd_time_picker.dart` over the
/// vanilla `showTimePicker` for user-facing flows — the custom
/// picker never shows Bangla numerals, always has an explicit
/// AM/PM toggle, and never overflows on small screens.
Widget force12HourPicker(BuildContext ctx, Widget? child) {
  return MediaQuery(
    data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
    child: child ?? const SizedBox.shrink(),
  );
}

// ────────────────────────────────────────────────────────────────────────────
// Bangla numeral helpers — used in the live countdown / send confirmation
// dialog so caretakers see numbers in their native script.
// ────────────────────────────────────────────────────────────────────────────

const String _bnDigits = '০১২৩৪৫৬৭৮৯';

/// Convert any ASCII digit characters in [s] to their Bangla
/// equivalents. Non-digit characters pass through unchanged.
String toBanglaDigits(String s) {
  final buf = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x30 && r <= 0x39) {
      buf.write(_bnDigits[r - 0x30]);
    } else {
      buf.writeCharCode(r);
    }
  }
  return buf.toString();
}

/// Convert an integer (positive) to Bangla digits as a string.
///   0  → "০"
///   12 → "১২"
///   90 → "৯০"
String intToBangla(int n) => toBanglaDigits(n.toString());

// ────────────────────────────────────────────────────────────────────────────
// Bangla calendar helpers — used by the bd_date_picker and (formerly
// inline) the voice_send_dialog so a "১২ সেপ্টেম্বর" style label is
// rendered from one canonical place.
// ────────────────────────────────────────────────────────────────────────────

/// Bangla month names, 1-indexed. Kept as a top-level constant so
/// the date picker, the send-confirmation dialog, and any future
/// Bangla calendar surface read the same names.
const List<String> kBanglaMonths = [
  'জানুয়ারি',
  'ফেব্রুয়ারি',
  'মার্চ',
  'এপ্রিল',
  'মে',
  'জুন',
  'জুলাই',
  'আগস্ট',
  'সেপ্টেম্বর',
  'অক্টোবর',
  'নভেম্বর',
  'ডিসেম্বর',
];

/// Bangla weekday names, indexed by `DateTime.weekday` (1 = Monday
/// → 7 = Sunday). We shift to a Sunday-first array since the
/// Bangladesh calendar grid is conventionally rendered Sun→Sat.
const List<String> kBanglaWeekdays = [
  'রবি', // Sunday
  'সোম', // Monday
  'মঙ্গল', // Tuesday
  'বুধ', // Wednesday
  'বৃহস্পতি', // Thursday
  'শুক্র', // Friday
  'শনি', // Saturday
];

/// Format a [DateTime] as a Bangla-localized calendar label.
///
///   [includeYear] defaults to true so the year shows up in the
///   voice-send confirmation dialog where context matters.
///   The bd_date_picker sets it to false on its compact day cells.
///
///   Examples:
///     DateTime(2026, 9, 5) → "৫ সেপ্টেম্বর, ২০২৬"
///     DateTime(2026, 9, 5, includeYear: false) → "৫ সেপ্টেম্বর"
String formatBanglaDate(DateTime d, {bool includeYear = true}) {
  final mo = kBanglaMonths[d.month - 1];
  if (!includeYear) {
    return '${intToBangla(d.day)} $mo';
  }
  return '${intToBangla(d.day)} $mo, ${intToBangla(d.year)}';
}

/// Return the Bangla weekday name for [d] (e.g. "শুক্রবার" — note
/// the "বার" suffix that's idiomatic when naming a specific day,
/// vs. the short form "শুক্র" used in calendar column headers).
String banglaWeekday(DateTime d) {
  // DateTime.weekday: 1 = Monday … 7 = Sunday. Our array is
  // Sun-first, so map: weekday=7 → index 0, weekday=1 → index 1, …
  final idx = d.weekday % 7;
  return '${kBanglaWeekdays[idx]}বার';
}

// ────────────────────────────────────────────────────────────────────────────
// Countdown helpers — for voice schedule cards / send confirmation.
// ────────────────────────────────────────────────────────────────────────────

/// Breakdown of the time remaining until [target] (UTC).
/// All fields are non-negative. If [now] is already past [target],
/// every field is zero and [isPast] is true.
class RemainingTime {
  final int days;
  final int hours;
  final int minutes;
  final int seconds;
  final bool isPast;

  const RemainingTime({
    required this.days,
    required this.hours,
    required this.minutes,
    required this.seconds,
    required this.isPast,
  });

  const RemainingTime.zeroPast()
      : days = 0,
        hours = 0,
        minutes = 0,
        seconds = 0,
        isPast = true;

  /// Total seconds for progress-bar math.
  int get totalSeconds =>
      days * 86400 + hours * 3600 + minutes * 60 + seconds;
}

/// Compute the time remaining between [now] and [target]. Both
/// arguments are expected to be UTC moments (Dart's
/// `DateTime.toUtc()` output).
RemainingTime remainingUntil(DateTime target, {DateTime? now}) {
  final n = now ?? DateTime.now().toUtc();
  if (!target.isAfter(n)) return const RemainingTime.zeroPast();
  final diff = target.difference(n);
  final days = diff.inDays;
  final hours = diff.inHours - days * 24;
  final minutes = diff.inMinutes - days * 24 * 60 - hours * 60;
  final seconds = diff.inSeconds -
      days * 24 * 3600 -
      hours * 3600 -
      minutes * 60;
  return RemainingTime(
    days: days,
    hours: hours,
    minutes: minutes,
    seconds: seconds,
    isPast: false,
  );
}

/// Render a [RemainingTime] as a Bangla-localized string the
/// caretaker can read at a glance:
///
///   0d 3h 12m 04s → "৩ ঘণ্টা ১২ মিনিট"
///   1d 02h 00m    → "১ দিন ২ ঘণ্টা"
///   0d 00h 45m    → "৪৫ মিনিট"
///   0d 00h 00m 5s → "৫ সেকেন্ড"
///
/// Hidden fields are dropped so the label never feels padded.
/// If [r] is in the past, returns "এখনই" (literally "right now").
String formatRemainingBn(RemainingTime r) {
  if (r.isPast) return 'এখনই';
  final parts = <String>[];
  if (r.days > 0) parts.add('${intToBangla(r.days)} দিন');
  if (r.hours > 0) parts.add('${intToBangla(r.hours)} ঘণ্টা');
  if (r.minutes > 0) parts.add('${intToBangla(r.minutes)} মিনিট');
  if (parts.isEmpty && r.seconds > 0) {
    return '${intToBangla(r.seconds)} সেকেন্ড';
  }
  // If everything is zero, show seconds.
  if (parts.isEmpty) {
    return '${intToBangla(r.seconds)} সেকেন্ড';
  }
  return parts.join(' ');
}
