/// "পানি" screen — diabetic-friendly daily hydration tracker.
/// 
/// Designed for an elderly user:
///   • Big, single-purpose tap-and-hold glass in the centre.
///   • Time-of-day buckets (সকাল / দুপুর / বিকেল / রাত) make the
///     "morning 1 glass, afternoon 2 glass" guidance crystal clear.
///   • Glass-fills animation runs while the user holds the glass; once
///     the fill crosses the threshold we commit `+0.25 L` server-side
///     and reset for the next tap.
///   • Bangla labels with explicit units (L / গ্লাস) so the number is
///     unambiguous even when eyesight is weak.
///   • No reliance on the rest of the app: a one-off tap on the bottom
///     sheet also commits water (mirrors the existing `addWaterLiters`
///     pattern used on the dashboard) so nothing is lost if the user
///     enters water from anywhere in the app.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/workout.dart' show DailyMetric;
import '../services/app_events.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';

/// One segment of the day — used both for the bucket chips at the top
/// and the breakdown rows lower down.
enum _Bucket { morning, noon, afternoon, night }

extension on _Bucket {
  /// Bengali label printed on the bucket card.
  String get bn {
    switch (this) {
      case _Bucket.morning:
        return 'সকাল';
      case _Bucket.noon:
        return 'দুপুর';
      case _Bucket.afternoon:
        return 'বিকেল';
      case _Bucket.night:
        return 'রাত';
    }
  }

  /// Short slot (e.g. for the breakdown "06:00"). Reserved for the
  /// row label; kept here so the bucket model stays self-contained
  /// even though the chip currently uses [bn].
  // ignore: unused_element
  String get slot {
    switch (this) {
      case _Bucket.morning:
        return '০৬:০০ – ১১:০০';
      case _Bucket.noon:
        return '১১:০০ – ১৫:০০';
      case _Bucket.afternoon:
        return '১৫:০০ – ১৯:০০';
      case _Bucket.night:
        return '১৯:০০ – রাত';
    }
  }

  /// Hint text shown beside the bucket chip.
  String get hint {
    switch (this) {
      case _Bucket.morning:
        return 'ঘুম থেকে উঠে ১ গ্লাস';
      case _Bucket.noon:
        return 'দুপুরের খাবারের সাথে';
      case _Bucket.afternoon:
        return 'বিকেলে ২ গ্লাস';
      case _Bucket.night:
        return 'ঘুমের ১ ঘণ্টা আগে';
    }
  }

  /// Recommended glass count for a diabetic patient in this slot.
  int get recommendation {
    switch (this) {
      case _Bucket.morning:
        return 1;
      case _Bucket.noon:
        return 1;
      case _Bucket.afternoon:
        return 2;
      case _Bucket.night:
        return 1;
    }
  }
}

/// State passed into the dashboard entry card so we don't have to
/// duplicate the daily-target maths in `dashboard_screen.dart`.
class WaterTodaySnapshot {
  final double liters;
  final double targetLiters;
  const WaterTodaySnapshot({
    required this.liters,
    required this.targetLiters,
  });

  int get glassesDrank => (liters / 0.25).round();
  int get glassesTarget => (targetLiters / 0.25).round();

  double get progress {
    if (targetLiters <= 0) return 0;
    return (liters / targetLiters).clamp(0.0, 1.0);
  }

  /// Fallback snapshot when the RPC failed or the user has no row yet.
  static const empty = WaterTodaySnapshot(
    liters: 0,
    targetLiters: 2.5,
  );
}

class WaterScreen extends StatefulWidget {
  const WaterScreen({super.key, this.initialMetric});

  /// Optional pre-loaded metric — used by the dashboard to avoid an
  /// extra round-trip when the user taps straight in from the card.
  final DailyMetric? initialMetric;

  @override
  State<WaterScreen> createState() => _WaterScreenState();
}

class _WaterScreenState extends State<WaterScreen>
    with TickerProviderStateMixin {
  // ── State ────────────────────────────────────────────────────────────────
  double _liters = 0;
  bool _loading = true;
  String? _error;
  _Bucket _activeBucket = _bucketForNow();

  // Fill progress from 0.0 (empty) to 1.0 (full) during a long-press.
  double _fillProgress = 0;
  bool _holding = false;
  bool _committing = false; // re-entrancy guard around the RPC call.

  // Animation controllers: one for the long-press fill ramp, one for
  // the always-on wave motion inside the glass.
  late final AnimationController _fillCtl;
  late final AnimationController _waveCtl;

  /// Daily target for a diabetic patient (2.5 L ≈ 8 glasses of ~300 ml
  /// each). Anchored on the conservative end so the goal feels
  /// reachable without setting the user up to fail.
  static const double _targetLiters = 2.5;

  @override
  void initState() {
    super.initState();
    _fillCtl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..addListener(() {
        if (mounted) setState(() => _fillProgress = _fillCtl.value);
      });
    _waveCtl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _activeBucket = _bucketForNow();

    final seed = widget.initialMetric;
    if (seed != null) {
      _liters = seed.waterLiters;
    }
    debugPrint('💧 [WaterScreen] initState seed.waterLiters='
        '${seed?.waterLiters} → _liters=$_liters');
    _load();
    AppEvents.waterChanged.addListener(_onWaterChangedExternal);
    debugPrint('💧 [WaterScreen] initState done — listener registered');
  }

  @override
  void dispose() {
    _fillCtl.dispose();
    _waveCtl.dispose();
    AppEvents.waterChanged.removeListener(_onWaterChangedExternal);
    super.dispose();
  }

  /// Re-fetch on cross-screen log events. The local commit guard
  /// (`_committing`) suppresses this listener so the server's mid-flight
  /// read cannot clobber the in-progress commit.
  void _onWaterChangedExternal() {
    debugPrint('💧 [WaterScreen] _onWaterChangedExternal fired — '
        'committing=$_committing');
    if (!mounted) return;
    if (_committing) return;
    _load(silent: true);
  }

  // ── Data loading ────────────────────────────────────────────────────────
  Future<void> _load({bool silent = false}) async {
    debugPrint('💧 [WaterScreen] _load(silent=$silent) start '
        '(current _liters=$_liters)');
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final m = await SupabaseService.getTodayDailyMetrics();
      if (!mounted) return;
      debugPrint('💧 [WaterScreen] _load got $m → '
          'setting _liters from $_liters to ${m.waterLiters}');
      setState(() {
        _liters = m.waterLiters;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('💧 [WaterScreen] _load EXCEPTION: $e');
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// Map the current time-of-day to one of the four buckets.
  static _Bucket _bucketForNow([DateTime? at]) {
    final h = (at ?? DateTime.now()).hour;
    if (h >= 5 && h < 11) return _Bucket.morning;
    if (h >= 11 && h < 15) return _Bucket.noon;
    if (h >= 15 && h < 19) return _Bucket.afternoon;
    return _Bucket.night;
  }

  // ── Tap-and-hold to fill ───────────────────────────────────────────────
  // The user holds the glass; fill ramps linearly from 0→1 over 1.2 s;
  // on release we commit `+0.25 L` if fill > 0.6 (i.e. the user let
  // the glass actually fill up). Otherwise we discard the gesture —
  // accidental brushes don't pollute the intake log.
  void _onHoldStart() {
    if (_holding || _loading || _committing) return;
    setState(() => _holding = true);
    HapticFeedback.lightImpact();
    _fillCtl.forward(from: 0);
  }

  void _onHoldEnd() {
    if (!_holding) return;
    _holding = false;
    _fillCtl.stop();
    final committed = _fillCtl.value >= 0.6;
    // Animate back to empty (or zero) regardless — every reset uses
    // the same curve so the next gesture is predictable.
    if (committed) {
      // First, briefly flash to full so the commit "lands" visually,
      // then drain with a CustomTween-style reverse animation.
      Future<void>.microtask(() async {
        if (!mounted) return;
        await _fillCtl.animateTo(
          1,
          duration: const Duration(milliseconds: 140),
          curve: AppMotion.emphasized,
        );
        await _commitGlass();
        if (!mounted) return;
        await _fillCtl.animateTo(
          0,
          duration: const Duration(milliseconds: 360),
          curve: AppMotion.decelerate,
        );
      });
    } else {
      _fillCtl.animateTo(0,
          duration: const Duration(milliseconds: 280),
          curve: AppMotion.decelerate);
    }
  }

  void _onHoldCancel() {
    if (!_holding) return;
    _holding = false;
    _fillCtl.stop();
    _fillCtl.animateTo(0,
        duration: const Duration(milliseconds: 240),
        curve: AppMotion.decelerate);
  }

  /// Log one glass (+0.25 L) to Supabase. Optimistically bumps the UI,
  /// trusts the row returned by the server as the new source of truth,
  /// and reverts + shows a snackbar only if the network call throws.
  Future<void> _commitGlass() async {
    if (_committing) return;
    _committing = true;

    const delta = 0.25;
    final previous = _liters;
    final optimisticValue = math.min(_liters + delta, 20.0);
    setState(() => _liters = optimisticValue);
    HapticFeedback.mediumImpact();
    debugPrint('💧 [WaterScreen] _commitGlass START previous=$previous '
        'optimistic=$optimisticValue delta=$delta');

    try {
      final updated = await SupabaseService.addWaterLiters(delta);
      if (!mounted) return;
      debugPrint('💧 [WaterScreen] _commitGlass RPC returned '
          'updated.waterLiters=${updated.waterLiters} '
          '(optimistic was $optimisticValue)');
      // Trust the server's authoritative value (it also clamps 0..20).
      setState(() => _liters = updated.waterLiters);
      AppEvents.notifyWaterChanged();
      debugPrint('💧 [WaterScreen] _commitGlass DONE — _liters now '
          '$_liters, notifyWaterChanged fired');
    } catch (e) {
      if (!mounted) return;
      debugPrint('💧 [WaterScreen] _commitGlass EXCEPTION: $e — '
          'rolling back to previous=$previous');
      // Roll back the optimistic bump so the UI matches the server.
      setState(() => _liters = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(
            'সংযোগ বিচ্ছিন্ন হয়েছে — অনুগ্রহ করে আবার চেষ্টা করুন। ($e)',
          ),
        ),
      );
    } finally {
      _committing = false;
    }
  }

  /// Manual undo: drop the most recent +0.25 L if the bucket genuinely
  /// over-counted. Uses the absolute setter so the server stays
  /// the source of truth.
  Future<void> _removeLastGlass() async {
    if (_committing || _liters <= 0) return;
    _committing = true;

    final previous = _liters;
    final double target = math.max(0.0, _liters - 0.25);
    setState(() => _liters = target);
    HapticFeedback.selectionClick();
    debugPrint('💧 [WaterScreen] _removeLastGlass START previous=$previous '
        'target=$target');

    try {
      final m = await SupabaseService.setWaterLiters(target);
      if (!mounted) return;
      debugPrint('💧 [WaterScreen] _removeLastGlass RPC returned '
          'm.waterLiters=${m.waterLiters} (target was $target)');
      setState(() => _liters = m.waterLiters);
      AppEvents.notifyWaterChanged();
      debugPrint('💧 [WaterScreen] _removeLastGlass DONE — _liters now '
          '$_liters, notifyWaterChanged fired');
    } catch (e) {
      if (!mounted) return;
      debugPrint('💧 [WaterScreen] _removeLastGlass EXCEPTION: $e — '
          'rolling back to previous=$previous');
      setState(() => _liters = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text('বাতিল করা যায়নি — আবার চেষ্টা করুন। ($e)'),
        ),
      );
    } finally {
      _committing = false;
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.newsCanvas,
      body: SafeArea(
        child: _loading
            ? const Center(child: LoadingMark())
            : _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final glassesTarget = (_targetLiters / 0.25).round();
    final glassesDrank = (_liters / 0.25).round();

    return RefreshIndicator(
      color: AppColors.newsInk,
      backgroundColor: AppColors.newsSurface,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          const _Header(),
          const SizedBox(height: 18),
          // Hero: big tappable glass with progress ring + glass-fill.
          _HeroPanel(
            liters: _liters,
            targetLiters: _targetLiters,
            glassesDrank: glassesDrank,
            glassesTarget: glassesTarget,
            fillProgress: _fillProgress,
            holding: _holding,
            waveCtl: _waveCtl,
            onHoldStart: _onHoldStart,
            onHoldEnd: _onHoldEnd,
            onHoldCancel: _onHoldCancel,
          ),
          const SizedBox(height: 20),
          // Time-of-day bucket guide.
          _BucketGuide(
            activeBucket: _activeBucket,
            glassesDrank: glassesDrank,
            glassesTarget: glassesTarget,
            litersPerBucket: _litersPerBucket(),
            onTapBucket: (b) => setState(() => _activeBucket = b),
          ),
          const SizedBox(height: 20),
          _QuickActions(
            onUndo: _removeLastGlass,
            canUndo: _liters >= 0.25,
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            _ErrorBanner(error: _error!),
          ],
          const SizedBox(height: 24),
          _TipCard(),
        ],
      ),
    );
  }

  /// Distribute the current liters across the four buckets for the
  /// progress breakdown chart. We round each bucket to nearest 0.25 L
  /// and clamp the last bucket to whatever remains so the numbers add
  /// up exactly.
  List<double> _litersPerBucket() {
    final totalGlasses = (_liters / 0.25).round();
    final slots = [0, 0, 0, 0];
    var remaining = totalGlasses;
    for (var i = 0; i < 4 && remaining > 0; i++) {
      final cap = _Bucket.values[i].recommendation;
      final take = math.min(cap, remaining);
      slots[i] = take;
      remaining -= take;
    }
    // Any leftover (user drank more than the 5-glass guide) gets
    // dumped into the "afternoon" bucket — it's the biggest slot.
    slots[_Bucket.afternoon.index] += remaining;
    return slots.map((g) => g * 0.25).toList();
  }
}

// ───────────────────────────── Header ──────────────────────────────

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 6, 14, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _LogoMark(size: 38),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'পানি',
                  style: TextStyle(
                    color: AppColors.newsInk,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                    height: 1.0,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'আজকের হাইড্রেশন ট্র্যাকার',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.newsMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  final double size;
  const _LogoMark({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brandPink, AppColors.brandPinkDeep],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandPinkDeep.withValues(alpha: 0.28),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.water_drop_rounded,
        size: size * 0.55,
        color: Colors.white,
      ),
    );
  }
}

// ───────────────────────────── Hero panel ──────────────────────────

class _HeroPanel extends StatelessWidget {
  final double liters;
  final double targetLiters;
  final int glassesDrank;
  final int glassesTarget;
  final double fillProgress;
  final bool holding;
  final AnimationController waveCtl;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final VoidCallback onHoldCancel;

  const _HeroPanel({
    required this.liters,
    required this.targetLiters,
    required this.glassesDrank,
    required this.glassesTarget,
    required this.fillProgress,
    required this.holding,
    required this.waveCtl,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.onHoldCancel,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (liters / targetLiters * 100).clamp(0.0, 100.0).round();
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
      decoration: BoxDecoration(
        color: AppColors.newsSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.newsDivider, width: 1),
        boxShadow: AppGlass.shadow(opacity: 0.05, blur: 18, y: 6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Top row: today / target big number + micro progress chip.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'আজ',
                    style: TextStyle(
                      color: AppColors.newsMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        color: AppColors.newsInk,
                        fontWeight: FontWeight.w900,
                        fontSize: 30,
                        letterSpacing: -0.6,
                        height: 1.0,
                      ),
                      children: [
                        TextSpan(text: liters.toStringAsFixed(2)),
                        const TextSpan(
                          text: ' L',
                          style: TextStyle(
                            fontSize: 18,
                            color: AppColors.newsMuted,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              _ProgressChip(
                pct: pct,
                drank: glassesDrank,
                target: glassesTarget,
              ),
            ],
          ),
          const SizedBox(height: 22),
          // Big tappable glass.
          _TapToFillGlass(
            fillProgress: fillProgress,
            ambientFill: targetLiters <= 0
                ? 0.0
                : (liters / targetLiters).clamp(0.0, 1.0),
            waveCtl: waveCtl,
            onHoldStart: onHoldStart,
            onHoldEnd: onHoldEnd,
            onHoldCancel: onHoldCancel,
          ),
          const SizedBox(height: 18),
          Text(
            holding
                ? 'ধরে রাখুন… গ্লাস ভরছে'
                : 'গ্লাসে চেপে ধরে পানি যোগ করুন',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: holding
                  ? AppColors.brandPinkDeep
                  : AppColors.newsMuted,
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressChip extends StatelessWidget {
  final int pct;
  final int drank;
  final int target;
  const _ProgressChip({
    required this.pct,
    required this.drank,
    required this.target,
  });

  @override
  Widget build(BuildContext context) {
    final done = pct >= 100;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: done
            ? AppColors.newsAccent.withValues(alpha: 0.10)
            : AppColors.newsSurfaceSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: done
              ? AppColors.newsAccent.withValues(alpha: 0.35)
              : AppColors.newsDivider,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? Icons.check_rounded : Icons.local_drink_rounded,
            size: 14,
            color: done ? AppColors.newsAccent : AppColors.newsInk,
          ),
          const SizedBox(width: 6),
          Text(
            '$drank/$target গ্লাস  •  $pct%',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.1,
              color: done ? AppColors.newsAccent : AppColors.newsInk,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────── Tap-to-fill glass ─────────────────────────

class _TapToFillGlass extends StatelessWidget {
  final double fillProgress;
  final double ambientFill;
  final AnimationController waveCtl;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final VoidCallback onHoldCancel;

  const _TapToFillGlass({
    required this.fillProgress,
    required this.ambientFill,
    required this.waveCtl,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.onHoldCancel,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // A 1:1.5 portrait glass that fills the available width but
        // caps at 280 dp so it doesn't dwarf the screen on tablets.
        final dim = math.min(constraints.maxWidth, 280.0);
        return Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPressStart: (_) => onHoldStart(),
            onLongPressEnd: (_) => onHoldEnd(),
            onLongPressCancel: onHoldCancel,
            onTapDown: (_) => onHoldStart(),
            onTapUp: (_) => onHoldEnd(),
            onTapCancel: onHoldCancel,
            child: SizedBox(
              width: dim,
              height: dim * 1.45,
              child: CustomPaint(
                painter: _GlassPainter(
                  fillProgress: fillProgress,
                  wave: waveCtl,
                  // The "ambient" fill reflects the day's actual
                  // progress so the glass is informative at rest.
                  ambientFill: ambientFill,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Draws a tulip-shaped drinking glass with a curved, animated water
/// surface. The "ambient" water level (today's % consumed) is layered
/// beneath the long-press `fillProgress` so a successful commit raises
/// the resting level by one glass.
class _GlassPainter extends CustomPainter {
  final double fillProgress;
  final AnimationController wave;
  final double ambientFill;
  Size? _lastSize;

  _GlassPainter({
    required this.fillProgress,
    required this.wave,
    required this.ambientFill,
  }) : super(repaint: wave);

  @override
  void paint(Canvas canvas, Size size) {
    _lastSize = size;
    final w = size.width;
    final h = size.height;

    // ── Glass silhouette (tulip outline) ───────────────────────────────
    final outline = Path()
      ..moveTo(w * 0.10, h * 0.06)
      ..lineTo(w * 0.18, h * 0.96)
      ..quadraticBezierTo(w * 0.50, h * 1.02, w * 0.82, h * 0.96)
      ..lineTo(w * 0.90, h * 0.06)
      ..quadraticBezierTo(w * 0.50, h * 0.00, w * 0.10, h * 0.06)
      ..close();

    final rim = Rect.fromLTWH(0, 0, w, h * 0.10);

    // Glass body fill — almost-white with a hint of warmth so the
    // outline reads on the cream canvas.
    final glassFill = Paint()
      ..color = const Color(0xFFF8FAFC)
      ..style = PaintingStyle.fill;
    canvas.drawPath(outline, glassFill);

    // Subtle inner highlight on the left edge — gives the glass a
    // physical "thickness" cue without resorting to a real blur.
    final hl = Paint()
      ..color = Colors.white
      ..strokeWidth = w * 0.045
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.save();
    canvas.clipPath(outline);
    canvas.drawLine(
      Offset(w * 0.22, h * 0.10),
      Offset(w * 0.28, h * 0.82),
      hl,
    );

    // ── Ambient (committed) water ──────────────────────────────────────
    // Sit between 6% (true zero visually) and 88% (the top lip is
    // always visible). The actual progress is encoded in ambientFill
    // but we only render it when the user isn't actively holding.
    final ambientLevel = h * (0.06 + ambientFill * 0.82);
    final ambient = _wavePath(w, ambientLevel, phase: wave.value, amp: h * 0.012);
    final ambientPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFBFE3F2), Color(0xFF7FB8D6)],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;
    canvas.drawPath(ambient, ambientPaint);

    // ── Long-press fill (overlaid) ─────────────────────────────────────
    if (fillProgress > 0.0001) {
      final holdLevel =
          h * (1 - fillProgress.clamp(0.0, 1.0) * 0.92);
      final hold = _wavePath(
        w,
        holdLevel,
        phase: wave.value * 1.4,
        amp: h * 0.018 * (0.4 + fillProgress * 0.8),
      );
      final holdPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF7DD3FC), Color(0xFF0EA5E9)],
        ).createShader(Rect.fromLTWH(0, 0, w, h))
        ..style = PaintingStyle.fill;
      canvas.drawPath(hold, holdPaint);
    }

    canvas.restore();

    // ── Glass outline on top ───────────────────────────────────────────
    final outlinePaint = Paint()
      ..color = AppColors.newsInk.withValues(alpha: 0.78)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(outline, outlinePaint);

    // ── Rim ellipse ────────────────────────────────────────────────────
    final rimPaint = Paint()
      ..color = AppColors.newsInk.withValues(alpha: 0.55)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    canvas.drawOval(rim.deflate(rim.height * 0.3), rimPaint);

    // ── Measurement ticks (every 25%) ─────────────────────────────────
    final tickPaint = Paint()
      ..color = AppColors.newsInk.withValues(alpha: 0.10)
      ..strokeWidth = 1.0;
    for (var i = 1; i <= 3; i++) {
      final y = h * (0.10 + 0.18 * i);
      canvas.drawLine(Offset(w * 0.14, y), Offset(w * 0.22, y), tickPaint);
    }
  }

  Path _wavePath(double w, double level, {required double phase, required double amp}) {
    // Two overlapping sine waves give a more organic surface than a
    // single sine; clip to the outline happens outside this fn.
    final h = _lastSize?.height ?? 0;
    final p = Path()..moveTo(0, level);
    const steps = 36;
    for (var i = 0; i <= steps; i++) {
      final x = w * (i / steps);
      final t = i / steps * math.pi * 4 + phase * math.pi * 2;
      final dy = math.sin(t) * amp + math.sin(t * 1.7 + 1.3) * amp * 0.35;
      p.lineTo(x, level + dy);
    }
    p
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    return p;
  }

  @override
  bool shouldRepaint(covariant _GlassPainter old) =>
      old.fillProgress != fillProgress ||
      old.ambientFill != ambientFill ||
      old.wave != wave;
}

// ───────────────────────── Bucket guide ─────────────────────────────

class _BucketGuide extends StatelessWidget {
  final _Bucket activeBucket;
  final int glassesDrank;
  final int glassesTarget;
  final List<double> litersPerBucket;
  final ValueChanged<_Bucket> onTapBucket;

  const _BucketGuide({
    required this.activeBucket,
    required this.glassesDrank,
    required this.glassesTarget,
    required this.litersPerBucket,
    required this.onTapBucket,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.newsSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.newsDivider, width: 1),
        boxShadow: AppGlass.shadow(opacity: 0.04, blur: 14, y: 4),
      ),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'সময় অনুযায়ী গ্লাস',
              style: TextStyle(
                color: AppColors.newsInk,
                fontWeight: FontWeight.w900,
                fontSize: 15,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'দিনের ৪টি সময়ে মিলিয়ে ৮ গ্লাস পানি',
              style: TextStyle(
                color: AppColors.newsMuted,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < _Bucket.values.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == 3 ? 0 : 10),
              child: _BucketRow(
                bucket: _Bucket.values[i],
                glassesDrank: (litersPerBucket[i] / 0.25).round(),
                isActive: _Bucket.values[i] == activeBucket,
                onTap: () => onTapBucket(_Bucket.values[i]),
              ),
            ),
          const SizedBox(height: 14),
          _ProgressBar(
            drank: glassesDrank,
            target: glassesTarget,
          ),
        ],
      ),
    );
  }
}

class _BucketRow extends StatelessWidget {
  final _Bucket bucket;
  final int glassesDrank;
  final bool isActive;
  final VoidCallback onTap;
  const _BucketRow({
    required this.bucket,
    required this.glassesDrank,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final rec = bucket.recommendation;
    final done = glassesDrank >= rec;
    return Pressable(
      onTap: onTap,
      pressScale: 0.985,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.brandPink.withValues(alpha: 0.08)
              : AppColors.newsSurfaceSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive
                ? AppColors.brandPink.withValues(alpha: 0.45)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Tiny time-slot chip
                Container(
                  width: 56,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.brandPink
                        : AppColors.newsInk,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    bucket.bn,
                    style: TextStyle(
                      color: isActive
                          ? AppColors.newsInk
                          : Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    bucket.hint,
                    style: const TextStyle(
                      color: AppColors.newsInk,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                Text(
                  '$glassesDrank/$rec গ্লাস',
                  style: TextStyle(
                    color: done
                        ? AppColors.newsAccent
                        : AppColors.newsMuted,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  done
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  color: done ? AppColors.newsAccent : AppColors.newsMuted,
                  size: 16,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Per-bucket progress.
            _MiniProgress(
              drank: glassesDrank,
              target: rec,
              active: isActive,
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniProgress extends StatelessWidget {
  final int drank;
  final int target;
  final bool active;
  const _MiniProgress({
    required this.drank,
    required this.target,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final pct = target == 0 ? 0.0 : (drank / target).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 6,
        child: Stack(
          children: [
            Container(color: AppColors.newsDivider),
            FractionallySizedBox(
              widthFactor: pct,
              child: Container(
                decoration: BoxDecoration(
                  gradient: active
                      ? const LinearGradient(
                          colors: [
                            AppColors.brandPink,
                            AppColors.brandPinkDeep,
                          ],
                        )
                      : const LinearGradient(
                          colors: [
                            AppColors.newsInk,
                            AppColors.newsInk,
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final int drank;
  final int target;
  const _ProgressBar({required this.drank, required this.target});

  @override
  Widget build(BuildContext context) {
    final pct = target == 0 ? 0.0 : (drank / target).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'দিনের লক্ষ্য',
              style: TextStyle(
                color: AppColors.newsMuted,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const Spacer(),
            Text(
              '$drank / $target গ্লাস',
              style: const TextStyle(
                color: AppColors.newsInk,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 8,
            child: Stack(
              children: [
                Container(color: AppColors.newsDivider),
                FractionallySizedBox(
                  widthFactor: pct,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.newsInk,
                          Color(0xFF2D2E40),
                        ],
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
}

// ───────────────────────── Quick actions ───────────────────────────

class _QuickActions extends StatelessWidget {
  final VoidCallback onUndo;
  final bool canUndo;
  const _QuickActions({required this.onUndo, required this.canUndo});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Pressable(
            onTap: canUndo ? onUndo : null,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.newsSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: canUndo
                      ? AppColors.newsInk.withValues(alpha: 0.85)
                      : AppColors.newsDivider,
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.undo_rounded,
                    size: 18,
                    color: canUndo
                        ? AppColors.newsInk
                        : AppColors.newsMuted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'শেষ গ্লাস বাতিল',
                    style: TextStyle(
                      color: canUndo
                          ? AppColors.newsInk
                          : AppColors.newsMuted,
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────── Tip card ─────────────────────────────

class _TipCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.newsAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.newsAccent.withValues(alpha: 0.20),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.newsAccent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.tips_and_updates_rounded,
              size: 18,
              color: AppColors.newsAccent,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'বিশেষজ্ঞ পরামর্শ',
                  style: TextStyle(
                    color: AppColors.newsInk,
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'গরমকালে প্রতিদিন ১০–১২ গ্লাস এবং শীতকালে ৬–৮ গ্লাস '
                  'পানি পান করুন। ডায়াবেটিক রোগীদের জন্য খাবারের ৩০ মিনিট '
                  'আগে এক গ্লাস পানি রক্তে শর্করা নিয়ন্ত্রণে সাহায্য করে।',
                  style: TextStyle(
                    color: AppColors.newsInk,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String error;
  const _ErrorBanner({required this.error});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCA5A5), width: 1),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.rose,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.rose,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
