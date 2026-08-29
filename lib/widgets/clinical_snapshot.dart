/// Clinical snapshot — redesigned (v4) to match the dashboard's forest-green
/// and white aesthetic. Summarises the patient's current health tiers,
/// macro targets, and recommendations.
library;

import 'package:flutter/material.dart';

import '../services/diet_recommender.dart';
import '../theme/app_theme.dart';

/// A reusable clinical-snapshot card.
class ClinicalSnapshotCard extends StatelessWidget {
  final DietClassification? classification;
  final bool dense;

  const ClinicalSnapshotCard({
    super.key,
    required this.classification,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = classification;
    if (c == null) {
      return _empty(context);
    }

    return Container(
      padding: EdgeInsets.all(dense ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.svcCategoryBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.svcHero.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.zero,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.favorite_rounded,
                  color: AppColors.svcHero,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'স্বাস্থ্যের বর্তমান অবস্থা',
                  style: TextStyle(
                    color: AppColors.svcHero,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Health Tiers (Glucose, BP, BMI) ────────────────────────
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.8,
            children: [
              _tierItem(
                icon: Icons.water_drop_outlined,
                label: 'গ্লুকোজ',
                value: _glucoseLabel(c.glucoseTier),
                color: _tierColor(c.glucoseTier),
              ),
              _tierItem(
                icon: Icons.monitor_heart_outlined,
                label: 'রক্তচাপ',
                value: _bpLabel(c.bpTier),
                color: _tierColor(c.bpTier),
              ),
              _tierItem(
                icon: Icons.straighten_outlined,
                label: 'BMI',
                value: _bmiLabel(c.bmiTier),
                color: _bmiColor(c.bmiTier),
              ),
              _tierItem(
                icon: Icons.restaurant_outlined,
                label: 'খাদ্য',
                value: _prefLabel(c.foodPreference),
                color: AppColors.svcHero,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Macro Caps (Carbs, Kcal, Sodium) ──────────────────────
          _capsStrip(c),

          // ── Warnings (If any) ──────────────────────────────────────
          if (!dense && c.warnings.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.rose.withValues(alpha: 0.06),
                borderRadius: BorderRadius.zero,
                border: Border.all(color: AppColors.rose.withValues(alpha: 0.12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.warning_amber_rounded,
                          size: 16, color: AppColors.rose),
                      SizedBox(width: 8),
                      Text(
                        'সতর্কতা',
                        style: TextStyle(
                          color: AppColors.rose,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...c.warnings.take(2).map((w) => _bullet(w, color: AppColors.rose)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tierItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.svcCategoryBg.withValues(alpha: 0.4),
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.svcCategoryBorder),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.newsMuted,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _capsStrip(DietClassification c) {
    return Row(
      children: [
        _macroInfo(
          'কার্ব',
          '${c.dailyCarbTargetG.toStringAsFixed(0)} গ্রাম',
          Icons.grain_outlined,
        ),
        const SizedBox(width: 10),
        _macroInfo(
          'ক্যালোরি',
          '${c.dailyKcalTarget.toStringAsFixed(0)}',
          Icons.local_fire_department_outlined,
        ),
        const SizedBox(width: 10),
        _macroInfo(
          'সোডিয়াম',
          '${c.dailySodiumCapMg.toStringAsFixed(0)} মিগ্রা',
          Icons.spa_outlined,
        ),
      ],
    );
  }

  Widget _macroInfo(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: AppColors.svcHero),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.newsMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: AppColors.svcHero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bullet(String text, {required Color color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 5,
            height: 5,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color.withValues(alpha: 0.9),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.svcCategoryBorder),
      ),
      alignment: Alignment.center,
      child: const CircularProgressIndicator(),
    );
  }
}

// ─────────────────── Label Helpers ───────────────────

String _glucoseLabel(String tier) {
  switch (tier) {
    case 'good':
      return 'ভালো';
    case 'moderate':
      return 'মাঝারি';
    case 'poor':
      return 'খারাপ';
    default:
      return tier;
  }
}

String _bpLabel(String tier) {
  switch (tier) {
    case 'normal':
      return 'স্বাভাবিক';
    case 'elevated':
      return 'উচ্চ';
    case 'stage1':
      return 'স্টেজ ১';
    case 'stage2':
      return 'স্টেজ ২';
    default:
      return tier;
  }
}

String _bmiLabel(String tier) {
  switch (tier) {
    case 'underweight':
      return 'কম ওজন';
    case 'normal':
      return 'স্বাভাবিক';
    case 'overweight':
      return 'বেশি ওজন';
    case 'obese':
      return 'স্থূল';
    default:
      return tier;
  }
}

String _prefLabel(String pref) {
  switch (pref) {
    case 'omnivore':
      return 'সব খাবার';
    case 'vegetarian':
      return 'নিরামিষ';
    case 'fish_only':
      return 'শুধু মাছ';
    case 'no_beef':
      return 'গরুর মাংস ছাড়া';
    default:
      return pref;
  }
}

Color _tierColor(String tier) {
  switch (tier) {
    case 'good':
    case 'normal':
      return const Color(0xFF1F3D2B); // Hero forest green
    case 'moderate':
    case 'elevated':
    case 'stage1':
      return AppColors.amber;
    case 'poor':
    case 'stage2':
      return AppColors.rose;
    default:
      return AppColors.svcHero;
  }
}

Color _bmiColor(String tier) {
  switch (tier) {
    case 'normal':
      return const Color(0xFF1F3D2B);
    case 'underweight':
    case 'overweight':
      return AppColors.amber;
    case 'obese':
      return AppColors.rose;
    default:
      return AppColors.svcHero;
  }
}
