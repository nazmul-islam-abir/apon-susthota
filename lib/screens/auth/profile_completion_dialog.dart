import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/bdapps/bdapps_session_service.dart';
import '../../theme/app_theme.dart';
import '../onboarding_screen.dart';

/// First-login prompt that asks the user to complete their profile.
///
/// Shown on every fresh BDApps login. Two outcomes:
///   * "এখনই সম্পূর্ণ করুন" → push [OnboardingScreen]. We
///     `markProfileCompleted(true)` when onboarding finishes (the
///     saveProfile flow already writes the new fields).
///   * "পরে করব"        → mark `profileCompleted=true` so the
///     banner doesn't fire on this session; the persistent banner
///     on the home screen still nags until they actually finish.
class ProfileCompletionDialog extends StatelessWidget {
  const ProfileCompletionDialog({super.key, required this.role});

  final String role;

  static Future<bool> show(
    BuildContext context, {
    required String role,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProfileCompletionDialog(role: role),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final isPatient = role != 'caretaker';
    final accent = isPatient ? AppColors.cyan : AppColors.violet;

    final fieldChips = isPatient
        ? const [
            ('বয়স / লিঙ্গ', Icons.cake_outlined),
            ('ওজন / উচ্চতা', Icons.monitor_weight_outlined),
            ('রক্তচাপ (BP)', Icons.favorite_outline),
            ('ইনসুলিন', Icons.medication_outlined),
            ('সুগার (Fasting / Post-meal / HbA1c)', Icons.water_drop_outlined),
            ('কিডনি / হৃদরোগ / অ্যানিমিয়া', Icons.health_and_safety_outlined),
            ('কার্যকলাপ ও খাবার পছন্দ', Icons.directions_walk_outlined),
          ]
        : const [
            ('নাম ও বয়স', Icons.person_outline),
            ('মোবাইল ও ইমেইল', Icons.alternate_email),
            ('ইউজারনেম (অনন্য)', Icons.tag),
            ('আপনার সম্পর্ক (যেমন: ছেলে, স্বামী)', Icons.family_restroom_outlined),
          ];

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  isPatient
                      ? Icons.health_and_safety_rounded
                      : Icons.favorite_rounded,
                  color: accent,
                  size: 32,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'আপনার প্রোফাইল সম্পূর্ণ করুন',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink,
                  height: 1.2,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isPatient
                    ? 'সেরা অভিজ্ঞতার জন্য আপনার স্বাস্থ্য সংক্রান্ত তথ্য যোগ করুন। এই তথ্য শুধু আপনার প্রোফাইলে সংরক্ষিত থাকবে।'
                    : 'রোগীর সঠিক তথ্য দেখাশোনা করতে আপনার প্রোফাইল সম্পূর্ণ করুন। আপনার ইউজারনেম দিয়ে রোগী আপনাকে খুঁজে পাবেন।',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.smoke,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPatient ? 'প্রয়োজনীয় তথ্য:' : 'প্রয়োজনীয় তথ্য:',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: AppColors.smoke,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (label, icon) in fieldChips)
                          _Chip(label: label, icon: icon, accent: accent),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () async {
                      HapticFeedback.selectionClick();
                      // Don't flip profileCompleted=false here — the
                      // "এখনই সম্পূর্ণ করুন" button means the user is
                      // *about* to finish, so keep the current value
                      // (usually already false on first run). Setting
                      // it to false here on a returning user would
                      // cause the dialog to reappear next launch
                      // even after they save their name + username.
                      // The onboarding screen itself calls
                      // markProfileCompleted(true) on save.
                      if (!context.mounted) return;
                      Navigator.of(context).pop(true);
                    },
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            accent,
                            accent.withValues(alpha: 0.85),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'এখনই সম্পূর্ণ করুন',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded,
                              color: Colors.white, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () async {
                  await BdappsSessionService.instance
                      .markProfileCompleted(value: true);
                  if (!context.mounted) return;
                  Navigator.of(context).pop(false);
                },
                child: const Text(
                  'পরে করব',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.smoke,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accent;

  const _Chip({required this.label, required this.icon, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}