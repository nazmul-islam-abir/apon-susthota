import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../services/onboarding_gate.dart';
import '../../theme/app_theme.dart';

/// Full-screen hero video shown once after the intro carousel and
/// before the role-landing page.
///
/// Plays `assets/vids/main.mp4` on loop with audio muted. The user can
/// skip at any time via the floating pill in the top-right, and on
/// natural completion (or skip) we mark the video as seen in
/// [OnboardingGate] and route to [RoleLandingScreen].
class OnboardingVideoScreen extends StatefulWidget {
  const OnboardingVideoScreen({super.key});

  @override
  State<OnboardingVideoScreen> createState() => _OnboardingVideoScreenState();
}

class _OnboardingVideoScreenState extends State<OnboardingVideoScreen> {
  VideoPlayerController? _controller;
  bool _initializing = true;
  String? _error;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final c = VideoPlayerController.asset('assets/vids/main.mp4');
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(1);
      await c.play();
      if (!mounted) {
        c.dispose();
        return;
      }
      c.addListener(_onTick);
      setState(() {
        _controller = c;
        _initializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _initializing = false;
      });
    }
  }

  void _onTick() {
    final c = _controller;
    if (c == null || !mounted) return;
    if (c.value.hasError) {
      setState(() => _error = c.value.errorDescription ?? 'ভিডিও লোড ব্যর্থ');
    }
    if (mounted) setState(() {});
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    await OnboardingGate.markVideoSeen();
    if (!mounted) return;
    // Hand off to the gate. See OnboardingIntroScreen for why we
    // never pushReplacement from inside a MaterialApp.home.
    OnboardingGate.flow.markVideoDone();
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_initializing)
            const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor:
                    AlwaysStoppedAnimation<Color>(AppColors.onAccent),
              ),
            )
          else if (_error != null || c == null)
            _ErrorState(message: _error, onSkip: _finish)
          else
            Center(
              child: AspectRatio(
                aspectRatio: c.value.aspectRatio == 0
                    ? 9 / 16
                    : c.value.aspectRatio,
                child: VideoPlayer(c),
              ),
            ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 16,
            child: _SkipPill(
              seconds: c?.value.position.inSeconds ?? 0,
              onTap: _finish,
            ),
          ),
          if (c != null && !c.value.isPlaying && _initializing == false)
            Center(
              child: GestureDetector(
                onTap: c.play,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 44,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SkipPill extends StatelessWidget {
  final int seconds;
  final VoidCallback onTap;
  const _SkipPill({required this.seconds, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(40),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.25),
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'এড়িয়ে যান',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
              ),
              SizedBox(width: 6),
              Icon(
                Icons.skip_next_rounded,
                color: Colors.white,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String? message;
  final VoidCallback onSkip;
  const _ErrorState({required this.message, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.white70,
            size: 56,
          ),
          const SizedBox(height: 16),
          const Text(
            'ভিডিও লোড করা যায়নি',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white60,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 24),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(28),
              onTap: onSkip,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Text(
                  'এগিয়ে যান',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
