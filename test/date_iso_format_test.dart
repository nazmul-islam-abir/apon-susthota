import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DateTime.toIso8601String substring(0,10)', () {
    test('produces YYYY-MM-DD for a mid-month date', () {
      final d = DateTime(2026, 8, 23);
      final iso = d.toIso8601String().substring(0, 10);
      expect(iso, '2026-08-23');
    });

    test('produces YYYY-MM-DD for Aug 1 (no padding issues)', () {
      final d = DateTime(2026, 8, 1);
      final iso = d.toIso8601String().substring(0, 10);
      expect(iso, '2026-08-01');
    });

    test('reproduces hand-built _dateOnly() output', () {
      String dateOnly(DateTime d) =>
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final d = DateTime(2026, 8, 23);
      expect(dateOnly(d), '2026-08-23');
    });

    test('DateTime.parse roundtrips YYYY-MM-DD to itself (year/month/day)', () {
      final d = DateTime.parse('2026-08-23');
      expect(d.year, 2026);
      expect(d.month, 8);
      expect(d.day, 23);
    });
  });
}
