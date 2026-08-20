/// SharedPreferences mirror of `check_and_increment_prompt_quota`.
///
/// The server is the source of truth (the user can't bypass the quota
/// by clearing app data because the RPC atomically increments before
/// we ever touch `shared_preferences`). This cache is purely there so:
///   * the welcome screen can render the "৩/৫ আজ" pill *immediately* on
///     cold start without a network round-trip,
///   * a 6th tap shows the "আজকের ৫টি প্রশ্ম শেষ" toast even when the
///     device is offline.
///
/// Server reads are non-mutating (`get_prompt_quota`) so we never
/// accidentally double-count by polling.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
// supabase_flutter types are re-exported via SupabaseService.currentUser
// (which is already a `User?`) and via SupabaseService.client.rpc(...),
// so this file no longer needs the direct package import.

import 'app_events.dart';
import 'supabase_service.dart';

/// Snapshot of today's quota.
class AiChatQuota {
  const AiChatQuota({
    required this.used,
    required this.limit,
    required this.resetsAt,
    required this.lastFetched,
    required this.cacheHit,
  });

  /// Convenience: how many prompts the user can still send.
  int get remaining => (limit - used).clamp(0, limit);

  /// True iff the user has hit the cap.
  bool get isExhausted => used >= limit;

  /// True iff we have a cached value to render before the server
  /// round-trip completes. The cache is *authoritative* only after
  /// [warmUp] has resolved.
  final bool cacheHit;

  final int used;
  final int limit;
  final DateTime resetsAt;
  final DateTime lastFetched;

  Map<String, dynamic> toJson() => {
        'used': used,
        'limit': limit,
        'resetsAt': resetsAt.toIso8601String(),
        'lastFetched': lastFetched.toIso8601String(),
      };

  static AiChatQuota fromJson(Map<String, dynamic> j) => AiChatQuota(
        used: (j['used'] as num?)?.toInt() ?? 0,
        limit: (j['limit'] as num?)?.toInt() ?? 5,
        resetsAt: DateTime.tryParse(j['resetsAt'] as String? ?? '') ??
            DateTime.now().toUtc(),
        lastFetched: DateTime.tryParse(j['lastFetched'] as String? ?? '') ??
            DateTime.now().toUtc(),
        cacheHit: false,
      );

  AiChatQuota copyWith({int? used, DateTime? lastFetched, bool? cacheHit}) =>
      AiChatQuota(
        used: used ?? this.used,
        limit: limit,
        resetsAt: resetsAt,
        lastFetched: lastFetched ?? this.lastFetched,
        cacheHit: cacheHit ?? this.cacheHit,
      );

  /// A blank quota we hand to listeners before the first real fetch
  /// resolves. We mark `cacheHit=false` so the UI knows the value is a
  /// placeholder, not a stale cache read.
  static AiChatQuota empty(int limit) => AiChatQuota(
        used: 0,
        limit: limit,
        resetsAt: DateTime.now().toUtc(),
        lastFetched: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        cacheHit: false,
      );
}

class AiChatQuotaCache extends ChangeNotifier
    implements ValueListenable<AiChatQuota> {
  AiChatQuotaCache._({required this.limit});

  static const String _prefsKeyPrefix = 'ai_chat_quota';

  final int limit;

  /// Singleton so multiple screens can listen without juggling refs.
  static AiChatQuotaCache? _instance;
  static AiChatQuotaCache get instance =>
      _instance ??= AiChatQuotaCache._(limit: 5);

  /// Reset the singleton (used by tests).
  @visibleForTesting
  static void resetInstanceForTest() => _instance = null;

  AiChatQuota _value = AiChatQuota.empty(5);

  @override
  AiChatQuota get value => _value;

  /// Key for the *current* day in the device's local time. The server
  /// uses Asia/Dhaka but the cache key needs to match the calendar day
  /// the user perceives. We use local time for the key and store the
  /// server's authoritative `resetsAt` for display.
  String _todayKey() {
    final n = DateTime.now();
    final d = DateTime(n.year, n.month, n.day);
    return d.toIso8601String().substring(0, 10);
  }

  String _prefsKey() => '$_prefsKeyPrefix:${_todayKey()}';

  /// Notify listeners that the quota changed (e.g. after a successful
  /// send). Bumps `AppEvents.aiChatQuotaChanged` so out-of-screen
  /// listeners (dashboard badge) can refresh.
  void _publish(AiChatQuota next) {
    _value = next;
    AppEvents.notifyAiChatQuotaChanged();
    notifyListeners();
  }

  /// Read whatever the cache has without talking to the server.
  /// Used at boot to render an instant "৩/৫ আজ" pill.
  Future<void> readFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey());
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _publish(AiChatQuota.fromJson(j).copyWith(cacheHit: true));
    } catch (_) {
      // Stale / corrupt cache — drop it; the server fetch will fix it.
      await prefs.remove(_prefsKey());
    }
  }

  /// Non-mutating fetch from the server. Safe to call on app start.
  /// On failure we keep whatever was in the cache (if anything).
  Future<AiChatQuota> warmUp({int limit = 5}) async {
    final prefs = await SharedPreferences.getInstance();
    // Use the self-healing SupabaseService.client so a hot-restart that
    // wiped the static field doesn't break the quota warmup. Falls
    // through to the cache value if the singleton truly isn't there.
    if (!SupabaseService.isInitialized) return _value;
    final user = SupabaseService.currentUser;
    if (user == null) return _value;

    try {
      final res = await SupabaseService.client.rpc(
        'get_prompt_quota',
        params: {'p_user_id': user.id, 'p_limit': limit},
      );
      final next = _fromRpc(res, limit: limit);
      await prefs.setString(_prefsKey(), jsonEncode(next.toJson()));
      _publish(next);
      return next;
    } catch (e) {
      debugPrint('⚠️ [AiChatQuotaCache] warmUp failed: $e');
      return _value;
    }
  }

  /// Called *after* the server's `check_and_increment_prompt_quota` has
  /// actually counted the new prompt. We update the cache so the UI
  /// reflects the new count without a round-trip on the next render.
  Future<void> recordConsumption({int? newUsed, int limit = 5}) async {
    final prefs = await SharedPreferences.getInstance();
    final next = _value.copyWith(
      used: newUsed ?? (_value.used + 1).clamp(0, limit),
      lastFetched: DateTime.now().toUtc(),
    );
    await prefs.setString(_prefsKey(), jsonEncode(next.toJson()));
    _publish(next);
  }

  /// Wipe today's cache (used after a successful `clear_ai_chat_history`
  /// when the user expects a fresh slate — though clearing the chat
  /// doesn't actually touch the quota, we expose this for completeness).
  Future<void> reset({int limit = 5}) async {
    final prefs = await SharedPreferences.getInstance();
    final fresh = AiChatQuota.empty(limit);
    await prefs.setString(_prefsKey(), jsonEncode(fresh.toJson()));
    _publish(fresh);
  }

  /// Pre-flight check on the client side. Even if the cache says the
  /// user is at the cap, the server is still authoritative — but
  /// showing the "আজকের ৫টি প্রশ্ন শেষ" toast without a round-trip
  /// keeps the UI snappy.
  bool get isExhaustedLocally => _value.isExhausted;

  AiChatQuota _fromRpc(dynamic res, {required int limit}) {
    // Supabase RPC returns either a List (when RETURNS TABLE) or a
    // single Map. Handle both shapes defensively.
    Map<String, dynamic>? row;
    if (res is List && res.isNotEmpty) {
      row = Map<String, dynamic>.from(res.first as Map);
    } else if (res is Map) {
      row = Map<String, dynamic>.from(res);
    }
    if (row == null) {
      return _value.copyWith(lastFetched: DateTime.now().toUtc());
    }
    final used = (row['used'] as num?)?.toInt() ?? 0;
    final lim = (row['limit_val'] as num?)?.toInt() ?? limit;
    final resets = DateTime.tryParse(row['resets_at'] as String? ?? '') ??
        DateTime.now().toUtc();
    return AiChatQuota(
      used: used,
      limit: lim,
      resetsAt: resets,
      lastFetched: DateTime.now().toUtc(),
      cacheHit: false,
    );
  }
}