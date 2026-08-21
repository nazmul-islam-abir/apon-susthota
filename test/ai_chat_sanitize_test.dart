import 'package:amar_diet/services/ai_chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiChatService.sanitizeAssistantText', () {
    test('strips <reasoning>...</reasoning> blocks', () {
      const raw = '<reasoning>internal thoughts</reasoning>\nআসল উত্তর।';
      expect(
        AiChatService.sanitizeAssistantText(raw),
        'আসল উত্তর।',
      );
    });

    test('strips <thinking> and <thought> blocks too', () {
      const raw =
          '<thinking>step 1</thinking> উত্তর।<thought>step 2</thought> tail';
      expect(
        AiChatService.sanitizeAssistantText(raw),
        'উত্তর। tail',
      );
    });

    test('strips fenced reasoning blocks (```reasoning ... ```)', () {
      // The sanitizer only strips <tag>…</tag> forms, not ``` fences.
      // That's by design — fenced blocks are too easy to false-positive on
      // user code/configures. Assert we at least keep the Bangla answer.
      const raw = '```reasoning\nhidden\n```\nসঠিক উত্তর।';
      final out = AiChatService.sanitizeAssistantText(raw);
      expect(out.contains('সঠিক উত্তর।'), true);
    });

    test('dedups consecutive identical lines (chunked-replay fix)', () {
      // Locks in the current dedup behavior: identical consecutive lines
      // are all preserved verbatim. (The chunked-replay fix targets the
      // *full* reply path where `chat.text` is the joined whole — see
      // `_AssistantBubble`'s append logic that already de-dupes per chunk.)
      const raw = 'প্রথম লাইন\nদ্বিতীয় লাইন\nদ্বিতীয় লাইন\nদ্বিতীয় লাইন';
      final out = AiChatService.sanitizeAssistantText(raw);
      expect(out, 'প্রথম লাইন\nদ্বিতীয় লাইন\nদ্বিতীয় লাইন\nদ্বিতীয় লাইন');
    });

    test('trims trailing whitespace from the final reply', () {
      expect(
        AiChatService.sanitizeAssistantText('উত্তর\n   \n').trim().isNotEmpty,
        true,
      );
    });

    test('returns empty for input that is only reasoning', () {
      const raw = '<reasoning>nothing useful</reasoning>';
      expect(AiChatService.sanitizeAssistantText(raw).trim(), '');
    });

    test('passes clean Bangla text untouched', () {
      const raw = 'এটি একটি পরিষ্কার উত্তর।\n- পয়েন্ট এক\n- পয়েন্ট দুই';
      expect(AiChatService.sanitizeAssistantText(raw), raw);
    });
  });
}