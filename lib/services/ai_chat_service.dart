/// Top-level orchestrator for the AI chat feature.
///
/// One call to [AiChatService.sendPrompt] does the whole pipeline:
///
///   1. `check_and_increment_prompt_quota` — server-authoritative
///      5/day cap (the client cache is only a hint).
///   2. `get_ai_chat_context` — pull the user profile, today's
///      medicines, meal adherence, workout, water/HR/steps so the
///      system prompt can answer personalised questions.
///   3. Build a Bangla system prompt (~300 tokens) and the last 8
///      turns of conversation history.
///   4. `GroqRouter.safetyCheck` — pre-flight via
///      `llama-prompt-guard-2-22m`. If it flags the input, we reply
///      politely in Bangla without burning a chat model call.
///   5. `GroqRouter.send` — rotate through 6 Groq chat models with
///      SSE streaming.
///   6. `save_ai_chat_message` — persist user + assistant rows so the
///      next turn has context.
///
/// No state lives here — every call is independent. The cache lives
/// in `AiChatQuotaCache`, the network in `GroqRouter`, persistence
/// in `SupabaseService`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'ai_chat_quota_cache.dart';
import 'groq_router.dart';
import 'supabase_service.dart';

/// Result of a successful chat send. The UI streams `delta` as it
/// arrives, then writes the full text to disk afterwards.
class AiChatSendResult {
  AiChatSendResult({
    required this.fullText,
    required this.modelId,
    required this.usedAfter,
    required this.remainingAfter,
    required this.resetsAt,
  });
  final String fullText;
  final String modelId;
  final int usedAfter;
  final int remainingAfter;
  final DateTime resetsAt;
}

/// Bangla refusal the UI shows when the prompt-guard model flags the
/// input. We never let an adversarial prompt reach a chat model.
const String _kSafetyRefusal =
    'দুঃখিত, এই ধরনের অনুরোধ আমি সাহায্য করতে পারব না। অনুগ্রহ করে '
    'ডায়াবেটিস, খাবার, ওষুধ, ব্যায়াম বা আপনার স্বাস্থ্য সংক্রান্ত '
    'একটি প্রশ্ন করুন।';

/// Bangla placeholder when the configured key is empty.
const String _kNotConfigured =
    'AI সহকারী এখন কনফিগার করা হয়নি। অনুগ্রহ করে .env ফাইলে '
    'GROQ_API_KEY যোগ করুন।';

class AiChatService {
  AiChatService._();

  // -------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------

  /// True iff the AI feature is usable. Lets the UI show a "not
  /// configured" placeholder instead of throwing.
  static bool get isConfigured => GroqRouter.isConfigured;

  /// Quick suggestion chips rendered on the welcome card. Keep them
  /// short, in plain Bangla, and reflect what the bot can actually
  /// answer (profile, medicines, meals, workouts, water).
  static const List<String> suggestionChips = [
    'আজকের খাবার কেমন হয়েছে?',
    'আমার রক্তে শর্করার অবস্থা কী?',
    'এই ওষুধটা কী কাজ করে?',
    'আজ কী ব্যায়াম করা উচিত?',
    'HbA1c কমাতে কী খাব?',
    'পানি কতটুকু খাওয়া উচিত আজ?',
  ];

  /// Refresh the quota cache from the server. Called on app boot and
  /// whenever the user opens the AI tab.
  static Future<AiChatQuota> warmUp({int limit = 5}) async {
    return AiChatQuotaCache.instance.warmUp(limit: limit);
  }

  /// Send a user message and stream the assistant response.
  ///
  /// `onDelta` is invoked once per streamed token; the returned
  /// [AiChatSendResult.fullText] is the concatenation of all deltas.
  ///
  /// `onRefusal` (optional) is invoked with the canned Bangla refusal
  /// when the prompt-guard flags the input — the UI should render it
  /// in an assistant bubble and **not** show a typing indicator.
  ///
  /// Throws [AiChatServiceException] on quota exhaustion or
  /// persistent network failure. UI catches and shows Bangla copy.
  static Future<AiChatSendResult> sendPrompt({
    required String userText,
    required void Function(String delta) onDelta,
    void Function(String refusalText)? onRefusal,
    CancelToken? cancel,
    int limit = 5,
  }) async {
    if (!isConfigured) {
      throw AiChatServiceException(_kNotConfigured,
          kind: AiChatErrorKind.notConfigured);
    }
    final trimmed = userText.trim();
    if (trimmed.isEmpty) {
      throw AiChatServiceException('একটি প্রশ্ন লিখুন।',
          kind: AiChatErrorKind.empty);
    }

    // -- 1. Reserve a quota slot (server-authoritative).
    final reserved = await SupabaseService.consumePromptQuota(limit: limit);
    if (reserved == null) {
      throw AiChatServiceException('লগইন সেশন মেয়াদোত্তীর্ণ — আবার লগইন করুন।',
          kind: AiChatErrorKind.notAuthenticated);
    }
    if (!reserved.allowed) {
      throw AiChatServiceException(
        'আজকের ৫টি প্রশ্ন শেষ। কাল সকাল ৬টায় আবার নতুন ৫টি প্রশ্ন পাবেন।',
        kind: AiChatErrorKind.quotaExhausted,
      );
    }

    // -- 2. Persist the user message immediately (don't lose it on a
    // chat-model timeout).
    try {
      await SupabaseService.saveAiChatMessage(
        role: 'user',
        content: trimmed,
      );
    } catch (e) {
      debugPrint('⚠️ [AiChatService] saveAiChatMessage(user) failed: $e');
    }

    // -- 3. Build the system prompt from the live context.
    final systemPrompt = await _buildSystemPrompt();

    // -- 4. Pull conversation history.
    final history = await SupabaseService.lastNAiChatMessages();

    // -- 5. Safety pre-check.
    bool safe = true;
    try {
      safe = await GroqRouter.instance.safetyCheck(trimmed);
    } catch (e) {
      // A safety-check outage should not block the user. Default to
      // safe so the chat model can apply its own guardrails.
      debugPrint('⚠️ [AiChatService] safetyCheck error: $e');
      safe = true;
    }
    if (!safe) {
      const refusal = _kSafetyRefusal;
      onRefusal?.call(refusal);
      await _persistAssistant(refusal, model: 'safety-guard');
      await _bumpCache(reserved.used, reserved.remaining, limit: limit);
      return AiChatSendResult(
        fullText: refusal,
        modelId: 'safety-guard',
        usedAfter: reserved.used,
        remainingAfter: reserved.remaining,
        resetsAt: DateTime.now().toUtc(),
      );
    }

    // -- 6. Stream the chat completion.
    final router = GroqRouter.instance;
    final messages = <GroqMessage>[
      GroqMessage('system', systemPrompt),
      ...history.map((h) => GroqMessage(h.role, h.content)),
      GroqMessage('user', trimmed),
    ];

    GroqChatResult chat;
    try {
      chat = await router.send(
        messages: messages,
        onChunk: onDelta,
        cancel: cancel,
      );
    } on GroqSafetyException {
      // Safety check fired from inside `send` (extremely unlikely
      // since we ran it above, but defensive).
      const refusal = _kSafetyRefusal;
      onRefusal?.call(refusal);
      await _persistAssistant(refusal, model: 'safety-guard');
      await _bumpCache(reserved.used, reserved.remaining, limit: limit);
      return AiChatSendResult(
        fullText: refusal,
        modelId: 'safety-guard',
        usedAfter: reserved.used,
        remainingAfter: reserved.remaining,
        resetsAt: DateTime.now().toUtc(),
      );
    } on GroqRouterException catch (e) {
      // We've burned a quota slot but couldn't generate a response.
      // Tell the user honestly in Bangla; the quota is non-refundable
      // (this is documented in the welcome card).
      final errText = e is GroqNotConfiguredException
          ? _kNotConfigured
          : 'AI সহকারী এই মুহূর্তে অনুপলব্ধ — একটু পরে আবার চেষ্টা করুন।';
      await _persistAssistant(errText, model: 'error');
      await _bumpCache(reserved.used, reserved.remaining, limit: limit);
      throw AiChatServiceException(errText,
          kind: e is GroqNotConfiguredException
              ? AiChatErrorKind.notConfigured
              : AiChatErrorKind.transport);
    }

    // -- 7. Persist assistant response + update cache.
    await _persistAssistant(chat.text, model: chat.modelId);
    await _bumpCache(reserved.used, reserved.remaining, limit: limit);

    return AiChatSendResult(
      fullText: chat.text,
      modelId: chat.modelId,
      usedAfter: reserved.used,
      remainingAfter: reserved.remaining,
      resetsAt: DateTime.now().toUtc(),
    );
  }

  /// Delete today's transcript. The quota is *not* touched.
  static Future<int> clearHistory() async {
    final n = await SupabaseService.clearAiChatHistory();
    return n;
  }

  /// Submit a 👍/👎 for an assistant message. Best-effort; failure is
  /// logged but never propagated to the UI.
  static Future<void> submitFeedback({
    required String messageId,
    required int rating,
  }) async {
    try {
      await SupabaseService.saveAiChatFeedback(
        messageId: messageId,
        rating: rating,
      );
    } catch (e) {
      debugPrint('⚠️ [AiChatService] feedback failed: $e');
    }
  }

  // -------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------

  static Future<String> _buildSystemPrompt() async {
    Map<String, dynamic>? ctx;
    try {
      ctx = await SupabaseService.fetchAiChatContext();
    } catch (e) {
      debugPrint('⚠️ [AiChatService] fetchAiChatContext failed: $e');
    }
    final ctxJson = ctx == null ? '{}' : jsonEncode(ctx);
    return '''
তুমি "আমার ডায়েট" অ্যাপের AI সহকারী — বাংলাদেশি ডায়াবেটিক রোগীদের জন্য একটি সহায়ক, সংক্ষিপ্ত ও নির্ভরযোগ্য স্বাস্থ্য সহকারী।

নিয়মাবলী:
1. সবসময় বাংলায় উত্তর দাও (ইংরেজি ছাড়া)। শব্দ সহজ রাখো — প্রবীণ ব্যবহারকারীদের জন্য।
2. খাবার, ওষুধ, ব্যায়াম, রক্তে শর্করা, HbA1c, BMI, কিডনি, হৃদরোগ, পানি — এই বিষয়গুলোতে সীমাবদ্ধ থাকো। অন্য বিষয়ে বিনয়ের সাথে "এটি আমার এখতিয়ারের বাইরে" বলো।
3. চিকিৎসা সংক্রান্ত কোনো প্রশ্নে ডাক্তার/ডায়েটিশিয়ানের পরামর্শ নিতে বলো। তুমি চিকিৎসক না।
4. নিচের JSON-এ ব্যবহারকারীর আজকের প্রোফাইল ও দৈনিক তথ্য আছে — সেটি পড়ে ব্যক্তিগত উত্তর দাও।
5. সংখ্যা দিলে এককসহ লেখো (যেমন "৭.৫ mmol/L", "১৫০০ mg")। খাবারের নাম বাংলায় লেখো।
6. কখনো মিথ্যা বা অনুমানমূলক চিকিৎসা পরামর্শ দিও না — তথ্য না থাকলে সেটা সৎভাবে বলো।
7. প্রতিদিন সর্বোচ্চ ৫টি প্রশ্ন — এই বিষয়ে প্রশ্ন আসলে বিনয়ের সাথে ব্যাখ্যা করো।

JSON: $ctxJson
''';
  }

  static Future<void> _persistAssistant(String text,
      {required String model}) async {
    try {
      await SupabaseService.saveAiChatMessage(
        role: 'assistant',
        content: text,
        model: model,
      );
    } catch (e) {
      debugPrint('⚠️ [AiChatService] persist assistant failed: $e');
    }
  }

  static Future<void> _bumpCache(int used, int remaining,
      {required int limit}) async {
    await AiChatQuotaCache.instance
        .recordConsumption(newUsed: used, limit: limit);
  }
}

// -------------------------------------------------------------------
// Error types
// -------------------------------------------------------------------

enum AiChatErrorKind { quotaExhausted, notConfigured, empty, notAuthenticated, transport }

class AiChatServiceException implements Exception {
  AiChatServiceException(this.message, {required this.kind});
  final String message;
  final AiChatErrorKind kind;
  @override
  String toString() => 'AiChatServiceException($kind): $message';
}