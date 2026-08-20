/// Clinical profile collected during onboarding.
/// Field set mirrors `public.user_profiles` in the Supabase schema.
class UserProfile {
  // Identity (set on signup, editable later)
  final String? fullName;
  final String? mobile;

  final int age;
  final String sex; // male / female / other
  final double weightKg;
  final double heightCm;

  final double? fastingGlucoseMmol;
  final double? postMealGlucoseMmol;
  final double? randomGlucoseMmol;
  final double? hba1cPercent;

  final bool onInsulin;
  final String? medication;

  final int? systolicBp;
  final int? diastolicBp;

  final bool hasCkd;
  final int? ckdStage;
  final bool hasHeartDisease;
  final bool hasAnemia;
  final String? otherConditions;

  final String activityLevel; // low / moderate / high
  final String mealSizePref; // small / medium / large
  final String foodPreference; // omnivore / vegetarian / fish_only / no_beef

  /// Optional photo URL (Supabase Storage `profile` bucket, signed).
  final String? avatarUrl;

  /// Number of times this user has uploaded a profile photo. Capped
  /// at 2 — see supabasesql/21_profile_photos.sql.
  final int photoUploadCount;

  UserProfile({
    this.fullName,
    this.mobile,
    required this.age,
    required this.sex,
    required this.weightKg,
    required this.heightCm,
    this.fastingGlucoseMmol,
    this.postMealGlucoseMmol,
    this.randomGlucoseMmol,
    this.hba1cPercent,
    this.onInsulin = false,
    this.medication,
    this.systolicBp,
    this.diastolicBp,
    this.hasCkd = false,
    this.ckdStage,
    this.hasHeartDisease = false,
    this.hasAnemia = false,
    this.otherConditions,
    this.activityLevel = 'low',
    this.mealSizePref = 'medium',
    this.foodPreference = 'omnivore',
    this.avatarUrl,
    this.photoUploadCount = 0,
  });

  double get bmi => weightKg / ((heightCm / 100) * (heightCm / 100));

  Map<String, dynamic> toSupabaseRow(String userId) => {
        'user_id': userId,
        'full_name': fullName,
        'mobile': mobile,
        'age': age,
        'sex': sex,
        'weight_kg': weightKg,
        'height_cm': heightCm,
        'fasting_glucose_mmol': fastingGlucoseMmol,
        'post_meal_glucose_mmol': postMealGlucoseMmol,
        'random_glucose_mmol': randomGlucoseMmol,
        'hba1c_percent': hba1cPercent,
        'on_insulin': onInsulin,
        'medication': medication,
        'systolic_bp': systolicBp,
        'diastolic_bp': diastolicBp,
        'has_ckd': hasCkd,
        'ckd_stage': ckdStage,
        'has_heart_disease': hasHeartDisease,
        'has_anemia': hasAnemia,
        'other_conditions': otherConditions,
        'activity_level': activityLevel,
        'meal_size_pref': mealSizePref,
        'food_preference': foodPreference,
        'avatar_url': avatarUrl,
        'photo_upload_count': photoUploadCount,
      };

  /// Returns a copy with the given fields replaced. Useful in tests
  /// and inline-edit flows (e.g. profile screen) that need to change
  /// one or two clinical values without rebuilding the whole object.
  UserProfile copyWith({
    String? fullName,
    String? mobile,
    int? age,
    String? sex,
    double? weightKg,
    double? heightCm,
    double? fastingGlucoseMmol,
    double? postMealGlucoseMmol,
    double? randomGlucoseMmol,
    double? hba1cPercent,
    bool? onInsulin,
    String? medication,
    int? systolicBp,
    int? diastolicBp,
    bool? hasCkd,
    int? ckdStage,
    bool? hasHeartDisease,
    bool? hasAnemia,
    String? otherConditions,
    String? activityLevel,
    String? mealSizePref,
    String? foodPreference,
    String? avatarUrl,
    int? photoUploadCount,
  }) {
    return UserProfile(
      fullName: fullName ?? this.fullName,
      mobile: mobile ?? this.mobile,
      age: age ?? this.age,
      sex: sex ?? this.sex,
      weightKg: weightKg ?? this.weightKg,
      heightCm: heightCm ?? this.heightCm,
      fastingGlucoseMmol:
          fastingGlucoseMmol ?? this.fastingGlucoseMmol,
      postMealGlucoseMmol:
          postMealGlucoseMmol ?? this.postMealGlucoseMmol,
      randomGlucoseMmol:
          randomGlucoseMmol ?? this.randomGlucoseMmol,
      hba1cPercent: hba1cPercent ?? this.hba1cPercent,
      onInsulin: onInsulin ?? this.onInsulin,
      medication: medication ?? this.medication,
      systolicBp: systolicBp ?? this.systolicBp,
      diastolicBp: diastolicBp ?? this.diastolicBp,
      hasCkd: hasCkd ?? this.hasCkd,
      ckdStage: ckdStage ?? this.ckdStage,
      hasHeartDisease: hasHeartDisease ?? this.hasHeartDisease,
      hasAnemia: hasAnemia ?? this.hasAnemia,
      otherConditions: otherConditions ?? this.otherConditions,
      activityLevel: activityLevel ?? this.activityLevel,
      mealSizePref: mealSizePref ?? this.mealSizePref,
      foodPreference: foodPreference ?? this.foodPreference,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      photoUploadCount: photoUploadCount ?? this.photoUploadCount,
    );
  }
}
