// =====================================================================
// Amar Diet — local data layer (Hive-backed)
// =====================================================================
//
// All CRUD is backed by Hive (persistent local DB). On first launch,
// HiveStore.init() must be awaited from main().
//
// BDApps is still used for OTP / subscription but every screen reads
// from this Hive-backed store. The public API is unchanged from the
// previous in-memory version, so no screen needs to be edited.
// =====================================================================

import '../data/bd_food_library.dart' as bd;
import 'auth_service.dart';
import 'hive_store.dart';

// ---------------------------------------------------------------------
//  Models
// ---------------------------------------------------------------------

class UserProfile {
  const UserProfile({
    required this.id,
    required this.phone,
    this.name,
    this.email,
    this.gender,
    this.dateOfBirth,
    this.heightCm,
    this.weightKg,
    this.activityLevel,
    this.goal,
    this.targetWeightKg,
    this.dietPref,
    this.bmr,
    this.tdee,
    this.dailyCalorieTarget,
    this.isPro = false,
  });

  final String id;
  final String phone;
  final String? name;
  final String? email;
  final String? gender;
  final DateTime? dateOfBirth;
  final double? heightCm;
  final double? weightKg;
  final String? activityLevel;
  final String? goal;
  final double? targetWeightKg;
  final String? dietPref;
  final double? bmr;
  final double? tdee;
  final double? dailyCalorieTarget;
  final bool isPro;

  String? get initials {
    final n = name?.trim();
    if (n == null || n.isEmpty) return null;
    final parts = n.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  int? get age {
    if (dateOfBirth == null) return null;
    final now = DateTime.now();
    var age = now.year - dateOfBirth!.year;
    if (now.month < dateOfBirth!.month ||
        (now.month == dateOfBirth!.month && now.day < dateOfBirth!.day)) {
      age--;
    }
    return age;
  }

  double? get bmi {
    if (heightCm == null || weightKg == null || heightCm == 0) return null;
    final m = heightCm! / 100.0;
    return weightKg! / (m * m);
  }

  String bmiLabel() {
    final b = bmi;
    if (b == null) return '—';
    if (b < 18.5) return 'under';
    if (b < 25) return 'normal';
    if (b < 30) return 'over';
    return 'obese';
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'phone': phone,
        'name': name,
        'email': email,
        'gender': gender,
        'date_of_birth': dateOfBirth == null
            ? null
            : '${dateOfBirth!.year.toString().padLeft(4, '0')}-${dateOfBirth!.month.toString().padLeft(2, '0')}-${dateOfBirth!.day.toString().padLeft(2, '0')}',
        'height_cm': heightCm,
        'weight_kg': weightKg,
        'activity_level': activityLevel,
        'goal': goal,
        'target_weight_kg': targetWeightKg,
        'diet_pref': dietPref,
        'bmr': bmr,
        'tdee': tdee,
        'daily_calorie_target': dailyCalorieTarget,
        'is_pro': isPro,
      };

  static UserProfile fromMap(Map m) => UserProfile(
        id: (m['id'] ?? '').toString(),
        phone: (m['phone'] ?? '').toString(),
        name: m['name']?.toString(),
        email: m['email']?.toString(),
        gender: m['gender']?.toString(),
        dateOfBirth: m['date_of_birth'] == null
            ? null
            : DateTime.tryParse(m['date_of_birth'].toString()),
        heightCm: (m['height_cm'] as num?)?.toDouble(),
        weightKg: (m['weight_kg'] as num?)?.toDouble(),
        activityLevel: m['activity_level']?.toString(),
        goal: m['goal']?.toString(),
        targetWeightKg: (m['target_weight_kg'] as num?)?.toDouble(),
        dietPref: m['diet_pref']?.toString(),
        bmr: (m['bmr'] as num?)?.toDouble(),
        tdee: (m['tdee'] as num?)?.toDouble(),
        dailyCalorieTarget: (m['daily_calorie_target'] as num?)?.toDouble(),
        isPro: m['is_pro'] == true,
      );
}

class FoodItem {
  const FoodItem({
    required this.id,
    required this.nameEn,
    required this.category,
    required this.servingG,
    required this.kcalPerServing,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.fiberG,
    this.nameBn,
  });

  final String id;
  final String nameEn;
  final String? nameBn;
  final String category;
  final double servingG;
  final double kcalPerServing;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double fiberG;

  String get displayName =>
      (nameBn != null && nameBn!.isNotEmpty) ? nameBn! : nameEn;
  double get kcal => kcalPerServing;
}

class MealEntry {
  const MealEntry({
    required this.id,
    required this.foodId,
    required this.foodName,
    required this.mealType,
    required this.servings,
    required this.eatenOn,
    required this.kcalTotal,
    required this.proteinTotal,
    required this.carbsTotal,
    required this.fatTotal,
    required this.createdAt,
  });

  final String id;
  final String foodId;
  final String foodName;
  final String mealType;
  final double servings;
  final DateTime eatenOn;
  final double kcalTotal;
  final double proteinTotal;
  final double carbsTotal;
  final double fatTotal;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'food_id': foodId,
        'food_name': foodName,
        'meal_type': mealType,
        'servings': servings,
        'eaten_on': eatenOn.toIso8601String(),
        'kcal_total': kcalTotal,
        'protein_total': proteinTotal,
        'carbs_total': carbsTotal,
        'fat_total': fatTotal,
        'created_at': createdAt.toIso8601String(),
      };

  static MealEntry fromMap(Map m) => MealEntry(
        id: (m['id'] ?? '').toString(),
        foodId: (m['food_id'] ?? '').toString(),
        foodName: (m['food_name'] ?? '').toString(),
        mealType: (m['meal_type'] ?? 'snack').toString(),
        servings: ((m['servings'] as num?)?.toDouble()) ?? 1,
        eatenOn: DateTime.tryParse(m['eaten_on']?.toString() ?? '') ??
            DateTime.now(),
        kcalTotal: ((m['kcal_total'] as num?)?.toDouble()) ?? 0,
        proteinTotal: ((m['protein_total'] as num?)?.toDouble()) ?? 0,
        carbsTotal: ((m['carbs_total'] as num?)?.toDouble()) ?? 0,
        fatTotal: ((m['fat_total'] as num?)?.toDouble()) ?? 0,
        createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}

class WaterLog {
  const WaterLog({
    required this.date,
    required this.totalMl,
    required this.targetMl,
    required this.entries,
  });
  factory WaterLog.empty() => WaterLog(
        date: DateTime.now(),
        totalMl: 0,
        targetMl: 2500,
        entries: const [],
      );

  final DateTime date;
  final int totalMl;
  final int targetMl;
  final List<WaterEntry> entries;
}

class WaterEntry {
  const WaterEntry({
    required this.id,
    required this.amountMl,
    required this.loggedOn,
    required this.loggedAt,
  });
  final String id;
  final int amountMl;
  final DateTime loggedOn;
  final DateTime? loggedAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'amount_ml': amountMl,
        'logged_on': loggedOn.toIso8601String(),
        'logged_at': loggedAt?.toIso8601String(),
      };

  static WaterEntry fromMap(Map m) => WaterEntry(
        id: (m['id'] ?? '').toString(),
        amountMl: ((m['amount_ml'] as num?)?.toInt()) ?? 0,
        loggedOn: DateTime.tryParse(m['logged_on']?.toString() ?? '') ??
            DateTime.now(),
        loggedAt: m['logged_at'] == null
            ? null
            : DateTime.tryParse(m['logged_at'].toString()),
      );
}

class DailyPlan {
  const DailyPlan({
    required this.planDate,
    required this.kcalTarget,
    required this.waterMl,
    this.notes,
  });
  factory DailyPlan.empty() => DailyPlan(
        planDate: DateTime.now(),
        kcalTarget: 2000,
        waterMl: 2500,
      );

  final DateTime planDate;
  final double kcalTarget;
  final int waterMl;
  final String? notes;

  Map<String, dynamic> toMap() => {
        'plan_date': planDate.toIso8601String(),
        'kcal_target': kcalTarget,
        'water_ml': waterMl,
        'notes': notes,
      };

  static DailyPlan fromMap(Map m) => DailyPlan(
        planDate: DateTime.tryParse(m['plan_date']?.toString() ?? '') ??
            DateTime.now(),
        kcalTarget: ((m['kcal_target'] as num?)?.toDouble()) ?? 2000,
        waterMl: ((m['water_ml'] as num?)?.toInt()) ?? 2500,
        notes: m['notes']?.toString(),
      );
}

class ProgressReport {
  const ProgressReport({
    required this.today,
    required this.target,
    required this.week,
    required this.streak,
    required this.weight,
    required this.macros,
  });

  factory ProgressReport.empty() => ProgressReport(
        today: const {
          'kcal_in': 0,
          'protein_in': 0,
          'carbs_in': 0,
          'fat_in': 0,
          'water_ml': 0,
          'kcal_out': 0,
        },
        target: const {'kcal': 2000, 'water_ml': 2500},
        week: const [],
        streak: 0,
        weight: const {'start': null, 'current': null, 'delta': null},
        macros: const {'protein_g': 110, 'carbs_g': 260, 'fat_g': 60},
      );

  final Map<String, dynamic> today;
  final Map<String, dynamic> target;
  final List<Map<String, dynamic>> week;
  final int streak;
  final Map<String, dynamic> weight;
  final Map<String, dynamic> macros;

  double get kcalIn => (today['kcal_in'] as num?)?.toDouble() ?? 0;
  double get proteinIn => (today['protein_in'] as num?)?.toDouble() ?? 0;
  double get carbsIn => (today['carbs_in'] as num?)?.toDouble() ?? 0;
  double get fatIn => (today['fat_in'] as num?)?.toDouble() ?? 0;
  int get waterMl => (today['water_ml'] as num?)?.toInt() ?? 0;
  double get kcalOut => (today['kcal_out'] as num?)?.toDouble() ?? 0;

  double get kcalTarget => (target['kcal'] as num?)?.toDouble() ?? 2000;
  int get waterTarget => (target['water_ml'] as num?)?.toInt() ?? 2500;

  double get proteinGoal =>
      (macros['protein_g'] as num?)?.toDouble() ?? 110;
  double get carbsGoal => (macros['carbs_g'] as num?)?.toDouble() ?? 260;
  double get fatGoal => (macros['fat_g'] as num?)?.toDouble() ?? 60;
}

// ---------------------------------------------------------------------
//  FoodItem adapter — converts the comprehensive BD library into the
//  legacy FoodItem type expected by screens.
// ---------------------------------------------------------------------

List<FoodItem> _allFoods() {
  return [
    for (final f in bd.BdFoodLibrary.all)
      FoodItem(
        id: f.id,
        nameEn: f.nameEn,
        nameBn: f.nameBn,
        category: f.category,
        servingG: f.servingG,
        kcalPerServing: f.kcalPerServing,
        proteinG: f.proteinG,
        carbsG: f.carbsG,
        fatG: f.fatG,
        fiberG: f.fiberG,
      ),
  ];
}

// ---------------------------------------------------------------------
//  ApiService — Hive-backed CRUD per verified phone
// ---------------------------------------------------------------------

class ApiService {
  ApiService._();

  // ----- Helpers -----

  static String _phone() {
    final p = AuthService.instance.phone;
    return p ?? 'guest';
  }

  static int _seq = 0;

  static String _genId(String prefix) {
    _seq++;
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_$_seq';
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime _normalize(DateTime d) => DateTime(d.year, d.month, d.day);

  // ----- Profile -----

  static Future<UserProfile> ensureProfile() async {
    final phone = _phone();
    final box = await HiveStore.instance.boxAsync(phone, 'profile');
    final stored = box.get('user');
    final base = stored == null
        ? UserProfile(
            id: 'local_$phone',
            phone: phone,
            isPro: AuthService.instance.isSubscribed,
            dailyCalorieTarget: 2000,
          )
        : UserProfile.fromMap(Map<String, dynamic>.from(stored as Map));
    // Always refresh subscription state from AuthService.
    final synced = _rebuildFreshIsPro(base, AuthService.instance.isSubscribed);
    await box.put('user', synced.toMap());
    return synced;
  }

  static UserProfile _rebuildFreshIsPro(UserProfile p, bool isPro) {
    return UserProfile(
      id: p.id,
      phone: p.phone,
      name: p.name,
      email: p.email,
      gender: p.gender,
      dateOfBirth: p.dateOfBirth,
      heightCm: p.heightCm,
      weightKg: p.weightKg,
      activityLevel: p.activityLevel,
      goal: p.goal,
      targetWeightKg: p.targetWeightKg,
      dietPref: p.dietPref,
      bmr: p.bmr,
      tdee: p.tdee,
      dailyCalorieTarget: p.dailyCalorieTarget,
      isPro: isPro,
    );
  }

  static Future<UserProfile> updateProfile(
      Map<String, dynamic> fields) async {
    final current = await ensureProfile();
    UserProfile updated = current;
    if (fields.containsKey('name')) {
      updated = _rebuild(updated, name: fields['name']?.toString());
    }
    if (fields.containsKey('email')) {
      updated = _rebuild(updated, email: fields['email']?.toString());
    }
    if (fields.containsKey('gender')) {
      updated = _rebuild(updated, gender: fields['gender']?.toString());
    }
    if (fields.containsKey('date_of_birth')) {
      final v = fields['date_of_birth']?.toString();
      updated = _rebuild(updated,
          dateOfBirth: v == null ? null : DateTime.tryParse(v));
    }
    if (fields.containsKey('height_cm')) {
      updated = _rebuild(updated,
          heightCm: (fields['height_cm'] as num?)?.toDouble());
    }
    if (fields.containsKey('weight_kg')) {
      updated = _rebuild(updated,
          weightKg: (fields['weight_kg'] as num?)?.toDouble());
    }
    if (fields.containsKey('activity_level')) {
      updated =
          _rebuild(updated, activityLevel: fields['activity_level']?.toString());
    }
    if (fields.containsKey('goal')) {
      updated = _rebuild(updated, goal: fields['goal']?.toString());
    }
    if (fields.containsKey('target_weight_kg')) {
      updated = _rebuild(updated,
          targetWeightKg:
              (fields['target_weight_kg'] as num?)?.toDouble());
    }
    if (fields.containsKey('diet_pref')) {
      updated = _rebuild(updated, dietPref: fields['diet_pref']?.toString());
    }

    // Recompute BMR, TDEE, daily calorie target.
    final bmr = _bmrFromProfile(updated);
    final tdee = _tdeeFromProfile(updated, bmr);
    final kcalTarget = _dailyCalorieTarget(updated, tdee);
    updated =
        _rebuild(updated, bmr: bmr, tdee: tdee, dailyCalorieTarget: kcalTarget);

    await (await HiveStore.instance.boxAsync(updated.phone, 'profile'))
        .put('user', updated.toMap());
    return updated;
  }

  static UserProfile _rebuild(
    UserProfile p, {
    String? name,
    String? email,
    String? gender,
    DateTime? dateOfBirth,
    double? heightCm,
    double? weightKg,
    String? activityLevel,
    String? goal,
    double? targetWeightKg,
    String? dietPref,
    double? bmr,
    double? tdee,
    double? dailyCalorieTarget,
  }) {
    return UserProfile(
      id: p.id,
      phone: p.phone,
      name: name ?? p.name,
      email: email ?? p.email,
      gender: gender ?? p.gender,
      dateOfBirth: dateOfBirth ?? p.dateOfBirth,
      heightCm: heightCm ?? p.heightCm,
      weightKg: weightKg ?? p.weightKg,
      activityLevel: activityLevel ?? p.activityLevel,
      goal: goal ?? p.goal,
      targetWeightKg: targetWeightKg ?? p.targetWeightKg,
      dietPref: dietPref ?? p.dietPref,
      bmr: bmr ?? p.bmr,
      tdee: tdee ?? p.tdee,
      dailyCalorieTarget: dailyCalorieTarget ?? p.dailyCalorieTarget,
      isPro: p.isPro,
    );
  }

  static double? _bmrFromProfile(UserProfile p) {
    if (p.weightKg == null || p.heightCm == null || p.dateOfBirth == null) {
      return null;
    }
    final age = p.age;
    if (age == null) return null;
    final isMale = (p.gender ?? '').toLowerCase() == 'male';
    // Mifflin-St Jeor
    final base = 10 * p.weightKg! + 6.25 * p.heightCm! - 5 * age;
    return isMale ? base + 5 : base - 161;
  }

  static double? _tdeeFromProfile(UserProfile p, double? bmr) {
    if (bmr == null) return null;
    final factor = switch ((p.activityLevel ?? 'sedentary').toLowerCase()) {
      'very_active' => 1.725,
      'active' => 1.55,
      'moderate' => 1.375,
      'light' => 1.2,
      _ => 1.0,
    };
    return bmr * factor;
  }

  static double _dailyCalorieTarget(UserProfile p, double? tdee) {
    if (tdee == null) return 2000;
    switch ((p.goal ?? 'maintain').toLowerCase()) {
      case 'lose':
        return tdee - 500;
      case 'gain':
        return tdee + 500;
      default:
        return tdee;
    }
  }

  // ----- Foods -----

  static Future<List<FoodItem>> listFoods({String? category}) async {
    final all = _allFoods();
    final list = category == null
        ? List<FoodItem>.from(all)
        : all.where((f) => f.category == category).toList();
    list.sort((a, b) => a.nameEn.compareTo(b.nameEn));
    return list;
  }

  // ----- Meals -----

  static Future<List<MealEntry>> listMeals({
    required DateTime date,
    String? mealType,
  }) async {
    final phone = _phone();
    final box = await HiveStore.instance.boxAsync(phone, 'meals');
    final all = box.values
        .map((e) => MealEntry.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    final day = _normalize(date);
    return all.where((m) {
      if (!_sameDay(m.eatenOn, day)) return false;
      if (mealType != null && m.mealType != mealType) return false;
      return true;
    }).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  static Future<String> logMeal({
    required String foodId,
    required DateTime eatenOn,
    required String mealType,
    double servings = 1.0,
  }) async {
    final phone = _phone();
    final food = _allFoods().firstWhere(
      (f) => f.id == foodId,
      orElse: () => throw StateError('Unknown food: $foodId'),
    );
    final entry = MealEntry(
      id: _genId('meal'),
      foodId: foodId,
      foodName: food.nameEn,
      mealType: mealType,
      servings: servings,
      eatenOn: eatenOn,
      kcalTotal: food.kcalPerServing * servings,
      proteinTotal: food.proteinG * servings,
      carbsTotal: food.carbsG * servings,
      fatTotal: food.fatG * servings,
      createdAt: DateTime.now(),
    );
    await (await HiveStore.instance.boxAsync(phone, 'meals'))
        .put(entry.id, entry.toMap());
    return entry.id;
  }

  static Future<void> deleteMeal(String id) async {
    final phone = _phone();
    await (await HiveStore.instance.boxAsync(phone, 'meals')).delete(id);
  }

  // ----- Water -----

  static Future<WaterLog> getWater(DateTime date) async {
    final phone = _phone();
    final box = await HiveStore.instance.boxAsync(phone, 'water');
    final entries = box.values
        .map((e) => WaterEntry.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList()
      ..sort((a, b) => a.loggedOn.compareTo(b.loggedOn));
    final day = _normalize(date);
    final dayEntries =
        entries.where((e) => _sameDay(e.loggedOn, day)).toList();
    final total = dayEntries.fold<int>(0, (s, e) => s + e.amountMl);
    final profile = await ensureProfile();
    final target = profile.weightKg == null
        ? 2500
        : (profile.weightKg! * 35).round().clamp(2000, 4000);
    return WaterLog(
      date: date,
      totalMl: total,
      targetMl: target,
      entries: dayEntries,
    );
  }

  static Future<void> addWater(int amountMl) async {
    final phone = _phone();
    final now = DateTime.now();
    final entry = WaterEntry(
      id: _genId('water'),
      amountMl: amountMl,
      loggedOn: now,
      loggedAt: now,
    );
    await (await HiveStore.instance.boxAsync(phone, 'water'))
        .put(entry.id, entry.toMap());
  }

  static Future<void> deleteWater(String id) async {
    final phone = _phone();
    await (await HiveStore.instance.boxAsync(phone, 'water')).delete(id);
  }

  // ----- Plan -----

  static Future<DailyPlan> getPlan({DateTime? date}) async {
    final phone = _phone();
    final box = await HiveStore.instance.boxAsync(phone, 'plan');
    final stored = box.get('current');
    if (stored != null) {
      return DailyPlan.fromMap(Map<String, dynamic>.from(stored as Map));
    }
    // Default plan derived from profile.
    final profile = await ensureProfile();
    final kcal = profile.dailyCalorieTarget ?? 2000;
    final water = profile.weightKg == null
        ? 2500
        : (profile.weightKg! * 35).round().clamp(2000, 4000);
    return DailyPlan(
      planDate: date ?? DateTime.now(),
      kcalTarget: kcal.toDouble(),
      waterMl: water,
    );
  }

  static Future<void> savePlan({
    required DateTime planDate,
    required double kcalTarget,
    required int waterMl,
    String? notes,
  }) async {
    final phone = _phone();
    final p = DailyPlan(
      planDate: planDate,
      kcalTarget: kcalTarget,
      waterMl: waterMl,
      notes: notes,
    );
    await (await HiveStore.instance.boxAsync(phone, 'plan'))
        .put('current', p.toMap());
  }

  // ----- Progress -----

  static Future<ProgressReport> getProgress() async {
    final phone = _phone();
    final today = DateTime.now();
    final plan = await getPlan(date: today);
    final water = await getWater(today);
    final mealsToday = await listMeals(date: today);

    double kcalIn = 0, pIn = 0, cIn = 0, fIn = 0;
    for (final m in mealsToday) {
      kcalIn += m.kcalTotal;
      pIn += m.proteinTotal;
      cIn += m.carbsTotal;
      fIn += m.fatTotal;
    }

    final week = await _buildWeek(phone, today);

    final profile = await ensureProfile();
    final streak = await _streak(phone);

    final start = await _firstWeight(phone);
    final current = await _lastWeight(phone) ?? profile.weightKg;
    final delta = (start != null && current != null) ? current - start : null;

    final kcalTarget = plan.kcalTarget;
    final waterTarget = plan.waterMl;
    final proteinGoal = (kcalTarget * 0.25 / 4);
    final carbsGoal = (kcalTarget * 0.50 / 4);
    final fatGoal = (kcalTarget * 0.25 / 9);

    return ProgressReport(
      today: {
        'kcal_in': kcalIn,
        'protein_in': pIn,
        'carbs_in': cIn,
        'fat_in': fIn,
        'water_ml': water.totalMl,
        'kcal_out': 0.0,
      },
      target: {
        'kcal': kcalTarget,
        'water_ml': waterTarget,
      },
      week: week,
      streak: streak,
      weight: {
        'start': start,
        'current': current,
        'delta': delta,
      },
      macros: {
        'protein_g': proteinGoal,
        'carbs_g': carbsGoal,
        'fat_g': fatGoal,
      },
    );
  }

  static Future<List<Map<String, dynamic>>> _buildWeek(
      String phone, DateTime today) async {
    final box = await HiveStore.instance.boxAsync(phone, 'meals');
    final meals = box.values
        .map((e) => MealEntry.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    final result = <Map<String, dynamic>>[];
    for (int i = 6; i >= 0; i--) {
      final d = today.subtract(Duration(days: i));
      final day = _normalize(d);
      final kcal = meals
          .where((m) => _sameDay(m.eatenOn, day))
          .fold<double>(0, (s, m) => s + m.kcalTotal);
      result.add({
        'date':
            '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
        'kcal_in': kcal,
      });
    }
    return result;
  }

  static Future<int> _streak(String phone) async {
    final box = await HiveStore.instance.boxAsync(phone, 'meals');
    final meals = box.values
        .map((e) => MealEntry.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    if (meals.isEmpty) return 0;
    final today = _normalize(DateTime.now());
    int streak = 0;
    for (int i = 0; i < 30; i++) {
      final day = today.subtract(Duration(days: i));
      final has = meals.any((m) => _sameDay(m.eatenOn, day));
      if (has) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  static Future<double?> _firstWeight(String phone) async {
    final box = await HiveStore.instance.boxAsync(phone, 'weight');
    if (box.isEmpty) return null;
    final first = box.values.first;
    return ((first) as Map)['weight_kg'] == null
        ? null
        : ((first)['weight_kg'] as num?)?.toDouble();
  }

  static Future<double?> _lastWeight(String phone) async {
    final box = await HiveStore.instance.boxAsync(phone, 'weight');
    if (box.isEmpty) return null;
    final last = box.values.last;
    return ((last) as Map)['weight_kg'] == null
        ? null
        : ((last)['weight_kg'] as num?)?.toDouble();
  }

  // ----- Activity -----

  static Future<void> logActivity({
    required String activity,
    required int durationMin,
    double? kcalBurned,
  }) async {
    // No-op in offline mode.
  }

  // ----- Weight -----

  static Future<void> logWeight(double kg, {DateTime? measuredOn}) async {
    final phone = _phone();
    final today = _normalize(measuredOn ?? DateTime.now());
    final box = await HiveStore.instance.boxAsync(phone, 'weight');
    final entry = {
      'measured_on':
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}',
      'weight_kg': kg,
      'logged_at': DateTime.now().toIso8601String(),
    };
    await box.add(entry);

    // Mirror into profile so the stat tile + progress card update.
    final p = await ensureProfile();
    final updated = _rebuild(p, weightKg: kg);
    await (await HiveStore.instance.boxAsync(phone, 'profile'))
        .put('user', updated.toMap());
  }
}

// Note: Hive is not directly referenced in this file; HiveStore wraps
// all box access.
