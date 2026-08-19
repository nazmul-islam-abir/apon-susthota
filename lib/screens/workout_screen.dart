import 'package:flutter/material.dart';

import '../models/workout.dart';
import '../services/app_events.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';
import 'workout_details_screen.dart';

/// "ব্যায়াম" tab — today's workout for the 30-day program.
///
/// Loads the day's assignment list via `get_today_workout(p_day_index)`,
/// groups it into a hero progress card and a vertical list of tiles.
/// Each tile opens `WorkoutDetailsScreen` for the per-exercise timer.
///
/// Designed for the elderly user:
///   • 56 dp tap targets, oversized Bangla labels.
///   • Single chunky "শুরু করুন / পরবর্তী" call to action.
///   • Live progress (completed / total + elapsed time).
class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  TodaysWorkout? _todays;
  WorkoutTimeTracking _tracking = WorkoutTimeTracking.empty;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    AppEvents.workoutChanged.addListener(_onChanged);
  }

  @override
  void dispose() {
    AppEvents.workoutChanged.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Make sure the user has assignments before fetching — idempotent.
      await SupabaseService.ensureDefaultWorkoutAssignments();
      // Also call the self-healing per-user RPC which re-activates
      // any soft-deactivated rows AND seeds the full 30-day plan for
      // this user. Together they guarantee the analytics + today list
      // always reflect every exercise the user is meant to do.
      await SupabaseService.seedMyWorkoutAssignments();
      // Day index is 1-based; we keep "today = dayIndex 1" for now and let
      // the day-progression work in `meal_plan_screen.dart` push it later.
      final results = await Future.wait([
        SupabaseService.getTodayWorkout(),
        SupabaseService.getWorkoutTimeRows(days: 7),
        SupabaseService.getTodayExerciseTimeFeedback(),
      ]);
      if (!mounted) return;
      final t = results[0] as TodaysWorkout?;
      final rows = (results[1] as List?)?.cast<WorkoutTimeRow>() ?? const [];
      final fb =
          (results[2] as Map?)?.cast<String, WorkoutExerciseTimeFeedback>() ??
              const {};
      setState(() {
        _todays = t;
        _tracking = WorkoutTimeTracking(daily: rows, byWorkout: fb);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openDetails(WorkoutAssignment assignment) async {
    final t = _todays;
    if (t == null) return;

    // If the session isn't open yet, start it now.
    WorkoutSession? session = t.session;
    if (session == null) {
      try {
        await SupabaseService.startWorkoutSession(dayIndex: t.dayIndex);
        // Reload so we have the freshly-created session + items.
        await _load();
        if (!mounted) return;
        session = _todays?.session;
        if (session == null) return;
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('সেশন শুরু করা যায়নি — আবার চেষ্টা করুন।')),
        );
        return;
      }
    }

    // We don't require a pre-existing session_item row anymore — the
    // `finish_workout_session_item` RPC lazy-creates it from
    // (sessionId, workoutId). That removes the "এই ব্যায়ামের সেশন
    // আইটেম পাওয়া যায়নি" snackbar that used to fire when a user
    // clicked a tile on a day the open session wasn't seeded for.
    // We still try to find the existing item first so that pre-seeded
    // rows get reused (cheaper + consistent with analytics).
    WorkoutSessionItem? existingItem;
    for (final it in session.items) {
      if (it.workoutId == assignment.workout.id) {
        existingItem = it;
        break;
      }
    }

    if (!mounted) return;
    final sessionId = session.id;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorkoutDetailsScreen(
          assignment: assignment,
          sessionItemId: existingItem?.id,
          sessionId: sessionId,
        ),
      ),
    );
    AppEvents.notifyWorkoutChanged();
    _load();
  }

  Future<void> _startSession() async {
    final t = _todays;
    if (t == null) return;
    try {
      await SupabaseService.startWorkoutSession(dayIndex: t.dayIndex);
      AppEvents.notifyWorkoutChanged();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('শুরু করা যায়নি: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.ink,
          backgroundColor: AppColors.paper,
          onRefresh: _load,
          child: _loading
              ? const Center(child: LoadingMark(size: 36))
              : _error != null
                  ? _buildError()
                  : _todays == null
                      ? const SizedBox.shrink()
                      : CustomScrollView(
                          slivers: [
                            SliverToBoxAdapter(child: _buildHeader()),
                            SliverToBoxAdapter(child: _buildHeroBanner()),
                            if (_todays != null && _todays!.assignments.isEmpty)
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: _buildEmpty(),
                              )
                            else if (_todays != null) ...[
                              SliverToBoxAdapter(child: _buildMyActivity()),
                              SliverToBoxAdapter(
                                  child: _buildScheduleSection()),
                            ],
                            const SliverToBoxAdapter(
                                child: SizedBox(height: 140)),
                          ],
                        ),
        ),
      ),
    );
  }

  // ── Header (compact top bar with greeting + action) ───────────
  Widget _buildHeader() {
    final t = _todays!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Overline('ব্যায়াম'),
                const SizedBox(height: 8),
                Text(
                  'Build your body',
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                    letterSpacing: -0.8,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'দিন ${t.dayIndex} / ৩০  •  আজকের রুটিন',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.smoke,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          _buildBellIcon(),
        ],
      ),
    );
  }

  Widget _buildBellIcon() {
    return Pressable(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('নোটিফিকেশন শীঘ্রই আসছে')),
        );
      },
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.notifications_active_rounded,
            color: AppColors.void1, size: 22),
      ),
    );
  }

  // ── Hero banner (dark card with progress + illustration) ──────
  Widget _buildHeroBanner() {
    final t = _todays!;
    final total = t.assignments.length;
    final done = t.completedCount;
    final pct = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    final started = t.session != null;
    final finished = t.isFinished;
    final elapsedMin = (t.session?.totalDurationSeconds ?? 0) ~/ 60;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1A2E), Color(0xFF0F0F1E), Color(0xFF000000)],
            stops: [0.0, 0.6, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withValues(alpha: 0.35),
              blurRadius: 28,
              offset: const Offset(0, 16),
            ),
          ],
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
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.cyan,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            finished
                                ? 'COMPLETE'
                                : started
                                    ? 'IN PROGRESS'
                                    : 'GET STARTED',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: AppColors.cyan,
                              letterSpacing: 1.6,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'আজকের',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB6B6C9),
                          height: 1.1,
                        ),
                      ),
                      Text(
                        finished
                            ? 'চমৎকার কাজ!'
                            : started
                                ? 'চলছে...'
                                : 'শুরু করুন',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: AppColors.void1,
                          height: 1.05,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _buildHeroStat('$done', 'করেছেন'),
                          const SizedBox(width: 22),
                          _buildHeroStat('$total', 'মোট'),
                          if (elapsedMin > 0) ...[
                            const SizedBox(width: 22),
                            _buildHeroStat('$elapsedMin মি', 'সময়'),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                _buildHeroIllustration(),
              ],
            ),
            const SizedBox(height: 22),
            _buildWeeklyProgress(pct, finished, started),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    finished
                        ? 'আজকের ব্যায়াম সম্পন্ন — দারুণ!'
                        : started
                            ? 'আরও ${total - done}টি বাকি — দারুণ চলছে!'
                            : 'আজকের $totalটি ব্যায়াম আপনার জন্য প্রস্তুত',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFB6B6C9),
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.cyan,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${(pct * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: AppColors.void1,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            if (!started && total > 0) ...[
              const SizedBox(height: 18),
              _buildStartButton(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeroStat(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: AppColors.void1,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF8E8EA3),
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }

  Widget _buildHeroIllustration() {
    // Stylised yoga / dumbbell scene drawn with gradients & shapes
    // — no external assets, scales correctly. Mirrors the editorial
    // hero in the reference.
    return SizedBox(
      width: 110,
      height: 110,
      child: Stack(
        children: [
          // glow
          Positioned(
            right: -10,
            top: -10,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    AppColors.cyan.withValues(alpha: 0.45),
                    Colors.transparent
                  ],
                ),
              ),
            ),
          ),
          // person figure
          Positioned.fill(
            child: CustomPaint(painter: _WorkoutFigurePainter(t: 1.0)),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyProgress(double pct, bool finished, bool started) {
    final clamped = pct.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'সাপ্তাহিক অগ্রগতি',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF8E8EA3),
                letterSpacing: 1.2,
              ),
            ),
            const Spacer(),
            Text(
              '${(clamped * 100).round()}%',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: AppColors.void1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 8,
            child: Stack(
              children: [
                Positioned.fill(
                    child: Container(color: const Color(0xFF2A2A3E))),
                FractionallySizedBox(
                  widthFactor: clamped,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF10B981), Color(0xFF34D399)],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStartButton() {
    return Pressable(
      onTap: _startSession,
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF10B981), Color(0xFF059669)],
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: AppColors.cyan.withValues(alpha: 0.4),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.play_arrow_rounded, color: AppColors.void1, size: 26),
            SizedBox(width: 10),
            Text(
              'আজকের সেশন শুরু করুন',
              style: TextStyle(
                color: AppColors.void1,
                fontSize: 17,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── "My Activity" — real analytics derived from workout data ──
  //
  // All numbers below are computed from real persisted data:
  //   • `_tracking.daily`     → per-day rows from `get_workout_time_tracking`
  //   • `_tracking.byWorkout` → per-exercise feedback from
  //                             `get_today_exercise_time_feedback`
  //   • `_todays`             → today's assignments + session state
  // No user-typed input is collected here — the user previously had
  // manually-entered steps / water / heart-rate tiles, which have
  // been replaced with a derived, read-only analytics block.
  Widget _buildMyActivity() {
    // ── Overall exercise % (last 7 days, weighted by target time) ──
    final daily = _tracking.daily;
    int totalTargetSec = 0;
    int totalActualSec = 0;
    int activeDays = 0;
    for (final r in daily) {
      totalTargetSec += r.targetSeconds;
      totalActualSec += r.actualSeconds;
      if (r.actualSeconds > 0) activeDays++;
    }
    final overallPct = totalTargetSec == 0
        ? 0.0
        : ((totalActualSec / totalTargetSec) * 100.0).clamp(0.0, 100.0);

    // ── Streak: consecutive days at the tail with any actual time ──
    final today = _tracking.today;
    int streak = 0;
    for (int i = daily.length - 1; i >= 0; i--) {
      if (daily[i].actualSeconds > 0) {
        streak++;
      } else {
        break;
      }
    }
    // Treat "today" as a fresh streak even if no time logged yet.
    final bool todayCountsEvenIfZero = streak == 0 && today.targetSeconds > 0;

    // ── Today's headline numbers ──
    final todayPct = today.targetSeconds == 0
        ? 0.0
        : ((today.actualSeconds / today.targetSeconds) * 100.0)
            .clamp(0.0, 100.0);
    final todayPlanned = today.plannedCount;
    final todayCompleted = today.completedCount;
    final todayMinutes = today.actualMinutes;
    final targetMinutes = today.targetMinutes;

    // ── Motivation line (Bangla) derived from the computed state ──
    final String motivation;
    final Color motivationColor;
    final IconData motivationIcon;
    if (overallPct >= 90) {
      motivation =
          'অসাধারণ! ধারাবাহিকতা বজায় রাখুন — লক্ষ্যের চেয়ে এগিয়ে আছেন।';
      motivationColor = const Color(0xFF059669);
      motivationIcon = Icons.emoji_events_rounded;
    } else if (overallPct >= 70) {
      motivation = 'চমৎকার অগ্রগতি! আরেকটু ধারাবাহিক থাকলে লক্ষ্য পূরণ হবে।';
      motivationColor = const Color(0xFF10B981);
      motivationIcon = Icons.trending_up_rounded;
    } else if (overallPct >= 40) {
      motivation = 'ভালো চলছে — প্রতিদিন একটু একটু করে লক্ষ্যের কাছাকাছি।';
      motivationColor = const Color(0xFF0EA5E9);
      motivationIcon = Icons.flash_on_rounded;
    } else if (overallPct > 0 || today.actualSeconds > 0) {
      motivation = 'শুরু করেছেন, এগিয়ে যান — প্রতিটি মিনিট গুরুত্বপূর্ণ।';
      motivationColor = const Color(0xFFF59E0B);
      motivationIcon = Icons.directions_run_rounded;
    } else {
      motivation =
          'আজকের ব্যায়াম শুরু করুন — প্রথম পদক্ষেপই সবচেয়ে কঠিন, তবে সবচেয়ে মূল্যবানও।';
      motivationColor = AppColors.smoke;
      motivationIcon = Icons.flag_rounded;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Row(
              children: [
                const Icon(Icons.insights_rounded,
                    color: AppColors.ink, size: 22),
                const SizedBox(width: 8),
                Text(
                  'আমার কার্যকলাপ',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'এই সপ্তাহ',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.smoke,
                          letterSpacing: 0.6,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.expand_more_rounded,
                          size: 14, color: AppColors.smoke),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Headline: overall exercise % with progress arc ────
          _buildOverallExerciseCard(
            overallPct: overallPct,
            totalActualMinutes: totalActualSec ~/ 60,
            totalTargetMinutes: totalTargetSec ~/ 60,
            activeDays: activeDays,
            totalDays: daily.length,
          ),
          const SizedBox(height: 12),

          // ── Two small tiles: today & streak ────────────────────
          Row(
            children: [
              Expanded(
                child: _buildAnalyticsTile(
                  label: 'আজকের অগ্রগতি',
                  value: todayPlanned == 0
                      ? '—'
                      : '${(todayPct).toStringAsFixed(0)}%',
                  sub: todayPlanned == 0
                      ? 'আজ ব্যায়াম নির্ধারিত নেই'
                      : '$todayCompleted / $todayPlanned সেট সম্পন্ন',
                  icon: Icons.today_rounded,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFE4F1), Color(0xFFFFD4E8)],
                  ),
                  accent: const Color(0xFFEC4899),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildAnalyticsTile(
                  label: 'আজকের সময়',
                  value: targetMinutes == 0
                      ? '—'
                      : '$todayMinutes / $targetMinutes',
                  sub: targetMinutes == 0 ? 'মিনিট' : 'মিনিট',
                  icon: Icons.timer_rounded,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFD0F4FF), Color(0xFFA8E6FF)],
                  ),
                  accent: const Color(0xFF0EA5E9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Streak row ─────────────────────────────────────────
          _buildStreakBanner(
            streak: streak,
            todayCountsEvenIfZero: todayCountsEvenIfZero,
          ),
          const SizedBox(height: 12),

          // ── Motivation banner ──────────────────────────────────
          _buildMotivationBanner(
            text: motivation,
            color: motivationColor,
            icon: motivationIcon,
          ),
        ],
      ),
    );
  }

  /// Headline card: a circular progress arc wrapping the overall %.
  Widget _buildOverallExerciseCard({
    required double overallPct,
    required int totalActualMinutes,
    required int totalTargetMinutes,
    required int activeDays,
    required int totalDays,
  }) {
    final clamped = overallPct.clamp(0.0, 100.0);
    final arcColor = clamped >= 70
        ? const Color(0xFF059669)
        : clamped >= 40
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEC4899);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.chalk, width: 1),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            height: 84,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 84,
                  height: 84,
                  child: CircularProgressIndicator(
                    value: clamped / 100.0,
                    strokeWidth: 8,
                    backgroundColor: AppColors.surfaceHigh,
                    valueColor: AlwaysStoppedAnimation<Color>(arcColor),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${clamped.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'সামগ্রিক',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.smoke,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'সামগ্রিক ব্যায়াম শতাংশ',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.smoke,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  totalTargetMinutes == 0
                      ? 'এখনও কোনো লক্ষ্য নির্ধারিত হয়নি'
                      : '$totalActualMinutes মিনিট / $totalTargetMinutes মিনিট',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  totalDays == 0
                      ? 'ডেটা লোড হচ্ছে…'
                      : 'সক্রিয় দিন: $activeDays / $totalDays',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.smoke,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Compact analytics tile (used for today + time).
  Widget _buildAnalyticsTile({
    required String label,
    required String value,
    required String sub,
    required IconData icon,
    required Gradient gradient,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: accent,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sub,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.smoke,
            ),
          ),
        ],
      ),
    );
  }

  /// Streak banner — auto-calculated from the daily rows.
  Widget _buildStreakBanner({
    required int streak,
    required bool todayCountsEvenIfZero,
  }) {
    final display = streak > 0 ? streak : (todayCountsEvenIfZero ? 1 : 0);
    final String text;
    final String sub;
    if (display == 0) {
      text = 'আজকের ধারা শুরু করুন';
      sub = 'একটানা দিনের গণনা এখানে দেখানো হবে';
    } else if (display == 1) {
      text = '১ দিনের ধারা';
      sub = todayCountsEvenIfZero
          ? 'আজকের ব্যায়াম শেষ করলে ধারা এগিয়ে যাবে'
          : 'আজকের সেশন শেষ করলে ধারা এগিয়ে যাবে';
    } else {
      text = '$display দিনের ধারা';
      sub = 'আজকের সেশন শেষ করলে ধারা এগিয়ে যাবে';
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.chalk, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFFFE4F1),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.local_fire_department_rounded,
              color: Color(0xFFEC4899),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.smoke,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Motivation banner — auto-generated Bangla line.
  Widget _buildMotivationBanner({
    required String text,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.22), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: color,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── "আজকের রুটিন" — exercise list with circular thumbnails ────
  Widget _buildScheduleSection() {
    final t = _todays!;
    final ordered = [...t.assignments]
      ..sort((a, b) => a.position.compareTo(b.position));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Row(
              children: [
                const Icon(Icons.list_alt_rounded,
                    color: AppColors.ink, size: 22),
                const SizedBox(width: 8),
                Text(
                  'আজকের রুটিন',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${t.completedCount}/${t.assignments.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (int i = 0; i < ordered.length; i++)
            _buildScheduleRow(
              ordered[i],
              _findItem(ordered[i]),
              _tracking.byWorkout[ordered[i].workout.id],
              i == ordered.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _buildScheduleRow(
    WorkoutAssignment assignment,
    WorkoutSessionItem? item,
    WorkoutExerciseTimeFeedback? feedback,
    bool isLast,
  ) {
    final w = assignment.workout;
    final completed = item?.isCompleted ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline column (dot + connector)
          SizedBox(
            width: 44,
            child: Column(
              children: [
                _buildTimelineDot(completed),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 56,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: completed
                          ? AppColors.cyan.withValues(alpha: 0.5)
                          : AppColors.line,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Pressable(
              onTap: () => _openDetails(assignment),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                decoration: BoxDecoration(
                  color: completed ? AppColors.ink : AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: completed ? AppColors.ink : AppColors.line,
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    _buildExerciseAvatar(w, completed),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            w.nameBn,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color:
                                  completed ? AppColors.void1 : AppColors.ink,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              _buildChip(
                                w.targetDurationLabel,
                                completed ? AppColors.void1 : AppColors.smoke,
                                completed
                                    ? AppColors.ink
                                    : AppColors.surfaceHigh,
                              ),
                              if (w.targetCaloriesKcal > 0)
                                _buildChip(
                                    '${w.targetCaloriesKcal} ক্যাল',
                                    completed
                                        ? AppColors.void1
                                        : AppColors.smoke,
                                    completed
                                        ? AppColors.ink
                                        : AppColors.surfaceHigh),
                              _buildChip(
                                  w.intensity.labelBn,
                                  completed ? AppColors.void1 : AppColors.smoke,
                                  completed
                                      ? AppColors.ink
                                      : AppColors.surfaceHigh),
                              if (feedback != null &&
                                  feedback.pct > 0 &&
                                  !completed)
                                _buildPctChip(feedback.pct),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color:
                            completed ? AppColors.cyan : AppColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        completed
                            ? Icons.check_rounded
                            : Icons.play_arrow_rounded,
                        color: completed ? AppColors.void1 : AppColors.ink,
                        size: 18,
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

  Widget _buildPctChip(double pct) {
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

  Widget _buildTimelineDot(bool completed) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: completed ? AppColors.cyan : AppColors.void1,
        shape: BoxShape.circle,
        border: Border.all(
          color: completed ? AppColors.cyan : AppColors.line,
          width: 2,
        ),
        boxShadow: completed
            ? [
                BoxShadow(
                  color: AppColors.cyan.withValues(alpha: 0.4),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: Icon(
        completed ? Icons.check_rounded : Icons.timer_outlined,
        color: completed ? AppColors.void1 : AppColors.smoke,
        size: 18,
      ),
    );
  }

  Widget _buildExerciseAvatar(Workout w, bool completed) {
    final IconData icon = _categoryIcon(w.category);
    final LinearGradient gradient = _categoryGradient(w.category);
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: completed ? null : gradient,
        color: completed ? AppColors.graphite : null,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: AppColors.void1, size: 24),
    );
  }

  Widget _buildChip(String text, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: fg,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(Icons.fitness_center,
                  color: AppColors.paper, size: 36),
            ),
            const SizedBox(height: 18),
            Text(
              'আজকের জন্য কোনো ব্যায়াম নেই',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'পরে আবার দেখুন — প্রোগ্রাম স্বয়ংক্রিয়ভাবে চলবে।',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.smoke,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 56, color: AppColors.ink),
            const SizedBox(height: 12),
            Text('লোড করা যায়নি',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(_error ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.smoke, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            MonoButton(label: 'আবার চেষ্টা করুন', onPressed: _load),
          ],
        ),
      ),
    );
  }

  // ── Lookup helpers ──────────────────────────────────────────────────

  WorkoutSessionItem? _findItem(WorkoutAssignment a) {
    final session = _todays?.session;
    if (session == null) return null;
    for (final it in session.items) {
      if (it.workoutId == a.workout.id) return it;
    }
    return null;
  }

  // ── Category icon / gradient ────────────────────────────────────────

  IconData _categoryIcon(WorkoutCategory c) {
    switch (c) {
      case WorkoutCategory.cardio:
        return Icons.local_fire_department_rounded;
      case WorkoutCategory.strength:
        return Icons.fitness_center_rounded;
      case WorkoutCategory.flexibility:
        return Icons.self_improvement_rounded;
      case WorkoutCategory.balance:
        return Icons.balance_rounded;
      case WorkoutCategory.breathing:
        return Icons.air_rounded;
      case WorkoutCategory.yoga:
        return Icons.spa_rounded;
      case WorkoutCategory.household:
        return Icons.home_work_rounded;
      case WorkoutCategory.walking:
        return Icons.directions_walk_rounded;
    }
  }

  LinearGradient _categoryGradient(WorkoutCategory c) {
    switch (c) {
      case WorkoutCategory.cardio:
        return const LinearGradient(
            colors: [Color(0xFFFFE0E0), Color(0xFFFFA6A6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight);
      case WorkoutCategory.strength:
        return const LinearGradient(
            colors: [Color(0xFFFFF3E0), Color(0xFFFFCC80)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight);
      case WorkoutCategory.flexibility:
        return const LinearGradient(
            colors: [Color(0xFFE0F7FA), Color(0xFFA8E6F1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight);
      case WorkoutCategory.balance:
        return const LinearGradient(
            colors: [Color(0xFFE8F5E9), Color(0xFFA5D6A7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight);
      case WorkoutCategory.breathing:
        return const LinearGradient(
            colors: [Color(0xFFE3F2FD), Color(0xFFB7DCFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight);
      case WorkoutCategory.yoga:
        return const LinearGradient(
            colors: [Color(0xFFF3E5F5), Color(0xFFCE93D8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight);
      case WorkoutCategory.household:
        return const LinearGradient(
            colors: [Color(0xFFFFF8E1), Color(0xFFFFE082)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight);
      case WorkoutCategory.walking:
        return const LinearGradient(
            colors: [Color(0xFFE0F2F1), Color(0xFF80CBC4)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight);
    }
  }
}

// ── Hero figure painter ────────────────────────────────────────────

class _WorkoutFigurePainter extends CustomPainter {
  final double t;

  _WorkoutFigurePainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final skin = Paint()..color = const Color(0xFFF4D6C2);
    final skinDark = Paint()..color = const Color(0xFFE0B79A);
    final cloth = Paint()..color = const Color(0xFFFF8A65);
    final clothDark = Paint()..color = const Color(0xFFE76F51);
    final shorts = Paint()..color = const Color(0xFF1E1E1E);
    final hair = Paint()..color = const Color(0xFF3A2A20);
    final white = Paint()..color = Colors.white;
    final dark = Paint()..color = const Color(0xFF1E1E1E);
    final dark2 = Paint()..color = const Color(0xFF2C2C2C);

    final w = size.width;
    final h = size.height;

    // Head
    final head = Offset(w * 0.5, h * 0.18);
    canvas.drawCircle(head, w * 0.075, skin);

    // Hair cap
    final hairPath = Path()
      ..moveTo(head.dx - w * 0.075, head.dy - w * 0.01)
      ..quadraticBezierTo(
          head.dx, head.dy - w * 0.12, head.dx + w * 0.075, head.dy - w * 0.01)
      ..lineTo(head.dx + w * 0.06, head.dy + w * 0.01)
      ..lineTo(head.dx - w * 0.06, head.dy + w * 0.01)
      ..close();
    canvas.drawPath(hairPath, hair);

    // Neck
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(head.dx, head.dy + w * 0.08),
        width: w * 0.06,
        height: h * 0.04,
      ),
      skinDark,
    );

    // Torso (tank top)
    final torso = Path()
      ..moveTo(head.dx - w * 0.12, head.dy + w * 0.11)
      ..lineTo(head.dx + w * 0.12, head.dy + w * 0.11)
      ..lineTo(head.dx + w * 0.14, head.dy + w * 0.40)
      ..quadraticBezierTo(
          head.dx, head.dy + w * 0.45, head.dx - w * 0.14, head.dy + w * 0.40)
      ..close();
    canvas.drawPath(torso, cloth);
    // Tank top straps
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(head.dx - w * 0.06, head.dy + w * 0.13),
        width: w * 0.04,
        height: h * 0.05,
      ),
      clothDark,
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(head.dx + w * 0.06, head.dy + w * 0.13),
        width: w * 0.04,
        height: h * 0.05,
      ),
      clothDark,
    );

    // Left arm (raised holding dumbbell)
    final armL = Path()
      ..moveTo(head.dx - w * 0.12, head.dy + w * 0.14)
      ..lineTo(head.dx - w * 0.28, head.dy - w * 0.02)
      ..lineTo(head.dx - w * 0.26, head.dy + w * 0.06)
      ..lineTo(head.dx - w * 0.10, head.dy + w * 0.20)
      ..close();
    canvas.drawPath(armL, skin);

    // Right arm (down)
    final armR = Path()
      ..moveTo(head.dx + w * 0.12, head.dy + w * 0.14)
      ..lineTo(head.dx + w * 0.22, head.dy + w * 0.30)
      ..lineTo(head.dx + w * 0.18, head.dy + w * 0.32)
      ..lineTo(head.dx + w * 0.08, head.dy + w * 0.18)
      ..close();
    canvas.drawPath(armR, skin);

    // Dumbbell in left hand
    final dbCenter = Offset(head.dx - w * 0.30, head.dy - w * 0.06);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: dbCenter,
          width: w * 0.10,
          height: h * 0.025,
        ),
        const Radius.circular(4),
      ),
      dark,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(dbCenter.dx - w * 0.05, dbCenter.dy),
          width: w * 0.03,
          height: h * 0.05,
        ),
        const Radius.circular(3),
      ),
      dark2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(dbCenter.dx + w * 0.05, dbCenter.dy),
          width: w * 0.03,
          height: h * 0.05,
        ),
        const Radius.circular(3),
      ),
      dark2,
    );

    // Shorts
    final shortsPath = Path()
      ..moveTo(head.dx - w * 0.14, head.dy + w * 0.38)
      ..lineTo(head.dx + w * 0.14, head.dy + w * 0.38)
      ..lineTo(head.dx + w * 0.13, head.dy + w * 0.55)
      ..lineTo(head.dx + w * 0.02, head.dy + w * 0.55)
      ..lineTo(head.dx - w * 0.02, head.dy + w * 0.55)
      ..lineTo(head.dx - w * 0.13, head.dy + w * 0.55)
      ..close();
    canvas.drawPath(shortsPath, shorts);

    // Left leg
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(head.dx - w * 0.06, head.dy + w * 0.65),
          width: w * 0.10,
          height: h * 0.20,
        ),
        const Radius.circular(8),
      ),
      skin,
    );
    // Right leg
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(head.dx + w * 0.06, head.dy + w * 0.65),
          width: w * 0.10,
          height: h * 0.20,
        ),
        const Radius.circular(8),
      ),
      skin,
    );
    // Shoes
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
            head.dx - w * 0.13, head.dy + w * 0.74, w * 0.12, h * 0.04),
        const Radius.circular(4),
      ),
      white,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
            head.dx + w * 0.005, head.dy + w * 0.74, w * 0.12, h * 0.04),
        const Radius.circular(4),
      ),
      white,
    );

    // Subtle highlight pulse on chest
    final pulse = Paint()
      ..color = const Color(0xFFFFB199).withOpacity(0.18 * t)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.06);
    canvas.drawCircle(
      Offset(head.dx, head.dy + w * 0.27),
      w * 0.08,
      pulse,
    );
  }

  @override
  bool shouldRepaint(covariant _WorkoutFigurePainter old) => old.t != t;
}
