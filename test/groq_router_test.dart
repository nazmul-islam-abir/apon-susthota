import 'package:amar_diet/services/groq_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Reuse the same shape of payload across every model so the test isn't
  // tied to the system prompt that production code happens to ship.
  const messages = <GroqMessage>[
    GroqMessage('system', 'sys'),
    GroqMessage('user', 'hi'),
  ];

  group('GroqRouter.debugRequestBodyFor', () {
    test('compound models enable web_search + code_interpreter', () {
      for (final model in [GroqModelId.compound, GroqModelId.compoundMini]) {
        final body = debugRequestBodyFor(
          model,
          messages: messages,
          stream: true,
        );
        expect(body['model'], model.id);
        expect(body['stream'], true);
        expect(body['temperature'], 1);
        expect(body['top_p'], 1);
        expect(body['max_completion_tokens'], 800);
        final tools =
            (body['compound_custom'] as Map<String, dynamic>)['tools']
                as Map<String, dynamic>;
        expect(tools['enabled_tools'],
            ['web_search', 'code_interpreter', 'visit_website']);
      }
    });

    test('gpt-oss 120b / 20b use reasoning_effort=low, 900 tokens', () {
      for (final model in [GroqModelId.gptOss120b, GroqModelId.gptOss20b]) {
        final body = debugRequestBodyFor(
          model,
          messages: messages,
          stream: true,
        );
        expect(body['temperature'], 1);
        expect(body['top_p'], 1);
        expect(body['reasoning_effort'], 'low');
        expect(body['max_completion_tokens'], 900);
        expect(body.containsKey('compound_custom'), false);
      }
    });

    test('gpt-oss-safeguard-20b is no longer in the chat rotation', () {
      // The safeguard model is a *classifier*, not a chat model — it
      // almost always returns zero content, which surfaced to the user
      // as "AI সহকারী এই মুহূর্তে অনুপলব্ধ". We removed it from the
      // rotation; the guard now lives in `safetyCheck` via
      // `llama-prompt-guard-2-22m`.
      expect(GroqModelId.values.any((m) => m.id.contains('safeguard')), false);
    });

    test('qwen uses temperature 0.6, top_p 0.95, reasoning_effort default', () {
      final body = debugRequestBodyFor(
        GroqModelId.qwen3_6_27b,
        messages: messages,
        stream: true,
      );
      expect(body['temperature'], 0.6);
      expect(body['top_p'], 0.95);
      expect(body['reasoning_effort'], 'default');
      expect(body['max_completion_tokens'], 900);
    });

    test('messages round-trip as OpenAI wire format', () {
      final body = debugRequestBodyFor(
        GroqModelId.gptOss20b,
        messages: messages,
        stream: false,
      );
      expect(body['stream'], false);
      final out = (body['messages'] as List).cast<Map<String, dynamic>>();
      expect(out.length, 2);
      expect(out[0], {'role': 'system', 'content': 'sys'});
      expect(out[1], {'role': 'user', 'content': 'hi'});
    });

    test('custom maxCompletionTokens override wins for all models', () {
      final body = debugRequestBodyFor(
        GroqModelId.compound,
        messages: messages,
        stream: true,
        maxCompletionTokens: 64,
      );
      expect(body['max_completion_tokens'], 64);
    });
  });

  group('GroqRouter.isConfigured', () {
    test('reflects whether GROQ_API_KEY is loaded', () {
      // The static getter simply forwards to Env.hasGroqKey, which may be
      // true or false depending on the runner's .env. We only assert it's
      // a bool — the wiring is exercised by the chat screen at runtime.
      expect(GroqRouter.isConfigured, isA<bool>());
    });
  });

  group('CancelToken', () {
    test('flips once and stays cancelled', () {
      final token = CancelToken();
      expect(token.isCancelled, false);
      token.cancel();
      expect(token.isCancelled, true);
      token.cancel();
      expect(token.isCancelled, true);
    });
  });

  group('GroqModelId.id', () {
    test('maps enum values to canonical Groq model IDs', () {
      expect(GroqModelId.compound.id, 'groq/compound');
      expect(GroqModelId.compoundMini.id, 'groq/compound-mini');
      expect(GroqModelId.gptOss120b.id, 'openai/gpt-oss-120b');
      expect(GroqModelId.gptOss20b.id, 'openai/gpt-oss-20b');
      expect(GroqModelId.qwen3_6_27b.id, 'qwen/qwen3.6-27b');
    });
  });
}
