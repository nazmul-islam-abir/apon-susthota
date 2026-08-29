/// "পানি" screen — professional technical hydration tracker.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/workout.dart' show DailyMetric;
import '../services/app_events.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/back_scaffold.dart';
import '../widgets/mono_widgets.dart';

enum _Bucket { morning, noon, afternoon, night }

extension on _Bucket {
  String get bn {
    switch (this) {
      case _Bucket.morning: return 'সকাল';
      case _Bucket.noon: return 'দুপুর';
      case _Bucket.afternoon: return 'বিকেল';
      case _Bucket.night: return 'রাত';
    }
  }

  String get hint {
    switch (this) {
      case _Bucket.morning: return 'ঘুম থেকে উঠে ১ গ্লাস';
      case _Bucket.noon: return 'দুপুরের খাবারের সাথে';
      case _Bucket.afternoon: return 'বিকেলে ২ গ্লাস';
      case _Bucket.night: return 'ঘুমের ১ ঘণ্টা আগে';
    }
  }

  int get recommendation {
    switch (this) {
      case _Bucket.morning: return 1;
      case _Bucket.noon: return 1;
      case _Bucket.afternoon: return 2;
      case _Bucket.night: return 1;
    }
  }
}

class WaterScreen extends StatefulWidget {
  const WaterScreen({super.key, this.initialMetric});
  final DailyMetric? initialMetric;

  @override
  State<WaterScreen> createState() => _WaterScreenState();
}

class _WaterScreenState extends State<WaterScreen> with TickerProviderStateMixin {
  double _liters = 0;
  bool _loading = true;
  String? _error;
  _Bucket _activeBucket = _Bucket.morning;
  double _fillProgress = 0;
  bool _holding = false;
  bool _committing = false;

  late final AnimationController _fillCtl;
  late final AnimationController _waveCtl;
  static const double _targetLiters = 2.5;

  @override
  void initState() {
    super.initState();
    _fillCtl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..addListener(() { if (mounted) setState(() => _fillProgress = _fillCtl.value); });
    _waveCtl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    
    final seed = widget.initialMetric;
    if (seed != null) _liters = seed.waterLiters;
    _load();
    AppEvents.waterChanged.addListener(_onWaterChangedExternal);
  }

  @override
  void dispose() {
    _fillCtl.dispose();
    _waveCtl.dispose();
    AppEvents.waterChanged.removeListener(_onWaterChangedExternal);
    super.dispose();
  }

  void _onWaterChangedExternal() {
    if (!mounted || _committing) return;
    _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      final m = await SupabaseService.getTodayDailyMetrics();
      if (!mounted) return;
      setState(() { _liters = m.waterLiters; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

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
    if (_fillCtl.value >= 0.6) {
      Future<void>.microtask(() async {
        if (!mounted) return;
        await _fillCtl.animateTo(1, duration: const Duration(milliseconds: 140), curve: AppMotion.emphasized);
        await _commitGlass();
        if (!mounted) return;
        await _fillCtl.animateTo(0, duration: const Duration(milliseconds: 360), curve: AppMotion.decelerate);
      });
    } else {
      _fillCtl.animateTo(0, duration: const Duration(milliseconds: 280), curve: AppMotion.decelerate);
    }
  }

  Future<void> _commitGlass() async {
    if (_committing) return;
    _committing = true;
    final previous = _liters;
    setState(() => _liters = math.min(_liters + 0.25, 10.0));
    HapticFeedback.mediumImpact();
    try {
      await SupabaseService.logWaterEvent(0.25);
      final m = await SupabaseService.getTodayDailyMetrics();
      if (mounted) setState(() => _liters = m.waterLiters);
      AppEvents.notifyWaterChanged();
    } catch (_) {
      if (mounted) setState(() => _liters = previous);
    } finally { _committing = false; }
  }

  Future<void> _removeLastGlass() async {
    if (_committing || _liters <= 0) return;
    _committing = true;
    final previous = _liters;
    setState(() => _liters = math.max(0.0, _liters - 0.25));
    try {
      final m = await SupabaseService.setWaterLiters(_liters);
      if (mounted) setState(() => _liters = m.waterLiters);
      AppEvents.notifyWaterChanged();
    } catch (_) {
      if (mounted) setState(() => _liters = previous);
    } finally { _committing = false; }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.svcCategoryBg,
      body: BackScaffold(
        title: 'পানি ট্র্যাকার',
        body: SafeArea(
          top: false,
          child: _loading ? const Center(child: LoadingMark()) : _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final drank = (_liters / 0.25).round();
    final target = (_targetLiters / 0.25).round();

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.svcHero,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: [
          _buildHero(drank, target),
          const SizedBox(height: 24),
          _buildBucketGuide(drank),
          const SizedBox(height: 24),
          _buildActionRow(),
          const SizedBox(height: 24),
          _buildTipCard(),
        ],
      ),
    );
  }

  Widget _buildHero(int drank, int target) {
    final pct = (_liters / _targetLiters).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.line, width: 1.2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12)],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('আজকের গ্রহণ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.smoke)),
                  const SizedBox(height: 4),
                  Text('${_liters.toStringAsFixed(2)} L', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.ink)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: AppColors.svcHero.withValues(alpha: 0.1), borderRadius: BorderRadius.zero),
                child: Text('$drank / $target গ্লাস', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.svcHero)),
              ),
            ],
          ),
          const SizedBox(height: 32),
          _TapGlass(fill: pct, fillProgress: _fillProgress, wave: _waveCtl, onStart: _onHoldStart, onEnd: _onHoldEnd),
          const SizedBox(height: 24),
          Text(
            _holding ? 'গ্লাস ভরছে...' : 'গ্লাসে চেপে ধরে পানি যোগ করুন',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _holding ? AppColors.svcHero : AppColors.smoke),
          ),
        ],
      ),
    );
  }

  Widget _buildBucketGuide(int totalDrank) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('সময় অনুযায়ী গাইড', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          for (final b in _Bucket.values) _BucketRow(bucket: b, current: _calculateBucketDrank(b, totalDrank)),
        ],
      ),
    );
  }

  int _calculateBucketDrank(_Bucket b, int total) {
    var rem = total;
    for (final v in _Bucket.values) {
      final take = math.min(v.recommendation, rem);
      if (v == b) return take;
      rem -= take;
    }
    return 0;
  }

  Widget _buildActionRow() {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: _removeLastGlass,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line)),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.undo_rounded, size: 20, color: AppColors.rose),
                  SizedBox(width: 8),
                  Text('শেষ গ্লাস বাতিল', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.rose)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTipCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.svcHero.withValues(alpha: 0.08), borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.svcHero.withValues(alpha: 0.2))),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.tips_and_updates_rounded, color: AppColors.svcHero, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'ডায়াবেটিক রোগীদের জন্য খাবারের ৩০ মিনিট আগে এক গ্লাস পানি রক্তে শর্করা নিয়ন্ত্রণে সাহায্য করে।',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _TapGlass extends StatelessWidget {
  final double fill;
  final double fillProgress;
  final AnimationController wave;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  const _TapGlass({required this.fill, required this.fillProgress, required this.wave, required this.onStart, required this.onEnd});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => onStart(),
      onTapUp: (_) => onEnd(),
      onTapCancel: onEnd,
      child: SizedBox(
        width: 220, height: 320, // Increased size
        child: CustomPaint(painter: _GlassPainter(fill: fill, fillProgress: fillProgress, wave: wave)),
      ),
    );
  }
}

class _GlassPainter extends CustomPainter {
  final double fill;
  final double fillProgress;
  final AnimationController wave;
  _GlassPainter({required this.fill, required this.fillProgress, required this.wave}) : super(repaint: wave);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final glassPath = Path()
      ..moveTo(w * 0.1, 0)
      ..lineTo(w * 0.2, h)
      ..lineTo(w * 0.8, h)
      ..lineTo(w * 0.9, 0)
      ..close();

    canvas.drawPath(glassPath, Paint()..color = AppColors.surfaceHigh..style = PaintingStyle.fill);
    
    final level = h * (1 - fill);
    final waterPath = Path()
      ..moveTo(w * 0.15, level)
      ..lineTo(w * 0.2, h)
      ..lineTo(w * 0.8, h)
      ..lineTo(w * 0.85, level)
      ..close();
    
    canvas.drawPath(waterPath, Paint()..color = const Color(0xFF0EA5E9).withValues(alpha: 0.6)..style = PaintingStyle.fill);

    if (fillProgress > 0) {
      final holdLevel = h * (1 - fillProgress);
      final holdPath = Path()
        ..moveTo(w * 0.15, holdLevel)
        ..lineTo(w * 0.2, h)
        ..lineTo(w * 0.8, h)
        ..lineTo(w * 0.85, holdLevel)
        ..close();
      canvas.drawPath(holdPath, Paint()..color = const Color(0xFF0EA5E9)..style = PaintingStyle.fill);
    }

    canvas.drawPath(glassPath, Paint()..color = AppColors.svcHero..style = PaintingStyle.stroke..strokeWidth = 3);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _BucketRow extends StatelessWidget {
  final _Bucket bucket;
  final int current;
  const _BucketRow({required this.bucket, required this.current});

  @override
  Widget build(BuildContext context) {
    final done = current >= bucket.recommendation;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 60, padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(color: AppColors.svcCategoryBg, borderRadius: BorderRadius.zero),
            alignment: Alignment.center,
            child: Text(bucket.bn, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.svcHero)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(bucket.hint, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
          Text('$current / ${bucket.recommendation}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: done ? AppColors.svcHero : AppColors.smoke)),
          const SizedBox(width: 8),
          Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked, size: 18, color: done ? AppColors.svcHero : AppColors.lineStrong),
        ],
      ),
    );
  }
}
