/// Clinical snapshot — a single, reusable card that summarises the
/// patient's current clinical classification (glucose tier, BP tier,
/// carb/sodium caps, food preference, and Bangla recommendations).
///
/// Used on both the new Dashboard landing page and (optionally) the
/// Profile screen so the user sees the same clinical summary in both
/// places. Replaces the legacy "personalization row" that used to live
/// at the top of the meal-plan screen and the inline clinical block
/// that used to sit below the user's account card.
library;

import 'package:flutter/material.dart';

import '../services/diet_recommender.dart';
import '../theme/app_theme.dart';

/// A reusable clinical-snapshot card.
///
/// Accepts an already-computed [DietClassification] (preferred) and
/// falls back to a sentinel "loading" copy if [classification] is null.
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
      padding: EdgeInsets.symmetric(
        horizontal: 18,
        vertical: dense ? 14 : 18,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A1422), Color(0xFF1F1018)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.brandPink.withValues(alpha: 0.16),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandMaroon.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppGradients.brandMagenta,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.favorite_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'ক্লিনিক্যাল সারসংক্ষেপ',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (c.conditions.hasCkd ||
                  c.conditions.hasHeartDisease ||
                  c.conditions.hasAnemia)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.brandPinkDeep.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'সতর্কতা',
                    style: TextStyle(
                      color: AppColors.brandPink,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: dense ? 10 : 14),
          // Tier pills — glucose / BP / BMI row
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _tierPill(
                icon: Icons.water_drop_rounded,
                label: 'গ্লুকোজ',
                value: _glucoseLabel(c.glucoseTier),
                color: _tierColor(c.glucoseTier),
              ),
              _tierPill(
                icon: Icons.monitor_heart_outlined,
                label: 'রক্তচাপ',
                value: _bpLabel(c.bpTier),
                color: _tierColor(c.bpTier),
              ),
              _tierPill(
                icon: Icons.scale_outlined,
                label: 'BMI',
                value: _bmiLabel(c.bmiTier),
                color: AppColors.brandPinkDeep,
              ),
              _tierPill(
                icon: Icons.restaurant_outlined,
                label: 'খাদ্য',
                value: _prefLabel(c.foodPreference),
                color: Colors.white,
              ),
            ],
          ),
          SizedBox(height: dense ? 12 : 16),
          // Cap tiles — carbs / sodium / kcal
          _capsRow(c),
          if (!dense && c.recommendationsBn.isNotEmpty) ...[
            const SizedBox(height: 16),
            const _Subheading(
              icon: Icons.check_circle_outline,
              title: 'আজকের সুপারিশ',
            ),
            const SizedBox(height: 8),
            ...c.recommendationsBn.take(3).map((r) => _bullet(r, ok: true)),
          ],
          if (!dense && c.warnings.isNotEmpty) ...[
            const SizedBox(height: 14),
            const _Subheading(
              icon: Icons.warning_amber_rounded,
              title: 'সতর্কতা',
            ),
            const SizedBox(height: 8),
            ...c.warnings.take(2).map((w) => _bullet(w, ok: false)),
          ],
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A1422), Color(0xFF1F1018)],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.brandPink),
            ),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Text(
              'ক্লিনিক্যাল তথ্য হিসাব করা হচ্ছে…',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _capsRow(DietClassification c) {
    final caps = <_CapTile>[
      _CapTile(
        icon: Icons.grain_rounded,
        label: 'দৈনিক কার্ব',
        value: '${c.dailyCarbTargetG.toStringAsFixed(0)} গ্রাম',
        subtitle: 'প্রতি বেলা ${c.maxCarbPerMeal.toStringAsFixed(0)} গ্রাম',
      ),
      _CapTile(
        icon: Icons.local_fire_department_outlined,
        label: 'ক্যালোরি',
        value: '${c.dailyKcalTarget.toStringAsFixed(0)} কিঃক্যালোরি',
        subtitle: 'প্রতিদিনের লক্ষ্য',
      ),
      _CapTile(
        icon: Icons.spa_rounded,
        label: 'সোডিয়াম',
        value: '${c.dailySodiumCapMg.toStringAsFixed(0)} মিগ্রা',
        subtitle: 'দৈনিক সর্বোচ্চ',
      ),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < caps.length; i++) ...[
          Expanded(child: _cap(caps[i])),
          if (i != caps.length - 1) const SizedBox(width: 10),
        ],
      ],
    );
  }

  Widget _cap(_CapTile t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(t.icon, size: 14, color: AppColors.brandPink),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    t.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              t.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              t.subtitle,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 10,
                height: 1.1,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );

  Widget _tierPill({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '$label · ',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color.withValues(alpha: 0.8),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bullet(String text, {required bool ok}) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ok ? AppColors.brandPink : const Color(0xFFFFB4A2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Subheading extends StatelessWidget {
  final IconData icon;
  final String title;
  const _Subheading({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.brandPink),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ],
    );
  }
}

class _CapTile {
  final IconData icon;
  final String label;
  final String value;
  final String subtitle;
  const _CapTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
  });
}

// ─────────────────── label helpers ───────────────────

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
    case 'underweight':
      return AppColors.mint;
    case 'moderate':
    case 'overweight':
    case 'elevated':
    case 'stage1':
      return const Color(0xFFFFB4A2);
    case 'poor':
    case 'stage2':
    case 'obese':
      return const Color(0xFFFFD6CC);
    default:
      return AppColors.brandPink;
  }
}
