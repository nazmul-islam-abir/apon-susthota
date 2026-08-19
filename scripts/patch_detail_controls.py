# -*- coding: utf-8 -*-
"""
Update workout_details_screen.dart _buildControls to:
  • Surface the partial-save guarantee (আংশিক সময়ও সেভ হয়).
  • Show a tiny inline progress indicator (N% সেভ হয়েছে) under the
    button when the user has worked out some but not all of the target.
  • Keep button label + behaviour unchanged.
"""
import io

path = r'c:\Users\Nazmul\StudioProjects\diabetics_meal-main\lib\screens\workout_details_screen.dart'

with io.open(path, 'r', encoding='utf-8') as f:
    src = f.read()

old = u"""  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        children: [
          // No outer SizedBox — MonoButton owns its 62dp height internally;
          // wrapping it in a smaller box was clipping the Bangla label.
          MonoButton(
            label: _completed ? 'সম্পন্ন হয়েছে' : 'সম্পন্ন করুন',
            leading: _completed
                ? Icons.check_circle_rounded
                : Icons.check_rounded,
            variant: MonoButtonVariant.primary,
            onPressed: _completed ? null : _markCompleted,
          ),
          const SizedBox(height: 10),
          const Text(
            'পজ করলে সময় স্বয়ংক্রিয়ভাবে সেভ হয়। সেভ বোতাম লাগবে না।',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.smoke,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }"""

new = u"""  Widget _buildControls() {
    final target = widget.assignment.workout.targetMinutes * 60;
    final pct = target <= 0
        ? 0.0
        : (_baseSeconds / target).clamp(0.0, 1.0);
    final pctLabel =
        '${(pct * 100).round()}% সম্পন্ন হয়েছে';
    final showPartial = !_completed && pct > 0.001;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        children: [
          // No outer SizedBox — MonoButton owns its 62dp height internally;
          // wrapping it in a smaller box was clipping the Bangla label.
          MonoButton(
            label: _completed ? 'সম্পন্ন হয়েছে' : 'সম্পন্ন করুন',
            leading: _completed
                ? Icons.check_circle_rounded
                : Icons.check_rounded,
            variant: MonoButtonVariant.primary,
            onPressed: _completed ? null : _markCompleted,
          ),
          const SizedBox(height: 10),
          if (showPartial) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.cyan,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  pctLabel,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          const Text(
            'আংশিক সময়ও সেভ হয় — পজ করলেই নিজে থেকে সংরক্ষিত হয়।',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.smoke,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }"""

assert old in src, 'detail-screen _buildControls block not found'
src = src.replace(old, new, 1)

with io.open(path, 'w', encoding='utf-8') as f:
    f.write(src)
print('OK: detail-screen controls updated')