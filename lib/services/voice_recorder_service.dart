/// Voice recording service — singleton wrapper over `record` v5.
///
/// The caretaker taps the mic, this starts recording into a temp
/// `.m4a` file; tapping again stops and returns the path. The path
/// is then handed to [VoiceUploadService] for upload to the
/// `voice` Supabase Storage bucket.
///
/// AAC-LC at 64 kbps mono gives ~8 KB/s — a 60-second clip is
/// ~500 KB. Plenty small for Supabase Storage on a typical mobile
/// connection.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// State of the recorder. Surfaced to widgets that want to render
/// a live counter or pulse animation.
enum VoiceRecorderState { idle, recording, stopped, denied }

class VoiceRecorderService {
  VoiceRecorderService._();
  static final VoiceRecorderService instance = VoiceRecorderService._();

  final AudioRecorder _recorder = AudioRecorder();
  String? _activePath;
  DateTime? _startedAt;

  final ValueNotifier<VoiceRecorderState> state =
      ValueNotifier(VoiceRecorderState.idle);
  final ValueNotifier<Duration> elapsed = ValueNotifier(Duration.zero);

  Timer? _ticker;

  /// True if the recorder is currently capturing audio.
  bool get isRecording => state.value == VoiceRecorderState.recording;

  /// Path to the most recently recorded file (set after [stop]).
  String? get lastFilePath => _activePath;

  /// Best-effort request for microphone permission. Returns true on
  /// grant, false on deny. We don't open Settings here — the caller
  /// can decide what UX to show.
  Future<bool> ensurePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted || status.isLimited;
  }

  /// Start a new recording. If a previous recording exists, it is
  /// overwritten in the temp dir (but [lastFilePath] still returns
  /// the most recent path).
  ///
  /// Returns true on success, false if permission was denied or the
  /// recorder failed to start.
  Future<bool> start() async {
    if (isRecording) return true;
    final ok = await ensurePermission();
    if (!ok) {
      state.value = VoiceRecorderState.denied;
      return false;
    }

    try {
      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = '${dir.path}/voice_$ts.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 22050,
          numChannels: 1,
        ),
        path: path,
      );

      _activePath = path;
      _startedAt = DateTime.now();
      state.value = VoiceRecorderState.recording;
      elapsed.value = Duration.zero;
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (_startedAt == null) return;
        elapsed.value = DateTime.now().difference(_startedAt!);
      });
      return true;
    } catch (e) {
      debugPrint('VoiceRecorderService.start failed: $e');
      state.value = VoiceRecorderState.idle;
      return false;
    }
  }

  /// Stop the current recording and return the path to the .m4a
  /// file on disk, or null if nothing was recording.
  Future<String?> stop() async {
    if (!isRecording) return _activePath;
    try {
      final path = await _recorder.stop();
      _ticker?.cancel();
      _ticker = null;
      _startedAt = null;
      state.value = VoiceRecorderState.stopped;
      if (path != null) _activePath = path;
      return _activePath;
    } catch (e) {
      debugPrint('VoiceRecorderService.stop failed: $e');
      state.value = VoiceRecorderState.idle;
      return null;
    }
  }

  /// Discard the most recent recording and free the temp file.
  Future<void> discard() async {
    final path = _activePath;
    _activePath = null;
    _startedAt = null;
    _ticker?.cancel();
    _ticker = null;
    state.value = VoiceRecorderState.idle;
    elapsed.value = Duration.zero;
    if (path != null) {
      final f = File(path);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {/* best-effort */}
      }
    }
  }

  /// Best-effort length of the current recording in milliseconds.
  /// For UI display only — accurate value comes from the
  /// `duration_ms` we stored in voice_schedules / voice_messages.
  int get currentDurationMs => elapsed.value.inMilliseconds;

  /// Release native resources. Call from `dispose()` of long-lived
  /// stateful widgets if you want — singleton otherwise lives for
  /// the app lifetime.
  Future<void> dispose() async {
    _ticker?.cancel();
    _ticker = null;
    await _recorder.dispose();
    state.dispose();
    elapsed.dispose();
  }
}
