import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import 'bdapps_login_screen.dart';
import 'subscription_check_screen.dart';

/// First screen the user sees when they open the app.
///
/// Asks them to pick which flow they need — Patient or Caretaker —
/// and routes them into the role-specific BDApps OTP login. The role
/// choice is also persisted on the user's profile when they sign up,
/// so the next time they log in they can skip this screen.
class RoleLandingScreen extends StatefulWidget {
  const RoleLandingScreen({super.key});

  @override
  State<RoleLandingScreen> createState() => _RoleLandingScreenState();
}

class _RoleLandingScreenState extends State<RoleLandingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entry;
  late final Animation<double> _fadeIn;
  late final Animation<double> _slide;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _fadeIn = CurvedAnimation(parent: _entry, curve: Curves.easeOut);
    _slide = Tween<double>(begin: 24, end: 0).animate(
      CurvedAnimation(parent: _entry, curve: Curves.easeOutCubic),
    );
    _entry.forward();
  }

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  void _pickRole(String role) {
    HapticFeedback.selectionClick();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BdappsLoginScreen(role: role),
      ),
    );
  }

  void _openSubscriptionCheck() {
    HapticFeedback.selectionClick();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SubscriptionCheckScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.void2,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _entry,
          builder: (context, child) {
            return Opacity(
              opacity: _fadeIn.value,
              child: Transform.translate(
                offset: Offset(0, _slide.value),
                child: child,
              ),
            );
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Brand(),
                const SizedBox(height: 32),
                const Text(
                  'কে হিসেবে প্রবেশ করবেন?',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                    letterSpacing: -0.6,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'আপনার ডায়েট পরিচালনা করুন, অথবা পরিবারের কাউকে দেখাশোনা করুন।',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.smoke,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),
                _RoleCard(
                  icon: Icons.person_rounded,
                  title: 'রোগী (Patient)',
                  subtitle:
                      'নিজের ডায়াবেটিস ও খাবারের পরিকল্পনা পরিচালনা করতে চাই',
                  accent: AppColors.cyan,
                  onTap: () => _pickRole('patient'),
                ),
                const SizedBox(height: 14),
                _RoleCard(
                  icon: Icons.favorite_rounded,
                  title: 'কেয়ারটেকার (Caretaker)',
                  subtitle:
                      'পরিবারের কারো ডায়াবেটিস ও খাবারের পরিকল্পনা দেখাশোনা করতে চাই',
                  accent: AppColors.violet,
                  onTap: () => _pickRole('caretaker'),
                ),
                const SizedBox(height: 14),
                _RoleCard(
                  icon: Icons.verified_user_outlined,
                  title: 'সাবস্ক্রিপশন চেক করুন',
                  subtitle:
                      'আপনার BDApps সাবস্ক্রিপশন সক্রিয় আছে কি না নম্বর দিয়ে যাচাই করুন',
                  accent: AppColors.amber,
                  onTap: _openSubscriptionCheck,
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.health_and_safety_outlined,
                        size: 18,
                        color: AppColors.cyan,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'BDApps দিয়ে নিরাপদে OTP ভেরিফাই করে প্রবেশ করুন। প্রতিদিন মাত্র ২.৭৮ টাকা।',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.smoke,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: AppGradients.aurora,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.cyan.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          child: Image.asset(
            'assets/logo.png',
            width: 38,
            height: 38,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.health_and_safety_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'আপন সুস্থতা',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
            Text(
              'Apon Susthota',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.smoke,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: accent, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.smoke,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded,
                  color: accent, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
