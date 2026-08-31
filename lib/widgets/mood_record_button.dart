/// A single tap-and-hold emoji button used by the mood banner.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

class MoodRecordButton extends StatefulWidget {
  final String emoji;
  final String kind;
  final ValueChanged<String> onRecorded;
  final Duration holdDuration;
  final double size;

  const MoodRecordButton({
    super.key,
    required this.emoji,
    required this.kind,
    required this.onRecorded,
    this.holdDuration = const Duration(milliseconds: 2000),
    this.size = 64,
  });

  @override
  State<MoodRecordButton> createState() => _MoodRecordButtonState();
}

class _MoodRecordButtonState extends State<MoodRecordButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;
  bool _holding = false;
  bool _recorded = false;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(vsync: this, duration: widget.holdDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _onComplete();
      });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _onDown(TapDownDetails _) {
    if (_holding) return;
    _holding = true;
    _recorded = false;
    HapticFeedback.lightImpact();
    _ctl.forward(from: 0);
  }

  void _onUp([_]) {
    if (!_holding) return;
    _holding = false;
    _ctl.stop();
    if (!_recorded) {
      _ctl.animateTo(0, duration: const Duration(milliseconds: 280), curve: Curves.decelerate);
    }
  }

  void _onComplete() {
    if (!_holding || _recorded) return;
    _recorded = true;
    _holding = false;
    HapticFeedback.mediumImpact();
    _ctl.value = 1.0;
    widget.onRecorded(widget.kind);
    Future<void>.microtask(() async {
      if (!mounted) return;
      await _ctl.animateTo(0, duration: const Duration(milliseconds: 360), curve: Curves.decelerate);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _onDown,
      onTapUp: _onUp,
      onTapCancel: () => _onUp(null),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _ctl,
          builder: (context, _) => Stack(
            alignment: Alignment.center,
            children: [
              // Premium emoji "puddle"
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: _holding ? 0.2 : 0.1),
                  borderRadius: BorderRadius.zero,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
                ),
              ),
              // Filling ring
              SizedBox(
                width: widget.size - 4,
                height: widget.size - 4,
                child: CircularProgressIndicator(
                  value: _ctl.value,
                  strokeWidth: 8,
                  valueColor: const AlwaysStoppedAnimation(AppColors.svcHeroAccent),
                  backgroundColor: Colors.transparent,
                ),
              ),
              // Emoji with subtle shadow
              Text(
                widget.emoji,
                style: TextStyle(
                  fontSize: widget.size * 0.5,
                  shadows: [
                    Shadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4)),
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
