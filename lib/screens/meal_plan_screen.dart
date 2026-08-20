import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/meal_item.dart';
import '../models/user_meal_plan.dart';
import '../services/supabase_service.dart';
import '../services/impact_engine.dart';
import '../services/diet_recommender.dart';
import '../services/plan_service.dart';
import '../services/app_events.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';
import 'plan_editor.dart';

/// Today's meal plan as a checklist.
/// The user marks each item as eaten, swaps it, or logs an off-plan food.
class MealPlanScreen extends StatefulWidget {
  final int initialDay;
  const MealPlanScreen({super.key, this.initialDay = 1});

  @override
  State<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends State<MealPlanScreen>
    with TickerProviderStateMixin {
  // The active day is locked to today's slot in the 30-day plan and
  // is computed server-side from `plan_start_date` in `user_profiles`.
  // Editing/adding is only meaningful for the current day.
  int _day = 1;

  /// Server-computed "today" slot inside the rotating plan. Null
  /// until the first plan-progress fetch resolves. Surfaces "আজ"
  /// badges on the relevant meal tiles.
  int? _todayDayIndex;
  Classification? _cls;

  /// Modern (v2) clinical classification — powers the personalization
  /// row, per-meal caps, and food-preference filtering. Falls back to
  /// the legacy [_cls] when the v2 RPC is unavailable.
  DietClassification? _cls2;
  List<MealSlotPlan> _items = [];
  // ignore: unused_field
  Map<String, MealLogEntry> _todayLog = {};
  List<UserMealPlan> _customEntries = [];
  bool _loading = true;
  String? _error;

  /// Filter the meal list by slot. Null = render all slots (the
  /// default). Set via the horizontal chip strip at the top of the
  /// body. Mirrors the "All recipes / Saved" tab pattern from the
  /// reference but adapted to the user's meal slots in Bangla.
  String? _slotFilter;

  /// Slot order used both by the section headers and the filter
  /// chips so the UI stays consistent.
  static const List<String> _slotOrder = [
    'breakfast',
    'morning_snack',
    'lunch',
    'evening_snack',
    'dinner',
    'other',
  ];

  static const Map<String, String> _slotTitleBn = {
    'breakfast': 'সকালের নাস্তা',
    'morning_snack': 'সকালের স্ন্যাক',
    'lunch': 'দুপুরের খাবার',
    'evening_snack': 'বিকেলের স্ন্যাক',
    'dinner': 'রাতের খাবার',
    'other': 'অন্যান্য',
  };

  static const Map<String, IconData> _slotIcon = {
    'breakfast': Icons.wb_sunny_outlined,
    'morning_snack': Icons.coffee_outlined,
    'lunch': Icons.lunch_dining_outlined,
    'evening_snack': Icons.cookie_outlined,
    'dinner': Icons.nightlight_outlined,
    'other': Icons.restaurant_outlined,
  };

  late final AnimationController _entry;

  @override
  void initState() {
    super.initState();
    _day = widget.initialDay;
    _entry = AnimationController(vsync: this, duration: AppMotion.long);
    _load();
    AppEvents.profileChanged.addListener(_onProfileChanged);
  }

  @override
  void dispose() {
    AppEvents.profileChanged.removeListener(_onProfileChanged);
    _entry.dispose();
    super.dispose();
  }

  void _onProfileChanged() {
    if (!mounted) return;
    // A profile change can invalidate the plan shape — reset to
    // today so the user sees the freshly-recomputed recommendation
    // instead of a stale past/future day.
    _todayDayIndex = null;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // First resolve which day of the 30-day plan is "today" via
      // the server (so multiple devices / day-rollovers stay in
      // sync). Then ask for the chosen day's plan + log.
      final progress = await SupabaseService.getPlanProgress();

      // Decide which day's plan to show:
      //  * First load (_todayDayIndex == null) → show today's day.
      //  * Auto-rollover: if we were showing today last time and
      //    the calendar has rolled forward, advance with it.
      //  * Otherwise preserve the user's currently displayed day.
      final hadToday = _todayDayIndex;
      var targetDay = _day.clamp(1, progress.totalDays);
      if (hadToday == null) {
        targetDay = progress.day;
      } else if (_day == hadToday && progress.day > hadToday) {
        // The user was viewing today and the world has rolled
        // forward — keep them on today (which is a new day).
        targetDay = progress.day;
      } else {
        // The user was viewing a past or future day. If their
        // chosen day is still in the valid range, keep it.
        targetDay = _day.clamp(1, progress.totalDays);
      }

      // Use the override-aware RPC so any user-pinned food comes
      // back already merged into the recommendation. Falls back to
      // the baseline RPC if 11_*.sql hasn't been run yet.
      final result =
          await SupabaseService.getDailyRecommendationWithOverrides(targetDay);
      final clsJson =
          Map<String, dynamic>.from(result['classification'] as Map);
      final cls = Classification.fromJson(clsJson);
      // Try the v2 classification in parallel — when deployed this
      // carries full clinical targets (food preference, CKD grade,
      // daily kcal / sodium caps) that the personalization row needs.
      DietClassification? cls2;
      try {
        final v2 = await PlanService.classifyUser();
        cls2 =
            DietClassification.fromJson(Map<String, dynamic>.from(v2 as Map));
      } catch (_) {
        // v2 RPC not yet deployed — leave null; [_buildPersonalizationRow]
        // degrades gracefully using only legacy fields.
      }

      // Fetch custom entries for the chosen day in parallel.
      // These are *extra* slots the user added (or a swap they
      // chose to keep as an off-AI row).
      final results = await Future.wait([
        Future(() => _expandPlan(result)),
        SupabaseService.getDailyLog(planDay: targetDay),
        _safeGetUserDayPlan(),
      ]);
      final items = results[0] as List<MealSlotPlan>;
      final log = results[1] as List<MealLogEntry>;
      final custom = results[2] as List<UserMealPlan>;

      final today = <String, MealLogEntry>{};
      for (final e in log) {
        final key = '${e.mealSlot}|${e.foodId ?? ''}';
        today[key] = e;
      }

      // Merge custom entries into the slot groups so each one shows
      // up under its own slot alongside the AI suggestions.
      final merged = _mergeCustomIntoPlan(items, custom);

      if (!mounted) return;
      setState(() {
        _day = targetDay;
        _todayDayIndex = progress.day;
        _cls = cls;
        _cls2 = cls2;
        _items = merged;
        _todayLog = today;
        _customEntries = custom;
      });
      _entry.forward(from: 0);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<UserMealPlan>> _safeGetUserDayPlan() async {
    try {
      return await SupabaseService.getUserDayPlan(_todayDate());
    } catch (_) {
      return const [];
    }
  }

  /// The calendar date that "today" maps to inside the rotating 30-day plan.
  /// The backend treats today as day 1, so this is just today.
  DateTime _todayDate() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Flatten the plan JSON into a list of MealSlotPlan.
  /// Each AI tile is tagged with role=null for single-item slots
  /// (breakfast, snacks) and the appropriate role otherwise. We
  /// don't know here which slots were overridden — that requires a
  /// separate override-list call which the screen doesn't need
  /// today, so we render all rows as 'ai' and rely on the food
  /// change itself to indicate an override.
  List<MealSlotPlan> _expandPlan(Map<String, dynamic> data) {
    final out = <MealSlotPlan>[];

    void addSlot(String slot, String role, Map<String, dynamic>? foodMap) {
      if (foodMap == null || foodMap.isEmpty) return;
      final id = foodMap['id'] as String?;
      if (id == null || id.isEmpty) return;
      final item = MealItem.fromJson(foodMap);
      out.add(MealSlotPlan(slot: slot, role: role, food: item));
    }

    final breakfast = data['breakfast'];
    if (breakfast is Map) {
      addSlot('breakfast', 'main', Map<String, dynamic>.from(breakfast));
    }

    final lunch = data['lunch'];
    if (lunch is Map) {
      final m = Map<String, dynamic>.from(lunch);
      addSlot('lunch', 'carb', (m['carb'] as Map?)?.cast<String, dynamic>());
      addSlot(
          'lunch', 'protein', (m['protein'] as Map?)?.cast<String, dynamic>());
      addSlot('lunch', 'vegetable',
          (m['vegetable'] as Map?)?.cast<String, dynamic>());
      addSlot('lunch', 'dal', (m['dal'] as Map?)?.cast<String, dynamic>());
    }

    final dinner = data['dinner'];
    if (dinner is Map) {
      final m = Map<String, dynamic>.from(dinner);
      addSlot('dinner', 'carb', (m['carb'] as Map?)?.cast<String, dynamic>());
      addSlot(
          'dinner', 'protein', (m['protein'] as Map?)?.cast<String, dynamic>());
      addSlot('dinner', 'vegetable',
          (m['vegetable'] as Map?)?.cast<String, dynamic>());
    }

    final ms = data['morning_snack'];
    if (ms is Map)
      addSlot('morning_snack', 'snack', Map<String, dynamic>.from(ms));
    final es = data['evening_snack'];
    if (es is Map)
      addSlot('evening_snack', 'snack', Map<String, dynamic>.from(es));

    return out;
  }

  /// Slot name for a custom entry: either an explicit
  /// breakfast/lunch/etc. bucket, or 'other' if the user picked
  /// a free-form slot. We treat the custom food's category as the
  /// role so it renders next to the matching AI suggestion when
  /// the categories line up.
  String _slotForCustom(UserMealPlan e) {
    if (kSlotOptions.contains(e.slot)) return e.slot;
    return 'other';
  }

  /// Slot key used to group tiles for display. Custom entries
  /// piggy-back on the canonical slot buckets; 'other' gets its
  /// own section.
  String _bucketKeyForSlot(String slot) => slot;

  /// Map a custom entry to a MealSlotPlan tile so it renders
  /// inside the standard checklist UI. `food` is a synthesized
  /// MealItem if the row points to a master food; otherwise we
  /// surface a placeholder with the free-text name.
  MealSlotPlan _customToSlotPlan(UserMealPlan e) {
    final f = e.food;
    final MealItem item;
    if (f != null) {
      item = MealItem.fromJson(f);
    } else {
      item = MealItem(
        id: 'custom-${e.id}',
        nameBn: e.customFoodName ?? '(নাম ছাড়া)',
        category: 'other',
        carbG: 0,
        proteinG: 0,
        fatG: 0,
        fiberG: 0,
        sodiumMg: 0,
        potassiumMg: 0,
        phosphorusMg: 0,
        giCategory: 'low',
        portionLabel: e.portionLabel,
      );
    }
    return MealSlotPlan(
      slot: _bucketKeyForSlot(_slotForCustom(e)),
      role: 'custom',
      food: item,
      source: 'custom',
      customId: e.id,
      customTime: e.displayTime,
      customPortionLabel: e.portionLabel,
    );
  }

  /// Append custom entries to the AI tile list, slot by slot. The
  /// render order stays AI-first, custom-last, which matches the
  /// mental model "your plan, with anything extra at the bottom".
  List<MealSlotPlan> _mergeCustomIntoPlan(
      List<MealSlotPlan> ai, List<UserMealPlan> custom) {
    if (custom.isEmpty) return ai;
    final out = List<MealSlotPlan>.from(ai);
    for (final e in custom) {
      out.add(_customToSlotPlan(e));
    }
    return out;
  }

  // No manual day navigation: the active slot in the 30-day plan is
  // resolved server-side per calendar day, so editing/customizing is
  // only meaningful for today.

  Future<void> _openItemSheet(MealSlotPlan item) async {
    final isAiOrOverride = item.isAi || item.isOverride;
    final result = await showModalBottomSheet<_ItemSheetResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      builder: (ctx) => _ItemSheet(
        item: item,
        cls: _cls!,
        onEditAi: isAiOrOverride
            ? () async {
                Navigator.pop(ctx, const _ItemSheetResult._noop());
                await _editAiFood(item);
              }
            : null,
        onResetAi: isAiOrOverride && item.isOverride
            ? () async {
                Navigator.pop(ctx, const _ItemSheetResult._noop());
                await _resetAiFood(item);
              }
            : null,
      ),
    );
    if (result == null || result.isNoop) return;
    await _applyItemAction(item, result);
  }

  /// Custom-tile quick actions: Edit (opens PlanEditorSheet) /
  /// Delete / Mark eaten. Renders as a clean two-row list inside
  /// a modal sheet so it matches the AI sheet pattern.
  Future<void> _openCustomTile(MealSlotPlan tile) async {
    final id = tile.customId;
    if (id == null) return;
    final entry = _customEntries.firstWhere(
      (e) => e.id == id,
      orElse: () => _customEntries.first,
    );
    HapticFeedback.selectionClick();
    final mq = MediaQuery.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.graphite,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Overline('আমার খাবার'),
                const SizedBox(height: 4),
                Text(
                  entry.displayName.isEmpty ? '(নাম ছাড়া)' : entry.displayName,
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  slotLabelBn(entry.slot),
                  style: const TextStyle(
                    color: AppColors.smoke,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                _modalOption(
                  ctx,
                  title: 'সম্পাদনা করুন',
                  subtitle: 'সময়, খাবার, পরিমাণ, নোট পরিবর্তন',
                  icon: Icons.edit_outlined,
                  onTap: () => Navigator.pop(ctx, 'edit'),
                ),
                const SizedBox(height: 10),
                _modalOption(
                  ctx,
                  title: 'খেয়েছি বলে লগ করুন',
                  subtitle: 'আজকের খাবারের হিসাবে যোগ হবে',
                  icon: Icons.check,
                  onTap: () => Navigator.pop(ctx, 'log'),
                ),
                const SizedBox(height: 10),
                _modalOption(
                  ctx,
                  title: 'পরিকল্পনা থেকে মুছুন',
                  subtitle: 'এই এন্ট্রিটি আজকের পরিকল্পনা থেকে বাদ যাবে',
                  icon: Icons.delete_outline,
                  destructive: true,
                  onTap: () => Navigator.pop(ctx, 'delete'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'edit':
        await _editCustomEntry(entry);
        break;
      case 'log':
        await _applyItemAction(
            tile,
            _ItemSheetResult(
              food: tile.food,
              status: 'eaten',
              impact: 'neutral',
              kcal: tile.food.kcal,
              carbG: tile.food.carbG,
              proteinG: tile.food.proteinG,
              fatG: tile.food.fatG,
              sodiumMg: tile.food.sodiumMg,
            ));
        break;
      case 'delete':
        if (await _confirmDelete(entry) ?? false) {
          try {
            await SupabaseService.deleteUserMealPlan(entry.id);
            HapticFeedback.lightImpact();
            await _load();
            AppEvents.notifyMealLogged();
          } catch (e) {
            _showError('মুছে ফেলা যায়নি: $e');
          }
        }
        break;
    }
  }

  Widget _modalOption(
    BuildContext ctx, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final color = destructive ? Colors.red.shade600 : AppColors.ink;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.chalk,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.graphite),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.smoke,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward, size: 20, color: color),
          ],
        ),
      ),
    );
  }

  /// Lets the user replace the AI-suggested food for the current
  /// (day, slot, role) with another master food. Persists via
  /// meal_plan_overrides; the next _load fetches the merged plan.
  Future<void> _editAiFood(MealSlotPlan item) async {
    final selected = await _pickFoodFromMaster(item.food.nameBn);
    if (selected == null || !mounted) return;
    try {
      await SupabaseService.upsertAiPlanOverride(
        planDay: _day,
        slot: item.slot,
        role: item.role == 'main' ? null : item.role,
        foodId: selected.id,
      );
      HapticFeedback.lightImpact();
      await _load();
    } catch (e) {
      _showError('সম্পাদনা হয়নি: $e');
    }
  }

  Future<void> _resetAiFood(MealSlotPlan item) async {
    try {
      await SupabaseService.deleteAiPlanOverride(
        planDay: _day,
        slot: item.slot,
        role: item.role == 'main' ? null : item.role,
      );
      HapticFeedback.lightImpact();
      await _load();
    } catch (e) {
      _showError('রিসেট হয়নি: $e');
    }
  }

  /// Search-and-pick sheet for the master foods list. Used both
  /// by "Edit AI food" and as a quick swap during log actions.
  Future<MealItem?> _pickFoodFromMaster(String initialQuery) {
    return showModalBottomSheet<MealItem>(
      context: context,
      backgroundColor: AppColors.paper,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _FoodPickerSheet(initialQuery: initialQuery),
    );
  }

  Future<void> _applyItemAction(MealSlotPlan item, _ItemSheetResult r) async {
    try {
      await SupabaseService.logMeal(
        mealSlot: item.slot,
        foodId: r.food?.id,
        foodNameBn: r.food?.nameBn ?? r.customLabel ?? item.food.nameBn,
        status: r.status,
        impact: r.impact,
        planDay: _day,
        reason: r.reason,
        notes: r.notes,
      );

      // When the user picks a real alternative (swap) for an AI-suggested
      // tile, also persist it as a per-day override so the next _load()
      // refetches the merged plan and shows the new food in place of the
      // original papaya / rice / etc. Off-plan entries and free-text custom
      // labels don't need an override because the user is just recording
      // what they ate, not changing tomorrow's plan.
      if (r.status == 'swap' &&
          r.food != null &&
          r.food!.id.trim().isNotEmpty &&
          r.food!.id != item.food.id) {
        try {
          await SupabaseService.upsertAiPlanOverride(
            planDay: _day,
            slot: item.slot,
            role: item.role == 'main' ? null : item.role,
            foodId: r.food!.id,
          );
        } catch (e) {
          // Override is best-effort — the logMeal row still records the
          // swap for analytics even if the override RPC isn't available.
          debugPrint('upsertAiPlanOverride failed: $e');
        }
      }

      if (!mounted) return;
      await _load();
      AppEvents.notifyMealLogged();
      HapticFeedback.lightImpact();
      if (!mounted) return;
      _showThankYou();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('লগ করা যায়নি')),
        );
      }
    }
  }

  void _showThankYou() {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(builder: (_) => const _ThankYouToast());
    overlay.insert(entry);
    Future.delayed(AppMotion.medium * 2, entry.remove);
  }

  // ──────────────────────────────────────────────────────────────────────
  // SCHEDULE-STYLE THEME TOKENS
  //
  // Inspired by the reference "Schedule Date" screen — a vibrant
  // pink/maroon canvas, white rounded content card, image-forward
  // meal cards, and a pill-shaped active state.
  // ──────────────────────────────────────────────────────────────────────

  /// Vibrant brand pink — used on the active day pill, the FAB,
  /// and rating stars. Stays consistent across the screen.
  static const Color _brandPink = Color(0xFFF6A6C5);
  // ignore: unused_field
  static const Color _brandPinkDeep = Color(0xFFEC7AA1);

  /// Full-screen surface — pure white so the whole page reads as
  /// one continuous canvas (no dark card framing).
  static const Color _canvasOuter = Color(0xFFFFFFFF);

  /// Foreground text + icon colour for the schedule. Deep
  /// near-black tinted toward the brand maroon so it harmonises
  /// with the pink accents without being a harsh #000.
  static const Color _canvasInner = Color(0xFF1F1018);

  /// Subtle off-white used for the date-strip pill background and
  /// other "card on canvas" surfaces.
  // ignore: unused_field
  static const Color _surfaceCard = Color(0xFFF7EEF2);
  // ignore: unused_field
  static const Color _surfaceElevated = Color(0xFFFFF1F5);

  /// Hairline divider colour, derived from a light grey-pink so it
  /// doesn't fight the deep text.
  // ignore: unused_field
  static const Color _lineSoft = Color(0x1A1F1018);
  // ignore: unused_field
  static const Color _onDark = Color(0xFFFFFFFF);
  // ignore: unused_field
  static const Color _onDarkMuted = Color(0xFF8A6A78);
  // ignore: unused_field
  static const Color _onDarkDim = Color(0xFFB89AA6);

  /// Default time-of-day rail values used when the AI/custom slot
  /// doesn't carry its own scheduled time. Stays Bangla-friendly
  /// (24h clock).
  static const Map<String, String> _slotTimeRail = {
    'breakfast': '08:00',
    'morning_snack': '11:00',
    'lunch': '13:00',
    'evening_snack': '17:00',
    'dinner': '20:00',
    'other': '21:00',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _canvasOuter,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _loading || _error != null
          ? null
          : FloatingActionButton.extended(
              backgroundColor: _brandPink,
              foregroundColor: _canvasInner,
              onPressed: _addCustomEntry,
              icon: const Icon(Icons.add_rounded, color: _canvasInner),
              label: const Text(
                'যোগ করুন',
                style: TextStyle(
                  color: _canvasInner,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ),
      body: _loading
          ? const _ScheduleLoading(outer: _canvasOuter)
          : _error != null
              ? _ScheduleError(
                  message: _error!,
                  outer: _canvasOuter,
                  onRetry: _load,
                )
              : _buildScheduleScaffold(),
    );
  }

  /// Build the full-screen white canvas + content. The header sits
  /// on the white surface, the date strip runs across it, and the
  /// schedule body extends to the bottom — no dark "card inside a
  /// pink canvas" framing. Keeps the screen feeling like one
  /// cohesive page so deep text stays easy to read.
  Widget _buildScheduleScaffold() {
    final today = DateTime.now();
    final weekDates = _weekDates(today);
    final activeIdx = _day.clamp(1, weekDates.length) - 1;
    final groups = _groupItemsForView();
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _buildHeader(),
          const SizedBox(height: 8),
          _buildDateStrip(weekDates, activeIdx),
          const SizedBox(height: 12),
          _buildPersonalizationRow(),
          Expanded(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 110),
                  sliver: _buildScheduleBody(groups),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Single-row personalization strip — combines the clinical
  /// context chips with totals-vs-targets into ONE compact card.
  /// Cuts header vertical bloat in half so the meal list gets
  /// more screen real estate.
  Widget _buildPersonalizationRow() {
    final cls = _cls;
    if (cls == null) return const SizedBox.shrink();
    final v2 = _cls2;

    // Prefer v2 fields (carbs/kcal/sodium caps, food preference)
    // when the v2 RPC is deployed; fall back to legacy.
    final dailyCarbTarget =
        v2 != null && v2.dailyCarbTargetG > 0 ? v2.dailyCarbTargetG : 0;
    final dailyKcalTarget =
        v2 != null && v2.dailyKcalTarget > 0 ? v2.dailyKcalTarget : 0;
    final dailySodiumCap =
        v2 != null && v2.dailySodiumCapMg > 0 ? v2.dailySodiumCapMg : 0;
    final foodPreference = v2?.foodPreference ?? 'omnivore';

    final tags = <(IconData, String)>[];
    tags.add(
        (Icons.water_drop_outlined, 'গ্লুকোজ: ${_tierLabel(cls.glucoseTier)}'));
    if (cls.bpTier == 'stage1' || cls.bpTier == 'stage2') {
      tags.add((
        Icons.monitor_heart_outlined,
        'রক্তচাপ: ${cls.bpTier == 'stage1' ? 'পর্যায় ১' : 'পর্যায় ২'}'
      ));
    }
    if (cls.glucoseTier == 'poor' || cls.glucoseTier == 'moderate') {
      tags.add((
        Icons.no_food_outlined,
        'কার্ব ≤ ${cls.maxCarbPerMeal.toInt()} গ্রাম/বেলা'
      ));
    }
    if (foodPreference != 'omnivore') {
      tags.add((Icons.eco_outlined, _prefLabel(foodPreference)));
    }

    // Live totals from the current plan.
    final double carb = _items.fold(0.0, (s, p) => s + p.food.carbG);
    final double kcal = _items.fold(0.0,
        (s, p) => s + p.food.carbG * 4 + p.food.proteinG * 4 + p.food.fatG * 9);
    final double sodium = _items.fold(0.0, (s, p) => s + p.food.sodiumMg);

    final carbOver = dailyCarbTarget > 0 && carb > dailyCarbTarget;
    final kcalOver = dailyKcalTarget > 0 && kcal > dailyKcalTarget;
    final sodiumOver = dailySodiumCap > 0 && sodium > dailySodiumCap;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Personalization context chips.
          // Single row: clinical context tags inline (white pills
          // on the pink surface), then totals-vs-targets below.
          // Cuts ~80px off the header so meal cards have room.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF7EEF2),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFEFD3E0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 22,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.zero,
                    itemCount: tags.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (_, i) {
                      final (icon, label) = tags[i];
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFFEFD3E0)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon,
                                size: 12, color: const Color(0xFFEC7AA1)),
                            const SizedBox(width: 4),
                            Text(
                              label,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1F1018),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _TotalsMini(
                        label: 'কার্ব',
                        value: dailyCarbTarget > 0
                            ? '${carb.toInt()} / ${dailyCarbTarget.toInt()} গ্রাম'
                            : '${carb.toInt()} গ্রাম',
                        over: carbOver,
                      ),
                    ),
                    Container(
                        width: 1, height: 22, color: const Color(0xFFEFD3E0)),
                    Expanded(
                      child: _TotalsMini(
                        label: 'ক্যালোরি',
                        value: dailyKcalTarget > 0
                            ? '${kcal.toInt()} / ${dailyKcalTarget.toInt()} kcal'
                            : '${kcal.toInt()} kcal',
                        over: kcalOver,
                      ),
                    ),
                    Container(
                        width: 1, height: 22, color: const Color(0xFFEFD3E0)),
                    Expanded(
                      child: _TotalsMini(
                        label: 'সোডিয়াম',
                        value: dailySodiumCap > 0
                            ? '${sodium.toInt()} / ${dailySodiumCap.toInt()} মিগ্রা'
                            : '${sodium.toInt()} মিগ্রা',
                        over: sodiumOver,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _tierLabel(String t) {
    switch (t) {
      case 'good':
        return 'ভালো';
      case 'moderate':
        return 'মাঝারি';
      case 'poor':
        return 'খারাপ';
      default:
        return 'অজানা';
    }
  }

  static String _prefLabel(String p) {
    switch (p) {
      case 'vegetarian':
        return 'নিরামিষ';
      case 'fish_only':
        return 'শুধু মাছ';
      case 'no_beef':
        return 'গরুর মাংস বাদ';
      default:
        return 'সব খাবার';
    }
  }

  /// Top bar — mirrors the reference header: back arrow + page
  /// title + bell icon. Sits on the white canvas with deep text.
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Row(
        children: [
          // Back button — surfaces an exit-confirmer so users on the
          // home tab can pop without confirmation.
          Pressable(
            onTap: () => maybeConfirmExit(context),
            borderRadius: BorderRadius.circular(40),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0xFFF7EEF2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_back_rounded,
                  size: 20, color: _canvasInner),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'আজকের পরিকল্পনা',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: _canvasInner,
                  letterSpacing: -0.5,
                  height: 1.0,
                ),
              ),
            ),
          ),
          // Notification bell + dot.
          Pressable(
            onTap: _showFilterSheet,
            borderRadius: BorderRadius.circular(40),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0xFFF7EEF2),
                shape: BoxShape.circle,
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.notifications_none_rounded,
                      size: 20, color: _canvasInner),
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: _brandPink,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Generate a 7-day rolling window starting today so the strip
  /// always has something to scroll through, regardless of how
  /// far into the 30-day plan the user is.
  List<DateTime> _weekDates(DateTime today) {
    return List<DateTime>.generate(
      7,
      (i) => DateTime(today.year, today.month, today.day + i),
    );
  }

  /// Build the horizontal pill-style date picker modelled on the
  /// reference. Selected day fills with the brand pink; unselected
  /// days are subtle off-white pills with deep-text numerals so the
  /// strip stays easy to scan on a white canvas.
  ///
  /// Tapping a date sets `_day` directly to the corresponding slot
  /// inside the 30-day plan (today = today, today + N = today + N),
  /// then triggers `_load()` so the meal list refreshes.
  Widget _buildDateStrip(List<DateTime> dates, int activeIdx) {
    final activeIdxClamped = activeIdx.clamp(0, dates.length - 1);
    final bnWeekdays = ['সোম', 'মঙ্গল', 'বুধ', 'বৃহঃ', 'শুক্র', 'শনি', 'রবি'];
    final today = DateTime.now();
    bool isToday(DateTime d) =>
        d.year == today.year && d.month == today.month && d.day == today.day;
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: dates.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final d = dates[i];
          final selected = i == activeIdxClamped;
          final weekday = bnWeekdays[(d.weekday - 1) % 7];
          return Pressable(
            onTap: () {
              // Map the calendar offset straight onto a plan day:
              //  today → 1,  today+1 → 2,  today+6 → 7.  Using the
              //  accumulated `_day + delta` form was buggy because
              //  repeated taps walked the index off the rail.
              final newDay = (i + 1).clamp(1, 30);
              if (newDay == _day) return;
              setState(() => _day = newDay);
              _load();
            },
            child: AnimatedContainer(
              duration: AppMotion.short,
              curve: AppMotion.emphasized,
              width: 54,
              decoration: BoxDecoration(
                color: selected ? _brandPink : const Color(0xFFF7EEF2),
                border: Border.all(
                  color: selected ? _brandPink : const Color(0x1A1F1018),
                  width: 1.2,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: selected
                    ? const [
                        BoxShadow(
                          color: Color(0x44EC7AA1),
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ]
                    : const [],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    weekday,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: selected
                          ? _canvasInner
                          : _canvasInner.withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${d.day}',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                      color: selected ? _canvasInner : _canvasInner,
                    ),
                  ),
                  if (isToday(d)) ...[
                    const SizedBox(height: 2),
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: selected ? _canvasInner : _brandPink,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Group items by slot for the schedule view. Mirrors
  /// _buildBody() but skips the slot-filter bar / classification
  /// banner — those would feel out of place inside the dark card.
  Map<String, List<MealSlotPlan>> _groupItemsForView() {
    final groups = <String, List<MealSlotPlan>>{
      'breakfast': [],
      'morning_snack': [],
      'lunch': [],
      'evening_snack': [],
      'dinner': [],
      'other': [],
    };
    for (final it in _items) {
      groups[it.slot]?.add(it);
    }
    return groups;
  }

  /// Sliver body that renders the time-rail + meal-card pairs.
  Widget _buildScheduleBody(Map<String, List<MealSlotPlan>> groups) {
    if (_cls == null || _items.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: _ScheduleEmptyState(outer: _canvasInner),
      );
    }
    final order = [
      'breakfast',
      'morning_snack',
      'lunch',
      'evening_snack',
      'dinner',
    ];
    final visibleSlots = <String>[];
    for (final slot in order) {
      final list = groups[slot] ?? const [];
      if (list.isNotEmpty) visibleSlots.add(slot);
    }
    final others = groups['other'] ?? const [];
    if (others.isNotEmpty) visibleSlots.add('other');
    final totalRows = visibleSlots.length;
    final kids = <Widget>[];
    int counter = 0;
    for (final slot in visibleSlots) {
      final list = groups[slot] ?? const [];
      final time = _slotTimeRail[slot] ?? '12:00';
      kids.add(_buildScheduleRow(
        slot: slot,
        time: time,
        items: list,
        rowIndex: counter,
        totalRows: totalRows,
      ));
      counter++;
    }
    return SliverList.list(children: kids);
  }

  /// One row in the schedule = vertical time rail on the left +
  /// horizontal list of meal cards on the right (one per item in
  /// the slot — lunch can have 3-4).
  Widget _buildScheduleRow({
    required String slot,
    required String time,
    required List<MealSlotPlan> items,
    required int rowIndex,
    required int totalRows,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Vertical time rail.
          SizedBox(
            width: 64,
            child: _ScheduleTimeRail(
              time: time,
              icon: _slotIcon[slot] ?? Icons.restaurant_outlined,
              slotLabel: _slotTitleBn[slot] ?? 'খাবার',
              isFirst: rowIndex == 0,
              isLast: rowIndex == totalRows - 1,
            ),
          ),
          // Meal cards.
          Expanded(
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++)
                  Padding(
                    padding:
                        EdgeInsets.only(bottom: i == items.length - 1 ? 0 : 14),
                    child: _ScheduleMealCard(
                      item: items[i].food,
                      isCustom: items[i].isCustom,
                      isOverridden: items[i].isOverride,
                      duration: items[i].customTime ?? time,
                      rating: 4.5,
                      onTap: () => items[i].isCustom
                          ? _openCustomTile(items[i])
                          : _openItemSheet(items[i]),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Back-button action for the schedule header. HomeShell already
  /// wires the hardware-back confirmation, so the in-screen arrow
  /// just delegates to the standard pop.
  void maybeConfirmExit(BuildContext context) {
    Navigator.of(context).maybePop();
  }

  /// Modal filter sheet triggered from the top-right filter icon.
  /// Reuses the same slot pills as the in-body strip so the user
  /// can collapse down to a single meal slot without scrolling.
  Future<void> _showFilterSheet() async {
    final picked = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.graphite,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Overline('ফিল্টার'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _filterChip(ctx, 'সবগুলো', null, Icons.menu_book_rounded),
                    for (final slot in _slotOrder)
                      if (slot != 'other')
                        _filterChip(
                            ctx, _slotTitleBn[slot]!, slot, _slotIcon[slot]!),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked == null && _slotFilter == null) return;
    setState(() => _slotFilter = (picked == null) ? _slotFilter : picked);
  }

  Widget _filterChip(
      BuildContext ctx, String label, String? key, IconData icon) {
    final selected = _slotFilter == key;
    return Pressable(
      onTap: () => Navigator.pop(ctx, key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.chalk,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.ink : AppColors.graphite,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16, color: selected ? AppColors.void1 : AppColors.ink),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: selected ? AppColors.void1 : AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Horizontal chip strip used to filter the list to a single slot.
  /// Each chip shows a tiny icon + the slot label + item count,
  /// modelled after the segmented tab control from the reference.
  Future<bool?> _confirmDelete(UserMealPlan entry) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('মুছে ফেলবেন?'),
        content: Text(
          '“${entry.displayName.isEmpty ? 'এই খাবার' : entry.displayName}” আজকের পরিকল্পনা থেকে সরানো হবে।',
          style: const TextStyle(fontSize: 15, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('বাতিল'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('মুছুন'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _addCustomEntry() async {
    final result = await PlanEditorSheet.show(
      context,
      date: _todayDate(),
    );
    if (result == null || !mounted) return;
    try {
      await SupabaseService.createUserMealPlan(
        effectiveDate: _todayDate(),
        slot: result.slot,
        scheduledTime: result.scheduledTime,
        foodId: result.foodId,
        customFoodName: result.customFoodName,
        portionLabel: result.portionLabel,
        notes: result.notes,
      );
      HapticFeedback.lightImpact();
      await _load();
      AppEvents.notifyMealLogged();
    } catch (e) {
      _showError('যোগ করা যায়নি: $e');
    }
  }

  Future<void> _editCustomEntry(UserMealPlan entry) async {
    final result = await PlanEditorSheet.show(
      context,
      date: _todayDate(),
      existing: entry,
    );
    if (result == null || !mounted) return;
    try {
      await SupabaseService.updateUserMealPlan(
        id: entry.id,
        effectiveDate: _todayDate(),
        slot: result.slot,
        scheduledTime: result.scheduledTime,
        clearScheduledTime: result.clearScheduledTime,
        foodId: result.foodId,
        clearFoodId: result.clearFoodId,
        customFoodName: result.customFoodName,
        portionLabel: result.portionLabel,
        notes: result.notes,
      );
      HapticFeedback.selectionClick();
      await _load();
      AppEvents.notifyMealLogged();
    } catch (e) {
      _showError('সম্পাদনা হয়নি: $e');
    }
  }
}

/// _PillChip is now inlined into _buildPersonalizationRow()
/// (tags are rendered inline inside the totals card). Keeping
/// this section clean — no dead widget class.
/// Mini stat used in the totals row. Shows "value / target unit" and
/// flips red when over the daily cap.
class _TotalsMini extends StatelessWidget {
  final String label;
  final String value;
  final bool over;
  const _TotalsMini({
    required this.label,
    required this.value,
    required this.over,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF8A6A78),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: over
                  ? _MealPlanScreenState._brandPinkDeep
                  : _MealPlanScreenState._canvasInner,
              height: 1.1,
            ),
          ),
        ),
      ],
    );
  }
}

/// 96×96 rounded thumbnail for a meal tile.
///
/// If the underlying food has `image_url` populated, we render the
/// network image with a lightweight loading + error fallback. If
/// there's no image yet, we render a category-tinted gradient with
/// the first letter of the Bangla name so the tile still feels rich.
///
/// Sized to match the reference recipe card while staying inside the
/// 56 dp elderly-friendly tap target the rest of the app uses.
///
/// Pass `hero: true` to render a full-bleed wide image instead — this
/// is the layout used by the redesigned recipe cards (the photo sits
/// at the bottom of the card, like the reference). Falls back to the
/// same category-tinted gradient when no `image_url` is set yet.
class _MealThumbnail extends StatelessWidget {
  final MealItem food;
  final bool hero;
  const _MealThumbnail({required this.food, this.hero = false});

  static const _radius = 18.0;
  static const _size = 96.0;
  static const _heroAspect = 16 / 9;

  @override
  Widget build(BuildContext context) {
    if (hero) {
      return AspectRatio(
        aspectRatio: _heroAspect,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.zero,
            bottom: Radius.circular(_radius),
          ),
          child: food.hasImage ? _buildNetwork() : _buildFallback(),
        ),
      );
    }
    return SizedBox(
      width: _size,
      height: _size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        child: food.hasImage ? _buildNetwork() : _buildFallback(),
      ),
    );
  }

  Widget _buildNetwork() {
    return Image.network(
      food.imageUrl!,
      width: hero ? double.infinity : _size,
      height: hero ? null : _size,
      fit: BoxFit.cover,
      // We use a real-world CDN / Supabase storage URL by default;
      // headers aren't required. Add them here if you host on a
      // private bucket.
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _buildFallback();
      },
      errorBuilder: (context, error, stack) => _buildFallback(),
    );
  }

  Widget _buildFallback() {
    final initial = _initialFor(food.nameBn);
    final gradient = _gradientFor(food.category);
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(gradient: gradient),
      alignment: Alignment.center,
      child: Stack(
        children: [
          // Subtle radial highlight at the top-left to give the
          // fallback the same "lit from above" feel as a real photo.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.6, -0.7),
                  radius: 0.9,
                  colors: [
                    Colors.white.withValues(alpha: 0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Text(
              initial,
              style: const TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -0.5,
                shadows: [
                  Shadow(
                    color: Color(0x33000000),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Pick the first visible Bangla character from the food name.
  /// Falls back to a generic dot if the string is empty so we never
  /// crash on a custom tile that hasn't typed a name yet.
  String _initialFor(String s) {
    final trimmed = s.trim();
    if (trimmed.isEmpty) return '·';
    return trimmed.characters.first.toUpperCase();
  }

  LinearGradient _gradientFor(String category) {
    switch (category) {
      case 'breakfast':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)],
        );
      case 'carb':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFBBF24), Color(0xFFD97706)],
        );
      case 'protein':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEF4444), Color(0xFFB91C1C)],
        );
      case 'vegetable':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF10B981), Color(0xFF047857)],
        );
      case 'dal':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF97316), Color(0xFFC2410C)],
        );
      case 'snack':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
        );
      default:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6B7280), Color(0xFF374151)],
        );
    }
  }
}

class _ThankYouToast extends StatelessWidget {
  const _ThankYouToast();

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Positioned(
      left: 20,
      right: 20,
      bottom: mq.padding.bottom + 110,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              boxShadow: [
                BoxShadow(
                  color: AppColors.ink.withValues(alpha: 0.3),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: AppColors.paper, size: 18),
                SizedBox(width: 10),
                Text(
                  'লগ হয়েছে',
                  style: TextStyle(
                    color: AppColors.paper,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Result of the action sheet.
class _ItemSheetResult {
  final MealItem? food;
  final String? customLabel;
  final String status; // eaten | swap | off_plan
  final String impact; // good | neutral | bad
  final String? reason;
  final String? notes;

  /// Per-meal macros captured at confirm-time, used by the parent
  /// to update the running day totals and the personalization row.
  final double kcal;
  final double carbG;
  final double proteinG;
  final double fatG;
  final double sodiumMg;

  _ItemSheetResult({
    this.food,
    this.customLabel,
    required this.status,
    required this.impact,
    this.reason,
    this.notes,
    this.kcal = 0,
    this.carbG = 0,
    this.proteinG = 0,
    this.fatG = 0,
    this.sodiumMg = 0,
  });

  /// Sentinel — AI-edit / reset buttons pop the sheet without
  /// committing a meal-log action.
  const _ItemSheetResult._noop()
      : food = null,
        customLabel = null,
        status = '',
        impact = '',
        reason = null,
        notes = null,
        kcal = 0,
        carbG = 0,
        proteinG = 0,
        fatG = 0,
        sodiumMg = 0;

  bool get isNoop => status.isEmpty && impact.isEmpty && food == null;
}

class _ItemSheet extends StatefulWidget {
  final MealSlotPlan item;
  final Classification cls;
  final VoidCallback? onEditAi;
  final VoidCallback? onResetAi;
  const _ItemSheet({
    required this.item,
    required this.cls,
    this.onEditAi,
    this.onResetAi,
  });
  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  List<MealItem> _alts = [];
  bool _loading = true;
  String? _mode;
  final _customCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAlternatives();
  }

  Future<void> _loadAlternatives() async {
    try {
      final alts = await SupabaseService.getAlternatives(widget.item.food.id);
      if (!mounted) return;
      setState(() {
        _alts = alts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  MealImpact _judge(MealItem food) {
    return ImpactEngine.judge(
      food: food,
      original: widget.item.food,
      cls: widget.cls,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.paper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.graphite,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Overline('কী খাবেন?'),
                    Text(
                      widget.item.food.nameBn,
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.item.food.portionLabel ?? '',
                      style: const TextStyle(
                        color: AppColors.smoke,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildImpactSummary(_judge(widget.item.food)),
                    const SizedBox(height: 20),
                    _optionTile(
                      title: 'হ্যাঁ, এটাই খেয়েছি',
                      subtitle: 'পরিকল্পনা অনুযায়ী খাবার গ্রহণ',
                      icon: Icons.check,
                      onTap: _confirmEaten,
                    ),
                    const SizedBox(height: 10),
                    _optionTile(
                      title: 'বিকল্প খাবার খেয়েছি',
                      subtitle: 'প্রস্তাবিত বিকল্পগুলো থেকে বেছে নিন',
                      icon: Icons.swap_horiz,
                      onTap: () => setState(() => _mode = 'swap'),
                    ),
                    const SizedBox(height: 10),
                    _optionTile(
                      title: 'পরিকল্পনার বাইরে',
                      subtitle: 'অন্য কিছু খেয়ে থাকলে নাম লিখুন',
                      icon: Icons.edit_outlined,
                      onTap: () => setState(() => _mode = 'off'),
                    ),
                    if (widget.onEditAi != null) ...[
                      const SizedBox(height: 10),
                      _optionTile(
                        title: widget.item.isOverride
                            ? 'অন্য খাবার দিয়ে বদলান'
                            : 'এই খাবারটি বদলান',
                        subtitle: 'AI এর পরামর্শ এই দিনের জন্য বদলে যাবে',
                        icon: Icons.restaurant_menu,
                        onTap: widget.onEditAi!,
                      ),
                    ],
                    if (widget.onResetAi != null) ...[
                      const SizedBox(height: 10),
                      _optionTile(
                        title: 'AI এর আসল পরামর্শে ফেরত যান',
                        subtitle:
                            'বদলানো খাবার বাদ দিয়ে মূল পরিকল্পনা ফিরিয়ে আনুন',
                        icon: Icons.refresh,
                        onTap: widget.onResetAi!,
                      ),
                    ],
                    if (_mode == 'swap') _buildSwapList(),
                    if (_mode == 'off') _buildOffPlan(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _optionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.chalk,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.graphite),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 22, color: AppColors.paper),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.smoke,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward, size: 22, color: AppColors.ink),
          ],
        ),
      ),
    );
  }

  Widget _buildSwapList() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: LoadingMark(size: 28)),
      );
    }
    if (_alts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'কোনো বিকল্প পাওয়া যায়নি',
          style: TextStyle(color: AppColors.smoke),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Overline('একটি বিকল্প বেছে নিন'),
          for (final alt in _alts)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _altTile(alt),
            ),
        ],
      ),
    );
  }

  Widget _altTile(MealItem alt) {
    final impact = _judge(alt);

    return Pressable(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.pop(
          context,
          _ItemSheetResult(
            food: alt,
            status: 'swap',
            impact: impact.level,
            reason: impact.reason,
            kcal: alt.kcal,
            carbG: alt.carbG,
            proteinG: alt.proteinG,
            fatG: alt.fatG,
            sodiumMg: alt.sodiumMg,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.paper,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.graphite),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alt.nameBn,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${alt.portionLabel ?? ''} · GI: ${ImpactEngine.giLabel(alt.giCategory)}'
                    '${alt.isCheap ? " · সাশ্রয়ী" : ""}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.smoke,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    impact.reason,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.ink,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward, size: 22, color: AppColors.ink),
          ],
        ),
      ),
    );
  }

  Widget _buildOffPlan() {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Overline('খাবারের নাম লিখুন'),
          TextField(
            controller: _customCtrl,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
            decoration: const InputDecoration(
              hintText: 'যেমন: বিরিয়ানি, চা-বিস্কুট',
              prefixIcon: Icon(Icons.edit_outlined),
            ),
          ),
          const SizedBox(height: 16),
          MonoButton(
            label: 'লগ করুন',
            leading: Icons.check,
            onPressed: () {
              final txt = _customCtrl.text.trim();
              if (txt.isEmpty) return;
              Navigator.pop(
                context,
                _ItemSheetResult(
                  customLabel: txt,
                  status: 'off_plan',
                  impact: 'neutral',
                  reason: 'পরিকল্পনার বাইরে',
                  notes: txt,
                  kcal: 0,
                  carbG: 0,
                  proteinG: 0,
                  fatG: 0,
                  sodiumMg: 0,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _confirmEaten() {
    final impact = _judge(widget.item.food);
    final f = widget.item.food;
    Navigator.pop(
      context,
      _ItemSheetResult(
        food: f,
        status: 'eaten',
        impact: impact.level,
        reason: impact.reason,
        kcal: f.kcal,
        carbG: f.carbG,
        proteinG: f.proteinG,
        fatG: f.fatG,
        sodiumMg: f.sodiumMg,
      ),
    );
  }

  /// Impact preview rendered above the option tiles — Bengali
  /// reason + per-meal macros vs the user's daily caps.
  Widget _buildImpactSummary(MealImpact impact) {
    final f = widget.item.food;
    final maxCarb = widget.cls.maxCarbPerMeal;
    final tier = widget.cls.glucoseTier;
    final tierLabel = switch (tier) {
      'good' => 'ভালো গ্লুকোজ নিয়ন্ত্রণ',
      'moderate' => 'মাঝারি গ্লুকোজ',
      'poor' => 'উচ্চ গ্লুকোজ — সতর্কতা',
      _ => 'গ্লুকোজ তথ্য নেই',
    };
    final carbOver = f.carbG > maxCarb;
    final levelColor = switch (impact.level) {
      'good' => AppColors.mint,
      'bad' => AppColors.danger,
      _ => AppColors.amber,
    };
    final levelLabel = switch (impact.level) {
      'good' => 'ভালো পছন্দ',
      'bad' => 'সতর্কতা',
      _ => 'মাঝারি প্রভাব',
    };
    final levelIcon = switch (impact.level) {
      'good' => Icons.check_circle_rounded,
      'bad' => Icons.warning_amber_rounded,
      _ => Icons.info_outline_rounded,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: levelColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: levelColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(levelIcon, color: levelColor, size: 20),
              const SizedBox(width: 8),
              Text(
                levelLabel,
                style: TextStyle(
                  color: levelColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.paper,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.graphite),
                ),
                child: Text(
                  tierLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.smoke,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            impact.reason,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _impactStat(
                  label: 'কার্ব',
                  value: '${f.carbG.toStringAsFixed(0)} গ্রাম',
                  target: '${maxCarb.toStringAsFixed(0)} গ্রাম সর্বোচ্চ',
                  over: carbOver),
              const SizedBox(width: 8),
              _impactStat(
                  label: 'ক্যালোরি',
                  value: '${f.kcal.toStringAsFixed(0)} কিলোক্যালরি',
                  target: '',
                  over: false),
              const SizedBox(width: 8),
              _impactStat(
                  label: 'সোডিয়াম',
                  value: '${f.sodiumMg.toStringAsFixed(0)} মিলিগ্রাম',
                  target: '',
                  over: f.sodiumMg > 400),
            ],
          ),
        ],
      ),
    );
  }

  Widget _impactStat({
    required String label,
    required String value,
    required String target,
    required bool over,
  }) {
    final color = over ? AppColors.danger : AppColors.ink;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.paper,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.graphite),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.smoke,
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            if (target.isNotEmpty)
              Text(
                target,
                style: const TextStyle(
                  fontSize: 9,
                  color: AppColors.smoke,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }
}

/// Search-and-pick sheet for the master foods list. Used by
/// "Edit AI food" to replace the AI suggestion with a different
/// master food from `public.foods`.
class _FoodPickerSheet extends StatefulWidget {
  final String initialQuery;
  const _FoodPickerSheet({required this.initialQuery});

  @override
  State<_FoodPickerSheet> createState() => _FoodPickerSheetState();
}

class _FoodPickerSheetState extends State<_FoodPickerSheet> {
  late final TextEditingController _ctrl;
  List<MealItem> _results = const [];
  bool _loading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialQuery);
    _runSearch();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _runSearch);
  }

  Future<void> _runSearch() async {
    final q = _ctrl.text.trim();
    setState(() => _loading = true);
    try {
      final list = await SupabaseService.searchFoods(q);
      if (!mounted) return;
      setState(() {
        _results = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.graphite,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'খাবার নির্বাচন',
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 4),
              const Text(
                'মাস্টার তালিকা থেকে যেকোনো খাবার বেছে নিতে পারেন',
                style: TextStyle(
                  color: AppColors.smoke,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _ctrl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                onSubmitted: (_) => _runSearch(),
                decoration: InputDecoration(
                  hintText: 'খাবার খুঁজুন…',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: AppColors.chalk,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : _results.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'কোনো খাবার পাওয়া যায়নি',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.smoke,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: _results.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (_, i) {
                                final f = _results[i];
                                return Pressable(
                                  onTap: () => Navigator.pop(context, f),
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: AppColors.chalk,
                                      borderRadius:
                                          BorderRadius.circular(AppRadius.md),
                                      border:
                                          Border.all(color: AppColors.graphite),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                f.nameBn.isEmpty
                                                    ? '(নাম ছাড়া)'
                                                    : f.nameBn,
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w800,
                                                  color: AppColors.ink,
                                                ),
                                              ),
                                              if (f.portionLabel != null &&
                                                  f.portionLabel!.isNotEmpty)
                                                Text(
                                                  f.portionLabel!,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: AppColors.smoke,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          f.category,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.smoke,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Schedule widgets (white canvas + deep text + pink accents)
// ===========================================================================

class _ScheduleLoading extends StatelessWidget {
  const _ScheduleLoading({required this.outer});
  final Color outer;
  @override
  Widget build(BuildContext context) {
    return Container(
      color: outer,
      alignment: Alignment.center,
      child: const LoadingMark(size: 36),
    );
  }
}

class _ScheduleError extends StatelessWidget {
  const _ScheduleError({
    required this.message,
    required this.outer,
    required this.onRetry,
  });
  final String message;
  final Color outer;
  final Future<void> Function() onRetry;
  @override
  Widget build(BuildContext context) {
    return Container(
      color: outer,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFF2A1320), size: 40),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF2A1320),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          Pressable(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF6A6C5),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Retry',
                style: TextStyle(
                  color: Color(0xFF1F1018),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleEmptyState extends StatelessWidget {
  const _ScheduleEmptyState({required this.outer});
  final Color outer;
  @override
  Widget build(BuildContext context) {
    return Container(
      color: outer,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFF7EEF2),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Icon(
              Icons.restaurant_menu_rounded,
              color: Color(0xFFEC7AA1),
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No plan for today',
            style: TextStyle(
              color: Color(0xFF1F1018),
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap the button below to add your own meal',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF1F1018),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleTimeRail extends StatelessWidget {
  const _ScheduleTimeRail({
    required this.time,
    required this.icon,
    required this.slotLabel,
    required this.isFirst,
    required this.isLast,
  });
  final String time;
  final IconData icon;
  final String slotLabel;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    const Color deep = Color(0xFF1F1018);
    const Color muted = Color(0xFF8A6A78);
    const Color rail = Color(0xFFF6A6C5);
    return SizedBox(
      width: 64,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            time,
            style: const TextStyle(
              color: deep,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: rail,
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33EC7AA1),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, size: 16, color: deep),
          ),
          const SizedBox(height: 6),
          Text(
            slotLabel,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: muted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          if (!isLast) ...[
            const SizedBox(height: 8),
            const SizedBox(
              width: 2,
              height: 56,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _Dot(),
                  _Dot(),
                  _Dot(),
                ],
              ),
            ),
          ] else
            const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      height: 4,
      decoration: const BoxDecoration(
        color: Color(0x55F6A6C5),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _ScheduleMealCard extends StatelessWidget {
  const _ScheduleMealCard({
    required this.item,
    required this.onTap,
    required this.isCustom,
    required this.isOverridden,
    required this.duration,
    required this.rating,
  });
  final MealItem item;
  final Future<void> Function() onTap;
  final bool isCustom;
  final bool isOverridden;
  final String duration;
  final double rating;

  @override
  Widget build(BuildContext context) {
    const Color deep = Color(0xFF1F1018);
    const Color muted = Color(0xFF8A6A78);
    const Color card = Color(0xFFFFFFFF);
    // Vertical card layout. Image sits at the top with no opaque
    // overlay panel — the food photography stays fully visible.
    // The name, portion, and "Custom/Edited" badge sit BELOW the
    // image on a clean white surface so the visual is unambiguous
    // and senior-readable.
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Pressable(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0x1A1F1018), width: 0.8),
            boxShadow: const [
              BoxShadow(
                color: Color(0x141F1018),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 4 / 3,
                    child: _MealThumbnail(food: item, hero: true),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: _RatingPill(rating: rating),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: _DurationPill(duration: duration),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.nameBn,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: deep,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.portionLabel ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isCustom)
                      const _Pill(
                        label: 'Custom',
                        color: Color(0xFFF6A6C5),
                        fg: Color(0xFF1F1018),
                      )
                    else if (isOverridden)
                      const _Pill(
                        label: 'Edited',
                        color: Color(0xFFF6A6C5),
                        fg: Color(0xFF1F1018),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color, required this.fg});
  final String label;
  final Color color;
  final Color fg;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RatingPill extends StatelessWidget {
  const _RatingPill({required this.rating});
  final double rating;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xE6FFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x1A1F1018), width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 12, color: Color(0xFFEC7AA1)),
          const SizedBox(width: 3),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(
              color: Color(0xFF1F1018),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DurationPill extends StatelessWidget {
  const _DurationPill({required this.duration});
  final String duration;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1F1018),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, size: 12, color: Color(0xFFF6A6C5)),
          const SizedBox(width: 3),
          Text(
            duration,
            style: const TextStyle(
              color: Color(0xFFFFFFFF),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
