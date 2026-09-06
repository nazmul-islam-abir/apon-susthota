/// Voice playback service — singleton wrapper over `audioplayers` v6.
///
/// Fetches a short-lived signed URL from the `voice` Supabase Storage
/// bucket (the storage RLS in 60_voice_messages.sql gates access by
/// uid segment match), then plays it. We reuse one [AudioPlayer] for
/// the whole app — only one voice plays at a time; tapping a second
/// bubble stops the first.
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'supabase_service.dart';

class VoicePlayerService {
  VoicePlayerService._();
  static final VoicePlayerService instance = VoicePlayerService._();

  final AudioPlayer _player = AudioPlayer();
  String? _currentUrl;

  /// Synchronous mirror of `isPlaying`. The
  /// `onPlayerStateChanged` listener fires asynchronously, so the
  /// `isPlaying` ValueNotifier can lag the actual player state by
  /// several hundred ms — long enough for a fast double-tap to
  /// read a stale value. `_localPlaying` is updated synchronously
  /// inside pause/resume/play/stop so that consecutive taps always
  /// see the latest truth.
  bool _localPlaying = false;
  final ValueNotifier<String?> playingUrl = ValueNotifier<String?>(null);
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> duration = ValueNotifier(Duration.zero);
  final ValueNotifier<bool> isPlaying = ValueNotifier(false);

  VoicePlayerService() {
    _player.onPlayerComplete.listen((_) {
      isPlaying.value = false;
      _localPlaying = false;
      position.value = Duration.zero;
      playingUrl.value = null;
    });
    _player.onPositionChanged.listen((p) => position.value = p);
    _player.onDurationChanged.listen((d) => duration.value = d);
    _player.onPlayerStateChanged.listen((s) {
      final playing = s == PlayerState.playing;
      _localPlaying = playing;
      isPlaying.value = playing;
      if (s != PlayerState.playing) {
        // Don't reset position here — onPlayerComplete handles the
        // natural end-of-clip case.
      }
    });
  }

  /// Play the voice at [storagePath] in the `voice` bucket. Returns
  /// true on success, false on failure (e.g. permissions).
  Future<bool> play(String storagePath) async {
    try {
      // Always stop any in-flight clip before starting a new one so
      // the user gets instant feedback on tap.
      await _player.stop();
      _localPlaying = false;
      isPlaying.value = false;
      final url = await SupabaseService.client.storage
          .from('voice')
          .createSignedUrl(storagePath, 60 * 60); // 1h validity
      if (url.isEmpty) {
        debugPrint('VoicePlayerService: empty signed URL for $storagePath');
        return false;
      }
      _currentUrl = url;
      playingUrl.value = storagePath;
      position.value = Duration.zero;
      // Optimistically flip the playing flag BEFORE awaiting
      // `_player.play()` so a tap immediately after this returns
      // (which is the typical "tap-pause" cadence) sees a fresh
      // value rather than the listener-lagged ValueNotifier.
      _localPlaying = true;
      isPlaying.value = true;
      await _player.play(UrlSource(url));
      return true;
    } catch (e) {
      debugPrint('VoicePlayerService.play failed: $e');
      _localPlaying = false;
      isPlaying.value = false;
      return false;
    }
  }

  /// Pause the currently-playing voice. Safe to call when idle.
  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (_) {}
    // Update the local mirror synchronously so the next tap reads
    // the correct state instead of waiting for the
    // onPlayerStateChanged listener (which on some audioplayers v6
    // Android implementations can take 300+ ms to fire on pause).
    _localPlaying = false;
    isPlaying.value = false;
  }

  /// Resume after a [pause].
  Future<void> resume() async {
    try {
      await _player.resume();
    } catch (_) {}
    _localPlaying = true;
    isPlaying.value = true;
  }

  /// Toggle play / pause for the currently loaded voice.
  Future<void> toggle() async {
    // Use `_localPlaying` (synchronous mirror) instead of
    // `isPlaying.value` so we never double-pause or double-resume
    // because of listener lag.
    if (_localPlaying) {
      await pause();
    } else {
      await resume();
    }
  }

  /// Stop and reset. Safe to call when idle.
  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
    playingUrl.value = null;
    position.value = Duration.zero;
    isPlaying.value = false;
    _localPlaying = false;
    _currentUrl = null;
  }

  /// Seek to [to] inside the current voice. No-op when not loaded.
  Future<void> seek(Duration to) async {
    try {
      await _player.seek(to);
    } catch (_) {}
  }

  /// Currently loading voice's storage path, or null if idle.
  String? get currentStoragePath => _currentUrl == null
      ? null
      : playingUrl.value;

  /// Release native resources.
  Future<void> dispose() async {
    await _player.dispose();
    playingUrl.dispose();
    position.dispose();
    duration.dispose();
    isPlaying.dispose();
  }
}
