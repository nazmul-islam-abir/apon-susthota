"""Insert _categoryIcon and _categoryGradient helpers before the
closing brace of _WorkoutDetailsScreenState (line 1096)."""
import sys

p = r'c:\Users\Nazmul\StudioProjects\diabetics_meal-main\lib\screens\workout_details_screen.dart'
with open(p, 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Verify the target line
target_idx = 1095  # 0-indexed for line 1096 which is `}`
assert lines[target_idx].strip() == '}', f'Expected `}}` at line 1096, got: {lines[target_idx]!r}'

helpers = '''
  // ── Category icon / gradient (mirrors workout_screen.dart) ──────────

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
            begin: Alignment.topLeft, end: Alignment.bottomRight);
      case WorkoutCategory.strength:
        return const LinearGradient(
            colors: [Color(0xFFFFF3E0), Color(0xFFFFCC80)],
            begin: Alignment.topLeft, end: Alignment.bottomRight);
      case WorkoutCategory.flexibility:
        return const LinearGradient(
            colors: [Color(0xFFE0F7FA), Color(0xFFA8E6F1)],
            begin: Alignment.topLeft, end: Alignment.bottomRight);
      case WorkoutCategory.balance:
        return const LinearGradient(
            colors: [Color(0xFFE8F5E9), Color(0xFFA5D6A7)],
            begin: Alignment.topLeft, end: Alignment.bottomRight);
      case WorkoutCategory.breathing:
        return const LinearGradient(
            colors: [Color(0xFFE3F2FD), Color(0xFFB7DCFF)],
            begin: Alignment.topLeft, end: Alignment.bottomRight);
      case WorkoutCategory.yoga:
        return const LinearGradient(
            colors: [Color(0xFFF3E5F5), Color(0xFFCE93D8)],
            begin: Alignment.topLeft, end: Alignment.bottomRight);
      case WorkoutCategory.household:
        return const LinearGradient(
            colors: [Color(0xFFFFF8E1), Color(0xFFFFE082)],
            begin: Alignment.topLeft, end: Alignment.bottomRight);
      case WorkoutCategory.walking:
        return const LinearGradient(
            colors: [Color(0xFFE0F2F1), Color(0xFF80CBC4)],
            begin: Alignment.topLeft, end: Alignment.bottomRight);
    }
  }
'''

# Split helpers into lines and prepend each with newline (they'll be
# inserted in order)
helper_lines = [l + '\n' for l in helpers.splitlines(keepends=False)]

# Insert helpers right before line 1096 (0-indexed 1095)
new_lines = lines[:target_idx] + helper_lines + lines[target_idx:]

with open(p, 'w', encoding='utf-8') as f:
    f.writelines(new_lines)

print(f'Inserted {len(helper_lines)} helper lines. New total: {len(new_lines)}')
