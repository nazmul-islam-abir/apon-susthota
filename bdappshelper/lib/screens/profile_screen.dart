import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/app_button.dart';
import '../widgets/glass_text_field.dart';
import '../services/api_service.dart';
import 'settings_screen.dart';
import 'subscription_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await ApiService.ensureProfile();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openEdit() async {
    final p = _profile;
    if (p == null) return;
    final updated = await Navigator.of(context).push<UserProfile>(
      MaterialPageRoute(builder: (_) => EditProfileScreen(initial: p)),
    );
    if (updated != null && mounted) {
      setState(() => _profile = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : _Body(profile: _profile!, onEdit: _openEdit, onRefresh: _load),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 56, color: AppColors.textSecondary),
            const SizedBox(height: AppSpacing.md),
            Text(
              "Couldn't load your profile",
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(label: 'Retry', icon: Icons.refresh_rounded, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.profile, required this.onEdit, required this.onRefresh});
  final UserProfile profile;
  final VoidCallback onEdit;
  final Future<void> Function() onRefresh;

  String _humanGoal(String? g) {
    switch ((g ?? '').toLowerCase()) {
      case 'lose':
        return 'LOSE WEIGHT';
      case 'gain':
        return 'GAIN WEIGHT';
      case 'maintain':
        return 'MAINTAIN';
      default:
        return 'SET';
    }
  }

  String _humanActivity(String? a) {
    switch ((a ?? '').toLowerCase()) {
      case 'very_active':
        return 'Very active';
      case 'active':
        return 'Active';
      case 'moderate':
        return 'Moderate';
      case 'light':
        return 'Light';
      case 'sedentary':
        return 'Sedentary';
      default:
        return 'Set';
    }
  }

  String _humanGender(String? g) {
    switch ((g ?? '').toLowerCase()) {
      case 'male':
        return 'Male';
      case 'female':
        return 'Female';
      case 'other':
        return 'Other';
      default:
        return '—';
    }
  }

  String _humanDiet(String? d) {
    switch ((d ?? '').toLowerCase()) {
      case 'vegetarian':
        return 'Vegetarian';
      case 'vegan':
        return 'Vegan';
      case 'halal':
        return 'Halal';
      case 'none':
        return 'No preference';
      default:
        return '—';
    }
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$dd';
  }

  @override
  Widget build(BuildContext context) {
    final initials = profile.initials ?? 'U';
    final displayName = profile.name?.trim().isNotEmpty == true
        ? profile.name!.trim()
        : 'Add your name';
    final email = profile.email?.trim().isNotEmpty == true
        ? profile.email!.trim()
        : 'Add an email';
    final age = profile.age;
    final ageLabel = age == null ? '—' : '$age';

    final kcalTarget = profile.dailyCalorieTarget?.round() ?? 2000;
    final waterTargetMl = profile.weightKg == null
        ? 2500
        : (profile.weightKg! * 35).round().clamp(2000, 4000);
    final weightStart = profile.weightKg ?? 0;
    final heightCm = profile.heightCm ?? 0;

    return RefreshIndicator(
      onRefresh: onRefresh,
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
              children: [
                const Text(
                  'Profile',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  color: AppColors.textSecondary,
                  onPressed: onRefresh,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            GlassCard(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Row(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryDark],
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        initials,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          email,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.bolt_rounded,
                              size: 14,
                              color: profile.isPro
                                  ? AppColors.secondary
                                  : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              profile.isPro ? 'Pro member' : 'Free plan',
                              style: TextStyle(
                                fontSize: 11,
                                color: profile.isPro
                                    ? AppColors.secondary
                                    : AppColors.textSecondary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: onEdit,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: const Icon(
                        Icons.edit_rounded,
                        color: AppColors.primaryDark,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    label: 'Weight',
                    value: weightStart > 0 ? weightStart.toStringAsFixed(1) : '—',
                    unit: 'kg',
                    icon: Icons.monitor_weight_rounded,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _StatTile(
                    label: 'Height',
                    value: heightCm > 0 ? heightCm.toStringAsFixed(0) : '—',
                    unit: 'cm',
                    icon: Icons.straighten_rounded,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _StatTile(
                    label: 'Age',
                    value: ageLabel,
                    unit: 'yrs',
                    icon: Icons.cake_rounded,
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
                  const Text(
                    'Your goals at a glance',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _GoalRow(
                    label: 'Daily calories',
                    value: '$kcalTarget kcal',
                    progress: _safeProgress(profile.weightKg == null ? 0 : 1,
                        max: 1),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _GoalRow(
                    label: 'Daily water',
                    value: '${(waterTargetMl / 1000).toStringAsFixed(1)} L',
                    progress: 0,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _GoalRow(
                    label: 'Goal',
                    value: _humanGoal(profile.goal),
                    progress: profile.goal == null ? 0 : 1,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _GoalRow(
                    label: 'Activity',
                    value: _humanActivity(profile.activityLevel),
                    progress: profile.activityLevel == null ? 0 : 1,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: _MenuTile(
                    icon: Icons.workspace_premium_rounded,
                    label: 'Subscription',
                    tint: AppColors.accent,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SubscriptionScreen(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _MenuTile(
                    icon: Icons.settings_rounded,
                    label: 'Settings',
                    tint: AppColors.primary,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Edit profile',
              variant: AppButtonVariant.secondary,
              icon: Icons.edit_rounded,
              onPressed: onEdit,
            ),
            const SizedBox(height: AppSpacing.lg),
            GlassCard(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Profile details',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _DetailRow('Phone', '+${profile.phone}'),
                  _DetailRow('Gender', _humanGender(profile.gender)),
                  _DetailRow('DOB', _fmtDate(profile.dateOfBirth)),
                  _DetailRow('Diet', _humanDiet(profile.dietPref)),
                  _DetailRow('Target weight',
                      profile.targetWeightKg == null ? '—' : '${profile.targetWeightKg} kg'),
                  _DetailRow('BMR',
                      profile.bmr == null ? '—' : '${profile.bmr!.toStringAsFixed(0)} kcal'),
                  _DetailRow('TDEE',
                      profile.tdee == null ? '—' : '${profile.tdee!.toStringAsFixed(0)} kcal'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _safeProgress(double v, {required double max}) {
    if (max <= 0) return 0;
    return (v / max).clamp(0.0, 1.0);
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
  });
  final String label;
  final String value;
  final String unit;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primaryDark, size: 18),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
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
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      height: 1,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 3),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  unit,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
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

class _GoalRow extends StatelessWidget {
  const _GoalRow({
    required this.label,
    required this.value,
    required this.progress,
  });
  final String label;
  final String value;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.primaryDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 5,
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
          ),
        ),
      ],
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.tint,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
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
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Edit profile screen
// =====================================================================

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.initial});
  final UserProfile initial;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _height;
  late final TextEditingController _weight;
  late final TextEditingController _target;

  String? _gender;
  String? _activity;
  String? _goal;
  String? _diet;
  DateTime? _dob;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _name = TextEditingController(text: p.name ?? '');
    _email = TextEditingController(text: p.email ?? '');
    _height = TextEditingController(
        text: p.heightCm == null ? '' : p.heightCm!.toStringAsFixed(0));
    _weight = TextEditingController(
        text: p.weightKg == null ? '' : p.weightKg!.toStringAsFixed(1));
    _target = TextEditingController(
        text: p.targetWeightKg == null ? '' : p.targetWeightKg!.toStringAsFixed(1));
    _gender = p.gender;
    _activity = p.activityLevel;
    _goal = p.goal;
    _diet = p.dietPref;
    _dob = p.dateOfBirth;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _height.dispose();
    _weight.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final fields = <String, dynamic>{};
      if (_name.text.trim().isNotEmpty) fields['name'] = _name.text.trim();
      if (_email.text.trim().isNotEmpty) fields['email'] = _email.text.trim();
      if (_gender != null) fields['gender'] = _gender;
      if (_height.text.trim().isNotEmpty) {
        fields['height_cm'] = double.tryParse(_height.text.trim()) ?? 0;
      }
      if (_weight.text.trim().isNotEmpty) {
        fields['weight_kg'] = double.tryParse(_weight.text.trim()) ?? 0;
      }
      if (_activity != null) fields['activity_level'] = _activity;
      if (_goal != null) fields['goal'] = _goal;
      if (_target.text.trim().isNotEmpty) {
        fields['target_weight_kg'] = double.tryParse(_target.text.trim()) ?? 0;
      }
      if (_diet != null) fields['diet_pref'] = _diet;
      if (_dob != null) {
        fields['date_of_birth'] =
            '${_dob!.year.toString().padLeft(4, '0')}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}';
      }
      final updated = await ApiService.updateProfile(fields);
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e'), behavior: SnackBarBehavior.floating),
      );
      setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.gradientMid,
      appBar: AppBar(
        title: const Text('Edit profile'),
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
                controller: _name,
                hint: 'Full name',
                prefix: const Icon(Icons.person_rounded,
                    color: AppColors.textSecondary, size: 18),
              ),
              const SizedBox(height: AppSpacing.md),
              GlassTextField(
                controller: _email,
                hint: 'Email',
                keyboardType: TextInputType.emailAddress,
                prefix: const Icon(Icons.alternate_email_rounded,
                    color: AppColors.textSecondary, size: 18),
              ),
              const SizedBox(height: AppSpacing.md),
              GlassCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Gender',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: AppSpacing.sm),
                    _Chips<String>(
                      options: const ['male', 'female', 'other'],
                      labels: const {'male': 'Male', 'female': 'Female', 'other': 'Other'},
                      selected: _gender,
                      onChanged: (v) => setState(() => _gender = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              GlassCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Date of birth',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: AppSpacing.sm),
                    InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today_rounded,
                                size: 16, color: AppColors.textSecondary),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              _dob == null
                                  ? 'Tap to choose'
                                  : '${_dob!.year}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: GlassTextField(
                      controller: _height,
                      hint: 'Height (cm)',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: GlassTextField(
                      controller: _weight,
                      hint: 'Weight (kg)',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              GlassCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Activity level',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: AppSpacing.sm),
                    _Chips<String>(
                      options: const ['sedentary', 'light', 'moderate', 'active', 'very_active'],
                      labels: const {
                        'sedentary': 'Sedentary',
                        'light': 'Light',
                        'moderate': 'Moderate',
                        'active': 'Active',
                        'very_active': 'Very active',
                      },
                      selected: _activity,
                      onChanged: (v) => setState(() => _activity = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              GlassCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Goal',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: AppSpacing.sm),
                    _Chips<String>(
                      options: const ['lose', 'maintain', 'gain'],
                      labels: const {
                        'lose': 'Lose weight',
                        'maintain': 'Maintain',
                        'gain': 'Gain weight',
                      },
                      selected: _goal,
                      onChanged: (v) => setState(() => _goal = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              GlassTextField(
                controller: _target,
                hint: 'Target weight (kg)',
                keyboardType: TextInputType.number,
                prefix: const Icon(Icons.flag_rounded,
                    color: AppColors.textSecondary, size: 18),
              ),
              const SizedBox(height: AppSpacing.md),
              GlassCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Diet preference',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: AppSpacing.sm),
                    _Chips<String>(
                      options: const ['none', 'vegetarian', 'vegan', 'halal'],
                      labels: const {
                        'none': 'No preference',
                        'vegetarian': 'Vegetarian',
                        'vegan': 'Vegan',
                        'halal': 'Halal',
                      },
                      selected: _diet,
                      onChanged: (v) => setState(() => _diet = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: _saving ? 'Saving…' : 'Save changes',
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

class _Chips<T> extends StatelessWidget {
  const _Chips({
    required this.options,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });
  final List<T> options;
  final Map<T, String> labels;
  final T? selected;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final isSel = opt == selected;
        return GestureDetector(
          onTap: () => onChanged(opt),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: isSel
                  ? const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryDark])
                  : null,
              color: isSel ? null : Colors.white.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: isSel
                    ? Colors.transparent
                    : Colors.white.withValues(alpha: 0.8),
              ),
            ),
            child: Text(
              labels[opt] ?? opt.toString(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: isSel ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
