import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io' as io;
import '../models/user_profile.dart';
import '../models/meal_item.dart';
import '../models/user_meal_plan.dart';
import '../models/medicine.dart';
import '../models/dashboard.dart';
import '../models/water_analytics.dart';
import '../models/workout.dart';

/// Thin wrapper around the Supabase client used by Amar Diet.
///
/// Setup:
///   1. Create a Supabase project.
///   2. Run the SQL files in `supabasesql/` in order (01 → 14).
///   3. Copy `.env.example` to `.env` and fill in SUPABASE_URL + SUPABASE_ANON_KEY.
///   4. Call SupabaseService.init() once in main().

/// Thrown when a caller accesses `SupabaseService.client` before
/// `SupabaseService.init()` has completed (or after a hot-restart
/// wiped the static field). Distinct from Flutter's generic
/// [StateError] so RPC wrappers can recognize it and surface a
/// friendly Bangla message instead of the raw developer-facing
/// "Bad state" overlay that Flutter paints red.
class SupabaseNotInitializedError extends Error {
  SupabaseNotInitializedError();
  @override
  String toString() =>
      'SupabaseNotInitializedError: SupabaseService.init() has not been '
      'awaited yet (or the static field was wiped by a hot-restart).';
}

class SupabaseService {
  SupabaseService();

  /// Reason the SDK could not be initialised (null on success).
  /// Surfaced in the UI as a polite Bangla error screen instead of a
  /// silent white-screen-of-death.
  static String? initError;

  static SupabaseClient? _client;
  static SupabaseClient get client {
    final c = _client;
    if (c != null) return c;
    // Hot-restart race: `init()` ran fine in the previous isolate and
    // `Supabase.initialize()` already established the singleton — but
    // our static `_client` field got wiped. Lazily re-attach so the
    // RPC wrappers below never see a not-initialized state.
    try {
      final live = Supabase.instance.client;
      _client = live;
      return live;
    } catch (_) {
      // Last resort: never let the getter throw. Return a stub that
      // fails loudly on every method call with a typed error. This
      // way the UI can catch the error and show a Bangla hint instead
      // of Flutter painting a red `ErrorWidget` overlay.
      return _NotReadyClient();
    }
  }

  /// True once `init()` has successfully set [_client] (and hasn't been
  /// wiped by a hot-restart since). Use this in async code paths that
  /// can simply bail out and surface a polite message instead of
  /// throwing through the `client` getter. Also returns true when the
  /// Supabase singleton is alive in the isolate but our static mirror
  /// is null (hot-restart recovery).
  static bool get isInitialized {
    if (_client != null) return true;
    try {
      // ignore: unnecessary_statements
      Supabase.instance.client; // throws if singleton missing
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Initialise the Supabase client.
  ///
  /// Never throws — if `.env` is missing or the keys are blank, we record
  /// a human-readable Bangla message in [initError] and return. Callers
  /// should check [initError] (or the bool return) before using [client].
  static Future<bool> init() async {
    String? url;
    String? anonKey;
    try {
      await dotenv.load(fileName: '.env');
      url = dotenv.env['SUPABASE_URL']?.trim();
      anonKey = dotenv.env['SUPABASE_ANON_KEY']?.trim();
    } catch (e) {
      initError =
          '.env ফাইল পাওয়া যায়নি — প্রজেক্টের রুটে .env.example থেকে .env কপি করুন।';
      return false;
    }
    final urlMissing = url == null || url.isEmpty;
    final keyMissing = anonKey == null || anonKey.isEmpty;
    final urlIsPlaceholder = url != null &&
        (url.toLowerCase().contains('your-project-ref') ||
            url == 'https://.supabase.co');
    final keyIsPlaceholder = anonKey != null &&
        (anonKey.toLowerCase().contains('your-anon-key') ||
            anonKey.startsWith('sb_publishable_'));
    if (urlMissing || keyMissing || urlIsPlaceholder || keyIsPlaceholder) {
      if (urlIsPlaceholder || keyIsPlaceholder) {
        initError =
            'SUPABASE_URL বা SUPABASE_ANON_KEY ভুল মানে সেট আছে — প্রজেক্টের "Project Settings → API" থেকে আসল URL (https://<ref>.supabase.co) এবং anon JWT বসান।';
      } else {
        initError =
            '.env ফাইলে সঠিক SUPABASE_URL ও SUPABASE_ANON_KEY সেট করা হয়নি — .env.example দেখুন এবং আপনার Supabase প্রজেক্টের তথ্য দিন।';
      }
      return false;
    }
    // URL must look like https://<ref>.supabase.co — anything else is almost
    // certainly a paste mistake that produces the "url not found" symptom.
    final urlPattern =
        RegExp(r'^https://[a-z0-9-]+\.supabase\.co/?$', caseSensitive: false);
    if (!urlPattern.hasMatch(url)) {
      initError =
          'SUPABASE_URL ফরম্যাট ভুল — "https://<your-ref>.supabase.co" ফরম্যাটে হতে হবে (আপনার বর্তমান মান: "$url")।';
      return false;
    }
    if (anonKey.startsWith('sb_publishable_')) {
      initError =
          'SUPABASE_ANON_KEY-এ sb_publishable_* কী বসানো হয়েছে — এটি publishable key, anon key নয়। "Project Settings → API" থেকে anon JWT কপি করুন।';
      return false;
    }
    try {
      await Supabase.initialize(url: url, anonKey: anonKey);
      _client = Supabase.instance.client;
      return true;
    } catch (e) {
      initError =
          'Supabase সংযোগ ব্যর্থ: $e — URL ও কী যাচাই করুন অথবা ইন্টারনেট সংযোগ দেখুন।';
      return false;
    }
  }

  static User? get currentUser => _client?.auth.currentUser;

  static Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    required String mobile,
  }) {
    return client.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': fullName.trim(),
        'mobile': mobile.trim(),
      },
    );
  }

  static Future<AuthResponse> signIn(String email, String password) {
    return client.auth.signInWithPassword(email: email, password: password);
  }

  static Future<void> signOut() => client.auth.signOut();

  /// Updates the auth user's user_metadata (used to edit name/mobile after signup).
  static Future<void> updateAccountMeta(
      {String? fullName, String? mobile}) async {
    final user = currentUser;
    if (user == null) throw Exception('No authenticated user.');
    final meta = Map<String, dynamic>.from(user.userMetadata ?? {});
    if (fullName != null) meta['full_name'] = fullName.trim();
    if (mobile != null) meta['mobile'] = mobile.trim();
    await client.auth.updateUser(UserAttributes(data: meta));
  }

  // ----------- PROFILE -----------

  /// Reads the user's profile row. Returns null if they haven't onboarded yet.
  static Future<UserProfile?> fetchProfile() async {
    final userId = currentUser?.id;
    if (userId == null) return null;
    final resp = await client
        .from('user_profiles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (resp == null) return null;
    final m = Map<String, dynamic>.from(resp);
    final meta = currentUser?.userMetadata ?? const {};
    return UserProfile(
      fullName: (m['full_name'] as String?) ?? (meta['full_name'] as String?),
      mobile: (m['mobile'] as String?) ?? (meta['mobile'] as String?),
      age: (m['age'] ?? 0) as int,
      sex: (m['sex'] ?? 'male') as String,
      weightKg: ((m['weight_kg'] ?? 0) as num).toDouble(),
      heightCm: ((m['height_cm'] ?? 0) as num).toDouble(),
      fastingGlucoseMmol: m['fasting_glucose_mmol'] != null
          ? ((m['fasting_glucose_mmol']) as num).toDouble()
          : null,
      postMealGlucoseMmol: m['post_meal_glucose_mmol'] != null
          ? ((m['post_meal_glucose_mmol']) as num).toDouble()
          : null,
      randomGlucoseMmol: m['random_glucose_mmol'] != null
          ? ((m['random_glucose_mmol']) as num).toDouble()
          : null,
      hba1cPercent: m['hba1c_percent'] != null
          ? ((m['hba1c_percent']) as num).toDouble()
          : null,
      onInsulin: (m['on_insulin'] ?? false) as bool,
      medication: m['medication'] as String?,
      systolicBp: m['systolic_bp'] as int?,
      diastolicBp: m['diastolic_bp'] as int?,
      hasCkd: (m['has_ckd'] ?? false) as bool,
      ckdStage: m['ckd_stage'] as int?,
      hasHeartDisease: (m['has_heart_disease'] ?? false) as bool,
      hasAnemia: (m['has_anemia'] ?? false) as bool,
      otherConditions: m['other_conditions'] as String?,
      activityLevel: (m['activity_level'] ?? 'low') as String,
      mealSizePref: (m['meal_size_pref'] ?? 'medium') as String,
      foodPreference: (m['food_preference'] ?? 'omnivore') as String,
      avatarUrl: (m['avatar_url'] as String?) ?? (meta['avatar_url'] as String?),
      photoUploadCount: ((m['photo_upload_count'] ?? 0) as num).toInt(),
    );
  }

  /// Upserts the user's clinical profile (public.user_profiles).
  ///
  /// We pass `onConflict: 'user_id'` so Postgres knows the merge target and
  /// doesn't silently fail on update. Without it, an upsert of an existing
  /// row can throw a 400 that bubbles up and crashes the app.
  static Future<void> saveProfile(UserProfile profile) async {
    final userId = currentUser?.id;
    if (userId == null) {
      throw StateError(
          'No authenticated user — sign in before saving a profile.');
    }
    await client.from('user_profiles').upsert(
          profile.toSupabaseRow(userId),
          onConflict: 'user_id',
        );
  }

  // ----------- PROFILE PHOTO -----------
  //
  // The `profile` Storage bucket is private. Each user is allowed to
  // upload at most 2 photos in total — the limit is enforced both
  // client-side (here) and server-side (the bump_photo_upload_count
  // RPC defined in 21_profile_photos.sql).

  /// Maximum number of profile photo uploads allowed per user.
  static const int maxProfilePhotoUploads = 2;

  /// Uploads [bytes] as the user's profile photo, replaces any
  /// previous photo, and persists the signed URL on
  /// user_profiles.avatar_url. Throws [StateError] if the user is
  /// unauthenticated, has already hit the upload cap, or if the
  /// server-side counter RPC refuses the upload.
  static Future<String> uploadProfilePhoto({
    required Uint8List bytes,
    required String contentType,
    String? originalFileName,
  }) async {
    final userId = currentUser?.id;
    if (userId == null) {
      throw StateError('No authenticated user.');
    }

    // 1. Find the current count (client-side gate, server still enforces).
    final profile = await fetchProfile();
    final used = profile?.photoUploadCount ?? 0;
    if (used >= maxProfilePhotoUploads) {
      throw StateError(
        'Profile photo upload limit reached (max $maxProfilePhotoUploads).',
      );
    }

    // 2. Upload to the private `profile` bucket under `<uid>/<ts>.<ext>`.
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ext = _guessPhotoExtension(originalFileName, contentType);
    final objectPath = '$userId/$ts$ext';

    await client.storage.from('profile').uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: true,
          ),
        );

    // 3. Persist the path on the profile row and auth metadata.
    await client
        .from('user_profiles')
        .update({'avatar_url': objectPath}).eq('user_id', userId);
    
    try {
      await client.auth.updateUser(UserAttributes(
        data: {'avatar_url': objectPath},
      ));
    } catch (_) {
      // Best-effort identity sync.
    }

    // 4. Bump the server-side counter (will rollback + throw if the
    //    user has already hit the cap).
    final newCount = await client.rpc('bump_photo_upload_count');

    // 5. Return a signed URL the caller can display immediately.
    final signed = await getProfilePhotoUrl(objectPath);
    if (signed.isNotEmpty) {
      final joiner = signed.contains('?') ? '&' : '?';
      return '$signed${joiner}_v=$newCount';
    }
    return signed;
  }

  /// Returns a freshly signed URL for an avatar stored at [path] in
  /// the `profile` bucket, or the empty string if the path is null,
  /// blank, or the signed-URL RPC fails.
  static Future<String> getProfilePhotoUrl(String? path) async {
    if (path == null || path.isEmpty) return '';
    try {
      // Use createSignedUrl for private buckets.
      final url = await client.storage
          .from('profile')
          .createSignedUrl(path, 60 * 60 * 24 * 7); // 7 days
      return url;
    } catch (e) {
      debugPrint('SupabaseService.getProfilePhotoUrl error: $e');
      return '';
    }
  }

  /// Best-effort file extension guess from the original filename or
  /// the MIME type the picker reports.
  static String _guessPhotoExtension(String? filename, String contentType) {
    final f = (filename ?? '').toLowerCase();
    for (final ext in ['.jpg', '.jpeg', '.png', '.webp', '.gif']) {
      if (f.endsWith(ext)) return ext;
    }
    final ct = contentType.toLowerCase();
    if (ct.contains('jpeg') || ct.contains('jpg')) return '.jpg';
    if (ct.contains('png')) return '.png';
    if (ct.contains('webp')) return '.webp';
    if (ct.contains('gif')) return '.gif';
    return '.jpg';
  }

  // ----------- DAY PLAN + LOG -----------

  /// Calls `get_daily_recommendation(user_id, day)` server-side.
  static Future<Map<String, dynamic>> getDailyRecommendation(int day) async {
    final userId = currentUser?.id;
    if (userId == null) throw StateError('No authenticated user.');
    final result = await client.rpc('get_daily_recommendation', params: {
      'p_user_id': userId,
      'p_day': day,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  // ─────────────── v2 RPC wrappers (supabasesql/23_*, 24_*) ───────────────
  // These power PlanService. Each falls back gracefully when v2 SQL
  // hasn't been deployed yet — see PlanService.

  /// `classify_user_v2(p_user_id)` — full clinical classification JSON.
  static Future<Map<String, dynamic>> classifyUserV2() async {
    final userId = currentUser?.id;
    if (userId == null) throw StateError('No authenticated user.');
    final result = await client.rpc('classify_user_v2', params: {
      'p_user_id': userId,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  /// `get_day_plan_with_fallback(p_user_id, p_plan_date, p_plan_day)`.
  /// Reads the cache, falls back to dynamic generation if missing.
  static Future<Map<String, dynamic>> getDayPlanWithFallback(
    int day, {
    DateTime? planDate,
  }) async {
    final userId = currentUser?.id;
    if (userId == null) throw StateError('No authenticated user.');
    final date = _dateOnly(planDate ?? DateTime.now());
    final result = await client.rpc('get_day_plan_with_fallback', params: {
      'p_user_id': userId,
      'p_plan_date': date,
      'p_plan_day': day,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  /// `food_alternatives_v2(p_user_id, p_food_id, p_limit)` — alternatives
  /// filtered through the user's classification.
  static Future<List<MealItem>> getAlternativesV2(String foodId,
      {int limit = 4}) async {
    final userId = currentUser?.id;
    if (userId == null) throw StateError('No authenticated user.');
    final result = await client.rpc('food_alternatives_v2', params: {
      'p_user_id': userId,
      'p_food_id': foodId,
      'p_limit': limit,
    });
    final list = (result as List?) ?? [];
    return list
        .map((e) => MealItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// `ensure_upcoming_plans(p_user_id, p_from_date, p_days)` — pre-bakes
  /// the cache starting at [fromDate] for [days] days. Fire-and-forget.
  static Future<void> ensureUpcomingPlans({
    int days = 7,
    DateTime? fromDate,
  }) async {
    final userId = currentUser?.id;
    if (userId == null) throw StateError('No authenticated user.');
    await client.rpc('ensure_upcoming_plans', params: {
      'p_user_id': userId,
      'p_from_date': _dateOnly(fromDate ?? DateTime.now()),
      'p_days': days,
    });
  }

  /// `invalidate_plan_cache(p_user_id, p_from_date)` — wipe cache rows
  /// for [fromDate] onward. Call after a profile update so the next
  /// load uses the new classification.
  static Future<void> invalidatePlanCache({DateTime? fromDate}) async {
    final userId = currentUser?.id;
    if (userId == null) throw StateError('No authenticated user.');
    await client.rpc('invalidate_plan_cache', params: {
      'p_user_id': userId,
      if (fromDate != null) 'p_from_date': _dateOnly(fromDate),
    });
  }

  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Legacy `classify_user(p_user_id)` — still works as a shim.
  static Future<Map<String, dynamic>> classifyUser() async {
    final userId = currentUser?.id;
    if (userId == null) throw StateError('No authenticated user.');
    final result = await client.rpc('classify_user', params: {
      'p_user_id': userId,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  /// Calls `food_alternatives_for(food_id, limit)` server-side.
  static Future<List<MealItem>> getAlternatives(String foodId,
      {int limit = 4}) async {
    final result = await client.rpc('food_alternatives_for', params: {
      'p_food_id': foodId,
      'p_limit': limit,
    });
    final list = (result as List?) ?? [];
    return list
        .map((e) => MealItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Calls `record_meal_intake(...)` — returns the log id.
  static Future<String> logMeal({
    required String mealSlot,
    required String? foodId,
    required String foodNameBn,
    required String status, // eaten | swap | off_plan
    required String impact, // good | neutral | bad
    int? planDay,
    String? reason,
    String? notes,
  }) async {
    final id = await client.rpc('record_meal_intake', params: {
      'p_meal_slot': mealSlot,
      'p_food_id': foodId,
      'p_food_name_bn': foodNameBn,
      'p_status': status,
      'p_impact': impact,
      'p_plan_day': planDay,
      'p_reason': reason,
      'p_notes': notes,
    });
    return id.toString();
  }

  static Future<void> hideMeal(String id) async {
    await client.rpc('hide_meal_intake', params: {'p_id': id});
  }

  /// Calls `get_daily_log(date, plan_day)` — returns the meal log for one
  /// day. When [planDay] (1..30) is supplied, only entries logged against
  /// that rotation day are returned. Pass [date] to override the calendar
  /// date (defaults to today in Asia/Dhaka on the server).
  static Future<List<MealLogEntry>> getDailyLog({
    DateTime? date,
    int? planDay,
  }) async {
    final params = <String, dynamic>{};
    if (date != null) {
      params['p_date'] = date.toIso8601String().substring(0, 10);
    }
    if (planDay != null) {
      params['p_plan_day'] = planDay;
    }
    final result = await client.rpc('get_daily_log', params: params);
    final m = Map<String, dynamic>.from(result as Map);
    final items = (m['items'] as List?) ?? [];
    return items
        .map((e) => MealLogEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Calls `get_dashboard_summary(days)` — streak, totals, daily breakdown.
  static Future<DashboardSummary> getDashboardSummary({int days = 7}) async {
    final result = await client.rpc('get_dashboard_summary', params: {
      'p_days': days,
    });
    return DashboardSummary.fromJson(Map<String, dynamic>.from(result as Map));
  }

  static Future<List<DailyNutrition>> getWeeklyNutrition({int days = 7}) async {
    try {
      final result = await client.rpc('get_weekly_nutrition', params: {
        'p_days': days,
      });

      if (result is List) {
        return result
            .map((e) =>
                DailyNutrition.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }

      if (result is Map) {
        // Fallback: If the RPC returns a summary instead of a list,
        // wrap it in a list so the UI doesn't crash.
        final m = Map<String, dynamic>.from(result);
        return [
          DailyNutrition(
            date: DateTime.now(),
            calories: (m['calories'] ?? 0) as int,
            carbs: (m['carb_g'] ?? 0).toInt(),
            protein: (m['protein_g'] ?? 0).toInt(),
            fat: (m['fat_g'] ?? 0).toInt(),
          )
        ];
      }

      return [];
    } catch (e, st) {
      debugPrint('getWeeklyNutrition error: $e\n$st');
      return [];
    }
  }

  /// Returns the workout log row for a single calendar day, or a zeroed row
  /// if no session was recorded for that date. Falls back to an empty row
  /// when the underlying RPC is unavailable.
  static Future<WorkoutLogRow> getWorkoutLog(DateTime d) async {
    final day = DateTime(d.year, d.month, d.day);
    try {
      final list = await getWorkoutLogs(days: 7);
      for (final row in list) {
        final rd = DateTime(row.day.year, row.day.month, row.day.day);
        if (rd == day) return row;
      }
      return WorkoutLogRow(day: day, total: 0, completed: 0);
    } catch (_) {
      return WorkoutLogRow(day: day, total: 0, completed: 0);
    }
  }

  // ----------- MEDICINES -----------
  // CRUD RPCs for the per-user medicine catalogue plus the
  // daily-dose timeline RPC. Same shape as the meal-plan section
  // above — JSON-returning, security-definer, auth.uid()-gated.
  // See `supabasesql/12_medicine.sql`.

  /// Lists every medicine (active + archived) for the current user.
  static Future<List<Medicine>> listMedicines() async {
    final result = await client.rpc('list_medicines');
    final list = (result as List?) ?? [];
    return list
        .map((e) => Medicine.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Creates a new medicine. Returns the new id. The [schedule]
  /// argument is the raw client-side list; the server re-classifies
  /// every entry into a bucket so historical readings stay consistent.
  static Future<String> createMedicine({
    required String nameBn,
    String? nameEn,
    String form = 'tablet',
    String? strength,
    double doseAmount = 1,
    String doseUnit = 'unit',
    String mealRelation = 'any',
    required List<MedicineScheduleSlot> schedule,
    DateTime? startDate,
    DateTime? endDate,
    String? color,
    String? notes,
  }) async {
    final id = await client.rpc('create_medicine', params: {
      'p_name_bn': nameBn,
      if (nameEn != null && nameEn.isNotEmpty) 'p_name_en': nameEn,
      'p_form': form,
      if (strength != null && strength.isNotEmpty) 'p_strength': strength,
      'p_dose_amount': doseAmount,
      'p_dose_unit': doseUnit,
      'p_meal_relation': mealRelation,
      'p_schedule': schedule
          .map((s) => {for (final e in s.toJson().entries) e.key: e.value})
          .toList(),
      if (startDate != null) 'p_start_date': _dateOnly(startDate),
      if (endDate != null) 'p_end_date': _dateOnly(endDate),
      if (color != null && color.isNotEmpty) 'p_color': color,
      if (notes != null && notes.isNotEmpty) 'p_notes': notes,
    });
    return id.toString();
  }

  /// Updates an existing medicine. Mirrors the meal-plan pattern —
  /// pass `null` to leave a column unchanged, or use the matching
  /// `clear*` flag to force it to null. Pass a new [schedule] list
  /// to replace the entire schedule.
  static Future<void> updateMedicine({
    required String id,
    String? nameBn,
    String? nameEn,
    bool clearNameEn = false,
    String? form,
    String? strength,
    bool clearStrength = false,
    double? doseAmount,
    String? doseUnit,
    String? mealRelation,
    List<MedicineScheduleSlot>? schedule,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
    String? color,
    bool clearColor = false,
    String? notes,
    bool clearNotes = false,
    bool? isActive,
  }) async {
    final params = <String, dynamic>{
      'p_id': id,
      if (nameBn != null && nameBn.isNotEmpty) 'p_name_bn': nameBn,
      if (clearNameEn) 'p_name_en': '',
      if (nameEn != null && !clearNameEn && nameEn.isNotEmpty)
        'p_name_en': nameEn,
      if (form != null) 'p_form': form,
      if (clearStrength) 'p_strength': '',
      if (strength != null && !clearStrength && strength.isNotEmpty)
        'p_strength': strength,
      if (doseAmount != null) 'p_dose_amount': doseAmount,
      if (doseUnit != null && doseUnit.isNotEmpty) 'p_dose_unit': doseUnit,
      if (mealRelation != null) 'p_meal_relation': mealRelation,
      if (schedule != null)
        'p_schedule': schedule
            .map((s) => {for (final e in s.toJson().entries) e.key: e.value})
            .toList(),
      if (startDate != null) 'p_start_date': _dateOnly(startDate),
      if (endDate != null) 'p_end_date': _dateOnly(endDate),
      if (clearEndDate) 'p_clear_end_date': true,
      if (clearColor) 'p_color': '',
      if (color != null && !clearColor && color.isNotEmpty) 'p_color': color,
      if (clearNotes) 'p_notes': '',
      if (notes != null && !clearNotes && notes.isNotEmpty) 'p_notes': notes,
      if (isActive != null) 'p_is_active': isActive,
    };
    await client.rpc('update_medicine', params: params);
  }

  /// Hard-deletes a medicine (cascades to its dose log).
  static Future<void> deleteMedicine(String id) async {
    await client.rpc('delete_medicine', params: {'p_id': id});
  }

  /// Returns the day's dose timeline (pending + taken + skipped +
  /// missed). Defaults to today in Asia/Dhaka.
  static Future<List<MedicineDose>> getMedicineDosesForDate(DateTime d) async {
    final result = await client.rpc('get_medicine_doses', params: {
      'p_date': _dateOnly(d),
    });
    final list = (result as List?) ?? [];
    return list
        .map((e) => MedicineDose.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Marks a single dose as taken/skipped/missed. Idempotent — calling
  /// twice doesn't create a duplicate row thanks to the unique index.
  static Future<void> markDose({
    required String medicineId,
    required DateTime date,
    required String scheduledTime, // HH:mm
    String status = 'taken',
    String? note,
  }) async {
    await client.rpc('mark_dose', params: {
      'p_medicine_id': medicineId,
      'p_dose_date': _dateOnly(date),
      'p_scheduled_time': scheduledTime,
      'p_status': status,
      if (note != null && note.isNotEmpty) 'p_note': note,
    });
  }

  /// Returns an adherence summary suitable for the dashboard tile.
  static Future<MedicineAdherence> getMedicineAdherence({int days = 7}) async {
    try {
      final result = await client.rpc('get_medicine_adherence', params: {
        'p_days': days,
      });

      if (result is Map) {
        return MedicineAdherence.fromJson(Map<String, dynamic>.from(result));
      }

      final list = (result as List?) ?? [];
      if (list.isEmpty) return MedicineAdherence.empty;

      int taken = 0;
      int total = 0;
      for (final row in list) {
        if (row is! Map) continue;
        final m = Map<String, dynamic>.from(row);
        taken += (m['taken'] ?? 0) as int;
        total += (m['total'] ?? 0) as int;
      }

      return MedicineAdherence(
        totalDoses: total,
        taken: taken,
        skipped: 0,
        missed: 0,
        takenPct: total == 0 ? 0 : (taken / total) * 100,
        currentStreakDays: 0,
        windowDays: days,
      );
    } catch (e, st) {
      debugPrint('getMedicineAdherence error: $e\n$st');
      return MedicineAdherence.empty;
    }
  }

  /// Returns the user's 30-day plan progression.
  static Future<PlanProgress> getPlanProgress({int totalDays = 30}) async {
    try {
      final result = await client.rpc('get_plan_progress', params: {
        'p_total_days': totalDays,
      });

      if (result is Map) {
        return PlanProgress.fromRow(Map<String, dynamic>.from(result));
      }

      final list = (result as List?) ?? [];
      if (list.isEmpty) return PlanProgress.fallback();
      return PlanProgress.fromRow(
        Map<String, dynamic>.from(list.first as Map),
      );
    } catch (e, st) {
      debugPrint('getPlanProgress error: $e\n$st');
      return PlanProgress.fallback();
    }
  }

  /// Returns a 7-day meal adherence summary for the dashboard.
  static Future<MealAdherence> getMealAdherence({int days = 7}) async {
    try {
      final result = await client.rpc('get_meal_adherence', params: {
        'p_days': days,
      });

      if (result is Map) {
        return MealAdherence.fromJson(Map<String, dynamic>.from(result));
      }

      final list = (result as List?) ?? [];
      if (list.isEmpty) return MealAdherence.empty;

      int planned = 0;
      int eaten = 0;
      for (final row in list) {
        if (row is! Map) continue;
        final m = Map<String, dynamic>.from(row);
        planned += (m['planned'] ?? 0) as int;
        eaten += (m['eaten'] ?? 0) as int;
      }

      return MealAdherence(
        planned: planned,
        eaten: eaten,
        eatenPct: planned == 0 ? 0 : (eaten / planned) * 100,
        currentStreakDays: 0,
        windowDays: days,
      );
    } catch (e, st) {
      debugPrint('getMealAdherence error: $e\n$st');
      return MealAdherence.empty;
    }
  }

  // ----------- WORKOUTS -----------

  /// Seeds 1..30 day assignments with the default walk + breathing + stretch
  /// routine for the signed-in user. Idempotent.
  ///
  /// We pass the user id explicitly because the RPC runs as `security definer`
  /// and `auth.uid()` is occasionally null when the JWT isn't propagated
  /// inside the function context. Falling back to the cached client user
  /// makes the seed reliable even on cold sessions.
  static Future<void> ensureDefaultWorkoutAssignments() async {
    final userId = currentUser?.id;
    if (userId == null) {
      debugPrint(
          'ensureDefaultWorkoutAssignments: no signed-in user; skipping');
      return;
    }
    try {
      await client.rpc('ensure_default_workout_assignments', params: {
        'p_user_id': userId,
      });
    } catch (e) {
      debugPrint('ensureDefaultWorkoutAssignments error: $e');
    }
  }

  /// Re-activates and re-seeds the 30-day workout plan for the signed-in
  /// user. Idempotent — safe to call on every workout screen load.
  /// Solves "only 1 exercise today" caused by stale `is_active = false`
  /// rows from earlier migrations or empty `auth.users` joins.
  static Future<void> seedMyWorkoutAssignments() async {
    final userId = currentUser?.id;
    if (userId == null) {
      debugPrint('seedMyWorkoutAssignments: no signed-in user; skipping');
      return;
    }
    try {
      await client.rpc('seed_my_workout_assignments');
    } catch (e) {
      debugPrint('seedMyWorkoutAssignments error: $e');
    }
  }

  /// Returns the whole "today's workout" payload for the given program day.
  /// Passing [dayIndex] is now optional — `15_diabetes_12ex.sql` makes the
  /// server side calendar-aware, so omitting it lets "today" mean the
  /// actual current Bangladesh date.
  static Future<TodaysWorkout> getTodayWorkout({int? dayIndex}) async {
    try {
      final params = <String, dynamic>{};
      if (dayIndex != null) params['p_day_index'] = dayIndex;
      final result = await client.rpc('get_today_workout', params: params);
      return TodaysWorkout.fromJson(Map<String, dynamic>.from(result as Map));
    } catch (e) {
      debugPrint('getTodayWorkout error: $e');
      return TodaysWorkout(
        dayIndex: dayIndex ?? 1,
        today: DateTime.now(),
        assignments: const [],
      );
    }
  }

  /// Returns a playable URL for a video stored in the `exercise`
  /// Supabase Storage bucket. Accepts either:
  ///   * a full https URL (already signed) — returned as-is;
  ///   * a bare storage path inside the `exercise` bucket — signed
  ///     on demand so the token stays short-lived.
  ///
  /// We then probe the URL with a HEAD request so a non-video
  /// response (e.g. a 404 HTML error page) fails loudly instead of
  /// leaving ExoPlayer stuck on "Source error".
  ///
  /// Returns an empty string when nothing playable is found so the
  /// caller can render a graceful placeholder.
  static Future<String> createExerciseVideoSignedUrl(
    String storagePathOrUrl, {
    Duration expiresIn = const Duration(hours: 2),
  }) async {
    final raw = storagePathOrUrl.trim();
    if (raw.isEmpty) return '';
    try {
      String url;
      if (raw.startsWith('http://') || raw.startsWith('https://')) {
        url = raw;
      } else {
        url = await client.storage
            .from('exercise')
            .createSignedUrl(raw, expiresIn.inSeconds);
      }

      // Probe the URL — if Supabase Storage returned an error page
      // (status != 200 or content-type isn't video/*) we surface that
      // as "not playable" instead of letting the video player choke
      // on a non-video body.
      final ok = await _looksLikeVideo(url);
      if (!ok) {
        debugPrint('createExerciseVideoSignedUrl: $url not a video response');
        return '';
      }
      return url;
    } catch (e) {
      debugPrint('createExerciseVideoSignedUrl($raw) error: $e');
      return '';
    }
  }

  /// Lightweight HEAD probe: returns true iff [url] returns 200
  /// with a content-type that looks like a video or generic binary.
  ///
  /// Supabase Storage frequently serves `video/mp4` files with the
  /// generic `application/octet-stream` Content-Type, so we accept
  /// any 2xx response whose Content-Type is either `video/*`,
  /// `application/octet-stream`, `binary/octet-stream`, or absent.
  /// Anything else (HTML, JSON, an empty 4xx) is rejected so the
  /// caller can render a graceful placeholder instead of stalling
  /// ExoPlayer on a dead URL.
  static Future<bool> _looksLikeVideo(String url) async {
    try {
      final client = io.HttpClient();
      final req = await client.openUrl('HEAD', Uri.parse(url));
      req.headers.set('User-Agent', 'AmarDiet/1.0');
      final resp = await req.close().timeout(const Duration(seconds: 6));
      final status = resp.statusCode;
      final ct = (resp.headers.contentType?.mimeType ?? '').toLowerCase();
      client.close(force: true);
      if (status < 200 || status >= 300) return false;
      if (ct.isEmpty) return true; // some proxies strip the header
      if (ct.startsWith('video/')) return true;
      if (ct == 'application/octet-stream' ||
          ct == 'binary/octet-stream' ||
          ct == 'application/mp4') return true;
      return false;
    } catch (_) {
      // HEAD probes are blocked on some Storage proxies; fall back to
      // trusting the URL — the video_player will surface a clearer
      // error to the user if it really is broken.
      return true;
    }
  }

  /// Starts (or resumes) today's workout session. Idempotent — returns the
  /// existing session id if one is already open for [dayIndex].
  static Future<String> startWorkoutSession({int dayIndex = 1}) async {
    final id = await client.rpc('start_workout_session', params: {
      'p_day_index': dayIndex,
    });
    return id as String;
  }

  /// Persists the result of one exercise in a session.
  ///
  /// Accepts either the legacy [itemId] alone, or the (sessionId,
  /// workoutId) pair — the latter lets the RPC lazy-create the
  /// session_item row when the user navigates to a day that the
  /// session wasn't originally started for (so the exercise wasn't
  /// pre-inserted into workout_session_items).
  static Future<void> finishWorkoutSessionItem({
    String? itemId,
    String? sessionId,
    String? workoutId,
    required int durationSeconds,
    required bool completed,
  }) async {
    await client.rpc('finish_workout_session_item', params: {
      if (itemId != null) 'p_item_id': itemId,
      if (workoutId != null) 'p_workout_id': workoutId,
      if (sessionId != null) 'p_session_id': sessionId,
      'p_duration_seconds': durationSeconds,
      'p_completed': completed,
    });
  }

  /// Marks the whole session as finished and rolls up totals.
  static Future<void> finishWorkoutSession({required String sessionId}) async {
    await client.rpc('finish_workout_session', params: {
      'p_session_id': sessionId,
    });
  }

  /// Per-day target vs. actual workout minutes for the last [days] days.
  /// Used by the workout screen to render "আজকের লক্ষ্য vs আপনার সময়".
  static Future<List<WorkoutTimeRow>> getWorkoutTimeRows({int days = 7}) async {
    try {
      final result = await client.rpc('get_workout_time_tracking', params: {
        'p_days': days,
      });
      final list = <WorkoutTimeRow>[];
      if (result is List) {
        for (final v in result) {
          if (v is Map) {
            list.add(WorkoutTimeRow.fromJson(Map<String, dynamic>.from(v)));
          }
        }
      }
      return list;
    } catch (e) {
      debugPrint('getWorkoutTimeRows error: $e');
      return const [];
    }
  }

  /// Per-exercise "actual/target min" feedback for today. Returns a map
  /// keyed by workout id so the assignment tiles can show inline pills.
  static Future<Map<String, WorkoutExerciseTimeFeedback>>
      getTodayExerciseTimeFeedback() async {
    try {
      final result = await client.rpc('get_today_exercise_time_feedback');
      final out = <String, WorkoutExerciseTimeFeedback>{};
      if (result is List) {
        for (final v in result) {
          if (v is Map) {
            final fb = WorkoutExerciseTimeFeedback.fromJson(
                Map<String, dynamic>.from(v));
            if (fb.workoutId.isNotEmpty) {
              out[fb.workoutId] = fb;
            }
          }
        }
      }
      return out;
    } catch (e) {
      debugPrint('getTodayExerciseTimeFeedback error: $e');
      return const {};
    }
  }

  /// Today's water / heart-rate / steps row. Falls back to
  /// `DailyMetric.empty` on any error (including a not-yet-initialized
  /// client from a hot-restart race) so the water screen never shows
  /// a raw developer-facing exception overlay.
  static Future<DailyMetric> getTodayDailyMetrics() async {
    debugPrint('💧 [getTodayDailyMetrics] → calling RPC');
    if (!isInitialized) {
      // Hot-restart race: `init()` ran fine but a new isolate cleared
      // the static field. Skip the call and let the user retry.
      debugPrint('💧 [getTodayDailyMetrics] skipped — client not '
          'initialized (hot-restart race)');
      return DailyMetric.empty;
    }
    try {
      final result = await client.rpc('get_today_daily_metrics');
      debugPrint('💧 [getTodayDailyMetrics] ← raw response: '
          'type=${result.runtimeType} value=$result');
      if (result == null) {
        debugPrint('💧 [getTodayDailyMetrics] null result → empty');
        return DailyMetric.empty;
      }

      Map<String, dynamic> row;
      if (result is List && result.isNotEmpty) {
        row = Map<String, dynamic>.from(result.first as Map);
      } else if (result is Map) {
        row = Map<String, dynamic>.from(result);
      } else {
        debugPrint('💧 [getTodayDailyMetrics] unrecognised shape → empty');
        return DailyMetric.empty;
      }

      final metric = DailyMetric.fromRow(row);
      debugPrint('💧 [getTodayDailyMetrics] parsed: $metric');
      return metric;
    } catch (e, st) {
      debugPrint('💧 [getTodayDailyMetrics] ✗ EXCEPTION: $e');
      debugPrint('💧 [getTodayDailyMetrics] stack: $st');
      return DailyMetric.empty;
    }
  }

  /// Quick-add water (e.g. +0.25 L from a tap). Atomic on the server
  /// so concurrent taps never lose the delta.
  static Future<DailyMetric> addWaterLiters(double deltaLiters) async {
    debugPrint('💧 [addWaterLiters] → delta=$deltaLiters');
    try {
      final result = await client.rpc(
        'add_water_liters',
        params: {'p_delta': deltaLiters},
      );
      debugPrint('💧 [addWaterLiters] ← raw response: '
          'type=${result.runtimeType} value=$result');
      if (result == null) {
        debugPrint('💧 [addWaterLiters] null result → empty (this is the '
            'likely cause of "value reset to 0"!)');
        return DailyMetric.empty;
      }

      Map<String, dynamic> row;
      if (result is List && result.isNotEmpty) {
        row = Map<String, dynamic>.from(result.first as Map);
      } else if (result is Map) {
        row = Map<String, dynamic>.from(result);
      } else {
        debugPrint('💧 [addWaterLiters] unrecognised shape → empty');
        return DailyMetric.empty;
      }

      final metric = DailyMetric.fromRow(row);
      debugPrint('💧 [addWaterLiters] parsed: $metric');
      return metric;
    } catch (e, st) {
      debugPrint('💧 [addWaterLiters] ✗ EXCEPTION: $e');
      debugPrint('💧 [addWaterLiters] stack: $st');
      return DailyMetric.empty;
    }
  }

  /// Set today's water to an absolute value (server clamps 0..20).
  /// Used by the water-screen "undo last glass" path so reverting
  /// doesn't leave the row a fraction of a glass off.
  /// Returns `DailyMetric.empty` (without persisting anything) if the
  /// client isn't initialized yet — typical of a hot-restart race —
  /// so the UI doesn't crash mid-tap.
  static Future<DailyMetric> setWaterLiters(double liters) async {
    debugPrint('💧 [setWaterLiters] → liters=$liters');
    if (!isInitialized) {
      debugPrint('💧 [setWaterLiters] skipped — client not initialized');
      return DailyMetric.empty;
    }
    try {
      final result = await client.rpc(
        'upsert_daily_metric',
        params: {
          'p_field': 'water_liters',
          'p_value': liters,
        },
      );
      debugPrint('💧 [setWaterLiters] ← raw response: '
          'type=${result.runtimeType} value=$result');
      if (result == null) {
        debugPrint('💧 [setWaterLiters] null result → empty');
        return DailyMetric.empty;
      }

      Map<String, dynamic> row;
      if (result is List && result.isNotEmpty) {
        row = Map<String, dynamic>.from(result.first as Map);
      } else if (result is Map) {
        row = Map<String, dynamic>.from(result);
      } else {
        debugPrint('💧 [setWaterLiters] unrecognised shape → empty');
        return DailyMetric.empty;
      }

      final metric = DailyMetric.fromRow(row);
      debugPrint('💧 [setWaterLiters] parsed: $metric');
      return metric;
    } catch (e, st) {
      debugPrint('💧 [setWaterLiters] ✗ EXCEPTION: $e');
      debugPrint('💧 [setWaterLiters] stack: $st');
      return DailyMetric.empty;
    }
  }

  // ─────────────────────────────── Water analytics ──────────────────────────
  // Newer RPCs that back the analytics screen + daily-restart flow.
  // Kept separate from addWaterLiters / setWaterLiters so the legacy
  // code paths still work even if the analytics tables haven't been
  // provisioned yet — callers fall back gracefully.

  /// `log_water_event(p_delta, p_occurred_at)` — write one glass
  /// event with a server-stamped bucket. The server mirrors the
  /// running total into `daily_metrics.water_liters` so existing
  /// callers (dashboard) still see today's total without code change.
  /// Returns the inserted event row, or `null` on failure or if the
  /// client isn't initialized yet (hot-restart race).
  static Future<Map<String, dynamic>?> logWaterEvent(
    double delta, {
    DateTime? at,
  }) async {
    if (!isInitialized) {
      debugPrint('💧 [logWaterEvent] skipped — client not initialized');
      return null;
    }
    try {
      final occurredAt =
          (at ?? DateTime.now()).toUtc().toIso8601String();
      final result = await client.rpc('log_water_event', params: {
        'p_delta': delta,
        'p_occurred_at': occurredAt,
      });
      if (result is List && result.isNotEmpty && result.first is Map) {
        return Map<String, dynamic>.from(result.first);
      }
      return null;
    } catch (e, st) {
      debugPrint('💧 [logWaterEvent] ✗ EXCEPTION: $e');
      debugPrint('💧 [logWaterEvent] stack: $st');
      return null;
    }
  }

  /// `get_water_analytics(p_days)` — last [days] days of summary
  /// stats. Single round-trip drives the entire analytics screen.
  /// Returns [WaterAnalyticsSummary.empty] on failure so callers can
  /// render a graceful empty state.
  static Future<WaterAnalyticsSummary> getWaterAnalytics({
    int days = 7,
  }) async {
    final userId = currentUser?.id;
    if (userId == null) {
      return WaterAnalyticsSummary.empty;
    }
    try {
      final result = await client.rpc('get_water_analytics', params: {
        'p_days': days,
      });
      if (result is Map) {
        return WaterAnalyticsSummary.fromJson(
          Map<String, dynamic>.from(result),
        );
      }
      debugPrint('💧 [getWaterAnalytics] unexpected shape: $result');
      return WaterAnalyticsSummary.empty;
    } catch (e, st) {
      debugPrint('💧 [getWaterAnalytics] ✗ EXCEPTION: $e');
      debugPrint('💧 [getWaterAnalytics] stack: $st');
      return WaterAnalyticsSummary.empty;
    }
  }

  /// `reset_daily_water_task(p_for_date)` — snapshots the requested
  /// day's totals into `daily_water_summary`. Idempotent; safe to
  /// call repeatedly. Used on app start when the local date has
  /// rolled over so analytics never lose a day.
  static Future<bool> resetDailyWaterTask({DateTime? forDate}) async {
    final userId = currentUser?.id;
    if (userId == null) return false;
    try {
      final dateStr = _dateOnly(forDate ??
          DateTime.now().subtract(const Duration(days: 1)));
      await client.rpc('reset_daily_water_task', params: {
        'p_for_date': dateStr,
      });
      return true;
    } catch (e, st) {
      debugPrint('💧 [resetDailyWaterTask] ✗ EXCEPTION: $e');
      debugPrint('💧 [resetDailyWaterTask] stack: $st');
      return false;
    }
  }

  /// Set heart rate (absolute value, clamped 30–230 on the server).
  static Future<DailyMetric> setHeartRate(int bpm) async {
    try {
      final result = await client.rpc(
        'upsert_daily_metric',
        params: {'p_field': 'heart_rate_bpm', 'p_value': bpm},
      );
      if (result is List && result.isNotEmpty && result.first is Map) {
        return DailyMetric.fromRow(Map<String, dynamic>.from(result.first));
      }
      return DailyMetric.empty;
    } catch (e) {
      debugPrint('setHeartRate error: $e');
      return DailyMetric.empty;
    }
  }

  /// Set step count (absolute value, clamped 0–200000 on the server).
  static Future<DailyMetric> setSteps(int steps) async {
    try {
      final result = await client.rpc(
        'upsert_daily_metric',
        params: {'p_field': 'steps', 'p_value': steps},
      );
      if (result is List && result.isNotEmpty && result.first is Map) {
        return DailyMetric.fromRow(Map<String, dynamic>.from(result.first));
      }
      return DailyMetric.empty;
    } catch (e) {
      debugPrint('setSteps error: $e');
      return DailyMetric.empty;
    }
  }

  /// Returns per-day workout logs for the last [days] days, oldest first.
  static Future<List<WorkoutLogRow>> getWorkoutLogs({int days = 7}) async {
    final resp = await client.rpc('get_workout_logs', params: {
      'p_days': days,
    });
    final list = (resp as List?) ?? [];
    return list
        .cast<Map>()
        .map((m) => WorkoutLogRow.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// Per-day meal adherence rows for the dashboard chart.
  static Future<List<MealLogRow>> getMealLogs({int days = 7}) async {
    try {
      final resp = await client.rpc('get_meal_logs', params: {
        'p_days': days,
      });
      if (resp is! List) return const [];
      return resp
          .cast<Map>()
          .map((m) => MealLogRow.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (e, st) {
      debugPrint('getMealLogs error: $e\n$st');
      return const [];
    }
  }

  /// Per-day medicine adherence rows for the dashboard chart.
  static Future<List<MedicineLogRow>> getMedicineLogs({int days = 7}) async {
    try {
      final resp = await client.rpc('get_medicine_logs', params: {
        'p_days': days,
      });
      if (resp is! List) return const [];
      return resp
          .cast<Map>()
          .map((m) => MedicineLogRow.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (e, st) {
      debugPrint('getMedicineLogs error: $e\n$st');
      return const [];
    }
  }

  /// Returns a windowed workout adherence summary.
  static Future<WorkoutAdherence> getWorkoutAdherence({int days = 7}) async {
    try {
      final result = await client.rpc('get_workout_adherence', params: {
        'p_days': days,
      });

      if (result is Map) {
        return WorkoutAdherence.fromJson(Map<String, dynamic>.from(result));
      }

      final list = (result as List?) ?? [];
      if (list.isEmpty) return WorkoutAdherence.empty;

      int completed = 0;
      int total = 0;
      int daysActive = 0;
      for (final row in list) {
        if (row is! Map) continue;
        final m = Map<String, dynamic>.from(row);
        final c = (m['completed'] ?? 0) as int;
        completed += c;
        total += (m['total'] ?? 0) as int;
        if (c > 0) daysActive++;
      }

      return WorkoutAdherence(
        totalSessions: total,
        completed: completed,
        completedPct: total == 0 ? 0 : (completed / total) * 100,
        currentStreakDays: 0,
        windowDays: days,
        daysActive: daysActive,
      );
    } catch (e, st) {
      debugPrint('getWorkoutAdherence error: $e\n$st');
      return WorkoutAdherence.empty;
    }
  }

  // ----------- FAVORITES -----------

  static Future<List<String>> listFavorites() async {
    final userId = currentUser?.id;
    if (userId == null) return [];
    final resp = await client
        .from('user_favorites')
        .select('food_id')
        .eq('user_id', userId);
    final list = (resp as List?) ?? [];
    return list.map((e) => (e as Map)['food_id'] as String).toList();
  }

  static Future<void> addFavorite(String foodId) async {
    final userId = currentUser?.id;
    if (userId == null) return;
    await client.from('user_favorites').upsert({
      'user_id': userId,
      'food_id': foodId,
    });
  }

  static Future<void> removeFavorite(String foodId) async {
    final userId = currentUser?.id;
    if (userId == null) return;
    await client
        .from('user_favorites')
        .delete()
        .eq('user_id', userId)
        .eq('food_id', foodId);
  }

  // ----------- USER CUSTOM MEAL PLANS -----------
  // The user_meal_plans table is a per-user, per-date CRUD store.
  // It lets users override or extend the AI-suggested 30-day
  // rotation with their own foods, slot names, times, and notes.

  /// Returns the user's custom entries in a date range.
  /// Default is the last 7 days (including today).
  static Future<List<UserMealPlan>> listUserMealPlans({
    DateTime? from,
    DateTime? to,
  }) async {
    final result = await client.rpc('list_user_meal_plans', params: {
      if (from != null) 'p_from': _dateOnly(from),
      if (to != null) 'p_to': _dateOnly(to),
    });
    final list = (result as List?) ?? [];
    return list
        .map((e) => UserMealPlan.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Returns the user's custom entries for a single date.
  static Future<List<UserMealPlan>> getUserDayPlan(DateTime date) async {
    final result = await client.rpc('get_user_day_plan', params: {
      'p_effective_date': _dateOnly(date),
    });
    final list = (result as List?) ?? [];
    return list
        .map((e) => UserMealPlan.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Creates a new custom entry. Returns the new id.
  static Future<String> createUserMealPlan({
    required DateTime effectiveDate,
    required String slot,
    String? scheduledTime,
    String? foodId,
    String? customFoodName,
    String? portionLabel,
    String? notes,
    int position = 0,
  }) async {
    final id = await client.rpc('create_user_meal_plan', params: {
      'p_effective_date': _dateOnly(effectiveDate),
      'p_slot': slot,
      if (scheduledTime != null && scheduledTime.isNotEmpty)
        'p_scheduled_time': scheduledTime,
      if (foodId != null && foodId.isNotEmpty) 'p_food_id': foodId,
      if (customFoodName != null && customFoodName.isNotEmpty)
        'p_custom_food_name': customFoodName,
      if (portionLabel != null && portionLabel.isNotEmpty)
        'p_portion_label': portionLabel,
      if (notes != null && notes.isNotEmpty) 'p_notes': notes,
      'p_position': position,
    });
    return id.toString();
  }

  /// Updates one or more fields of an existing entry.
  /// Any null parameter is left unchanged, EXCEPT for the
  /// `clearXxx` flags which force the field to null.
  static Future<void> updateUserMealPlan({
    required String id,
    DateTime? effectiveDate,
    String? slot,
    String? scheduledTime,
    bool clearScheduledTime = false,
    String? foodId,
    bool clearFoodId = false,
    String? customFoodName,
    String? portionLabel,
    String? notes,
    int? position,
    bool? isActive,
  }) async {
    final params = <String, dynamic>{
      'p_id': id,
      if (effectiveDate != null) 'p_effective_date': _dateOnly(effectiveDate),
      if (slot != null) 'p_slot': slot,
      if (clearScheduledTime) 'p_clear_scheduled_time': true,
      if (scheduledTime != null && !clearScheduledTime)
        'p_scheduled_time': scheduledTime,
      if (clearFoodId) 'p_clear_food_id': true,
      if (foodId != null && !clearFoodId) 'p_food_id': foodId,
      if (customFoodName != null) 'p_custom_food_name': customFoodName,
      if (portionLabel != null) 'p_portion_label': portionLabel,
      if (notes != null) 'p_notes': notes,
      if (position != null) 'p_position': position,
      if (isActive != null) 'p_is_active': isActive,
    };
    await client.rpc('update_user_meal_plan', params: params);
  }

  /// Soft-deletes (deactivates) an entry.
  static Future<void> deleteUserMealPlan(String id) async {
    await client.rpc('delete_user_meal_plan', params: {'p_id': id});
  }

  /// Replaces every entry for a single date with the supplied list.
  /// Pass an empty list to clear the date entirely.
  static Future<int> replaceUserDayPlan({
    required DateTime effectiveDate,
    required List<Map<String, dynamic>> entries,
  }) async {
    final result = await client.rpc('replace_user_day_plan', params: {
      'p_effective_date': _dateOnly(effectiveDate),
      'p_entries': entries,
    });
    return (result as num).toInt();
  }

  // ----------- AI PLAN OVERRIDES -----------
  // meal_plan_overrides lets a user pin a single food_id to a
  // (plan_day, slot, role) tuple, replacing the AI-suggested
  // food for that position. The baseline 30-day rotation is
  // untouched. See supabasesql/11_ai_plan_overrides.sql.

  /// Daily recommendation with per-user overrides merged on top
  /// of the 30-day rotation.
  static Future<Map<String, dynamic>> getDailyRecommendationWithOverrides(
      int day) async {
    final userId = currentUser?.id;
    if (userId == null) throw StateError('No authenticated user.');
    try {
      final result = await client.rpc('get_daily_recommendation_with_overrides',
          params: {'p_plan_day': day});
      return Map<String, dynamic>.from(result as Map);
    } catch (_) {
      // Fallback for environments where 11_* hasn't been run yet.
      return getDailyRecommendation(day);
    }
  }

  /// Pins `foodId` to the AI plan slot `(planDay, slot, role)`.
  /// Pass `role: null` for single-item slots like breakfast.
  static Future<void> upsertAiPlanOverride({
    required int planDay,
    required String slot,
    String? role,
    required String foodId,
  }) async {
    await client.rpc('upsert_ai_plan_override', params: {
      'p_plan_day': planDay,
      'p_slot': slot,
      if (role != null) 'p_role': role,
      'p_food_id': foodId,
    });
  }

  /// Removes an override so the AI suggestion is shown again.
  static Future<void> deleteAiPlanOverride({
    required int planDay,
    required String slot,
    String? role,
  }) async {
    await client.rpc('delete_ai_plan_override', params: {
      'p_plan_day': planDay,
      'p_slot': slot,
      if (role != null) 'p_role': role,
    });
  }

  /// Searches the master foods list by Bangla name. Empty query
  /// returns the first `limit` foods.
  static Future<List<MealItem>> searchFoods(String query,
      {int limit = 20}) async {
    final result = await client.rpc('search_foods', params: {
      'p_query': query,
      'p_limit': limit,
    });
    final list = (result as List?) ?? [];
    return list
        .map((e) => MealItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Fetches the full master food list (capped at [limit]) so the
  /// profile screen can show "foods to avoid" against the user's
  /// classification. Ordered to surface cheap, common-in-BD, healthy
  /// options first — those are the ones a Bangladeshi user is most
  /// likely to see in their daily plan.
  ///
  /// Throws on any Supabase error so callers can show a graceful
  /// fallback (empty list) in their `FutureBuilder`.
  static Future<List<MealItem>> fetchAllFoodsForProfile(
      {int limit = 250}) async {
    final result = await client
        .from('foods')
        .select()
        .order('common_in_bd', ascending: false)
        .order('healthiness')
        .limit(limit);
    final list = (result as List?) ?? [];
    return list
        .map((e) => MealItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  // ---------------------------------------------------------------
  // AI Chat (Groq) — see supabasesql/25_ai_chat.sql
  // ---------------------------------------------------------------

  /// Identifies a quota row from `check_and_increment_prompt_quota` /
  /// `get_prompt_quota`. Both RPCs return the same shape so we share
  /// this Dart type.
  static Map<String, dynamic>? _firstRow(dynamic res) {
    if (res is List && res.isNotEmpty) {
      return Map<String, dynamic>.from(res.first as Map);
    }
    if (res is Map) return Map<String, dynamic>.from(res);
    return null;
  }

  /// Reads today's quota *without* mutating. Used to refresh the
  /// "৩/৫ আজ" pill after a successful send.
  static Future<({int used, int remaining, int limit, DateTime resetsAt})?>
      fetchPromptQuota({int limit = 5}) async {
    final user = currentUser;
    if (user == null) return null;
    final row = _firstRow(await client.rpc('get_prompt_quota', params: {
      'p_user_id': user.id,
      'p_limit': limit,
    }));
    if (row == null) return null;
    return (
      used: (row['used'] as num?)?.toInt() ?? 0,
      remaining: (row['remaining'] as num?)?.toInt() ?? limit,
      limit: (row['limit_val'] as num?)?.toInt() ?? limit,
      resetsAt: DateTime.tryParse(row['resets_at'] as String? ?? '') ??
          DateTime.now().toUtc(),
    );
  }

  /// Atomically reserve a prompt slot. Returns the new count + the
  /// `allowed` flag. Throws on RPC error so the UI can show a polite
  /// Bangla error.
  static Future<({bool allowed, int used, int remaining, int limit})?>
      consumePromptQuota({int limit = 5}) async {
    final user = currentUser;
    if (user == null) return null;
    final row = _firstRow(await client.rpc(
      'check_and_increment_prompt_quota',
      params: {
        'p_user_id': user.id,
        'p_limit': limit,
      },
    ));
    if (row == null) return null;
    return (
      allowed: row['allowed'] as bool? ?? false,
      used: (row['used'] as num?)?.toInt() ?? 0,
      remaining: (row['remaining'] as num?)?.toInt() ?? 0,
      limit: (row['limit_val'] as num?)?.toInt() ?? limit,
    );
  }

  /// Give back a quota slot when the AI never produced a usable reply.
  /// Called by `AiChatService` after `router.send()` returns either an
  /// empty string or throws `every-model-silent`. Clamped at 0
  /// server-side so it's safe to call speculatively.
  ///
  /// Returns the refreshed quota + whether a slot was actually refunded
  /// (false means the user never consumed one today, which is harmless).
  static Future<({int used, int remaining, int limit, bool refunded})?>
      refundPromptQuota({int limit = 5}) async {
    final user = currentUser;
    if (user == null) return null;
    final row = _firstRow(await client.rpc(
      'refund_prompt_quota',
      params: {
        'p_user_id': user.id,
        'p_limit': limit,
      },
    ));
    if (row == null) return null;
    return (
      used: (row['used'] as num?)?.toInt() ?? 0,
      remaining: (row['remaining'] as num?)?.toInt() ?? limit,
      limit: (row['limit_val'] as num?)?.toInt() ?? limit,
      refunded: row['refunded'] as bool? ?? false,
    );
  }

  /// Fetches the JSON blob the Flutter client prepends to the system
  /// prompt (`profile`, `classification`, `medicines_today`, etc.).
  static Future<Map<String, dynamic>?> fetchAiChatContext() async {
    final user = currentUser;
    if (user == null) return null;
    final res = await client.rpc('get_ai_chat_context',
        params: {'p_user_id': user.id});
    if (res == null) return null;
    if (res is Map) return Map<String, dynamic>.from(res);
    return null;
  }

  /// Append a single message to the transcript. Returns the row id so
  /// the UI can wire up a "👍/👎" feedback chip later.
  ///
  /// If [threadId] is passed the row is tagged with that thread so
  /// the sidebar history can group messages by conversation.
  static Future<String?> saveAiChatMessage({
    required String role,
    required String content,
    String? model,
    String? threadId,
  }) async {
    final user = currentUser;
    if (user == null) return null;
    if (role != 'user' && role != 'assistant' && role != 'system') {
      throw ArgumentError('role must be user|assistant|system, got "$role"');
    }
    final id = await client.rpc('save_ai_chat_message', params: {
      'p_user_id': user.id,
      'p_role': role,
      'p_content': content,
      if (model != null) 'p_model': model,
      if (threadId != null) 'p_thread_id': threadId,
    });
    return id as String?;
  }

  // ----------------------------------------------------------------
  // Conversation threads (history sidebar)
  // ----------------------------------------------------------------

  /// Lightweight row used by the history sidebar.
  /// `preview` is the first user message truncated for the title slot.
  static Future<List<AiChatThreadRow>> listAiChatThreads({
    int limit = 100,
  }) async {
    final user = currentUser;
    if (user == null) return const [];
    final res = await client.rpc('list_ai_chat_threads', params: {
      'p_user_id': user.id,
      'p_limit': limit,
    });
    final list = (res as List?) ?? [];
    return list.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return AiChatThreadRow(
        id: m['id'] as String,
        title: (m['title'] as String?) ?? '',
        createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ??
            DateTime.now().toUtc(),
        lastMessageAt: DateTime.tryParse(m['last_message_at'] as String? ?? '') ??
            DateTime.now().toUtc(),
        messageCount: (m['message_count'] as num?)?.toInt() ?? 0,
        preview: (m['preview'] as String?) ?? '',
      );
    }).toList(growable: false);
  }

  /// Start a new thread. Returns the new thread id.
  static Future<String?> createAiChatThread({String? titleSeed}) async {
    final user = currentUser;
    if (user == null) return null;
    final id = await client.rpc('create_ai_chat_thread', params: {
      'p_user_id': user.id,
      if (titleSeed != null) 'p_title_seed': titleSeed,
    });
    return id as String?;
  }

  /// Rename a thread the user owns. Returns `true` on success.
  static Future<bool> renameAiChatThread({
    required String threadId,
    required String title,
  }) async {
    final user = currentUser;
    if (user == null) return false;
    final res = await client.rpc('rename_ai_chat_thread', params: {
      'p_thread_id': threadId,
      'p_user_id': user.id,
      'p_title': title,
    });
    return res == true;
  }

  /// Delete a thread + its messages. Quota is untouched.
  static Future<bool> deleteAiChatThread({required String threadId}) async {
    final user = currentUser;
    if (user == null) return false;
    final res = await client.rpc('delete_ai_chat_thread', params: {
      'p_thread_id': threadId,
      'p_user_id': user.id,
    });
    return res == true;
  }

  /// Load the full transcript of a past thread, ordered oldest-first.
  static Future<List<AiChatHistoryMessage>> loadThreadMessages({
    required String threadId,
    int limit = 500,
  }) async {
    final user = currentUser;
    if (user == null) return const [];
    final res = await client.rpc('load_thread_messages', params: {
      'p_user_id': user.id,
      'p_thread_id': threadId,
      'p_limit': limit,
    });
    final list = (res as List?) ?? [];
    return list.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return AiChatHistoryMessage(
        id: m['id'] as String?,
        role: (m['role'] as String?) ?? 'user',
        content: (m['content'] as String?) ?? '',
        model: m['model'] as String?,
        createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ??
            DateTime.now().toUtc(),
      );
    }).toList(growable: false);
  }

  /// Wipe the user's transcript. Quota isn't touched.
  static Future<int> clearAiChatHistory() async {
    final user = currentUser;
    if (user == null) return 0;
    final n = await client.rpc('clear_ai_chat_history',
        params: {'p_user_id': user.id});
    return (n as num?)?.toInt() ?? 0;
  }

  /// Record a 👍/👎 on an assistant message. `rating` must be `1`
  /// or `-1`.
  static Future<void> saveAiChatFeedback({
    required String messageId,
    required int rating,
  }) async {
    assert(rating == 1 || rating == -1, 'rating must be -1 or 1');
    final user = currentUser;
    if (user == null) return;
    await client.rpc('save_ai_chat_feedback', params: {
      'p_user_id': user.id,
      'p_message_id': messageId,
      'p_rating': rating,
    });
  }

  /// Last N user/assistant turns (oldest first) for the conversation
  /// history sent to the chat model. Defaults to 8 (≈ 4 exchanges).
  ///
  /// Pass [threadId] so we only recall turns from the *active*
  /// conversation — never bleeds across threads.
  static Future<List<({String role, String content, String? model})>>
      lastNAiChatMessages({int n = 8, String? threadId}) async {
    final user = currentUser;
    if (user == null) return const [];
    final res = await client.rpc('last_n_ai_chat_messages', params: {
      'p_user_id': user.id,
      'p_n': n,
      if (threadId != null) 'p_thread_id': threadId,
    });
    final list = (res as List?) ?? [];
    return list
        .map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return (
            role: (m['role'] as String?) ?? 'user',
            content: (m['content'] as String?) ?? '',
            model: m['model'] as String?,
          );
        })
        .toList(growable: false);
  }
}

/// One conversation in the history sidebar (ChatGPT/Claude style).
class AiChatThreadRow {
  AiChatThreadRow({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.lastMessageAt,
    required this.messageCount,
    required this.preview,
  });
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime lastMessageAt;
  final int messageCount;
  final String preview;
}

/// One message loaded from a past thread.
class AiChatHistoryMessage {
  AiChatHistoryMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.model,
    required this.createdAt,
  });
  final String? id;
  final String role; // 'user' | 'assistant' | 'system'
  final String content;
  final String? model;
  final DateTime createdAt;
}

/// Stand-in [SupabaseClient] returned by [SupabaseService.client] when
/// neither our static mirror nor the underlying [Supabase.instance]
/// singleton is available (e.g. mid hot-restart before re-init runs).
///
/// Every method throws a typed [SupabaseNotInitializedError] so
/// callers' existing `try/catch` blocks surface the friendly Bangla
/// message instead of Flutter painting a raw red overlay.
class _NotReadyClient implements SupabaseClient {
  Never _throw() => throw SupabaseNotInitializedError();

  @override
  dynamic noSuchMethod(Invocation invocation) => _throw();
}
