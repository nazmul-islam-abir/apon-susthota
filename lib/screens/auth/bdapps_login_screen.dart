import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/app_navigator.dart';
import '../../services/bdapps/bdapps_service.dart';
import '../../services/bdapps/bdapps_session_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/glass_text_field.dart';
import '../../widgets/app_button.dart';

/// Unified BDApps OTP login screen for both Patient and Caretaker.
///
/// Steps:
///   1. User enters their Bangladeshi mobile number.
///   2. Tap "OTP পাঠান" → `BdappsService.sendOtp`.
///   3. UI switches to the OTP step (6-digit code).
///   4. User enters the code → `BdappsService.verifyOtp`.
///   5. On success → `BdappsSessionService.loginOrSignup` issues a
///      Supabase session via `bdapps_issue_session`. The AuthScreen's
///      auth-listener picks up the new session and routes to the
///      role-appropriate shell.
class BdappsLoginScreen extends StatefulWidget {
  const BdappsLoginScreen({super.key, required this.role});

  /// The role the user picked on the landing screen. Passed through
  /// to the Supabase RPC when creating the shadow auth user.
  final String role;

  @override
  State<BdappsLoginScreen> createState() => _BdappsLoginScreenState();
}

class _BdappsLoginScreenState extends State<BdappsLoginScreen>
    with SingleTickerProviderStateMixin {
  // Step 0 = mobile entry, Step 1 = OTP.
  int _step = 0;
  final _phone = TextEditingController();
  bool _loading = false;
  String _status = '';
  String? _referenceNo;

  // OTP step state.
  final _otpControllers = List.generate(6, (_) => TextEditingController());
  final _otpFocusNodes = List.generate(6, (_) => FocusNode());
  int _seconds = 45;
  Timer? _timer;
  bool _verifying = false;

  late final AnimationController _stepAnim;

  @override
  void initState() {
    super.initState();
    _stepAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..forward();
  }

  @override
  void dispose() {
    _phone.dispose();
    _timer?.cancel();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    _stepAnim.dispose();
    super.dispose();
  }

  bool get _isCaretaker => widget.role == 'caretaker';

  String _mask(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D+'), '');
    if (digits.length < 8) return phone;
    return '${digits.substring(0, 5)}XXXXXX';
  }

  void _startTimer() {
    _timer?.cancel();
    _seconds = 45;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        if (_seconds > 0) _seconds--;
        if (_seconds == 0) t.cancel();
      });
    });
  }

  void _onOtpChange(int i, String v) {
    if (v.length == 1 && i < 5) {
      _otpFocusNodes[i + 1].requestFocus();
    }
    if (v.isEmpty && i > 0) {
      _otpFocusNodes[i - 1].requestFocus();
    }
  }

  String get _otp => _otpControllers.map((c) => c.text).join();

  Future<void> _onSendOtp() async {
    final raw = _phone.text.trim();
    debugPrint('[BdappsLogin] _onSendOtp tap, raw="$raw"');
    if (!BdappsService.isValidBdMobile(raw)) {
      setState(() => _status = 'ভুল নম্বর ফরম্যাট');
      _snack('একটি বৈধ বাংলাদেশি মোবাইল নম্বর দিন');
      return;
    }

    if (!mounted) return;
    setState(() {
      _loading = true;
      _status = 'সার্ভারের সাথে যোগাযোগ হচ্ছে…';
    });
    debugPrint('[BdappsLogin] calling BdappsService.sendOtp ...');

    Map<String, dynamic> res;
    try {
      res = await BdappsService.sendOtp(raw);
      debugPrint('[BdappsLogin] sendOtp response: $res');
    } catch (e, st) {
      debugPrint('[BdappsLogin] sendOtp threw: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = 'সার্ভারের সাথে যোগাযোগ ব্যর্থ';
      });
      _snack('নেটওয়ার্ক সমস্যা: ${e.toString()}');
      return;
    }
    if (!mounted) return;

    if (BdappsService.isAlreadyRegisteredError(res)) {
      debugPrint('[BdappsLogin] detected already-registered, completing login');
      setState(() => _status = 'নথিভুক্ত ব্যবহারকারী, সেশন তৈরি হচ্ছে…');
      await _completeLogin(raw, referenceNo: null);
      return;
    }

    setState(() => _loading = false);

    final ref = res['referenceNo']?.toString();
    final ok =
        (res['ok'] == true) || (res['success'] == true) || (ref != null && ref.isNotEmpty);

    if (!ok) {
      debugPrint('[BdappsLogin] sendOtp not ok: $res');
      setState(() => _status = 'OTP পাঠানো যায়নি');
      _snack(
        res['statusDetail']?.toString() ??
            res['message']?.toString() ??
            'OTP পাঠানো যায়নি। আবার চেষ্টা করুন।',
      );
      return;
    }

    setState(() {
      _step = 1;
      _referenceNo = ref;
      _status = '';
    });
    _startTimer();
    _stepAnim.forward(from: 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _otpFocusNodes.first.requestFocus();
    });
  }

  Future<void> _onVerifyOtp() async {
    if (_otp.length != 6) {
      _snack('৬ সংখ্যার কোড দিন');
      return;
    }
    setState(() => _verifying = true);

    debugPrint('[BdappsLogin] Verifying OTP: $_otp, Ref: $_referenceNo');

    try {
      final res = await BdappsService.verifyOtp(
        otp: _otp,
        referenceNo: _referenceNo ?? '',
      ).timeout(const Duration(seconds: 65), onTimeout: () {
        return {
          'statusCode': 'FAILED',
          'statusDetail': 'সার্ভার থেকে কোনো সাড়া পাওয়া যাচ্ছে না (Timeout)। ইন্টারনেট কানেকশন চেক করে আবার চেষ্টা করুন।'
        };
      });

      debugPrint('[BdappsLogin] Verify response: $res');

      if (!mounted) return;
      setState(() => _verifying = false);

      final statusCode = res['statusCode']?.toString().toUpperCase() ?? '';
      final subscriptionStatus =
          res['subscriptionStatus']?.toString().toUpperCase() ?? '';
      final success =
          statusCode == 'S1000' || subscriptionStatus == 'REGISTERED';

      if (!success) {
        _snack(res['statusDetail']?.toString() ?? 'ভুল কোড। আবার চেষ্টা করুন।');
        return;
      }

      await _completeLogin(
        _phone.text.trim(),
        referenceNo: _referenceNo,
      );
    } catch (e, st) {
      debugPrint('[BdappsLogin] Verify error: $e\n$st');
      if (!mounted) return;
      setState(() => _verifying = false);
      _snack('যাচাইকরণ ত্রুটি: ${e.toString()}');
    }
  }

  Future<void> _onResend() async {
    _startTimer();
    final res = await BdappsService.sendOtp(_phone.text.trim());
    if (!mounted) return;

    // Same fallback as _onSendOtp: if the platform says the number is
    // already registered, skip OTP and sign in directly.
    if (BdappsService.isAlreadyRegisteredError(res)) {
      await _completeLogin(_phone.text.trim(), referenceNo: null);
      return;
    }

    final ref = res['referenceNo']?.toString();
    if (ref != null && ref.isNotEmpty) {
      setState(() => _referenceNo = ref);
      _snack('নতুন কোড পাঠানো হয়েছে');
    } else {
      _snack(res['statusDetail']?.toString() ?? 'কোড আবার পাঠানো যায়নি');
    }
  }

  Future<void> _completeLogin(String mobile, {String? referenceNo}) async {
    setState(() {
      _loading = true;
      _status = 'অ্যাকাউন্ট তৈরি হচ্ছে…';
    });
    BdappsLoginResult result;
    try {
      result = await BdappsSessionService.instance.loginOrSignup(
        mobile: mobile,
        role: widget.role,
      );
    } catch (e) {
      debugPrint('[BdappsLogin] _completeLogin threw: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = 'অ্যাকাউন্ট তৈরি ব্যর্থ';
      });
      _snack('লগইন ব্যর্থ: ${e.toString()}');
      return;
    }
    if (!mounted) return;
    setState(() => _loading = false);

    if (!result.success) {
      _snack(result.errorMessage ?? 'লগইন ব্যর্থ হয়েছে');
      return;
    }

    // SUCCESS: flip the BDApps signed-in notifier. main.dart listens
    // to it and rebuilds with RoleRouter as the home.
    AppNavigator.markSignedIn(value: true);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        dismissDirection: DismissDirection.horizontal,
      ),
    );
  }

  void _goBackToMobile() {
    _timer?.cancel();
    setState(() {
      _step = 0;
      _referenceNo = null;
      for (final c in _otpControllers) {
        c.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = _isCaretaker ? AppColors.violet : AppColors.cyan;

    return Scaffold(
      backgroundColor: AppColors.void2,
      appBar: AppBar(
        backgroundColor: AppColors.void2,
        elevation: 0,
        foregroundColor: AppColors.ink,
        title: Text(
          _isCaretaker ? 'কেয়ারটেকার লগইন' : 'রোগী লগইন',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: AppColors.ink,
          ),
        ),
        leading: _step == 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: _goBackToMobile,
              )
            : null,
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: _step == 0
              ? _buildMobileStep(accent: accent)
              : _buildOtpStep(accent: accent),
        ),
      ),
    );
  }

  Widget _buildMobileStep({required Color accent}) {
    return SingleChildScrollView(
      key: const ValueKey('mobile'),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: accent.withValues(alpha: 0.24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _isCaretaker
                          ? Icons.favorite_rounded
                          : Icons.person_rounded,
                      color: accent,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isCaretaker
                          ? 'কেয়ারটেকার হিসেবে প্রবেশ'
                          : 'রোগী হিসেবে প্রবেশ',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'আপনার মোবাইল নম্বরে একটি OTP পাঠানো হবে। রবি ও সার্কেল গ্রাহকদের জন্য প্রযোজ্য (২.৭৮ টাকা/দিন)।',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.smoke,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'মোবাইল নম্বর',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          GlassTextField(
            hint: '01XXX XXX XXX',
            prefixText: '+88 ',
            keyboardType: TextInputType.phone,
            controller: _phone,
            maxLength: 14,
          ),
          const SizedBox(height: 28),
          AppButton(
            label: _loading ? 'অপেক্ষা করুন…' : 'OTP পাঠান',
            icon: Icons.arrow_forward_rounded,
            accent: accent,
            onPressed: _loading ? null : _onSendOtp,
          ),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 14),
            Center(
              child: Text(
                _status,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Center(
            child: TextButton.icon(
              onPressed: _loading ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('ভূমিকা বদলান'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpStep({required Color accent}) {
    return SingleChildScrollView(
      key: const ValueKey('otp'),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Text(
            'OTP যাচাই করুন',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '+880 ${_mask(_phone.text.trim())} নম্বরে ৬ সংখ্যার কোড পাঠানো হয়েছে',
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.smoke,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 28),
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (int i = 0; i < 6; i++)
                      _OtpBox(
                        controller: _otpControllers[i],
                        focusNode: _otpFocusNodes[i],
                        accent: accent,
                        onChanged: (v) => _onOtpChange(i, v),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                AppButton(
                  label: _verifying ? 'যাচাই হচ্ছে…' : 'যাচাই করুন',
                  icon: Icons.check_rounded,
                  accent: accent,
                  onPressed: _verifying ? null : _onVerifyOtp,
                ),
                if (_status.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Center(
                    child: Text(
                      _status,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.rose,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                _seconds > 0
                    ? Text(
                        'পুনঃ কোড পাঠাতে ${_seconds.toString().padLeft(2, '0')} সেকেন্ড',
                        style: const TextStyle(
                          color: AppColors.smoke,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      )
                    : TextButton(
                        onPressed: _onResend,
                        child: Text(
                          'কোড আবার পাঠান',
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
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

class _OtpBox extends StatelessWidget {
  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.accent,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Color accent;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.line),
      ),
      alignment: Alignment.center,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w900,
          color: AppColors.ink,
        ),
        decoration: const InputDecoration(
          counterText: '',
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}