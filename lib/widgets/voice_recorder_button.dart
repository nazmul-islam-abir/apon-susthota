/// Voice recorder button — Messenger/WhatsApp shape.
///
/// Tap once to start, tap again to stop. Wraps
/// [VoiceRecorderService] so the parent screen doesn't have to
/// deal with the recorder lifecycle directly.
///
/// The button shows three visual states:
///   * idle      — outlined mic
///   * recording — solid red mic with a soft pulse ring + live timer
///   * denied    — muted mic + "অনুমতি দিন" caption
library;

import 'package:flutter/material.dart';

import '../services/voice_recorder_service.dart';
import '../theme/app_theme.dart';

/// Callback the parent can react to:
///   * onStarted      — recording began
///   * onStopped(path, durationMs)  — recording ended, file ready
///   * onPermissionDenied — user denied mic; surface a Bangla snackbar
///   * onCleared      — recording discarded
class VoiceRecorderButton extends StatelessWidget {
  final ValueChanged<String> onStopped; // path
  final ValueChanged<int>? onDuration; // durationMs
  final VoidCallback? onPermissionDenied;
  final VoidCallback? onStarted;
  final VoidCallback? onCleared;
  final double size;

  const VoiceRecorderButton({
    super.key,
    required this.onStopped,
    this.onDuration,
    this.onPermissionDenied,
    this.onStarted,
    this.onCleared,
    this.size = 88,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VoiceRecorderState>(
      valueListenable: VoiceRecorderService.instance.state,
      builder: (context, state, _) {
        final isRec = state == VoiceRecorderState.recording;
        final isDenied = state == VoiceRecorderState.denied;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _handleTap(context, state),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: isRec
                      ? AppColors.rose
                      : (isDenied
                          ? AppColors.surfaceHigh
                          : AppColors.cyan.withValues(alpha: 0.1)),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isRec
                        ? AppColors.rose
                        : (isDenied
                            ? AppColors.lineStrong
                            : AppColors.cyan),
                    width: 2,
                  ),
                  boxShadow: isRec
                      ? [
                          BoxShadow(
                            color: AppColors.rose.withValues(alpha: 0.35),
                            blurRadius: 24,
                            spreadRadius: 4,
                          )
                        ]
                      : null,
                ),
                child: Center(
                  child: Icon(
                    isRec
                        ? Icons.stop_rounded
                        : (isDenied
                            ? Icons.mic_off_rounded
                            : Icons.mic_rounded),
                    color: isRec
                        ? AppColors.void1
                        : (isDenied
                            ? AppColors.textMuted
                            : AppColors.cyan),
                    size: size * 0.45,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (isRec) _LiveCounter(size: size),
              if (!isRec)
                Text(
                  isDenied ? 'অনুমতি দিন' : 'রেকর্ড শুরু',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDenied
                        ? AppColors.textMuted
                        : AppColors.cyan,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleTap(
      BuildContext context, VoiceRecorderState state) async {
    final svc = VoiceRecorderService.instance;
    if (state == VoiceRecorderState.recording) {
      final path = await svc.stop();
      if (path != null) {
        onStopped(path);
        onDuration?.call(svc.currentDurationMs);
      }
      return;
    }
    final ok = await svc.start();
    if (ok) {
      onStarted?.call();
    } else if (svc.state.value == VoiceRecorderState.denied) {
      onPermissionDenied?.call();
    }
  }
}

class _LiveCounter extends StatelessWidget {
  final double size;
  const _LiveCounter({required this.size});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: VoiceRecorderService.instance.elapsed,
      builder: (context, d, _) {
        final total = d.inMilliseconds ~/ 1000;
        final m = (total ~/ 60).toString().padLeft(2, '0');
        final s = (total % 60).toString().padLeft(2, '0');
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.rose,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$m:$s',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.rose,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        );
      },
    );
  }
}
