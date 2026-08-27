/// Row shape returned by `get_caretaker_patient_list`.
///
/// One row per patient a caretaker is actively watching (or has a
/// pending request for). Used by the caretaker "Patients" tab to
/// render the list without N+1 round-trips.
library;

import 'package:flutter/foundation.dart' show immutable;

/// Lightweight, read-only summary of a patient as seen from the
/// caretaker's list view. Not the full `UserProfile` — caretakers
/// never see PII like mobile or full medical history here.
@immutable
class CaretakerPatientSummary {
  /// Patient's auth.users.uid. Used for drilldown RPCs.
  final String patientUserId;

  /// Display name from `user_profiles.full_name`. Falls back to
  /// "রোগী" when the patient has not entered a name yet.
  final String fullName;

  /// Bangla subtitle: relationship string from the link
  /// ("ছেলে", "স্বামী") — what the caretaker wrote at request time.
  final String? caretakerRelationship;

  /// Avatar URL from the patient's profile photo. May be null.
  final String? avatarUrl;

  /// Last time the caretaker opened this patient (touched by
  /// `get_caretaker_today_overview`). UTC. Used for "Recently
  /// observed" sorting in the list.
  final DateTime? lastSeenAt;

  /// Number of meals logged in the trailing 7 days.
  /// 0 → patient is inactive; UI renders an "inactive" pill.
  final int mealsLast7Days;

  /// Number of meals planned in the trailing 7 days.
  /// Adherence = mealsLast7Days / mealsPlannedLast7Days.
  final int mealsPlannedLast7Days;

  /// 0..1 — fraction of planned meals the patient logged.
  /// Null when `mealsPlannedLast7Days == 0`.
  final double? mealAdherence7d;

  /// Number of medicine doses the patient took in the trailing 7
  /// days (vs. planned). 0..1. Null when no medicines are configured.
  final double? medicineAdherence7d;

  /// Most recent HbA1c from the patient's profile (snapshot field
  /// — never auto-updates from daily glucose logs). Null if unset.
  final double? hba1cPercent;

  /// Most recent fasting glucose (mmol/L) from the patient's profile.
  /// Null if unset.
  final double? fastingGlucoseMmol;

  /// Latest link status. Should always be active for items in this
  /// list, but kept so the UI can render a "অপেক্ষমান" badge for the
  /// brief window between send and accept.
  final String linkStatus;

  /// True when the row was created by the caretaker's own request
  /// (i.e. the caretaker sent the link invite). False when the
  /// patient initiated the connection. Null when the RPC didn't
  /// expose this — in which case the connection card renders a
  /// neutral "সংযোগকারীর তথ্য উপলব্ধ নেই" line.
  final bool? initiatedByMe;

  /// When the link was created (UTC). Optional.
  final DateTime? linkedAt;

  const CaretakerPatientSummary({
    required this.patientUserId,
    required this.fullName,
    this.caretakerRelationship,
    this.avatarUrl,
    this.lastSeenAt,
    required this.mealsLast7Days,
    required this.mealsPlannedLast7Days,
    this.mealAdherence7d,
    this.medicineAdherence7d,
    this.hba1cPercent,
    this.fastingGlucoseMmol,
    required this.linkStatus,
    this.initiatedByMe,
    this.linkedAt,
  });

  /// True when the patient has logged anything in the last 24h
  /// (proxy: any meal in the last day). UI uses this to render the
  /// green "সক্রিয়" pill vs. gray "নিষ্ক্রিয়".
  bool get isActive {
    if (lastSeenAt == null) return false;
    return DateTime.now().toUtc().difference(lastSeenAt!.toUtc()).inHours < 24;
  }

  /// Bangla subtitle for the list row: caretaking relationship,
  /// never falls back to the patient's name (PII boundary).
  String get subtitleBn {
    final rel = caretakerRelationship?.trim();
    if (rel == null || rel.isEmpty) return 'পরিচর্যাকারী সংযুক্তি';
    return rel;
  }

  /// Adherence pill text in Bangla, formatted as a percent.
  /// Returns "—" when adherence is undefined.
  String get adherencePillBn {
    final a = mealAdherence7d;
    if (a == null) return '—';
    return '${(a * 100).round()}%';
  }

  factory CaretakerPatientSummary.fromRpcJson(Map<String, dynamic> json) {
    DateTime? _parseDt(Object? v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is String && v.isNotEmpty) {
        return DateTime.tryParse(v)?.toUtc();
      }
      return null;
    }

    double? _parseDouble(Object? v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    int _parseInt(Object? v, {int fallback = 0}) {
      if (v == null) return fallback;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    return CaretakerPatientSummary(
      patientUserId: json['patient_user_id'] as String,
      fullName: (json['full_name'] as String?) ?? 'রোগী',
      caretakerRelationship: json['caretaker_relationship'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      lastSeenAt: _parseDt(json['last_seen_at']),
      mealsLast7Days: _parseInt(json['meals_last_7_days']),
      mealsPlannedLast7Days: _parseInt(json['meals_planned_7_days']),
      mealAdherence7d: _parseDouble(json['meal_adherence_7d']),
      medicineAdherence7d: _parseDouble(json['medicine_adherence_7d']),
      hba1cPercent: _parseDouble(json['hba1c_percent']),
      fastingGlucoseMmol: _parseDouble(json['fasting_glucose_mmol']),
      linkStatus: (json['link_status'] as String?) ?? 'active',
      initiatedByMe: json['initiated_by_me'] as bool?,
      linkedAt: _parseDt(json['linked_at']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CaretakerPatientSummary &&
          other.patientUserId == patientUserId);

  @override
  int get hashCode => patientUserId.hashCode;
}
