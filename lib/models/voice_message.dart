/// Models for the voice-message feature.
///
/// `voice_schedules` (caretaker → patient scheduled delivery) and
/// `voice_messages` (the materialized inbox rows the patient
/// actually sees, plus the patient's reply back). See
/// `supabasesql/60_voice_messages.sql` for the table shapes and
/// `63_voice_passthrough.sql` for the JSON payload format returned
/// by `list_my_voice_inbox`, `list_caretaker_voice_inbox`, and
/// `list_voice_thread`.
library;

import 'package:flutter/foundation.dart' show immutable;

/// Lifecycle of a `voice_schedules.status` row.
///
/// pending   — caretaker queued; waiting for deliver_at
/// delivered — materialized into a voice_messages row
/// cancelled — caretaker cancelled before delivery
enum VoiceScheduleStatus { pending, delivered, cancelled }

extension VoiceScheduleStatusX on VoiceScheduleStatus {
  String get code {
    switch (this) {
      case VoiceScheduleStatus.pending:
        return 'pending';
      case VoiceScheduleStatus.delivered:
        return 'delivered';
      case VoiceScheduleStatus.cancelled:
        return 'cancelled';
    }
  }

  /// Bangla label for status pills / list headers.
  String get labelBn {
    switch (this) {
      case VoiceScheduleStatus.pending:
        return 'শিডিউল হয়েছে';
      case VoiceScheduleStatus.delivered:
        return 'পৌঁছে গেছে';
      case VoiceScheduleStatus.cancelled:
        return 'বাতিল';
    }
  }
}

VoiceScheduleStatus _parseScheduleStatus(String? raw) {
  switch (raw) {
    case 'delivered':
      return VoiceScheduleStatus.delivered;
    case 'cancelled':
      return VoiceScheduleStatus.cancelled;
    case 'pending':
    default:
      return VoiceScheduleStatus.pending;
  }
}

/// A row from `public.voice_schedules`.
///
/// Caretaker-recorded, server-delivered. The schedule itself is
/// invisible to the patient until the cron materializes it.
@immutable
class VoiceSchedule {
  final String id;
  final String caretakerUserId;
  final String patientUserId;
  final String storagePath;
  final int durationMs;
  final String timezone;
  final DateTime deliverAt;
  final String? caption;
  final VoiceScheduleStatus status;
  final String? deliveredMessageId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const VoiceSchedule({
    required this.id,
    required this.caretakerUserId,
    required this.patientUserId,
    required this.storagePath,
    required this.durationMs,
    required this.timezone,
    required this.deliverAt,
    required this.status,
    this.caption,
    this.deliveredMessageId,
    this.createdAt,
    this.updatedAt,
  });

  factory VoiceSchedule.fromJson(Map<String, dynamic> json) {
    DateTime? parseDt(Object? v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toUtc();
      return null;
    }

    int parseInt(Object? v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    return VoiceSchedule(
      id: json['id'] as String,
      caretakerUserId: json['caretaker_user_id'] as String,
      patientUserId: json['patient_user_id'] as String,
      storagePath: json['storage_path'] as String,
      durationMs: parseInt(json['duration_ms']),
      timezone: (json['timezone'] as String?) ?? 'Asia/Dhaka',
      deliverAt:
          parseDt(json['deliver_at']) ?? DateTime.now().toUtc(),
      caption: json['caption'] as String?,
      status: _parseScheduleStatus(json['status'] as String?),
      deliveredMessageId: json['delivered_message_id'] as String?,
      createdAt: parseDt(json['created_at']),
      updatedAt: parseDt(json['updated_at']),
    );
  }

  VoiceSchedule copyWith({VoiceScheduleStatus? status}) => VoiceSchedule(
        id: id,
        caretakerUserId: caretakerUserId,
        patientUserId: patientUserId,
        storagePath: storagePath,
        durationMs: durationMs,
        timezone: timezone,
        deliverAt: deliverAt,
        caption: caption,
        status: status ?? this.status,
        deliveredMessageId: deliveredMessageId,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  /// Pretty "0:42" duration string for list rows.
  String get durationLabel {
    final totalSec = (durationMs / 1000).round();
    final m = (totalSec ~/ 60).toString().padLeft(1, '0');
    final s = (totalSec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// A row from `public.voice_messages` — what the patient actually
/// sees in their inbox, plus the patient's reply back to the
/// caretaker.
///
/// Field semantics:
///   * senderUserId   — who recorded the voice (caretaker or patient)
///   * receiverUserId — who will hear it
///   * isReply        — true if sender is replying (vs. fresh material)
///   * threadId       — groups a voice with its replies
///   * playedAt       — receiver tapped play (nullable; null = unplayed)
@immutable
class VoiceMessage {
  final String id;
  final String senderUserId;
  final String receiverUserId;
  final String storagePath;
  final int durationMs;
  final String? caption;
  final String? threadId;
  final bool isReply;
  final DateTime? playedAt;
  final DateTime createdAt;

  // Display fields joined from `user_profiles` by the SQL RPCs.
  // Optional because the sender might be deleted or have no profile row.
  final String? senderName;
  final String? senderUsername;
  final String? senderAvatarUrl;

  const VoiceMessage({
    required this.id,
    required this.senderUserId,
    required this.receiverUserId,
    required this.storagePath,
    required this.durationMs,
    required this.isReply,
    required this.createdAt,
    this.caption,
    this.threadId,
    this.playedAt,
    this.senderName,
    this.senderUsername,
    this.senderAvatarUrl,
  });

  factory VoiceMessage.fromJson(Map<String, dynamic> json) {
    DateTime? parseDt(Object? v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toUtc();
      return null;
    }

    int parseInt(Object? v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    bool parseBool(Object? v) {
      if (v == null) return false;
      if (v is bool) return v;
      if (v is String) return v.toLowerCase() == 'true' || v == '1';
      if (v is num) return v != 0;
      return false;
    }

    return VoiceMessage(
      id: json['id'] as String,
      senderUserId: json['sender_user_id'] as String,
      receiverUserId: json['receiver_user_id'] as String,
      storagePath: json['storage_path'] as String,
      durationMs: parseInt(json['duration_ms']),
      caption: json['caption'] as String?,
      threadId: json['thread_id'] as String?,
      isReply: parseBool(json['is_reply']),
      playedAt: parseDt(json['played_at']),
      createdAt:
          parseDt(json['created_at']) ?? DateTime.now().toUtc(),
      senderName: (json['sender_name'] ??
              json['sender_full_name']) as String?,
      senderUsername: json['sender_username'] as String?,
      senderAvatarUrl: json['sender_avatar_url'] as String?,
    );
  }

  String get durationLabel {
    final totalSec = (durationMs / 1000).round();
    final m = (totalSec ~/ 60).toString();
    final s = (totalSec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  bool get isUnplayed => playedAt == null;

  /// Best-effort display name: prefer the joined profile name, fall
  /// back to a short UUID prefix so the UI never shows "null".
  String get senderLabel {
    final n = senderName?.trim();
    if (n != null && n.isNotEmpty) return n;
    final u = senderUsername?.trim();
    if (u != null && u.isNotEmpty) return '@$u';
    return senderUserId.substring(0, 8);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is VoiceMessage && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
