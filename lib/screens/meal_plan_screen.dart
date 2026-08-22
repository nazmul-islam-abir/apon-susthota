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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/meal_item.dart';
import '../models/workout.dart';
import '../screens/meal_details_screen.dart';
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
  int _day = 1;
  int? _todayDayIndex;
  // ignore: unused_field
  DietClassification? _cls2;
  List<MealSlotPlan> _items = const [];
  Map<String, MealLogEntry> _todayLog = {};
  // ignore: unused_field
  DailyMetric _daily = DailyMetric.empty;
  bool _loading = true;
  String? _error;
  String? _slotFilter; // null = all

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
  };

  static const Map<String, IconData> _slotIcon = {
    'breakfast': Icons.wb_sunny_outlined,
    'morning_snack': Icons.coffee_outlined,
    'lunch': Icons.lunch_dining_outlined,
    'evening_snack': Icons.cookie_outlined,
    'dinner': Icons.nightlight_outlined,
  };

  @override
  void initState() {
    super.initState();
    _day = widget.initialDay;
    _load();
    AppEvents.profileChanged.addListener(_onProfileChanged);
  }

  @override
  void dispose() {
    AppEvents.profileChanged.removeListener(_onProfileChanged);
    super.dispose();
  }

  void _onProfileChanged() {
    if (!mounted) return;
    setState(() {
      _todayDayIndex = null;
    });
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final progress = await SupabaseService.getPlanProgress();
      final hadToday = _todayDayIndex;
      var targetDay = _day.clamp(1, progress.totalDays);
      if (hadToday == null) {
        targetDay = progress.day;
      } else if (_day == hadToday && progress.day > hadToday) {
        targetDay = progress.day;
      }

      final result =
          await SupabaseService.getDailyRecommendationWithOverrides(targetDay);
      DietClassification? cls2;
      try {
        final v2 = await PlanService.classifyUser();
        cls2 =
            DietClassification.fromJson(Map<String, dynamic>.from(v2 as Map));
      } catch (_) {
        cls2 = null;
      }

      final results = await Future.wait([
        Future(() => _expandPlan(result)),
        SupabaseService.getDailyLog(planDay: targetDay),
        SupabaseService.getTodayDailyMetrics(),
      ]);
      final items = results[0] as List<MealSlotPlan>;
      final log = results[1] as List<MealLogEntry>;
      final daily = results[2] as DailyMetric;

      final today = <String, MealLogEntry>{};
      for (final e in log) {
        final key = '${e.mealSlot}|${e.foodId ?? ''}';
        today[key] = e;
      }

      if (!mounted) return;
      setState(() {
        _day = targetDay;
        _todayDayIndex = progress.day;
        _cls2 = cls2;
        _items = items;
        _todayLog = today;
        _daily = daily;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

  Future<void> _markEaten(MealSlotPlan plan) async {
    final key = '${plan.slot}|${plan.food.id}';
    if (_todayLog[key]?.status == 'eaten') {
      HapticFeedback.lightImpact();
      return;
    }
    HapticFeedback.lightImpact();
    try {
      await SupabaseService.logMeal(
        mealSlot: plan.slot,
        foodId: plan.food.id,
        foodNameBn: plan.food.nameBn,
        status: 'eaten',
        impact: 'good',
        planDay: _day,
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

  // ── Week strip ──────────────────────────────────────────────────────
  Widget _buildWeekStrip() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final selected = now; // simple: always lock to today
    final days = List.generate(7, (i) => monday.add(Duration(days: i)));
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(7, (i) {
          final d = days[i];
          final isSel = d.year == selected.year &&
              d.month == selected.month &&
              d.day == selected.day;
          return _dayCell(labels[i], d.day, isSel);
        }),
      ),
    );
  }

  Widget _dayCell(String label, int day, bool selected) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.mintDeep : AppColors.textDim,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.mint : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$day',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: selected ? AppColors.void1 : AppColors.text,
            ),
          ),
        ),
      ],
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
        ],
      ),
    );
  }

  Widget _mealCard(MealSlotPlan plan) {
    final logKey = '${plan.slot}|${plan.food.id}';
    final eaten = _todayLog[logKey]?.status == 'eaten';
    final swap = _todayLog[logKey]?.status == 'swap';
    final food = plan.food;
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
              color: eaten
                  ? AppColors.mintDeep
                  : swap
                      ? AppColors.amber
                      : AppColors.line,
              width: eaten || swap ? 1.4 : 1,
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
                            color: AppColors.surfaceHigh,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _slotTitleBn[plan.slot] ?? plan.slot,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textMuted,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
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
                    Text(
                      _roleLabel(plan.role),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _eatenButton(logKey, eaten, swap, plan),
            ],
          ),
        ),
      ),
    );
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
