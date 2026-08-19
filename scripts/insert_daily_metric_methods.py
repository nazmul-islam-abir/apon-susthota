# -*- coding: utf-8 -*-
"""Insert DailyMetric-related RPC methods into SupabaseService."""
import io

NEW = u"""
  /// Today's water / heart-rate / steps row. Falls back to
  /// `DailyMetric.empty` on any error so the screen never shows a
  /// loading spinner stuck in place when the RPC is offline.
  static Future<DailyMetric> getTodayDailyMetrics() async {
    try {
      final result = await client.rpc('get_today_daily_metrics');
      if (result is List && result.isNotEmpty) {
        final first = result.first;
        if (first is Map) {
          return DailyMetric.fromRow(Map<String, dynamic>.from(first));
        }
      }
      return DailyMetric.empty;
    } catch (e) {
      debugPrint('getTodayDailyMetrics error: $e');
      return DailyMetric.empty;
    }
  }

  /// Quick-add water (e.g. +0.25 L from a tap). Atomic on the server
  /// so concurrent taps never lose the delta.
  static Future<DailyMetric> addWaterLiters(double deltaLiters) async {
    try {
      final result = await client.rpc(
        'add_water_liters',
        params: {'p_delta': deltaLiters},
      );
      if (result is List && result.isNotEmpty && result.first is Map) {
        return DailyMetric.fromRow(Map<String, dynamic>.from(result.first));
      }
      return DailyMetric.empty;
    } catch (e) {
      debugPrint('addWaterLiters error: $e');
      return DailyMetric.empty;
    }
  }

  /// Set heart rate (absolute value, clamped 30–230 on the server).
  static Future<DailyMetric> setHeartRate(int bpm) async {
    try {
      final result = await client.rpc(
        'upsert_daily_metric',
        params: {'p_field': 'heart_rate_bpm', 'p_value': bpm},
      );
      if (result is List && result.isNotEmpty && result.first is Map) {
        return DailyMetric.fromRow(Map<String, dynamic>.from(result.first));
      }
      return DailyMetric.empty;
    } catch (e) {
      debugPrint('setHeartRate error: $e');
      return DailyMetric.empty;
    }
  }

  /// Set step count (absolute value, clamped 0–200000 on the server).
  static Future<DailyMetric> setSteps(int steps) async {
    try {
      final result = await client.rpc(
        'upsert_daily_metric',
        params: {'p_field': 'steps', 'p_value': steps},
      );
      if (result is List && result.isNotEmpty && result.first is Map) {
        return DailyMetric.fromRow(Map<String, dynamic>.from(result.first));
      }
      return DailyMetric.empty;
    } catch (e) {
      debugPrint('setSteps error: $e');
      return DailyMetric.empty;
    }
  }

"""

target = r'c:\Users\Nazmul\StudioProjects\diabetics_meal-main\lib\services\supabase_service.dart'

with io.open(target, 'r', encoding='utf-8') as f:
    src = f.read()

if 'getTodayDailyMetrics' in src:
    print('SKIP: already present')
else:
    # Insert right after the closing brace of getTodayExerciseTimeFeedback
    marker = u"      debugPrint('getTodayExerciseTimeFeedback error: $e');\n      return const {};\n    }\n  }"
    if marker not in src:
        print('ERROR: marker not found')
        raise SystemExit(1)
    new_src = src.replace(marker, marker + NEW, 1)
    with io.open(target, 'w', encoding='utf-8') as f:
        f.write(new_src)
    print('OK: inserted 4 methods')