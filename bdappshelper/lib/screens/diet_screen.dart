import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../widgets/gradient_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/glass_card.dart' show GlassChip;
import '../widgets/app_button.dart';
import 'home_shell.dart';

class DietScreen extends StatefulWidget {
  const DietScreen({super.key});

  @override
  State<DietScreen> createState() => _DietScreenState();
}

enum _DietType { veg, nonVeg, both }

class _DietScreenState extends State<DietScreen> {
  _DietType _type = _DietType.both;
  bool _halal = true;
  final _allergies = const [
    'Dairy',
    'Gluten',
    'Peanuts',
    'Soy',
    'Eggs',
    'Shellfish',
    'Mustard',
  ];
  final Set<String> _picked = {};

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
                      'Diet preferences',
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
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: AppSpacing.md),
                      _SectionTitle('Diet type'),
                      const SizedBox(height: AppSpacing.md),
                      GlassCard(
                        padding: const EdgeInsets.all(6),
                        child: Row(
                          children: [
                            _DietToggle(
                              label: 'Veg',
                              icon: Icons.eco_rounded,
                              selected: _type == _DietType.veg,
                              onTap: () =>
                                  setState(() => _type = _DietType.veg),
                            ),
                            _DietToggle(
                              label: 'Non-Veg',
                              icon: Icons.set_meal_rounded,
                              selected: _type == _DietType.nonVeg,
                              onTap: () =>
                                  setState(() => _type = _DietType.nonVeg),
                            ),
                            _DietToggle(
                              label: 'Both',
                              icon: Icons.restaurant_rounded,
                              selected: _type == _DietType.both,
                              onTap: () =>
                                  setState(() => _type = _DietType.both),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _SectionTitle('Allergies'),
                      const SizedBox(height: AppSpacing.md),
                      GlassCard(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 10,
                          children: [
                            for (final a in _allergies)
                              GlassChip(
                                label: a,
                                selected: _picked.contains(a),
                                onTap: () => setState(() {
                                  if (_picked.contains(a)) {
                                    _picked.remove(a);
                                  } else {
                                    _picked.add(a);
                                  }
                                }),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _SectionTitle('Religious preferences'),
                      const SizedBox(height: AppSpacing.md),
                      GlassCard(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(AppRadius.md),
                              ),
                              child: const Icon(
                                Icons.mosque_rounded,
                                color: AppColors.primary,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.lg),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Halal only',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Show only halal-certified options',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch.adaptive(
                              value: _halal,
                              onChanged: (v) => setState(() => _halal = v),
                              activeColor: AppColors.primary,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      AppButton(
                        label: 'Start tracking',
                        icon: Icons.check_rounded,
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const HomeShell(),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class _DietToggle extends StatelessWidget {
  const _DietToggle({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              gradient: selected
                  ? const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryDark],
                    )
                  : null,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? Colors.white : AppColors.textPrimary,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.textPrimary,
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
