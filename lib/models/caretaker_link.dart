/// Models for the caretaker ↔ patient link system.
///
/// Mirrors `public.caretaker_patient_links` (28_roles_and_caretaker.sql)
/// and the responses from the helper RPCs in
/// `29_caretaker_read_rpcs.sql` / `30_caretaker_write_passthrough.sql`.
library;

import 'package:flutter/foundation.dart' show immutable;

/// Lifecycle of a caretaker-link request.
///
/// pending   — caretaker sent the request; patient must accept/decline
/// active    — patient accepted; both parties can read/observe
/// declined  — patient explicitly said no; terminal (no auto-resend)
/// revoked   — either party ended the link; terminal; new request needed
enum CaretakerLinkStatus { pending, active, declined, revoked }

extension CaretakerLinkStatusX on CaretakerLinkStatus {
  /// Lowercase string used in the `status` column and JSON wire format.
  String get code {
    switch (this) {
      case CaretakerLinkStatus.pending:
        return 'pending';
      case CaretakerLinkStatus.active:
        return 'active';
      case CaretakerLinkStatus.declined:
        return 'declined';
      case CaretakerLinkStatus.revoked:
        return 'revoked';
    }
  }

  /// Bangla label for status pills.
  String get labelBn {
    switch (this) {
      case CaretakerLinkStatus.pending:
        return 'অপেক্ষমান';
      case CaretakerLinkStatus.active:
        return 'সক্রিয়';
      case CaretakerLinkStatus.declined:
        return 'প্রত্যাখ্যাত';
      case CaretakerLinkStatus.revoked:
        return 'বাতিল';
    }
  }
}

CaretakerLinkStatus _parseCaretakerLinkStatus(String raw) {
  switch (raw) {
    case 'pending':
      return CaretakerLinkStatus.pending;
    case 'active':
      return CaretakerLinkStatus.active;
    case 'declined':
      return CaretakerLinkStatus.declined;
    case 'revoked':
      return CaretakerLinkStatus.revoked;
    default:
      // Legacy/garbage rows must never crash the UI. Default to pending
      // so a stale row shows up in the inbox instead of vanishing.
      return CaretakerLinkStatus.pending;
  }
}

/// A row from `public.caretaker_patient_links`.
///
/// Immutable; copy via `copyWith` and persist via
/// `SupabaseService.{send,respond,revoke}CaretakerLink()`.
@immutable
class CaretakerLink {
  /// UUID primary key. Null for unsaved rows being constructed for
  /// `sendCaretakerRequest()`.
  final String? id;

  /// UID of the caretaker (the one watching).
  final String caretakerUserId;

  /// UID of the patient (the one being observed).
  final String patientUserId;

  /// Current lifecycle state. See [CaretakerLinkStatus].
  final CaretakerLinkStatus status;

  /// Optional note from the caretaker explaining who they are
  /// ("আমি তার মেয়ে, ঢাকায় থাকি"). Free text, length ≤ 500 enforced
  /// by the DB.
  final String? requestNote;

  /// Patient-or-caretaker relationship string ("son", "spouse",
  /// "home nurse"). Mirrors `user_profiles.caretaker_relationship`
  /// for caretakers, but can be filled in per-link to support
  /// multiple relatives per patient.
  final String? caretakerRelationship;

  /// When the caretaker sent the request. UTC, ISO-8601.
  final DateTime? requestedAt;

  /// When the patient accepted/declined the request. UTC.
  final DateTime? respondedAt;

  /// When the caretaker last opened this patient. Bumped by
  /// `get_caretaker_today_overview` so the patient list can sort
  /// "most recently observed" first. UTC.
  final DateTime? lastSeenAt;

  /// Server-side write timestamps for audit. UTC.
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Optional display name of the OTHER party (caretaker name when
  /// shown to a patient; patient name when shown to a caretaker).
  /// Filled by RPCs that join `user_profiles.full_name` so the
  /// inbox renders a real name instead of "কেয়ারটেকার".
  final String? otherFullName;

  /// Optional avatar URL of the OTHER party. Same source as above.
  final String? otherAvatarUrl;

  /// Optional email of the OTHER party. Joined from
  /// `user_profiles.email` by inbox RPCs so the request card can
  /// show who's reaching out (FB-style friend request preview).
  final String? otherEmail;

  /// Optional age of the OTHER party (years). Joined from
  /// `user_profiles.age`.
  final int? otherAge;

  /// Optional sex of the OTHER party. Bangla values used by the app
  /// ("পুরুষ" / "মহিলা"), or the raw DB column. Joined from
  /// `user_profiles.sex`.
  final String? otherSex;

  const CaretakerLink({
    this.id,
    required this.caretakerUserId,
    required this.patientUserId,
    required this.status,
    this.requestNote,
    this.caretakerRelationship,
    this.requestedAt,
    this.respondedAt,
    this.lastSeenAt,
    this.createdAt,
    this.updatedAt,
    this.otherFullName,
    this.otherAvatarUrl,
    this.otherEmail,
    this.otherAge,
    this.otherSex,
  });

  factory CaretakerLink.fromSupabaseRow(Map<String, dynamic> row) {
    DateTime? _parseDt(Object? v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is String && v.isNotEmpty) {
        return DateTime.tryParse(v)?.toUtc();
      }
      return null;
    }

    int? _parseInt(Object? v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    return CaretakerLink(
      id: row['id'] as String?,
      caretakerUserId: row['caretaker_user_id'] as String,
      patientUserId: row['patient_user_id'] as String,
      status: _parseCaretakerLinkStatus((row['status'] as String?) ?? 'pending'),
      requestNote: row['request_note'] as String?,
      caretakerRelationship: row['caretaker_relationship'] as String?,
      requestedAt: _parseDt(row['requested_at']),
      respondedAt: _parseDt(row['responded_at']),
      lastSeenAt: _parseDt(row['last_seen_at']),
      createdAt: _parseDt(row['created_at']),
      updatedAt: _parseDt(row['updated_at']),
      // SQL returns either `caretaker_*` / `patient_*` keys depending
      // on which inbox RPC we're reading from. The `other_*` alias is
      // used by a unified view, if present.
      otherFullName: (row['other_full_name'] ??
              row['caretaker_full_name'] ??
              row['patient_full_name']) as String?,
      otherAvatarUrl: (row['other_avatar_url'] ??
              row['caretaker_avatar_url'] ??
              row['patient_avatar_url']) as String?,
      otherEmail: (row['other_email'] ??
              row['caretaker_email'] ??
              row['patient_email']) as String?,
      otherAge: _parseInt(row['other_age'] ??
          row['caretaker_age'] ??
          row['patient_age']),
      otherSex: (row['other_sex'] ??
              row['caretaker_sex'] ??
              row['patient_sex']) as String?,
    );
  }

  /// Convenience: `Map<String, dynamic>` shaped exactly like the
  /// `caretaker_patient_links` row. Used for tests + optimistic
  /// provider-side state.
  Map<String, dynamic> toSupabaseRow() => {
        if (id != null) 'id': id,
        'caretaker_user_id': caretakerUserId,
        'patient_user_id': patientUserId,
        'status': status.code,
        'request_note': requestNote,
        'caretaker_relationship': caretakerRelationship,
        'requested_at': requestedAt?.toUtc().toIso8601String(),
        'responded_at': respondedAt?.toUtc().toIso8601String(),
        'last_seen_at': lastSeenAt?.toUtc().toIso8601String(),
      };

  CaretakerLink copyWith({
    String? id,
    String? caretakerUserId,
    String? patientUserId,
    CaretakerLinkStatus? status,
    String? requestNote,
    String? caretakerRelationship,
    DateTime? requestedAt,
    DateTime? respondedAt,
    DateTime? lastSeenAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CaretakerLink(
      id: id ?? this.id,
      caretakerUserId: caretakerUserId ?? this.caretakerUserId,
      patientUserId: patientUserId ?? this.patientUserId,
      status: status ?? this.status,
      requestNote: requestNote ?? this.requestNote,
      caretakerRelationship:
          caretakerRelationship ?? this.caretakerRelationship,
      requestedAt: requestedAt ?? this.requestedAt,
      respondedAt: respondedAt ?? this.respondedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// True for terminal states that the patient should NOT see in their
  /// inbox (the row stays in the DB for audit + "revoked before" replies).
  bool get isTerminal =>
      status == CaretakerLinkStatus.declined ||
      status == CaretakerLinkStatus.revoked;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is CaretakerLink && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
