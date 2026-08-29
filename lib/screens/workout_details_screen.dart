// আমার ডায়েট — Workout Details screen (v5 Redesign).
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/workout.dart';
import '../services/app_events.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';
import '../widgets/workout_video_player.dart';

class WorkoutDetailsScreen extends StatefulWidget {
  final WorkoutAssignment assignment;
  final String? sessionItemId;
  final String sessionId;

  const WorkoutDetailsScreen({
    super.key,
    required this.assignment,
    required this.sessionId,
    this.sessionItemId,
  });

  @override
  State<WorkoutDetailsScreen> createState() => _WorkoutDetailsScreenState();
}

class _WorkoutDetailsScreenState extends State<WorkoutDetailsScreen> {
  Timer? _ticker;
  int _baseSeconds = 0;
  int _runSeconds = 0;
  bool _running = false;
  bool _completed = false;
  bool _saving = false;

  int get _totalSeconds => _baseSeconds + _runSeconds;

  @override
  void initState() {
    super.initState();
    _loadBaseline();
  }

  Future<void> _loadBaseline() async {
    try {
      final map = await SupabaseService.getTodayExerciseTimeFeedback();
      final fb = map[widget.assignment.workout.id];
      if (!mounted) return;
      setState(() {
        _baseSeconds = fb?.actualSeconds ?? 0;
        _completed = (fb?.actualSeconds ?? 0) >= (widget.assignment.workout.targetDurationSeconds);
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _toggleTimer() {
    HapticFeedback.selectionClick();
    if (_completed) return;
    if (_running) _pause(); else _start();
  }

  void _start() {
    if (_running || _completed) return;
    setState(() => _running = true);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _runSeconds += 1);
      _maybeAutoComplete();
    });
  }

  void _maybeAutoComplete() {
    if (_completed) return;
    final target = widget.assignment.workout.targetDurationSeconds;
    if (target <= 0 || _totalSeconds < target) return;
    HapticFeedback.heavyImpact();
    _completed = true;
    final run = _runSeconds;
    setState(() { _running = false; _baseSeconds += run; _runSeconds = 0; });
    _persist(seconds: _baseSeconds, completed: true, runAtPause: run);
  }

  Future<void> _pause() async {
    if (!_running) return;
    _ticker?.cancel();
    _ticker = null;
    final runAtPause = _runSeconds;
    setState(() { _running = false; _baseSeconds += runAtPause; _runSeconds = 0; });
    if (runAtPause <= 0) return;
    await _persist(seconds: _baseSeconds, completed: false, runAtPause: runAtPause);
  }

  Future<void> _persist({required int seconds, required bool completed, int? runAtPause}) async {
    if (_saving) return;
    final stickyCompleted = _completed || completed;
    setState(() => _saving = true);
    try {
      await SupabaseService.finishWorkoutSessionItem(
        itemId: widget.sessionItemId, sessionId: widget.sessionId, workoutId: widget.assignment.workout.id, durationSeconds: seconds, completed: stickyCompleted,
      );
      AppEvents.notifyWorkoutChanged();
      if (!mounted) return;
      setState(() { _saving = false; if (completed) _completed = true; _baseSeconds = seconds; });
    } catch (_) { if (mounted) setState(() => _saving = false); }
  }

  String _fmt(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final r = (s % 60).toString().padLeft(2, '0');
    return '$m:$r';
  }

  void _handleBack() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.assignment.workout;
    final targetSec = w.targetDurationSeconds;
    final progress = targetSec <= 0 ? 0.0 : (_totalSeconds / targetSec).clamp(0.0, 1.0);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop && _running) { _ticker?.cancel(); _ticker = null; await _pause(); }
      },
      child: Scaffold(
        backgroundColor: AppColors.paper,
        body: SafeArea(
          top: false,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              _buildHero(w),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              SliverToBoxAdapter(child: _buildVideoSection(w)),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              SliverToBoxAdapter(child: _buildTimerCard(progress, targetSec)),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              SliverToBoxAdapter(child: _buildStatsGrid(w)),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              SliverToBoxAdapter(child: _buildContentBox('ব্যায়াম বিবরণ', w.descriptionBn, Icons.description_outlined)),
              if (w.instructions.isNotEmpty)
                SliverToBoxAdapter(child: _buildInstructionsBox(w.instructions)),
              if (w.equipment.isNotEmpty)
                SliverToBoxAdapter(child: _buildEquipmentBox(w.equipment)),
              const SliverToBoxAdapter(child: SizedBox(height: 60)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero(Workout w) {
    const url = 'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/app/photo-1564352969906-8b7f46ba4b8b.avif?token=eyJraWQiOiJhZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJhcHAvcGhvdG8tMTU2NDM1Mjk2OTkwNi04YjdmNDZiYTRiOGIuYXZpZiIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODc4Njg2MjksImV4cCI6MTgxOTQwNDYyOX0.Jdl-6cqT6wHh_nv8j-7oD3zjU2KcoR4e5ohJVnZgTNs';
    return SliverToBoxAdapter(
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          color: AppColors.svcHero,
          image: const DecorationImage(image: NetworkImage(url), fit: BoxFit.cover, opacity: 0.7),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: Container(color: Colors.black.withValues(alpha: 0.3))),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                          onPressed: _handleBack,
                        ),
                        const Expanded(child: Text('ব্যায়াম বিস্তারিত', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900))),
                        const Icon(Icons.bookmark_outline_rounded, color: Colors.white, size: 24),
                      ],
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 20),
                      child: Text(w.nameBn, style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoSection(Workout w) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line, width: 1.2)),
        clipBehavior: Clip.antiAlias,
        child: WorkoutVideoPlayer(storagePath: w.videoUrl, label: w.nameBn, autoLoop: false),
      ),
    );
  }

  Widget _buildTimerCard(double progress, int target) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line, width: 1.2)),
        child: Column(
          children: [
            const Overline('টাইমার ও অগ্রগতি', padding: EdgeInsets.only(bottom: 20)),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 200, height: 200,
                  child: CircularProgressIndicator(value: progress, strokeWidth: 12, color: AppColors.svcHero, backgroundColor: AppColors.surfaceHigh),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_fmt(_totalSeconds), style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: AppColors.ink, letterSpacing: -1)),
                    Text('লক্ষ্য ${_fmt(target)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.smoke)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 32),
            GestureDetector(
              onTap: _toggleTimer,
              child: AnimatedContainer(
                duration: AppMotion.short,
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: _completed ? AppColors.mint : AppColors.ink,
                  borderRadius: BorderRadius.zero,
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 15, offset: const Offset(0, 8))],
                ),
                child: Icon(_completed ? Icons.check_rounded : (_running ? Icons.pause_rounded : Icons.play_arrow_rounded), color: Colors.white, size: 36),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid(Workout w) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(child: _buildStatItem('সেট/রিপিট', w.setsRepsLabel ?? '—', Icons.fitness_center_rounded, AppColors.amber)),
          const SizedBox(width: 12),
          Expanded(child: _buildStatItem('সময়', '${w.durationMin} মি', Icons.timer_outlined, const Color(0xFF0EA5E9))),
          const SizedBox(width: 12),
          Expanded(child: _buildStatItem('ক্যালরি', '${w.targetCaloriesKcal}', Icons.local_fire_department_outlined, AppColors.rose)),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line)),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.ink)),
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.smoke)),
        ],
      ),
    );
  }

  Widget _buildContentBox(String title, String content, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppColors.svcHero),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.newsInk)),
              ],
            ),
            const SizedBox(height: 12),
            Text(content, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink, height: 1.4)),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionsBox(List<String> steps) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [Icon(Icons.list_rounded, size: 18, color: AppColors.svcHero), SizedBox(width: 8), Text('ধাপে ধাপে', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900))]),
            const SizedBox(height: 16),
            ...steps.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${e.key + 1}. ', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.svcHero)),
                  Expanded(child: Text(e.value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.4))),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildEquipmentBox(List<String> items) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [Icon(Icons.construction_rounded, size: 18, color: AppColors.svcHero), SizedBox(width: 8), Text('প্রয়োজনীয় যন্ত্রপাতি', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900))]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: items.map((i) => Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: AppColors.svcCategoryBg, borderRadius: BorderRadius.zero), child: Text(i, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.svcHero)))).toList()),
          ],
        ),
      ),
    );
  }
}
