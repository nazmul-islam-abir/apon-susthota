// আমার ডায়েট — Meal Details screen (v4).
//
// Visual reference: hero image + back/more buttons + BREAKFAST pill
// (bottom-left), 2 stat cards (prep time + difficulty), centered
// calorie ring, "Nutritional Value" bars (protein/carb/fat),
// "Why Eat This?" heading + paragraph, 3 benefit cards with
// heart/dumbbell/leaf icons. All copy Bangla with Hind Siliguri font.
//
// Data: `SupabaseService.getMealDetails(foodId)` →
// `get_food_details(p_food_id)` RPC → MealDetails model.
//

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/meal_details.dart';
import '../models/meal_item.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class MealDetailsScreen extends StatefulWidget {
  final String foodId;
  final String? fallbackNameBn;
  final MealItem? seed;

  const MealDetailsScreen({
    super.key,
    required this.foodId,
    this.fallbackNameBn,
    this.seed,
  });

  @override
  State<MealDetailsScreen> createState() => _MealDetailsScreenState();
}

class _MealDetailsScreenState extends State<MealDetailsScreen> {
  Future<MealDetails?>? _future;

  @override
  void initState() {
    super.initState();
    _future = SupabaseService.getMealDetails(widget.foodId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.void2,
      body: FutureBuilder<MealDetails?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return _DetailsLoading(
              seed: widget.seed,
              fallbackNameBn: widget.fallbackNameBn,
            );
          }
          if (snap.hasError) {
            return _DetailsError(
              onRetry: () => setState(() => _future = _retry()),
            );
          }
          final details = snap.data;
          if (details == null) {
            return _DetailsEmpty(
              seed: widget.seed,
              fallbackNameBn: widget.fallbackNameBn,
              onRetry: () => setState(() => _future = _retry()),
            );
          }
          return _DetailsBody(details: details);
        },
      ),
    );
  }

  Future<MealDetails?> _retry() =>
      SupabaseService.getMealDetails(widget.foodId);
}

// ── Loading / Error / Empty shells ──────────────────────────────────────

class _DetailsLoading extends StatelessWidget {
  final MealItem? seed;
  final String? fallbackNameBn;
  const _DetailsLoading({required this.seed, this.fallbackNameBn});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.void2,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.cyan),
            const SizedBox(height: 16),
            Text(
              seed?.nameBn ?? fallbackNameBn ?? 'লোড হচ্ছে…',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailsError extends StatelessWidget {
  final VoidCallback onRetry;
  const _DetailsError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.void2,
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined,
                  color: AppColors.rose, size: 36),
              const SizedBox(height: 12),
              const Text(
                'তথ্য লোড হয়নি',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: onRetry, child: const Text('আবার চেষ্টা')),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailsEmpty extends StatelessWidget {
  final MealItem? seed;
  final String? fallbackNameBn;
  final VoidCallback onRetry;
  const _DetailsEmpty({
    required this.seed,
    required this.fallbackNameBn,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.void2,
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_meals_outlined,
                  color: AppColors.textMuted, size: 36),
              const SizedBox(height: 12),
              Text(
                seed?.nameBn ?? fallbackNameBn ?? 'তথ্য পাওয়া যায়নি',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: onRetry, child: const Text('আবার চেষ্টা')),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Main body matching reference image 2 ───────────────────────────────

class _DetailsBody extends StatelessWidget {
  final MealDetails details;
  const _DetailsBody({required this.details});

  IconData _benefitIcon(String name) {
    switch (name) {
      case 'bolt':
      case 'flash_on':
        return Icons.bolt;
      case 'eco':
      case 'leaf':
        return Icons.eco;
      case 'restaurant':
        return Icons.restaurant;
      case 'favorite':
      case 'heart':
      default:
        return Icons.favorite;
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalMacro = (details.carbG + details.proteinG + details.fatG)
        .clamp(1, 9999)
        .toDouble();

    final benefits = details.benefits.isNotEmpty
        ? details.benefits
        : _fallbackBenefits(details);

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          SliverToBoxAdapter(child: _Header(details: details)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'PREP TIME',
                      value: '${details.prepTimeMin}',
                      unit: 'min',
                      icon: Icons.schedule,
                      bg: AppColors.cyan.withValues(alpha: 0.10),
                      fg: AppColors.cyan,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: 'DIFFICULTY',
                      value: details.difficultyBn,
                      unit: '',
                      icon: Icons.bolt,
                      bg: AppColors.mint.withValues(alpha: 0.12),
                      fg: AppColors.mintDeep,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: _CalorieRing(
                kcal: details.kcal,
                label: 'CALORIE',
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: _NutritionCard(
                proteinG: details.proteinG,
                carbG: details.carbG,
                fatG: details.fatG,
                totalMacro: totalMacro,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 4),
              child: const Text(
                'কেন খাবেন?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(
                details.whyEatThisBn.isNotEmpty
                    ? details.whyEatThisBn
                    : '${details.nameBn} ডায়াবেটিস-বান্ধব একটি খাবার — '
                        'এতে কম গ্লাইসেমিক ইনডেক্স, ভালো পুষ্টি ও পর্যাপ্ত ফাইবার রয়েছে।',
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
            sliver: SliverList.builder(
              itemCount: benefits.length.clamp(0, 3),
              itemBuilder: (context, i) {
                final b = benefits[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _BenefitCard(
                    icon: _benefitIcon(b.icon),
                    title: b.title,
                    body: b.body,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<MealBenefit> _fallbackBenefits(MealDetails d) {
    final out = <MealBenefit>[];
    if (d.fatG > 3) {
      out.add(MealBenefit(
        icon: 'favorite',
        title: 'হৃদযন্ত্রের জন্য ভালো ফ্যাট',
        body: 'ভালো মানের ফ্যাট কোলেস্টেরল ও হৃদরোগের ঝুঁকি কমায়।',
      ));
    }
    if (d.proteinG > 5) {
      out.add(MealBenefit(
        icon: 'bolt',
        title: 'উচ্চমানের প্রোটিন',
        body: 'রক্তে শর্করা নিয়ন্ত্রণে সাহায্য করে এবং পেশি গঠনে সহায়ক।',
      ));
    }
    if (d.fiberG >= 2) {
      out.add(MealBenefit(
        icon: 'eco',
        title: 'ফাইবার সমৃদ্ধ',
        body: 'হজম প্রক্রিয়া ভালো রাখে এবং দীর্ঘক্ষণ পেট ভরা রাখে।',
      ));
    }
    while (out.length < 2) {
      out.add(MealBenefit(
        icon: 'favorite',
        title: 'পুষ্টিকর বিকল্প',
        body: '${d.nameBn} একটি সহজলভ্য ও সুস্বাদু পছন্দ।',
      ));
    }
    return out.take(3).toList();
  }
}

// ── Header (hero + back/more buttons + BREAKFAST pill) ─────────────────

class _Header extends StatelessWidget {
  final MealDetails details;
  const _Header({required this.details});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 360,
      child: Stack(
        children: [
          Positioned.fill(
            child: _HeroImage(details: details),
          ),
          // soft top scrim so the back/menu buttons stay readable
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.30),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          // back + menu
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    _circleButton(
                      icon: Icons.arrow_back,
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const Spacer(),
                    _circleButton(
                      icon: Icons.more_horiz,
                      onTap: () => _showOptions(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // BREAKFAST pill (uses food category as a friendly tag).
          Positioned(
            left: 20,
            bottom: 18,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.mint,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text(
                _categoryPill(details.category),
                style: const TextStyle(
                  color: AppColors.void1,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          // title (also visible in the body section header, but the
          // image overlay benefits from its own caption so it stays
          // on-brand when the hero is white-ish)
          Positioned(
            left: 20,
            right: 20,
            bottom: 60,
            child: Text(
              details.nameBn,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.void1,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                shadows: [
                  Shadow(blurRadius: 12, color: Colors.black54),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _categoryPill(String category) {
    switch (category) {
      case 'protein':
        return 'PROTEIN';
      case 'vegetable':
        return 'VEGETABLE';
      case 'carb':
        return 'CARB';
      case 'dal':
        return 'LENTIL';
      case 'snack':
        return 'SNACK';
      default:
        return 'BREAKFAST';
    }
  }

  Widget _circleButton({required IconData icon, required VoidCallback onTap}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: Colors.white.withValues(alpha: 0.25),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, color: Colors.white, size: 22),
            ),
          ),
        ),
      ),
    );
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('শেয়ার করুন'),
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: details.nameBn));
              },
            ),
            ListTile(
              leading: const Icon(Icons.bookmark_border),
              title: const Text('পছন্দের তালিকায় যোগ করুন'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroImage extends StatelessWidget {
  final MealDetails details;
  const _HeroImage({required this.details});

  @override
  Widget build(BuildContext context) {
    final url = details.imageUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        loadingBuilder: (ctx, child, p) => p == null
            ? child
            : Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF065F46), Color(0xFF10B981)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                alignment: Alignment.center,
                child: const CircularProgressIndicator(color: AppColors.void1),
              ),
        errorBuilder: (ctx, e, s) => _gradient(),
      );
    }
    return _gradient();
  }

  Widget _gradient() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF065F46), Color(0xFF10B981)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.restaurant, color: Colors.white, size: 64),
    );
  }
}

// ── Stat cards (Prep / Difficulty) ─────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color bg;
  final Color fg;
  const _StatCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: fg, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: fg,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Calorie ring ───────────────────────────────────────────────────────

class _CalorieRing extends StatelessWidget {
  final double kcal;
  final String label;
  const _CalorieRing({required this.kcal, required this.label});

  @override
  Widget build(BuildContext context) {
    final dailyTarget = 600.0; // approx per-meal target; UI ring is symbolic
    final pct = (kcal / dailyTarget).clamp(0.0, 1.0).toDouble();
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.textMuted,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: 180,
            height: 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 180,
                  height: 180,
                  child: CircularProgressIndicator(
                    value: 1,
                    strokeWidth: 12,
                    color: AppColors.surfaceHigh,
                  ),
                ),
                SizedBox(
                  width: 180,
                  height: 180,
                  child: CircularProgressIndicator(
                    value: pct,
                    strokeWidth: 12,
                    color: AppColors.cyan,
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.local_fire_department,
                        color: AppColors.rose, size: 28),
                    const SizedBox(height: 4),
                    Text(
                      kcal.toStringAsFixed(0),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: AppColors.text,
                      ),
                    ),
                    const Text(
                      'kcal',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Nutrition bars (Protein / Carbs / Fat) ─────────────────────────────

class _NutritionCard extends StatelessWidget {
  final double proteinG;
  final double carbG;
  final double fatG;
  final double totalMacro;
  const _NutritionCard({
    required this.proteinG,
    required this.carbG,
    required this.fatG,
    required this.totalMacro,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nutritional Value',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 18),
          _MacroRow(
            label: 'Protein',
            color: AppColors.mintDeep,
            grams: proteinG,
            fraction: proteinG / totalMacro,
          ),
          const SizedBox(height: 14),
          _MacroRow(
            label: 'Carbs',
            color: AppColors.cyan,
            grams: carbG,
            fraction: carbG / totalMacro,
          ),
          const SizedBox(height: 14),
          _MacroRow(
            label: 'Fat',
            color: AppColors.amber,
            grams: fatG,
            fraction: fatG / totalMacro,
          ),
        ],
      ),
    );
  }
}

class _MacroRow extends StatelessWidget {
  final String label;
  final Color color;
  final double grams;
  final double fraction;
  const _MacroRow({
    required this.label,
    required this.color,
    required this.grams,
    required this.fraction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.05, 1.0).toDouble(),
              minHeight: 10,
              color: color,
              backgroundColor: AppColors.surfaceHigh,
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 50,
          child: Text(
            '${grams.toStringAsFixed(0)}g',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Benefit card ───────────────────────────────────────────────────────

class _BenefitCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _BenefitCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.cyan.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.cyan, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: GoogleFonts.hindSiliguri(
                    textStyle: const TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      color: AppColors.textMuted,
                    ),
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
