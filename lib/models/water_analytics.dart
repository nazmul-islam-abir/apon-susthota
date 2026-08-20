/// Aggregated water-tracking analytics — mirrors the JSON shape
/// returned by `public.get_water_analytics(p_days)` in
/// `supabasesql/18_daily_metrics.sql`.
///
/// One instance powers the entire analytics screen:
///   • `days`           — list of `WaterDayStat`, one per day
///   • `streakDays`     — consecutive days hitting the target
///   • `daysHitTarget`  — count in the window
///   • `avgLiters`      — rolling average in the window
///   • `consistencyPct` — % of days hitting target
///   • `targetLiters`   — daily target (default 2.5 L)
///
/// `WaterDayStat` carries the per-day breakdown: total glasses /
/// liters, whether the target was hit, and a `bucketDistribution`
/// map so the bucket pie chart can read it directly.
library;

import 'package:flutter/foundation.dart';

@immutable
class WaterDayStat {
  /// ISO-8601 date string (YYYY-MM-DD).
  final String date;

  /// Number of glasses the user drank that day.
  final int glasses;

  /// Total liters consumed that day.
  final double liters;

  /// Whether the user hit the daily target on this day.
  final bool targetHit;

  /// Glass count broken down by time-of-day bucket.
  final Map<String, int> bucketDistribution;

  const WaterDayStat({
    required this.date,
    required this.glasses,
    required this.liters,
    required this.targetHit,
    required this.bucketDistribution,
  });

  factory WaterDayStat.fromJson(Map<String, dynamic> json) {
    final rawBuckets = json['buckets'] as Map? ?? const {};
    final distribution = <String, int>{
      'morning': 0,
      'noon': 0,
      'afternoon': 0,
      'night': 0,
      ...{
        for (final e in rawBuckets.entries)
          e.key.toString(): (e.value as num).toInt()
      },
    };
    return WaterDayStat(
      date: (json['date'] ?? '').toString(),
      glasses: (json['glasses'] as num?)?.toInt() ?? 0,
      liters: (json['liters'] as num?)?.toDouble() ?? 0.0,
      targetHit: json['target_hit'] == true,
      bucketDistribution: distribution,
    );
  }

  /// Bengali label for the bucket, used by the analytics UI.
  static String bucketBn(String key) {
    switch (key) {
      case 'morning':
        return 'সকাল';
      case 'noon':
        return 'দুপুর';
      case 'afternoon':
        return 'বিকেল';
      case 'night':
        return 'রাত';
    }
    return key;
  }
}

@immutable
class WaterAnalyticsSummary {
  final List<WaterDayStat> days;
  final int streakDays;
  final int daysHitTarget;
  final double avgLiters;
  final double consistencyPct;
  final double targetLiters;

  /// Date of the most recent day in the window (ISO).
  final String rangeEnd;

  /// Date of the oldest day in the window (ISO).
  final String rangeStart;

  const WaterAnalyticsSummary({
    required this.days,
    required this.streakDays,
    required this.daysHitTarget,
    required this.avgLiters,
    required this.consistencyPct,
    required this.targetLiters,
    required this.rangeStart,
    required this.rangeEnd,
  });

  factory WaterAnalyticsSummary.fromJson(Map<String, dynamic> json) {
    final rawDays = (json['days'] as List?) ?? const [];
    final parsed = rawDays
        .whereType<Map>()
        .map((e) =>
            WaterDayStat.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
    return WaterAnalyticsSummary(
      days: parsed,
      streakDays: (json['streak_days'] as num?)?.toInt() ?? 0,
      daysHitTarget: (json['days_hit_target'] as num?)?.toInt() ?? 0,
      avgLiters: (json['avg_liters'] as num?)?.toDouble() ?? 0.0,
      consistencyPct:
          (json['consistency_pct'] as num?)?.toDouble() ?? 0.0,
      targetLiters:
          (json['target_liters'] as num?)?.toDouble() ?? 2.5,
      rangeStart: (json['range_start'] ?? '').toString(),
      rangeEnd: (json['range_end'] ?? '').toString(),
    );
  }

  /// Empty summary used when the RPC fails or the user has no
  /// history yet. Lets the UI render a friendly "no data" state.
  static const empty = WaterAnalyticsSummary(
    days: [],
    streakDays: 0,
    daysHitTarget: 0,
    avgLiters: 0.0,
    consistencyPct: 0.0,
    targetLiters: 2.5,
    rangeStart: '',
    rangeEnd: '',
  );

  /// Returns `true` when the user has no analytics at all — used by
  /// the screen to choose between "you haven't logged yet" and the
  /// populated analytics view.
  bool get isEmpty => days.isEmpty;

  /// Sum of glasses across all days in the window.
  int get totalGlasses =>
      days.fold(0, (acc, d) => acc + d.glasses);

  /// Sum of liters across all days in the window.
  double get totalLiters =>
      days.fold(0.0, (acc, d) => acc + d.liters);

  /// Per-bucket totals across the whole window. Used by the pie.
  Map<String, int> get bucketTotals {
    final out = <String, int>{
      'morning': 0,
      'noon': 0,
      'afternoon': 0,
      'night': 0,
    };
    for (final d in days) {
      d.bucketDistribution.forEach((k, v) {
        out[k] = (out[k] ?? 0) + v;
      });
    }
    return out;
  }

  /// One-line verdict string used by the screen's hero card. The
  /// thresholds mirror the in-app coaching tone: celebrate streaks,
  /// nudge when the user is borderline, push when they're falling
  /// short.
  String verdict() {
    if (isEmpty) return 'এখনও কোনো তথ্য নেই — আজ একটা গ্লাস যোগ করুন!';
    if (consistencyPct >= 85) {
      return 'চমৎকার! আপনি ধারাবাহিকভাবে লক্ষ্য পূরণ করছেন।';
    }
    if (consistencyPct >= 60) {
      return 'ভালো চলছে — দুপুরের গ্লাসটা মিস করবেন না।';
    }
    if (daysHitTarget > 0) {
      return 'কিছুটা এগিয়েছেন — প্রতিদিন ১ গ্লাস বেশি চেষ্টা করুন।';
    }
    return 'এখনই শুরু করুন — একটা গ্লাস দিয়ে দিন শুরু হোক।';
  }
}