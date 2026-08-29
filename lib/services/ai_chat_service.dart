/// Top-level orchestrator for the AI chat feature.
///
/// One call to [AiChatService.sendPrompt] does the whole pipeline:
///
///   1. `check_and_increment_prompt_quota` — server-authoritative
///      10/day cap (the client cache is only a hint).
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
import 'ai_tools/action_inverse.dart';
import 'ai_tools/groq_tool_call.dart';
import 'ai_tools/pending_actions_store.dart';
import 'ai_tools/tool_executor.dart';
import 'ai_tools/tool_registry.dart';
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

/// Result of one tool-aware turn. The UI streams `delta` as it
/// arrives and shows confirmation cards for any write tool calls
/// before executing them.
class AiChatToolResult {
  AiChatToolResult({
    required this.fullText,
    required this.modelId,
    required this.usedAfter,
    required this.remainingAfter,
    required this.resetsAt,
    required this.pendingActions,
    this.threadId,
    this.assistantMessageId,
  });
  final String fullText;
  final String modelId;
  final int usedAfter;
  final int remainingAfter;
  final DateTime resetsAt;
  final List<PendingAction> pendingActions;
  final String? threadId;

  /// Id of the partial assistant row persisted in round 1. The UI
  /// passes it back so the audit log links to the right assistant
  /// bubble.
  final String? assistantMessageId;
}

/// Bangla refusal the UI shows when the prompt-guard model flags the
/// input. We never let an adversarial prompt reach a chat model.
const String _kSafetyRefusal =
    'দুঃখিত, এই ধরনের অনুরোধ আমি সাহায্য করতে পারব না। অনুগ্রহ করে '
    'ডায়াবেটিস, খাবার, ওষুধ, ব্যায়াম বা আপনার স্বাস্থ্য সংক্রান্ত '
    'একটি প্রশ্ন করুন।';

/// Render an integer as a Bangla numeral string ("10" → "১০"). Used for
/// the quota messages so the UI matches the rest of the Bangla copy.
String _bnNumber(int n) {
  const digits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
  final s = n.toString();
  final buf = StringBuffer();
  for (final ch in s.codeUnits) {
    if (ch >= 0x30 && ch <= 0x39) {
      buf.write(digits[ch - 0x30]);
    } else {
      buf.writeCharCode(ch);
    }
  }
  return buf.toString();
}

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

  /// Daily prompt cap shared by [warmUp] / [sendPrompt] /
  /// [sendPromptWithTools]. Kept on [AiChatService] so the limit is
  /// defined in exactly one place — change it here, not at every call
  /// site. The server RPC accepts the limit as a parameter, so bumping
  /// this number doesn't require a migration.
  static const int dailyPromptLimit = 10;

  /// Refresh the quota cache from the server. Called on app boot and
  /// whenever the user opens the AI tab.
  static Future<AiChatQuota> warmUp({int? limit}) async {
    return AiChatQuotaCache.instance
        .warmUp(limit: limit ?? dailyPromptLimit);
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
    int? limit,
    String? threadId,
  }) async {
    final effectiveLimit = limit ?? dailyPromptLimit;
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
    final reserved =
        await SupabaseService.consumePromptQuota(limit: effectiveLimit);
    if (reserved == null) {
      throw AiChatServiceException('লগইন সেশন মেয়াদোত্তীর্ণ — আবার লগইন করুন।',
          kind: AiChatErrorKind.notAuthenticated);
    }
    if (!reserved.allowed) {
      throw AiChatServiceException(
        'আজকের ${_bnNumber(effectiveLimit)}টি প্রশ্ন শেষ। কাল সকাল ৬টায় আবার নতুন ${_bnNumber(effectiveLimit)}টি প্রশ্ন পাবেন।',
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
      await _bumpCache(reserved.used, reserved.remaining,
          limit: effectiveLimit);
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
      await _bumpCache(reserved.used, reserved.remaining,
          limit: effectiveLimit);
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
      // quota slot so the 10/day limit stays fair. Other transport
      // errors (genuine outage) are also refunded; the user can retry
      // and succeed when Groq recovers.
      final errText = e is GroqNotConfiguredException
          ? _kNotConfigured
          : 'AI সহকারী এই মুহূর্তে অনুপলব্ধ — একটু পরে আবার চেষ্টা করুন।';
      await _refundAndRefreshCache(reserved, limit: effectiveLimit);
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
      await _refundAndRefreshCache(reserved, limit: effectiveLimit);
      const errText = 'AI সহকারী কোনো উত্তর দিতে পারেনি — আবার চেষ্টা করুন।';
      await _persistAssistant(errText,
          model: 'empty', threadId: activeThread);
      throw AiChatServiceException(errText, kind: AiChatErrorKind.transport);
    }

    // -- 9. Persist assistant response + update cache.
    await _persistAssistant(cleanedText,
        model: chat.modelId, threadId: activeThread);
    await _bumpCache(reserved.used, reserved.remaining,
        limit: effectiveLimit);

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
তুমি "আপন সুস্থতা" অ্যাপের AI ম্যানেজার — বাংলাদেশি ডায়াবেটিক রোগীদের জন্য নির্ভরযোগ্য স্বাস্থ্য সহকারী এবং এই অ্যাপের সব কাজের (ওষুধ, খাবার, ব্যায়াম, পানি, দৈনিক মেট্রিক্স) হয়ে কাজ করার জন্য দায়িত্বপ্রাপ্ত।

তোমার ক্ষমতা ও কর্তব্য (অবশ্যই মানবে):
1. সবসময় বাংলায় উত্তর দাও। শব্দ সহজ রাখো — প্রবীণ ব্যবহারকারীদের জন্য।
2. অ্যাপের যেকোনো তথ্য পড়তে (ওষুধ, খাবার-প্ল্যান, ব্যায়াম, পানি, প্রোফাইল, দৈনিক মেট্রিক্স, ডোজ-ইতিহাস, লগ) এবং সেগুলো যোগ/পরিবর্তন/মুছতে পারার জন্য তোমার কাছে tool আছে — প্রয়োজন হলে বিনা দ্বিধায় ব্যবহার করো। কোনো "এখতিয়ারের বাইরে" বলার দরকার নেই; যা পারবে তাই করো।
3. ওষুধ, খাবার, ব্যায়াম, রক্তে শর্করা, HbA1c, BMI, কিডনি, হৃদরোগ, পানি — এসব বিষয়ে সরাসরি সাহায্য করো।
4. গুরুতর চিকিৎসা সিদ্ধান্তে ডাক্তার/ডায়েটিশিয়ানের পরামর্শ নিতে বলো। তুমি চিকিৎসক না — তবে তুমি ব্যবহারকারীর হয়ে অ্যাপের ডেটা সাজিয়ে দিতে পারো।
5. নিচের JSON-এ আজকের প্রোফাইল ও দৈনিক তথ্য আছে — পড়ে ব্যক্তিগত উত্তর দাও।
6. ব্যবহারকারী যা করতে বলে (ওষুধ যোগ, খাবার লগ, ব্যায়াম শুরু, পানি লগ, কাস্টম খাবার যোগ) তা সরাসরি tool call করে করুন — করার পর একটি ছোট বাংলা সারাংশ দাও।

tool ব্যবহারের নিয়ম:
- যেকোনো পরিবর্তন/যোগ/মোছা আগে tool call করবে, পরে ছোট Bangla সারাংশ।
- একই turn-এ একাধিক কাজ করতে পারো (যেমন: একসাথে ওষুধ যোগ + পানি লগ)।
- read-only tool (তালিকা/সারসংক্ষেপ) ব্যবহার করলে উত্তরেই ফলাফল দেখাও।

উত্তরের ধরন (অত্যন্ত গুরুত্বপূর্ণ):
- "টু-দ্য-পয়েন্ট" উত্তর দাও। কোনো বাড়তি ব্যাখ্যা, ভূমিকা, বা পুনরাবৃত্তি নয়।
- দীর্ঘ বাক্য নয় — প্রতিটি পয়েন্ট ১-২ লাইনে।
- তালিকা ব্যবহার করো (• বা -); মার্কডাউন টেবিল, হেডার (#), কোড ব্লক ব্যবহার করো না।
- সংখ্যার সাথে একক দাও ("৭.৫ mmol/L")।
- সর্বোচ্চ ৮-১২টি পয়েন্ট (বেশি হলে ব্যবহারকারী পড়তে পারে না)।
- উত্তর সাধারণত ১২০-২৫০ শব্দের মধ্যে রাখো।

এড়িয়ে চলো:
- "আপনার প্রশ্নের জন্য ধন্যবাদ" / "আশা করি সাহায্য হলো" — এই ধরনের ভূমিকা।
- একই তথ্য বারবার না।
- বিশাল টেবিল বা ৫+ কলামের গ্রিড — বরং বুলেট পয়েন্টে ভাঙো।
- ইংরেজি হেডার।
- কখনো "এটি আমার এখতিয়ারের বাইরে" বলো না — তুমি অ্যাপের ম্যানেজার, যা tool দিয়ে করা যায় তাই করো।

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

  // -------------------------------------------------------------------
  // Tool-aware pipeline ("AI as the app's manager")
  // -------------------------------------------------------------------

  /// Sends a user message and runs the tool-aware pipeline.
  ///
  /// Round 1: build system prompt + tool manifest, stream the model's
  /// first response. If it produced any `tool_calls`, queue each write
  /// as a `PendingAction` (so the chat UI can render the করুন / বাতিল
  /// cards) and immediately run read tools.
  ///
  /// Round 2: when every tool is resolved, ship all `tool` messages
  /// back to the model and stream its Bangla summary. The summary text
  /// is what the user sees in the assistant bubble after the action
  /// cards collapse.
  ///
  /// Quota pricing is unchanged: one turn = one slot, regardless of
  /// the number of tool calls.
  static Future<AiChatToolResult> sendPromptWithTools({
    required String userText,
    required void Function(String delta) onDelta,
    void Function(PendingAction action)? onPendingAction,
    CancelToken? cancel,
    int? limit,
    String? threadId,
  }) async {
  final effectiveLimit = limit ?? dailyPromptLimit;
  if (!isConfigured) {
    throw AiChatServiceException(_kNotConfigured,
        kind: AiChatErrorKind.notConfigured);
  }
  final trimmed = userText.trim();
  if (trimmed.isEmpty) {
    throw AiChatServiceException('একটি প্রশ্ন লিখুন।',
        kind: AiChatErrorKind.empty);
  }

  // Create / reuse the thread.
  String? activeThread = threadId;
  if (activeThread == null) {
    try {
      activeThread =
          await SupabaseService.createAiChatThread(titleSeed: trimmed);
    } catch (e) {
      debugPrint('⚠️ [AiChatService] createAiChatThread failed: $e');
    }
  }

  // Reserve a quota slot.
  final reserved =
      await SupabaseService.consumePromptQuota(limit: effectiveLimit);
  if (reserved == null) {
    throw AiChatServiceException('লগইন সেশন মেয়াদোত্তীর্ণ — আবার লগইন করুন।',
        kind: AiChatErrorKind.notAuthenticated);
  }
  if (!reserved.allowed) {
    throw AiChatServiceException(
      'আজকের ${_bnNumber(effectiveLimit)}টি প্রশ্ন শেষ। কাল সকাল ৬টায় আবার নতুন ${_bnNumber(effectiveLimit)}টি প্রশ্ন পাবেন।',
      kind: AiChatErrorKind.quotaExhausted,
    );
  }

  // Persist the user message. The id isn't needed downstream; we
  // just want the row to land so the chat thread isn't empty if the
  // model call fails afterwards.
  try {
    await SupabaseService.saveAiChatMessage(
      role: 'user',
      content: trimmed,
      threadId: activeThread,
    );
  } catch (e) {
    debugPrint('⚠️ [AiChatService] saveAiChatMessage(user) failed: $e');
  }

  // Build system prompt with the live context (same blob as today).
  final systemPrompt = await _buildSystemPrompt();

  // Pull conversation history (thread-scoped).
  final history =
      await SupabaseService.lastNAiChatMessages(threadId: activeThread);

  // Safety pre-check.
  bool safe = true;
  try {
    safe = await GroqRouter.instance.safetyCheck(trimmed);
  } catch (e) {
    debugPrint('⚠️ [AiChatService] safetyCheck error: $e');
    safe = true;
  }
  if (!safe) {
    const refusal = _kSafetyRefusal;
    onDelta(refusal);
    await _persistAssistant(refusal,
        model: 'safety-guard', threadId: activeThread);
    await _bumpCache(reserved.used, reserved.remaining, limit: effectiveLimit);
    return AiChatToolResult(
      fullText: refusal,
      modelId: 'safety-guard',
      usedAfter: reserved.used,
      remainingAfter: reserved.remaining,
      resetsAt: DateTime.now().toUtc(),
      pendingActions: const [],
      threadId: activeThread,
    );
  }

  final router = GroqRouter.instance;
  final tools = AiToolRegistry.toGroqToolsJson();

  // ── ROUND 1 ── assistant may stream text AND/OR tool_calls.
  final messages = <GroqMessage>[
    GroqMessage('system', systemPrompt),
    ...history.map((h) => GroqMessage(h.role, h.content)),
    GroqMessage('user', trimmed),
  ];

  GroqChatResult round1;
  try {
    round1 = await router.send(
      messages: messages,
      onChunk: onDelta,
      cancel: cancel,
      tools: tools,
    );
  } on GroqSafetyException {
    const refusal = _kSafetyRefusal;
    onDelta(refusal);
    await _persistAssistant(refusal,
        model: 'safety-guard', threadId: activeThread);
    await _bumpCache(reserved.used, reserved.remaining, limit: effectiveLimit);
    return AiChatToolResult(
      fullText: refusal,
      modelId: 'safety-guard',
      usedAfter: reserved.used,
      remainingAfter: reserved.remaining,
      resetsAt: DateTime.now().toUtc(),
      pendingActions: const [],
      threadId: activeThread,
    );
  } on GroqRouterException catch (e) {
    final errText = e is GroqNotConfiguredException
        ? _kNotConfigured
        : 'AI সহকারী এই মুহূর্তে অনুপলব্ধ — একটু পরে আবার চেষ্টা করুন।';
    await _refundAndRefreshCache(reserved, limit: effectiveLimit);
    await _persistAssistant(errText,
        model: 'error', threadId: activeThread);
    throw AiChatServiceException(errText,
        kind: e is GroqNotConfiguredException
            ? AiChatErrorKind.notConfigured
            : AiChatErrorKind.transport);
  }

  final cleanedText = sanitizeAssistantText(round1.text);

  // No tool calls → identical to today's behaviour.
  if (round1.toolCalls.isEmpty) {
    if (cleanedText.trim().isEmpty) {
      await _refundAndRefreshCache(reserved, limit: effectiveLimit);
      const errText = 'AI সহকারী কোনো উত্তর দিতে পারেনি — আবার চেষ্টা করুন।';
      await _persistAssistant(errText,
          model: 'empty', threadId: activeThread);
      throw AiChatServiceException(errText, kind: AiChatErrorKind.transport);
    }
    await _persistAssistant(cleanedText,
        model: round1.modelId, threadId: activeThread);
    await _bumpCache(reserved.used, reserved.remaining, limit: effectiveLimit);
    return AiChatToolResult(
      fullText: cleanedText,
      modelId: round1.modelId,
      usedAfter: reserved.used,
      remainingAfter: reserved.remaining,
      resetsAt: DateTime.now().toUtc(),
      pendingActions: const [],
      threadId: activeThread,
    );
  }

  // ── Tool calls landed. Persist the partial bubble so far as a
  // single assistant row that will be updated with the final
  // summary after Round 2. We pass an empty string now — the model
  // will append the summary, and the bubble UI shows the cards
  // in the meantime.
  String? assistantMessageId;
  try {
    assistantMessageId = await SupabaseService.saveAiChatMessage(
      role: 'assistant',
      content: cleanedText,
      model: round1.modelId,
      threadId: activeThread,
    );
  } catch (e) {
    debugPrint('⚠️ [AiChatService] saveAiChatMessage(assistant) failed: $e');
  }

  // Build pending actions for writes. Reads are executed inline and
  // their results fed to Round 2 as `tool` messages. Reads are
  // independent RPCs so they can fan out concurrently.
  final pendingActions = <PendingAction>[];
  final toolMessages = <GroqMessage>[];
  final writeJobs = <(GroqToolCall, AiTool, Map<String, dynamic>)>[];
  final readJobs = <(GroqToolCall, AiTool, Map<String, dynamic>)>[];

  for (final call in round1.toolCalls) {
    final tool = AiToolRegistry.byName(call.name);
    if (tool == null) {
      toolMessages.add(GroqMessage(
        'tool',
        jsonEncode({'ok': false, 'error': 'unknown_tool', 'name': call.name}),
        toolCallId: call.id,
        name: call.name,
      ));
      continue;
    }
    Map<String, dynamic> args;
    try {
      args = (jsonDecode(call.argumentsJson.isEmpty ? '{}' : call.argumentsJson)
              as Map<String, dynamic>)
          .cast<String, dynamic>();
    } catch (e) {
      toolMessages.add(GroqMessage(
        'tool',
        jsonEncode({'ok': false, 'error': 'bad_args'}),
        toolCallId: call.id,
        name: tool.name,
      ));
      continue;
    }
    if (tool.writeMutating) {
      writeJobs.add((call, tool, args));
    } else {
      readJobs.add((call, tool, args));
    }
  }

  // Fan out read executions — the order of results doesn't matter
  // because we key each `tool` message by call.id.
  if (readJobs.isNotEmpty) {
    final readResults = await Future.wait(
      readJobs.map((j) async {
        try {
          return _ReadOk(
              callId: j.$1.id,
              name: j.$2.name,
              result: await AiToolExecutor.execute(
                tool: j.$2,
                call: j.$1,
                args: j.$3,
                threadId: activeThread,
                messageId: assistantMessageId,
              ));
        } catch (e) {
          return _ReadOk(
            callId: j.$1.id,
            name: j.$2.name,
            error: e.toString(),
          );
        }
      }),
    );
    for (final r in readResults) {
      toolMessages.add(GroqMessage(
        'tool',
        r.error != null
            ? jsonEncode({'ok': false, 'error': r.error})
            : r.result!.toToolMessageJson(),
        toolCallId: r.callId,
        name: r.name,
      ));
    }
  }

  // Queue writes for user confirmation.
  for (final (call, tool, args) in writeJobs) {
    final description = await AiToolExecutor.describe(
      tool: tool,
      args: args,
    );
    final pending = PendingAction(
      call: call,
      toolName: tool.name,
      toolArgs: args,
      description: description,
      createdAt: DateTime.now(),
    );
    pendingActions.add(pending);
    PendingActionsStore.instance.add(pending);
    onPendingAction?.call(pending);
  }

  // ── If every tool call was a read, immediately feed results back
  // and stream the final summary. Writes wait on the user.
  if (pendingActions.isEmpty && toolMessages.isNotEmpty) {
    final followupMessages = <GroqMessage>[
      ...messages,
      GroqMessage('assistant', cleanedText,
          toolCalls: round1.toolCalls),
      ...toolMessages,
      GroqMessage(
        'user',
        'উপরের টুল রেজাল্ট দেখে বাংলায় সংক্ষেপে জবাব দাও (১২০-২৫০ শব্দ, বুলেট পয়েন্ট)।',
      ),
    ];
    GroqChatResult round2;
    try {
      round2 = await router.send(
        messages: followupMessages,
        onChunk: onDelta,
        cancel: cancel,
        tools: tools,
      );
    } on GroqRouterException {
      const errText = 'AI সহকারী এই মুহূর্তে অনুপলব্ধ — একটু পরে আবার চেষ্টা করুন।';
      await _refundAndRefreshCache(reserved, limit: effectiveLimit);
      throw AiChatServiceException(errText, kind: AiChatErrorKind.transport);
    }
    final summary = sanitizeAssistantText(round2.text);
    if (summary.trim().isEmpty) {
      await _refundAndRefreshCache(reserved, limit: effectiveLimit);
      throw AiChatServiceException(
        'AI সহকারী কোনো উত্তর দিতে পারেনি — আবার চেষ্টা করুন।',
        kind: AiChatErrorKind.transport,
      );
    }
    await _appendAssistantMessage(
      assistantMessageId: assistantMessageId,
      additionalText: summary,
      threadId: activeThread,
    );
    await _bumpCache(reserved.used, reserved.remaining, limit: effectiveLimit);
    return AiChatToolResult(
      fullText: summary,
      modelId: round2.modelId,
      usedAfter: reserved.used,
      remainingAfter: reserved.remaining,
      resetsAt: DateTime.now().toUtc(),
      pendingActions: const [],
      threadId: activeThread,
    );
  }

  // ── Writes are pending. We hand control back to the UI; it will
  // call `executeConfirmedAction()` per pending action and then
  // `resumeFinalSummary()` to stream the wrap-up.
  await _bumpCache(reserved.used, reserved.remaining, limit: effectiveLimit);
  return AiChatToolResult(
    fullText: cleanedText,
    modelId: round1.modelId,
    usedAfter: reserved.used,
    remainingAfter: reserved.remaining,
    resetsAt: DateTime.now().toUtc(),
    pendingActions: pendingActions,
    threadId: activeThread,
    assistantMessageId: assistantMessageId,
  );
}
}

// -------------------------------------------------------------------
// Round-2 resume + write execution
// -------------------------------------------------------------------

/// Internal: save the partial round-1 assistant row with the round-2
/// summary appended. Append-only — we never mutate history; we just
/// insert a new "assistant" message that picks up the story.
Future<String?> _appendAssistantMessage({
  String? assistantMessageId,
  required String additionalText,
  String? threadId,
}) async {
  // The simplest implementation is to just append a new assistant
  // bubble. We don't currently have an "update existing message"
  // RPC, and the audit log references the assistant row by id. So
  // we just persist a fresh row.
  try {
    return await SupabaseService.saveAiChatMessage(
      role: 'assistant',
      content: additionalText,
      threadId: threadId,
    );
  } catch (e) {
    debugPrint('⚠️ [AiChatService] appendAssistantMessage failed: $e');
    return null;
  }
}

/// Execute a single confirmed action. Called by the chat screen
/// after the user taps করুন. On success the entry's [status] flips
/// to `succeeded` and [auditId] is populated; on failure the entry
/// flips to `failed` with the error message for retry UI.
Future<ToolExecution> executeConfirmedAction({
  required PendingAction action,
  String? threadId,
  String? messageId,
}) async {
  final tool = AiToolRegistry.byName(action.toolName);
  if (tool == null) {
    return ToolExecution(
      toolName: action.toolName,
      description: action.description,
      requiresConfirmation: true,
      toolArgs: action.toolArgs,
      inverseArgs: const {},
      errorMessage: 'unknown_tool',
    );
  }
  PendingActionsStore.instance.update(action.call.id,
      (a) => a..status = PendingActionStatus.executing);
  final result = await AiToolExecutor.execute(
    tool: tool,
    call: action.call,
    args: action.toolArgs,
    threadId: threadId,
    messageId: messageId,
  );
  PendingActionsStore.instance.update(action.call.id, (a) {
    a.auditId = result.auditId;
    a.status = result.ok
        ? PendingActionStatus.succeeded
        : PendingActionStatus.failed;
    a.errorMessage = result.errorMessage;
    return a;
  });
  return result;
}

/// Re-attempt a failed action (used by the retry pill on the
/// confirmation card).
Future<ToolExecution> retryConfirmedAction({
  required PendingAction action,
  String? threadId,
  String? messageId,
}) async {
  PendingActionsStore.instance.update(action.call.id,
      (a) => a..status = PendingActionStatus.awaiting);
  return executeConfirmedAction(
    action: action,
    threadId: threadId,
    messageId: messageId,
  );
}

/// Undo a previously-confirmed action. Runs the inverse RPC and
/// marks the audit row as undone. On success the card flips to
/// `undone` so the UI can show a "ফিরিয়ে আনা হয়েছে" pill.
Future<bool> undoAction({required PendingAction action}) async {
  if (action.auditId == null) return false;
  final ok = await ActionInverse.run(
    toolName: action.toolName,
    inverseArgs: action.inverseArgs,
  );
  if (ok) {
    await SupabaseService.undoAiChatAction(actionId: action.auditId!);
    PendingActionsStore.instance.update(action.call.id,
        (a) => a..status = PendingActionStatus.undone);
  }
  return ok;
}

/// Run the second round after every pending action is resolved
/// (all writes confirmed or cancelled). Streams the Bangla summary
/// back via `onDelta` and returns the final text.
Future<String?> resumeFinalSummary({
  required List<GroqMessage> round1Messages,
  required String round1Text,
  required List<GroqToolCall> round1ToolCalls,
  required Map<String, ToolExecution> resolvedByCallId,
  required void Function(String delta) onDelta,
  CancelToken? cancel,
  String? threadId,
}) async {
  final router = GroqRouter.instance;
  final tools = AiToolRegistry.toGroqToolsJson();
  final toolMessages = <GroqMessage>[
    for (final call in round1ToolCalls)
      if (resolvedByCallId.containsKey(call.id))
        GroqMessage(
          'tool',
          resolvedByCallId[call.id]!.toToolMessageJson(),
          toolCallId: call.id,
          name: call.name,
        ),
  ];
  final followup = <GroqMessage>[
    ...round1Messages,
    GroqMessage('assistant', round1Text, toolCalls: round1ToolCalls),
    ...toolMessages,
    GroqMessage(
      'user',
      'উপরের টুল রেজাল্ট দেখে বাংলায় সংক্ষেপে জবাব দাও (১২০-২৫০ শব্দ, বুলেট পয়েন্ট)।',
    ),
  ];
  try {
    final r = await router.send(
      messages: followup,
      onChunk: onDelta,
      cancel: cancel,
      tools: tools,
    );
    final summary = AiChatService.sanitizeAssistantText(r.text);
    if (summary.trim().isEmpty) return null;
    await _appendAssistantMessage(
      additionalText: summary,
      threadId: threadId,
    );
    return summary;
  } on GroqRouterException {
    return null;
  }
}

/// Internal: result of a parallel read tool execution. Either [result]
/// is set (success) or [error] (RPC threw). Carries the call id and
/// tool name so the parent can re-key them into `tool` messages.
class _ReadOk {
  _ReadOk({required this.callId, required this.name, this.result, this.error});
  final String callId;
  final String name;
  final ToolExecution? result;
  final String? error;
}

enum AiChatErrorKind { quotaExhausted, notConfigured, empty, notAuthenticated, transport }

class AiChatServiceException implements Exception {
  AiChatServiceException(this.message, {required this.kind});
  final String message;
  final AiChatErrorKind kind;
  @override
  String toString() => 'AiChatServiceException($kind): $message';
}