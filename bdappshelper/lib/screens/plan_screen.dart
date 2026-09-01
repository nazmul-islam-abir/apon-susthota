import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/app_button.dart';
import '../widgets/glass_text_field.dart';
import '../widgets/gradient_background.dart';
import '../widgets/section_header.dart';
import '../services/api_service.dart';

class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  late Future<DailyPlan> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<DailyPlan> _load() async {
    return ApiService.getPlan(date: DateTime.now());
  }

  Future<void> _reload() async {
    final next = _load();
    setState(() {
      _future = next;
    });
    await next;
  }

  Future<void> _edit(DailyPlan current) async {
    await Navigator.of(context).push<DailyPlan>(
      MaterialPageRoute(builder: (_) => EditPlanScreen(plan: current)),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: FutureBuilder<DailyPlan>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }
          if (snap.hasError) {
            return _ErrorView(error: snap.error.toString(), onRetry: _reload);
          }
          final plan = snap.data ?? DailyPlan.empty();
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            color: AppColors.primary,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.xl,
                120,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Today\'s plan',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                                letterSpacing: -0.3,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Targets hand-tuned from your profile.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded),
                        color: AppColors.textSecondary,
                        onPressed: _reload,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: _PlanStatTile(
                          icon: Icons.local_fire_department_rounded,
                          tint: AppColors.primary,
                          label: 'Calories',
                          value: plan.kcalTarget.toStringAsFixed(0),
                          unit: 'kcal',
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _PlanStatTile(
                          icon: Icons.water_drop_rounded,
                          tint: AppColors.secondary,
                          label: 'Water',
                          value: (plan.waterMl / 1000).toStringAsFixed(1),
                          unit: 'L',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  GlassCard(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.notes_rounded,
                                size: 18, color: AppColors.primaryDark),
                            const SizedBox(width: AppSpacing.sm),
                            const Text(
                              'Notes',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _edit(plan),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.15),
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.sm),
                                  ),
                                  child: const Icon(
                                    Icons.edit_rounded,
                                    size: 14,
                                    color: AppColors.primaryDark,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          (plan.notes == null || plan.notes!.trim().isEmpty)
                              ? 'No notes for today. Tap the pencil to add one.'
                              : plan.notes!,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const SectionHeader(title: 'Macro breakdown'),
                  const SizedBox(height: AppSpacing.md),
                  _MacroBar(
                    label: 'Protein',
                    kcal: plan.kcalTarget * 0.25,
                    grams: (_protein(plan.kcalTarget)).toStringAsFixed(0),
                    color: AppColors.secondary,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _MacroBar(
                    label: 'Carbs',
                    kcal: plan.kcalTarget * 0.50,
                    grams: (_carbs(plan.kcalTarget)).toStringAsFixed(0),
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _MacroBar(
                    label: 'Fat',
                    kcal: plan.kcalTarget * 0.25,
                    grams: (_fat(plan.kcalTarget)).toStringAsFixed(0),
                    color: AppColors.accent,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    label: 'Edit plan',
                    icon: Icons.tune_rounded,
                    onPressed: () => _edit(plan),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
    ),
    );
  }

  // 50% carbs / 25% protein / 25% fat with 4 / 4 / 9 kcal per gram.
  double _carbs(double kcal) => (kcal * 0.50) / 4;
  double _protein(double kcal) => (kcal * 0.25) / 4;
  double _fat(double kcal) => (kcal * 0.25) / 9;
}

class _PlanStatTile extends StatelessWidget {
  const _PlanStatTile({
    required this.icon,
    required this.tint,
    required this.label,
    required this.value,
    required this.unit,
  });
  final IconData icon;
  final Color tint;
  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  tint.withValues(alpha: 0.85),
                  tint.withValues(alpha: 0.55),
                ],
              ),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      height: 1,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  unit,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MacroBar extends StatelessWidget {
  const _MacroBar({
    required this.label,
    required this.kcal,
    required this.grams,
    required this.color,
  });
  final String label;
  final double kcal;
  final String grams;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${kcal.toStringAsFixed(0)} kcal · $grams g',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: 1,
              minHeight: 6,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 56, color: AppColors.textSecondary),
            const SizedBox(height: AppSpacing.md),
            const Text(
              "Couldn't load your plan",
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
                label: 'Retry', icon: Icons.refresh_rounded, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// Edit plan
// =====================================================================

class EditPlanScreen extends StatefulWidget {
  const EditPlanScreen({super.key, required this.plan});
  final DailyPlan plan;

  @override
  State<EditPlanScreen> createState() => _EditPlanScreenState();
}

class _EditPlanScreenState extends State<EditPlanScreen> {
  late final TextEditingController _kcal;
  late final TextEditingController _water;
  late final TextEditingController _notes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _kcal = TextEditingController(
      text: widget.plan.kcalTarget.toStringAsFixed(0),
    );
    _water = TextEditingController(
      text: widget.plan.waterMl.toString(),
    );
    _notes = TextEditingController(text: widget.plan.notes ?? '');
  }

  @override
  void dispose() {
    _kcal.dispose();
    _water.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final kcal = int.tryParse(_kcal.text.trim()) ?? 0;
    final water = int.tryParse(_water.text.trim()) ?? 0;
    if (kcal <= 0 || water <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a positive calorie and water target.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiService.savePlan(
        planDate: DateTime.now(),
        kcalTarget: kcal.toDouble(),
        waterMl: water,
        notes: _notes.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.gradientMid,
      appBar: AppBar(
        title: const Text('Edit plan'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassTextField(
                controller: _kcal,
                hint: 'Calories target',
                keyboardType: TextInputType.number,
                prefix: const Icon(Icons.local_fire_department_rounded,
                    color: AppColors.textSecondary, size: 18),
              ),
              const SizedBox(height: AppSpacing.md),
              GlassTextField(
                controller: _water,
                hint: 'Water target (ml)',
                keyboardType: TextInputType.number,
                prefix: const Icon(Icons.water_drop_rounded,
                    color: AppColors.textSecondary, size: 18),
              ),
              const SizedBox(height: AppSpacing.md),
              GlassTextField(
                controller: _notes,
                hint: 'Notes (optional)',
                maxLines: 4,
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: _saving ? 'Saving…' : 'Save plan',
                icon: Icons.check_rounded,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
