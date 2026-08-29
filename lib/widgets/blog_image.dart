/// Renders either the network image at `url` or a gradient placeholder
/// when the URL is empty / fails to load. Used by both the Home rail
/// and the Details hero so missing images never break the layout.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class BlogImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final List<Color>? gradient;

  const BlogImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius;
    Widget child;
    if (url.isEmpty) {
      child = _placeholder();
    } else {
      child = Image.network(
        url,
        fit: fit,
        // Smooth fade-in once the image has decoded.
        frameBuilder: (ctx, child, frame, sync) {
          if (frame == null) {
            return AnimatedOpacity(
              opacity: 0,
              duration: const Duration(milliseconds: 240),
              child: _placeholder(),
            );
          }
          return AnimatedOpacity(
            opacity: 1,
            duration: const Duration(milliseconds: 280),
            child: child,
          );
        },
        // Network failures fall back to the gradient placeholder so the
        // UI never looks broken.
        errorBuilder: (ctx, err, st) => _placeholder(),
        loadingBuilder: (ctx, child, progress) {
          if (progress == null) return child;
          return _placeholder();
        },
      );
    }
    if (radius != null) {
      child = ClipRRect(borderRadius: radius, child: child);
    }
    return child;
  }

  Widget _placeholder() {
    final grad = gradient ??
        const [AppColors.svcHero, AppColors.svcHeroDeep];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: grad,
        ),
      ),
      child: const Center(
        child: Icon(Icons.image_outlined,
            color: AppColors.newsOnPill, size: 36),
      ),
    );
  }
}

/// 16:9 rounded hero image — used by both the featured card on the
/// Home rail and the top of the Details page. Pulls shadow + radius
/// from the design tokens so both call sites stay visually identical.
class HeroImage extends StatelessWidget {
  final String url;
  final List<Color> gradient;
  final double radius;
  const HeroImage({
    super.key,
    required this.url,
    required this.gradient,
    this.radius = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: AppGlass.shadow(opacity: 0.10, blur: 22, y: 10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: AspectRatio(
          aspectRatio: 16 / 10,
          child: BlogImage(url: url, gradient: gradient),
        ),
      ),
    );
  }
}
