/// Pure functions that turn user data into the list of pending
/// notifications for each task type.
///
/// Each scheduler (medicine / meal / workout / water) calls its own
/// `build*Tasks()` function, gets a `List<PendingTask>`, and hands them
/// off to `LocalNotifications.schedule(...)`.
///
/// **Why pure?** All time-math lives here so it can be unit-tested
/// without touching `flutter_local_notifications`, SharedPreferences,
/// or any platform channel.
///
/// **Why 2 minutes?** Your spec: "alert the user 2 min before the task
/// is due". Tunable via [kPreAlert] if we want to let users change it
/// later.
library;

import '../models/medicine.dart';

/// How early before the scheduled time the notification should fire.
const Duration kPreAlert = Duration(minutes: 2);

/// Stable int id ranges (must not overlap). Used by the facade so we
/// can cancel-by-id without collisions across task types.
class TaskIdRange {
  static const int medicineStart = 1000000;
  static const int medicineEnd = 1099999;
  static const int mealStart = 1100000;
  static const int mealEnd = 1199999;
  static const int workoutStart = 1200000;
  static const int workoutEnd = 1299999;
  static const int waterStart = 1300000;
  static const int waterEnd = 1399999;
}

/// What kind of task a notification represents — used by the tap-router
/// in the facade.
enum TaskType { medicine, meal, workout, water }

/// One reminder, ready to hand to `flutter_local_notifications`.
class PendingTask {
  /// Stable int id (see [TaskIdRange]).
  final int id;

  /// When to fire. The facade converts this to a `tz.TZDateTime`.
  final DateTime fireAt;

  /// Localised headline (e.g. "ওষুধ নেওয়ার সময় হবে").
  final String title;

  /// Localised body (e.g. "মেটফরমিন ৫০০mg — ১ ট্যাবলেট — ২ মিনিট পর").
  final String body;

  /// Payload format: `v1:<type>:<id>:<iso>`.
  final String payload;

  /// Used by the scheduler to group related reminders (e.g. cancel all
  /// medicine reminders when one is taken).
  final TaskType type;

  /// Optional grouping key. For medicines this is the medicine id so
  /// we can cancel every reminder for one medicine at once. For meals
  /// it's the slot name. For workouts it's the dayIndex. For water
  /// it's the slot index.
  final String groupKey;

  const PendingTask({
    required this.id,
    required this.fireAt,
    required this.title,
    required this.body,
    required this.payload,
    required this.type,
    required this.groupKey,
  });
}

/// Helper: combine today's date with an HH:mm time string into a
/// device-local DateTime. Returns null if the time can't be parsed.
DateTime? _todayAtTime(DateTime today, String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return DateTime(today.year, today.month, today.day, h, m);
}

// ════════════════════════════════════════════════════════════════════════
//  MEDICINE TASKS
// ════════════════════════════════════════════════════════════════════════

/// Build today's medicine reminders. Skips slots whose
/// `scheduledTime - 2 min` has already passed (no point reminding
/// the user about 08:00 medicine at 09:00 — they should have taken it).
///
/// [takenToday] is a set of synthetic keys (medicineId + iso-time) for
/// doses already marked taken today, so we don't nag the user again.
List<PendingTask> buildMedicineTasks({
  required List<Medicine> medicines,
  required DateTime now,
  Set<String> takenToday = const {},
  bool localeBangla = true,
}) {
  final out = <PendingTask>[];
  final today = DateTime(now.year, now.month, now.day);
  var nextId = TaskIdRange.medicineStart;

  for (final med in medicines) {
    if (!med.isActive) continue;
    for (var i = 0; i < med.schedule.length; i++) {
      final slot = med.schedule[i];
      final base = _todayAtTime(today, slot.time);
      if (base == null) continue;
      final fireAt = base.subtract(kPreAlert);

      // Skip past slots — we never want a "your 08:00 medicine is due"
      // notification at 14:00.
      if (fireAt.isBefore(now)) continue;

      final key = '${med.id}@${slot.time}';
      if (takenToday.contains(key)) continue;

      final doseLabel = med.doseLabel;
      final medName = med.nameBn.isNotEmpty
          ? med.nameBn
          : (med.nameEn ?? '');
      final title = localeBangla
          ? 'ওষুধ নেওয়ার সময় হবে'
          : 'Medicine due soon';
      final body = localeBangla
          ? '$medName — $doseLabel — ২ মিনিট পর'
          : '$medName — $doseLabel — in 2 minutes';

      out.add(PendingTask(
        id: nextId++,
        fireAt: fireAt,
        title: title,
        body: body,
        payload: 'v1:medicine:${med.id}:${slot.time}',
        type: TaskType.medicine,
        groupKey: med.id,
      ));
    }
  }
  return out;
}

// ════════════════════════════════════════════════════════════════════════
//  MEAL TASKS
// ════════════════════════════════════════════════════════════════════════

/// Default reminder times per meal slot. Tuned for a Bangladeshi day
/// — breakfast before work, snacks mid-morning / late-afternoon,
/// lunch, dinner.
const Map<String, String> kDefaultMealTimes = {
  'breakfast': '08:00',
  'morning_snack': '11:00',
  'lunch': '13:30',
  'evening_snack': '17:00',
  'dinner': '20:30',
};

/// Build today's meal reminders. Skips past slots.
List<PendingTask> buildMealTasks({
  required DateTime now,
  bool localeBangla = true,
}) {
  final out = <PendingTask>[];
  final today = DateTime(now.year, now.month, now.day);
  var nextId = TaskIdRange.mealStart;

  kDefaultMealTimes.forEach((slot, hhmm) {
    final base = _todayAtTime(today, hhmm);
    if (base == null) return;
    final fireAt = base.subtract(kPreAlert);
    if (fireAt.isBefore(now)) return;

    final titleBn = _mealTitleBn(slot);
    final titleEn = _mealTitleEn(slot);
    final body = localeBangla
        ? '$titleBn — ২ মিনিট পর খাবার'
        : '$titleEn — in 2 minutes';
    out.add(PendingTask(
      id: nextId++,
      fireAt: fireAt,
      title: localeBangla ? 'খাবারের সময় হবে' : 'Meal due soon',
      body: body,
      payload: 'v1:meal:$slot:${hhmm}',
      type: TaskType.meal,
      groupKey: slot,
    ));
  });
  return out;
}

String _mealTitleBn(String slot) {
  switch (slot) {
    case 'breakfast':
      return 'সকালের নাস্তা';
    case 'morning_snack':
      return 'সকালের স্ন্যাক্স';
    case 'lunch':
      return 'দুপুরের খাবার';
    case 'evening_snack':
      return 'বিকেলের স্ন্যাক্স';
    case 'dinner':
      return 'রাতের খাবার';
    default:
      return slot;
  }
}

String _mealTitleEn(String slot) {
  switch (slot) {
    case 'breakfast':
      return 'Breakfast';
    case 'morning_snack':
      return 'Morning snack';
    case 'lunch':
      return 'Lunch';
    case 'evening_snack':
      return 'Evening snack';
    case 'dinner':
      return 'Dinner';
    default:
      return slot;
  }
}

// ════════════════════════════════════════════════════════════════════════
//  WORKOUT TASKS
// ════════════════════════════════════════════════════════════════════════

/// Five fixed daily workout reminders, as agreed in the plan.
const List<TimeOfDayStruct> kWorkoutSlots = [
  TimeOfDayStruct(7, 0),
  TimeOfDayStruct(10, 30),
  TimeOfDayStruct(13, 0),
  TimeOfDayStruct(17, 30),
  TimeOfDayStruct(21, 0),
];

/// Minimal struct so we don't pull `flutter/material.dart` into this
/// pure module — keeps unit tests lightweight.
class TimeOfDayStruct {
  final int hour;
  final int minute;
  const TimeOfDayStruct(this.hour, this.minute);
}

/// Build today's workout reminders. Returns an empty list when [allComplete]
/// is true (every workout marked done → no more nagging today).
List<PendingTask> buildWorkoutTasks({
  required int dayIndex,
  required int workoutCountForToday,
  required bool allComplete,
  required DateTime now,
  bool localeBangla = true,
}) {
  if (allComplete || workoutCountForToday == 0) return const [];
  final out = <PendingTask>[];
  final today = DateTime(now.year, now.month, now.day);

  for (var i = 0; i < kWorkoutSlots.length; i++) {
    final slot = kWorkoutSlots[i];
    final base = DateTime(today.year, today.month, today.day,
        slot.hour, slot.minute);
    final fireAt = base.subtract(kPreAlert);
    if (fireAt.isBefore(now)) continue;

    final hhmm =
        '${slot.hour.toString().padLeft(2, '0')}:${slot.minute.toString().padLeft(2, '0')}';
    final slotLabel = localeBangla ? 'স্লট ${i + 1}' : 'slot ${i + 1}';
    final body = localeBangla
        ? 'দিন $dayIndex — $workoutCountForToday টি ব্যায়াম বাকি আছে ($slotLabel) — ২ মিনিট পর শুরু'
        : 'Day $dayIndex — $workoutCountForToday workout(s) pending ($slotLabel) — start in 2 minutes';
    out.add(PendingTask(
      id: TaskIdRange.workoutStart + dayIndex * 10 + i,
      fireAt: fireAt,
      title: localeBangla ? 'ব্যায়ামের সময় হবে' : 'Workout due soon',
      body: body,
      payload: 'v1:workout:$dayIndex:$hhmm',
      type: TaskType.workout,
      groupKey: '$dayIndex',
    ));
  }
  return out;
}

// ════════════════════════════════════════════════════════════════════════
//  WATER TASKS
// ════════════════════════════════════════════════════════════════════════

/// Build today's water reminders, evenly spaced between [wakeFrom] and
/// [wakeTo] (device-local). [count] reminders total. The default of 8
/// matches a 2.5L / 250ml-per-glass daily target.
///
/// If [wakeFrom]/[wakeTo] fall outside the same calendar day, the
/// function silently skips past slots and returns whatever fits.
List<PendingTask> buildWaterTasks({
  required DateTime now,
  required DateTime wakeFrom,
  required DateTime wakeTo,
  int count = 8,
  bool localeBangla = true,
}) {
  if (count <= 0 || !wakeTo.isAfter(wakeFrom)) return const [];
  final out = <PendingTask>[];
  final spanMin = wakeTo.difference(wakeFrom).inMinutes;
  final stepMin = (spanMin / count).floor();
  if (stepMin <= 0) return const [];

  for (var i = 0; i < count; i++) {
    final base = wakeFrom.add(Duration(minutes: stepMin * i));
    final fireAt = base.subtract(kPreAlert);
    if (fireAt.isBefore(now)) continue;

    final hhmm =
        '${base.hour.toString().padLeft(2, '0')}:${base.minute.toString().padLeft(2, '0')}';
    final body = localeBangla
        ? 'এক গ্লাস পানি পান করুন — ২ মিনিট পর'
        : 'Drink a glass of water — in 2 minutes';
    out.add(PendingTask(
      id: TaskIdRange.waterStart + i,
      fireAt: fireAt,
      title: localeBangla ? 'পানি পানের সময়' : 'Time to hydrate',
      body: body,
      payload: 'v1:water:$i:$hhmm',
      type: TaskType.water,
      groupKey: '$i',
    ));
  }
  return out;
}

/// Heuristic: derive a sensible wake window from a list of medicine
/// schedule times. Returns null if the list is empty so the caller can
/// fall back to the default 08:00–22:00 window.
({DateTime wakeFrom, DateTime wakeTo})? inferWakeWindowFromMeds(
  List<Medicine> medicines,
  DateTime today,
) {
  if (medicines.isEmpty) return null;
  final times = <int>[];
  for (final m in medicines) {
    for (final s in m.schedule) {
      final t = _todayAtTime(today, s.time);
      if (t != null) times.add(t.hour * 60 + t.minute);
    }
  }
  if (times.isEmpty) return null;
  times.sort();
  final firstMin = times.first;
  final lastMin = times.last;
  // Pad 30 minutes either side — but clamp to a sane 06:00–23:00 window.
  final wakeFromMin = (firstMin - 30).clamp(6 * 60, 23 * 60);
  final wakeToMin = (lastMin + 30).clamp(6 * 60 + 30, 23 * 60);
  return (
    wakeFrom: DateTime(today.year, today.month, today.day, wakeFromMin ~/ 60,
        wakeFromMin % 60),
    wakeTo: DateTime(today.year, today.month, today.day, wakeToMin ~/ 60,
        wakeToMin % 60),
  );
}

/// Default wake window if we have no medicines to infer from.
({DateTime wakeFrom, DateTime wakeTo}) defaultWakeWindow(DateTime today) {
  return (
    wakeFrom: DateTime(today.year, today.month, today.day, 8, 0),
    wakeTo: DateTime(today.year, today.month, today.day, 22, 0),
  );
}
