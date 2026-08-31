/// "পানি" screen — professional technical hydration tracker redesigned (v2).
/// Matches the "Nexora" aesthetic with full-bleed hero and sharp corners.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/workout.dart' show DailyMetric;
import '../services/app_events.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';
import '../widgets/tab_history_mixin.dart';

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
  late DateTime _today;
  late DateTime _selectedDay;
  final ScrollController _stripController = ScrollController();
  
  static const int _windowSize = 15;
  static const int _todayIndex = 15;

  double _liters = 0;
  bool _loading = true;
  String? _error;
  double _fillProgress = 0;
  bool _holding = false;
  bool _committing = false;

  late final AnimationController _fillCtl;
  late final AnimationController _waveCtl;
  static const double _targetLiters = 2.5;

  @override
  void initState() {
    super.initState();
    _today = _midnight(DateTime.now());
    _selectedDay = _today;
    
    _fillCtl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..addListener(() { if (mounted) setState(() => _fillProgress = _fillCtl.value); });
    _waveCtl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    
    final seed = widget.initialMetric;
    if (seed != null) _liters = seed.waterLiters;
    _load();
    AppEvents.waterChanged.addListener(_onWaterChangedExternal);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollStripToIndex(_todayIndex, immediate: true));
  }

  @override
  void dispose() {
    _fillCtl.dispose();
    _waveCtl.dispose();
    _stripController.dispose();
    AppEvents.waterChanged.removeListener(_onWaterChangedExternal);
    super.dispose();
  }

  DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

  bool get _isToday => _midnight(_selectedDay).isAtSameMomentAs(_today);

  void _scrollStripToIndex(int index, {bool immediate = false}) {
    if (!_stripController.hasClients) return;
    const cellWidth = 50.0;
    const spacing = 8.0;
    const stride = cellWidth + spacing;
    final screenWidth = MediaQuery.of(context).size.width;
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
    if (_holding || _loading || _committing || !_isToday) return;
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

  void _handleBack() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      TabHistory.maybePop();
    }
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
                _buildHeroSliver(),
                const SliverToBoxAdapter(child: SizedBox(height: 22)),
                SliverToBoxAdapter(child: _buildSectionTitle('আজকের লক্ষ্য', 'হাইড্রেশন সূচক')),
                SliverToBoxAdapter(child: _buildDailyTargetCard()),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
                SliverToBoxAdapter(child: _buildSectionTitle('পানি পান করুন', 'চেপে ধরে গ্লাস ভরুন')),
                SliverToBoxAdapter(child: _buildInteractiveGlassCard()),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
                SliverToBoxAdapter(child: _buildSectionTitle('সময় অনুযায়ী গাইড', 'আপনার রুটিন')),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _BucketRow(bucket: _Bucket.values[i], current: _calculateBucketDrank(_Bucket.values[i], (_liters / 0.25).round())),
                      childCount: _Bucket.values.length,
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: _buildActionRow()),
                SliverToBoxAdapter(child: _buildTipCard()),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSliver() {
    const url = 'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/app/photo-1564352969906-8b7f46ba4b8b.avif?token=eyJraWQiOiJhZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJhcHAvcGhvdG8tMTU2NDM1Mjk2OTkwNi04YjdmNDZiYTRiOGIuYXZpZiIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODc4Njg2MjksImV4cCI6MTgxOTQwNDYyOX0.Jdl-6cqT6wHh_nv8j-7oD3zjU2KcoR4e5ohJVnZgTNs';
    final dateLabel = DateFormat('EEEE, d MMMM yyyy', 'bn').format(_selectedDay);

    return SliverToBoxAdapter(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.svcHero,
          image: const DecorationImage(image: NetworkImage(url), fit: BoxFit.cover, opacity: 0.7),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: Container(color: Colors.black.withValues(alpha: 0.35))),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 20, 0),
                    child: Row(
                      children: [
                        IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20), onPressed: _handleBack),
                        const Expanded(child: Text('পানি ট্র্যাকার', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5))),
                        _todayPill(),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dateLabel, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -0.6)),
                      const SizedBox(height: 6),
                      Text('পর্যাপ্ত পানি পান আপনার রক্তে শর্করা নিয়ন্ত্রণে সাহায্য করে', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _buildWeekStrip(),
                const SizedBox(height: 24),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekStrip() {
    final start = _today.subtract(const Duration(days: _windowSize));
    final days = List.generate(_windowSize * 2 + 1, (i) => start.add(Duration(days: i)));
    
    return Row(
      children: [
        _navArrow(icon: Icons.chevron_left, enabled: _selectedDay.isAfter(start), onTap: () {
          final next = _selectedDay.subtract(const Duration(days: 1));
          final index = next.difference(start).inDays;
          if (index >= 0) {
            setState(() => _selectedDay = next);
            _scrollStripToIndex(index);
          }
        }),
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
              itemBuilder: (_, i) {
                final d = days[i];
                final isSel = _midnight(d) == _midnight(_selectedDay);
                final isToday = _midnight(d) == _midnight(_today);
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedDay = _midnight(d));
                    _scrollStripToIndex(i);
                  },
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
              },
            ),
          ),
        ),
        _navArrow(icon: Icons.chevron_right, enabled: _selectedDay.isBefore(start.add(Duration(days: _windowSize * 2))), onTap: () {
          final next = _selectedDay.add(const Duration(days: 1));
          final index = next.difference(start).inDays;
          if (index <= _windowSize * 2) {
            setState(() => _selectedDay = next);
            _scrollStripToIndex(index);
          }
        }),
      ],
    );
  }

  Widget _navArrow({required IconData icon, required bool enabled, required VoidCallback onTap}) {
    return IconButton(onPressed: enabled ? onTap : null, icon: Icon(icon, color: enabled ? Colors.white : Colors.white24, size: 20));
  }

  Widget _todayPill() {
    final isToday = _midnight(_selectedDay) == _midnight(_today);
    return InkWell(
      onTap: () {
        setState(() => _selectedDay = _today);
        _scrollStripToIndex(_todayIndex);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: isToday ? AppColors.svcHeroAccent : Colors.white12, borderRadius: BorderRadius.zero, border: Border.all(color: Colors.white24)),
        child: Text('আজ', style: TextStyle(color: isToday ? AppColors.svcHero : Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
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

  Widget _buildDailyTargetCard() {
    final progress = (_liters / _targetLiters).clamp(0.0, 1.0);

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
                  const Text('পানির লক্ষ্যমাত্রা', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.smoke, letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  Text('${_liters.toStringAsFixed(2)} / $_targetLiters L', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.ink, letterSpacing: -0.5)),
                  const SizedBox(height: 12),
                  MonoBar(value: progress, height: 8, fill: Colors.blue),
                ],
              ),
            ),
            const SizedBox(width: 24),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(width: 64, height: 64, child: CircularProgressIndicator(value: progress, strokeWidth: 10, color: Colors.blue, backgroundColor: AppColors.surfaceHigh)),
                Text('${(progress * 100).round()}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.ink)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInteractiveGlassCard() {
    final pct = (_liters / _targetLiters).clamp(0.0, 1.0);
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: AppColors.line, width: 1.2),
        ),
        child: Column(
          children: [
            _TapGlass(
              fill: pct, 
              fillProgress: _fillProgress, 
              wave: _waveCtl, 
              onStart: _onHoldStart, 
              onEnd: _onHoldEnd,
              disabled: !_isToday,
            ),
            const SizedBox(height: 32),
            Text(
              !_isToday ? 'অতীতের ডেটা এডিট করা যাবে না' : (_holding ? 'গ্লাস ভরছে...' : 'গ্লাসে চেপে ধরে পানি যোগ করুন'),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _holding ? Colors.blue : AppColors.smoke),
            ),
          ],
        ),
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
    if (!_isToday) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: InkWell(
        onTap: _removeLastGlass,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.zero,
            border: Border.all(color: AppColors.rose, width: 1.4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.undo_rounded, color: AppColors.rose, size: 22),
              SizedBox(width: 8),
              Text('শেষ গ্লাস বাতিল করুন', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.rose, letterSpacing: 0.2)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTipCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppColors.svcCategoryBg, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.tips_and_updates_rounded, color: AppColors.svcHero, size: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'ডায়াবেটিক রোগীদের জন্য খাবারের ৩০ মিনিট আগে এক গ্লাস পানি রক্তে শর্করা নিয়ন্ত্রণে সাহায্য করে।',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink.withValues(alpha: 0.8), height: 1.4),
              ),
            ),
          ],
        ),
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
  final bool disabled;

  const _TapGlass({required this.fill, required this.fillProgress, required this.wave, required this.onStart, required this.onEnd, this.disabled = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: disabled ? null : (_) => onStart(),
      onTapUp: disabled ? null : (_) => onEnd(),
      onTapCancel: disabled ? null : onEnd,
      child: Opacity(
        opacity: disabled ? 0.5 : 1.0,
        child: SizedBox(
          width: 180, height: 260,
          child: CustomPaint(painter: _GlassPainter(fill: fill, fillProgress: fillProgress, wave: wave)),
        ),
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
    
    canvas.drawPath(waterPath, Paint()..color = const Color(0xFF0EA5E9).withValues(alpha: 0.5)..style = PaintingStyle.fill);

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

    canvas.drawPath(glassPath, Paint()..color = AppColors.lineStrong..style = PaintingStyle.stroke..strokeWidth = 2);
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
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: done ? AppColors.svcHero : AppColors.line, width: done ? 1.4 : 1.0),
        ),
        child: Row(
          children: [
            Container(
              width: 56, height: 44,
              decoration: BoxDecoration(color: AppColors.svcCategoryBg, borderRadius: BorderRadius.zero),
              alignment: Alignment.center,
              child: Text(bucket.bn, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.svcHero)),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(bucket.hint, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.ink))),
            const SizedBox(width: 10),
            Text('$current / ${bucket.recommendation}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: done ? AppColors.svcHero : AppColors.smoke)),
            const SizedBox(width: 8),
            Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked, size: 20, color: done ? AppColors.svcHero : AppColors.lineStrong),
          ],
        ),
      ),
    );
  }
}
