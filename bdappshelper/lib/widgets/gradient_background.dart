import 'package:flutter/material.dart';
import '../core/app_theme.dart';

/// The soft mint→white gradient that the entire app is layered on.
/// Includes two faint colored blobs for a glass-shimmer backdrop.
class GradientBackground extends StatelessWidget {
  const GradientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const _BaseGradient(),
        Positioned(
          top: -80,
          right: -60,
          child: _Blob(
            size: 260,
            color: AppColors.primaryLight.withValues(alpha: 0.35),
          ),
        ),
        Positioned(
          bottom: 120,
          left: -80,
          child: _Blob(
            size: 220,
            color: AppColors.accent.withValues(alpha: 0.30),
          ),
        ),
        Positioned(
          top: 220,
          left: 60,
          child: _Blob(
            size: 140,
            color: AppColors.secondary.withValues(alpha: 0.10),
          ),
        ),
        child,
      ],
    );
  }
}

class _BaseGradient extends StatelessWidget {
  const _BaseGradient();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.gradientTop,
            AppColors.gradientMid,
            AppColors.gradientBottom,
          ],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}
