/// Voice message bubble — chat-bubble-style row with play button,
/// progress bar, and duration counter.
///
/// Used in both the patient's VoiceInboxScreen and the caretaker's
/// CaretakerVoiceInboxScreen. Drives [VoicePlayerService] for
/// playback, so only one voice plays at a time across the app.
library;

import 'package:flutter/material.dart';

import '../models/voice_message.dart';
import '../services/voice_player_service.dart';
import '../theme/app_theme.dart';

class VoiceMessageBubble extends StatelessWidget {
  final VoiceMessage message;
  final bool isMine;

  /// Optional caption override shown beneath the waveform.
  final String? captionOverride;

  const VoiceMessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.captionOverride,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isMine ? AppColors.cyan : AppColors.violet;
    final bubbleColor = isMine
        ? AppColors.cyan.withValues(alpha: 0.10)
        : AppColors.surfaceHigh;
    final caption = captionOverride ?? message.caption;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMine ? 16 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 16),
            ),
            border: Border.all(color: accent.withValues(alpha: 0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _Header(
                senderLabel: message.senderLabel,
                accent: accent,
                isReply: message.isReply,
              ),
              const SizedBox(height: 8),
              _Player(
                storagePath: message.storagePath,
                durationMs: message.durationMs,
                accent: accent,
              ),
              if (caption != null && caption.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  caption,
                  style: const TextStyle(
                    fontSize: 14.5,
                    color: AppColors.text,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String senderLabel;
  final Color accent;
  final bool isReply;
  const _Header({
    required this.senderLabel,
    required this.accent,
    required this.isReply,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isReply ? Icons.reply_rounded : Icons.mic_rounded,
            size: 14,
            color: accent,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            senderLabel,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ),
      ],
    );
  }
}

class _Player extends StatelessWidget {
  final String storagePath;
  final int durationMs;
  final Color accent;
  const _Player({
    required this.storagePath,
    required this.durationMs,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: VoicePlayerService.instance.playingUrl,
      builder: (context, currentPath, _) {
        final isThis = currentPath == storagePath;
        return Row(
          children: [
            _PlayButton(
              storagePath: storagePath,
              isThis: isThis,
              accent: accent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: isThis
                  ? ValueListenableBuilder<Duration>(
                      valueListenable:
                          VoicePlayerService.instance.position,
                      builder: (context, pos, _) {
                        final maxMs = durationMs <= 0 ? 1 : durationMs;
                        final value = pos.inMilliseconds / maxMs;
                        return _WaveProgressBar(
                          value: value.clamp(0.0, 1.0),
                          accent: accent,
                        );
                      },
                    )
                  : _WaveProgressBar(value: 0, accent: accent),
            ),
            const SizedBox(width: 8),
            Text(
              _fmtMs(durationMs),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: accent,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PlayButton extends StatelessWidget {
  final String storagePath;
  final bool isThis;
  final Color accent;
  const _PlayButton({
    required this.storagePath,
    required this.isThis,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        if (!isThis) {
          await VoicePlayerService.instance.play(storagePath);
          return;
        }
        await VoicePlayerService.instance.toggle();
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: accent,
          shape: BoxShape.circle,
        ),
        child: ValueListenableBuilder<bool>(
          valueListenable: VoicePlayerService.instance.isPlaying,
          builder: (context, playing, _) {
            final showPause = isThis && playing;
            return Icon(
              showPause ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: AppColors.void1,
              size: 22,
            );
          },
        ),
      ),
    );
  }
}

class _WaveProgressBar extends StatelessWidget {
  final double value;
  final Color accent;
  const _WaveProgressBar({required this.value, required this.accent});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: CustomPaint(
        painter: _WavePainter(progress: value, accent: accent),
        size: const Size(double.infinity, 28),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double progress; // 0..1
  final Color accent;
  _WavePainter({required this.progress, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 26;
    const gap = 3.0;
    final barW = (size.width - gap * (barCount - 1)) / barCount;
    final paint = Paint();
    final mid = size.height / 2;
    final progressX = size.width * progress;
    for (var i = 0; i < barCount; i++) {
      final x = i * (barW + gap);
      // Pseudo-random heights driven by index → quiet/cheerful waveform.
      final phase = (i * 1.37) % (6.28);
      final h = (size.height * (0.25 + 0.6 * (0.5 + 0.5 * _sin(phase + i * 0.4))));
      final left = x;
      final top = mid - h / 2;
      final rect = Rect.fromLTWH(left, top, barW, h);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(2));
      paint.color =
          (x <= progressX ? accent : AppColors.line).withValues(alpha: x <= progressX ? 0.9 : 0.7);
      canvas.drawRRect(rrect, paint);
    }
  }

  static double _sin(double x) {
    // Approximate sine (visual noise only — precision doesn't matter).
    return (x - (x.floor() ~/ 1) ).abs();
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.progress != progress || old.accent != accent;
}

String _fmtMs(int ms) {
  final s = (ms / 1000).round();
  final m = s ~/ 60;
  final r = s % 60;
  return '$m:${r.toString().padLeft(2, '0')}';
}
