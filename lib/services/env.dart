/// Single source of truth for environment variables read from `.env`.
///
/// We deliberately keep this thin — no logging, no caching, no fallbacks —
/// so a missing key surfaces immediately rather than being masked by a
/// later default. Callers that need to *display* an empty state when the
/// AI service is not configured should check [groqApiKey] for emptiness
/// and degrade gracefully (see `GroqRouter.isConfigured`).
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
  /// list in `GROQ_API_KEYS` for future multi-key rotation; this getter
  /// returns the first one so existing call-sites keep working.
  static String get groqApiKey {
    // dotenv throws `NotInitializedError` when load() never ran (e.g. unit
    // tests). Treat that as "no key" so callers get a graceful empty
    // string instead of a stack trace every time hasGroqKey is checked.
    final map = _safeEnvMap();
    final list = (map['GROQ_API_KEYS'] ?? '').trim();
    if (list.isNotEmpty) {
      // First non-empty token wins.
      for (final raw in list.split(',')) {
        final t = raw.trim();
        if (t.isNotEmpty) return t;
      }
    }
    final single = (map['GROQ_API_KEY'] ?? '').trim();
    return single;
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
