/// Clinical snapshot — redesigned (v4) to match the dashboard's forest-green
/// and white aesthetic. Summarises the patient's current health tiers,
/// macro targets, and recommendations.
library;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
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
    final l = AppLocalizations.of(context);
    if (l == null) return const SizedBox.shrink();

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
              Expanded(
                child: Text(
                  l.clinicalSnapshotTitle,
                  style: const TextStyle(
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
                label: l.classificationGlucose,
                value: _glucoseLabel(c.glucoseTier, l),
                color: _tierColor(c.glucoseTier),
              ),
              _tierItem(
                icon: Icons.monitor_heart_outlined,
                label: l.classificationBp,
                value: _bpLabel(c.bpTier, l),
                color: _tierColor(c.bpTier),
              ),
              _tierItem(
                icon: Icons.straighten_outlined,
                label: l.classificationBmi,
                value: _bmiLabel(c.bmiTier, l),
                color: _bmiColor(c.bmiTier),
              ),
              _tierItem(
                icon: Icons.restaurant_outlined,
                label: l.clinicalSnapshotFood,
                value: _prefLabel(c.foodPreference, l),
                color: AppColors.svcHero,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Macro Caps (Carbs, Kcal, Sodium) ──────────────────────
          _capsStrip(c, l),

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
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          size: 16, color: AppColors.rose),
                      const SizedBox(width: 8),
                      Text(
                        l.clinicalSnapshotWarnings,
                        style: const TextStyle(
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

  Widget _capsStrip(DietClassification c, AppLocalizations l) {
    return Row(
      children: [
        _macroInfo(
          l.macroCarb,
          l.macroCarbValue(c.dailyCarbTargetG.toStringAsFixed(0)),
          Icons.grain_outlined,
        ),
        const SizedBox(width: 10),
        _macroInfo(
          l.macroKcal,
          c.dailyKcalTarget.toStringAsFixed(0),
          Icons.local_fire_department_outlined,
        ),
        const SizedBox(width: 10),
        _macroInfo(
          l.macroSodium,
          l.macroSodiumValue(c.dailySodiumCapMg.toStringAsFixed(0)),
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

String _glucoseLabel(String tier, AppLocalizations l) {
  switch (tier) {
    case 'good':
      return l.tierGood;
    case 'moderate':
      return l.tierModerate;
    case 'poor':
      return l.tierPoor;
    default:
      return tier;
  }
}

String _bpLabel(String tier, AppLocalizations l) {
  switch (tier) {
    case 'normal':
      return l.tierNormal;
    case 'elevated':
      return l.tierElevated;
    case 'stage1':
      return l.tierStage1;
    case 'stage2':
      return l.tierStage2;
    default:
      return tier;
  }
}

String _bmiLabel(String tier, AppLocalizations l) {
  switch (tier) {
    case 'underweight':
      return l.tierUnderweight;
    case 'normal':
      return l.tierNormal;
    case 'overweight':
      return l.tierOverweight;
    case 'obese':
      return l.tierObese;
    default:
      return tier;
  }
}

String _prefLabel(String pref, AppLocalizations l) {
  switch (pref) {
    case 'omnivore':
      return l.foodPrefOmnivore;
    case 'vegetarian':
      return l.foodPrefVegetarian;
    case 'fish_only':
      return l.foodPrefFishOnly;
    case 'no_beef':
      return l.foodPrefNoBeef;
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
