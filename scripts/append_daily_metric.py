# -*- coding: utf-8 -*-
"""Append DailyMetric class to lib/models/workout.dart."""
import io

NEW = u"""

/// আমার দৈনিক কার্যকলাপের মেট্রিক্স — পানি, হৃদস্পন্দন, পদক্ষেপ।
/// Mirrors row from `supabasesql/18_daily_metrics.sql`.
///
/// • `waterLiters`     — ঐচ্ছিক, ব্যবহারকারী যে পরিমাণ পানি যোগ করেছে।
/// • `heartRateBpm`    — ঐচ্ছিক, শূন্য মানে ‘এখনও সেট করা হয়নি’।
/// • `steps`           — ঐচ্ছিক, ম্যানুয়ালি সেট করা পদক্ষেপ সংখ্যা।
/// • `hasData`         — true হলে ব্যবহারকারী আজ কোনো মেট্রিক্স এন্ট্রি
///                      করেছে; ভুয়া 0 দেখানো এড়াতে UI-তে ফ্ল্যাগ হিসেবে কাজে লাগে।
@immutable
class DailyMetric {
  final double waterLiters;
  final int heartRateBpm;
  final int steps;
  final bool hasData;

  const DailyMetric({
    required this.waterLiters,
    required this.heartRateBpm,
    required this.steps,
    required this.hasData,
  });

  static const empty = DailyMetric(
    waterLiters: 0,
    heartRateBpm: 0,
    steps: 0,
    hasData: false,
  );

  /// Parse from the row returned by `get_today_daily_metrics()`.
  /// The RPC returns a 4-tuple (not a JSON object), so the *first*
  /// row is shaped like: `(water_liters, heart_rate_bpm, steps, has_data)`.
  factory DailyMetric.fromRow(Map<String, dynamic> row) {
    double _d(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0;
      return 0;
    }

    bool _b(dynamic v) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) return v.toLowerCase() == 'true' || v == '1';
      return false;
    }

    return DailyMetric(
      waterLiters: _d(row['water_liters']),
      heartRateBpm: _asInt(row['heart_rate_bpm']) ?? 0,
      steps: _asInt(row['steps']) ?? 0,
      hasData: _b(row['has_data']),
    );
  }

  bool get isWater => waterLiters > 0;
  bool get hasHeartRate => heartRateBpm > 0;
  bool get hasSteps => steps > 0;

  DailyMetric copyWith({
    double? waterLiters,
    int? heartRateBpm,
    int? steps,
    bool? hasData,
  }) {
    return DailyMetric(
      waterLiters: waterLiters ?? this.waterLiters,
      heartRateBpm: heartRateBpm ?? this.heartRateBpm,
      steps: steps ?? this.steps,
      hasData: hasData ?? this.hasData,
    );
  }

  @override
  String toString() =>
      'DailyMetric(water=$waterLiters L, hr=$heartRateBpm bpm, steps=$steps, data=$hasData)';
}
"""

target = r'c:\Users\Nazmul\StudioProjects\diabetics_meal-main\lib\models\workout.dart'

with io.open(target, 'r', encoding='utf-8') as f:
    existing = f.read()

# Guard against duplicate append on re-run.
if 'class DailyMetric' in existing:
    print('SKIP: DailyMetric already exists')
else:
    with io.open(target, 'a', encoding='utf-8') as f:
        if not existing.endswith('\n'):
            f.write('\n')
        f.write(NEW)
    print('OK: appended DailyMetric')
