import 'package:flutter/material.dart';

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
    final cls = DietRecommender.classify(profile);
    final restricted = DietRecommender.restrictedFoods(candidates, cls);

    if (restricted.isEmpty) {
      return _EmptyCard(title: titleOverride ?? 'এড়িয়ে চলা উচিত এমন খাবার');
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
                  titleOverride ?? 'এড়িয়ে চলা উচিত এমন খাবার',
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
            'আপনার বর্তমান স্বাস্থ্য অবস্থা অনুযায়ী নিচের �াবারগুলো সীমিত বা এড়িয়ে চলা উচিত।',
            style: TextStyle(
                fontSize: 12, color: AppColors.textMuted.withValues(alpha: 0.9)),
          ),
          const SizedBox(height: 10),
          ...shown.map((r) => _RestrictedRow(item: r)),
          if (hidden > 0) ...[
            const SizedBox(height: 4),
            Text(
              'আরও $hiddenটি খাবার রয়েছে — সব দেখতে প্রোফাইল সম্পাদনা করুন।',
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
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.check_circle_outline,
                  size: 18, color: AppColors.mint),
              SizedBox(width: 8),
              Text(
                'এড়িয়ে চলা উচিত এমন �াবার',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'আপনার বর্তমান স্বাস্�্য তথ্য অনুযায়ী নির্দিষ্� কোনো নিষিদ্ধ খাবার নেই। �িকিৎসকের পরামর্শ অনুযায়ী এগিয়ে যান।',
            style: TextStyle(
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
    final glucoseLabel = _glucoseLabel(cls.glucoseTier);
    final bmiLabel = _bmiLabel(cls.bmiTier);
    final bpLabel = _bpLabel(cls.bpTier);

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.insights_outlined,
                  size: 18, color: AppColors.cyan),
              SizedBox(width: 8),
              Text(
                'আপনার বর্তমান শ্রেণিবিন্যাস',
                style: TextStyle(
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
              Expanded(child: _MetricTile(label: 'গ্�ুকোজ', value: glucoseLabel)),
              const SizedBox(width: 8),
              Expanded(child: _MetricTile(label: 'BMI', value: bmiLabel)),
              const SizedBox(width: 8),
              Expanded(child: _MetricTile(label: 'রক্তচাপ', value: bpLabel)),
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
                const Text(
                  'দৈনিক লক্ষ্যমাত্রা',
                  style: TextStyle(
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
                        label: 'ক্যালোরি',
                        value: '${cls.dailyKcalTarget.toInt()} kcal'),
                    _Pill(
                        label: 'কার্ব',
                        value: '${cls.dailyCarbTargetG.toInt()} g'),
                    _Pill(
                        label: 'প্রোটিন',
                        value: '${cls.dailyProteinTargetG.toInt()} g'),
                    _Pill(
                        label: 'চর্বি',
                        value: '${cls.dailyFatTargetG.toInt()} g'),
                    _Pill(
                        label: 'সোডিয়াম সর্বোচ্চ',
                        value: '${cls.dailySodiumCapMg.toInt()} mg'),
                    _Pill(
                        label: 'এক বেলায় কার্ব',
                        value: '${cls.maxCarbPerMeal.toInt()} g'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _glucoseLabel(String t) {
    switch (t) {
      case 'good':
        return 'ভালো';
      case 'moderate':
        return 'মাঝারি';
      case 'poor':
        return 'খারাপ';
      default:
        return 'অজানা';
    }
  }

  String _bmiLabel(String t) {
    switch (t) {
      case 'underweight':
        return 'কম ওজন';
      case 'normal':
        return 'স্বাভাবিক';
      case 'overweight':
        return 'বেশি ওজন';
      case 'obese':
        return 'স্থূল';
      default:
        return 'অজানা';
    }
  }

  String _bpLabel(String t) {
    switch (t) {
      case 'normal':
        return 'স্বাভাবিক';
      case 'elevated':
        return 'উচ্চ';
      case 'stage1':
        return 'পর্যায় ১';
      case 'stage2':
        return 'পর্যায় ২';
      default:
        return 'অজানা';
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
    final recs = cls.recommendationsBn;
    final warns = cls.warnings;
    if (recs.isEmpty && warns.isEmpty) return const SizedBox.shrink();

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.tips_and_updates_outlined,
                  size: 18, color: AppColors.amber),
              SizedBox(width: 8),
              Text(
                'ব্যক্তিগত পরামর্শ',
                style: TextStyle(
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