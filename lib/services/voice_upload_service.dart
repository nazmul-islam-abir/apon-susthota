/// Voice upload service — uploads a recorded `.m4a` clip to the
/// `voice` Supabase Storage bucket under the convention
/// `{sender_uid}/{receiver_uid}/{epoch_ms}.m4a`.
///
/// The `voice` bucket is declared in 60_voice_messages.sql with
/// per-object RLS: the first path segment must equal
/// `auth.uid()::text`. We therefore can't accidentally upload to
/// another user's folder.
///
/// After upload the caller has a [storagePath]; pair that with the
/// client-measured [durationMs] and call
/// `caretaker_create_voice_schedule` (63_voice_passthrough.sql) to
/// insert the row that the cron will materialize later.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class VoiceUploadService {
  VoiceUploadService._();

  /// Upload [localPath] to the `voice` bucket addressed to
  /// [receiverUserId]. Returns the storage path on success.
  ///
  /// Throws on failure. The caller (typically the compose screen)
  /// should wrap in try/catch and surface a Bangla snackbar on
  /// failure.
  static Future<String> upload({
    required String localPath,
    required String receiverUserId,
    int? durationMs,
  }) async {
    final senderId = SupabaseService.currentUser?.id;
    if (senderId == null) {
      throw StateError('VoiceUploadService: not authenticated');
    }
    final file = File(localPath);
    if (!await file.exists()) {
      throw StateError('VoiceUploadService: local file not found: $localPath');
    }
    final bytes = await file.readAsBytes();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = '$senderId/$receiverUserId/$ts.m4a';

    await SupabaseService.client.storage.from('voice').uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(
        contentType: 'audio/mp4',
        upsert: true,
      ),
    );
    if (kDebugMode) {
      debugPrint('VoiceUploadService.uploaded $path (${bytes.length} bytes)');
    }
    return path;
  }

  /// Best-effort delete of a stored voice. Used when the user
  /// cancels a schedule before the cron materializes it, so we don't
  /// leak orphaned storage objects.
  static Future<void> deleteIfExists(String storagePath) async {
    try {
      await SupabaseService.client.storage.from('voice').remove([storagePath]);
    } catch (e) {
      debugPrint('VoiceUploadService.deleteIfExists failed: $e');
    }
  }

  /// Returns a short-lived signed URL the player can fetch.
  /// Default 1h validity — long enough for an active session, short
  /// enough to limit exposure if the URL leaks.
  static Future<String> signedUrl(String storagePath,
      {Duration validFor = const Duration(hours: 1)}) async {
    return SupabaseService.client.storage
        .from('voice')
        .createSignedUrl(storagePath, validFor.inSeconds);
  }
}
