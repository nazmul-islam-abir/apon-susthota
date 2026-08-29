// lib/models/thirty_day_report.dart
//
// Typed mirror of public.get_thirty_day_report() (see supabasesql/27_*).
// The RPC returns a single jsonb blob. These classes parse it strictly so the
// Doctor Report can render with guaranteed field paths.
import 'package:intl/intl.dart';

/// Summary counters across the full 30-day cycle.
class ThirtyDayTotals {
  final int daysLogged;
  final int plannedMealsTotal;
  final int loggedMealsTotal;
  final int goodMeals;
  final int moderateMeals;
  final int badMeals;
  final int offplanMeals;
  final int kcalTotal;
  final int waterMlTotal;
  final int medScheduledTotal;
  final int medTakenTotal;
  final int medMissedTotal;
  final int workoutsCompleted;
  final int workoutMinutesTotal;
  final int avgAdherencePct;

  const ThirtyDayTotals({
    this.daysLogged = 0,
    this.plannedMealsTotal = 0,
    this.loggedMealsTotal = 0,
    this.goodMeals = 0,
    this.moderateMeals = 0,
    this.badMeals = 0,
    this.offplanMeals = 0,
    this.kcalTotal = 0,
    this.waterMlTotal = 0,
    this.medScheduledTotal = 0,
    this.medTakenTotal = 0,
    this.medMissedTotal = 0,
    this.workoutsCompleted = 0,
    this.workoutMinutesTotal = 0,
    this.avgAdherencePct = 0,
  });

  factory ThirtyDayTotals.fromJson(Map<String, dynamic> j) => ThirtyDayTotals(
        daysLogged:        (j['days_logged']         ?? 0) as int,
        plannedMealsTotal: (j['planned_meals_total'] ?? 0) as int,
        loggedMealsTotal:  (j['logged_meals_total']  ?? 0) as int,
        goodMeals:         (j['good_meals']          ?? 0) as int,
        moderateMeals:     (j['moderate_meals']      ?? 0) as int,
        badMeals:          (j['bad_meals']           ?? 0) as int,
        offplanMeals:      (j['offplan_meals']       ?? 0) as int,
        kcalTotal:         (j['kcal_total']          ?? 0) as int,
        waterMlTotal:      (j['water_ml_total']      ?? 0) as int,
        medScheduledTotal: (j['med_scheduled_total'] ?? 0) as int,
        medTakenTotal:     (j['med_taken_total']     ?? 0) as int,
        medMissedTotal:    (j['med_missed_total']    ?? 0) as int,
        workoutsCompleted: (j['workouts_completed']  ?? 0) as int,
        workoutMinutesTotal: (j['workout_minutes_total'] ?? 0) as int,
        avgAdherencePct:   (j['avg_adherence_pct']   ?? 0) as int,
      );

  /// % of planned meals the user actually logged (good or moderate ok).
  double get mealAdherencePct => plannedMealsTotal == 0
      ? 0
      : ((loggedMealsTotal / plannedMealsTotal) * 100).clamp(0, 100);

  /// 0..1 ratio of doses taken vs scheduled across the cycle.
  double get medAdherenceRatio => medScheduledTotal == 0
      ? 1
      : (medTakenTotal / medScheduledTotal).clamp(0.0, 1.0);

  /// Total water in litres (UI-friendly).
  double get waterLitres => waterMlTotal / 1000.0;

  /// Average daily kcal across days the user actually logged meals on.
  double get kcalAvg =>
      daysLogged <= 0 ? 0 : (kcalTotal / daysLogged).toDouble();

  /// Days the user was expected to log (30 unless the cycle is still rolling).
  /// Set to `30` for the analytics screen — overridable per report.
  int get daysExpected => 30;

  /// Aggregate cycle breakdown used by insights UI.
  ({int good, int moderate, int bad}) get breakdown =>
      (good: goodMeals, moderate: moderateMeals, bad: badMeals);

  /// Meals logged/planned summary used by the stat grid.
  String get mealsLoggedPlannedLabel =>
      '$loggedMealsTotal/$plannedMealsTotal';
  String get medsLoggedPlannedLabel => '$medTakenTotal/$medScheduledTotal';
  String get workoutsLoggedPlannedLabel =>
      '$workoutsCompleted/${workoutMinutesTotal > 0 ? workoutMinutesTotal : workoutsCompleted}';
  String get daysLoggedExpectedLabel => '$daysLogged/$daysExpected';
}

/// Per-meal classification counts inside a day.
class LoggedMeals {
  final int good;
  final int moderate;
  final int bad;
  final int offplan;
  const LoggedMeals({this.good = 0, this.moderate = 0, this.bad = 0, this.offplan = 0});
  factory LoggedMeals.fromJson(Map<String, dynamic> j) => LoggedMeals(
        good:     (j['good']     ?? 0) as int,
        moderate: (j['moderate'] ?? 0) as int,
        bad:      (j['bad']      ?? 0) as int,
        offplan:  (j['offplan']  ?? 0) as int,
      );
  int get total => good + moderate + bad + offplan;
}

/// Daily macro aggregate inside a cycle day.
class DayMacros {
  final int kcal;
  final int carbG;
  final int proteinG;
  final int fatG;
  final int sodiumMg;
  const DayMacros({
    this.kcal = 0,
    this.carbG = 0,
    this.proteinG = 0,
    this.fatG = 0,
    this.sodiumMg = 0,
  });
  factory DayMacros.fromJson(Map<String, dynamic> j) => DayMacros(
        kcal:      (j['kcal']      ?? 0) as int,
        carbG:     (j['carb_g']    ?? 0) as int,
        proteinG:  (j['protein_g'] ?? 0) as int,
        fatG:      (j['fat_g']     ?? 0) as int,
        sodiumMg:  (j['sodium_mg'] ?? 0) as int,
      );
}

/// Medicine schedule + compliance for a single day.
class DayMedicine {
  final int scheduled;
  final int taken;
  final int missed;
  const DayMedicine({this.scheduled = 0, this.taken = 0, this.missed = 0});
  factory DayMedicine.fromJson(Map<String, dynamic> j) => DayMedicine(
        scheduled: (j['scheduled'] ?? 0) as int,
        taken:     (j['taken']     ?? 0) as int,
        missed:    (j['missed']    ?? 0) as int,
      );
}

/// Workout execution counts for a single day.
class DayWorkouts {
  final int completed;
  final int partial;
  final int minutes;
  final bool skipped;
  const DayWorkouts({
    this.completed = 0,
    this.partial = 0,
    this.minutes = 0,
    this.skipped = false,
  });
  factory DayWorkouts.fromJson(Map<String, dynamic> j) => DayWorkouts(
        completed: (j['completed'] ?? 0) as int,
        partial:   (j['partial']   ?? 0) as int,
        minutes:   (j['minutes']   ?? 0) as int,
        skipped:   (j['skipped']   ?? false) as bool,
      );
  int get doneAny => completed + partial;
}

/// One day inside the 30-day cycle.  Days the user hasn't lived yet or skipped
/// come back filled with zeros.
class ThirtyDayReportDay {
  final DateTime date;
  final int dayOfCycle;
  final bool isToday;
  final bool isFuture;
  final int plannedMeals;
  final LoggedMeals loggedMeals;
  final DayMacros macros;
  final int waterMl;
  final DayMedicine medicine;
  final DayWorkouts workouts;
  final int adherencePct;

  const ThirtyDayReportDay({
    required this.date,
    required this.dayOfCycle,
    required this.isToday,
    required this.isFuture,
    required this.plannedMeals,
    required this.loggedMeals,
    required this.macros,
    required this.waterMl,
    required this.medicine,
    required this.workouts,
    required this.adherencePct,
  });

  factory ThirtyDayReportDay.fromJson(Map<String, dynamic> j) {
    final parsed = DateTime.parse(j['date'] as String);
    return ThirtyDayReportDay(
      date:         parsed,
      dayOfCycle:   (j['day_of_cycle']  ?? 0) as int,
      isToday:      (j['is_today']      ?? false) as bool,
      isFuture:     (j['is_future']     ?? false) as bool,
      plannedMeals: (j['planned_meals'] ?? 0) as int,
      loggedMeals:  LoggedMeals.fromJson(
        (j['logged_meals'] ?? const {}) as Map<String, dynamic>,
      ),
      macros: DayMacros.fromJson(
        (j['macros'] ?? const {}) as Map<String, dynamic>,
      ),
      waterMl:      (j['water_ml']      ?? 0) as int,
      medicine:     DayMedicine.fromJson(
        (j['medicine'] ?? const {}) as Map<String, dynamic>,
      ),
      workouts:     DayWorkouts.fromJson(
        (j['workouts'] ?? const {}) as Map<String, dynamic>,
      ),
      adherencePct: (j['adherence_pct'] ?? 0) as int,
    );
  }

  bool get hasAnyActivity =>
      loggedMeals.total > 0 ||
      waterMl > 0 ||
      medicine.taken > 0 ||
      medicine.scheduled > 0 ||
      workouts.doneAny > 0;

  String get bnWeekday {
    const names = ['সোম', 'মঙ্গল', 'বুধ', 'বৃহঃ', 'শুক্র', 'শনি', 'রবি'];
    return names[date.weekday - 1];
  }

  String get dateLabelBn =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  /// Short Bengali summary line used by the day card subtitle.
  String get summaryBn {
    if (isFuture) return 'আসছে';
    if (!hasAnyActivity && plannedMeals == 0) return 'কোনো পরিকল্পনা নেই';
    if (!hasAnyActivity) return 'লগ করা হয়নি';
    final m = loggedMeals.total;
    final ml = waterMl;
    final w = workouts.doneAny;
    final p = medicine.taken;
    final parts = <String>[];
    if (m > 0) parts.add('$m খাবার');
    if (ml > 0) parts.add('${(ml / 1000).toStringAsFixed(1)}L পানি');
    if (p > 0) parts.add('$p ওষুধ');
    if (w > 0) parts.add('$w ব্যায়াম');
    if (parts.isEmpty) return 'লগ করা হয়নি';
    return parts.join(' • ');
  }
}

/// Full 30-day cycle report.
class ThirtyDayReport {
  final DateTime cycleStart;
  final DateTime today;
  final int dayOfCycle;
  final bool cycleComplete;
  /// 0 = current cycle (the one today falls inside), 1 = previous 30-day
  /// window, 2 = two cycles ago, etc. Defaulted to 0 for callers that don't
  /// pass `p_cycle_index`.
  final int cycleIndex;
  final ThirtyDayTotals totals;
  final List<ThirtyDayReportDay> days;

  const ThirtyDayReport({
    required this.cycleStart,
    required this.today,
    required this.dayOfCycle,
    required this.cycleComplete,
    required this.totals,
    required this.days,
    this.cycleIndex = 0,
  });

  static final _df = DateFormat('d MMM yyyy', 'en');

  factory ThirtyDayReport.fromJson(Map<String, dynamic> j) {
    final rawDays = (j['days'] as List?) ?? const [];
    return ThirtyDayReport(
      cycleStart:    DateTime.parse(j['cycle_start']   as String),
      today:         DateTime.parse(j['today']         as String),
      dayOfCycle:    (j['day_of_cycle']  ?? 1) as int,
      cycleComplete: (j['cycle_complete'] ?? false) as bool,
      cycleIndex:    (j['cycle_index']    ?? 0) as int,
      totals:        ThirtyDayTotals.fromJson(
        (j['totals'] ?? const {}) as Map<String, dynamic>,
      ),
      days: rawDays
          .cast<Map<String, dynamic>>()
          .map(ThirtyDayReportDay.fromJson)
          .toList(),
    );
  }

  String get cycleRangeLabel =>
      '${_df.format(cycleStart)}  →  ${_df.format(cycleStart.add(const Duration(days: 29)))}';

  /// A 0..1 progress number for the cycle hero bar.
  double get cycleProgress =>
      dayOfCycle <= 0 ? 0 : (dayOfCycle / 30).clamp(0.0, 1.0);

  /// Days that are still ahead (so the UI can show "আরও X দিন বাকি").
  int get daysRemaining => (30 - dayOfCycle).clamp(0, 30);

  /// Trend across the cycle: average adherence in the second half minus the
  /// first half (0..100 scale). Returns 0 when the cycle has fewer than 4
  /// active days so the UI caption degrades gracefully.
  ///
  /// Positive → "ভালো হচ্ছে"; negative → "কমে যা�্ছে".
  double get adherenceTrendDelta {
    final samples = days.where((d) => !d.isFuture).toList(growable: false);
    if (samples.length < 4) return 0;
    final mid = samples.length ~/ 2;
    double avg(List<ThirtyDayReportDay> slice) =>
        slice.isEmpty ? 0 : slice.fold<int>(0, (a, d) => a + d.adherencePct) / slice.length;
    final firstHalf = avg(samples.sublist(0, mid));
    final secondHalf = avg(samples.sublist(mid));
    return (secondHalf - firstHalf).clamp(-100.0, 100.0);
  }

  /// Today's day record (or last active day if today is in the future).
  ThirtyDayReportDay get todayDay {
    for (final d in days) {
      if (d.isToday) return d;
    }
    final past = days.where((d) => !d.isFuture).toList();
    return past.isNotEmpty ? past.last : days.first;
  }

  /// "বর্তমান চক্র", "আগের চক্র", etc. — derived from [cycleIndex].
  String cycleLabelBn() {
    if (cycleIndex == 0) return 'বর্তমান চক্র';
    if (cycleIndex == 1) return 'আগের চক্র';
    if (cycleIndex == 2) return '২ চক্র আগে';
    return '$cycleIndex চক্র আগে';
  }

  ThirtyDayReportDay? dayByDate(DateTime d) {
    for (final day in days) {
      if (day.date.year == d.year &&
          day.date.month == d.month &&
          day.date.day == d.day) {
        return day;
      }
    }
    return null;
  }
}

/// Per-day drill-down (supabasesql/27_daily_detail.sql).
class DayFullReport {
  final DateTime date;
  final bool isToday;
  final bool isFuture;
  final Map<String, dynamic> mealsSummary;
  final DayMacros macros;
  final List<DayMealRow> meals;
  final List<DayMedRow> meds;
  final List<DayWaterRow> waterLogs;
  final List<DayWorkoutRow> workouts;

  const DayFullReport({
    required this.date,
    required this.isToday,
    required this.isFuture,
    required this.mealsSummary,
    required this.macros,
    required this.meals,
    required this.meds,
    required this.waterLogs,
    required this.workouts,
  });

  factory DayFullReport.fromJson(Map<String, dynamic> j) => DayFullReport(
        date:         DateTime.parse(j['date'] as String),
        isToday:      (j['is_today']  ?? false) as bool,
        isFuture:     (j['is_future'] ?? false) as bool,
        mealsSummary: (j['meals_summary'] ?? const {}) as Map<String, dynamic>,
        macros:       DayMacros.fromJson(
          (j['macros'] ?? const {}) as Map<String, dynamic>,
        ),
        meals:     ((j['meals']     ?? const []) as List)
            .cast<Map<String, dynamic>>()
            .map(DayMealRow.fromJson)
            .toList(),
        meds:      ((j['meds']      ?? const []) as List)
            .cast<Map<String, dynamic>>()
            .map(DayMedRow.fromJson)
            .toList(),
        waterLogs: ((j['water_logs'] ?? const []) as List)
            .cast<Map<String, dynamic>>()
            .map(DayWaterRow.fromJson)
            .toList(),
        workouts:  ((j['workouts']  ?? const []) as List)
            .cast<Map<String, dynamic>>()
            .map(DayWorkoutRow.fromJson)
            .toList(),
      );
}

class DayMealRow {
  final String time;
  final String slot;
  final String nameBn;
  final String nameEn;
  final String impact;
  final int kcal;
  final int carbG;
  final int proteinG;
  final int fatG;
  final int sodiumMg;
  final bool offplan;
  final String note;
  const DayMealRow({
    required this.time, required this.slot, required this.nameBn, required this.nameEn,
    required this.impact, required this.kcal, required this.carbG, required this.proteinG,
    required this.fatG, required this.sodiumMg, required this.offplan, required this.note,
  });
  factory DayMealRow.fromJson(Map<String, dynamic> j) => DayMealRow(
        time:     (j['time']     ?? '') as String,
        slot:     (j['slot']     ?? '') as String,
        nameBn:   (j['name_bn']  ?? '') as String,
        nameEn:   (j['name_en']  ?? '') as String,
        impact:   (j['impact']   ?? '') as String,
        kcal:     (j['kcal']     ?? 0) as int,
        carbG:    (j['carb_g']    ?? 0) as int,
        proteinG: (j['protein_g'] ?? 0) as int,
        fatG:     (j['fat_g']     ?? 0) as int,
        sodiumMg: (j['sodium_mg'] ?? 0) as int,
        offplan:  (j['offplan']  ?? false) as bool,
        note:     (j['note']      ?? '') as String,
      );
}

class DayMedRow {
  final String name;
  final String dose;
  final String scheduledAt;
  final String? takenAt;
  final String status;
  const DayMedRow({
    required this.name, required this.dose, required this.scheduledAt,
    required this.takenAt, required this.status,
  });
  factory DayMedRow.fromJson(Map<String, dynamic> j) => DayMedRow(
        name:         (j['name']         ?? '') as String,
        dose:         (j['dose']         ?? '') as String,
        scheduledAt:  (j['scheduled_at'] ?? '') as String,
        takenAt:      j['taken_at'] as String?,
        status:       (j['status']       ?? '') as String,
      );
}

class DayWaterRow {
  final String time;
  final int ml;
  const DayWaterRow({required this.time, required this.ml});
  factory DayWaterRow.fromJson(Map<String, dynamic> j) => DayWaterRow(
        time: (j['time'] ?? '') as String,
        ml:   (j['ml']   ?? 0) as int,
      );
}

class DayWorkoutRow {
  final String name;
  final int durationMin;
  final String status;
  final String? startedAt;
  final String? finishedAt;
  const DayWorkoutRow({
    required this.name, required this.durationMin, required this.status,
    required this.startedAt, required this.finishedAt,
  });
  factory DayWorkoutRow.fromJson(Map<String, dynamic> j) => DayWorkoutRow(
        name:         (j['name']         ?? '') as String,
        durationMin:  (j['duration_min'] ?? 0) as int,
        status:       (j['status']       ?? '') as String,
        startedAt:    j['started_at']  as String?,
        finishedAt:   j['finished_at'] as String?,
      );
}
