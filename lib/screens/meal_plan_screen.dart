// আমার ডায়েট — Meal Plan screen (v5 Premium Redesign).
library;

import 'dart:async';

import 'package:amar_diet/screens/water_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../models/thirty_day_report.dart';
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
import '../widgets/mono_widgets.dart';
import '../widgets/tab_history_mixin.dart';
import '../l10n/app_localizations.dart';

class MealPlanScreen extends StatefulWidget {
  final int initialDay;
  final bool isReadOnly;
  const MealPlanScreen({super.key, this.initialDay = 1, this.isReadOnly = false});

  @override
  State<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends State<MealPlanScreen> {
  late DateTime _selectedDate;
  late DateTime _todayDate;
  final ScrollController _stripController = ScrollController();
  
  static const int _windowSize = 15; // 15 days before and 15 days after
  static const int _todayIndex = 15;

  PlanProgress _progress = PlanProgress.fallback();
  DietClassification? _cls2;
  List<MealSlotPlan> _items = const [];
  List<UserMealPlan> _userRows = const [];
  Map<String, MealLogEntry> _todayLog = {};
  ThirtyDayReport? _trendReport;
  bool _loading = true;
  String? _error;
  String? _slotFilter;
  bool _crudHintShown = false;

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

  @override
  void initState() {
    super.initState();
    _todayDate = _dateOnly(DateTime.now());
    _selectedDate = _todayDate;
    _load();
    AppEvents.profileChanged.addListener(_onProfileChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollStripToIndex(_todayIndex, immediate: true);
    });
  }

  @override
  void dispose() {
    AppEvents.profileChanged.removeListener(_onProfileChanged);
    _stripController.dispose();
    super.dispose();
  }

  void _scrollStripToIndex(int index, {bool immediate = false}) {
    if (!_stripController.hasClients) return;
    const cellWidth = 50.0;
    const spacing = 8.0;
    const stride = cellWidth + spacing;
    final screenWidth = MediaQuery.of(context).size.width;
    
    // Calculate offset to center the cell
    final offset = (index * stride) - (screenWidth / 2) + (cellWidth / 2) + 24.0;
    
    if (immediate) {
      _stripController.jumpTo(offset.clamp(
        _stripController.position.minScrollExtent,
        _stripController.position.maxScrollExtent,
      ));
    } else {
      _stripController.animateTo(
        offset.clamp(
          _stripController.position.minScrollExtent,
          _stripController.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _onProfileChanged() {
    if (!mounted) return;
    PlanService.clearCache();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final progress = await SupabaseService.getPlanProgress();
      _progress = progress;
      final targetDay = _dayForDate(_selectedDate, progress);
      unawaited(_prebakeUserCycle(progress.planStartDate));

      final result = await _loadDayPlanWithFallback(targetDay);
      DietClassification? cls2;
      try {
        final v2 = await PlanService.classifyUser();
        cls2 = DietClassification.fromJson(Map<String, dynamic>.from(v2 as Map));
      } catch (_) { cls2 = null; }

      final results = await Future.wait([
        Future(() => _expandPlan(result)),
        Future(() async {
          try { return await SupabaseService.getUserDayPlan(_selectedDate); }
          catch (_) { return const <UserMealPlan>[]; }
        }),
        if (_isToday) SupabaseService.getDailyLog(planDay: targetDay)
        else Future<List<MealLogEntry>>.value(const []),
        SupabaseService.getThirtyDayReport(),
      ]);

      final aiItems = results[0] as List<MealSlotPlan>;
      final userRows = results[1] as List<UserMealPlan>;
      final log = results[2] as List<MealLogEntry>;
      final trend = results[3] as ThirtyDayReport?;

      final aiFiltered = aiItems.where((it) => !userRows.any((u) => u.foodId == it.food.id && (u.customFoodName ?? '').startsWith('__removed__'))).toList();
      final customItems = _customEntriesToMealSlotPlans(userRows);
      final items = <MealSlotPlan>[...aiFiltered, ...customItems];

      final today = <String, MealLogEntry>{};
      for (final e in log) {
        today['${e.mealSlot}|${e.foodId ?? ''}'] = e;
      }

      if (!mounted) return;
      setState(() {
        _items = items;
        _userRows = userRows;
        _todayLog = today;
        _cls2 = cls2;
        _trendReport = trend;
      });

      if (!_crudHintShown && userRows.where((u) => !(u.customFoodName ?? '').startsWith('__removed__')).isEmpty) {
        _crudHintShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 4),
              content: Text('যেকোনো খাবার সম্পাদনা বা মুছতে কার্ডে দীর্ঘ চাপুন'),
            ),
          );
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _dayForDate(DateTime date, PlanProgress progress) {
    final start = progress.planStartDate;
    if (start != null) {
      final daysFromStart = _dateOnly(date).difference(_dateOnly(start)).inDays;
      if (daysFromStart >= 0) {
        final mod = daysFromStart % progress.totalDays;
        return (mod + 1).clamp(1, progress.totalDays);
      }
    }
    return progress.day.clamp(1, progress.totalDays);
  }

  Future<void> _prebakeUserCycle(DateTime? planStartDate) async {
    await PlanService.ensureUpcomingPlans(days: 30);
  }

  Future<Map<String, dynamic>> _loadDayPlanWithFallback(int targetDay) async {
    try {
      final raw = await SupabaseService.getDayPlanWithFallback(targetDay);
      return _flattenV2ToLegacyJson(raw);
    } catch (_) {
      return SupabaseService.getDailyRecommendationWithOverrides(targetDay);
    }
  }

  Map<String, dynamic> _flattenV2ToLegacyJson(Map<String, dynamic> raw) {
    final List<dynamic> list;
    if (raw is List) list = raw as List<dynamic>;
    else if (raw['plan'] is List) list = raw['plan'];
    else if (raw['slots'] is List) list = raw['slots'];
    else list = const [];
    
    final out = <String, dynamic>{};
    for (final entry in list) {
      if (entry is! Map) continue;
      final m = Map<String, dynamic>.from(entry);
      final slot = (m['slot'] ?? '') as String;
      final role = (m['role'] ?? 'main') as String;
      if (slot.isEmpty) continue;
      final foodMap = {
        'id': m['food_id'] ?? m['id'],
        'name_bn': m['resolved_name'] ?? m['name_bn'] ?? '',
        'category': m['resolved_category'] ?? m['category'] ?? 'snack',
        'gi_category': m['resolved_gi'] ?? m['gi_category'] ?? 'low',
        'portion_label': m['resolved_portion'] ?? m['portion_label'],
        'portion_g': m['portion_g'],
        'carb_g': m['carb_g'] ?? 0,
        'protein_g': m['protein_g'] ?? 0,
        'fat_g': m['fat_g'] ?? 0,
      };
      if (['breakfast', 'morning_snack', 'evening_snack'].contains(slot)) out[slot] = foodMap;
      else {
        final bucket = (out[slot] as Map<String, dynamic>?) ?? <String, dynamic>{};
        bucket[role] = foodMap;
        out[slot] = bucket;
      }
    }
    return out;
  }

  List<MealSlotPlan> _customEntriesToMealSlotPlans(List<UserMealPlan> entries) {
    final out = <MealSlotPlan>[];
    for (final u in entries) {
      if ((u.customFoodName ?? '').startsWith('__removed__')) continue;
      final name = u.displayName.isNotEmpty ? u.displayName : 'কাস্টম খাবার';
      MealItem food;
      if (u.food != null) {
        try { food = MealItem.fromJson(Map<String, dynamic>.from(u.food!)); }
        catch (_) { food = _placeholderFood(name); }
      } else food = _placeholderFood(name);
      
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
    return out;
  }

  MealItem _placeholderFood(String name) {
    return MealItem(
      id: 'custom::$name', nameBn: name, category: 'custom',
      carbG: 0, proteinG: 0, fatG: 0, fiberG: 0, sodiumMg: 0, potassiumMg: 0, phosphorusMg: 0, giCategory: 'low',
    );
  }

  List<MealSlotPlan> _expandPlan(Map<String, dynamic> data) {
    final out = <MealSlotPlan>[];
    void addSlot(String slot, String role, Map<String, dynamic>? foodMap) {
      if (foodMap == null || foodMap.isEmpty) return;
      final id = foodMap['id'] as String?;
      if (id == null || id.isEmpty) return;
      out.add(MealSlotPlan(slot: slot, role: role, food: MealItem.fromJson(foodMap)));
    }
    final b = data['breakfast'];
    if (b is Map) addSlot('breakfast', 'main', Map<String, dynamic>.from(b));
    final ms = data['morning_snack'];
    if (ms is Map) addSlot('morning_snack', 'snack', Map<String, dynamic>.from(ms));
    final l = data['lunch'];
    if (l is Map) {
      final m = Map<String, dynamic>.from(l);
      addSlot('lunch', 'carb', (m['carb'] as Map?)?.cast<String, dynamic>());
      addSlot('lunch', 'protein', (m['protein'] as Map?)?.cast<String, dynamic>());
      addSlot('lunch', 'vegetable', (m['vegetable'] as Map?)?.cast<String, dynamic>());
      addSlot('lunch', 'dal', (m['dal'] as Map?)?.cast<String, dynamic>());
    }
    final es = data['evening_snack'];
    if (es is Map) addSlot('evening_snack', 'snack', Map<String, dynamic>.from(es));
    final d = data['dinner'];
    if (d is Map) {
      final m = Map<String, dynamic>.from(d);
      addSlot('dinner', 'carb', (m['carb'] as Map?)?.cast<String, dynamic>());
      addSlot('dinner', 'protein', (m['protein'] as Map?)?.cast<String, dynamic>());
      addSlot('dinner', 'vegetable', (m['vegetable'] as Map?)?.cast<String, dynamic>());
    }
    return out;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  bool get _isToday => _dateOnly(_selectedDate) == _todayDate;
  DateTime _addDays(DateTime base, int delta) => DateTime(base.year, base.month, base.day + delta);

  void _onDayPicked(DateTime day) {
    final target = _dateOnly(day);
    if (target == _selectedDate) return;
    setState(() => _selectedDate = target);
    
    final index = target.difference(_addDays(_todayDate, -_windowSize)).inDays;
    _scrollStripToIndex(index);
    _load();
  }

  void _onTodayTap() {
    if (_isToday) { _load(); return; }
    setState(() => _selectedDate = _todayDate);
    _scrollStripToIndex(_todayIndex);
    _load();
  }

  void _onStepDay(int delta) {
    final next = _addDays(_selectedDate, delta);
    final min = _addDays(_todayDate, -_windowSize);
    final max = _addDays(_todayDate, _windowSize);
    if (next.isBefore(min) || next.isAfter(max)) return;
    setState(() => _selectedDate = next);
    
    final index = next.difference(_addDays(_todayDate, -_windowSize)).inDays;
    _scrollStripToIndex(index);
    _load();
  }

  void _handleBack() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      TabHistory.maybePop();
    }
  }

  Future<void> _markEaten(MealSlotPlan plan) async {
    if (widget.isReadOnly || !_isToday) return;
    final key = '${plan.slot}|${plan.food.id}';
    if (_todayLog[key]?.status == 'eaten') return;
    HapticFeedback.lightImpact();
    try {
      final planDay = _dayForDate(_selectedDate, _progress);
      await SupabaseService.logMeal(
        mealSlot: plan.slot, foodId: plan.food.id, foodNameBn: plan.food.nameBn, status: 'eaten', impact: 'good', planDay: planDay,
      );
      setState(() {
        _todayLog[key] = MealLogEntry(id: 'tmp', mealSlot: plan.slot, foodId: plan.food.id, foodNameBn: plan.food.nameBn, status: 'eaten', impact: 'good', createdAt: DateTime.now());
      });
      // Bump the local event bus so the patient's own analytics /
      // dashboard refresh immediately (workout & water already do
      // this on their own screens; the predefined-meal flow was
      // missing it, which left today's progress stale until the
      // user pulled-to-refreshed).
      AppEvents.notifyMealLogged();
    } catch (_) {}
  }

  void _openDetails(MealSlotPlan plan) {
    final userRow = _findUserRow(plan.customId);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MealDetailsScreen(
        foodId: plan.food.id,
        fallbackNameBn: plan.food.nameBn,
        seed: plan.food,
        notes: userRow?.notes,
      ),
    ));
  }

  UserMealPlan? _findUserRow(String? customId) {
    if (customId == null || customId.isEmpty) return null;
    for (final r in _userRows) {
      if (r.id == customId) return r;
    }
    return null;
  }

  Future<void> _onCardLongPress(MealSlotPlan plan) async {
    if (widget.isReadOnly) return;
    HapticFeedback.mediumImpact();
    if (plan.isCustom) {
      final existing = _findUserRow(plan.customId);
      if (existing != null) {
        final result = await PlanEditorSheet.show(
          context,
          date: _selectedDate,
          existing: existing,
          defaultSlot: plan.slot,
        );
        if (result != null) {
          await _handleEditResult(existing, result);
        } else {
          await _load();
        }
      }
      return;
    }
    if (plan.isAi) {
      final action = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: AppColors.paper,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (ctx) {
          return SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.graphite, borderRadius: BorderRadius.circular(4)),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 6, 24, 6),
                  child: Row(
                    children: [
                      Container(width: 6, height: 20, decoration: const BoxDecoration(color: AppColors.svcHero)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(plan.food.nameBn, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.ink)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                ListTile(
                  leading: const Icon(Icons.edit_outlined, color: AppColors.ink),
                  title: const Text('এই খাবারটি সম্পাদনা করুন'),
                  subtitle: const Text('একটি নতুন user_meal_plans এন্ট্রি তৈরি হবে'),
                  onTap: () => Navigator.pop(ctx, 'edit'),
                ),
                ListTile(
                  leading: const Icon(Icons.visibility_off_outlined, color: Colors.red),
                  title: const Text('আজকের জন্য সরান', style: TextStyle(color: Colors.red)),
                  subtitle: const Text('AI পরামর্শ লুকিয়ে রাখুন'),
                  onTap: () => Navigator.pop(ctx, 'remove'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      );
      if (!mounted) return;
      if (action == 'edit') {
        final result = await PlanEditorSheet.show(
          context,
          date: _selectedDate,
          existing: null,
          defaultSlot: plan.slot,
        );
        if (result != null) await _handleAddResult(result);
      } else if (action == 'remove') {
        await _softRemoveAiEntry(plan);
      }
    }
  }

  Future<void> _onAddMealTap() async {
    final result = await PlanEditorSheet.show(
      context,
      date: _selectedDate,
      existing: null,
      defaultSlot: _slotOrder.first,
    );
    if (result != null) await _handleAddResult(result);
  }

  Future<void> _handleAddResult(PlanEditResult r) async {
    try {
      await SupabaseService.createUserMealPlan(
        effectiveDate: _selectedDate,
        slot: r.slot,
        scheduledTime: r.scheduledTime,
        foodId: r.foodId,
        customFoodName: r.customFoodName,
        portionLabel: r.portionLabel,
        notes: r.notes,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('সংরক্ষণ ব্যর্থ: $e')));
      return;
    }
    await _load();
  }

  Future<void> _handleEditResult(UserMealPlan existing, PlanEditResult r) async {
    try {
      await SupabaseService.updateUserMealPlan(
        id: existing.id,
        slot: r.slot,
        scheduledTime: r.scheduledTime,
        clearScheduledTime: r.clearScheduledTime,
        foodId: r.foodId,
        clearFoodId: r.clearFoodId,
        customFoodName: r.customFoodName,
        portionLabel: r.portionLabel,
        notes: r.notes,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('সম্পাদনা ব্যর্থ: $e')));
      return;
    }
    await _load();
  }

  Future<void> _softRemoveAiEntry(MealSlotPlan plan) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('আজকের জন্য সরাবেন?'),
        content: Text('"${plan.food.nameBn}" আজকের পরিকল্পনা থেকে লুকিয়ে রাখা হবে। অন্য দিনে এটি আবার দেখা যাবে।'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('বাতিল')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('সরান'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await SupabaseService.createUserMealPlan(
        effectiveDate: _selectedDate,
        slot: plan.slot,
        foodId: plan.food.id,
        customFoodName: '__removed__::${plan.food.id}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('মুছে ফেলা ব্যর্থ: $e')));
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.svcCategoryBg,
        body: SafeArea(
          top: false,
          child: RefreshIndicator(
            onRefresh: _load,
            color: AppColors.svcHero,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              slivers: [
                _buildHero(),
                const SliverToBoxAdapter(child: SizedBox(height: 22)),
                SliverToBoxAdapter(child: _buildSectionTitle('আজকের লক্ষ্য', 'স্বাস্থ্য সূচক')),
                SliverToBoxAdapter(child: _buildDailyGoals()),
                SliverToBoxAdapter(child: _buildMealProgress()),
                if (_trendReport != null)
                  SliverToBoxAdapter(child: _MealTrendAnalysis(report: _trendReport!)),
                SliverToBoxAdapter(child: _buildWaterRedirectCard()),
                const SliverToBoxAdapter(child: SizedBox(height: 22)),
                SliverToBoxAdapter(child: _buildSectionTitle('খাবারের তালিকা', 'পরিকল্পিত')),
                ..._buildMealCardSlivers(),
                const SliverToBoxAdapter(child: SizedBox(height: 140)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHero() {
    const url = 'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/app/photo-1564352969906-8b7f46ba4b8b.avif?token=eyJraWQiOiJhZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJhcHAvcGhvdG8tMTU2NDM1Mjk2OTkwNi04YjdmNDZiYTRiOGIuYXZpZiIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODc4Njg2MjksImV4cCI6MTgxOTQwNDYyOX0.Jdl-6cqT6wHh_nv8j-7oD3zjU2KcoR4e5ohJVnZgTNs';
    final headerDateLabel = DateFormat('EEEE, d MMMM yyyy', 'bn').format(_selectedDate);

    return SliverToBoxAdapter(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.svcHero,
          image: const DecorationImage(image: NetworkImage(url), fit: BoxFit.cover, opacity: 0.7),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: Container(color: Colors.black.withValues(alpha: 0.3))),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 20, 0),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                          onPressed: _handleBack,
                        ),
                        const Expanded(
                          child: Text(
                            'খাবার পরিকল্পনা',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                          ),
                        ),
                        _todayPill(_isToday),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headerDateLabel,
                        style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -0.6),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'আপনার স্বাস্থ্যের জন্য উপযোগী খাবার',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _buildWeekStrip(),
                const SizedBox(height: 20),
                _buildSlotFilter(),
                const SizedBox(height: 24),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekStrip() {
    final start = _addDays(_todayDate, -_windowSize);
    final days = List.generate(_windowSize * 2 + 1, (i) => _addDays(start, i));
    
    return Row(
      children: [
        _navArrow(icon: Icons.chevron_left, enabled: _selectedDate.isAfter(_addDays(_todayDate, -_windowSize)), onTap: () => _onStepDay(-1)),
        Expanded(
          child: SizedBox(
            height: 70,
            child: ListView.separated(
              controller: _stripController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              physics: const BouncingScrollPhysics(),
              itemCount: days.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => _dayCell(days[i]),
            ),
          ),
        ),
        _navArrow(icon: Icons.chevron_right, enabled: _selectedDate.isBefore(_addDays(_todayDate, _windowSize)), onTap: () => _onStepDay(1)),
      ],
    );
  }

  Widget _dayCell(DateTime d) {
    final isSel = _dateOnly(d) == _selectedDate;
    final isToday = _dateOnly(d) == _todayDate;
    return GestureDetector(
      onTap: () => _onDayPicked(d),
      child: AnimatedContainer(
        duration: AppMotion.short,
        width: 50,
        decoration: BoxDecoration(
          color: isSel ? Colors.white : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.zero,
          border: Border.all(color: isSel ? Colors.white : Colors.white24, width: 1.2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(DateFormat('E', 'bn').format(d).substring(0, 1), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: isSel ? AppColors.svcHero : Colors.white70)),
            Text('${d.day}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: isSel ? AppColors.svcHero : Colors.white)),
            if (isToday) Container(margin: const EdgeInsets.only(top: 2), width: 4, height: 4, decoration: const BoxDecoration(color: AppColors.svcHeroAccent, shape: BoxShape.circle)),
          ],
        ),
      ),
    );
  }

  Widget _navArrow({required IconData icon, required bool enabled, required VoidCallback onTap}) {
    return IconButton(onPressed: enabled ? onTap : null, icon: Icon(icon, color: enabled ? Colors.white : Colors.white24, size: 20));
  }

  Widget _todayPill(bool isToday) {
    return InkWell(
      onTap: _onTodayTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: isToday ? AppColors.svcHeroAccent : Colors.white12, borderRadius: BorderRadius.zero, border: Border.all(color: Colors.white24)),
        child: Text('আজ', style: TextStyle(color: isToday ? AppColors.svcHero : Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
      ),
    );
  }

  Widget _buildSlotFilter() {
    Widget chip(String label, String? key) {
      final active = _slotFilter == key;
      return GestureDetector(
        onTap: () => setState(() => _slotFilter = key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          margin: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.zero,
            border: Border.all(color: active ? Colors.white : Colors.white24, width: 1.2),
          ),
          child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: active ? AppColors.svcHero : Colors.white)),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [chip('সব', null), chip('সকালের নাস্তা', 'breakfast'), chip('দুপুর', 'lunch'), chip('রাত', 'dinner'), chip('স্ন্যাক', 'snack')],
      ),
    );
  }

  Widget _buildSectionTitle(String title, String sub) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.newsInk, letterSpacing: -0.3)),
          Text(sub, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.newsMuted.withValues(alpha: 0.8))),
        ],
      ),
    );
  }

  Widget _buildDailyGoals() {
    final cls = _cls2;
    final kcalTarget = cls?.dailyKcalTarget ?? 1800;
    double kcalTaken = 0;
    for (final e in _todayLog.values) {
      if (e.status == 'eaten') {
        final item = _items.firstWhere((m) => m.food.id == e.foodId, orElse: () => MealSlotPlan(slot: e.mealSlot, role: 'main', food: _placeholderFood('')));
        kcalTaken += item.food.kcal;
      }
    }
    final progress = (kcalTaken / kcalTarget).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: AppColors.line, width: 1.2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ক্যালোরি লক্ষ্যমাত্রা', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.smoke, letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  Text('${kcalTaken.round()} / ${kcalTarget.round()} kcal', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.ink, letterSpacing: -0.5)),
                  const SizedBox(height: 12),
                  MonoBar(value: progress, height: 8, fill: AppColors.svcHero),
                ],
              ),
            ),
            const SizedBox(width: 24),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(width: 64, height: 64, child: CircularProgressIndicator(value: progress, strokeWidth: 10, color: AppColors.svcHero, backgroundColor: AppColors.surfaceHigh)),
                Text('${(progress * 100).round()}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.ink)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Day-level "how much have I eaten today" analysis card.
  /// Counts the planned items, how many have been logged as 'eaten',
  /// and renders a ring + headline + stacked bar + two summary tiles.
  Widget _buildMealProgress() {
    final l = AppLocalizations.of(context)!;
    final total = _items.length;
    int eaten = 0;
    for (final it in _items) {
      if (_todayLog['${it.slot}|${it.food.id}']?.status == 'eaten') {
        eaten++;
      }
    }
    final remaining = (total - eaten).clamp(0, total);
    final pct = total == 0 ? 0.0 : (eaten / total).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: AppColors.line, width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.mealProgressTitle,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: AppColors.smoke,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l.mealProgressOfTotal(eaten, total, (pct * 100).round()),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.ink,
                          letterSpacing: -0.5,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 68,
                  height: 68,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 68,
                        height: 68,
                        child: CircularProgressIndicator(
                          value: pct,
                          strokeWidth: 9,
                          color: AppColors.svcHero,
                          backgroundColor: AppColors.surfaceHigh,
                        ),
                      ),
                      Text(
                        '${(pct * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildMealBreakdownBar(eaten: eaten, remaining: remaining),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _buildMealBreakdownTile(
                    Icons.check_circle_rounded,
                    AppColors.svcHero,
                    l.mealAggregateEatenLabel,
                    eaten,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMealBreakdownTile(
                    Icons.radio_button_unchecked_rounded,
                    AppColors.lineStrong,
                    l.mealAggregatePendingLabel,
                    remaining,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Stacked horizontal bar showing eaten / remaining as proportional widths.
  Widget _buildMealBreakdownBar({required int eaten, required int remaining}) {
    if (eaten == 0 && remaining == 0) {
      return Container(
        height: 8,
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.zero,
        ),
      );
    }
    return Row(
      children: [
        if (eaten > 0)
          Expanded(
            flex: (eaten * 1000).round(),
            child: Container(height: 8, color: AppColors.svcHero),
          ),
        if (remaining > 0)
          Expanded(
            flex: (remaining * 1000).round(),
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.zero,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMealBreakdownTile(IconData icon, Color color, String label, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.svcCategoryBg,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.line, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
              letterSpacing: -0.4,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.smoke,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMealCardSlivers() {
    final groups = <String, List<MealSlotPlan>>{};
    for (final it in _items) groups.putIfAbsent(it.slot, () => []).add(it);
    final children = <Widget>[];
    final slots = _slotFilter == null ? _slotOrder : (_slotFilter == 'snack' ? ['morning_snack', 'evening_snack'] : [_slotFilter!]);
    for (final slot in slots) {
      final list = groups[slot];
      if (list == null || list.isEmpty) continue;
      children.add(SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 24, 20, 10), child: Row(
        children: [
          Container(width: 6, height: 20, decoration: const BoxDecoration(color: AppColors.svcHero, borderRadius: BorderRadius.zero)),
          const SizedBox(width: 10),
          Text(_slotTitleBn[slot] ?? slot, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.svcHero)),
        ],
      ))));
      children.add(SliverList.builder(itemCount: list.length, itemBuilder: (context, i) => _mealCard(list[i])));
    }
    children.add(SliverToBoxAdapter(child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: widget.isReadOnly ? const SizedBox.shrink() : InkWell(
        onTap: _onAddMealTap,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.zero,
            border: Border.all(color: AppColors.svcHero, width: 1.4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.add_rounded, color: AppColors.svcHero, size: 22),
              SizedBox(width: 8),
              Text('নতুন খাবার যোগ করুন', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.svcHero, letterSpacing: 0.2)),
            ],
          ),
        ),
      ),
    )));
    return children;
  }

  Widget _mealCard(MealSlotPlan plan) {
    final eaten = _todayLog['${plan.slot}|${plan.food.id}']?.status == 'eaten';
    final userRow = plan.source == 'custom' ? _findUserRow(plan.customId) : null;
    final displayKcal = userRow != null ? userRow.kcal : plan.food.kcal;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: InkWell(
        onTap: () => _openDetails(plan),
        onLongPress: () => _onCardLongPress(plan),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.zero,
            border: Border.all(color: eaten ? AppColors.svcHero : AppColors.line, width: eaten ? 1.6 : 1.2),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 12, offset: const Offset(0, 6))],
          ),
          child: Row(
            children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(color: AppColors.svcCategoryBg, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line, width: 0.8)),
                clipBehavior: Clip.antiAlias,
                child: _thumb(plan.food),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plan.food.nameBn, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.ink, height: 1.2)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.zero), child: Text('${displayKcal.round()} kcal', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.smoke))),
                        const SizedBox(width: 8),
                        Text(_roleLabel(plan.role), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.smoke.withValues(alpha: 0.7))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: widget.isReadOnly ? null : () => _markEaten(plan),
                child: AnimatedContainer(
                  duration: AppMotion.short,
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: eaten ? AppColors.svcHero : AppColors.surfaceHigh,
                    borderRadius: BorderRadius.zero,
                    border: Border.all(color: eaten ? AppColors.svcHero : AppColors.line, width: 1.5),
                  ),
                  child: Icon(Icons.check_rounded, color: eaten ? Colors.white : AppColors.lineStrong, size: 24),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumb(MealItem food) {
    if (food.imageUrl?.isNotEmpty ?? false) return Image.network(food.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _thumbFallback(food));
    return _thumbFallback(food);
  }

  Widget _thumbFallback(MealItem food) => Container(color: AppColors.svcCategoryBg, alignment: Alignment.center, child: Text(food.nameBn.isEmpty ? '?' : food.nameBn.characters.first, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.svcHero)));

  String _roleLabel(String role) {
    if (role == 'carb') return 'কার্বোহাইড্রেট';
    if (role == 'protein') return 'প্রোটিন';
    if (role == 'vegetable') return 'সবজি';
    if (role == 'dal') return 'ডাল';
    return 'প্রধান খাবার';
  }

  Widget _buildWaterRedirectCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WaterScreen())),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: AppGradients.aurora,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.cyanDeep.withValues(alpha: 0.45), width: 1.2),
          ),
          child: const Row(
            children: [
              Icon(Icons.water_drop_rounded, color: Colors.white, size: 28),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('পর্যাপ্ত পানি পান করেছেন?', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                    Text('আপনার হাইড্রেশন লেভেল ট্র্যাক করুন', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _MealTrendAnalysis extends StatelessWidget {
  final ThirtyDayReport report;
  const _MealTrendAnalysis({required this.report});

  @override
  Widget build(BuildContext context) {
    const double target = 5; // typical target meals per day
    final data = report.days.where((d) => !d.isFuture).map((d) => _ChartData(d.dayOfCycle, d.loggedMeals.total.toDouble())).toList();
    
    // Dynamic Scaling:
    double maxVal = data.isEmpty ? 0 : data.map((e) => e.value).fold(0, (p, c) => (p > c) ? p : c);
    double chartMax = (maxVal > target * 1.5) ? maxVal * 1.1 : target * 1.5;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('খাবারের ধারাবাহিকতা', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.ink)),
          const SizedBox(height: 4),
          const Text('গত ৩০ দিনের খাবারের সংখ্যা বিশ্লেষণ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.smoke)),
          const SizedBox(height: 16),
          Container(
            height: 200,
            padding: const EdgeInsets.fromLTRB(10, 20, 16, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.zero,
              border: Border.all(color: AppColors.line, width: 1.5),
            ),
            child: SfCartesianChart(
              margin: EdgeInsets.zero,
              plotAreaBorderWidth: 0,
              primaryXAxis: NumericAxis(
                interval: 5,
                majorGridLines: const MajorGridLines(width: 0),
                axisLine: const AxisLine(width: 1),
                labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
              ),
              primaryYAxis: NumericAxis(
                minimum: 0,
                maximum: chartMax,
                labelFormat: '{value}',
                majorTickLines: const MajorTickLines(size: 0),
                axisLine: const AxisLine(width: 0),
                majorGridLines: const MajorGridLines(width: 0.5, dashArray: [5, 5]),
                labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
              ),
              series: <CartesianSeries<_ChartData, num>>[
                ColumnSeries<_ChartData, num>(
                  dataSource: data,
                  xValueMapper: (_ChartData d, _) => d.day,
                  yValueMapper: (_ChartData d, _) => d.value,
                  color: AppColors.amber,
                  borderRadius: BorderRadius.zero,
                  width: 0.7,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartData {
  final int day;
  final double value;
  _ChartData(this.day, this.value);
}
