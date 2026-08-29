/// Models for the daily mood + health-conditions check-in.
///
/// Mirrors the `public.mood_entries` table added in
/// `supabasesql/41_mood.sql`. Each user has at most one row per
/// local day (Asia/Dhaka) — `log_mood` upserts on conflict so
/// the user can re-record their mood by tapping the edit
/// pencil on the dashboard banner.
library;

/// Five-step Likert-style mood scale. Stored on the server as the
/// lowercase code so analytics queries stay stable across locale
/// changes.
enum MoodKind {
  sad,
  meh,
  ok,
  good,
  great,
}

extension MoodKindX on MoodKind {
  /// Wire-safe lowercase code, e.g. `'sad'`, `'great'`.
  String get code {
    switch (this) {
      case MoodKind.sad:
        return 'sad';
      case MoodKind.meh:
        return 'meh';
      case MoodKind.ok:
        return 'ok';
      case MoodKind.good:
        return 'good';
      case MoodKind.great:
        return 'great';
    }
  }

  /// Bangla short label, e.g. 'খারাপ'.
  String get labelBn {
    switch (this) {
      case MoodKind.sad:
        return 'খারাপ';
      case MoodKind.meh:
        return 'খারাপ-মাঝারি';
      case MoodKind.ok:
        return 'মাঝারি';
      case MoodKind.good:
        return 'ভালো';
      case MoodKind.great:
        return 'চমৎকার';
    }
  }

  /// English short label, e.g. 'Sad'.
  String get labelEn {
    switch (this) {
      case MoodKind.sad:
        return 'Sad';
      case MoodKind.meh:
        return 'Meh';
      case MoodKind.ok:
        return 'OK';
      case MoodKind.good:
        return 'Good';
      case MoodKind.great:
        return 'Great';
    }
  }

  /// The face emoji shown on the banner — single source of truth
  /// so the dashboard banner, history list, and any future chart
  /// all render the same glyph.
  String get emoji {
    switch (this) {
      case MoodKind.sad:
        return '😞';
      case MoodKind.meh:
        return '😕';
      case MoodKind.ok:
        return '😐';
      case MoodKind.good:
        return '🙂';
      case MoodKind.great:
        return '😄';
    }
  }
}

/// Convert a server code to enum, with a safe fallback.
MoodKind moodKindFromCode(String? code) {
  switch (code) {
    case 'sad':
      return MoodKind.sad;
    case 'meh':
      return MoodKind.meh;
    case 'ok':
      return MoodKind.ok;
    case 'good':
      return MoodKind.good;
    case 'great':
      return MoodKind.great;
    default:
      return MoodKind.ok;
  }
}

/// One row of today's mood + health signals. Always represents a
/// single user-local-day.
class MoodEntry {
  final MoodKind mood;
  final int energyLevel; // 1–5 (1 = exhausted, 5 = energetic)
  final int stressLevel; // 1–5 (1 = relaxed, 5 = overwhelmed)
  final double sleepHours; // 0.0–24.0
  final String? symptoms; // optional free text
  final DateTime entryDate;
  final DateTime createdAt;

  const MoodEntry({
    required this.mood,
    required this.energyLevel,
    required this.stressLevel,
    required this.sleepHours,
    this.symptoms,
    required this.entryDate,
    required this.createdAt,
  });

  factory MoodEntry.fromJson(Map<String, dynamic> json) {
    return MoodEntry(
      mood: moodKindFromCode(json['mood_kind'] as String?),
      energyLevel: (json['energy_level'] as int?) ?? 3,
      stressLevel: (json['stress_level'] as int?) ?? 3,
      sleepHours: json['sleep_hours'] != null
          ? ((json['sleep_hours']) as num).toDouble()
          : 7.0,
      symptoms: json['symptoms'] as String?,
      entryDate: DateTime.parse(json['entry_date'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Pretty time-of-day string ("9:14 PM" / "রাত ৯:১৪") used on
  /// the dashboard banner after a row is logged.
  String get loggedAtBn {
    final h = createdAt.hour;
    final m = createdAt.minute.toString().padLeft(2, '0');
    final period = h >= 18
        ? 'রাত'
        : h >= 12
            ? 'বিকেল'
            : h >= 6
                ? 'সকাল'
                : 'রাত';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$period $h12:$m';
  }

  String get loggedAtEn {
    final h = createdAt.hour;
    final m = createdAt.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:$m $period';
  }
}

/// Energy 1–5 with friendly label + emoji for the chip row.
class EnergyChip {
  final int level; // 1–5
  const EnergyChip(this.level);
  String get emoji {
    switch (level) {
      case 1:
        return '😴';
      case 2:
        return '😪';
      case 3:
        return '🙂';
      case 4:
        return '😊';
      case 5:
        return '🤩';
      default:
        return '🙂';
    }
  }
}

/// Stress 1–5 with friendly label + emoji for the chip row.
/// Stored scale = 1 (calm) … 5 (overwhelmed) so lower is better.
class StressChip {
  final int level; // 1–5
  const StressChip(this.level);
  String get emoji {
    switch (level) {
      case 1:
        return '😎';
      case 2:
        return '😌';
      case 3:
        return '😐';
      case 4:
        return '😟';
      case 5:
        return '😰';
      default:
        return '😐';
    }
  }
}