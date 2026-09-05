import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io' as io;
import '../models/blog_article.dart';
import '../models/user_profile.dart';
import '../models/meal_item.dart';
import '../models/meal_details.dart';
import '../models/user_meal_plan.dart';
import '../models/medicine.dart';
import '../models/dashboard.dart';
import '../models/thirty_day_report.dart';
import '../models/water_analytics.dart';
import '../models/workout.dart';
import '../models/caretaker_link.dart';
import '../models/caretaker_patient_summary.dart';
import '../models/caregiver_observation.dart';
import '../models/mood_entry.dart';
import 'bdapps/bdapps_session_service.dart';

/// Thin wrapper around the Supabase client used by Apon Susthota (আপন সুস্থতা).
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
    String? username,
    String role = 'patient',
    String? caretakerRelationship,
  }) {
    final meta = <String, dynamic>{
      'full_name': fullName.trim(),
      'mobile': mobile.trim(),
      'role': role,
    };
    if (username != null && username.trim().isNotEmpty) {
      meta['username'] = username.trim();
    }
    if (role == 'caretaker' &&
        caretakerRelationship != null &&
        caretakerRelationship.trim().isNotEmpty) {
      meta['caretaker_relationship'] = caretakerRelationship.trim();
    }
    return client.auth.signUp(
      email: email,
      password: password,
      data: meta,
    );
  }

  static Future<AuthResponse> signIn(String email, String password) {
    return client.auth.signInWithPassword(email: email, password: password);
  }

  /// Send a "forgot password" email via Supabase Auth.
  /// Caller is expected to render the result in a friendly snackbar.
  static Future<void> resetPassword(String email) {
    return client.auth.resetPasswordForEmail(email.trim());
  }

  /// Liveness check used by the auth screen's connection pill.
  /// We simply query the `profiles` table (a 1-row read) so any
  /// reachable Supabase project responds within ~1s — even when
  /// the user isn't signed in yet.
  static Future<void> pingSession() async {
    await client.from('user_profiles').select('user_id').limit(1);
  }

  static Future<void> signOut() => client.auth.signOut();

  /// Updates the auth user's user_metadata (used to edit name/mobile/username
  /// after signup).
  static Future<void> updateAccountMeta({
    String? fullName,
    String? mobile,
    String? username,
    bool? profileCompleted,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('No authenticated user.');
    final meta = Map<String, dynamic>.from(user.userMetadata ?? {});
    if (fullName != null) meta['full_name'] = fullName.trim();
    if (mobile != null) meta['mobile'] = mobile.trim();
    if (username != null) meta['username'] = username.trim();
    if (profileCompleted != null) meta['profile_completed'] = profileCompleted;
    await client.auth.updateUser(UserAttributes(data: meta));
  }

  // ----------- PROFILE -----------

  /// Reads the user's profile row. Returns null if they haven't onboarded yet.
  static Future<UserProfile?> fetchProfile() async {
    final userId = currentUser?.id;
    if (userId == null) return null;
    final m = await client
        .from('user_profiles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (m == null) return null;
    final meta = currentUser?.userMetadata ?? const {};
    final isBdapps = meta['auth_source'] == 'bdapps';
    final mobile = meta['mobile'] as String?;

    Map<String, dynamic>? bdRow;
    if (isBdapps && mobile != null) {
      try {
        final dynamic res = await client.rpc('bdapps_fetch_profile', params: {'p_mobile': mobile});
        if (res != null) {
          bdRow = Map<String, dynamic>.from(res is List ? res.first : res);
        }
      } catch (e) {
        debugPrint('bdapps_fetch_profile failed: $e');
      }
    }

    return UserProfile(
      fullName: (bdRow?['full_name'] as String?) ?? (m['full_name'] as String?) ?? (meta['full_name'] as String?),
      mobile: (bdRow?['mobile'] as String?) ?? (m['mobile'] as String?) ?? (meta['mobile'] as String?),
      username: (bdRow?['username'] as String?) ?? (m['username'] as String?) ?? (meta['username'] as String?),
      age: (bdRow?['age'] ?? m['age'] ?? 0) as int,
      sex: (bdRow?['sex'] ?? m['sex'] ?? 'male') as String,
      weightKg: ((bdRow?['weight_kg'] ?? m['weight_kg'] ?? 0) as num).toDouble(),
      heightCm: ((bdRow?['height_cm'] ?? m['height_cm'] ?? 0) as num).toDouble(),
      fastingGlucoseMmol: (bdRow?['fasting_sugar'] != null)
          ? ((bdRow?['fasting_sugar']) as num).toDouble()
          : (m['fasting_glucose_mmol'] != null)
              ? ((m['fasting_glucose_mmol']) as num).toDouble()
              : null,
      postMealGlucoseMmol: (bdRow?['post_meal_sugar'] != null)
          ? ((bdRow?['post_meal_sugar']) as num).toDouble()
          : (m['post_meal_glucose_mmol'] != null)
              ? ((m['post_meal_glucose_mmol']) as num).toDouble()
              : null,
      randomGlucoseMmol: m['random_glucose_mmol'] != null
          ? ((m['random_glucose_mmol']) as num).toDouble()
          : null,
      hba1cPercent: (bdRow?['hba1c'] != null)
          ? ((bdRow?['hba1c']) as num).toDouble()
          : (m['hba1c_percent'] != null)
              ? ((m['hba1c_percent']) as num).toDouble()
              : null,
      onInsulin: (bdRow?['insulin'] != null)
          ? (bdRow!['insulin'].toString().toLowerCase() != 'no')
          : (m['on_insulin'] ?? false) as bool,
      medication: m['medication'] as String?,
      systolicBp: bdRow?['bp'] != null
          ? int.tryParse(bdRow!['bp'].toString().split('/').first)
          : m['systolic_bp'] as int?,
      diastolicBp: bdRow?['bp'] != null && bdRow!['bp'].toString().contains('/')
          ? int.tryParse(bdRow['bp'].toString().split('/').last)
          : m['diastolic_bp'] as int?,
      hasCkd: (bdRow?['kidney_disease'] ?? m['has_ckd'] ?? false) as bool,
      ckdStage: m['ckd_stage'] as int?,
      hasHeartDisease: (bdRow?['heart_disease'] ?? m['has_heart_disease'] ?? false) as bool,
      hasAnemia: (bdRow?['anemia'] ?? m['has_anemia'] ?? false) as bool,
      otherConditions: m['other_conditions'] as String?,
      activityLevel: (m['activity_level'] ?? 'low') as String,
      mealSizePref: (m['meal_size_pref'] ?? 'medium') as String,
      foodPreference: (m['food_preference'] ?? 'omnivore') as String,
      avatarUrl: (bdRow?['avatar_url'] as String?) ?? (m['avatar_url'] as String?) ?? (meta['avatar_url'] as String?),
      photoUploadCount: ((m['photo_upload_count'] ?? 0) as num).toInt(),
      role: (bdRow?['role'] as String?) ??
          (m['role'] as String?) ??
          (meta['role'] as String?) ??
          'patient',
      caretakerRelationship: (bdRow?['caretaker_relationship'] as String?) ??
          (m['caretaker_relationship'] as String?) ??
          (meta['caretaker_relationship'] as String?),
      profileCompleted: (bdRow?['profile_completed'] as bool?) ??
          (m['profile_completed'] as bool?) ??
          (meta['profile_completed'] as bool?) ??
          false,
      bdappsMobile: (m['bdapps_mobile'] as String?) ??
          (meta['bdapps_mobile'] as String?),
    );
  }

  /// Upserts the user's clinical profile (public.user_profiles).
  ///
  /// We pass `onConflict: 'user_id'` so Postgres knows the merge target and
  /// doesn't silently fail on update. Without it, an upsert of an existing
  /// row can throw a 400 that bubbles up and crashes the app.
  static Future<void> saveProfile(UserProfile profile) async {
    final user = currentUser;
    final userId = user?.id;
    if (userId == null) {
      throw StateError(
          'No authenticated user — sign in before saving a profile.');
    }

    // 1. Save to the main user_profiles table (legacy/shadow row).
    // This maintains compatibility with all other tables/RPCs that join on user_profiles.
    await client.from('user_profiles').upsert(
          profile.toSupabaseRow(userId),
          onConflict: 'user_id',
        );

    // 2. If this is a BDApps user, also mirror the data to the bdapps_users table.
    // The user "moved" the source of truth to bdapps_users in migration 46/49.
    final mobile = user?.userMetadata?['mobile'] as String?;
    final isBdapps = user?.userMetadata?['auth_source'] == 'bdapps';

    if (isBdapps && mobile != null) {
      try {
        await client.rpc('bdapps_update_profile', params: {
          'p_mobile': mobile,
          'p_full_name': profile.fullName,
          'p_username': profile.username,
          'p_age': profile.age,
          'p_weight_kg': profile.weightKg,
          'p_height_cm': profile.heightCm,
          'p_bp': profile.systolicBp != null && profile.diastolicBp != null
              ? '${profile.systolicBp}/${profile.diastolicBp}'
              : null,
          'p_insulin': profile.onInsulin ? (profile.medication ?? 'Yes') : 'No',
          'p_fasting_sugar': profile.fastingGlucoseMmol,
          'p_post_meal_sugar': profile.postMealGlucoseMmol,
          'p_hba1c': profile.hba1cPercent,
          'p_kidney_disease': profile.hasCkd,
          'p_heart_disease': profile.hasHeartDisease,
          'p_anemia': profile.hasAnemia,
          'p_email': null, // We don't usually have a real email for BDApps users
          'p_caretaker_relationship': profile.caretakerRelationship,
          'p_avatar_url': profile.avatarUrl,
          'p_mark_completed': profile.profileCompleted,
        });
      } catch (e) {
        // Log but don't fail the whole operation if the mirror fails.
        debugPrint('bdapps_update_profile mirror failed: $e');
      }
    }
  }

  /// Persists the user's chosen role + (for caretakers) their
  /// relationship string. Called by the role router once the
  /// user has picked Patient | Caregiver. Both columns have a
  /// CHECK constraint enforced server-side — invalid values throw.
  ///
  /// We always write both columns in a single UPDATE so the row
  /// stays consistent: clearing the relationship when the user
  /// re-picks "patient" prevents stale "ছেলে" labels from leaking
  /// into the patient shell.
  static Future<void> updateRoleAndRelationship({
    required String role,
    String? caretakerRelationship,
  }) async {
    final userId = currentUser?.id;
    if (userId == null) {
      throw StateError('No authenticated user.');
    }
    await client.from('user_profiles').update({
      'role': role,
      'caretaker_relationship':
          role == 'caretaker' ? caretakerRelationship?.trim() : null,
    }).eq('user_id', userId);
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

  /// Server-side classification (diet type, BMI bucket, etc.).
  ///
  /// Wrapped in try/catch because this is called inside `Future.wait`
  /// on the dashboard. Any throw here propagates out of `_load()` and
  /// turns the whole dashboard into the error widget — a "white
  /// screen" experience for the user.
  ///
  /// The PostgREST schema cache is also intermittently stale for
  /// freshly-deployed functions (404 / PGRST202), so we degrade
  /// gracefully to an empty map and let the dashboard render with
  /// `cls == null` rather than nuking the whole screen.
  static Future<Map<String, dynamic>> classifyUser() async {
    final userId = currentUser?.id;
    if (userId == null) return <String, dynamic>{};
    try {
      final result = await client.rpc('classify_user', params: {
        'p_user_id': userId,
      });
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return <String, dynamic>{};
    } catch (e, st) {
      debugPrint('classifyUser error (degraded to empty): $e\n$st');
      return <String, dynamic>{};
    }
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

  /// Calls `get_food_details(p_food_id text)` server-side and returns
  /// the joined [MealDetails] (master food row + optional recipe row).
  /// Returns null when the food id is unknown — UI treats this as
  /// "no details available" without throwing.
  static Future<MealDetails?> getMealDetails(String foodId) async {
    if (foodId.isEmpty) return null;
    final result = await client.rpc('get_food_details', params: {
      'p_food_id': foodId,
    });
    if (result == null) return null;
    final m = Map<String, dynamic>.from(result as Map);
    if (m['found'] == false) return null;
    return MealDetails.fromJson(m);
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
    // If foodId starts with 'custom::', it's a UI-generated key for a free-text
    // meal in the rotation plan. The database foreign key on `food_id` expects
    // a valid UUID from the `foods` table. We pass null so the name-only
    // logging logic in the RPC takes over.
    final effectiveFoodId = (foodId != null && foodId.startsWith('custom::')) ? null : foodId;

    final id = await client.rpc('record_meal_intake', params: {
      'p_meal_slot': mealSlot,
      'p_food_id': effectiveFoodId,
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
  ///
  /// Returns `true` on success, `false` on any failure. The caller (workout
  /// screen) surfaces a clear error when both this AND [seedMyWorkoutAssignments]
  /// fail to seed rows, which used to manifest as a silent empty screen.
  static Future<bool> ensureDefaultWorkoutAssignments() async {
    final userId = currentUser?.id;
    if (userId == null) {
      debugPrint(
          'ensureDefaultWorkoutAssignments: no signed-in user; skipping');
      return false;
    }
    try {
      await client.rpc('ensure_default_workout_assignments', params: {
        'p_user_id': userId,
      });
      return true;
    } catch (e) {
      debugPrint('ensureDefaultWorkoutAssignments error: $e');
      return false;
    }
  }

  /// Re-activates and re-seeds the 30-day workout plan for the signed-in
  /// user. Idempotent — safe to call on every workout screen load.
  /// Solves "only 1 exercise today" caused by stale `is_active = false`
  /// rows from earlier migrations or empty `auth.users` joins.
  ///
  /// Returns `true` on success, `false` on any failure.
  static Future<bool> seedMyWorkoutAssignments() async {
    final userId = currentUser?.id;
    if (userId == null) {
      debugPrint('seedMyWorkoutAssignments: no signed-in user; skipping');
      return false;
    }
    try {
      await client.rpc('seed_my_workout_assignments');
      return true;
    } catch (e) {
      debugPrint('seedMyWorkoutAssignments error: $e');
      return false;
    }
  }

  /// Seeds the 4-week progressive plan (`17_workout_progressive_30day.sql`)
  /// for the current user. This is the most recent and most detailed plan,
  /// designed for elderly users with progressive intensity across 30 days.
  /// Idempotent — safe to call on every workout screen load.
  ///
  /// We call this *in addition to* `seedMyWorkoutAssignments` because the
  /// two RPCs come from different migration files and can write to
  /// different (day, workout) cells. Together they guarantee today's
  /// `get_today_workout` has at least one active row per calendar day.
  ///
  /// Returns `true` on success, `false` if the RPC is missing on the
  /// server (older deployments) or any other failure.
  static Future<bool> seedMyProgressivePlan() async {
    final userId = currentUser?.id;
    if (userId == null) {
      debugPrint('seedMyProgressivePlan: no signed-in user; skipping');
      return false;
    }
    try {
      await client.rpc('seed_my_progressive_plan');
      return true;
    } catch (e) {
      // PGRST202 — function not in schema cache. Common on older DBs
      // that pre-date migration 17_*.sql. Log but don't crash; the
      // other seed RPC still gives us a usable plan.
      debugPrint('seedMyProgressivePlan error: $e');
      return false;
    }
  }

  /// Emergency re-seed for the calling user — the last line of defence
  /// against the "no workout today" symptom. Tries the strong RPC first
  /// (added in `35_fix_workout_assignments.sql`) which re-seeds the
  /// entire 30-day progressive plan, and falls back to the legacy
  /// walking-only fallback from `34_workout_emergency_reseed.sql`.
  ///
  /// We pass an explicit named parameter even for parameterless RPCs
  /// to dodge the PostgREST schema-cache quirk where a parameterless
  /// call against a parameterless function returns PGRST202
  /// ("Could not find the function ... without parameters").
  ///
  /// Idempotent — safe to call on every workout screen load. Returns
  /// `true` on success, `false` if every RPC failed.
  static Future<bool> reseedTodayForCurrentUser() async {
    final userId = currentUser?.id;
    if (userId == null) {
      debugPrint('reseedTodayForCurrentUser: no signed-in user; skipping');
      return false;
    }
    // (1) Strong re-seed: full 30-day progressive plan. The function
    //     takes no parameters, but we still send a no-op named arg so
    //     PostgREST's schema cache resolves the call deterministically.
    try {
      await client.rpc('reseed_full_workout_plan', params: const {});
      return true;
    } catch (e) {
      debugPrint('reseed_full_workout_plan error (will fall back): $e');
    }
    // (2) Legacy fallback: walking-only emergency reseed from 34_*.sql.
    try {
      await client.rpc('reseed_today_for_all_users', params: const {});
      return true;
    } catch (e) {
      debugPrint('reseedTodayForCurrentUser error: $e');
      return false;
    }
  }

  /// Returns the program_day of the user's most recent
  /// workout_session, or null if none exists. Used by the workout
  /// screen as a last-resort fallback when today's calendar anchor
  /// returns no assignments (e.g. after a long gap). Lets the user
  /// resume from where they last were instead of staring at an
  /// empty "day 1/30" placeholder.
  static Future<int?> getLastProgramDayForCurrentUser() async {
    if (currentUser == null) return null;
    try {
      final result = await client
          .from('workout_sessions')
          .select('program_day')
          .eq('user_id', currentUser!.id)
          .order('session_date', ascending: false)
          .limit(1)
          .maybeSingle();
      if (result == null) return null;
      final v = result['program_day'];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return null;
    } catch (e) {
      debugPrint('getLastProgramDayForCurrentUser error: $e');
      return null;
    }
  }

  /// Returns the whole "today's workout" payload for the given program day.
  /// Passing [dayIndex] is now optional — `15_diabetes_12ex.sql` makes the
  /// server side calendar-aware, so omitting it lets "today" mean the
  /// actual current Bangladesh date.
  ///
  /// Rethrows on RPC failure so the workout screen can surface the real
  /// error instead of rendering a silent empty state. Earlier we caught
  /// here and returned an empty `TodaysWorkout`, which is what caused the
  /// "no workout visible" symptom — the screen was happily rendering an
  /// empty hero because the underlying network / RLS error was hidden.
  static Future<TodaysWorkout> getTodayWorkout({int? dayIndex}) async {
    // Always pass `p_day_index` (even when null). The server-side function
    // is declared as `get_today_workout(p_day_index int default null)` —
    // PostgREST's schema cache refuses to match a `()`-style call against a
    // signature that has parameters, and surfaces PGRST202 ("Could not find
    // the function ... without parameters"). Passing the key explicitly
    // resolves the match.
    final params = <String, dynamic>{'p_day_index': dayIndex};
    final result = await client.rpc('get_today_workout', params: params);
    return TodaysWorkout.fromJson(Map<String, dynamic>.from(result as Map));
  }

  /// Returns a playable URL for a video stored in the `exercise`
  /// Supabase Storage bucket. Accepts either:
  ///   * a full https URL (already signed) — returned as-is;
  ///   * a bare storage path inside the `exercise` bucket — signed
  ///     on demand so the token stays short-lived.
  ///
  /// We then probe the URL with a HEAD request so a non-video
  /// response (e.g. a 404 HTML error page, or — most importantly —
  /// an *expired* signed-URL token returning 403) fails loudly
  /// instead of leaving ExoPlayer stuck on "Source error".
  ///
  /// If the URL is a pre-signed link that has expired, we transparently
  /// extract the underlying storage path and re-sign it on the fly, so
  /// old DB rows that still point at expired tokens keep working
  /// forever.  Returns an empty string when nothing playable is found
  /// so the caller can render a graceful placeholder.
  static Future<String> createExerciseVideoSignedUrl(
    String storagePathOrUrl, {
    Duration expiresIn = const Duration(hours: 2),
  }) async {
    final raw = storagePathOrUrl.trim();
    if (raw.isEmpty) return '';
    try {
      String url;
      bool fromFullUrl = false;
      if (raw.startsWith('http://') || raw.startsWith('https://')) {
        url = raw;
        fromFullUrl = true;
      } else {
        url = await client.storage
            .from('exercise')
            .createSignedUrl(raw, expiresIn.inSeconds);
      }

      // probe the URL — if Supabase Storage returned an error page
      // (status != 200 or content-type isn't video/*) we surface that
      // as "not playable" instead of letting the video player choke
      // on a non-video body.
      final ok = await _looksLikeVideo(url);
      if (ok) return url;

      // 4xx (commonly 403/400 for an expired signed-URL token) on a
      // full URL — try to recover by re-signing the underlying
      // storage path. This lets the existing 12 rows keep working
      // even though their stored tokens have expired.
      if (fromFullUrl) {
        final path = _extractExerciseStoragePath(raw);
        if (path != null && path.isNotEmpty) {
          debugPrint(
              'createExerciseVideoSignedUrl: signed URL expired or invalid, re-signing decoded path: $path');
          try {
            final refreshed = await client.storage
                .from('exercise')
                .createSignedUrl(path, expiresIn.inSeconds);
            return refreshed;
          } catch (e) {
            debugPrint('createExerciseVideoSignedUrl re-sign failed for $path: $e');
          }
        }
      }

      // If it's a bare path and the probe failed, it might be a false
      // positive on the HEAD request (e.g. 403). We return it anyway
      // and let the video player try the full GET request.
      if (!fromFullUrl && url.isNotEmpty) return url;

      debugPrint('createExerciseVideoSignedUrl: $url not a video response');
      return '';
    } catch (e) {
      debugPrint('createExerciseVideoSignedUrl($raw) error: $e');
      return '';
    }
  }

  /// Extract the storage path (e.g. `Walking.mp4`) from a full
  /// Supabase Storage URL of any flavour:
  ///   * signed     — `/storage/v1/object/sign/exercise/Walking.mp4?token=...`
  ///   * public     — `/storage/v1/object/public/exercise/Walking.mp4`
  ///   * render     — `/storage/v1/render/image/sign/exercise/Walking.mp4?token=...`
  /// Returns `null` if the URL does not look like a storage object URL.
  static String? _extractExerciseStoragePath(String url) {
    try {
      final uri = Uri.parse(url);
      final segs = uri.pathSegments;
      // segs will be like: ['storage', 'v1', 'object', 'sign', 'exercise', 'Walking.mp4']
      // or ['storage', 'v1', 'object', 'public', 'exercise', 'Walking.mp4']
      // or ['storage', 'v1', 'render', 'image', 'sign', 'exercise', 'Walking.mp4']
      final i = segs.indexOf('exercise');
      if (i < 0 || i + 1 >= segs.length) return null;
      // Re-join everything after 'exercise/' in case there are subfolders.
      // pathSegments are already decoded by Uri.parse.
      return segs.sublist(i + 1).join('/');
    } catch (_) {
      return null;
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
      req.headers.set('User-Agent', 'AponSusthota/1.0');
      final resp = await req.close().timeout(const Duration(seconds: 6));
      final status = resp.statusCode;
      final ct = (resp.headers.contentType?.mimeType ?? '').toLowerCase();
      client.close(force: true);

      // If the storage proxy returns 405 (Method Not Allowed) for HEAD,
      // we fall back to trusting the URL.
      if (status == 405) return true;

      // 403 (Forbidden) or 401 (Unauthorized) usually means an expired
      // signed token. Return false so we can try to re-sign.
      if (status == 403 || status == 401) return false;

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

  /// Append a row to `public.ai_chat_action_log` capturing a tool call
  /// the AI just executed. Idempotent on (p_message_id, p_tool_name).
  /// Returns the audit row id, which the client uses to Undo later.
  static Future<String?> logAiChatAction({
    required String toolName,
    required Map<String, dynamic> toolArgs,
    required Map<String, dynamic> inverseArgs,
    required String description,
    String? messageId,
    String? threadId,
  }) async {
    try {
      final id = await client.rpc('log_ai_chat_action', params: {
        'p_tool_name': toolName,
        'p_tool_args': toolArgs,
        'p_inverse_args': inverseArgs,
        'p_description': description,
        if (messageId != null) 'p_message_id': messageId,
        if (threadId != null) 'p_thread_id': threadId,
      });
      return id?.toString();
    } catch (e) {
      debugPrint('⚠️ [SupabaseService] logAiChatAction failed: $e');
      return null;
    }
  }

  /// Mark an AI action as undone. The Flutter `action_inverse` module
  /// runs the compensating RPC after this returns.
  static Future<bool> undoAiChatAction({required String actionId}) async {
    try {
      await client.rpc('undo_ai_chat_action', params: {
        'p_id': actionId,
      });
      return true;
    } catch (e) {
      debugPrint('⚠️ [SupabaseService] undoAiChatAction failed: $e');
      return false;
    }
  }

  /// Inverse for `logWaterEvent` — subtracts the row from the running
  /// total so the dashboard tile updates instantly.
  static Future<bool> deleteWaterIntake({required String logId}) async {
    try {
      await client.rpc('delete_water_intake', params: {
        'p_log_id': logId,
      });
      return true;
    } catch (e) {
      debugPrint('⚠️ [SupabaseService] deleteWaterIntake failed: $e');
      return false;
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  Mood + health check-in
  // ════════════════════════════════════════════════════════════════

  /// Today's mood + health row, or null when the user hasn't logged
  /// yet today. Mirrors `get_today_mood` in `41_mood.sql`.
  static Future<MoodEntry?> getTodayMood() async {
    debugPrint('🌤️ [getTodayMood] → calling RPC');
    if (!isInitialized) {
      debugPrint('🌤️ [getTodayMood] skipped — client not initialized');
      return null;
    }
    try {
      final result = await client.rpc('get_today_mood');
      if (result == null) return null;
      List<dynamic> rows;
      if (result is List) {
        rows = result;
      } else {
        rows = const [];
      }
      if (rows.isEmpty) {
        debugPrint('🌤️ [getTodayMood] no row for today');
        return null;
      }
      final entry = MoodEntry.fromJson(
        Map<String, dynamic>.from(rows.first as Map),
      );
      debugPrint('🌤️ [getTodayMood] parsed: $entry');
      return entry;
    } catch (e, st) {
      debugPrint('🌤️ [getTodayMood] ✗ EXCEPTION: $e');
      debugPrint('🌤️ [getTodayMood] stack: $st');
      return null;
    }
  }

  /// Upsert today's mood + health row via the `log_mood` RPC.
  /// Returns the freshly-inserted row so the caller can render
  /// the post-save "logged at HH:mm" label without a second
  /// round-trip.
  static Future<MoodEntry?> logMood({
    required MoodKind mood,
    required int energyLevel,
    required int stressLevel,
    required double sleepHours,
    String? symptoms,
  }) async {
    debugPrint('🌤️ [logMood] → $mood energy=$energyLevel '
        'stress=$stressLevel sleep=${sleepHours}h');
    if (!isInitialized) {
      debugPrint('🌤️ [logMood] skipped — client not initialized');
      return null;
    }
    try {
      await client.rpc('log_mood', params: {
        'p_mood_kind': mood.code,
        'p_energy': energyLevel,
        'p_stress': stressLevel,
        'p_sleep': sleepHours,
        'p_symptoms': symptoms,
      });
      // Re-read so we get the canonical `created_at` the server
      // wrote, and any DB-side defaults applied.
      return await getTodayMood();
    } catch (e, st) {
      debugPrint('🌤️ [logMood] ✗ EXCEPTION: $e');
      debugPrint('🌤️ [logMood] stack: $st');
      return null;
    }
  }

  /// Last [days] days of mood + health rows (newest first), for the
  /// mood history screen and any future analytics chart.
  static Future<List<MoodEntry>> getMoodHistory({int days = 14}) async {
    debugPrint('🌤️ [getMoodHistory] → days=$days');
    if (!isInitialized) {
      debugPrint('🌤️ [getMoodHistory] skipped — client not initialized');
      return const [];
    }
    try {
      final result = await client.rpc(
        'get_mood_history',
        params: {'p_days': days},
      );
      final rows = (result is List) ? result : const [];
      return rows
          .map((e) => MoodEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e, st) {
      debugPrint('🌤️ [getMoodHistory] ✗ EXCEPTION: $e');
      debugPrint('🌤️ [getMoodHistory] stack: $st');
      return const [];
    }
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

  // ---------------------------------------------------------------------------
  // 30-day Doctor Report cycle
  // - Wraps the JSON RPCs defined in supabasesql/27_thirty_day_report.sql and
  //   supabasesql/27_daily_detail.sql.
  // - The cycle is anchored on auth.users.created_at; day 1 = signup day.
  // - Days the user has not lived yet or skipped come back as zeros.
  // ---------------------------------------------------------------------------

  /// Fetch the full 30-day cycle report (one RPC round-trip).
  ///
  /// [cycleIndex] selects which 30-day window to return:
  ///   • 0 (default) — current cycle, the one containing today
  ///   • 1 — the previous 30-day window
  ///   • 2+ — further back
  ///
  /// Returns `null` when the requested cycle is past the user's signup date
  /// (i.e. the user hasn't been around long enough to have that cycle).
  /// The analytics screen uses that signal to disable the "আগের চক্র"
  /// button instead of rendering the current cycle twice.
  static Future<ThirtyDayReport?> getThirtyDayReport({
    int cycleIndex = 0,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    // Server-side auth check lives in the RPC (auth.uid()).
    final res = await client
        .rpc('get_thirty_day_report', params: {'p_cycle_index': cycleIndex})
        .timeout(timeout);
    final m = Map<String, dynamic>.from(res as Map);
    final report = ThirtyDayReport.fromJson(m);
    // The SQL always returns a 30-day window — even if the requested cycle
    // falls BEFORE the user's signup date (the window is then entirely in
    // the past). We treat that as "this cycle exists" because the data
    // might still be useful for analytics; the caller decides whether to
    // surface it. Only a `null` RPC result is treated as missing.
    return report;
  }

  /// Returns how many 30-day cycles of data the current user has. 1 means
  /// only the current cycle is available (the user is in their first month).
  /// Used by the analytics screen to bound its cycle-picker.
  static Future<int> getAnalyticsCycleCount({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final res = await client
          .rpc('get_analytics_cycle_count')
          .timeout(timeout);
      if (res is int) return res;
      if (res is num) return res.toInt();
      if (res is String) return int.tryParse(res) ?? 1;
      return 1;
    } catch (e) {
      debugPrint('getAnalyticsCycleCount error: $e');
      return 1;
    }
  }

  /// Fetch the per-day drill-down for one day in the cycle (meals, meds,
  /// workouts, water logs). Used by the Doctor Report screen when the user
  /// expands a day.  [date] is the calendar date (not day_of_cycle index).
  static Future<DayFullReport> getDayFullReport({
    required DateTime date,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    // Server-side auth check lives in the RPC (auth.uid()).
    final iso =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final res = await client
        .rpc('get_day_full_report', params: {'p_date': iso})
        .timeout(timeout);
    final m = Map<String, dynamic>.from(res as Map);
    return DayFullReport.fromJson(m);
  }

  // ============================================================
  // CARETAKER / PATIENT LINK SYSTEM (28/29/30)
  // ============================================================
  //
  // All write paths go through RPCs so RLS + status checks live on
  // the server, not the client. Read paths fan out to either an RPC
  // (for joined/computed views like `get_caretaker_patient_list`) or
  // direct table reads (for `get_patient_pending_links` etc — those
  // tables already have RLS so a `from(...).select()` is safe and
  // saves a round-trip vs an RPC).

  // ---------- Patient inbox (from the patient's perspective) ----------

  /// Patient inbox: list of `caretaker_patient_links` rows where the
  /// current user is the patient and status = 'pending'.
  ///
  /// RLS on `caretaker_patient_links` restricts this to rows where
  /// `patient_user_id = auth.uid()`, so no extra server-side check is
  /// required here.
  static Future<List<CaretakerLink>> getPatientPendingLinks() async {
    final List<dynamic> res = await client
        .from('caretaker_patient_links')
        .select()
        .eq('patient_user_id', currentUser?.id ?? '')
        .eq('status', 'pending')
        .order('requested_at', ascending: false);
    return res
        .map((e) => CaretakerLink.fromSupabaseRow(
            Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Active caretakers currently watching the signed-in patient.
  static Future<List<CaretakerLink>> getPatientActiveCaretakers() async {
    final List<dynamic> res = await client
        .from('caretaker_patient_links')
        .select()
        .eq('patient_user_id', currentUser?.id ?? '')
        .eq('status', 'active')
        .order('responded_at', ascending: false);
    return res
        .map((e) => CaretakerLink.fromSupabaseRow(
            Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Patient action on a pending request — accepts or declines. The
  /// RPC writes the response timestamp and updates status atomically;
  /// it also broadcasts via realtime so the caretaker sees the result
  /// without polling.
  ///
  /// [accept] true to accept (status → 'active'), false to decline.
  static Future<void> respondCaretakerRequest({
    required String linkId,
    required bool accept,
  }) async {
    await client.rpc('respond_caretaker_link', params: {
      'p_link_id': linkId,
      // SQL signature is `p_decision text` ('accept' | 'decline').
      'p_decision': accept ? 'accept' : 'decline',
    });
  }

  /// Patient revokes an active link. The RPC refuses if the row is
  /// not in 'active' state (so double-taps are safe).
  static Future<void> revokeCaretakerLinkAsPatient(String linkId) async {
    await client.rpc('revoke_caretaker_link', params: {
      'p_link_id': linkId,
    });
  }

  // ---------- Caretaker writes (sending & revoking) ----------

  /// Caretaker searches for a patient by mobile number. Returns up to
  /// 5 matches. Each row is shaped exactly like the patient search
  /// RPC return: `{user_id, full_name, mobile_last4}` — no PII leak.
  static Future<List<Map<String, dynamic>>> searchPatientByMobile(
    String mobile,
  ) async {
    if (mobile.trim().isEmpty) return const [];
    final List<dynamic> res = await client.rpc(
      'search_patient_by_mobile',
      // SQL signature is `p_query text`.
      params: {'p_query': mobile.trim()},
    );
    return res
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  /// Unified Facebook-style people search.
  ///
  /// The caller (a caretaker OR a patient) can find users of the
  /// opposite role by name, email, or last-4-mobile. Returns up to
  /// [limit] rows. Each row carries:
  ///   * `user_id`
  ///   * `full_name`
  ///   * `mobile`         → masked (****1234)
  ///   * `email`          → masked (r••••@gmail.com)
  ///   * `role`           → 'patient' | 'caretaker'
  ///   * `age`, `sex`
  ///   * `avatar_url`     → storage path; client signs it locally
  ///   * `is_linked`      → true when there's any pending/active link
  ///   * `link_status`    → 'active' | 'pending' | null
  ///
  /// Backed by the `search_people` RPC (supabasesql/31_*.sql).
  static Future<List<Map<String, dynamic>>> searchPeople(
    String query, {
    int limit = 25,
  }) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    try {
      final List<dynamic> res = await client.rpc(
        'search_people',
        params: {
          'p_query': q,
          'p_limit': limit,
        },
      );
      return res
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
    } catch (e) {
      debugPrint('searchPeople error: $e');
      return const [];
    }
  }

  /// Public-profile RPC. Returns a small, PII-safe profile preview
  /// any signed-in user can read about any other user. Clinical
  /// fields (HbA1c, BP, weight, …) are NOT exposed by this RPC.
  ///
  /// Backed by `get_public_profile(uuid)` in supabasesql/31_*.sql.
  static Future<Map<String, dynamic>?> getPublicProfile(String userId) async {
    if (userId.isEmpty) return null;
    try {
      final res = await client.rpc(
        'get_public_profile',
        params: {'p_user_id': userId},
      );
      if (res is Map) return Map<String, dynamic>.from(res);
      return null;
    } catch (e) {
      debugPrint('getPublicProfile error: $e');
      return null;
    }
  }

  /// Patient-side inbox: pending caretaker requests, each carrying
  /// the caretaker's `full_name`, `avatar_url`, relationship, etc.
  /// Returns fully-mapped [CaretakerLink] objects.
  ///
  /// The SQL RPC `get_inbox_pending_links()` (see supabasesql/31_*.sql)
  /// aliases the link primary key as `link_id` and only returns
  /// `caretaker_user_id` / `patient_user_id` plus the joined profile
  /// columns under `caretaker_*`. We remap `link_id → id` and supply
  /// the relationship/status columns here so the resulting [CaretakerLink]
  /// has a non-null `id` (otherwise `respond_caretaker_link` cannot
  /// be called and accept/reject becomes a silent no-op). This mirrors
  /// the remap used by [listCaretakerPendingRequests] on the caretaker
  /// side.
  static Future<List<CaretakerLink>> getInboxPendingLinks() async {
    try {
      final res = await client.rpc('get_inbox_pending_links');
      if (res is! List) return const [];
      return res.whereType<Map>().map((e) {
        final raw = Map<String, dynamic>.from(e);
        return CaretakerLink.fromSupabaseRow({
          'id': raw['link_id'] ?? raw['id'],
          'caretaker_user_id': raw['caretaker_user_id'] ?? '',
          'patient_user_id': raw['patient_user_id'] ?? '',
          'status': 'pending',
          'request_note': raw['request_note'],
          'caretaker_relationship': raw['caretaker_relationship'],
          'requested_at': raw['requested_at'],
        });
      }).toList(growable: false);
    } catch (e) {
      debugPrint('getInboxPendingLinks error: $e');
      return const [];
    }
  }

  /// Patient-side inbox: active caretakers with joined name/avatar.
  /// Same `link_id → id` remap as [getInboxPendingLinks] so the
  /// resulting [CaretakerLink] has a usable id for the revoke RPC.
  static Future<List<CaretakerLink>> getInboxActiveCaretakers() async {
    try {
      final res = await client.rpc('get_inbox_active_caretakers');
      if (res is! List) return const [];
      return res.whereType<Map>().map((e) {
        final raw = Map<String, dynamic>.from(e);
        return CaretakerLink.fromSupabaseRow({
          'id': raw['link_id'] ?? raw['id'],
          'caretaker_user_id': raw['caretaker_user_id'] ?? '',
          'patient_user_id': raw['patient_user_id'] ?? '',
          'status': 'active',
          'caretaker_relationship': raw['caretaker_relationship'],
          'requested_at': raw['requested_at'],
          'responded_at': raw['responded_at'],
          'last_seen_at': raw['last_seen_at'],
        });
      }).toList(growable: false);
    } catch (e) {
      debugPrint('getInboxActiveCaretakers error: $e');
      return const [];
    }
  }

  /// Caretaker sends a link request. [patientUserId] is the uid
  /// returned from `searchPatientByMobile`. [relationship] is the
  /// caretaking role ("son", "spouse", "home nurse"). [note] is an
  /// optional free-text intro shown in the patient inbox.
  ///
  /// The `request_caretaker_link` SQL function returns the new link's
  /// UUID as a plain string (not a row). We construct a minimal
  /// `CaretakerLink` locally so the provider can return it; the
  /// caller usually triggers a `refresh()` afterwards which pulls
  /// the fully-enriched row via the inbox RPC.
  static Future<CaretakerLink> sendCaretakerRequest({
    required String patientUserId,
    required String relationship,
    String? note,
  }) async {
    final res = await client.rpc('request_caretaker_link', params: {
      'p_patient_user_id': patientUserId,
      'p_relationship': relationship.trim(),
      'p_note': note?.trim(),
    });
    final newId = res is String
        ? res
        : (res is Map ? res['id']?.toString() : null);
    return CaretakerLink(
      id: newId,
      caretakerUserId: currentUser?.id ?? '',
      patientUserId: patientUserId,
      status: CaretakerLinkStatus.pending,
      requestNote: (note ?? '').trim().isEmpty ? null : note?.trim(),
      caretakerRelationship: relationship.trim(),
      requestedAt: DateTime.now().toUtc(),
    );
  }

  /// Caretaker revokes one of their own active (or still-pending)
  /// links. Server validates caller == caretaker_user_id.
  static Future<void> revokeCaretakerLinkAsCaretaker(String linkId) async {
    await client.rpc('revoke_caretaker_link', params: {
      'p_link_id': linkId,
    });
  }

  // ---------- Caretaker reads ----------

  /// List of patients the signed-in caretaker is currently watching
  /// (status = 'active'), enriched with trailing 7-day adherence +
  /// last-seen timestamp. Sorted by `last_seen_at desc` so the
  /// most-recently-observed patient is at the top.
  static Future<List<CaretakerPatientSummary>>
      listCaretakerPatients() async {
    final List<dynamic> res = await client.rpc('get_caretaker_patient_list');
    return res
        .map((e) => CaretakerPatientSummary.fromRpcJson(
            Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Pending requests the caretaker has sent (where they are still
  /// waiting on a patient to accept). Used to show "অপেক্ষমান" rows in
  /// the patient search screen.
  static Future<List<CaretakerLink>> listCaretakerPendingRequests() async {
    final List<dynamic> res =
        await client.rpc('get_caretaker_pending_requests');
    // SQL returns rows keyed `link_id` plus wrapper fields
    // (`patient_user_id`, `full_name`, `age`, `request_note`,
    // `caretaker_relationship`, `requested_at`). Remap to the
    // shape `CaretakerLink.fromSupabaseRow` expects.
    return res.map((e) {
      final raw = Map<String, dynamic>.from(e as Map);
      return CaretakerLink.fromSupabaseRow({
        'id': raw['link_id'] ?? raw['id'],
        'caretaker_user_id':
            raw['caretaker_user_id'] ?? SupabaseService.currentUser?.id ?? '',
        'patient_user_id': raw['patient_user_id'] ?? '',
        'status': 'pending', // RPC only returns pending rows
        'request_note': raw['request_note'],
        'caretaker_relationship': raw['caretaker_relationship'],
        'requested_at': raw['requested_at'],
      });
    }).toList();
  }

  /// Today's at-a-glance for a patient. Triggers a server-side
  /// `last_seen_at` bump so the patient list can be sorted
  /// "most-recently-observed first". Returns the JSONB row from
  /// `get_caretaker_today_overview`.
  static Future<Map<String, dynamic>> getCaretakerTodayOverview({
    required String patientUserId,
  }) async {
    final res = await client.rpc('get_caretaker_today_overview', params: {
      'p_patient': patientUserId,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  /// Per-day sparkline data for a patient for the trailing N days.
  /// Each row holds aggregated meals/medicine/water/workout for one
  /// calendar day. [days] is clamped server-side to [7, 90].
  ///
  /// The RPC returns `{patient_user_id, days, series[]}` — we
  /// unwrap and return the inner `series` array.
  static Future<List<Map<String, dynamic>>> getCaretakerDailyBreakdown({
    required String patientUserId,
    int days = 30,
  }) async {
    final res = await client.rpc(
      'get_caretaker_daily_breakdown',
      params: {
        'p_patient': patientUserId,
        'p_days': days.clamp(1, 90),
      },
    );
    final raw = Map<String, dynamic>.from(res as Map);
    final List<dynamic> series = (raw['series'] as List?) ?? const [];
    return series
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  /// Merged activity feed for a patient (meals + medicine + water +
  /// workouts). [limit] is clamped server-side to ≤ 200.
  static Future<List<CaregiverObservation>> getCaretakerRecentActivities({
    required String patientUserId,
    int limit = 50,
  }) async {
    final List<dynamic> res = await client.rpc(
      'get_caretaker_recent_activities',
      params: {
        'p_patient': patientUserId,
        'p_limit': limit,
      },
    );
    return res
        .map((e) => CaregiverObservation.fromRpcJson(
            Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Read-only clinical snapshot for a patient (HbA1c, BP, glucose,
  /// conditions, allergies, food prefs). Server never returns PII
  /// like mobile or full address — those are caregiver-stripped at
  /// the RPC layer.
  static Future<Map<String, dynamic>> getCaretakerClinicalSnapshot({
    required String patientUserId,
  }) async {
    final res = await client.rpc('get_caretaker_clinical_snapshot', params: {
      'p_patient': patientUserId,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  // ---------- Caretaker own profile (relatives info) ----------
  // The SQL migration `56_caretaker_relatives_rename.sql` re-purposes
  // the doctor_* columns (originally added in `45_caretaker_care_doctor.sql`)
  // as relatives / family info: relationship, contact phone, address,
  // free-text note, and contact-hours availability. We wrap the thin
  // get/update RPCs here so the UI doesn't have to know the column
  // names.

  /// Fetch the signed-in caretaker's own profile fragment (relatives
  /// info). Returns {} when the user is not a caretaker (no rows).
  static Future<Map<String, dynamic>> getMyCaretakerProfile() async {
    try {
      final res = await client.rpc('get_my_caretaker_profile');
      if (res == null) return const {};
      return Map<String, dynamic>.from(res as Map);
    } catch (_) {
      return const {};
    }
  }

  /// Update the signed-in caretaker's own profile fragment.
  /// Pass null for any field you don't want to change; empty strings
  /// clear the column. Server enforces `role='caretaker'`.
  static Future<void> updateMyCaretakerProfile({
    String? fullName,
    String? username,
    String? bio,
    String? relationship,
    String? contactPhone,
    String? address,
    String? note,
    String? availability,
    bool? profileCompleted,
  }) async {
    final userId = currentUser?.id;
    if (userId == null) throw Exception('No authenticated user.');

    // 1. Update relatives-info fields via RPC
    await client.rpc('update_my_caretaker_profile', params: {
      'p_bio': bio,
      'p_relationship': relationship,
      'p_contact_phone': contactPhone,
      'p_address': address,
      'p_note': note,
      'p_availability': availability,
    });

    // 2. Update identity fields in user_profiles table directly
    if (fullName != null || username != null) {
      await client.from('user_profiles').update({
        if (fullName != null) 'full_name': fullName,
        if (username != null) 'username': username,
      }).eq('user_id', userId);
    }

    // 3. Mirror to auth metadata
    await updateAccountMeta(
      fullName: fullName,
      username: username,
      profileCompleted: profileCompleted,
    );

    // 4. Always mirror profileCompleted to the bdapps_users row AND
    //    the local session cache. Without this the post-login popup
    //    keeps firing forever because fetchProfile() reads
    //    bdapps_users first. We run it unconditionally so offline
    //    caretakers (no live auth session yet) still hit the local
    //    SharedPreferences cache.
    final effective = profileCompleted ?? true;
    if (effective) {
      try {
        await BdappsSessionService.instance
            .markProfileCompleted(value: true);
      } catch (e) {
        debugPrint(
            'updateMyCaretakerProfile: markProfileCompleted mirror failed: $e');
      }
    }
  }

  // ---------- Caretaker write passthrough (45_caretaker_care_doctor.sql + 56_caretaker_relatives_rename.sql) ----------
  // Mirrors the patient-only write RPCs but routes the call through
  // the caretaker's active link. The server impersonates the patient
  // for the duration of the write so the underlying patient RPC
  // accepts it without duplication.

  /// Log a meal on behalf of a patient.
  static Future<String> caretakerLogMealForPatient({
    required String patientUserId,
    required String mealSlot,
    String? foodId,
    required String foodNameBn,
    required String status, // 'eaten' | 'swap' | 'off_plan'
    required String impact, // 'good' | 'neutral' | 'bad'
    int? planDay,
    String? reason,
  }) async {
    final effectiveFoodId = (foodId != null && foodId.startsWith('custom::')) ? null : foodId;

    final res = await client.rpc('caretaker_log_meal_for_patient', params: {
      'p_patient_user_id': patientUserId,
      'p_meal_slot': mealSlot,
      'p_food_id': effectiveFoodId,
      'p_food_name_bn': foodNameBn,
      'p_status': status,
      'p_impact': impact,
      'p_plan_day': planDay,
      'p_reason': reason,
    });
    return res as String;
  }

  /// Log a water event on behalf of a patient.
  static Future<Map<String, dynamic>> caretakerLogWaterForPatient({
    required String patientUserId,
    required double deltaLiters,
  }) async {
    final res = await client.rpc('caretaker_log_water_for_patient', params: {
      'p_patient_user_id': patientUserId,
      'p_delta': deltaLiters,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  /// Mark a medicine dose on behalf of a patient.
  static Future<String> caretakerMarkDoseForPatient({
    required String patientUserId,
    required String medicineId,
    required DateTime doseDate,
    required String scheduledTime, // HH:mm
    String status = 'taken',
    String? note,
  }) async {
    final res = await client.rpc('caretaker_mark_dose_for_patient', params: {
      'p_patient_user_id': patientUserId,
      'p_medicine_id': medicineId,
      'p_dose_date': _dateOnly(doseDate),
      'p_scheduled_time': scheduledTime,
      'p_status': status,
      'p_note': note,
    });
    return res as String;
  }

  /// Add a medicine to a patient's catalogue on the caretaker's behalf.
  /// Returns the new medicine id.
  static Future<String> caretakerCreateMedicineForPatient({
    required String patientUserId,
    required String nameBn,
    String? nameEn,
    String form = 'tablet',
    String? strength,
    double doseAmount = 1,
    String doseUnit = 'unit',
    String mealRelation = 'any',
    required List<Map<String, String>> schedule,
    DateTime? startDate,
    DateTime? endDate,
    String? color,
    String? notes,
  }) async {
    final res = await client.rpc('caretaker_create_medicine_for_patient', params: {
      'p_patient_user_id': patientUserId,
      'p_name_bn': nameBn,
      'p_name_en': nameEn,
      'p_form': form,
      'p_strength': strength,
      'p_dose_amount': doseAmount,
      'p_dose_unit': doseUnit,
      'p_meal_relation': mealRelation,
      'p_schedule': schedule.map((m) => {'time': m['time'], 'bucket': ''}).toList(),
      'p_start_date': startDate == null ? null : _dateOnly(startDate),
      'p_end_date': endDate == null ? null : _dateOnly(endDate),
      'p_color': color,
      'p_notes': notes,
    });
    return res as String;
  }

  /// Update a patient's medicine. The server looks up the medicine's
  /// owner and authorizes against the caretaker's active link.
  static Future<void> caretakerUpdateMedicine({
    required String medicineId,
    String? nameBn,
    String? nameEn,
    String? form,
    String? strength,
    double? doseAmount,
    String? doseUnit,
    String? mealRelation,
    List<Map<String, String>>? schedule,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
    String? color,
    String? notes,
    bool? isActive,
  }) async {
    await client.rpc('caretaker_update_medicine', params: {
      'p_medicine_id': medicineId,
      'p_name_bn': nameBn,
      'p_name_en': nameEn,
      'p_form': form,
      'p_strength': strength,
      'p_dose_amount': doseAmount,
      'p_dose_unit': doseUnit,
      'p_meal_relation': mealRelation,
      'p_schedule': schedule?.map((m) => {'time': m['time'], 'bucket': ''}).toList(),
      'p_start_date': startDate == null ? null : _dateOnly(startDate),
      'p_end_date': endDate == null ? null : _dateOnly(endDate),
      'p_clear_end_date': clearEndDate,
      'p_color': color,
      'p_notes': notes,
      'p_is_active': isActive,
    });
  }

  /// Soft-delete a patient's medicine.
  static Future<void> caretakerDeleteMedicine(String medicineId) async {
    await client.rpc('caretaker_delete_medicine', params: {
      'p_medicine_id': medicineId,
    });
  }

  /// Create a custom meal-plan entry on the patient's calendar.
  /// Returns the new entry id.
  static Future<String> caretakerCreateMealPlanEntry({
    required String patientUserId,
    required DateTime effectiveDate,
    required String slot,
    String? scheduledTime, // HH:mm
    String? foodId,
    String? customFoodName,
    String? portionLabel,
    String? notes,
    int position = 0,
  }) async {
    final res = await client.rpc('caretaker_create_meal_plan_entry', params: {
      'p_patient_user_id': patientUserId,
      'p_effective_date': _dateOnly(effectiveDate),
      'p_slot': slot,
      'p_scheduled_time': scheduledTime,
      'p_food_id': foodId,
      'p_custom_food_name': customFoodName,
      'p_portion_label': portionLabel,
      'p_notes': notes,
      'p_position': position,
    });
    return res as String;
  }

  /// Update a patient's custom meal-plan entry.
  static Future<void> caretakerUpdateMealPlanEntry({
    required String planId,
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
    await client.rpc('caretaker_update_meal_plan_entry', params: {
      'p_plan_id': planId,
      'p_effective_date': effectiveDate == null ? null : _dateOnly(effectiveDate),
      'p_slot': slot,
      'p_scheduled_time': scheduledTime,
      'p_clear_scheduled_time': clearScheduledTime,
      'p_food_id': foodId,
      'p_clear_food_id': clearFoodId,
      'p_custom_food_name': customFoodName,
      'p_portion_label': portionLabel,
      'p_notes': notes,
      'p_position': position,
      'p_is_active': isActive,
    });
  }

  /// Soft-delete a patient's custom meal-plan entry.
  static Future<void> caretakerDeleteMealPlanEntry(String planId) async {
    await client.rpc('caretaker_delete_meal_plan_entry', params: {
      'p_plan_id': planId,
    });
  }

  /// Undo a meal-log entry the patient (or the caretaker earlier)
  /// recorded. Soft-hide so the history is preserved.
  static Future<void> caretakerHideMealIntake(String intakeId) async {
    await client.rpc('caretaker_hide_meal_intake', params: {
      'p_intake_id': intakeId,
    });
  }

  /// Caretaker write-passthrough for logging a meal on behalf of a
  /// patient. Server validates that the caller has an active link to
  /// [patientUserId] before allowing the write.
  ///
  /// The RPC is `record_meal_intake(meal_slot, food_id, food_name_bn,
  /// status, impact, notes, plan_day, reason, logged_by)`. The
  /// caretaker passes their own auth.uid() as `p_logged_by` and the
  /// server stamps `user_id = auth.uid()` (the caretaker) — but the
  /// `caretaker_can_write_for()` helper redirects ownership to the
  /// patient via the active link. Callers should pass a free-text
  /// "off-plan" status for the simplest caretaker flow.
  static Future<void> recordMealIntakeAsCaretaker({
    required String patientUserId,
    required String mealSlot,
    required String foodId,
    required String foodNameBn,
    required String status, // 'eaten' | 'swap' | 'off_plan'
    String? impact,        // 'good' | 'moderate' | 'bad'
    String? notes,
  }) async {
    await client.rpc('record_meal_intake', params: {
      'p_meal_slot': mealSlot,
      'p_food_id': foodId,
      'p_food_name_bn': foodNameBn,
      'p_status': status,
      'p_impact': impact,
      'p_notes': notes,
      'p_logged_by': currentUser?.id,
    });
  }

  /// Caretaker write-passthrough for marking a medicine dose on
  /// behalf of a patient.
  ///
  /// The RPC is `mark_dose(medicine_id, dose_date, scheduled_time,
  /// status, note, logged_by)`. The server picks the bucket from
  /// `scheduled_time`, so callers should pass the HH:mm string the
  /// medicine's schedule uses.
  static Future<void> markDoseAsCaretaker({
    required String patientUserId,
    required String medicineId,
    required DateTime doseDate,
    required String scheduledTime, // HH:mm
    required String status,        // 'taken'|'skipped'|'missed'
    String? note,
  }) async {
    await client.rpc('mark_dose', params: {
      'p_medicine_id': medicineId,
      'p_dose_date': _dateOnly(doseDate),
      'p_scheduled_time': scheduledTime,
      'p_status': status,
      'p_note': note,
      'p_logged_by': currentUser?.id,
    });
  }

  // ---------- Realtime ----------

  /// Subscribe to realtime broadcasts for the signed-in user's link
  /// inbox. The SQL trigger in `28_roles_and_caretaker.sql` adds the
  /// `caretaker_patient_links` table to the `supabase_realtime`
  /// publication, so any INSERT/UPDATE/DELETE on a row involving the
  /// caller fires the callback here.
  ///
  /// RLS on the table restricts which rows the caller's session can
  /// see — so a single `onPostgresChanges` binding without any filter
  /// naturally only fires for rows where auth.uid() matches either
  /// `caretaker_user_id` or `patient_user_id`. We used to register
  /// two bindings (one per side); that's redundant and fires the
  /// callback twice per event. One binding is enough.
  static RealtimeChannel subscribeToMyLinkEvents({
    required void Function() onChange,
  }) {
    final uid = currentUser?.id;
    final ch = client.channel('caretaker_link_${uid ?? 'anon'}');
    ch.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'caretaker_patient_links',
      callback: (_) => onChange(),
    );
    ch.subscribe();
    return ch;
  }

  /// Subscribe to "patient logged something" realtime events for the
  /// given [patientUserId].
  ///
  /// This Supabase project (per Realtime Inspector screenshot) is on
  /// Realtime < 2.0, so `realtime.send(jsonb)` private-channel
  /// broadcasts are NOT available. We use the
  /// `supabase_realtime` publication path instead:
  ///
  ///   1. `supabasesql/54_caretaker_realtime_subscription.sql` adds
  ///      the 7 data tables to the publication and grants the
  ///      caretaker session SELECT access only for rows whose
  ///      `user_id` is linked via an active `caretaker_patient_links`
  ///      row.
  ///   2. Each binding here filters by `user_id = patientUserId`, so
  ///      the channel only fires for THIS patient. If the caretaker
  ///      is connected to several patients, opening a separate
  ///      channel per patient keeps subscriptions scoped.
  ///
  /// The callback receives no payload — the screen just re-fetches
  /// its existing `get_caretaker_*` RPCs, which is the source of
  /// truth for the rendered numbers.
  static RealtimeChannel subscribeToPatientDataEvents({
    required String patientUserId,
    required void Function() onChange,
  }) {
    final uid = currentUser?.id;
    final ch = client.channel('caretaker_data_${uid ?? 'anon'}_$patientUserId');

    void bind({
      required String table,
    }) {
      // The payload arrives as PostgresChangePayload; we don't need
      // to read its fields because the screen re-fetches from RPC.
      ch.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: patientUserId,
        ),
        callback: (_) => onChange(),
      );
    }

    bind(table: 'meal_intake_log');
    bind(table: 'medicine_doses');
    bind(table: 'water_intake_log');
    bind(table: 'daily_metrics');
    bind(table: 'workout_sessions');
    bind(table: 'mood_entries');

    // workout_session_items has no user_id column of its own —
    // its parent session does. PostgresChangeFilter can only filter
    // by a column on the bound table, so we omit a server-side
    // filter here and rely on the SELECT RLS policy added in
    // `54_caretaker_realtime_subscription.sql`. The policy grants
    // access only for items whose session belongs to a linked
    // patient, so the binding can never deliver another patient's
    // row.
    ch.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'workout_session_items',
      callback: (_) => onChange(),
    );

    ch.subscribe();
    return ch;
  }

  // ---------- Blog / Details ----------

  /// Fetch every active blog post. The service layer sorts them, so
  /// we just filter by `is_active` here.
  static Future<List<BlogPostRow>> fetchBlogPosts() async {
    final resp = await client
        .from('blog_posts')
        .select()
        .eq('is_active', true);
    final list = (resp as List).cast<Map<String, dynamic>>();
    return list.map(BlogPostRow.fromJson).toList(growable: false);
  }

  // ---------- Notifications ----------

  /// RPC: list_active_notifications(p_limit int) → table.
  ///
  /// Returns the joined view of `notifications × notification_deliveries`
  /// for the current user. Side effect: lazily inserts a delivery row
  /// for any active broadcast the user has not yet seen.
  static Future<List<dynamic>> fetchActiveNotifications(
      {int limit = 50}) async {
    final resp = await client.rpc('list_active_notifications',
        params: {'p_limit': limit});
    return (resp as List).cast<Map<String, dynamic>>();
  }

  /// RPC: mark_notification_read(uuid) → void.
  static Future<void> markNotificationRead(String id) async {
    await client.rpc('mark_notification_read', params: {'p_id': id});
  }

  /// RPC: mark_notification_dismissed(uuid) → void.
  static Future<void> markNotificationDismissed(String id) async {
    await client.rpc('mark_notification_dismissed', params: {'p_id': id});
  }

  /// RPC: unread_notification_count() → bigint.
  static Future<int> unreadNotificationCount() async {
    final resp = await client.rpc('unread_notification_count');
    if (resp is num) return resp.toInt();
    return int.tryParse('${resp ?? 0}') ?? 0;
  }
}

/// Wire-format row from the `blog_posts` table. Converted into the
/// UI-facing model via [BlogPostRow.toArticle].
class BlogPostRow {
  final String id;
  final String slug;
  final String? titleEn;
  final String titleBn;
  final String summaryBn;
  final String dekBn;
  final String badge;
  final String dateLabel;
  final String readTimeLabel;
  final String? heroImageUrl;
  final String? thumbImageUrl;
  final String? ctaLabel;
  final bool isActive;
  final bool isFeatured;
  final int sortOrder;
  final List<Map<String, String>> sections;
  final List<String> canDo;
  final DateTime createdAt;

  BlogPostRow({
    required this.id,
    required this.slug,
    required this.titleEn,
    required this.titleBn,
    required this.summaryBn,
    required this.dekBn,
    required this.badge,
    required this.dateLabel,
    required this.readTimeLabel,
    required this.heroImageUrl,
    required this.thumbImageUrl,
    required this.ctaLabel,
    required this.isActive,
    required this.isFeatured,
    required this.sortOrder,
    required this.sections,
    required this.canDo,
    required this.createdAt,
  });

  factory BlogPostRow.fromJson(Map<String, dynamic> j) {
    List<Map<String, String>> decodeSections(dynamic raw) {
      if (raw is! List) return const [];
      return raw.map((e) {
        final m = (e as Map).cast<String, dynamic>();
        return {
          'heading': (m['heading'] ?? '').toString(),
          'body': (m['body'] ?? '').toString(),
        };
      }).toList(growable: false);
    }

    List<String> decodeCanDo(dynamic raw) {
      if (raw is! List) return const [];
      return raw.map((e) => e.toString()).toList(growable: false);
    }

    DateTime decodeCreated(dynamic raw) {
      if (raw is String) {
        return DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    String? opt(dynamic v) {
      if (v == null) return null;
      final s = v.toString();
      return s.isEmpty ? null : s;
    }

    int toInt(dynamic v, int fallback) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    bool toBool(dynamic v, bool fallback) {
      if (v is bool) return v;
      if (v is String) {
        final s = v.toLowerCase();
        if (s == 'true' || s == 't' || s == '1') return true;
        if (s == 'false' || s == 'f' || s == '0') return false;
      }
      return fallback;
    }

    return BlogPostRow(
      id: (j['id'] ?? '').toString(),
      slug: (j['slug'] ?? '').toString(),
      titleEn: opt(j['title_en']),
      titleBn: (j['title_bn'] ?? '').toString(),
      summaryBn: (j['summary_bn'] ?? '').toString(),
      dekBn: (j['dek_bn'] ?? '').toString(),
      badge: (j['badge'] ?? '').toString(),
      dateLabel: (j['date_label'] ?? '').toString(),
      readTimeLabel: (j['read_time_label'] ?? '').toString(),
      heroImageUrl: opt(j['hero_image_url']),
      thumbImageUrl: opt(j['thumb_image_url']),
      ctaLabel: opt(j['cta_label']),
      isActive: toBool(j['is_active'], true),
      isFeatured: toBool(j['is_featured'], false),
      sortOrder: toInt(j['sort_order'], 100),
      sections: decodeSections(j['sections']),
      canDo: decodeCanDo(j['can_do']),
      createdAt: decodeCreated(j['created_at']),
    );
  }

  /// Wire DTO → UI-facing [BlogArticle].
  BlogArticle toArticle() {
    final uiSections = sections
        .where((m) => m['heading']?.isNotEmpty == true)
        .map((m) => BlogSection(heading: m['heading'] ?? '', body: m['body'] ?? ''))
        .toList(growable: false);
    return BlogArticle(
      id: slug,
      titleEn: titleEn ?? '',
      titleBn: titleBn,
      summaryBn: summaryBn,
      dekBn: dekBn,
      badge: badge,
      dateLabel: dateLabel,
      readTimeLabel: readTimeLabel,
      sections: uiSections,
      canDo: canDo,
      ctaLabel: ctaLabel,
      isFeatured: isFeatured,
      isActive: isActive,
      sortOrder: sortOrder,
      createdAt: createdAt,
      heroImageUrl: heroImageUrl,
      thumbImageUrl: thumbImageUrl,
    );
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
