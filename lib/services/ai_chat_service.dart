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
    this.threadId,
  });
  final String fullText;
  final String modelId;
  final int usedAfter;
  final int remainingAfter;
  final DateTime resetsAt;

  /// The conversation thread this message was saved under. May be
  /// `null` if the thread insert failed — the chat still rendered.
  final String? threadId;
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
  /// If [threadId] is null we create a new thread on first send and
  /// return its id via [AiChatSendResult.threadId] so the UI can
  /// associate the message with the sidebar entry.
  ///
  /// Throws [AiChatServiceException] on quota exhaustion or
  /// persistent network failure. UI catches and shows Bangla copy.
  static Future<AiChatSendResult> sendPrompt({
    required String userText,
    required void Function(String delta) onDelta,
    void Function(String refusalText)? onRefusal,
    CancelToken? cancel,
    int limit = 5,
    String? threadId,
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

    // -- 0. Create a fresh thread on the first prompt so the sidebar
    // shows the chat even if the model call fails afterwards.
    String? activeThread = threadId;
    if (activeThread == null) {
      try {
        activeThread =
            await SupabaseService.createAiChatThread(titleSeed: trimmed);
      } catch (e) {
        debugPrint('⚠️ [AiChatService] createAiChatThread failed: $e');
      }
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
        threadId: activeThread,
      );
    } catch (e) {
      debugPrint('⚠️ [AiChatService] saveAiChatMessage(user) failed: $e');
    }

    // -- 3. Build the system prompt from the live context.
    final systemPrompt = await _buildSystemPrompt();

    // -- 4. Pull conversation history (thread-scoped).
    final history =
        await SupabaseService.lastNAiChatMessages(threadId: activeThread);

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
      await _persistAssistant(refusal,
          model: 'safety-guard', threadId: activeThread);
      await _bumpCache(reserved.used, reserved.remaining, limit: limit);
      return AiChatSendResult(
        fullText: refusal,
        modelId: 'safety-guard',
        usedAfter: reserved.used,
        remainingAfter: reserved.remaining,
        resetsAt: DateTime.now().toUtc(),
        threadId: activeThread,
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
      await _persistAssistant(refusal,
          model: 'safety-guard', threadId: activeThread);
      await _bumpCache(reserved.used, reserved.remaining, limit: limit);
      return AiChatSendResult(
        fullText: refusal,
        modelId: 'safety-guard',
        usedAfter: reserved.used,
        remainingAfter: reserved.remaining,
        resetsAt: DateTime.now().toUtc(),
        threadId: activeThread,
      );
    } on GroqRouterException catch (e) {
      // If the failure was "every model in rotation returned zero
      // tokens" the user got nothing for their prompt — refund the
      // quota slot so the 5/day limit stays fair. Other transport
      // errors (genuine outage) are also refunded; the user can retry
      // and succeed when Groq recovers.
      final errText = e is GroqNotConfiguredException
          ? _kNotConfigured
          : 'AI সহকারী এই মুহূর্তে অনুপলব্ধ — একটু পরে আবার চেষ্টা করুন।';
      await _refundAndRefreshCache(reserved, limit: limit);
      await _persistAssistant(errText,
          model: 'error', threadId: activeThread);
      throw AiChatServiceException(errText,
          kind: e is GroqNotConfiguredException
              ? AiChatErrorKind.notConfigured
              : AiChatErrorKind.transport);
    }

    // -- 7. Sanitize the streamed text. Some models leak reasoning
    // tags (`<reasoning>`, `<thinking>`, `<thought>`) into the visible
    // answer — strip them so the bubble shows only the final reply.
    final cleanedText = sanitizeAssistantText(chat.text);

    // -- 8. If we ended up with effectively no reply, treat this the
    // same as a silent rotation failure: refund + friendly error, no
    // half-empty bubble for the user to stare at.
    if (cleanedText.trim().isEmpty) {
      await _refundAndRefreshCache(reserved, limit: limit);
      const errText = 'AI সহকারী কোনো উত্তর দিতে পারেনি — আবার চেষ্টা করুন।';
      await _persistAssistant(errText,
          model: 'empty', threadId: activeThread);
      throw AiChatServiceException(errText, kind: AiChatErrorKind.transport);
    }

    // -- 9. Persist assistant response + update cache.
    await _persistAssistant(cleanedText,
        model: chat.modelId, threadId: activeThread);
    await _bumpCache(reserved.used, reserved.remaining, limit: limit);

    return AiChatSendResult(
      fullText: cleanedText,
      modelId: chat.modelId,
      usedAfter: reserved.used,
      remainingAfter: reserved.remaining,
      resetsAt: DateTime.now().toUtc(),
      threadId: activeThread,
    );
  }

  /// Delete today's transcript. The quota is *not* touched.
  static Future<int> clearHistory() async {
    final n = await SupabaseService.clearAiChatHistory();
    return n;
  }

  // ----------------------------------------------------------------
  // Thread management (history sidebar)
  // ----------------------------------------------------------------

  static Future<List<AiChatThreadRow>> listThreads({int limit = 100}) {
    return SupabaseService.listAiChatThreads(limit: limit);
  }

  static Future<List<AiChatHistoryMessage>> loadThread(
      {required String threadId, int limit = 500}) {
    return SupabaseService.loadThreadMessages(
      threadId: threadId,
      limit: limit,
    );
  }

  static Future<bool> deleteThread(String threadId) =>
      SupabaseService.deleteAiChatThread(threadId: threadId);

  static Future<bool> renameThread(
          {required String threadId, required String title}) =>
      SupabaseService.renameAiChatThread(threadId: threadId, title: title);

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
তুমি "আপন সুস্থতা" অ্যাপের AI সহকারী — বাংলাদেশি ডায়াবেটিক রোগীদের জন্য সংক্ষিপ্ত ও নির্ভরযোগ্য স্বাস্থ্য সহকারী।

মূলনীতি (অবশ্যই মানবে):
1. সবসময় বাংলায় উত্তর দাও। শব্দ সহজ রাখো — প্রবীণ ব্যবহারকারীদের জন্য।
2. খাবার, ওষুধ, ব্যায়াম, রক্তে শর্করা, HbA1c, BMI, কিডনি, হৃদরোগ, পানি — এই বিষয়গুলোতে সীমাবদ্ধ থাকো। অন্য বিষয়ে বিনয়ের সাথে বলো "এটি আমার এখতিয়ারের বাইরে।"
3. চিকিৎসা প্রশ্নে ডাক্তার/ডায়েটিশিয়ানের পরামর্শ নিতে বলো। তুমি চিকিৎসক না।
4. নিচের JSON-এ আজকের প্রোফাইল ও দৈনিক তথ্য আছে — পড়ে ব্যক্তিগত উত্তর দাও।

উত্তরের ধরন (অত্যন্ত গুরুত্বপূর্ণ):
- "টু-দ্য-পয়েন্ট" উত্তর দাও। কোনো বাড়তি ব্যাখ্যা, ভূমিকা, বা পুনরাবৃত্তি নয়।
- দীর্ঘ বাক্য নয় — প্রতিটি পয়েন্ট ১-২ লাইনে।
- তালিকা ব্যবহার করো (• বা -); মার্কডাউন টেবিল, হেডার (#), কোড ব্লক ব্যবহার করো না।
- সংখ্যার সাথে একক দাও ("৭.৫ mmol/L")।
- সর্বোচ্চ ৮-১২টি পয়েন্ট (বেশি হলে ব্যবহারকারী পড়তে পারে না)।
- উত্তর সাধারণত ১২০-২৫০ শব্দের মধ্যে রাখো।
- শেষে ১টি ছোট "পরামর্শ" লাইন দিতে পারো (ডাক্তার/ডায়েটিশিয়ান দেখানো ইত্যাদি)।

এড়িয়ে চলো:
- "আপনার প্রশ্নের জন্য ধন্যবাদ" / "আশা করি সাহায্য হলো" — এই ধরনের ভূমিকা।
- একই তথ্য বারবার না।
- বিশাল টেবিল বা ৫+ কলামের গ্রিড — বরং বুলেট পয়েন্টে ভাঙো।
- ইংরেজি হেডার।

JSON: $ctxJson
''';
  }

  static Future<void> _persistAssistant(String text,
      {required String model, String? threadId}) async {
    try {
      await SupabaseService.saveAiChatMessage(
        role: 'assistant',
        content: text,
        model: model,
        threadId: threadId,
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

  /// Roll back today's quota slot when the AI never produced a usable
  /// reply (every-model-silent, transport failure, or empty cleaned
  /// text). Fire-and-forget for the RPC — if the network is genuinely
  /// down the next `get_prompt_quota` call will reconcile the pill.
  static Future<void> _refundAndRefreshCache(
    ({bool allowed, int used, int remaining, int limit}) reserved, {
    required int limit,
  }) async {
    try {
      final r =
          await SupabaseService.refundPromptQuota(limit: limit);
      if (r != null) {
        await AiChatQuotaCache.instance
            .recordRefund(newUsed: r.used, limit: limit);
      } else {
        // RPC unavailable — fall back to decrementing locally; the
        // server will heal itself on next `get_prompt_quota`.
        await AiChatQuotaCache.instance.recordRefund(
            newUsed: reserved.used - 1, limit: limit);
      }
    } catch (e) {
      debugPrint('⚠️ [AiChatService] refundPromptQuota failed: $e');
    }
  }

  /// Strip reasoning/internal-monologue tags that some chat models
  /// (gpt-oss variants, qwen3) leak into the visible answer. Also
  /// collapses duplicated runs of the same line — chunked streaming
  /// sometimes replays the final sentence.
  static String sanitizeAssistantText(String raw) {
    if (raw.isEmpty) return raw;
    var out = raw;
    // Strip <reasoning>…</reasoning>, <thinking>…</thinking>,
    // <thought>…</thought>, and the bare <think>…</think> form.
    final tagPatterns = <String>[
      '<reasoning>',
      '<thinking>',
      '<thought>',
      '<think>',
    ];
    final tagCloses = <String>[
      '</reasoning>',
      '</thinking>',
      '</thought>',
      '</think>',
    ];
    for (var i = 0; i < tagPatterns.length; i++) {
      final open = tagPatterns[i];
      final close = tagCloses[i];
      while (true) {
        final start = out.indexOf(open);
        if (start == -1) break;
        final end = out.indexOf(close, start);
        if (end == -1) {
          out = out.substring(0, start);
          break;
        }
        out = out.substring(0, start) + out.substring(end + close.length);
      }
    }
    // Collapse runs of whitespace.
    out = out.replaceAll(RegExp(r'[ \t]+'), ' ');
    // De-duplicate identical consecutive lines (some chunked streams
    // repeat the closing paragraph once or twice).
    final lines = out.split('\n');
    final deduped = <String>[];
    for (final line in lines) {
      if (deduped.isEmpty || deduped.last.trim() != line.trim()) {
        deduped.add(line);
      } else if (line.trim().isNotEmpty) {
        // keep one extra copy only if the line is non-empty and
        // length differs from previous — preserves paragraph breaks.
        deduped.add(line);
      }
    }
    return deduped.join('\n').trim();
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