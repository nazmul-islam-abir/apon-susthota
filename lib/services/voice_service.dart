/// Voice CRUD service — thin wrappers over the voice-message RPCs
/// declared in 63_voice_passthrough.sql.
///
/// All methods follow the same pattern as the rest of the app:
/// try/catch around the RPC, return an empty list / null on
/// failure so the UI can render an empty-state instead of crashing.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/voice_message.dart';
import 'supabase_service.dart';

class VoiceService {
  VoiceService._();

  static SupabaseClient get _client => SupabaseService.client;

  // ─── Caretaker side ─────────────────────────────────────────────────────

  /// Schedule a voice for delivery at [deliverAt] (UTC).
  /// Returns the new schedule id.
  static Future<String> createSchedule({
    required String patientUserId,
    required String storagePath,
    required int durationMs,
    required String timezone,
    required DateTime deliverAt,
    String? caption,
  }) async {
    final res = await _client.rpc('caretaker_create_voice_schedule', params: {
      'p_patient_user_id': patientUserId,
      'p_storage_path': storagePath,
      'p_duration_ms': durationMs,
      'p_timezone': timezone,
      'p_deliver_at': deliverAt.toUtc().toIso8601String(),
      'p_caption': caption,
    });
    return res as String;
  }

  /// Force the server to materialize any pending voice_schedules
  /// whose deliver_at has already passed. The pg_cron job defined
  /// in `61_voice_cron.sql` runs every minute, but if it is missing
  /// or broken, this fallback ensures the patient still receives the
  /// voice immediately when the caretaker taps "Send" for a
  /// "deliver now / within the next 2 minutes" schedule.
  ///
  /// Safe to call repeatedly — the underlying SQL is idempotent and
  /// uses `FOR UPDATE SKIP LOCKED`, so concurrent calls don't
  /// double-insert. Returns the number of voice_messages rows
  /// newly materialized by this call (0 = nothing was due).
  static Future<int> materializeDueNow() async {
    try {
      final res = await _client.rpc('materialize_due_voices_now');
      if (res is int) return res;
      if (res is num) return res.toInt();
      return 0;
    } catch (_) {
      // If the RPC isn't installed yet (the user hasn't run
      // 64_voice_cron_fix.sql), we silently no-op — the cron job
      // (if scheduled) will still pick it up. Best-effort.
      return 0;
    }
  }

  /// Returns true when [deliverAt] is "effectively now" — within
  /// 2 minutes of the current time. Used by the compose screen
  /// to decide whether to trigger the instant-materialize fallback.
  static bool isEffectivelyNow(DateTime deliverAt) {
    final now = DateTime.now().toUtc();
    final delta = deliverAt.toUtc().difference(now).inSeconds.abs();
    return delta <= 120; // 2 minutes
  }

  /// Cancel a still-pending schedule.
  static Future<void> cancelSchedule(String scheduleId) async {
    await _client.rpc('caretaker_cancel_voice_schedule', params: {
      'p_schedule_id': scheduleId,
    });
  }

  /// List the caretaker's schedules for one patient.
  static Future<List<VoiceSchedule>> listSchedulesForPatient(
      String patientUserId) async {
    try {
      final res = await _client.rpc('list_caretaker_voice_schedules', params: {
        'p_patient_user_id': patientUserId,
      });
      final list = (res as List?) ?? const [];
      return list
          .whereType<Map>()
          .map((e) =>
              VoiceSchedule.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Caretaker's view of the patient inbox (includes both
  /// materialized caretaker voices and patient replies).
  static Future<List<VoiceMessage>> listInboxForPatient(
      String patientUserId) async {
    try {
      final res = await _client.rpc('list_caretaker_voice_inbox', params: {
        'p_patient_user_id': patientUserId,
      });
      final list = (res as List?) ?? const [];
      return list
          .whereType<Map>()
          .map((e) =>
              VoiceMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Caretaker sends a follow-up voice directly (bypasses scheduling).
  static Future<String> sendReply({
    required String patientUserId,
    required String storagePath,
    required int durationMs,
    String? caption,
    String? threadId,
  }) async {
    final res = await _client.rpc('caretaker_send_voice_reply', params: {
      'p_patient_user_id': patientUserId,
      'p_storage_path': storagePath,
      'p_duration_ms': durationMs,
      'p_caption': caption,
      'p_thread_id': threadId,
    });
    return res as String;
  }

  // ─── Patient side ───────────────────────────────────────────────────────

  /// Patient fetches their own inbox.
  static Future<List<VoiceMessage>> listMyInbox() async {
    try {
      final res = await _client.rpc('list_my_voice_inbox');
      final list = (res as List?) ?? const [];
      return list
          .whereType<Map>()
          .map((e) =>
              VoiceMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Patient fetches the full thread for a given message id (used
  /// when tapping into a single voice to see replies).
  static Future<List<VoiceMessage>> listThread(String threadId) async {
    try {
      final res = await _client.rpc('list_voice_thread', params: {
        'p_thread_id': threadId,
      });
      final list = (res as List?) ?? const [];
      return list
          .whereType<Map>()
          .map((e) =>
              VoiceMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Mark a voice as played by the receiver. Idempotent on the
  /// server side.
  static Future<void> markPlayed(String messageId) async {
    try {
      await _client.rpc('mark_voice_played', params: {
        'p_message_id': messageId,
      });
    } catch (_) {/* best-effort */}
  }

  // ─── Patient reply (direct insert) ──────────────────────────────────────

  /// Patient replies with their own voice. The insert is gated by
  /// the sender-only RLS policy on voice_messages (60_*.sql).
  static Future<String> patientReply({
    required String receiverUserId,
    required String storagePath,
    required int durationMs,
    String? caption,
    String? threadId,
  }) async {
    final senderId = SupabaseService.currentUser?.id;
    if (senderId == null) {
      throw StateError('VoiceService.patientReply: not authenticated');
    }
    final res = await _client.from('voice_messages').insert({
      'sender_user_id': senderId,
      'receiver_user_id': receiverUserId,
      'storage_path': storagePath,
      'duration_ms': durationMs,
      'caption': caption,
      'thread_id': threadId,
      'is_reply': true,
    }).select('id').single();
    return res['id'] as String;
  }
}
