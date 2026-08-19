# -*- coding: utf-8 -*-
"""
Wire DailyMetric live data into workout_screen.dart.

Plan:
  1. Add `_daily` state field (DailyMetric) and load it inside `_load()`.
  2. Replace the static derivations in `_buildMyActivity` with `_daily`.
  3. Wrap each stat tile in a Pressable that opens an edit bottom sheet.
  4. Add a % chip in `_buildScheduleRow` when there's a partial feedback.
  5. Add three bottom-sheet helpers: `_showWaterSheet`, `_showHeartRateSheet`,
     `_showStepsSheet`. Each calls the relevant SupabaseService method and
     re-runs `_load()` so the UI updates.
"""
import io

path = r'c:\Users\Nazmul\StudioProjects\diabetics_meal-main\lib\screens\workout_screen.dart'

with io.open(path, 'r', encoding='utf-8') as f:
    src = f.read()

# ── 1. Add state field ─────────────────────────────────────────
old_state = u"  TodaysWorkout? _todays;\n  WorkoutTimeTracking _tracking = WorkoutTimeTracking.empty;\n  bool _loading = true;\n  String? _error;\n"
new_state = u"""  TodaysWorkout? _todays;
  WorkoutTimeTracking _tracking = WorkoutTimeTracking.empty;
  DailyMetric _daily = DailyMetric.empty;
  bool _loading = true;
  String? _error;
"""
assert old_state in src, 'state field anchor not found'
src = src.replace(old_state, new_state, 1)

# ── 2. Extend _load() to fetch DailyMetric in parallel ────────
old_load_block = u"""      final results = await Future.wait([
        SupabaseService.getTodayWorkout(),
        SupabaseService.getWorkoutTimeRows(days: 7),
        SupabaseService.getTodayExerciseTimeFeedback(),
      ]);
      if (!mounted) return;
      final t = results[0] as TodaysWorkout?;
      final rows = (results[1] as List?)?.cast<WorkoutTimeRow>() ?? const [];
      final fb = (results[2] as Map?)?.cast<String, WorkoutExerciseTimeFeedback>() ?? const {};
      setState(() {
        _todays = t;
        _tracking = WorkoutTimeTracking(daily: rows, byWorkout: fb);
      });"""
new_load_block = u"""      final results = await Future.wait([
        SupabaseService.getTodayWorkout(),
        SupabaseService.getWorkoutTimeRows(days: 7),
        SupabaseService.getTodayExerciseTimeFeedback(),
        SupabaseService.getTodayDailyMetrics(),
      ]);
      if (!mounted) return;
      final t = results[0] as TodaysWorkout?;
      final rows = (results[1] as List?)?.cast<WorkoutTimeRow>() ?? const [];
      final fb = (results[2] as Map?)?.cast<String, WorkoutExerciseTimeFeedback>() ?? const {};
      final dm = (results[3] as DailyMetric?) ?? DailyMetric.empty;
      setState(() {
        _todays = t;
        _tracking = WorkoutTimeTracking(daily: rows, byWorkout: fb);
        _daily = dm;
      });"""
assert old_load_block in src, 'load block anchor not found'
src = src.replace(old_load_block, new_load_block, 1)

# ── 3. Replace static derivations in _buildMyActivity ─────────
old_activity = u"""  // ── "My Activity" — steps / water / heart rate tiles ───────
  Widget _buildMyActivity() {
    final t = _todays!;
    // Derive proxy numbers for the activity tiles. The workout RPC
    // doesn't expose step count or water intake, so we synthesise
    // them from progress + completed minutes — they still feel
    // honest and motivate consistency without making up data.
    final fbValues = _tracking.byWorkout.values.toList();
    final done = t.completedCount;
    final totalFb = fbValues.fold<int>(0, (s, f) => s + f.targetMinutes);
    final actualFb = fbValues.fold<int>(0, (s, f) => s + f.actualMinutes);
    final steps = done * 1200 + 1400; // baseline + bonus per exercise
    final water = 1.6 + (actualFb * 0.05).clamp(0.0, 0.6);
    final heartRate = (62 + (totalFb ~/ 4)).clamp(55, 135);
    return Padding("""
new_activity = u"""  // ── "My Activity" — steps / water / heart rate tiles ───────
  Widget _buildMyActivity() {
    // Live values come from `daily_metrics` (see supabasesql/18_*.sql).
    // Falls back to "—" when the user hasn't entered anything yet.
    final stepsValue = _daily.hasSteps ? _daily.steps.toString() : '—';
    final waterValue = _daily.isWater ? _daily.waterLiters.toStringAsFixed(1) : '0.0';
    final heartValue = _daily.hasHeartRate ? _daily.heartRateBpm.toString() : '—';
    return Padding("""
assert old_activity in src, 'activity anchor not found'
src = src.replace(old_activity, new_activity, 1)

# ── 4. Wire steps tile to live value + edit sheet ─────────────
old_steps = u"""              Expanded(
                child: _buildStatTile(
                  'Steps',
                  steps.toString(),
                  'পদক্ষেপ',
                  Icons.directions_walk_rounded,
                  const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFE4F1), Color(0xFFFFD4E8)],
                  ),
                  const Color(0xFFEC4899),
                ),
              ),"""
new_steps = u"""              Expanded(
                child: Pressable(
                  onTap: () => _showStepsSheet(),
                  child: _buildStatTile(
                    'Steps',
                    stepsValue,
                    'পদক্ষেপ',
                    Icons.directions_walk_rounded,
                    const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFFE4F1), Color(0xFFFFD4E8)],
                    ),
                    const Color(0xFFEC4899),
                  ),
                ),
              ),"""
assert old_steps in src, 'steps tile anchor not found'
src = src.replace(old_steps, new_steps, 1)

# ── 5. Wire water tile to live value + edit sheet ─────────────
old_water = u"""              Expanded(
                child: _buildStatTile(
                  'Water',
                  water.toStringAsFixed(1),
                  'লিটার',
                  Icons.water_drop_rounded,
                  const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFD0F4FF), Color(0xFFA8E6FF)],
                  ),
                  const Color(0xFF0EA5E9),
                ),
              ),"""
new_water = u"""              Expanded(
                child: Pressable(
                  onTap: () => _showWaterSheet(),
                  child: _buildStatTile(
                    'Water',
                    waterValue,
                    'লিটার',
                    Icons.water_drop_rounded,
                    const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFD0F4FF), Color(0xFFA8E6FF)],
                    ),
                    const Color(0xFF0EA5E9),
                  ),
                ),
              ),"""
assert old_water in src, 'water tile anchor not found'
src = src.replace(old_water, new_water, 1)

# ── 6. Wire heart rate tile ────────────────────────────────────
old_hr = u"""          const SizedBox(height: 12),
          _buildHeartRateTile(heartRate.toString()),
        ],
      ),
    );
  }"""
new_hr = u"""          const SizedBox(height: 12),
          Pressable(
            onTap: () => _showHeartRateSheet(),
            child: _buildHeartRateTile(heartValue),
          ),
        ],
      ),
    );
  }

  // ── Edit sheets — water / heart-rate / steps ────────────────
  Future<void> _showWaterSheet() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'পানি যোগ করুন',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'আজ মোট: ${_daily.waterLiters.toStringAsFixed(2)} লিটার',
                  style: const TextStyle(
                    color: AppColors.smoke,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    for (final d in const [0.25, 0.5, 0.75, 1.0]) ...[
                      Expanded(
                        child: MonoButton(
                          label: '+${d == d.toInt() ? d.toInt() : d} L',
                          onTap: () async {
                            Navigator.pop(ctx);
                            final next =
                                await SupabaseService.addWaterLiters(d);
                            if (!mounted) return;
                            setState(() => _daily = next);
                            _load();
                          },
                        ),
                      ),
                      if (d != 1.0) const SizedBox(width: 8),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showHeartRateSheet() async {
    final ctrl = TextEditingController(
      text: _daily.hasHeartRate ? _daily.heartRateBpm.toString() : '',
    );
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            18,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'হৃদস্পন্দন (bpm)',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'যেমন: 72',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              MonoButton(
                label: 'সংরক্ষণ করুন',
                onTap: () async {
                  final v = int.tryParse(ctrl.text.trim());
                  if (v == null || v < 30 || v > 230) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                          content: Text('৩০–২৩০ এর মধ্যে একটি সংখ্যা দিন।')),
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  final next = await SupabaseService.setHeartRate(v);
                  if (!mounted) return;
                  setState(() => _daily = next);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showStepsSheet() async {
    final ctrl = TextEditingController(
      text: _daily.hasSteps ? _daily.steps.toString() : '',
    );
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            18,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'আজকের পদক্ষেপ',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'যেমন: 4000',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              MonoButton(
                label: 'সংরক্ষণ করুন',
                onTap: () async {
                  final v = int.tryParse(ctrl.text.trim());
                  if (v == null || v < 0 || v > 200000) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('একটি বৈধ সংখ্যা দিন।')),
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  final next = await SupabaseService.setSteps(v);
                  if (!mounted) return;
                  setState(() => _daily = next);
                },
              ),
            ],
          ),
        );
      },
    );
  }"""
assert old_hr in src, 'heart-rate anchor not found'
src = src.replace(old_hr, new_hr, 1)

# ── 7. Add % chip in _buildScheduleRow ────────────────────────
old_chip_block = u"""                              _buildChip(
                                  w.intensity.labelBn,
                                  completed
                                      ? AppColors.void1
                                      : AppColors.smoke,
                                  completed
                                      ? AppColors.ink
                                      : AppColors.surfaceHigh),
                            ],"""
new_chip_block = u"""                              _buildChip(
                                  w.intensity.labelBn,
                                  completed
                                      ? AppColors.void1
                                      : AppColors.smoke,
                                  completed
                                      ? AppColors.ink
                                      : AppColors.surfaceHigh),
                              if (feedback != null && feedback.pct > 0 && !completed)
                                _buildPctChip(feedback.pct),
                            ],"""
assert old_chip_block in src, 'chip anchor not found'
src = src.replace(old_chip_block, new_chip_block, 1)

# ── 8. Add _buildPctChip helper (insert before _buildTimelineDot) ──
old_paint_anchor = u"  Widget _buildTimelineDot(bool completed) {"
new_paint_anchor = u"""  Widget _buildPctChip(double pct) {
    final done = pct >= 0.999;
    final color = done ? AppColors.mint : AppColors.cyan;
    final pctText = '${(pct * 100).round()}%';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        pctText,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: AppColors.ink,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _buildTimelineDot(bool completed) {"""
assert old_paint_anchor in src, 'timeline-dot anchor not found'
src = src.replace(old_paint_anchor, new_paint_anchor, 1)

with io.open(path, 'w', encoding='utf-8') as f:
    f.write(src)
print('OK: workout_screen.dart wired')