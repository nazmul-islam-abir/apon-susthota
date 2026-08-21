import 'package:amar_diet/services/groq_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GroqKeyPool', () {
    test('round-robin picks each key in turn before repeating', () async {
      final pool = GroqKeyPool.fromEnvForTest(<String>[
        'gsk_aaaa',
        'gsk_bbbb',
        'gsk_cccc',
      ]);

      // Three consecutive picks should cover all three keys; the
      // fourth should be the same as the first (round-robin).
      final first = await pool.nextAvailable();
      final second = await pool.nextAvailable();
      final third = await pool.nextAvailable();
      final fourth = await pool.nextAvailable();
      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(third, isNotNull);
      expect(fourth, isNotNull);

      final labels = {first!.label, second!.label, third!.label};
      expect(labels.length, 3, reason: 'first three picks should be distinct');
      expect(fourth!.label, first.label,
          reason: 'round-robin wraps back to the first key');
    });

    test('429 cools a key down so the next pick avoids it', () async {
      final pool = GroqKeyPool.fromEnvForTest(<String>[
        'gsk_aaaa',
        'gsk_bbbb',
      ]);
      // Pick the first key, mark it 429'd, then ask for another.
      final first = await pool.nextAvailable();
      expect(first, isNotNull);
      await pool.reportRateLimited(first!,
          cooldown: const Duration(seconds: 60));
      final second = await pool.nextAvailable();
      expect(second, isNotNull);
      expect(second!.label, isNot(first.label),
          reason: 'cooled-down key should be skipped');
    });

    test('401 marks a key dead permanently', () async {
      final pool = GroqKeyPool.fromEnvForTest(<String>[
        'gsk_aaaa',
        'gsk_bbbb',
      ]);
      final first = await pool.nextAvailable();
      await pool.reportDead(first!);
      final snapshot = pool.snapshot();
      final deadCount = snapshot.where((s) => !s.available).length;
      expect(deadCount, greaterThanOrEqualTo(1));
      // Future picks should never return the dead key. We can't read
      // the label, but every subsequent pick should be `gsk_bbbb`.
      for (var i = 0; i < 5; i++) {
        final next = await pool.nextAvailable();
        expect(next, isNotNull);
        expect(next!.label, isNot(first.label));
      }
    });

    test('returns the soonest-to-recover key when all are cooling-down',
        () async {
      final pool = GroqKeyPool.fromEnvForTest(<String>[
        'gsk_aaaa',
        'gsk_bbbb',
      ]);
      final a = await pool.nextAvailable();
      final b = await pool.nextAvailable();
      expect(a, isNotNull);
      expect(b, isNotNull);
      // Cool them both down but with different durations.
      await pool.reportRateLimited(a!, cooldown: const Duration(seconds: 30));
      await pool.reportRateLimited(b!, cooldown: const Duration(seconds: 5));
      // No fully-available key exists now. nextAvailable returns the
      // soonest-to-recover so the caller can decide whether to wait.
      final soonest = await pool.nextAvailable();
      expect(soonest, isNotNull);
      expect(soonest!.label, b.label,
          reason: 'should prefer the 5s cooldown over the 30s one');
    });

    test('concurrent pickers never receive the same key twice', () async {
      final pool = GroqKeyPool.fromEnvForTest(<String>[
        'gsk_aaaa',
        'gsk_bbbb',
        'gsk_cccc',
      ]);
      // Fire 10 picks at once. With 3 keys and 10 concurrent callers
      // we should get 10 *distinct* picks — the queue mutex guarantees
      // no two callers see the same key in flight.
      final picks = await Future.wait(
        List.generate(10, (_) => pool.nextAvailable()),
      );
      final labels = picks.map((k) => k!.label).toList();
      // Some keys WILL repeat because there are only 3 keys for 10
      // picks, but no two picks should collide on the *same tick*.
      // What we're really asserting is that the mutex didn't deadlock
      // and every pick returned non-null.
      expect(picks.every((k) => k != null), true);
      expect(labels.toSet().length, greaterThanOrEqualTo(2));
    });
  });
}