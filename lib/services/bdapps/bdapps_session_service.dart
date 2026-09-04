import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../supabase_service.dart';
import 'bdapps_service.dart';

/// BDApps session — a minimal, **local-only** session cache.
///
/// We deliberately do NOT touch Supabase auth. BDApps users are
/// identified by their canonical BD mobile number (8801XXXXXXXXX).
/// On login we cache (mobile, role) in SharedPreferences and the
/// app gates navigation on [isSignedIn]. A row in `public.bdapps_users`
/// holds the same fields on the server so other screens can look up
/// the profile by mobile without an auth context.
///
/// Flow:
///   1. User types mobile → BdappsService.sendOtp is called.
///   2. If PHP returns E1351 "already registered", we skip OTP and
///      call [loginOrSignup] directly with referenceNo=null.
///   3. Otherwise user types OTP → BdappsService.verifyOtp → on
///      S1000 / REGISTERED, call [loginOrSignup].
///   4. [loginOrSignup] RPC-upserts a `bdapps_users` row, returns it,
///      and we persist (mobile, role, profileCompleted) locally.
///   5. App reads [isSignedIn] / [role] / [mobile] to decide what to
///      show on launch.
class BdappsSessionService {
  BdappsSessionService._();

  static final BdappsSessionService instance = BdappsSessionService._();

  static const _kRole = 'bdapps.role';
  static const _kProfileCompleted = 'bdapps.profileCompleted';
  static const _kMobile = 'bdapps.mobile';

  String? _role;
  bool _profileCompleted = false;
  String? _mobile;

  String? get role => _role;
  bool get profileCompleted => _profileCompleted;
  String? get mobile => _mobile;

  /// True when we have at least a (mobile, role) cached AND a real
  /// Supabase auth session is established. The Supabase auth check is
  /// what matters for downstream RPCs (they all use auth.uid()); the
  /// local cache just lets us pick the right role/profile-completed
  /// state to render.
  bool get isSignedIn =>
      _mobile != null &&
      _mobile!.isNotEmpty &&
      SupabaseService.isInitialized &&
      SupabaseService.client.auth.currentSession != null;

  /// Hydrate the in-memory cache from disk. Call once on app start.
  /// If we have a cached mobile but no live Supabase session (typical
  /// after a cold start), try to re-establish the session by calling
  /// `bdapps_create_shadow_auth` again — it will rotate the password
  /// and return credentials for signInWithPassword.
  Future<void> hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    _role = prefs.getString(_kRole);
    _profileCompleted = prefs.getBool(_kProfileCompleted) ?? false;
    _mobile = prefs.getString(_kMobile);
    debugPrint(
        '[BdappsSession] hydrate role=$_role mobile=$_mobile completed=$_profileCompleted');

    if (_mobile == null || _mobile!.isEmpty) return;
    if (!SupabaseService.isInitialized) return;

    final hasSession =
        SupabaseService.client.auth.currentSession != null;
    if (hasSession) {
      debugPrint('[BdappsSession] live Supabase session present, skipping re-auth');
      return;
    }

    debugPrint('[BdappsSession] no live session — re-establishing for $_mobile');
    try {
      final dynamic shadow = await SupabaseService.client
          .rpc('bdapps_create_shadow_auth', params: {'p_mobile': _mobile})
          .timeout(const Duration(seconds: 15));
      Map<String, dynamic>? row;
      if (shadow is List && shadow.isNotEmpty && shadow.first is Map) {
        row = Map<String, dynamic>.from(shadow.first);
      } else if (shadow is Map) {
        row = Map<String, dynamic>.from(shadow);
      }
      final email = row?['email']?.toString();
      final password = row?['password']?.toString();
      if (email == null || password == null) {
        debugPrint('[BdappsSession] shadow re-auth returned no credentials');
        return;
      }
      await SupabaseService.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      debugPrint('[BdappsSession] session restored for $email');
    } catch (e, st) {
      debugPrint('[BdappsSession] hydrate re-auth failed: $e\n$st');
    }
  }

  /// Server-side subscription gate.
  ///
  /// Called on every cold-start AFTER [hydrate]. If the cached mobile
  /// is no longer `REGISTERED` (e.g. the user unsubscribed from the
  /// website, or the operator flipped them to `UNREGISTERED`), we
  /// tear down the local session so the gate in `main.dart` shows the
  /// landing screen instead of letting them use the app for free.
  ///
  /// This closes the gap where a web-only unsubscribe would otherwise
  /// leave the app signed-in indefinitely (the cached Supabase auth
  /// session + SharedPreferences would survive until the user manually
  /// tapped "logout" in the profile).
  ///
  /// **Tolerant of network failures**: if the BDApps lookup endpoint
  /// is unreachable or returns a malformed payload, we KEEP the
  /// cached session — a network outage should not log users out.
  /// They can always tap "Check subscription" inside the app to
  /// re-trigger verification.
  ///
  /// Returns `true` when the local session is intact (still active OR
  /// couldn't be verified), `false` when the server confirmed the
  /// number is `UNREGISTERED` and we tore it down.
  Future<bool> verifyAndGateSession() async {
    final m = _mobile;
    if (m == null || m.isEmpty) {
      // Nothing cached — there's no session to gate.
      return true;
    }
    try {
      final res = await BdappsService.checkSubscription(m)
          .timeout(const Duration(seconds: 8));
      final active = BdappsService.isUserActive(res);
      final status = (res['subscriptionStatus'] ?? '')
          .toString()
          .toUpperCase()
          .trim();
      debugPrint(
          '[BdappsSession] verifyAndGateSession mobile=$m status=$status active=$active');

      if (active) {
        // Still subscribed (REGISTERED / GRACE / INITIAL CHARGING
        // PENDING / etc.). Keep the session.
        return true;
      }

      // Server says UNREGISTERED (or empty). Tear down locally so the
      // gate in main.dart flips to the landing screen.
      debugPrint(
          '[BdappsSession] server says UNREGISTERED — forcing local sign-out');
      await signOut();
      // Stash a transient flag the landing screen reads to surface a
      // "resubscribe to continue" toast on its first frame.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('bdapps.unsubscribedFromServer', true);
      return false;
    } catch (e, st) {
      debugPrint(
          '[BdappsSession] verifyAndGateSession lookup failed (keeping session): $e\n$st');
      // Network / parsing failure: keep the cached session.
      return true;
    }
  }

  /// True when the user was just bounced out by [verifyAndGateSession]
  /// because the server reported `UNREGISTERED`. Cleared after the
  /// landing screen reads it so it doesn't re-show on the next
  /// cold-start.
  static Future<bool> consumeUnsubscribedNotice() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool('bdapps.unsubscribedFromServer') ?? false;
    if (v) {
      await prefs.remove('bdapps.unsubscribedFromServer');
    }
    return v;
  }

  /// After BDApps OTP success (or E1351 already-registered): look up
  /// or create the `bdapps_users` row, then establish a real Supabase
  /// auth session so RPCs that use `auth.uid()` work.
  ///
  /// Flow:
  ///   1. `bdapps_lookup_or_create(p_mobile, p_role)` — idempotent
  ///      INSERT/SELECT on the lightweight bdapps_users table.
  ///   2. `bdapps_create_shadow_auth(p_mobile)` — creates (or rotates)
  ///      an `auth.users` shadow row with a bcrypt-hashed password and
  ///      returns (email, password) the client uses to sign in.
  ///   3. `supabase.auth.signInWithPassword(email, password)` — issues
  ///      a real session that all other RPCs recognize via auth.uid().
  ///   4. Persist (mobile, role, profileCompleted) locally so the app
  ///      gate can render the right shell on next launch.
  Future<BdappsLoginResult> loginOrSignup({
    required String mobile,
    required String role,
  }) async {
    if (!SupabaseService.isInitialized) {
      debugPrint('[BdappsSession] Supabase not initialized');
      return BdappsLoginResult.failure('Supabase is not initialized.');
    }
    final client = SupabaseService.client;

    // ---------- Step 1: upsert bdapps_users row ----------
    debugPrint(
        '[BdappsSession] calling bdapps_lookup_or_create mobile=$mobile role=$role');
    final dynamic raw;
    try {
      raw = await client.rpc(
        'bdapps_lookup_or_create',
        params: {'p_mobile': mobile, 'p_role': role},
      ).timeout(const Duration(seconds: 15));
    } catch (e, st) {
      debugPrint('[BdappsSession] bdapps_lookup_or_create failed: $e\n$st');
      return BdappsLoginResult.failure(
          'Could not create your account: ${e.toString()}');
    }
    debugPrint('[BdappsSession] bdapps_lookup_or_create returned: $raw');

    Map<String, dynamic>? row;
    if (raw is Map<String, dynamic>) {
      row = raw;
    } else if (raw is Map) {
      row = Map<String, dynamic>.from(raw);
    } else if (raw is List && raw.isNotEmpty) {
      final first = raw.first;
      row = first is Map ? Map<String, dynamic>.from(first) : null;
    }
    if (row == null) {
      return BdappsLoginResult.failure(
          'Server returned no record (response was ${raw.runtimeType}).');
    }

    final serverMobile = (row['mobile'] ?? mobile).toString();
    final serverRole = (row['role'] ?? role).toString();
    final completed = row['profile_completed'] == true;

    // ---------- Step 2: create / rotate the auth.users shadow row ----------
    String? authEmail;
    String? authPassword;
    String? lastShadowPayload;
    try {
      final dynamic shadow = await client
          .rpc('bdapps_create_shadow_auth',
              params: {'p_mobile': serverMobile})
          .timeout(const Duration(seconds: 15));
      debugPrint('[BdappsSession] bdapps_create_shadow_auth returned: $shadow');
      lastShadowPayload = shadow?.toString();
      Map<String, dynamic>? shadowRow;
      if (shadow is List && shadow.isNotEmpty) {
        shadowRow = shadow.first is Map ? Map<String, dynamic>.from(shadow.first) : null;
      } else if (shadow is Map) {
        shadowRow = Map<String, dynamic>.from(shadow);
      }
      if (shadowRow != null) {
        authEmail = shadowRow['email']?.toString();
        authPassword = shadowRow['password']?.toString();
      }
    } catch (e, st) {
      debugPrint('[BdappsSession] bdapps_create_shadow_auth failed: $e\n$st');
      return BdappsLoginResult.failure(
          'Could not create your account session: ${e.toString()}');
    }
    if (authEmail == null || authPassword == null) {
      return BdappsLoginResult.failure(
          'Server did not return an auth credential (response was ${lastShadowPayload ?? 'null'}).');
    }

    // ---------- Step 3: sign in to Supabase auth ----------
    try {
      await client.auth.signInWithPassword(
        email: authEmail,
        password: authPassword,
      );
      debugPrint(
          '[BdappsSession] Supabase auth session established for $authEmail');
    } catch (e, st) {
      debugPrint('[BdappsSession] signInWithPassword failed: $e\n$st');
      return BdappsLoginResult.failure(
          'Could not sign you in: ${e.toString()}');
    }

    // ---------- Step 4: persist locally so the app gate renders ----------
    await _persist(
      mobile: serverMobile,
      role: serverRole,
      profileCompleted: completed,
    );

    return BdappsLoginResult.success(
      mobile: serverMobile,
      role: serverRole,
      profileCompleted: completed,
    );
  }

  Future<void> _persist({
    required String mobile,
    required String role,
    required bool profileCompleted,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMobile, mobile);
    await prefs.setString(_kRole, role);
    await prefs.setBool(_kProfileCompleted, profileCompleted);
    _mobile = mobile;
    _role = role;
    _profileCompleted = profileCompleted;
    debugPrint(
        '[BdappsSession] persisted mobile=$mobile role=$role completed=$profileCompleted');
  }

  /// Re-read the profile_completed flag from the server. Call after
  /// onboarding so the persistent banner goes away.
  Future<void> refreshProfileCompleted({required bool value}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kProfileCompleted, value);
    _profileCompleted = value;
  }

  Future<void> markProfileCompleted({bool value = true}) async {
    final m = mobile;
    if (m != null && SupabaseService.isInitialized) {
      try {
        await SupabaseService.client.rpc('bdapps_mark_profile_completed',
            params: {'p_mobile': m, 'p_value': value});
      } catch (e) {
        debugPrint('bdapps_mark_profile_completed failed: $e');
      }
    }
    await refreshProfileCompleted(value: value);
  }

  Future<void> signOut() async {
    // Tear down the Supabase auth session first so the gate in main.dart
    // sees the change immediately (no stale auth.currentSession keeping
    // the shell mounted).
    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client.auth.signOut();
      } catch (e) {
        debugPrint('[BdappsSession] auth.signOut failed (continuing): $e');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kMobile);
    await prefs.remove(_kRole);
    await prefs.remove(_kProfileCompleted);
    _mobile = null;
    _role = null;
    _profileCompleted = false;
  }

  /// Permanently wipe the user's BDApps subscription + server-side data.
  ///
  /// Steps (each best-effort — we still call [signOut] locally even if
  /// some steps fail so the user lands on the landing screen):
  ///   1. Call BDApps `unsubscribe.php` so the operator stops charging.
  ///   2. Call RPC `bdapps_delete_account(p_mobile)` which deletes the
  ///      `auth.users` shadow row (cascade wipes every domain table)
  ///      and the standalone `bdapps_users` row.
  ///   3. Local [signOut] — clears SharedPreferences + Supabase session.
  ///
  /// Returns [BdappsDeleteAccountResult.success] when at least the
  /// local sign-out ran. The `errorMessage` is non-null only when
  /// the call aborted before sign-out (e.g. no mobile on file).
  Future<BdappsDeleteAccountResult> deleteAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final mobile = _mobile ?? prefs.getString(_kMobile);
    if (mobile == null || mobile.isEmpty) {
      return const BdappsDeleteAccountResult.failure(
          'No mobile number on file.');
    }

    // 1. BDApps unsubscribe — best-effort. A failure here (e.g. user
    //    is already unsubscribed, or operator is unreachable) should
    //    not block the local wipe.
    try {
      final res = await BdappsService.unsubscribe(mobile);
      debugPrint('[BdappsSession] deleteAccount unsubscribe response: $res');
    } catch (e) {
      debugPrint(
          '[BdappsSession] deleteAccount unsubscribe failed (continuing): $e');
    }

    // 2. RPC delete — needs a live auth session so auth.uid() matches
    //    the shadow row's id. If we don't have a session (already
    //    signed out elsewhere), just skip — the bdapps_users row may
    //    still be left behind but the user can still log out.
    if (SupabaseService.isInitialized &&
        SupabaseService.client.auth.currentSession != null) {
      try {
        final raw = await SupabaseService.client
            .rpc('bdapps_delete_account', params: {'p_mobile': mobile})
            .timeout(const Duration(seconds: 15));
        debugPrint('[BdappsSession] deleteAccount rpc result: $raw');
      } catch (e, st) {
        debugPrint('[BdappsSession] deleteAccount rpc failed: $e\n$st');
      }
    } else {
      debugPrint(
          '[BdappsSession] deleteAccount skipped rpc — no live Supabase session');
    }

    // 3. Local sign-out (always runs).
    await signOut();
    return const BdappsDeleteAccountResult.success();
  }

  /// Convenience helper for debugging — emits the last known session
  /// payload as JSON.
  String debugLastSession() {
    return jsonEncode({
      'role': _role,
      'mobile': _mobile,
      'profileCompleted': _profileCompleted,
    });
  }
}

/// Result of a BDApps login attempt.
class BdappsLoginResult {
  final bool success;
  final String? mobile;
  final String? role;
  final bool profileCompleted;
  final String? errorMessage;

  const BdappsLoginResult({
    required this.success,
    this.mobile,
    this.role,
    this.profileCompleted = false,
    this.errorMessage,
  });

  factory BdappsLoginResult.success({
    required String mobile,
    required String role,
    required bool profileCompleted,
  }) {
    return BdappsLoginResult(
      success: true,
      mobile: mobile,
      role: role,
      profileCompleted: profileCompleted,
    );
  }

  factory BdappsLoginResult.failure(String message) {
    return BdappsLoginResult(success: false, errorMessage: message);
  }
}

/// Result of a delete-account attempt. `success` is true when the local
/// sign-out ran (and we therefore cleared SharedPreferences + Supabase
/// session). `errorMessage` is non-null only when the call aborted
/// before sign-out — for a best-effort flow that's almost always
/// "no mobile on file".
class BdappsDeleteAccountResult {
  final bool success;
  final String? errorMessage;
  const BdappsDeleteAccountResult({
    required this.success,
    this.errorMessage,
  });

  const BdappsDeleteAccountResult.success()
      : this(success: true);

  const BdappsDeleteAccountResult.failure(String message)
      : this(success: false, errorMessage: message);
}
