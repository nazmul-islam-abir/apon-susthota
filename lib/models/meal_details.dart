/// Combines a base [MealItem] (from `public.foods`) with one extra
/// row from `public.food_details` (recipe, benefits, cautions...).
/// This is what the MealDetailsScreen renders — produced by the
/// `get_food_details(p_food_id text)` RPC.
class MealDetails {
  /// Master food row (id, name, macros, GI, portion, image...).
  final String id;
  final String nameBn;
  final String nameEn;
  final String category;
  final double carbG;
  final double proteinG;
  final double fatG;
  final double fiberG;
  final double sodiumMg;
  final double potassiumMg;
  final double phosphorusMg;
  final String giCategory;
  final String? portionLabel;
  final double? portionG;
  final String affordability;
  final bool commonInBd;
  final String effort;
  final String healthiness;
  final List<String> tags;
  final String? imageUrl;

  // ---- detail-side fields (public.food_details) ----
  final int prepTimeMin;
  final String difficulty; // easy | medium | hard

  /// Short user-facing "Why eat this?" intro paragraph (Bangla).
  final String whyEatThisBn;

  /// Local-measure ingredients, e.g. ["২ কাপ লাল আটা", …].
  final List<String> ingredientsBn;

  /// Ordered cooking steps in Bangla.
  final List<String> stepsBn;

  /// 3 short benefit cards. Each item:
  ///   { icon: String, title: String, body: String }.
  final List<MealBenefit> benefits;

  /// Optional clinical cautions ("কিডনি রোগী পরিমিত খান"…).
  final List<String> cautionsBn;

  /// Optional serving tip ("লেবু চিপে খান"…).
  final String? servingTipBn;

  /// False when `public.food_details` has no row yet — UI shows a
  /// "তথ্য শীঘ্রই আসছে" placeholder.
  final bool hasDetails;

  const MealDetails({
    required this.id,
    required this.nameBn,
    required this.nameEn,
    required this.category,
    required this.carbG,
    required this.proteinG,
    required this.fatG,
    required this.fiberG,
    required this.sodiumMg,
    required this.potassiumMg,
    required this.phosphorusMg,
    required this.giCategory,
    this.portionLabel,
    this.portionG,
    this.affordability = 'low_cost',
    this.commonInBd = true,
    this.effort = 'easy',
    this.healthiness = 'good',
    this.tags = const [],
    this.imageUrl,
    this.prepTimeMin = 10,
    this.difficulty = 'easy',
    this.whyEatThisBn = '',
    this.ingredientsBn = const [],
    this.stepsBn = const [],
    this.benefits = const [],
    this.cautionsBn = const [],
    this.servingTipBn,
    this.hasDetails = false,
  });

  /// Estimated energy using Atwater factors (4-4-9) for the portion
  /// stored on the food row.
  double get kcal {
    return (carbG * 4.0) + (proteinG * 4.0) + (fatG * 9.0);
  }

  bool get isCheap => affordability == 'low_cost';
  bool get isLocal => commonInBd;
  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  /// Difficulty → Bangla label for the stat card.
  String get difficultyBn {
    switch (difficulty) {
      case 'medium':
        return 'মাঝারি';
      case 'hard':
        return 'কঠিন';
      default:
        return 'সহজ';
    }
  }

  /// Builds a [MealDetails] from the JSON returned by the
  /// `get_food_details(p_food_id text)` RPC. Tolerant of missing
  /// fields and of the optional `has_details = false` fallback
  /// returned when the food row exists but no detail row exists yet.
  factory MealDetails.fromJson(Map<String, dynamic> json) {
    final rawImg = json['image_url'];
    final img = rawImg is String && rawImg.trim().isNotEmpty
        ? rawImg.trim()
        : null;

    final ing = (json['ingredients_bn'] as List?)
            ?.map((e) => e?.toString() ?? '')
            .where((s) => s.trim().isNotEmpty)
            .toList() ??
        const <String>[];
    final stp = (json['steps_bn'] as List?)
            ?.map((e) => e?.toString() ?? '')
            .where((s) => s.trim().isNotEmpty)
            .toList() ??
        const <String>[];
    final cau = (json['cautions_bn'] as List?)
            ?.map((e) => e?.toString() ?? '')
            .where((s) => s.trim().isNotEmpty)
            .toList() ??
        const <String>[];
    final rawBenefits = json['benefits'];
    final benefits = <MealBenefit>[];
    if (rawBenefits is List) {
      for (final e in rawBenefits) {
        if (e is Map) {
          benefits.add(MealBenefit.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }

    return MealDetails(
      id: (json['id'] ?? '') as String,
      nameBn: (json['name_bn'] ?? '') as String,
      nameEn: (json['name_en'] ?? json['name'] ?? '') as String,
      category: (json['category'] ?? 'snack') as String,
      carbG: ((json['carb_g'] ?? 0) as num).toDouble(),
      proteinG: ((json['protein_g'] ?? 0) as num).toDouble(),
      fatG: ((json['fat_g'] ?? 0) as num).toDouble(),
      fiberG: ((json['fiber_g'] ?? 0) as num).toDouble(),
      sodiumMg: ((json['sodium_mg'] ?? 0) as num).toDouble(),
      potassiumMg: ((json['potassium_mg'] ?? 0) as num).toDouble(),
      phosphorusMg: ((json['phosphorus_mg'] ?? 0) as num).toDouble(),
      giCategory: (json['gi_category'] ?? 'low') as String,
      portionLabel: json['portion_label'] as String?,
      portionG: json['portion_g'] != null
          ? ((json['portion_g']) as num).toDouble()
          : null,
      affordability: (json['affordability'] ?? 'low_cost') as String,
      commonInBd: json['common_in_bd'] as bool? ?? true,
      effort: (json['effort'] ?? 'easy') as String,
      healthiness: (json['healthiness'] ?? 'good') as String,
      tags: (json['tags'] as List?)?.cast<String>() ?? const [],
      imageUrl: img,
      prepTimeMin: (json['prep_time_min'] is num)
          ? (json['prep_time_min'] as num).toInt()
          : 10,
      difficulty: (json['difficulty'] ?? 'easy') as String,
      whyEatThisBn: (json['why_eat_this_bn'] ?? '') as String,
      ingredientsBn: ing,
      stepsBn: stp,
      benefits: benefits,
      cautionsBn: cau,
      servingTipBn: json['serving_tip_bn'] as String?,
      hasDetails: json['has_details'] == true,
    );
  }
}

/// One benefit card in the "কেন খাবেন" section. Mirrors the SQL
/// `benefits` jsonb shape: { icon, title, body }.
class MealBenefit {
  final String icon; // favorite | bolt | eco | payments | restaurant …
  final String title;
  final String body;

  const MealBenefit({
    required this.icon,
    required this.title,
    required this.body,
  });

  factory MealBenefit.fromJson(Map<String, dynamic> json) {
    return MealBenefit(
      icon: (json['icon'] ?? 'favorite') as String,
      title: (json['title'] ?? '') as String,
      body: (json['body'] ?? '') as String,
    );
  }

  bool get isEmpty => title.trim().isEmpty && body.trim().isEmpty;
}
