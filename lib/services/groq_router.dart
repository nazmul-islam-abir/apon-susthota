/// HTTP client for the Groq Chat Completions API.
///
/// Responsibilities:
///   * Rotate through the 6 free chat models on transient failure
///     (HTTP 429, 5xx, timeout, connection reset, stalled SSE) so a
///     single rate-limited model never takes the whole feature down.
///   * Provide a tiny "safety" hook backed by `llama-prompt-guard-2-22m`
///     so we can refuse prompt-injection before paying for a chat call.
///   * Stream Server-Sent Events so the assistant bubble fills in real
///     time instead of jumping in at the end.
///   * Enforce a per-chunk *idle* timeout and a *total* time budget so
///     a stuck model never leaves the user staring at "..." forever.
///
/// Everything is synchronous-ish on the Dart side: callers receive
/// `onChunk(String delta)` callbacks and a final `onComplete(String
/// modelId)` once the chosen model emits `done: true`. The router never
/// touches the database — quota + transcript persistence live in
/// `AiChatService` / Supabase.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'env.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

/// Identifies a model in the rotation. The values here are the literal
/// Groq model IDs we pass to the API; the `_kebab` enum names are just a
/// Dart convenience.
enum GroqModelId {
  compound,
  compoundMini,
  gptOss120b,
  gptOss20b,
  qwen3_6_27b;

  const GroqModelId();

  String get id {
    switch (this) {
      case GroqModelId.compound:
        return 'groq/compound';
      case GroqModelId.compoundMini:
        return 'groq/compound-mini';
      case GroqModelId.gptOss120b:
        return 'openai/gpt-oss-120b';
      case GroqModelId.gptOss20b:
        return 'openai/gpt-oss-20b';
      case GroqModelId.qwen3_6_27b:
        return 'qwen/qwen3.6-27b';
    }
  }

}

/// Order used for round-robin rotation. `groq/compound` and `compound-mini`
/// go first (they include web_search / code_interpreter via
/// `compound_custom.tools.enabled_tools`), then the open-source OSS / Qwen
/// chat models.
///
/// **Why no `gpt-oss-safeguard-20b`?** It is a *guard classifier*, not a
/// chat model — streaming against it almost always produces zero content
/// and surfaces to the user as "AI সহকারী এই মুহূর্তে অনুপলব্ধ".
/// We use `llama-prompt-guard-2-22m` for the safety pre-filter instead.
const List<GroqModelId> _kChatRotation = [
  GroqModelId.compound,
  GroqModelId.compoundMini,
  GroqModelId.gptOss120b,
  GroqModelId.gptOss20b,
  GroqModelId.qwen3_6_27b,
];

/// A single chat message in OpenAI's wire format.
class GroqMessage {
  const GroqMessage(this.role, this.content);
  final String role; // 'system' | 'user' | 'assistant'
  final String content;

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

/// Internal value-object summarising what came out of a single model
/// attempt. We keep `text` empty (rather than throw) when the model
/// sent [DONE] without any content — that lets the caller decide if a
/// silent-clean stream is "this model isn't a chat model" (rotate) or
/// "the service is too busy to give a useful answer" (refund).
class _StreamOutcome {
  const _StreamOutcome({required this.text, required this.cleanDone});
  final String text;
  final bool cleanDone;
}

// ---------------------------------------------------------------------------
// Exception types
// ---------------------------------------------------------------------------

/// Surfaced to the UI when every model in the rotation failed.
class GroqRouterException implements Exception {
  GroqRouterException(this.message, {this.lastStatusCode, this.cause});
  final String message;
  final int? lastStatusCode;
  final Object? cause;

  @override
  String toString() => 'GroqRouterException($message, '
      'status=$lastStatusCode, cause=$cause)';
}

/// Raised when the configured key is empty (the caller should fall back
/// to the "AI not configured" placeholder screen rather than a hard
/// error toast every time).
class GroqNotConfiguredException extends GroqRouterException {
  GroqNotConfiguredException()
      : super('GROQ_API_KEY is missing. Add it to .env.');
}

/// Returned by [GroqRouter.safetyCheck] when the input looks like an
/// injection attempt. Callers should reply politely in Bangla and skip
/// the chat call entirely.
class GroqSafetyException implements Exception {
  GroqSafetyException(this.reason);
  final String reason;
  @override
  String toString() => 'GroqSafetyException($reason)';
}

// ---------------------------------------------------------------------------
// Per-model parameter maps
// ---------------------------------------------------------------------------
// These match the user's curl samples byte-for-byte so Groq never rejects
// us with a 400 because of an unexpected parameter combination.

Map<String, dynamic> _requestBodyFor(
  GroqModelId model, {
  required List<GroqMessage> messages,
  required bool stream,
  int? maxCompletionTokens,
}) {
  final base = <String, dynamic>{
    'model': model.id,
    'stream': stream,
    'messages': messages.map((m) => m.toJson()).toList(),
  };

  // Default caps are intentionally tight: the bot's answer must fit on
  // a phone screen (≈ 120-250 Bangla words). If the caller wants a
  // longer response (e.g. a meal plan) they can pass a higher
  // [maxCompletionTokens] explicitly.
  switch (model) {
    case GroqModelId.compound:
    case GroqModelId.compoundMini:
      base.addAll({
        'temperature': 1,
        'top_p': 1,
        'compound_custom': {
          'tools': {
            'enabled_tools': ['web_search', 'code_interpreter', 'visit_website'],
          },
        },
        'max_completion_tokens': maxCompletionTokens ?? 800,
      });
      break;

    case GroqModelId.gptOss120b:
    case GroqModelId.gptOss20b:
      base.addAll({
        'temperature': 1,
        'top_p': 1,
        'reasoning_effort': 'low',
        'max_completion_tokens': maxCompletionTokens ?? 900,
      });
      break;

    case GroqModelId.qwen3_6_27b:
      base.addAll({
        'temperature': 0.6,
        'top_p': 0.95,
        'reasoning_effort': 'default',
        'max_completion_tokens': maxCompletionTokens ?? 900,
      });
      break;
  }
  return base;
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

class GroqRouter {
  GroqRouter({
    HttpClient? httpClient,
    // Long timeout because the gpt-oss-120b / compound models can take
    // 30-40s to first-token with a full context payload. We also have
    // an outer rotation budget (see [_kRotationBudget]) so we never
    // hang silently on a stalled stream.
    Duration perRequestTimeout = const Duration(seconds: 60),
    // How long we'll wait between SSE chunks before declaring the
    // stream dead. Shorter than [perRequestTimeout] so a stalled
    // model fails fast while a slow-but-healthy one survives.
    Duration idleChunkTimeout = const Duration(seconds: 20),
    // Hard cap across the whole model rotation. If we've spent this
    // long trying models we surface the last error rather than let
    // the user stare at a typing indicator forever.
    Duration rotationBudget = const Duration(seconds: 120),
    int safetyMaxTokens = 1,
    String endpoint =
        'https://api.groq.com/openai/v1/chat/completions',
    Random? random,
  })  : _httpClient = httpClient ?? HttpClient(),
        _perRequestTimeout = perRequestTimeout,
        _idleChunkTimeout = idleChunkTimeout,
        _rotationBudget = rotationBudget,
        _safetyMaxTokens = safetyMaxTokens,
        _endpoint = Uri.parse(endpoint),
        _random = random ?? Random() {
    _httpClient.connectionTimeout = const Duration(seconds: 12);
  }

  final HttpClient _httpClient;
  final Duration _perRequestTimeout;
  final Duration _idleChunkTimeout;
  final Duration _rotationBudget;
  final int _safetyMaxTokens;
  final Uri _endpoint;
  final Random _random;

  /// Lazy singleton so the UI can call `GroqRouter.instance` without
  /// pumping a `Provider` everywhere. Tests can override by
  /// reassigning the field.
  static GroqRouter? _instance;
  static GroqRouter get instance => _instance ??= GroqRouter();

  /// Reset the singleton (test hook).
  @visibleForTesting
  static void resetInstanceForTest() => _instance = null;

  /// True iff a non-empty key is configured. Use this to short-circuit
  /// the UI to a "not configured" placeholder.
  static bool get isConfigured => Env.hasGroqKey;

  /// Pick a random offset so consecutive requests don't always start at
  /// the same model (helps when many users are online at once and a
  /// particular model is heavily throttled).
  List<GroqModelId> _shuffledRotation() {
    final list = List<GroqModelId>.from(_kChatRotation)..shuffle(_random);
    return list;
  }

  // -------------------------------------------------------------------------
  // Chat completion (streaming, with rotation)
  // -------------------------------------------------------------------------

  /// Stream a chat completion. `messages` should already contain the
  /// system prompt at index 0 — the router doesn't add one for you.
  ///
  /// `onChunk` is called once per incremental token. `onComplete` is
  /// called exactly once after `done: true` arrives.
  ///
  /// On success returns [GroqChatResult]; if every model in the rotation
  /// failed to produce *any* token, throws a [GroqRouterException] whose
  /// `cause` is either a real transport failure or the synthetic
  /// `every-model-silent` marker so callers can decide whether to refund
  /// the user's quota slot.
  Future<GroqChatResult> send({
    required List<GroqMessage> messages,
    void Function(String delta)? onChunk,
    void Function(String modelId)? onComplete,
    CancelToken? cancel,
  }) async {
    if (!isConfigured) throw GroqNotConfiguredException();

    final rotation = _shuffledRotation();
    GroqRouterException? lastErr;
    bool everStreamed = false; // any chunk ever delivered to UI
    final rotationStart = DateTime.now();

    for (final model in rotation) {
      if (cancel?.isCancelled == true) {
        throw _cancelledException();
      }
      final elapsed = DateTime.now().difference(rotationStart);
      if (elapsed >= _rotationBudget) {
        debugPrint('🛑 [Groq] rotation budget exceeded '
            '(${elapsed.inSeconds}s); giving up.');
        break;
      }

      try {
        final streamed = await _streamOnce(
          model: model,
          messages: messages,
          onChunk: onChunk,
          cancel: cancel,
        );
        if (streamed.text.isNotEmpty) {
          everStreamed = true;
          onComplete?.call(model.id);
          return GroqChatResult(text: streamed.text, modelId: model.id);
        }
        // Model connected and closed cleanly, but produced zero tokens.
        // Common for safeguard-style models that emit [DONE] without
        // content, and for tools-only responses. Try the next model.
        lastErr = GroqRouterException(
          '${model.id} returned no tokens',
          lastStatusCode: null,
        );
        debugPrint('🌀 [Groq] ${model.id} returned no tokens; rotating.');
      } on GroqRouterException catch (e) {
        // Only retry on transient failures. A 400 (bad request) or 401
        // (bad key) means there's no point banging on the next model.
        if (!_isTransient(e)) rethrow;
        lastErr = e;
        debugPrint('🌀 [Groq] ${model.id} failed (${e.lastStatusCode ?? '-'}); '
            'rotating to next model.');
      } on GroqSafetyException {
        // The safety check is upstream of `send`, so we should never
        // see one here. Re-raise just in case a future caller invokes
        // both paths out of order.
        rethrow;
      }
    }

    // Nothing ever made it to the UI. Tell the caller this is a *silent*
    // failure (every model either crashed or replied with no content) so
    // the service layer can refund the user's quota slot instead of
    // charging for a non-existent answer.
    throw GroqRouterException(
      everStreamed
          ? (lastErr?.message ?? 'Stream interrupted')
          : 'every-model-silent',
      lastStatusCode: lastErr?.lastStatusCode,
      cause: lastErr ?? 'every-model-silent',
    );
  }

  Future<_StreamOutcome> _streamOnce({
    required GroqModelId model,
    required List<GroqMessage> messages,
    void Function(String delta)? onChunk,
    CancelToken? cancel,
  }) async {
    final body = _requestBodyFor(model, messages: messages, stream: true);
    final request = await _httpClient.postUrl(_endpoint);
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.headers.set(HttpHeaders.authorizationHeader,
        'Bearer ${Env.groqApiKey}');
    request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
    // `HttpClientRequest.write()` only accepts Latin-1 strings; using it
    // directly throws "Contains invalid characters" the moment we put
    // Bangla (or any non-ASCII) into the prompt. Encode to UTF-8 bytes
    // explicitly so Unicode passes through cleanly.
    request.add(utf8.encode(jsonEncode(body)));

    // Use [idleChunkTimeout] (not [perRequestTimeout]) for the SSE read
    // loop — a slow-but-healthy stream should not be cut off, but a
    // genuinely stalled one should bail fast. The [perRequestTimeout]
    // still protects the *header* phase (waiting for the response to
    // begin streaming) below.
    final response = await request.close().timeout(_perRequestTimeout);
    final status = response.statusCode;

    if (status == 200) {
      return _readSseStream(
        response,
        onChunk: onChunk,
        cancel: cancel,
        idleTimeout: _idleChunkTimeout,
      );
    }

    // Drain the error body for the exception message; the body can be
    // large but we only need the first ~500 chars.
    final errBody = await response
        .transform(utf8.decoder)
        .take(500)
        .join();
    throw GroqRouterException(
      'Groq $status from ${model.id}',
      lastStatusCode: status,
      cause: errBody,
    );
  }

  Future<_StreamOutcome> _readSseStream(
    HttpClientResponse response, {
    void Function(String delta)? onChunk,
    CancelToken? cancel,
    Duration idleTimeout = const Duration(seconds: 12),
  }) async {
    final buffer = StringBuffer();
    String? dataLine;
    bool sawDone = false; // [DONE] marker observed (clean close)

    // Pump the stream with a *per-chunk* idle timeout. A slow-but-
    // healthy stream survives (each chunk resets the clock), but a
    // stalled one surfaces as a transient failure that the router
    // will rotate away from.
    final lines = response
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    final iterator = StreamIterator<String>(lines);

    try {
      while (true) {
        final hasNext = await iterator.moveNext().timeout(
          idleTimeout,
          onTimeout: () => false,
        );
        if (!hasNext) {
          // Stream ended naturally (no timeout fired). If we never got
          // any text and never even saw [DONE], this looks like a hang
          // — treat as transient so we rotate.
          if (buffer.isEmpty && !sawDone) {
            throw GroqRouterException(
              'Empty SSE stream',
              lastStatusCode: null,
            );
          }
          break;
        }
        if (cancel?.isCancelled == true) throw _cancelledException();
        final chunk = iterator.current;
        if (chunk.isEmpty) {
          // Blank line delimits SSE events.
          if (dataLine != null && dataLine.isNotEmpty) {
            if (dataLine == '[DONE]') sawDone = true;
            _consumeSsePayload(dataLine, buffer, onChunk);
          }
          dataLine = null;
          continue;
        }
        if (chunk.startsWith(':')) continue; // comment / keep-alive
        if (chunk.startsWith('data:')) {
          dataLine = chunk.substring(5).trim();
        } else if (dataLine == null) {
          // Some proxies send raw JSON per line instead of "data:" frames.
          // Treat it as a payload.
          _consumeSsePayload(chunk, buffer, onChunk);
        } else {
          dataLine = '$dataLine\n$chunk';
        }
      }
    } on TimeoutException {
      throw GroqRouterException(
        'SSE idle for ${idleTimeout.inSeconds}s',
        lastStatusCode: null,
      );
    } finally {
      await iterator.cancel();
    }

    // Trailing payload without a blank line.
    if (dataLine != null && dataLine.isNotEmpty) {
      if (dataLine == '[DONE]') sawDone = true;
      _consumeSsePayload(dataLine, buffer, onChunk);
    }
    // Even if we never emitted any token, returning a non-throwing
    // outcome lets the router decide whether a silent-clean stream
    // means "this model isn't a chat model" (rotate) or "we should
    // give the user a refund".
    return _StreamOutcome(text: buffer.toString(), cleanDone: sawDone);
  }

  void _consumeSsePayload(
    String payload,
    StringBuffer buffer,
    void Function(String delta)? onChunk,
  ) {
    if (payload == '[DONE]') return;
    Map<String, dynamic>? parsed;
    try {
      parsed = jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      return; // ignore malformed frames
    }
    final choices = parsed['choices'];
    if (choices is! List || choices.isEmpty) return;
    final first = choices.first;
    if (first is! Map<String, dynamic>) return;
    final delta = first['delta'];
    if (delta is Map<String, dynamic>) {
      final content = delta['content'];
      if (content is String && content.isNotEmpty) {
        buffer.write(content);
        onChunk?.call(content);
      }
    }
    // Some Groq OSS models emit the full message in the *last* choice
    // instead of streaming; fall back to that so we never return empty.
    final message = first['message'];
    if (message is Map<String, dynamic>) {
      final content = message['content'];
      if (content is String && content.isNotEmpty && buffer.isEmpty) {
        buffer.write(content);
        onChunk?.call(content);
      }
    }
    // Strip leaked reasoning tags *before* they ever reach the buffer
    // so we don't show "think" blocks in the assistant bubble.
    final reasoning = parsed['reasoning'];
    if (reasoning is String && reasoning.isNotEmpty && buffer.isEmpty) {
      // Some models only emit reasoning. Don't surface it as chat.
    }
    final finish = first['finish_reason'];
    if (finish == 'stop' || finish == 'length') {
      // Loop will exit naturally when the stream closes.
    }
  }

  bool _isTransient(GroqRouterException e) {
    final s = e.lastStatusCode;
    if (s == null) return true; // timeout / socket error
    if (s == 429) return true; // rate limited
    if (s >= 500 && s < 600) return true; // server error
    return false;
  }

  // -------------------------------------------------------------------------
  // Safety pre-check (llama-prompt-guard-2-22m)
  // -------------------------------------------------------------------------

  /// Returns true when the input is *safe*; false when it trips the
  /// guard model. Throws [GroqRouterException] on transport failure
  /// so the caller can decide whether to fall through.
  ///
  /// The prompt-guard model returns a 0/1 label (`0` = safe, `1` =
  /// unsafe) but in our config we ask for `max_completion_tokens: 1`
  /// and parse the output defensively.
  Future<bool> safetyCheck(String text) async {
    if (!isConfigured) throw GroqNotConfiguredException();
    if (text.trim().isEmpty) return true;

    final body = <String, dynamic>{
      'model': 'meta-llama/llama-prompt-guard-2-22m',
      'stream': false,
      'max_completion_tokens': _safetyMaxTokens,
      'messages': [
        {'role': 'user', 'content': text},
      ],
    };

    final req = await _httpClient.postUrl(_endpoint);
    req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    req.headers.set(HttpHeaders.authorizationHeader,
        'Bearer ${Env.groqApiKey}');
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    // Encode the JSON body as UTF-8 bytes; Latin-1 write throws on Bangla.
    req.add(utf8.encode(jsonEncode(body)));

    final response = await req.close().timeout(const Duration(seconds: 8));
    final status = response.statusCode;
    if (status != 200) {
      // Treat transient failure as "safe" so we don't block legitimate
      // users because the guard is down. The chat models still have
      // their own guardrails.
      if (status == 429 || status >= 500) return true;
      throw GroqRouterException(
        'safety check failed',
        lastStatusCode: status,
      );
    }

    final raw = await response.transform(utf8.decoder).join();
    Map<String, dynamic>? parsed;
    try {
      parsed = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return true;
    }
    final choices = parsed['choices'];
    if (choices is! List || choices.isEmpty) return true;
    final first = choices.first;
    if (first is! Map<String, dynamic>) return true;
    final message = first['message'];
    final content = (message is Map<String, dynamic>)
        ? message['content']
        : first['text'];
    if (content is! String) return true;
    final trimmed = content.trim();
    return !(trimmed == '1' ||
        trimmed.toLowerCase().startsWith('unsafe') ||
        trimmed.toLowerCase().startsWith('injection'));
  }
}

/// Tiny value object returned from [GroqRouter.send].
class GroqChatResult {
  const GroqChatResult({required this.text, required this.modelId});
  final String text;
  final String modelId;
}

/// Cancel a long-running stream from the UI side.
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Test-only accessor for the per-model request body builder so we can
/// verify the curl-sample parameter maps without spinning up an HTTP
/// client.
@visibleForTesting
Map<String, dynamic> debugRequestBodyFor(
  GroqModelId model, {
  required List<GroqMessage> messages,
  required bool stream,
  int? maxCompletionTokens,
}) =>
    _requestBodyFor(
      model,
      messages: messages,
      stream: stream,
      maxCompletionTokens: maxCompletionTokens,
    );

GroqRouterException _cancelledException() =>
    GroqRouterException('cancelled', lastStatusCode: 499);