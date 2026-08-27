/// Single entry on the caretaker's "recent activities" feed.
///
/// Returned by `get_caretaker_recent_activities` — a merged feed of
/// meal logs, medicine doses, water logs, and workout completions
/// for a single patient. Used by the patient detail screen and the
/// caretaker "Today" tab to show "what just happened" without
/// hitting four separate endpoints.
library;

import 'package:flutter/foundation.dart' show immutable;

/// What kind of activity this row represents. The string values are
/// stable wire codes used by both the RPC and the analytics layer.
enum CaregiverObservationKind { meal, medicine, water, workout }

extension CaregiverObservationKindX on CaregiverObservationKind {
  String get code {
    switch (this) {
      case CaregiverObservationKind.meal:
        return 'meal';
      case CaregiverObservationKind.medicine:
        return 'medicine';
      case CaregiverObservationKind.water:
        return 'water';
      case CaregiverObservationKind.workout:
        return 'workout';
    }
  }

  String get labelBn {
    switch (this) {
      case CaregiverObservationKind.meal:
        return 'খাবার';
      case CaregiverObservationKind.medicine:
        return 'ওষুধ';
      case CaregiverObservationKind.water:
        return 'পানি';
      case CaregiverObservationKind.workout:
        return 'ব্যায়াম';
    }
  }
}

CaregiverObservationKind _parseKind(String raw) {
  switch (raw) {
    case 'meal':
      return CaregiverObservationKind.meal;
    case 'medicine':
      return CaregiverObservationKind.medicine;
    case 'water':
      return CaregiverObservationKind.water;
    case 'workout':
      return CaregiverObservationKind.workout;
    default:
      // Unknown kinds never crash the UI; treated as meal so the
      // row stays visible until the schema catches up.
      return CaregiverObservationKind.meal;
  }
}

/// Single activity row from the merged feed.
///
/// [summaryBn] is a short Bangla headline ("মুরগি + ভাত খেয়েছেন")
/// and [detail] is an optional structured payload (meal_slot,
/// food_name_bn, impact, dose status, workout duration, etc). The
/// RPC returns `detail` as `jsonb`, so the field type is
/// `Map<String, dynamic>?`. Renderers call `.toString()` on the
/// value if they want a single string.
@immutable
class CaregiverObservation {
  /// When the activity happened (UTC, ISO-8601).
  final DateTime occurredAt;

  /// Bucket of activity — see [CaregiverObservationKind].
  final CaregiverObservationKind kind;

  /// Bangla headline shown as the primary line in the feed.
  final String summaryBn;

  /// Optional structured detail (jsonb). Keys vary by [kind]:
  ///   * meal    → {meal_slot, food_name_bn, impact}
  ///   * water   → {liters, bucket}
  ///   * medicine → {status, scheduled_time}
  ///   * workout → {total_items, completed_items, duration_seconds}
  /// Null when the activity has no payload.
  final Map<String, dynamic>? detail;

  /// Free-form color hint for the row's left rail accent.
  /// 'good' | 'warn' | 'bad' | 'neutral'. Defaults to 'neutral'
  /// because the current RPC does not return a `tone` column —
  /// callers can derive tone from `kind` + `detail` instead.
  final String tone;

  const CaregiverObservation({
    required this.occurredAt,
    required this.kind,
    required this.summaryBn,
    this.detail,
    required this.tone,
  });

  factory CaregiverObservation.fromRpcJson(Map<String, dynamic> json) {
    DateTime _parseDt(Object? v) {
      if (v is DateTime) return v.toUtc();
      if (v is String && v.isNotEmpty) {
        return DateTime.tryParse(v)?.toUtc() ??
            DateTime.now().toUtc();
      }
      return DateTime.now().toUtc();
    }

    Object? rawDetail = json['detail'];
    Map<String, dynamic>? detail;
    if (rawDetail is Map) {
      detail = Map<String, dynamic>.from(rawDetail);
    } else if (rawDetail is String && rawDetail.isNotEmpty) {
      // Older RPC variants sent detail as text. Wrap it so
      // callers can treat it uniformly.
      detail = {'text': rawDetail};
    }

    // Derive a tonal hint from kind + detail (RPC doesn't return a
    // `tone` column). Default 'neutral'.
    String tone = (json['tone'] as String?) ?? _deriveTone(
          _parseKind((json['kind'] as String?) ?? 'meal'),
          detail,
        );

    return CaregiverObservation(
      occurredAt: _parseDt(json['occurred_at']),
      kind: _parseKind((json['kind'] as String?) ?? 'meal'),
      summaryBn: (json['summary_bn'] as String?) ?? '',
      detail: detail,
      tone: tone,
    );
  }

  static String _deriveTone(
    CaregiverObservationKind kind,
    Map<String, dynamic>? detail,
  ) {
    if (detail == null) return 'neutral';
    if (kind == CaregiverObservationKind.medicine) {
      final s = detail['status'];
      if (s == 'missed' || s == 'skipped') return 'warn';
      if (s == 'taken') return 'good';
    }
    if (kind == CaregiverObservationKind.meal) {
      if (detail['impact'] == 'high') return 'warn';
      if (detail['impact'] == 'low' || detail['impact'] == 'good') return 'good';
    }
    if (kind == CaregiverObservationKind.water) {
      return 'good';
    }
    if (kind == CaregiverObservationKind.workout) {
      return 'good';
    }
    return 'neutral';
  }
}