import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/user_profile.dart';
import '../services/bdapps/bdapps_session_service.dart';
import '../services/supabase_service.dart';
import '../services/classification_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';

/// Onboarding / profile editor — 4-step clinical intake with custom editorial UI.
class OnboardingScreen extends StatefulWidget {
  final UserProfile? edit;
  const OnboardingScreen({super.key, this.edit});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  int _step = 0;

  // Controllers
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _mobile = TextEditingController();
  final _age = TextEditingController();
  final _weight = TextEditingController();
  final _height = TextEditingController();
  final _fasting = TextEditingController();
  final _postMeal = TextEditingController();
  final _hba1c = TextEditingController();
  final _medication = TextEditingController();
  final _systolic = TextEditingController();
  final _diastolic = TextEditingController();
  final _other = TextEditingController();

  // Selectors
  String _sex = 'male';
  bool _onInsulin = false;
  bool _hasCkd = false;
  bool _hasHeart = false;
  bool _hasAnemia = false;
  String _activity = 'low';
  String _mealSize = 'medium';
  String _foodPref = 'omnivore';

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    if (e != null) {
      _name.text = e.fullName ?? '';
      _username.text = e.username ?? '';
      _mobile.text = e.mobile ?? '';
      _age.text = e.age.toString();
      _sex = e.sex;
      _weight.text = e.weightKg.toString();
      _height.text = e.heightCm.toString();
      _fasting.text = e.fastingGlucoseMmol?.toString() ?? '';
      _postMeal.text = e.postMealGlucoseMmol?.toString() ?? '';
      _hba1c.text = e.hba1cPercent?.toString() ?? '';
      _medication.text = e.medication ?? '';
      _systolic.text = e.systolicBp?.toString() ?? '';
      _diastolic.text = e.diastolicBp?.toString() ?? '';
      _other.text = e.otherConditions ?? '';
      _onInsulin = e.onInsulin;
      _hasCkd = e.hasCkd;
      _hasHeart = e.hasHeartDisease;
      _hasAnemia = e.hasAnemia;
      _activity = e.activityLevel;
      _mealSize = e.mealSizePref;
      _foodPref = e.foodPreference;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _mobile.dispose();
    _age.dispose();
    _weight.dispose();
    _height.dispose();
    _fasting.dispose();
    _postMeal.dispose();
    _hba1c.dispose();
    _medication.dispose();
    _systolic.dispose();
    _diastolic.dispose();
    _other.dispose();
    super.dispose();
  }

  String? _number(String? v, AppLocalizations l) {
    if (v == null || v.trim().isEmpty) return l.onboardingFieldRequired;
    if (double.tryParse(v.trim()) == null) return l.onboardingFieldNumber;
    return null;
  }

  /// Username validation: required, exactly 6 chars, [A-Za-z0-9_] only.
  /// Case-insensitive uniqueness is enforced server-side via the
  /// `uniq_user_profiles_username` partial index, so the only thing
  /// we can catch here is format.
  String? _usernameFmt(String? v, AppLocalizations l) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return l.onboardingFieldRequired;
    if (s.length != 6) return l.onboardingUsernameFormat;
    if (!RegExp(r'^[A-Za-z0-9_]{6}$').hasMatch(s)) {
      return l.onboardingUsernameCharset;
    }
    return null;
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context)!;
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Hard-check required fields before any I/O so we never hit a parse error
    // in the middle of an async save.
    final username = _username.text.trim();
    final usernameErr = _usernameFmt(username, l);
    if (usernameErr != null) {
      _toast(usernameErr);
      return;
    }
    final age = int.tryParse(_age.text.trim());
    final weight = double.tryParse(_weight.text.trim());
    final height = double.tryParse(_height.text.trim());
    if (age == null || age < 1 || age > 120) {
      _toast(l.onboardingAgeRange);
      return;
    }
    if (weight == null || weight < 10 || weight > 400) {
      _toast(l.onboardingWeightInvalid);
      return;
    }
    if (height == null || height < 30 || height > 250) {
      _toast(l.onboardingHeightInvalid);
      return;
    }

    setState(() => _saving = true);

    try {
      // Safe parsing: ensure we never crash on invalid input that slipped
      // past the basic validators (e.g. decimals in int fields).
      final fasting = double.tryParse(_fasting.text.trim());
      final postMeal = double.tryParse(_postMeal.text.trim());
      final hba1c = double.tryParse(_hba1c.text.trim());
      
      final systolic = int.tryParse(_systolic.text.trim()) ?? 
          (double.tryParse(_systolic.text.trim())?.round());
      final diastolic = int.tryParse(_diastolic.text.trim()) ?? 
          (double.tryParse(_diastolic.text.trim())?.round());

      final profile = UserProfile(
        fullName: _name.text.trim().isEmpty ? null : _name.text.trim(),
        username: username,
        mobile: _mobile.text.trim().isEmpty ? null : _mobile.text.trim(),
        age: age,
        sex: _sex,
        weightKg: weight,
        heightCm: height,
        fastingGlucoseMmol: fasting,
        postMealGlucoseMmol: postMeal,
        hba1cPercent: hba1c,
        onInsulin: _onInsulin,
        medication: _medication.text.trim().isEmpty ? null : _medication.text.trim(),
        systolicBp: systolic,
        diastolicBp: diastolic,
        hasCkd: _hasCkd,
        hasHeartDisease: _hasHeart,
        hasAnemia: _hasAnemia,
        otherConditions: _other.text.trim().isEmpty ? null : _other.text.trim(),
        activityLevel: _activity,
        mealSizePref: _mealSize,
        foodPreference: _foodPref,
        avatarUrl: widget.edit?.avatarUrl,
        photoUploadCount: widget.edit?.photoUploadCount ?? 0,
        // Preserve the existing role + caretaker relationship. Without this,
        // a caretaker who edits their profile from inside the caretaker shell
        // would be silently downgraded to 'patient' because the UserProfile()
        // default is role='patient'. The SQL trigger (08_signup_identity.sql)
        // sets role from auth metadata at signup; this round-trip preserves it
        // on every subsequent edit.
        role: widget.edit?.role ?? 'patient',
        caretakerRelationship: widget.edit?.caretakerRelationship,
        profileCompleted: true, // gate the post-login dialog
      );

      await SupabaseService.saveProfile(profile);

      // BDApps: flip the local + server profile_completed flag so the
      // post-login dialog doesn't fire again on this user.
      if (BdappsSessionService.instance.role != null) {
        await BdappsSessionService.instance.markProfileCompleted();
      }

      try {
        await SupabaseService.updateAccountMeta(
          fullName: profile.fullName,
          mobile: profile.mobile,
          username: profile.username,
          profileCompleted: profile.profileCompleted,
        );
      } catch (_) {
        // Silent — profile is already saved. Identity mirror is best-effort.
      }

      if (!mounted) return;

      // Capture the navigator BEFORE any further awaits so we don't hit
      // "looking up a deactivated widget" if the user navigates away during
      // the warnings dialog.
      final navigator = Navigator.of(context);

      final cls = ClassificationEngine.classify(profile);
      if (cls.warnings.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (_) => _WarningsDialog(warnings: cls.warnings),
        );
      }
      if (!mounted) return;
      navigator.pop(true);
    } catch (e, st) {
      // Surface error and keep the user on the screen instead of tearing the
      // app down. Log the stack for debugging.
      debugPrint('saveProfile failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            l.onboardingSaveFailed(_friendlyError(e, l)),
            style: const TextStyle(color: AppColors.paper),
          ),
          backgroundColor: AppColors.ink,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(msg, style: const TextStyle(color: AppColors.paper)),
        backgroundColor: AppColors.ink,
      ),
    );
  }

  String _friendlyError(Object e, AppLocalizations l) {
    final s = e.toString();
    if (s.contains('SocketException') || s.contains('Failed host lookup')) {
      return l.onboardingErrNoInternet;
    }
    if (s.contains('42501') || s.toLowerCase().contains('row-level security')) {
      return l.onboardingErrNoPermission;
    }
    if (s.contains('23514') || s.contains('check constraint')) {
      return l.onboardingErrOutOfRange;
    }
    // Postgres unique-violation on the username partial index. Show a
    // friendly picker message rather than the raw DB code.
    if (s.contains('uniq_user_profiles_username') ||
        (s.contains('duplicate key value') && s.contains('username'))) {
      return l.onboardingErrUsernameTaken;
    }
    return l.onboardingErrRetry;
  }

  void _next() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_step < 3) {
      setState(() => _step++);
    } else {
      _save();
    }
  }

  void _back() {
    if (_step == 0) {
      Navigator.pop(context);
    } else {
      setState(() => _step--);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _topBar(),
            _progressRail(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: Form(
                  key: _formKey,
                  child: AnimatedSwitcher(
                    duration: AppMotion.medium,
                    switchInCurve: AppMotion.emphasized,
                    switchOutCurve: AppMotion.emphasized,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.04, 0),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey(_step),
                      child: _buildStep(_step),
                    ),
                  ),
                ),
              ),
            ),
            _bottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 20, 0),
      child: Row(
        children: [
          Pressable(
            onTap: _back,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.chalk,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.graphite),
              ),
              child: const Icon(Icons.arrow_back, size: 20, color: AppColors.ink),
            ),
          ),
          const Spacer(),
          Text(
            widget.edit != null ? l.onboardingEditTitle : l.onboardingNewTitle,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.smoke,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressRail() {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Overline(
            [
              l.onboardingStep1Of4,
              l.onboardingStep2Of4,
              l.onboardingStep3Of4,
              l.onboardingStep4Of4,
            ][_step],
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 10),
          Text(
            [
              l.onboardingStep1Title,
              l.onboardingStep2Title,
              l.onboardingStep3Title,
              l.onboardingStep4Title,
            ][_step],
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              height: 1.05,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            [
              l.onboardingStep1Blurb,
              l.onboardingStep2Blurb,
              l.onboardingStep3Blurb,
              l.onboardingStep4Blurb,
            ][_step],
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.smoke,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(4, (i) {
              final filled = i <= _step;
              return Expanded(
                child: AnimatedContainer(
                  duration: AppMotion.short,
                  curve: AppMotion.emphasized,
                  margin: EdgeInsets.only(right: i == 3 ? 0 : 6),
                  height: 5,
                  decoration: BoxDecoration(
                    color: filled ? AppColors.ink : AppColors.graphite,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    final l = AppLocalizations.of(context)!;
    final isLast = _step == 3;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      decoration: BoxDecoration(
        color: AppColors.paper,
        border: Border(top: BorderSide(color: AppColors.graphite.withValues(alpha: 0.6))),
      ),
      child: Row(
        children: [
          if (_step > 0)
            Expanded(
              flex: 2,
              child: MonoButton(
                label: l.onboardingPrevious,
                leading: Icons.arrow_back,
                variant: MonoButtonVariant.outline,
                onPressed: _saving ? null : () => setState(() => _step--),
              ),
            ),
          if (_step > 0) const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: MonoButton(
              label: isLast ? l.onboardingFinish : l.onboardingNext,
              trailing: isLast ? null : Icons.arrow_forward,
              loading: _saving,
              onPressed: _next,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- STEP BUILDERS ----------------

  Widget _buildStep(int step) {
    switch (step) {
      case 0:
        return _basic();
      case 1:
        return _glucose();
      case 2:
        return _conditions();
      case 3:
      default:
        return _lifestyle();
    }
  }

  Widget _basic() {
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labeled(l.onboardingFieldFullName, l.onboardingOptional),
        TextFormField(
          controller: _name,
          decoration: InputDecoration(hintText: l.onboardingFieldFullNameHint),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.ink),
        ),
        const SizedBox(height: 18),
        _labeled(l.onboardingMobile, l.onboardingOptional),
        TextFormField(
          controller: _mobile,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(hintText: '01XXXXXXXXX'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.ink),
        ),
        const SizedBox(height: 18),
        // Unique @username — case-insensitive unique across the app.
        // Caretakers search for patients by this, and the patient inbox
        // + dashboard surface it next to the full name so two "abir"s
        // are easy to tell apart. Required, exactly 6 chars,
        // [A-Za-z0-9_]. Uniqueness is enforced server-side; the
        // _friendlyError handler surfaces the duplicate-key error
        // as a friendly picker message.
        _labeled(l.onboardingUsername, l.onboardingRequired6),
        TextFormField(
          controller: _username,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.none,
          maxLength: 6,
          decoration: const InputDecoration(
            hintText: 'nazmul',
            counterText: '',
            prefixText: '@',
          ),
          style: const TextStyle(
              fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink),
          validator: (v) => _usernameFmt(v, l),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final useRow = constraints.maxWidth > 400;
            if (useRow) {
              return Row(
                children: [
                  Expanded(child: _field(_age, l.onboardingAge, validator: (v) => _number(v, l), numeric: true)),
                  const SizedBox(width: 12),
                  Expanded(child: _field(_weight, l.onboardingWeight, validator: (v) => _number(v, l), numeric: true)),
                  const SizedBox(width: 12),
                  Expanded(child: _field(_height, l.onboardingHeight, validator: (v) => _number(v, l), numeric: true)),
                ],
              );
            }
            return Column(
              children: [
                _field(_age, l.onboardingAge, validator: (v) => _number(v, l), numeric: true),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _field(_weight, l.onboardingWeight, validator: (v) => _number(v, l), numeric: true)),
                    const SizedBox(width: 12),
                    Expanded(child: _field(_height, l.onboardingHeight, validator: (v) => _number(v, l), numeric: true)),
                  ],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        _labeled(l.onboardingSex),
        MonoSegmented<String>(
          selected: _sex,
          options: [
            (label: l.onboardingSexMale, value: 'male'),
            (label: l.onboardingSexFemale, value: 'female'),
            (label: l.onboardingSexOther, value: 'other'),
          ],
          onChanged: (v) => setState(() => _sex = v),
        ),
      ],
    );
  }

  Widget _glucose() {
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final useRow = constraints.maxWidth > 340;
            if (useRow) {
              return Row(
                children: [
                  Expanded(child: _field(_fasting, l.onboardingFastingGlucose, suffix: 'mmol/L', validator: (v) => _number(v, l), numeric: true)),
                  const SizedBox(width: 12),
                  Expanded(child: _field(_postMeal, l.onboardingPostMealGlucose, suffix: 'mmol/L', validator: (v) => _number(v, l), numeric: true)),
                ],
              );
            }
            return Column(
              children: [
                _field(_fasting, l.onboardingFastingGlucose, suffix: 'mmol/L', validator: (v) => _number(v, l), numeric: true),
                const SizedBox(height: 12),
                _field(_postMeal, l.onboardingPostMealGlucose, suffix: 'mmol/L', validator: (v) => _number(v, l), numeric: true),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        _field(_hba1c, l.onboardingHba1c, suffix: '%', validator: (v) => _number(v, l), numeric: true),
        const SizedBox(height: 18),
        _labeled(l.onboardingMedicationLabel),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          decoration: BoxDecoration(
            color: AppColors.chalk,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.graphite),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l.onboardingOnInsulin,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
              ),
              Switch.adaptive(
                value: _onInsulin,
                activeTrackColor: AppColors.ink,
                activeColor: AppColors.paper,
                inactiveTrackColor: AppColors.graphite,
                onChanged: (v) => setState(() => _onInsulin = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _medication,
          decoration: InputDecoration(hintText: l.onboardingMedicationHint),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ink),
        ),
      ],
    );
  }

  Widget _conditions() {
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labeled(l.onboardingBp, l.onboardingOptional),
        Row(
          children: [
            Expanded(child: _field(_systolic, l.onboardingSystolic, optional: true, validator: (v) => _number(v, l), numeric: true)),
            const SizedBox(width: 12),
            Expanded(child: _field(_diastolic, l.onboardingDiastolic, optional: true, validator: (v) => _number(v, l), numeric: true)),
          ],
        ),
        const SizedBox(height: 18),
        _labeled(l.onboardingChronic),
        _switchTile(
          label: l.onboardingCkdLabel,
          sub: l.onboardingCkdSub,
          value: _hasCkd,
          onChanged: (v) => setState(() => _hasCkd = v),
        ),
        const SizedBox(height: 10),
        _switchTile(
          label: l.onboardingHeartLabel,
          sub: l.onboardingHeartSub,
          value: _hasHeart,
          onChanged: (v) => setState(() => _hasHeart = v),
        ),
        const SizedBox(height: 10),
        _switchTile(
          label: l.onboardingAnemiaLabel,
          sub: l.onboardingAnemiaSub,
          value: _hasAnemia,
          onChanged: (v) => setState(() => _hasAnemia = v),
        ),
        const SizedBox(height: 18),
        _labeled(l.onboardingOtherConditions, l.onboardingOptional),
        TextFormField(
          controller: _other,
          maxLines: 2,
          decoration: InputDecoration(hintText: l.onboardingOtherConditionsHint),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ink),
        ),
      ],
    );
  }

  Widget _lifestyle() {
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labeled(l.onboardingActivity),
        MonoSegmented<String>(
          selected: _activity,
          options: [
            (label: l.onboardingActivityLow, value: 'low'),
            (label: l.onboardingActivityModerate, value: 'moderate'),
            (label: l.onboardingActivityHigh, value: 'high'),
          ],
          onChanged: (v) => setState(() => _activity = v),
        ),
        const SizedBox(height: 18),
        _labeled(l.onboardingMealSize),
        MonoSegmented<String>(
          selected: _mealSize,
          options: [
            (label: l.onboardingMealSizeSmall, value: 'small'),
            (label: l.onboardingMealSizeMedium, value: 'medium'),
            (label: l.onboardingMealSizeLarge, value: 'large'),
          ],
          onChanged: (v) => setState(() => _mealSize = v),
        ),
        const SizedBox(height: 18),
        _labeled(l.onboardingFoodPref),
        MonoSegmented<String>(
          selected: _foodPref,
          options: [
            (label: l.onboardingFoodPrefOmnivore, value: 'omnivore'),
            (label: l.onboardingFoodPrefVegetarian, value: 'vegetarian'),
            (label: l.onboardingFoodPrefFishOnly, value: 'fish_only'),
            (label: l.onboardingFoodPrefNoBeef, value: 'no_beef'),
          ],
          onChanged: (v) => setState(() => _foodPref = v),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.chalk,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.graphite),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: AppGradients.aurora,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.info_outline, color: AppColors.paper, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l.onboardingDisclaimer,
                  style: const TextStyle(fontSize: 13, color: AppColors.ink, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------- FORM PIECES ----------------

  Widget _labeled(String label, [String? hint]) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              letterSpacing: 0.2,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(width: 8),
            Text(
              hint,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.smoke,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    String? suffix,
    String? Function(String?)? validator,
    bool numeric = false,
    bool optional = false,
  }) {
    final l = AppLocalizations.of(context)!;
    // Tight, width-safe layout — label above, compact field below. The suffix
    // sits inside the input and is allowed to wrap so two side-by-side fields
    // never overflow on narrow phones.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labeled(label, optional ? l.onboardingOptional : null),
        TextFormField(
          controller: ctrl,
          validator: optional
              ? (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  if (double.tryParse(v.trim()) == null) return l.onboardingFieldNumber;
                  return null;
                }
              : validator,
          keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          inputFormatters: numeric ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))] : null,
          decoration: suffix != null
              ? InputDecoration(
                  hintText: '0',
                  suffixText: suffix,
                  suffixStyle: const TextStyle(fontSize: 13, color: AppColors.smoke, fontWeight: FontWeight.w600),
                  isDense: true,
                )
              : const InputDecoration(isDense: true),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
      ],
    );
  }

  Widget _switchTile({required String label, required String sub, required bool value, required ValueChanged<bool> onChanged}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: AppColors.chalk,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.graphite),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
                const SizedBox(height: 2),
                Text(sub, style: const TextStyle(fontSize: 13, color: AppColors.smoke, height: 1.35)),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeTrackColor: AppColors.ink,
            activeColor: AppColors.paper,
            inactiveTrackColor: AppColors.graphite,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _WarningsDialog extends StatelessWidget {
  final List<String> warnings;
  const _WarningsDialog({required this.warnings});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Dialog(
      backgroundColor: AppColors.paper,
      surfaceTintColor: AppColors.paper,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: AppGradients.aurora,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.priority_high, color: AppColors.paper, size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  l.onboardingWarningsTitle,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink, letterSpacing: -0.2),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final w in warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(width: 5, height: 5, decoration: const BoxDecoration(color: AppColors.ink, shape: BoxShape.circle)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(w, style: const TextStyle(fontSize: 15, color: AppColors.ink, height: 1.4)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: MonoButton(label: l.onboardingGotIt, onPressed: () => Navigator.pop(context)),
            ),
          ],
        ),
      ),
    ));
  }
}
