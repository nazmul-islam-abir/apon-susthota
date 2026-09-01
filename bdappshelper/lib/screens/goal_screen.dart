import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../widgets/gradient_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/app_button.dart';
import 'diet_screen.dart';

class GoalScreen extends StatefulWidget {
  const GoalScreen({super.key});

  @override
  State<GoalScreen> createState() => _GoalScreenState();
}

class _GoalScreenState extends State<GoalScreen> {
  final _goals = const [
    _Goal(
      icon: Icons.south_rounded,
      tint: AppColors.secondary,
      title: 'Lose Weight',
      subtitle: 'Reduce body fat with a gentle calorie deficit.',
    ),
    _Goal(
      icon: Icons.north_rounded,
      tint: AppColors.primary,
      title: 'Gain Weight',
      subtitle: 'Build healthy mass with a calorie surplus.',
    ),
    _Goal(
      icon: Icons.balance_rounded,
      tint: AppColors.primaryDark,
      title: 'Maintain',
      subtitle: 'Stay at your current weight while eating well.',
    ),
    _Goal(
      icon: Icons.medical_services_rounded,
      tint: AppColors.accent,
      title: 'Manage Condition',
      subtitle: 'Diabetes, PCOS, blood pressure — tailored plans.',
    ),
  ];

  String? _selected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      color: AppColors.textPrimary,
                    ),
                    const Spacer(),
                    const Text(
                      'Health goal',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 40),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'What is your goal?',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Pick one — we will personalise your plan around it.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  child: Column(
                    children: [
                      for (final g in _goals) ...[
                        _GoalCard(
                          goal: g,
                          selected: _selected == g.title,
                          onTap: () => setState(() => _selected = g.title),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      AppButton(
                        label: 'Continue',
                        icon: Icons.arrow_forward_rounded,
                        onPressed: _selected == null
                            ? null
                            : () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const DietScreen(),
                                  ),
                                );
                              },
                      ),
                      const SizedBox(height: AppSpacing.xl),
                    ],
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

class _Goal {
  const _Goal({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.goal,
    required this.selected,
    required this.onTap,
  });

  final _Goal goal;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      borderColor: selected ? AppColors.primary : Colors.white,
      borderOpacity: selected ? 0.9 : 0.6,
      gradient: selected
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primary.withValues(alpha: 0.85),
                AppColors.primaryDark.withValues(alpha: 0.85),
              ],
            )
          : null,
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white.withValues(alpha: 0.25)
                  : goal.tint.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(
              goal.icon,
              color: selected ? Colors.white : goal.tint,
              size: 28,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  goal.title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  goal.subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: selected
                        ? Colors.white.withValues(alpha: 0.85)
                        : AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(
            selected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: selected ? Colors.white : AppColors.primary,
            size: 22,
          ),
        ],
      ),
    );
  }
}
