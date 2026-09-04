import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/onboarding_gate.dart';
import '../../theme/app_theme.dart';

/// First-run marketing carousel shown before the hero video and the
/// role-landing page. Three PageView slides using the bundled splash
/// images, with a dot indicator, Skip button and Next / Get Started
/// CTA.
///
/// Marked as seen via [OnboardingGate.markIntroSeen] the first time
/// the user reaches the last slide — regardless of whether they tap
/// Skip or Next, so the next launch jumps straight to the video.
class OnboardingIntroScreen extends StatefulWidget {
  const OnboardingIntroScreen({super.key});

  @override
  State<OnboardingIntroScreen> createState() => _OnboardingIntroScreenState();
}

class _OnboardingIntroScreenState extends State<OnboardingIntroScreen> {
  static const List<_IntroSlide> _slides = [
    _IntroSlide(
      image: 'assets/splash/1.png',
      title: 'আপনার ডায়াবেটিস, সহজভাবে',
      subtitle:
          'খাবার, ওষুধ, ব্যায়াম ও রক্তে শর্করা — সব এক জায়গায় ট্র্যাক করুন।',
    ),
    _IntroSlide(
      image: 'assets/splash/2.png',
      title: 'বাংলাদেশি খাবারের বুদ্ধিদ্বারা গাইড',
      subtitle:
          'ভাত, মাছ, ডাল, সবজি — প্রতিটি খাবারের জন্য ব্যক্তিগত পরামর্শ পান।',
    ),
    _IntroSlide(
      image: 'assets/splash/3.png',
      title: 'পরিবারের যত্ন একসাথে',
      subtitle:
          'কেয়ারটেকার হিসেবে পরিবারের সদস্যকে দেখাশোনা করুন — নিরাপদে, সহজভাবে।',
    ),
  ];

  late final PageController _pageController;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _advance({bool forceFinish = false}) async {
    if (forceFinish || _index >= _slides.length - 1) {
      await OnboardingGate.markIntroSeen();
      if (!mounted) return;
      // Hand off to the gate. Do NOT push / replace routes here —
      // we are the MaterialApp.home, and replacing the home route
      // orphans the original home reference, which then leaks back
      // in when the auth gate tries to popUntil. Instead we flip the
      // shared flow controller and let the root gate rebuild home.
      OnboardingGate.flow.markIntroDone();
      return;
    }
    await _pageController.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _index == _slides.length - 1;
    return Scaffold(
      backgroundColor: AppColors.void2,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  const _BrandChip(),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _advance(forceFinish: true),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.smoke,
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: const Text('এড়িয়ে যান'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _SlideBody(slide: _slides[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_slides.length, (i) {
                  final active = i == _index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: active ? 28 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.cyan
                          : AppColors.lineStrong,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              child: SizedBox(
                height: 56,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _advance,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: AppGradients.aurora,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isLast ? 'শুরু করুন' : 'পরবর্তী',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: AppColors.onAccent,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              size: 20,
                              color: AppColors.onAccent,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroSlide {
  final String image;
  final String title;
  final String subtitle;
  const _IntroSlide({
    required this.image,
    required this.title,
    required this.subtitle,
  });
}

class _BrandChip extends StatelessWidget {
  const _BrandChip();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: AppGradients.aurora,
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          child: Image.asset(
            'assets/logo.png',
            width: 28,
            height: 28,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.health_and_safety_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'আপন সুস্থতা',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
                height: 1.0,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Apon Susthota',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.smoke,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SlideBody extends StatelessWidget {
  final _IntroSlide slide;
  const _SlideBody({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppColors.line),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.cyan.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              // The hero slot is square-ish but our three bundled
              // splash images are mixed aspect ratios (one ~2:1
              // landscape, one square, one ~16:9). `BoxFit.cover`
              // would crop the landscape ones. Instead we measure
              // the image's intrinsic dimensions and size the slot
              // to match the largest fitting rectangle — preserving
              // the original artwork while keeping the card slot
              // visually balanced.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return FutureBuilder<Size>(
                    future: _measureAsset(slide.image),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const ColoredBox(
                          color: AppColors.surfaceHigh,
                          child: Center(
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            ),
                          ),
                        );
                      }
                      final img = snap.data!;
                      final maxW = constraints.maxWidth;
                      final maxH = constraints.maxHeight;
                      final slotAspect = maxW / maxH;
                      final imgAspect = img.width / img.height;
                      double w;
                      double h;
                      if (imgAspect > slotAspect) {
                        // Image is wider than slot — fit by width,
                        // letterbox top/bottom.
                        w = maxW;
                        h = maxW / imgAspect;
                      } else {
                        // Image is taller (or equal) — fit by height,
                        // letterbox sides.
                        h = maxH;
                        w = maxH * imgAspect;
                      }
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Image.asset(
                            slide.image,
                            width: w,
                            height: h,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const ColoredBox(
                              color: AppColors.surfaceHigh,
                              child: Center(
                                child: Icon(
                                  Icons.image_outlined,
                                  size: 56,
                                  color: AppColors.smoke,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
              height: 1.2,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            slide.subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.smoke,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

/// Resolves the intrinsic pixel size of an asset image without
/// decoding the full bitmap. We use this to fit each slide's hero
/// image into the square-ish card slot without cropping.
///
/// Returns a sensible 1:1 fallback if the asset can't be resolved so
/// the FutureBuilder never stays in the loading state forever.
Future<Size> _measureAsset(String asset) {
  final completer = Completer<Size>();
  final stream = AssetImage(asset).resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!completer.isCompleted) {
        completer.complete(
          Size(
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          ),
        );
      }
      stream.removeListener(listener);
    },
    onError: (error, stack) {
      if (!completer.isCompleted) {
        completer.complete(const Size(1, 1));
      }
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return completer.future;
}
