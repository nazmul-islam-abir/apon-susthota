/// Single source of truth for environment variables read from `.env`.
///
/// We deliberately keep this thin — no logging, no caching, no fallbacks —
/// so a missing key surfaces immediately rather than being masked by a
/// later default. Callers that need to *display* an empty state when the
/// AI service is not configured should check [groqApiKey] for emptiness
/// and degrade gracefully (see `GroqRouter.isConfigured`).
///
/// ---
/// Multi-account rotation (used by `GroqKeyPool`):
///
/// To multiply effective rate limits, list multiple keys — each must
/// belong to a separate Groq organization (separate Gmail/SSO). Two keys
/// under the same org share one quota pool, so adding a second key in
/// the same org does nothing.
///
/// Paste this into your local `.env` (gitignored):
///
/// ```ini
/// # Multi-account rotation (one per Groq org). The first key is the
/// # primary; the others are tried in order whenever the primary hits
/// # a 429. A 401/403 on a key permanently retires it for this session.
/// GROQ_API_KEYS=gsk_personal_a,gsk_work_b,gsk_backup_c
/// GROQ_API_KEY_LABELS=personal,work,backup
///
/// # Legacy single-key form still works as a fallback:
/// # GROQ_API_KEY=gsk_personal_a
/// ```
///
/// NEVER commit `.env` to source control — it's already covered by the
/// repo's `.gitignore`. If a key ever appears in chat / logs / a PR
/// description, treat it as compromised and rotate it in the Groq
/// console immediately.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Accessors for runtime configuration values loaded by
/// `SupabaseService.init()` (which calls `dotenv.load()` first).
///
/// We never expose the raw `Map<String, String>` — callers get typed
/// accessors so a typo in the env key becomes a compile error here
/// instead of a runtime null-check scattered through the app.
class Env {
  Env._();

  /// Groq API key. Multiple keys may be supplied as a comma-separated
  /// list in `GROQ_API_KEYS` for multi-account rotation; this getter
  /// returns the first one so existing call-sites keep working.
  ///
  /// **Prefer [groqApiKeys] when you need rotation.** This getter is
  /// kept for legacy single-key call-sites that don't yet know about
  /// the pool (e.g. build-time checks).
  static String get groqApiKey => groqApiKeys.isEmpty ? '' : groqApiKeys.first;

  /// All configured Groq API keys, in declaration order.
  ///
  /// Source priority:
  ///   1. `GROQ_API_KEYS` — comma-separated list (recommended for
  ///      multi-account rotation). Whitespace around each token is
  ///      trimmed; empty tokens are skipped.
  ///   2. `GROQ_API_KEY` — single key (legacy). Wrapped into a
  ///      one-element list so the pool still works.
  ///
  /// Returns an empty list if nothing is configured so callers can
  /// gracefully degrade to a "not configured" placeholder.
  static List<String> get groqApiKeys {
    final map = _safeEnvMap();
    final list = (map['GROQ_API_KEYS'] ?? '').trim();
    if (list.isNotEmpty) {
      final out = <String>[];
      for (final raw in list.split(',')) {
        final t = raw.trim();
        if (t.isNotEmpty) out.add(t);
      }
      if (out.isNotEmpty) return out;
    }
    final single = (map['GROQ_API_KEY'] ?? '').trim();
    return single.isEmpty ? const <String>[] : <String>[single];
  }

  /// Optional human-friendly labels for each key (parallel to
  /// [groqApiKeys]). Sourced from `GROQ_API_KEY_LABELS` as a
  /// comma-separated list. Useful when logging which account replied.
  ///
  /// Falls back to "key1", "key2", … when fewer labels are provided
  /// than keys, so callers can always log something stable.
  static List<String> get groqKeyLabels {
    final map = _safeEnvMap();
    final raw = (map['GROQ_API_KEY_LABELS'] ?? '').trim();
    final labels = <String>[];
    if (raw.isNotEmpty) {
      for (final t in raw.split(',')) {
        final v = t.trim();
        if (v.isNotEmpty) labels.add(v);
      }
    }
    final keys = groqApiKeys;
    while (labels.length < keys.length) {
      labels.add('key${labels.length + 1}');
    }
    return labels;
  }

  /// Wraps [DotEnv.env] so a missing `load()` doesn't blow up unit tests.
  static Map<String, String> _safeEnvMap() {
    try {
      return dotenv.env;
    } catch (_) {
      return const <String, String>{};
    }
  }

  /// True iff a non-empty Groq key is present. Use to short-circuit the
  /// AI tab to a "not configured" placeholder instead of throwing on
  /// every request.
  static bool get hasGroqKey => groqApiKey.isNotEmpty;

  /// Debug-only redacted key (first 6 chars + "…") safe to print.
  static String get groqApiKeyDebug {
    final k = groqApiKey;
    if (k.isEmpty) return '(empty)';
    if (k.length <= 8) return '…';
    return '${k.substring(0, 6)}…';
  }

  /// Called once during app boot so misconfigured deployments fail
  /// loudly instead of waiting for the first AI request.
  static void debugReport() {
    debugPrint('🔑 [Env] GROQ_API_KEY=${hasGroqKey ? groqApiKeyDebug : '(missing)'}');
  }
}
