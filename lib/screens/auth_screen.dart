import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../services/app_errors.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';

/// Editorial-style auth.
///
/// Visually a single black panel that gently "thickness" itself on the mode
/// toggle, with the right-hand form sliding up underneath.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  bool _signUpMode = false;
  bool _loading = false;
  bool _obscure = true;
  String? _error;
  String? _errorField;

  // Connection-state pill — checked once on mount to show whether
  // the device can reach Supabase before the user even tries to log
  // in. Without this the user clicks "লগইন" on a dead wifi and
  // stares at a spinner until it times out.
  _ConnState _conn = _ConnState.checking;
  String? _connHint;

  // Sign-up only
  final _nameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  // Role pickers — added by the Patient/Caretaker split. Default
  // to 'patient' so existing callers + dev presets keep working.
  String _signUpRole = 'patient';
  final _roleRelationshipCtrl = TextEditingController();

  // Both modes
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  // Focus chain so "Next" jumps between fields and "Done" submits.
  final _nameFocus = FocusNode();
  final _mobileFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passFocus = FocusNode();

  // One-shot entry animation — starts at value=1 (i.e. fully visible) so
  // the first frame already shows the form. We briefly fade in only after
  // the layout pass completes, so we never collide with the keyboard or
  // the IME insets ticking.
  late final AnimationController _entry;
  late final Animation<double> _lift;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
      vsync: this,
      duration: AppMotion.medium,
      value: 1.0, // start visible — animation is purely cosmetic
    );
    _lift = Tween<double>(begin: 28, end: 0).animate(
      CurvedAnimation(parent: _entry, curve: AppMotion.emphasized),
    );
    _fadeIn = CurvedAnimation(parent: _entry, curve: AppMotion.standard);
    // Probe the network once on mount so the user can see a
    // "সংযুক্ত ✓" or "সংযোগ ব্যর্থ" pill above the form.
    WidgetsBinding.instance.addPostFrameCallback((_) => _probeConnection());
  }

  @override
  void dispose() {
    _entry.dispose();
    _nameFocus.dispose();
    _mobileFocus.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _roleRelationshipCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context)!;
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    if (email.isEmpty || pass.isEmpty) {
      _setError(l.authErrEmailPassword, field: 'auth');
      return;
    }
    if (_signUpMode) {
      final name = _nameCtrl.text.trim();
      final mobile = _mobileCtrl.text.trim();
      if (name.isEmpty) {
        _setError(l.authErrFullName, field: 'name');
        return;
      }
      if (mobile.length < 8) {
        _setError(l.authErrMobile, field: 'mobile');
        return;
      }
      if (_signUpRole == 'caretaker' &&
          _roleRelationshipCtrl.text.trim().isEmpty) {
        _setError(l.authErrRelationship, field: 'role');
        return;
      }
    }
    setState(() {
      _loading = true;
      _error = null;
      _errorField = null;
    });
    try {
      if (_signUpMode) {
        await SupabaseService.signUp(
          email: email,
          password: pass,
          fullName: _nameCtrl.text.trim(),
          mobile: _mobileCtrl.text.trim(),
          username: _usernameCtrl.text.trim(),
          role: _signUpRole,
          caretakerRelationship: _signUpRole == 'caretaker'
              ? _roleRelationshipCtrl.text.trim()
              : null,
        );
      } else {
        await SupabaseService.signIn(email, pass);
      }
      if (!mounted) return;
      _goNext();
    } catch (e) {
      // Use the shared Bangla mapper so common Supabase / network
      // errors render as friendly user-facing text instead of an
      // English stack trace.
      final msg = BanglaError.toBangla(e);
      _setError(
        _signUpMode
            ? l.authErrSignupPrefix(msg)
            : l.authErrLoginPrefix(msg),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setError(String msg, {String? field}) {
    HapticFeedback.heavyImpact();
    setState(() {
      _error = msg;
      _errorField = field;
    });
  }

  void _goNext() {
    // No manual navigation — the root widget subscribes to
    // Supabase auth state changes and rebuilds the tree with HomeShell
    // as soon as the session is established. Manually pushing here
    // would double-mount HomeShell.
    return;
  }

  void _toggleMode(bool signup) {
    if (_signUpMode == signup || _loading) return;
    HapticFeedback.selectionClick();
    setState(() {
      _signUpMode = signup;
      _error = null;
      _errorField = null;
      // Reset role fields when leaving signup so the next time the
      // user opens the form they start with the default.
      _signUpRole = 'patient';
      _roleRelationshipCtrl.clear();
    });
  }

  Future<void> _probeConnection() async {
    if (!mounted) return;
    final l = AppLocalizations.of(context)!;
    setState(() => _conn = _ConnState.checking);
    try {
      // A lightweight RPC call — any reachable path proves the
      // device can hit Supabase. 1.5s budget keeps the pill snappy.
      await SupabaseService.pingSession()
          .timeout(const Duration(milliseconds: 1500));
      if (!mounted) return;
      setState(() {
        _conn = _ConnState.online;
        _connHint = l.authConnOnline;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _conn = _ConnState.offline;
        _connHint = BanglaError.toBangla(e);
      });
    }
  }

  Future<void> _resetPassword() async {
    final l = AppLocalizations.of(context)!;
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      _setError(l.authErrResetEmail, field: 'auth');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _loading = true);
    try {
      await SupabaseService.resetPassword(email);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.cyan,
          content: Text(
            l.authErrResetSent(email),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.rose,
          content: Text(l.authErrResetFailed(BanglaError.toBangla(e))),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Transparent — the cosmos backdrop is painted in `main.dart`.
      backgroundColor: Colors.transparent,
      // Disable the keyboard-driven resize so the form doesn't keep relayouting
      // while the IME is animating in (that was the source of the "Skipped
      // 420 frames!" freeze).
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    // Computed once per build. We deliberately do NOT call MediaQuery.of
    // inside the body — every IME-inset tick would otherwise rebuild the
    // whole auth screen and cause the Skipped 420 frames crash.
    final mq = MediaQuery.maybeOf(context);
    final width = mq?.size.width ?? 360.0;
    final height = mq?.size.height ?? 720.0;
    final isWide = width > 720;
    final heroHeight = math.max(320.0, height * 0.45);
    if (isWide) {
      return Row(
        children: [
          Expanded(flex: 5, child: _buildHero()),
          Expanded(flex: 6, child: _buildForm()),
        ],
      );
    }
    return ListView(
      padding: EdgeInsets.zero,
      // BouncingScrollPhysics lets the user scroll the form back into view
      // even when the keyboard is up (the inner SingleChildScrollView handles
      // the actual text-field overflow).
      physics: const BouncingScrollPhysics(),
      children: [
        // Fixed hero height — it scrolls out of view when the keyboard appears,
        // which is fine. Animating the hero height on every IME tick was the
        // root cause of the layout storm.
        SizedBox(
          height: heroHeight,
          child: _buildHero(compact: true),
        ),
        _buildForm(physics: const NeverScrollableScrollPhysics()),
      ],
    );
  }

  Widget _buildHero({bool compact = false}) {
    final l = AppLocalizations.of(context)!;
    // The whole hero fades in once. Wrapping it in an AnimatedBuilder was
    // forcing a full subtree rebuild for every tick of the entry animation;
    // using AnimatedOpacity on the outermost widget is cheaper and quits
    // rebuilding once the tween finishes.
    return AnimatedBuilder(
      animation: _fadeIn,
      builder: (context, child) {
        return Opacity(opacity: _fadeIn.value.clamp(0.0, 1.0), child: child);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Local violet→cyan gradient — feels distinct from the global cosmos.
          const DecoratedBox(
              decoration: BoxDecoration(gradient: AppGradients.cosmos)),
          // Soft radial highlight from the top so the headline reads on top.
          Positioned(
            top: -60,
            left: -40,
            child: Container(
              width: 280,
              height: 280,
              decoration: const BoxDecoration(
                gradient: AppGradients.blobCyan,
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            right: -40,
            child: Container(
              width: 260,
              height: 260,
              decoration: const BoxDecoration(
                gradient: AppGradients.blobViolet,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 24 : 56,
              vertical: compact ? 28 : 56,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Real brand logo from assets/. Sized to fit the same
                    // 40-px square the placeholder icon used to occupy
                    // so the row layout stays identical.
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: AppGradients.aurora,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.cyan.withValues(alpha: 0.3),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      alignment: Alignment.center,
                      child: Image.asset(
                        'assets/logo.png',
                        width: 34,
                        height: 34,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.health_and_safety_rounded,
                          color: AppColors.void1,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      l.authBrand,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (!compact)
                  GradientTitle(
                    l.authHeroTitle,
                    style: const TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                      letterSpacing: -1.0,
                    ),
                  ),
                if (compact)
                  GradientTitle(
                    l.authHeroTitleCompact,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      letterSpacing: -0.6,
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  compact
                      ? l.authHeroSubCompact
                      : l.authHeroSub,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: compact ? 14 : 18,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                _ConnectionPill(
                  state: _conn,
                  hint: _connHint,
                  onTap: _probeConnection,
                ),
                const Spacer(),
                Row(
                  children: [
                    _heroBullet(l.authHeroBulletLocal),
                    const SizedBox(width: 18),
                    _heroBullet(l.authHeroBulletSenior),
                    const SizedBox(width: 18),
                    _heroBullet(l.authHeroBulletFree),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroBullet(String text) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            gradient: AppGradients.aurora,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildForm({ScrollPhysics? physics}) {
    // Wrap the whole form in a single AnimatedBuilder whose `child` is the
    // expensive subtree. Only the Transform itself rebuilds per animation
    // tick; the form below stays put.
    return AnimatedBuilder(
      animation: _lift,
      child: _buildFormBody(physics: physics),
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _lift.value),
          child: child,
        );
      },
    );
  }

  Widget _buildFormBody({ScrollPhysics? physics}) {
    final l = AppLocalizations.of(context)!;
    // IMPORTANT: do not call MediaQuery.of(context) here. Doing so would
    // subscribe the form body to every IME-inset tick and rebuild the
    // entire subtree ~10× per keyboard animation, blowing past the 16ms
    // frame budget and producing the "Skipped 420 frames!" crash.
    //
    // The outer ListView already handles keyboard overflow — when the IME
    // pushes the focused field out of view, the user can scroll the outer
    // ListView (BouncingScrollPhysics) to bring it back.
    return SingleChildScrollView(
      physics: physics,
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Overline(_signUpMode ? l.authOverlineSignup : l.authOverlineLogin),
          Text(
            _signUpMode ? l.authSignupTitle : l.authLoginTitle,
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              height: 1.1,
              letterSpacing: -0.6,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _signUpMode
                ? l.authSignupSubtitle
                : l.authLoginSubtitle,
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.smoke,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 22),
          Center(
            child: MonoSegmented<bool>(
              options: [
                (value: false, label: l.authLogin),
                (value: true, label: l.authSignup),
              ],
              selected: _signUpMode,
              onChanged: _toggleMode,
            ),
          ),
          const SizedBox(height: 28),
          AnimatedSize(
            duration: AppMotion.medium,
            curve: AppMotion.standard,
            child: Column(
              children: [
                if (_signUpMode) ...[
                  _Input(
                    controller: _nameCtrl,
                    focusNode: _nameFocus,
                    label: l.authFullName,
                    hint: l.authFullNameHint,
                    icon: Icons.person_outline,
                    hasError: _errorField == 'name',
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _mobileFocus.requestFocus(),
                  ),
                  const SizedBox(height: 14),
                  _Input(
                    controller: _mobileCtrl,
                    focusNode: _mobileFocus,
                    label: l.authMobile,
                    hint: l.authMobileHint,
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    hasError: _errorField == 'mobile',
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _emailFocus.requestFocus(),
                  ),
                  const SizedBox(height: 14),
                  // Unique @username — case-insensitive, exactly 6
                  // chars, [A-Za-z0-9_]. Collected at signup so the
                  // SQL trigger can mirror it into user_profiles.
                  // Caretakers search for patients by this handle.
                  _Input(
                    controller: _usernameCtrl,
                    label: l.authUsername,
                    hint: l.authUsernameHint,
                    icon: Icons.alternate_email,
                    hasError: _errorField == 'username',
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _emailFocus.requestFocus(),
                  ),
                  const SizedBox(height: 18),
                  // 3rd pill for the role split (Patient | Caregiver).
                  // We render a labelled segmented control rather than
                  // reusing the form-input chrome so the choice reads
                  // like a "question" not a "field".
                  Overline(l.authRoleQuestion),
                  const SizedBox(height: 6),
                  MonoSegmented<String>(
                    options: [
                      (value: 'patient', label: l.authRolePatient),
                      (value: 'caretaker', label: l.authRoleCaregiver),
                    ],
                    selected: _signUpRole,
                    onChanged: (v) => setState(() {
                      _signUpRole = v;
                      _error = null;
                      _errorField = null;
                    }),
                  ),
                  AnimatedSize(
                    duration: AppMotion.short,
                    curve: AppMotion.standard,
                    child: _signUpRole == 'caretaker'
                        ? Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: _Input(
                              controller: _roleRelationshipCtrl,
                              label: l.authRelationship,
                              hint: l.authRelationshipHint,
                              icon: Icons.family_restroom_outlined,
                              hasError: _errorField == 'role',
                              textCapitalization: TextCapitalization.none,
                              textInputAction: TextInputAction.next,
                              onSubmitted: (_) =>
                                  _emailFocus.requestFocus(),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 14),
                ],
                _Input(
                  controller: _emailCtrl,
                  focusNode: _emailFocus,
                  label: l.authEmail,
                  hint: l.authEmailHint,
                  icon: Icons.mail_outline,
                  keyboardType: TextInputType.emailAddress,
                  hasError: _errorField == 'auth',
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _passFocus.requestFocus(),
                  autofocus: !_signUpMode,
                ),
                const SizedBox(height: 14),
                _Input(
                  controller: _passCtrl,
                  focusNode: _passFocus,
                  label: l.authPassword,
                  hint: l.authPasswordHint,
                  icon: Icons.lock_outline,
                  obscureText: _obscure,
                  trailing: IconButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      setState(() => _obscure = !_obscure);
                    },
                    icon: Icon(_obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    tooltip: _obscure ? l.authShowPassword : l.authHidePassword,
                  ),
                  hasError: _errorField == 'auth',
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                ),
                // Forgot-password link — only visible in login mode.
                if (!_signUpMode)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _loading ? null : _resetPassword,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.violet,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.lock_reset_rounded, size: 16),
                      label: Text(
                        l.authForgotPassword,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: AppMotion.short,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SizeTransition(
                sizeFactor: anim,
                axisAlignment: -1,
                child: child,
              ),
            ),
            child: _error == null
                ? const SizedBox(height: 0, key: ValueKey('no_error'))
                : Padding(
                    key: ValueKey(_error),
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            size: 18, color: AppColors.ink),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          MonoButton(
            label: _signUpMode ? l.authSignupTitle : l.authLogin,
            leading: _signUpMode ? Icons.person_add_alt_1 : Icons.arrow_forward,
            loading: _loading,
            onPressed: _submit,
          ),
          const SizedBox(height: 16),
          Center(
            child: Pressable(
              onTap: _loading ? null : () => _toggleMode(!_signUpMode),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Text(
                  _signUpMode
                      ? l.authToggleToLogin
                      : l.authToggleToSignup,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Input extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? trailing;
  final bool hasError;
  final TextCapitalization textCapitalization;
  // IME stability additions: explicit focus chain + keyboard action button.
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  const _Input({
    required this.controller,
    required this.label,
    required this.icon,
    this.hint,
    this.keyboardType,
    this.obscureText = false,
    this.trailing,
    this.hasError = false,
    this.textCapitalization = TextCapitalization.none,
    this.focusNode,
    this.textInputAction,
    this.onSubmitted,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    // Static Container — no per-keystroke AnimatedContainer rebuild. The
    // error-state shadow is a decoration, not a transition; we paint it
    // only when `hasError` flips on.
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: hasError
            ? const [
                BoxShadow(
                  color: Color(
                      0x1A0F0E14), // AppColors.ink @ 10% (avoid rebuild on alpha lookup)
                  blurRadius: 0,
                  offset: Offset(0, 3),
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        obscureText: obscureText,
        textCapitalization: textCapitalization,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        autofocus: autofocus,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
        cursorColor: AppColors.ink,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: Icon(icon, size: 22),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 44, minHeight: 44),
          suffixIcon: trailing,
        ),
      ),
    );
  }
}

/// Three states for the auth screen's connection pill. Tapping the
/// pill always re-runs the probe so the user can refresh after
/// toggling wifi.
enum _ConnState { checking, online, offline }

/// Small status chip rendered just under the hero subtitle. Shows
/// whether the device can reach Supabase before the user attempts
/// to sign in.
class _ConnectionPill extends StatelessWidget {
  final _ConnState state;
  final String? hint;
  final VoidCallback onTap;
  const _ConnectionPill({
    required this.state,
    required this.hint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final (color, icon, label) = switch (state) {
      _ConnState.checking => (
          AppColors.cyanDeep,
          Icons.sync_rounded,
          l.authConnChecking,
        ),
      _ConnState.online => (
          AppColors.cyanDeep,
          Icons.check_circle_rounded,
          hint ?? l.authConnOnline,
        ),
      _ConnState.offline => (
          AppColors.rose,
          Icons.cloud_off_rounded,
          hint ?? l.authConnOffline,
        ),
    };
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.36)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
