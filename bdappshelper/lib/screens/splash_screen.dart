import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../widgets/glass_card.dart';
import '../services/auth_service.dart';
import 'home_shell.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    Future.delayed(const Duration(milliseconds: 3200), () {
      if (!mounted) return;
      final authed = AuthService.instance.isAuthenticated;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              authed ? const HomeShell() : const OnboardingScreen(),
        ),
      );
    });
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
              AnimatedBuilder(
                animation: _shimmer,
                builder: (_, __) {
                  return _GlassLogoBadge(progress: _shimmer.value);
                },
              ),
              const SizedBox(height: AppSpacing.xxl),
              const Text(
                'Amar Diet',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'আমার ডায়েট • Eat well, live better',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
    );
  }
}

class _GlassLogoBadge extends StatelessWidget {
  const _GlassLogoBadge({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer glass disc
          GlassCard(
            width: 140,
            height: 140,
            padding: EdgeInsets.zero,
            radius: 36,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Image.asset(
                'assets/logo.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.eco_rounded,
                  size: 70,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          // Shimmer sweep
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(36),
              child: ShaderMask(
                shaderCallback: (rect) {
                  final dx = -0.4 + progress * 1.8;
                  return LinearGradient(
                    begin: Alignment(dx - 0.4, 0),
                    end: Alignment(dx + 0.4, 0),
                    colors: const [
                      Colors.transparent,
                      Colors.white,
                      Colors.transparent,
                    ],
                    stops: const [0.35, 0.5, 0.65],
                  ).createShader(rect);
                },
                blendMode: BlendMode.srcATop,
                child: Container(color: Colors.white.withValues(alpha: 0.25)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
