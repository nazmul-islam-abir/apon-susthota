import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/meal_item.dart';
import '../models/user_profile.dart';
import '../services/diet_recommender.dart';
import '../theme/app_theme.dart';
import 'mono_widgets.dart';

/// Card that lists foods the user should specifically AVOID based on
/// their clinical classification. Each row shows the Bengali food name
/// plus a Bengali reason with citation (KDIGO, ADA, AHA, DASH, ICMR).
///
/// The card is fed a list of candidate foods (e.g. all `foods` the user
/// has recently seen, or the union of today's plan + alternatives) and
/// filters them through [DietRecommender.restrictedFoods].
class RestrictedFoodsCard extends StatelessWidget {
  final UserProfile profile;
  final List<MealItem> candidates;

  /// Optional title override. Defaults to a Bengali heading.
  final String? titleOverride;

  /// Show up to this many foods (others are hidden behind a "+N more"
  /// chip). Keeps the profile screen compact.
  final int maxItems;

  const RestrictedFoodsCard({
    super.key,
    required this.profile,
    required this.candidates,
    this.titleOverride,
    this.maxItems = 6,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cls = DietRecommender.classify(profile);
    final restricted = DietRecommender.restrictedFoods(candidates, cls);

    if (restricted.isEmpty) {
      return _EmptyCard(title: titleOverride ?? l.restrictedFoodsTitle);
    }

    final shown = restricted.take(maxItems).toList();
    final hidden = restricted.length - shown.length;

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.do_not_disturb_alt_outlined,
                  size: 18, color: AppColors.danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titleOverride ?? l.restrictedFoodsTitle,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${restricted.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.danger,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l.restrictedFoodsBlurb,
            style: TextStyle(
                fontSize: 12, color: AppColors.textMuted.withValues(alpha: 0.9)),
          ),
          const SizedBox(height: 10),
          ...shown.map((r) => _RestrictedRow(item: r)),
          if (hidden > 0) ...[
            const SizedBox(height: 4),
            Text(
              l.restrictedFoodsMore(hidden),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textDim,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RestrictedRow extends StatelessWidget {
  final RestrictedFood item;
  const _RestrictedRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.restaurant_outlined,
                size: 18, color: AppColors.danger),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.food.nameBn,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.reason,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String title;
  const _EmptyCard({required this.title});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 18, color: AppColors.mint),
              const SizedBox(width: 8),
              Text(
                title.isNotEmpty ? title : l.restrictedFoodsTitle,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l.restrictedFoodsEmpty,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact classification summary used in the profile dashboard.
/// Shows glucose / BMI / BP tiers plus daily macro targets in a
/// dense grid layout suitable for a 360dp-wide phone.
class ClassificationSummaryCard extends StatelessWidget {
  final DietClassification cls;
  const ClassificationSummaryCard({super.key, required this.cls});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final glucoseLabel = _glucoseLabel(cls.glucoseTier, l);
    final bmiLabel = _bmiLabel(cls.bmiTier, l);
    final bpLabel = _bpLabel(cls.bpTier, l);

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_outlined,
                  size: 18, color: AppColors.cyan),
              const SizedBox(width: 8),
              Text(
                l.classificationTitle,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _MetricTile(label: l.classificationGlucose, value: glucoseLabel)),
              const SizedBox(width: 8),
              Expanded(child: _MetricTile(label: l.classificationBmi, value: bmiLabel)),
              const SizedBox(width: 8),
              Expanded(child: _MetricTile(label: l.classificationBp, value: bpLabel)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.classificationDailyTargets,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    _Pill(
                        label: l.classificationKcal,
                        value: l.classificationValueKcal(cls.dailyKcalTarget.toInt())),
                    _Pill(
                        label: l.classificationCarb,
                        value: l.classificationValueG(cls.dailyCarbTargetG.toInt())),
                    _Pill(
                        label: l.classificationProtein,
                        value: l.classificationValueG(cls.dailyProteinTargetG.toInt())),
                    _Pill(
                        label: l.classificationFat,
                        value: l.classificationValueG(cls.dailyFatTargetG.toInt())),
                    _Pill(
                        label: l.classificationSodium,
                        value: l.classificationValueMg(cls.dailySodiumCapMg.toInt())),
                    _Pill(
                        label: l.classificationCarbPerMeal,
                        value: l.classificationValueG(cls.maxCarbPerMeal.toInt())),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _glucoseLabel(String t, AppLocalizations l) {
    switch (t) {
      case 'good':
        return l.tierGood;
      case 'moderate':
        return l.tierModerate;
      case 'poor':
        return l.tierPoor;
      default:
        return l.tierUnknown;
    }
  }

  String _bmiLabel(String t, AppLocalizations l) {
    switch (t) {
      case 'underweight':
        return l.tierUnderweight;
      case 'normal':
        return l.tierNormal;
      case 'overweight':
        return l.tierOverweight;
      case 'obese':
        return l.tierObese;
      default:
        return l.tierUnknown;
    }
  }

  String _bpLabel(String t, AppLocalizations l) {
    switch (t) {
      case 'normal':
        return l.tierNormal;
      case 'elevated':
        return l.tierElevated;
      case 'stage1':
        return l.tierStage1;
      case 'stage2':
        return l.tierStage2;
      default:
        return l.tierUnknown;
    }
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  const _MetricTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              )),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.text,
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final String value;
  const _Pill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line, width: 1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w500,
              )),
          const SizedBox(width: 4),
          Text(value,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.text,
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
    );
  }
}

/// Card that lists Bengali recommendations + warnings tailored to the
/// user's classification. Used on profile screen just below the
/// classification summary.
class RecommendationsCard extends StatelessWidget {
  final DietClassification cls;
  const RecommendationsCard({super.key, required this.cls});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final recs = cls.recommendationsBn;
    final warns = cls.warnings;
    if (recs.isEmpty && warns.isEmpty) return const SizedBox.shrink();

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tips_and_updates_outlined,
                  size: 18, color: AppColors.amber),
              const SizedBox(width: 8),
              Text(
                l.recommendationsTitle,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          if (warns.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...warns.map((w) => _WarningRow(text: w)),
          ],
          if (recs.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...recs.map((r) => _RecommendationRow(text: r)),
          ],
        ],
      ),
    );
  }
}

class _WarningRow extends StatelessWidget {
  final String text;
  const _WarningRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline,
              size: 16, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.text,
                    height: 1.4,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _RecommendationRow extends StatelessWidget {
  final String text;
  const _RecommendationRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline,
              size: 16, color: AppColors.mint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.text,
                    height: 1.4)),
          ),
        ],
      ),
    );
  }
}