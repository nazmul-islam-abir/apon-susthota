/// Lightweight model for a food item, used both by the plan and the log.
class MealItem {
  final String id;
  final String nameBn;
  final String category; // breakfast / carb / protein / vegetable / dal / snack
  final double carbG;
  final double proteinG;
  final double fatG;
  final double fiberG;
  final double sodiumMg;
  final double potassiumMg;
  final double phosphorusMg;
  final String giCategory; // low / medium / high
  final String? portionLabel;
  final double? portionG;
  final String affordability; // low_cost / medium / premium
  final bool commonInBd;
  final String effort; // easy / medium / hard
  final String healthiness; // good / neutral / bad
  final List<String> tags;

  /// Optional remote image URL (populated from `foods.image_url`).
  /// Null or empty means "no image — render a gradient avatar".
  final String? imageUrl;

  MealItem({
    required this.id,
    required this.nameBn,
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
  });

  /// Estimated energy using the Atwater factors (4-4-9).
  /// Returns kcal for one portion of this food.
  double get kcal {
    return (carbG * 4.0) + (proteinG * 4.0) + (fatG * 9.0);
  }

  factory MealItem.fromJson(Map<String, dynamic> json) {
    final rawImg = json['image_url'];
    final img = rawImg is String && rawImg.trim().isNotEmpty
        ? rawImg.trim()
        : null;
    return MealItem(
      id: (json['id'] ?? '') as String,
      nameBn: (json['name_bn'] ?? '') as String,
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
    );
  }

  bool get isCheap => affordability == 'low_cost';
  bool get isLocal => commonInBd;
  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;
}

/// A single planned meal slot (e.g. "breakfast/carb", "lunch/protein").
class MealSlotPlan {
  final String slot; // breakfast | morning_snack | lunch | evening_snack | dinner
  final String role; // main | carb | protein | vegetable | dal | snack
  final MealItem food;
  final List<MealItem> alternatives;

  /// `ai`     — suggestion came straight from the 30-day rotation.
  /// `override` — suggestion is from the user's per-day override row.
  /// `custom` — entry lives in user_meal_plans (an extra / swapped slot).
  final String source;

  /// When [source] == 'custom', this is the user_meal_plans row id
  /// so the UI can edit or delete it. Null for ai/override tiles.
  final String? customId;

  /// User-editable overrides + custom entries can carry a time/portion
  /// the AI baseline doesn't have. Null for pure AI tiles.
  final String? customTime; // HH:mm
  final String? customPortionLabel;

  const MealSlotPlan({
    required this.slot,
    required this.role,
    required this.food,
    this.alternatives = const [],
    this.source = 'ai',
    this.customId,
    this.customTime,
    this.customPortionLabel,
  });

  bool get isAi => source == 'ai';
  bool get isOverride => source == 'override';
  bool get isCustom => source == 'custom';

  /// Render-friendly 12-hour wall-clock time with AM/PM (e.g.
  /// `"8:00 AM"`). Returns empty string when no custom time.
  /// Storage stays 24-hour `HH:mm` in [customTime]; the UI should
  /// always render via this getter so Bangladesh users see the
  /// familiar AM/PM form.
  String get displayTime {
    final t = customTime;
    if (t == null || t.isEmpty) return '';
    // Accept HH:mm:ss(.ffffff) or HH:mm.
    final parts = t.split(':');
    if (parts.length < 2) return t;
    final h24 = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h24 == null || m == null) return '${parts[0]}:${parts[1]}';
    final ampm = h24 < 12 ? 'AM' : 'PM';
    var h12 = h24 % 12;
    if (h12 == 0) h12 = 12;
    final mm = m.toString().padLeft(2, '0');
    return '$h12:$mm $ampm';
  }

  /// Parses either the v2 SQL shape
  /// (`{slot, role, food, alternatives, source, custom_id}`) or the
  /// legacy v1 shape used by older RPCs.
  factory MealSlotPlan.fromJson(Map<String, dynamic> json) {
    final foodJson = json['food'];
    MealItem food;
    if (foodJson is Map) {
      food = MealItem.fromJson(Map<String, dynamic>.from(foodJson));
    } else if (foodJson is String) {
      food = MealItem(
        id: '',
        nameBn: foodJson,
        category: 'snack',
        carbG: 0,
        proteinG: 0,
        fatG: 0,
        fiberG: 0,
        sodiumMg: 0,
        potassiumMg: 0,
        phosphorusMg: 0,
        giCategory: 'low',
      );
    } else {
      food = MealItem(
        id: '',
        nameBn: '',
        category: 'snack',
        carbG: 0,
        proteinG: 0,
        fatG: 0,
        fiberG: 0,
        sodiumMg: 0,
        potassiumMg: 0,
        phosphorusMg: 0,
        giCategory: 'low',
      );
    }
    final altList = (json['alternatives'] as List?) ??
        (json['alts'] as List?) ??
        const [];
    final alts = altList
        .where((e) => e is Map)
        .map((e) => MealItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return MealSlotPlan(
      slot: (json['slot'] ?? '') as String,
      role: (json['role'] ?? 'main') as String,
      food: food,
      alternatives: alts,
      source: (json['source'] ?? 'ai') as String,
      customId: json['custom_id'] as String?,
      customTime: json['custom_time'] as String?,
      customPortionLabel: json['custom_portion_label'] as String?,
    );
  }
}

/// A single logged entry from `meal_intake_log`.
class MealLogEntry {
  final String id;
  final String mealSlot;
  final String? foodId;
  final String foodNameBn;
  final String status; // eaten | swap | off_plan
  final String impact; // good | neutral | bad
  final String? notes;
  final String? impactReason;
  final int? planDay; // 1..30 — which rotation day this entry belongs to
  final DateTime createdAt;

  const MealLogEntry({
    required this.id,
    required this.mealSlot,
    required this.foodId,
    required this.foodNameBn,
    required this.status,
    required this.impact,
    this.notes,
    this.impactReason,
    this.planDay,
    required this.createdAt,
  });

  factory MealLogEntry.fromJson(Map<String, dynamic> json) {
    return MealLogEntry(
      id: (json['id'] ?? '') as String,
      mealSlot: (json['meal_slot'] ?? '') as String,
      foodId: json['food_id'] as String?,
      foodNameBn: (json['food_name_bn'] ?? '') as String,
      status: (json['status'] ?? 'eaten') as String,
      impact: (json['impact'] ?? 'neutral') as String,
      notes: json['notes'] as String?,
      impactReason: json['impact_reason'] as String?,
      planDay: json['plan_day'] is int
          ? json['plan_day'] as int
          : (json['plan_day'] is num
              ? (json['plan_day'] as num).toInt()
              : null),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
