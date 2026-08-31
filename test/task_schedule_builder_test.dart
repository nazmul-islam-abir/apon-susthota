import 'package:flutter_test/flutter_test.dart';

import 'package:amar_diet/models/medicine.dart';
import 'package:amar_diet/services/task_schedule_builder.dart';

void main() {
  group('buildMedicineTasks — 2-min pre-alert', () {
    test('08:00 slot → fires at 07:58 today', () {
      final now = DateTime(2026, 8, 31, 6, 0); // 06:00 today
      final med = _med(
        id: 'm1',
        schedule: const [
          MedicineScheduleSlot(time: '08:00', bucket: TimeBucket.morning),
        ],
      );
      final tasks = buildMedicineTasks(medicines: [med], now: now);
      expect(tasks, hasLength(1));
      expect(tasks.first.fireAt, DateTime(2026, 8, 31, 7, 58));
      expect(tasks.first.title, contains('ওষুধ'));
    });

    test('past slot (08:00, now 09:00) is skipped', () {
      final now = DateTime(2026, 8, 31, 9, 0);
      final med = _med(
        id: 'm1',
        schedule: const [
          MedicineScheduleSlot(time: '08:00', bucket: TimeBucket.morning),
        ],
      );
      final tasks = buildMedicineTasks(medicines: [med], now: now);
      expect(tasks, isEmpty);
    });

    test('multiple slots → one task per future slot', () {
      final now = DateTime(2026, 8, 31, 0, 0);
      final med = _med(
        id: 'm1',
        schedule: const [
          MedicineScheduleSlot(time: '08:00', bucket: TimeBucket.morning),
          MedicineScheduleSlot(time: '14:00', bucket: TimeBucket.afternoon),
          MedicineScheduleSlot(time: '21:00', bucket: TimeBucket.night),
        ],
      );
      final tasks = buildMedicineTasks(medicines: [med], now: now);
      expect(tasks, hasLength(3));
      expect(tasks.map((t) => t.fireAt), [
        DateTime(2026, 8, 31, 7, 58),
        DateTime(2026, 8, 31, 13, 58),
        DateTime(2026, 8, 31, 20, 58),
      ]);
    });

    test('inactive medicines are skipped', () {
      final now = DateTime(2026, 8, 31, 0, 0);
      final med = _med(
        id: 'm1',
        isActive: false,
        schedule: const [
          MedicineScheduleSlot(time: '08:00', bucket: TimeBucket.morning),
        ],
      );
      final tasks = buildMedicineTasks(medicines: [med], now: now);
      expect(tasks, isEmpty);
    });

    test('taken-today key drops the matching reminder', () {
      final now = DateTime(2026, 8, 31, 0, 0);
      final med = _med(
        id: 'm1',
        schedule: const [
          MedicineScheduleSlot(time: '08:00', bucket: TimeBucket.morning),
        ],
      );
      final tasks = buildMedicineTasks(
        medicines: [med],
        now: now,
        takenToday: {'m1@08:00'},
      );
      expect(tasks, isEmpty);
    });
  });

  group('buildMealTasks — default 5 slots', () {
    test('produces 5 tasks before breakfast time', () {
      final now = DateTime(2026, 8, 31, 0, 0);
      final tasks = buildMealTasks(now: now);
      expect(tasks, hasLength(5));
      // First slot is breakfast 08:00 → fires 07:58.
      expect(tasks.first.fireAt, DateTime(2026, 8, 31, 7, 58));
    });

    test('at noon only the post-noon slots survive', () {
      final now = DateTime(2026, 8, 31, 12, 0);
      final tasks = buildMealTasks(now: now);
      // 08:00 and 11:00 are past; 13:30 / 17:00 / 20:30 remain.
      expect(tasks, hasLength(3));
      expect(tasks.first.fireAt, DateTime(2026, 8, 31, 13, 28));
    });

    test('payload encodes slot + iso time', () {
      final now = DateTime(2026, 8, 31, 0, 0);
      final tasks = buildMealTasks(now: now);
      expect(tasks.first.payload, startsWith('v1:meal:'));
    });
  });

  group('buildWorkoutTasks — 5 fixed daily slots', () {
    test('all-complete → empty list', () {
      final now = DateTime(2026, 8, 31, 12, 0);
      final tasks = buildWorkoutTasks(
        dayIndex: 3,
        workoutCountForToday: 4,
        allComplete: true,
        now: now,
      );
      expect(tasks, isEmpty);
    });

    test('zero workouts today → empty list', () {
      final now = DateTime(2026, 8, 31, 5, 0);
      final tasks = buildWorkoutTasks(
        dayIndex: 7, // rest day
        workoutCountForToday: 0,
        allComplete: false,
        now: now,
      );
      expect(tasks, isEmpty);
    });

    test('schedules 5 tasks when there are pending workouts', () {
      final now = DateTime(2026, 8, 31, 0, 0);
      final tasks = buildWorkoutTasks(
        dayIndex: 3,
        workoutCountForToday: 4,
        allComplete: false,
        now: now,
      );
      expect(tasks, hasLength(5));
      expect(tasks.first.fireAt, DateTime(2026, 8, 31, 6, 58)); // 07:00 - 2m
    });
  });

  group('buildWaterTasks — 8 evenly spread', () {
    test('wake window 08:00–22:00 → 8 tasks, all in the future', () {
      final today = DateTime(2026, 8, 31);
      final wakeFrom = DateTime(today.year, today.month, today.day, 8, 0);
      final wakeTo = DateTime(today.year, today.month, today.day, 22, 0);
      final tasks = buildWaterTasks(
        now: DateTime(today.year, today.month, today.day, 0, 0),
        wakeFrom: wakeFrom,
        wakeTo: wakeTo,
      );
      expect(tasks, hasLength(8));
      // All fire 2 min before their slot, so first is 06:28 in device TZ.
      expect(tasks.first.fireAt, DateTime(today.year, today.month, today.day, 8, 0)
          .subtract(const Duration(minutes: 2)));
    });

    test('past slots are pruned', () {
      final today = DateTime(2026, 8, 31);
      final wakeFrom = DateTime(today.year, today.month, today.day, 8, 0);
      final wakeTo = DateTime(today.year, today.month, today.day, 22, 0);
      // "Now" is 14:00 — only the 14:00+ slots should survive.
      final tasks = buildWaterTasks(
        now: DateTime(today.year, today.month, today.day, 14, 0),
        wakeFrom: wakeFrom,
        wakeTo: wakeTo,
      );
      // 4 of 8 slots remain (the afternoon/evening ones).
      expect(tasks.length, lessThan(8));
      expect(tasks.length, greaterThan(0));
      for (final t in tasks) {
        expect(t.fireAt.isAfter(DateTime(today.year, today.month, today.day, 14, 0)), isTrue);
      }
    });
  });

  group('inferWakeWindowFromMeds', () {
    test('uses first/last dose ± 30 min as the window', () {
      final today = DateTime(2026, 8, 31);
      final meds = [
        _med(
          id: 'a',
          schedule: const [
            MedicineScheduleSlot(time: '07:00', bucket: TimeBucket.morning),
          ],
        ),
        _med(
          id: 'b',
          schedule: const [
            MedicineScheduleSlot(time: '22:00', bucket: TimeBucket.night),
          ],
        ),
      ];
      final window = inferWakeWindowFromMeds(meds, today);
      expect(window, isNotNull);
      expect(window!.wakeFrom.hour, 6); // 07:00 - 30min = 06:30 → 06:00 (clamped)
      expect(window.wakeTo.hour, 22); // 22:00 + 30min = 22:30 → clamped to 23:00
    });

    test('returns null when no medicines', () {
      final today = DateTime(2026, 8, 31);
      expect(inferWakeWindowFromMeds([], today), isNull);
    });
  });
}

Medicine _med({
  required String id,
  List<MedicineScheduleSlot> schedule = const [],
  bool isActive = true,
}) {
  return Medicine(
    id: id,
    nameBn: 'মেটফরমিন',
    nameEn: 'Metformin',
    form: 'tablet',
    strength: '500mg',
    doseAmount: 1,
    doseUnit: 'unit',
    mealRelation: 'after',
    schedule: schedule,
    startDate: DateTime(2026, 1, 1),
    isActive: isActive,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}
