/// Circular play / pause button used to launch a voice clip
/// in-list — without opening a thread or detail screen.
///
/// Subscribes to [VoicePlayerService] so the icon flips to a pause
/// glyph the moment this clip starts playing and reverts when it
/// stops. Used by:
///
///   * the patient's inbox row (replaces a static mic icon),
///   * the caretaker's schedule card (lets the caretaker preview
///     their own recording before the patient hears it).
///
/// The button drives [VoicePlayerService] directly, so only one
/// clip plays at a time across the whole app — tapping another
/// [VoicePlayButton] (or any [VoiceMessageBubble]) automatically
/// stops this one.
library;

import 'package:flutter/material.dart';

import '../services/voice_player_service.dart';
import '../theme/app_theme.dart';

/// Compact circular play/pause button.
///
///   * [storagePath] — Supabase Storage path inside the `voice`
///                     bucket. The button calls
///                     `VoicePlayerService.instance.play(storagePath)`
///                     on tap; the service handles signed-URL +
///                     single-flight playback.
///   * [accent]      — fill color when active. Defaults to the app's
///                     cyan brand color.
///   * [size]        — diameter in logical pixels. Defaults to 44.
///   * [onTap]       — optional callback fired when the user taps.
///                     Use this if the host screen needs to react
///                     (e.g. mark-as-played, navigate).
class VoicePlayButton extends StatelessWidget {
  final String storagePath;
  final Color accent;
  final double size;
  final VoidCallback? onTap;
  const VoicePlayButton({
    super.key,
    required this.storagePath,
    required this.onTap,
    this.accent = AppColors.cyan,
    this.size = 44,
  });

  Future<void> _handleTap() async {
    final service = VoicePlayerService.instance;
    final current = service.playingUrl.value;
    if (current == storagePath) {
      await service.toggle();
    } else {
      await service.play(storagePath);
    }
    onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: VoicePlayerService.instance.playingUrl,
      builder: (context, currentPath, _) {
        final isThis = currentPath == storagePath;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: isThis ? accent : accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: ValueListenableBuilder<bool>(
              valueListenable: VoicePlayerService.instance.isPlaying,
              builder: (context, playing, _) {
                final showPause = isThis && playing;
                return Icon(
                  showPause
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: isThis ? AppColors.void1 : accent,
                  size: size * 0.5,
                );
              },
            ),
          ),
        );
      },
    );
  }
}
