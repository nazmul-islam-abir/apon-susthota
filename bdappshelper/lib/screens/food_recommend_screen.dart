import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/food_image.dart';
import '../services/api_service.dart';
import '../services/recommendation_engine.dart';
import 'food_detail_screen.dart';

class FoodRecommendScreen extends StatefulWidget {
  const FoodRecommendScreen({super.key});

  @override
  State<FoodRecommendScreen> createState() => _FoodRecommendScreenState();
}

class _FoodRecommendScreenState extends State<FoodRecommendScreen> {
  final _controller = PageController(viewportFraction: 0.92);
  int _index = 0;
  late Future<List<MealSuggestion>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<MealSuggestion>> _load() async {
    final results = await Future.wait([
      ApiService.getProgress(),
      ApiService.ensureProfile(),
      ApiService.listMeals(date: DateTime.now()),
    ]);
    final ctx = RecommendationContext(
      profile: results[1] as UserProfile,
      progress: results[0] as ProgressReport,
      todayMeals: results[2] as List<MealEntry>,
    );
    return RecommendationEngine.suggest(ctx);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _future = next;
    });
    await next;
  }

  IconData _iconForMeal(String type) {
    switch (type) {
      case 'breakfast':
        return Icons.wb_sunny_rounded;
      case 'lunch':
        return Icons.lunch_dining_rounded;
      case 'dinner':
        return Icons.dinner_dining_rounded;
      default:
        return Icons.icecream_rounded;
    }
  }

  Color _tintForMeal(String type) {
    switch (type) {
      case 'breakfast':
        return AppColors.accent;
      case 'lunch':
        return AppColors.primary;
      case 'dinner':
        return AppColors.primaryDark;
      default:
        return AppColors.secondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.primary,
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
                      'Recommended',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.tune_rounded,
                        color: AppColors.textPrimary),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Personalised for you',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Swipe through breakfast, lunch, snack & dinner ideas.',
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
                child: FutureBuilder<List<MealSuggestion>>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary),
                      );
                    }
                    if (snap.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Text(
                            'Could not build recommendations: ${snap.error}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      );
                    }
                    final items = snap.data ?? const <MealSuggestion>[];
                    if (items.isEmpty) {
                      return const Center(
                        child: Text(
                          'No suggestions available.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      );
                    }
                    return PageView.builder(
                      controller: _controller,
                      onPageChanged: (i) => setState(() => _index = i),
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final s = items[i];
                        final isActive = i == _index;
                        return AnimatedPadding(
                          duration: const Duration(milliseconds: 320),
                          padding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: isActive ? 0 : 24,
                          ),
                          child: _MealCard(
                            suggestion: s,
                            tint: _tintForMeal(s.mealType),
                            icon: _iconForMeal(s.mealType),
                            onTap: (f) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FoodDetailScreen(food: f),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FutureBuilder<List<MealSuggestion>>(
                future: _future,
                builder: (context, snap) {
                  final items = snap.data ?? const <MealSuggestion>[];
                  if (items.isEmpty) return const SizedBox.shrink();
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (int i = 0; i < items.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          height: 6,
                          width: i == _index ? 22 : 6,
                          decoration: BoxDecoration(
                            color: i == _index
                                ? AppColors.primary
                                : AppColors.primary.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({
    required this.suggestion,
    required this.tint,
    required this.icon,
    required this.onTap,
  });

  final MealSuggestion suggestion;
  final Color tint;
  final IconData icon;
  final ValueChanged<FoodItem> onTap;

  @override
  Widget build(BuildContext context) {
    final hero = suggestion.options.isNotEmpty
        ? suggestion.options.first
        : null;

    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Meal label + hero image of top suggestion
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      tint.withValues(alpha: 0.85),
                      tint.withValues(alpha: 0.55),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      suggestion.label,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hero != null
                          ? 'Top pick: ${hero.nameEn}'
                          : 'No suggestions for this slot',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          // Hero image of top suggestion
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: SizedBox(
              height: 160,
              width: double.infinity,
              child: hero == null
                  ? Container(
                      color: AppColors.glassWhite,
                      child: const Center(
                        child: Icon(Icons.no_food_rounded,
                            color: AppColors.textSecondary, size: 48),
                      ),
                    )
                  : FoodImage(
                      food: hero,
                      fit: BoxFit.cover,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // All suggestions list
          const Text(
            'Best matches',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: ListView.separated(
              itemCount: suggestion.options.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (_, i) {
                final f = suggestion.options[i];
                return _OptionRow(food: f, tint: tint, onTap: () => onTap(f));
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.food,
    required this.tint,
    required this.onTap,
  });
  final FoodItem food;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.glassWhite,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: FoodImage(
                    food: food,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      food.nameEn,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '${food.proteinG.round()}g protein • ${food.carbsG.round()}g carbs',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      tint.withValues(alpha: 0.85),
                      tint.withValues(alpha: 0.6),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '${food.kcal.round()} kcal',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.add_rounded,
                  color: AppColors.textPrimary, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
