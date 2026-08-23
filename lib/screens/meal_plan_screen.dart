// আমার ডায়েট — Meal Plan screen (v4).
//
// Visual reference: clean header + 7-day week strip + slot chips +
// "Daily Goals" 4-ring card + horizontal meal cards with side check
// button. All copy is Bangla, hind-siliguri font for clean BD glyphs.
//
// Data wiring:
//   * Daily recommendation: SupabaseService.getDailyRecommendationWithOverrides
//   * Today's log: SupabaseService.getDailyLog(planDay: …)
//   * Daily goals ring data: DietClassification targets (kcal/protein/carb/fat)
//   * Tap a card    → MealDetailsScreen(foodId, seed)
//   * Tap checkbox  → SupabaseService.logMeal(status: 'eaten', impact: 'good')
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/meal_item.dart';
import '../models/user_meal_plan.dart';
import '../models/workout.dart';
import '../screens/meal_details_screen.dart';
import '../screens/plan_editor.dart';
import '../services/app_events.dart';
import '../services/diet_recommender.dart';
import '../services/plan_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class MealPlanScreen extends StatefulWidget {
  final int initialDay;
  const MealPlanScreen({super.key, this.initialDay = 1});

  @override
  State<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends State<MealPlanScreen> {
  /// Currently-selected calendar date (midnight, local tz). The UI
  /// lets the user browse any past/future day; ticking ("খেয়েছি")
  /// is only allowed when this equals [_todayDate].
  late DateTime _selectedDate;

  /// Today (cached on init so the navigator can mark the chip
  /// consistently across rebuilds).
  late DateTime _todayDate;

  /// Controller for the horizontal date strip. Used so the chip
  /// for the currently-selected date (and especially "today") is
  /// always visible — without this, the strip starts at index 0
  /// (today − 14 days) and a fresh user has to scroll right to
  /// find today.
  final ScrollController _stripController = ScrollController();

  /// Index of today inside the [_pastWindow..+_futureWindow] window
  /// (always == _pastWindow). Pre-computed for clarity.
  static const int _todayIndex = _pastWindow;

  /// Cached PlanProgress from the server. Used to compute the
  /// active 30-day rotation `day` for the selected date.
  PlanProgress _progress = PlanProgress.fallback();
  DietClassification? _cls2;
  List<MealSlotPlan> _items = const [];
  Map<String, MealLogEntry> _todayLog = {};
  // ignore: unused_field
  DailyMetric _daily = DailyMetric.empty;
  bool _loading = true;
  String? _error;
  String? _slotFilter; // null = all

  /// Total visible window: from -14 .. +14 days around today
  /// (29 days in total — covers the full 30-day rotation plus
  /// a safe margin so the user can always reach today).
  static const int _pastWindow = 14;
  static const int _futureWindow = 14;

  static const List<String> _slotOrder = [
    'breakfast',
    'morning_snack',
    'lunch',
    'evening_snack',
    'dinner',
  ];

  static const Map<String, String> _slotTitleBn = {
    'breakfast': 'সকালের নাস্তা',
    'morning_snack': 'সকালের স্ন্যাক',
    'lunch': 'দুপুরের খাবার',
    'evening_snack': 'বিকেলের স্ন্যাক',
    'dinner': 'রাতের খাবার',
    'tiffin': 'টিফিন',
    'late_night': 'রাতে',
    'pre_workout': 'ব্যায়ামের আগে',
    'post_workout': 'ব্যায়ামের পরে',
    'other': 'অন্যান্য',
  };

  static const Map<String, IconData> _slotIcon = {
    'breakfast': Icons.wb_sunny_outlined,
    'morning_snack': Icons.coffee_outlined,
    'lunch': Icons.lunch_dining_outlined,
    'evening_snack': Icons.cookie_outlined,
    'dinner': Icons.nightlight_outlined,
    'tiffin': Icons.fastfood_outlined,
    'late_night': Icons.bedtime_outlined,
    'pre_workout': Icons.fitness_center_outlined,
    'post_workout': Icons.sports_handball_outlined,
    'other': Icons.restaurant_outlined,
  };

  @override
  void initState() {
    super.initState();
    _todayDate = _dateOnly(DateTime.now());
    _selectedDate = _todayDate;
    _load();
    AppEvents.profileChanged.addListener(_onProfileChanged);
    // Centre today's chip on the very first paint so a fresh
    // user lands on the 23rd (or whatever today is), not on
    // today-14 (Aug 9). WidgetsBinding fires after layout, so
    // the jumpTo uses a real offset rather than zero.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollStripToToday();
    });
  }

  @override
  void dispose() {
    AppEvents.profileChanged.removeListener(_onProfileChanged);
    _stripController.dispose();
    super.dispose();
  }

  /// Centres the date strip so the currently-selected chip is
  /// visible. Called after first paint (so today is in view for
  /// a brand-new user) and whenever the user steps day-by-day
  /// with the chevron arrows.
  void _scrollStripToToday() {
    if (!_stripController.hasClients) return;
    // Estimated per-chip width: ~62px wide cell + 6px gap. The
    // exact value isn't critical — we only need to get today
    // into the viewport, not pixel-centre it. Multiplying by
    // _todayIndex lands today's chip roughly in the middle of
    // the visible window.
    const approxChipStride = 68.0;
    const offset = (_todayIndex * approxChipStride) - 60;
    _stripController.jumpTo(offset.clamp(
      _stripController.position.minScrollExtent,
      _stripController.position.maxScrollExtent,
    ));
  }

  /// Centres the date strip so the chip for [index] is visible.
  /// Used after a day-tap or chevron step so the newly-selected
  /// chip stays in view if it scrolled out of the viewport.
  void _scrollStripToIndex(int index) {
    if (!_stripController.hasClients) return;
    const approxChipStride = 68.0;
    final offset = (index * approxChipStride) - 60;
    _stripController.jumpTo(offset.clamp(
      _stripController.position.minScrollExtent,
      _stripController.position.maxScrollExtent,
    ));
  }

  void _onProfileChanged() {
    if (!mounted) return;
    PlanService.clearCache();
    _load();
  }

  /// Reloads the AI plan + custom meals for [_selectedDate].
  ///
  /// PlanProgress tells us which 30-day rotation index applies to
  /// the selected calendar date. We then fetch:
  ///   * the AI plan for that index (with per-day overrides merged),
  ///   * the user's custom user_meal_plans rows for that date,
  ///   * the day's intake log (only meaningful when viewing today).
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final progress = await SupabaseService.getPlanProgress();
      _progress = progress;
      final targetDay = _dayForDate(_selectedDate, progress);

      // Pre-bake the user's first full 30-day cycle anchored at
      // their signup date so swiping through the date strip is
      // instant. Fire-and-forget — failures don't block the load.
      unawaited(_prebakeUserCycle(progress.planStartDate));

      final result = await _loadDayPlanWithFallback(targetDay);
      DietClassification? cls2;
      try {
        final v2 = await PlanService.classifyUser();
        cls2 =
            DietClassification.fromJson(Map<String, dynamic>.from(v2 as Map));
      } catch (_) {
        cls2 = null;
      }

      // Fetch log + custom meals in parallel; only the log step is
      // gated on viewing today (past/future days won't show ticks).
      final results = await Future.wait([
        Future(() => _expandPlan(result)),
        Future(() async {
          try {
            return await SupabaseService.getUserDayPlan(_selectedDate);
          } catch (_) {
            return const <UserMealPlan>[];
          }
        }),
        if (_isToday)
          SupabaseService.getDailyLog(planDay: targetDay)
        else
          Future<List<MealLogEntry>>.value(const []),
        SupabaseService.getTodayDailyMetrics(),
      ]);
      final aiItems = results[0] as List<MealSlotPlan>;
      final userRows = results[1] as List<UserMealPlan>;
      final log = results[2] as List<MealLogEntry>;
      final daily = results[3] as DailyMetric;

      // Persist the raw user_meal_plans rows for this date. The set
      // includes both visible custom meals and `__removed__` markers.
      _userMealPlanRows = userRows;

      // Visible custom rows = user_meal_plans minus removal markers.
      final customEntries = userRows
          .where((u) =>
              !(u.customFoodName ?? '').startsWith(_removedMarkerPrefix))
          .toList(growable: false);

      // Build the merged list: AI baseline (with removals applied)
      // + visible custom user entries.
      final aiFiltered = _applyAiRemovals(aiItems);
      final customItems = _customEntriesToMealSlotPlans(customEntries);
      final items = <MealSlotPlan>[...aiFiltered, ...customItems];

      final today = <String, MealLogEntry>{};
      for (final e in log) {
        final key = '${e.mealSlot}|${e.foodId ?? ''}';
        today[key] = e;
      }

      if (!mounted) return;
      setState(() {
        _items = items;
        _todayLog = today;
        _daily = daily;
        _cls2 = cls2;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Convert the selected date into a 1..totalDays rotation index.
  ///
  /// If we know the cycle's plan_start_date, days since that start
  /// modulo totalDays + 1 give us the active plan slot. Otherwise
  /// fall back to the live rotation `progress.day`.
  int _dayForDate(DateTime date, PlanProgress progress) {
    final start = progress.planStartDate;
    if (start != null) {
      final daysFromStart =
          _dateOnly(date).difference(_dateOnly(start)).inDays;
      if (daysFromStart >= 0) {
        final mod = daysFromStart % progress.totalDays;
        return (mod + 1).clamp(1, progress.totalDays);
      }
    }
    return progress.day.clamp(1, progress.totalDays);
  }

  /// Pre-bakes the user's first full 30-day cycle anchored at their
  /// signup date so swiping the date strip is instant. Fire-and-forget:
  /// any failure is logged but does not block the current load.
  ///
  /// Runs once per [_load] call. The server-side RPC is idempotent
  /// (re-runs overwrite the same `user_meal_plan_recommendations`
  /// rows for that date), so redundant calls are cheap.
  Future<void> _prebakeUserCycle(DateTime? planStartDate) async {
    // PlanService.ensureUpcomingPlans() defaults `fromDate` to today
    // on the server side; for the first cycle that's the same day
    // as `plan_start_date` (the server auto-stamps it on the user's
    // first `get_plan_progress` call).
    await PlanService.ensureUpcomingPlans(days: 30);
  }

  /// Loads one day plan, preferring the per-user v2 RPC
  /// (`get_day_plan_with_fallback`, which substitutes restricted
  /// foods via `classify_user_v2`) and falling back to the legacy
  /// v1-with-overrides RPC when v2 isn't deployed. Returns the
  /// legacy nested JSON (`{breakfast, lunch: {...}, dinner, ...}`)
  /// so [_expandPlan] can consume either result.
  Future<Map<String, dynamic>> _loadDayPlanWithFallback(int targetDay) async {
    try {
      final raw = await SupabaseService.getDayPlanWithFallback(targetDay);
      return _flattenV2ToLegacyJson(raw);
    } catch (_) {
      return SupabaseService.getDailyRecommendationWithOverrides(targetDay);
    }
  }

  /// Translates the v2 RPC payload (flat array of rows from
  /// `user_meal_plan_recommendations` joined with `foods`) into the
  /// legacy nested JSON shape that [_expandPlan] already consumes.
  ///
  /// The v2 row has: `slot`, `role`, `food_id`, plus the joined food
  /// fields as either `resolved_name/portion_label/category/gi_category`
  /// or directly `name_bn/portion_label/category/gi_category`.
  /// Either way the relevant food fields are top-level on the row.
  Map<String, dynamic> _flattenV2ToLegacyJson(Map<String, dynamic> raw) {
    // The SQL returns `jsonb_agg(...)` from get_day_plan_with_fallback,
    // which the PostgREST client returns as a top-level List. Defensive
    // fallbacks cover the wrapper shape (`{plan: [...]}`) too.
    final List<dynamic> list;
    if (raw is List) {
      list = raw as List;
    } else if (raw['plan'] is List) {
      list = raw['plan'] as List;
    } else if (raw['slots'] is List) {
      list = raw['slots'] as List;
    } else {
      list = const [];
    }
    final out = <String, dynamic>{};

    for (final entry in list) {
      if (entry is! Map) continue;
      final m = Map<String, dynamic>.from(entry);
      final slot = (m['slot'] ?? '') as String;
      final role = (m['role'] ?? 'main') as String;
      if (slot.isEmpty) continue;

      // Pick whichever join alias the SQL used.
      final foodMap = <String, dynamic>{
        'id': m['food_id'] ?? m['id'],
        'name_bn': m['resolved_name'] ?? m['name_bn'] ?? '',
        'category': m['resolved_category'] ?? m['category'] ?? 'snack',
        'gi_category': m['resolved_gi'] ?? m['gi_category'] ?? 'low',
        'portion_label': m['resolved_portion'] ?? m['portion_label'],
        'portion_g': m['portion_g'],
        'carb_g': m['carb_g'] ?? 0,
        'protein_g': m['protein_g'] ?? 0,
        'fat_g': m['fat_g'] ?? 0,
        'fiber_g': m['fiber_g'] ?? 0,
        'sodium_mg': m['sodium_mg'] ?? 0,
        'potassium_mg': m['potassium_mg'] ?? 0,
        'phosphorus_mg': m['phosphorus_mg'] ?? 0,
      };

      if (slot == 'breakfast' ||
          slot == 'morning_snack' ||
          slot == 'evening_snack') {
        out[slot] = foodMap;
      } else {
        // lunch / dinner — fold into {carb, protein, vegetable, dal, ...}
        final bucket =
            (out[slot] as Map<String, dynamic>?) ?? <String, dynamic>{};
        bucket[role] = foodMap;
        out[slot] = bucket;
      }
    }
    return out;
  }

  /// Convert a list of `UserMealPlan` rows into `MealSlotPlan`s that
  /// can render in the existing card list. Each custom entry has
  /// either a real food (we resolve it) or a free-text name.
  List<MealSlotPlan> _customEntriesToMealSlotPlans(
      List<UserMealPlan> entries) {
    final out = <MealSlotPlan>[];
    for (final u in entries) {
      // Skip any `__removed__` marker rows — they live in
      // `user_meal_plans` to record AI removals, not as visible cards.
      if ((u.customFoodName ?? '').startsWith(_removedMarkerPrefix)) {
        continue;
      }
      final name = u.displayName.isNotEmpty ? u.displayName : 'কাস্টম খাবার';
      MealItem food;
      if (u.food != null) {
        try {
          food = MealItem.fromJson(Map<String, dynamic>.from(u.food!));
        } catch (_) {
          food = _placeholderFood(name);
        }
      } else {
        food = _placeholderFood(name);
      }
      out.add(MealSlotPlan(
        slot: u.slot,
        role: 'custom',
        food: food,
        source: 'custom',
        customId: u.id,
        customTime: u.displayTime.isEmpty ? null : u.displayTime,
        customPortionLabel: u.portionLabel,
      ));
    }
    // Stable ordering inside each slot — by position, then creation time.
    out.sort((a, b) {
      if (a.slot != b.slot) return a.slot.compareTo(b.slot);
      return (a.customId ?? '').compareTo(b.customId ?? '');
    });
    return out;
  }

  /// Sentinel prefix used to mark "user has removed this AI suggestion
  /// for today" rows in `user_meal_plans`. The food's master id is
  /// still in `food_id` so we can match it back to the AI card.
  static const String _removedMarkerPrefix = '__removed__';

  /// All user_meal_plans rows fetched for the current date. Includes
  /// both visible custom meals and removal markers; the UI decides
  /// which is which by inspecting `customFoodName`.
  List<UserMealPlan> _userMealPlanRows = const [];

  /// Convenience: ids of AI food suggestions the user has marked
  /// as removed for the current day. Derived from
  /// `_userMealPlanRows` so we never have to re-walk the list.
  Set<String> get _removedAiFoodIds {
    return _userMealPlanRows
        .where((u) =>
            (u.customFoodName ?? '').startsWith(_removedMarkerPrefix) &&
            u.foodId != null)
        .map((u) => u.foodId!)
        .toSet();
  }

  /// Filter the AI list so any food the user has marked "removed for
  /// today" is hidden from the card list. Custom entries pass through
  /// untouched.
  List<MealSlotPlan> _applyAiRemovals(List<MealSlotPlan> aiItems) {
    if (_removedAiFoodIds.isEmpty) return aiItems;
    return aiItems
        .where((it) => !_removedAiFoodIds.contains(it.food.id))
        .toList(growable: false);
  }

  /// Marker rows (`custom_food_name LIKE '__removed__%'`) fetched
  /// today. Used by [_restoreAiSuggestion] to know which id to
  /// deactivate.
  List<UserMealPlan> get _removedEntries {
    return _userMealPlanRows
        .where((u) =>
            (u.customFoodName ?? '').startsWith(_removedMarkerPrefix))
        .toList(growable: false);
  }

  /// Write a `user_meal_plans` row that marks the given AI food as
  /// removed for the selected day. The row has the AI food's
  /// `food_id` so the UI can find it on next load; `custom_food_name`
  /// carries the marker prefix.
  Future<void> _removeAiSuggestion(MealSlotPlan plan) async {
    final name = plan.food.nameBn;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('সাজেশনটি বাদ দিবেন?'),
        content: Text(
            '"$name" আজকের পরিকল্পনা থেকে সরানো হবে। আপনি চাইলে পরে ফিরিয়ে আনতে পারবেন।'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('বাতিল'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.rose),
            child: const Text('বাদ দিন'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await SupabaseService.createUserMealPlan(
        effectiveDate: _selectedDate,
        slot: plan.slot,
        foodId: plan.food.id,
        customFoodName: _removedMarkerPrefix,
      );
      if (!mounted) return;
      await _load();
      messenger.showSnackBar(
        SnackBar(content: Text('"$name" আজকের জন্য বাদ দেওয়া হয়েছে')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('বাদ দেওয়া যায়নি: $e')),
      );
    }
  }

  /// Undo a prior remove: deactivate the `__removed__` marker row.
  Future<void> _restoreAiSuggestion(MealSlotPlan plan) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final removed = _removedEntries
          .where((u) => u.foodId == plan.food.id)
          .toList(growable: false);
      if (removed.isEmpty) return;
      for (final u in removed) {
        await SupabaseService.deleteUserMealPlan(u.id);
      }
      if (!mounted) return;
      await _load();
      messenger.showSnackBar(
        SnackBar(content: Text('"${plan.food.nameBn}" ফিরিয়ে আনা হয়েছে')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ফিরিয়ে আনা যায়নি: $e')),
      );
    }
  }

  MealItem _placeholderFood(String name) {
    return MealItem(
      id: 'custom::$name',
      nameBn: name,
      category: 'custom',
      carbG: 0,
      proteinG: 0,
      fatG: 0,
      fiberG: 0,
      sodiumMg: 0,
      potassiumMg: 0,
      phosphorusMg: 0,
      giCategory: 'low',
    );
  }

  /// Flatten the recommendation JSON into a flat list of `MealSlotPlan`s,
  /// one per (slot, role) tile. Roles match the meal-card layout.
  List<MealSlotPlan> _expandPlan(Map<String, dynamic> data) {
    final out = <MealSlotPlan>[];
    void addSlot(String slot, String role, Map<String, dynamic>? foodMap) {
      if (foodMap == null || foodMap.isEmpty) return;
      final id = foodMap['id'] as String?;
      if (id == null || id.isEmpty) return;
      out.add(MealSlotPlan(
        slot: slot,
        role: role,
        food: MealItem.fromJson(foodMap),
      ));
    }

    final b = data['breakfast'];
    if (b is Map) addSlot('breakfast', 'main', Map<String, dynamic>.from(b));
    final ms = data['morning_snack'];
    if (ms is Map) {
      addSlot('morning_snack', 'snack', Map<String, dynamic>.from(ms));
    }
    final l = data['lunch'];
    if (l is Map) {
      final m = Map<String, dynamic>.from(l);
      addSlot('lunch', 'carb', (m['carb'] as Map?)?.cast<String, dynamic>());
      addSlot(
          'lunch', 'protein', (m['protein'] as Map?)?.cast<String, dynamic>());
      addSlot('lunch', 'vegetable',
          (m['vegetable'] as Map?)?.cast<String, dynamic>());
      addSlot('lunch', 'dal', (m['dal'] as Map?)?.cast<String, dynamic>());
    }
    final es = data['evening_snack'];
    if (es is Map) {
      addSlot('evening_snack', 'snack', Map<String, dynamic>.from(es));
    }
    final d = data['dinner'];
    if (d is Map) {
      final m = Map<String, dynamic>.from(d);
      addSlot('dinner', 'carb', (m['carb'] as Map?)?.cast<String, dynamic>());
      addSlot(
          'dinner', 'protein', (m['protein'] as Map?)?.cast<String, dynamic>());
      addSlot('dinner', 'vegetable',
          (m['vegetable'] as Map?)?.cast<String, dynamic>());
    }
    return out;
  }

  /// Strips time-of-day, returning a midnight date for safe
  /// equality comparisons and day-difference math.
  static DateTime _dateOnly(DateTime d) =>
      DateTime(d.year, d.month, d.day);

  /// True when the currently-selected day equals today (date-only).
  bool get _isToday {
    final n = DateTime.now();
    return _selectedDate.year == n.year &&
        _selectedDate.month == n.month &&
        _selectedDate.day == n.day;
  }

  /// Returns the same DateTime but 1 calendar day earlier.
  DateTime _addDays(DateTime base, int delta) =>
      DateTime(base.year, base.month, base.day + delta);

  /// User tapped a different day in the navigator strip.
  void _onDayPicked(DateTime day) {
    final target = _dateOnly(day);
    if (target == _selectedDate) return;
    setState(() => _selectedDate = target);
    final newIndex = target.difference(_addDays(_todayDate, -_pastWindow)).inDays;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollStripToIndex(newIndex.clamp(0, _pastWindow + _futureWindow));
    });
    _load();
  }

  /// Jump back to today (or refresh today's data if already there).
  void _onTodayTap() {
    if (_isToday) {
      _load();
      return;
    }
    setState(() => _selectedDate = _todayDate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollStripToToday();
    });
    _load();
  }

  /// Step the navigator by ±1 day and reload.
  void _onStepDay(int delta) {
    final next = _addDays(_selectedDate, delta);
    // Clamp to the visible window so the user can't wander too far.
    final min = _addDays(_todayDate, -_pastWindow);
    final max = _addDays(_todayDate, _futureWindow);
    if (next.isBefore(min) || next.isAfter(max)) return;
    setState(() => _selectedDate = next);
    final newIndex = next.difference(_addDays(_todayDate, -_pastWindow)).inDays;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollStripToIndex(newIndex.clamp(0, _pastWindow + _futureWindow));
    });
    _load();
  }

  /// Open the editor to *add* a meal in [slot] for the selected day.
  /// After it returns, save the result and reload.
  Future<void> _addCustomMeal(String slot) async {
    final result = await PlanEditorSheet.show(
      context,
      date: _selectedDate,
      defaultSlot: slot,
    );
    if (result == null) return;
    try {
      await SupabaseService.createUserMealPlan(
        effectiveDate: _selectedDate,
        slot: result.slot,
        scheduledTime: result.scheduledTime,
        foodId: result.foodId,
        customFoodName: result.customFoodName,
        portionLabel: result.portionLabel,
        notes: result.notes,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      await _load();
      messenger.showSnackBar(
        const SnackBar(content: Text('কাস্টম খাবার যোগ হয়েছে')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('যোগ করা যায়নি: $e')),
      );
    }
  }

  /// Open the editor pre-filled with [existing] for editing.
  Future<void> _editCustomMeal(UserMealPlan existing) async {
    final result = await PlanEditorSheet.show(
      context,
      date: existing.effectiveDate,
      existing: existing,
    );
    if (result == null) return;
    try {
      await SupabaseService.updateUserMealPlan(
        id: existing.id,
        slot: result.slot,
        scheduledTime: result.scheduledTime,
        clearScheduledTime: result.clearScheduledTime,
        foodId: result.foodId,
        clearFoodId: result.clearFoodId,
        customFoodName: result.customFoodName,
        portionLabel: result.portionLabel,
        notes: result.notes,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      await _load();
      messenger.showSnackBar(
        const SnackBar(content: Text('হালনাগাদ হয়েছে')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('হালনাগাদ ব্যর্থ: $e')),
      );
    }
  }

  /// Show a confirm dialog, then soft-delete the custom row.
  Future<void> _deleteCustomMeal(MealSlotPlan plan) async {
    final id = plan.customId;
    if (id == null) return;
    final name = plan.food.nameBn;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('খাবারটি মুছবেন?'),
        content: Text('"$name" আপনার পরিকল্পনা থেকে সরানো হবে।'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('বাতিল'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.rose),
            child: const Text('মুছে ফেলুন'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await SupabaseService.deleteUserMealPlan(id);
      if (!mounted) return;
      await _load();
      messenger.showSnackBar(
        SnackBar(content: Text('"$name" মুছে ফেলা হয়েছে')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('মুছতে ব্যর্থ: $e')),
      );
    }
  }

  Future<void> _markEaten(MealSlotPlan plan) async {
    // Ticking is only allowed on today's plan. Past/future days
    // show the cards read-only.
    if (!_isToday) return;
    final key = '${plan.slot}|${plan.food.id}';
    if (_todayLog[key]?.status == 'eaten') {
      HapticFeedback.lightImpact();
      return;
    }
    HapticFeedback.lightImpact();
    try {
      final planDay = _dayForDate(_selectedDate, _progress);
      await SupabaseService.logMeal(
        mealSlot: plan.slot,
        foodId: plan.food.id,
        foodNameBn: plan.food.nameBn,
        status: 'eaten',
        impact: 'good',
        planDay: planDay,
      );
      if (!mounted) return;
      setState(() {
        _todayLog[key] = MealLogEntry(
          id: 'tmp',
          mealSlot: plan.slot,
          foodId: plan.food.id,
          foodNameBn: plan.food.nameBn,
          status: 'eaten',
          impact: 'good',
          createdAt: DateTime.now(),
        );
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('লগ সংরক্ষণ ব্যর্থ: $e')),
      );
    }
  }

  Future<void> _openDetails(MealSlotPlan plan) async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MealDetailsScreen(
          foodId: plan.food.id,
          fallbackNameBn: plan.food.nameBn,
          seed: plan.food,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.void2,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          color: AppColors.cyan,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              _buildHeader(),
              SliverToBoxAdapter(child: _buildWeekStrip()),
              SliverToBoxAdapter(child: _buildSlotChips()),
              SliverToBoxAdapter(child: _buildDailyGoals()),
              if (_items.isEmpty && !_loading)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmpty(),
                )
              else
                ..._buildMealCardSlivers(),
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.mint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.calendar_today_outlined,
                  color: AppColors.mintDeep, size: 22),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                'আমার\nখাবার পরিকল্পনা',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                  height: 1.15,
                ),
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz, color: AppColors.text),
              color: AppColors.surface,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppColors.line),
              ),
              onSelected: (v) {
                if (v == 'refresh') _load();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'refresh', child: Text('রিফ্রেশ')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Date navigator ──────────────────────────────────────────────────
  //
  // Replaces the old static 7-day strip with a 15-day window
  // around today (-14 .. +14). Prev/next arrows step one day at a
  // time; the chip strip is horizontally scrollable so the user
  // can land on any day in the range. A "আজ" button jumps back to
  // today and refreshes when already there.
  Widget _buildWeekStrip() {
    final start = _addDays(_todayDate, -_pastWindow);
    const totalDays = _pastWindow + _futureWindow + 1;
    final days = List.generate(totalDays, (i) => _addDays(start, i));

    final String headerDateLabel =
        DateFormat('EEEE, d MMMM yyyy', 'bn').format(_selectedDate);
    final bool isToday = _isToday;

    final canStepBack = _selectedDate.isAfter(_addDays(_todayDate, -_pastWindow));
    final canStepForward =
        _selectedDate.isBefore(_addDays(_todayDate, _futureWindow));

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row: day-of-week + a centered "Today" chip
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    headerDateLabel,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                _todayPill(isToday),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Strip with arrows on each side.
          Row(
            children: [
              _navArrow(
                icon: Icons.chevron_left,
                enabled: canStepBack,
                onTap: () => _onStepDay(-1),
              ),
              Expanded(
                child: SizedBox(
                  height: 78,
                  child: ListView.separated(
                    controller: _stripController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    physics: const BouncingScrollPhysics(),
                    itemCount: days.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (_, i) {
                      final d = days[i];
                      return _dayCell(d);
                    },
                  ),
                ),
              ),
              _navArrow(
                icon: Icons.chevron_right,
                enabled: canStepForward,
                onTap: () => _onStepDay(1),
              ),
            ],
          ),
          // Caption reminding the user that ticking is today-only.
          if (!isToday)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 8, right: 16),
              child: Row(
                children: [
                  const Icon(Icons.lock_clock_outlined,
                      size: 14, color: AppColors.textDim),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _selectedDate.isBefore(_todayDate)
                          ? 'গত দিনের পরিকল্পনা — টিক দেওয়া যাবে না'
                          : 'আগামী দিনের পরিকল্পনা — টিক দেওয়া যাবে না',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDim,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _navArrow({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: InkResponse(
        onTap: enabled ? onTap : null,
        radius: 22,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.line),
          ),
          child: Icon(icon, color: AppColors.text, size: 20),
        ),
      ),
    );
  }

  Widget _todayPill(bool isToday) {
    return InkWell(
      onTap: _onTodayTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isToday ? AppColors.mint : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isToday ? AppColors.mint : AppColors.line,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.today_outlined,
              size: 14,
              color: isToday ? AppColors.void1 : AppColors.text,
            ),
            const SizedBox(width: 6),
            Text(
              'আজ',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: isToday ? AppColors.void1 : AppColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayCell(DateTime d) {
    final isSel = _dateOnly(d) == _selectedDate;
    final today = _dateOnly(d) == _todayDate;
    final weekdayLabel = DateFormat('E', 'bn').format(d).substring(0, 1);

    return InkWell(
      onTap: () => _onDayPicked(d),
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 54,
        margin: EdgeInsets.only(
          top: isSel ? 0 : 4,
          bottom: isSel ? 0 : 4,
        ),
        decoration: BoxDecoration(
          color: isSel
              ? AppColors.mint
              : (today ? AppColors.surfaceHigh : AppColors.surface),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSel
                ? AppColors.mint
                : (today ? AppColors.mintDeep : AppColors.line),
            width: isSel ? 1.4 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              weekdayLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isSel ? AppColors.void1 : AppColors.textDim,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${d.day}',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: isSel
                    ? AppColors.void1
                    : (today ? AppColors.mintDeep : AppColors.text),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              DateFormat('MMM', 'bn').format(d),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isSel ? AppColors.void1 : AppColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Slot chips ──────────────────────────────────────────────────────
  Widget _buildSlotChips() {
    Widget chip(String label, String? key) {
      final active = _slotFilter == key;
      return GestureDetector(
        onTap: () => setState(() => _slotFilter = key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.cyan : AppColors.surface,
            border: Border.all(
              color: active ? AppColors.cyan : AppColors.line,
              width: 1.2,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: active ? AppColors.void1 : AppColors.text,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          chip('সব', null),
          chip('সকালের নাস্তা', 'breakfast'),
          chip('দুপুর', 'lunch'),
          chip('রাত', 'dinner'),
          chip('স্ন্যাক', 'snack'),
        ],
      ),
    );
  }

  // ── Daily Goals card (4 ring meters) ────────────────────────────────
  Widget _buildDailyGoals() {
    final cls = _cls2;
    final kcalTarget =
        cls?.dailyKcalTarget ?? 1800; // safe default for adult diabetic
    final proteinTarget = cls?.dailyProteinTargetG ?? 60;
    final carbTarget = cls?.dailyCarbTargetG ?? 220;
    final fatTarget = cls?.dailyFatTargetG ?? 55;

    double kcalTaken = 0, pTaken = 0, cTaken = 0, fTaken = 0;
    for (final e in _todayLog.values) {
      if (e.status != 'eaten' && e.status != 'swap') continue;
      final item = _items.firstWhere(
        (m) => m.food.id == e.foodId,
        orElse: () => MealSlotPlan(
          slot: e.mealSlot,
          role: 'main',
          food: MealItem(
            id: e.foodId ?? '',
            nameBn: e.foodNameBn,
            category: 'snack',
            carbG: 0,
            proteinG: 0,
            fatG: 0,
            fiberG: 0,
            sodiumMg: 0,
            potassiumMg: 0,
            phosphorusMg: 0,
            giCategory: 'low',
          ),
        ),
      );
      kcalTaken += item.food.kcal;
      pTaken += item.food.proteinG;
      cTaken += item.food.carbG;
      fTaken += item.food.fatG;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flag_outlined,
                    size: 18, color: AppColors.cyan),
                const SizedBox(width: 6),
                const Text(
                  'আজকের লক্ষ্য',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const Spacer(),
                Text(
                  '${kcalTaken.toStringAsFixed(0)} / ${kcalTarget.toStringAsFixed(0)} kcal',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _ringStat(
                  'KCAL',
                  kcalTaken,
                  kcalTarget,
                  AppColors.cyan,
                ),
                _ringStat(
                  'PRO',
                  pTaken,
                  proteinTarget,
                  AppColors.mintDeep,
                ),
                _ringStat(
                  'CARB',
                  cTaken,
                  carbTarget,
                  AppColors.amber,
                ),
                _ringStat(
                  'FAT',
                  fTaken,
                  fatTarget,
                  AppColors.violet,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _ringStat(String label, double taken, double target, Color color) {
    final pct = target <= 0 ? 0.0 : (taken / target).clamp(0.0, 1.0).toDouble();
    final percentLabel = (pct * 100).toStringAsFixed(0);
    return Expanded(
      child: Column(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(
                    value: 1,
                    strokeWidth: 6,
                    color: AppColors.surfaceHigh,
                  ),
                ),
                SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(
                    value: pct,
                    strokeWidth: 6,
                    color: color,
                  ),
                ),
                Text(
                  '$percentLabel%',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${taken.toStringAsFixed(0)}g',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textDim,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Meal card slivers ──────────────────────────────────────────────
  List<Widget> _buildMealCardSlivers() {
    final groups = <String, List<MealSlotPlan>>{};
    for (final it in _items) {
      groups.putIfAbsent(it.slot, () => []).add(it);
    }

    final children = <Widget>[];
    final slotsToShow = <String>[];
    if (_slotFilter == null) {
      slotsToShow.addAll(_slotOrder);
    } else if (_slotFilter == 'snack') {
      slotsToShow.addAll(['morning_snack', 'evening_snack']);
    } else {
      slotsToShow.add(_slotFilter!);
    }

    var firstCard = true;
    for (final slot in slotsToShow) {
      final list = groups[slot];
      if (list == null || list.isEmpty) continue;
      if (!firstCard) {
        children.add(const SliverToBoxAdapter(child: SizedBox(height: 8)));
      }
      firstCard = false;
      children.add(SliverToBoxAdapter(
        child: _sectionLabel(slot),
      ));
      children.add(SliverList.builder(
        itemCount: list.length,
        itemBuilder: (context, i) => _mealCard(list[i]),
      ));
    }

    if (children.isEmpty) {
      children.add(SliverToBoxAdapter(child: _buildEmpty()));
    }
    return children;
  }

  Widget _sectionLabel(String slot) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          Icon(_slotIcon[slot] ?? Icons.restaurant_outlined,
              size: 18, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Text(
            _slotTitleBn[slot] ?? slot,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textMuted,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          // "+" — opens the editor to add a custom meal in this slot.
          // Disabled for non-today dates (the user can still see the
          // strip but cannot create entries for past/future days).
          Tooltip(
            message: _isToday ? 'কাস্টম খাবার যোগ করুন' : 'শুধু আজকের জন্য যোগ করা যায়',
            child: InkWell(
              onTap: () async {
                if (!_isToday) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('কাস্টম খাবার শুধু আজকের জন্য যোগ করা যায়'),
                    ),
                  );
                  return;
                }
                await _addCustomMeal(slot);
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _isToday ? AppColors.surfaceHigh : AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isToday ? AppColors.line : AppColors.line,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_circle,
                      size: 16,
                      color: _isToday ? AppColors.mintDeep : AppColors.textDim,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'যোগ',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color:
                            _isToday ? AppColors.mintDeep : AppColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mealCard(MealSlotPlan plan) {
    final logKey = '${plan.slot}|${plan.food.id}';
    final eaten = _todayLog[logKey]?.status == 'eaten';
    final swap = _todayLog[logKey]?.status == 'swap';
    final food = plan.food;
    final isCustom = plan.isCustom;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      child: InkWell(
        onTap: () => _openDetails(plan),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isCustom
                  ? AppColors.violet.withValues(alpha: 0.5)
                  : eaten
                      ? AppColors.mintDeep
                      : swap
                          ? AppColors.amber
                          : AppColors.line,
              width: isCustom || eaten || swap ? 1.4 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: _thumb(food),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isCustom
                                ? AppColors.violet.withValues(alpha: 0.12)
                                : AppColors.surfaceHigh,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _slotTitleBn[plan.slot] ?? plan.slot,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isCustom
                                  ? AppColors.violetDeep
                                  : AppColors.textMuted,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        if (isCustom) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.violetDeep,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'কাস্টম',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.void1,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 6),
                        Text(
                          '· ${food.kcal.toStringAsFixed(0)} kcal',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDim,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      food.nameBn,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          _roleLabel(plan.role),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (plan.customTime != null &&
                            plan.customTime!.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.schedule_outlined,
                              size: 12, color: AppColors.textDim),
                          const SizedBox(width: 2),
                          Text(
                            plan.customTime!,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textDim,
                            ),
                          ),
                        ],
                        if (plan.customPortionLabel != null &&
                            plan.customPortionLabel!.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.scale_outlined,
                              size: 12, color: AppColors.textDim),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              plan.customPortionLabel!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textDim,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Every card (AI-suggested + custom) now exposes BOTH the
              // tick button (today-only) AND a 3-dot menu with
              // edit/delete. Custom meals can be ticked; AI suggestions
              // can be edited or removed in addition to being ticked.
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _eatenButton(logKey, eaten, swap, plan),
                  const SizedBox(height: 6),
                  _cardMenu(plan),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Three-dot menu shown on every meal card. The semantics differ
  /// by source:
  ///   * Custom  → Edit opens `PlanEditorSheet` pre-filled with the
  ///               row, Delete soft-deletes it.
  ///   * AI      → Edit opens `PlanEditorSheet` in add mode with the
  ///               same slot, so the user can save their replacement.
  ///               Delete writes a `__removed__` marker row so this
  ///               AI suggestion is hidden on subsequent loads.
  Widget _cardMenu(MealSlotPlan plan) {
    return SizedBox(
      width: 36,
      height: 32,
      child: PopupMenuButton<String>(
        tooltip: 'খাবারের বিকল্প',
        icon: const Icon(Icons.more_vert, color: AppColors.textMuted, size: 20),
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.line),
        ),
        offset: const Offset(0, 36),
        onSelected: (v) async {
          if (v == 'edit') {
            if (!mounted) return;
            if (plan.isCustom) {
              final existing = await _fetchUserMealPlan(plan.customId);
              if (existing == null || !mounted) return;
              await _editCustomMeal(existing);
            } else {
              await _addCustomMeal(plan.slot);
            }
          } else if (v == 'delete') {
            if (plan.isCustom) {
              await _deleteCustomMeal(plan);
            } else {
              await _removeAiSuggestion(plan);
            }
          } else if (v == 'tick') {
            // Convenience entry — same as tapping the tick button.
            await _markEaten(plan);
          } else if (v == 'undo') {
            await _restoreAiSuggestion(plan);
          }
        },
        itemBuilder: (_) {
          final custom = plan.isCustom;
          return [
            if (_isToday)
              const PopupMenuItem(
                value: 'tick',
                child: Row(children: [
                  Icon(Icons.check_circle_outline,
                      size: 18, color: AppColors.mintDeep),
                  SizedBox(width: 8),
                  Text('টিক / খেয়েছি'),
                ]),
              ),
            PopupMenuItem(
              value: 'edit',
              child: Row(children: [
                const Icon(Icons.edit_outlined,
                    size: 18, color: AppColors.text),
                const SizedBox(width: 8),
                Text(custom ? 'সম্পাদনা' : 'বদলে আমারটা যোগ করুন'),
              ]),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Row(children: [
                Icon(
                    custom
                        ? Icons.delete_outline
                        : Icons.visibility_off_outlined,
                    size: 18,
                    color: AppColors.rose),
                const SizedBox(width: 8),
                Text(custom ? 'মুছে ফেলুন' : 'আজকের জন্য বাদ দিন',
                    style: const TextStyle(color: AppColors.rose)),
              ]),
            ),
            if (!custom && _removedAiFoodIds.contains(plan.food.id))
              const PopupMenuItem(
                value: 'undo',
                child: Row(children: [
                  Icon(Icons.restore_outlined,
                      size: 18, color: AppColors.cyan),
                  SizedBox(width: 8),
                  Text('আবার ফিরিয়ে আনুন'),
                ]),
              ),
          ];
        },
      ),
    );
  }

  /// Re-fetches a single user_meal_plans row so the editor can be
  /// populated with the latest server state. The local MealSlotPlan
  /// carries enough data for rendering but the editor wants the full
  /// row (effectiveDate, position, isActive, …).
  Future<UserMealPlan?> _fetchUserMealPlan(String? id) async {
    if (id == null) return null;
    try {
      final day = await SupabaseService.getUserDayPlan(_selectedDate);
      for (final u in day) {
        if (u.id == id) return u;
      }
    } catch (_) {}
    return null;
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'carb':
        return 'কার্বোহাইড্রেট';
      case 'protein':
        return 'প্রোটিন';
      case 'vegetable':
        return 'সবজি';
      case 'dal':
        return 'ডাল';
      case 'snack':
        return 'হালকা খাবার';
      case 'custom':
        return 'আপনার যোগ করা খাবার';
      default:
        return 'প্রধান খাবার';
    }
  }

  Widget _thumb(MealItem food) {
    final url = food.imageUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        loadingBuilder: (ctx, child, p) =>
            p == null ? child : Container(color: AppColors.surfaceHigh),
        errorBuilder: (ctx, e, s) => _thumbFallback(food),
      );
    }
    return _thumbFallback(food);
  }

  Widget _thumbFallback(MealItem food) {
    final colors = _categoryColors(food.category);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        _initial(food.nameBn),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  List<Color> _categoryColors(String category) {
    switch (category) {
      case 'carb':
        return [const Color(0xFFEAB308), const Color(0xFFCA8A04)];
      case 'protein':
        return [const Color(0xFFEF4444), const Color(0xFFB91C1C)];
      case 'vegetable':
        return [const Color(0xFF10B981), const Color(0xFF047857)];
      case 'dal':
        return [const Color(0xFFF59E0B), const Color(0xFFB45309)];
      case 'snack':
        return [const Color(0xFF8B5CF6), const Color(0xFF6D28D9)];
      default:
        return [const Color(0xFF6B7280), const Color(0xFF4B5563)];
    }
  }

  String _initial(String s) {
    if (s.isEmpty) return '?';
    return s.trim().characters.first;
  }

  Widget _eatenButton(
    String logKey,
    bool eaten,
    bool swap,
    MealSlotPlan plan,
  ) {
    // Tick is today-only. Show a disabled "lock" circle for past/future.
    if (!_isToday) {
      return Tooltip(
        message: 'শুধু আজকের খাবার টিক দেওয়া যায়',
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.line),
          ),
          child: const Icon(Icons.lock_outline,
              color: AppColors.textDim, size: 20),
        ),
      );
    }
    final Color bg;
    final Color fg;
    final IconData icon;
    if (eaten) {
      bg = AppColors.mint;
      fg = AppColors.void1;
      icon = Icons.check;
    } else if (swap) {
      bg = AppColors.amber;
      fg = AppColors.void1;
      icon = Icons.swap_horiz;
    } else {
      bg = AppColors.surface;
      fg = AppColors.textMuted;
      icon = Icons.radio_button_unchecked;
    }
    return InkWell(
      onTap: () => _markEaten(plan),
      customBorder: const CircleBorder(),
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(
            color: eaten || swap ? bg : AppColors.lineStrong,
            width: 1.4,
          ),
        ),
        child: Icon(icon, color: fg, size: 22),
      ),
    );
  }

  Widget _buildEmpty() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(child: CircularProgressIndicator(color: AppColors.cyan)),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            children: [
              const Icon(Icons.cloud_off_outlined,
                  color: AppColors.rose, size: 36),
              const SizedBox(height: 10),
              const Text('ডেটা লোড হয়নি',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 6),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _load,
                child: const Text('আবার চেষ্টা করুন'),
              ),
            ],
          ),
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 80),
      child: Center(
        child: Text(
          'আজকের জন্য কোনো খাবার নির্ধারণ হয়নি।',
          style: TextStyle(color: AppColors.textMuted),
        ),
      ),
    );
  }
}
