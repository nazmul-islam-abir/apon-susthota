import 'dart:async';
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../widgets/gradient_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/app_button.dart';
import '../services/bdapps_service.dart';
import '../services/auth_service.dart';
import 'register_screen.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({
    super.key,
    required this.phone,
    required this.referenceNo,
  });

  final String phone;
  final String referenceNo;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _controllers = List.generate(6, (_) => TextEditingController());
  final _focusNodes = List.generate(6, (_) => FocusNode());
  int _seconds = 45;
  Timer? _timer;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
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

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _onChange(int i, String v) {
    if (v.length == 1 && i < 5) {
      _focusNodes[i + 1].requestFocus();
    }
    if (v.isEmpty && i > 0) {
      _focusNodes[i - 1].requestFocus();
    }
  }

  String get _otp => _controllers.map((c) => c.text).join();

  Future<void> _onVerify() async {
    if (_otp.length != 6) {
      _snack('Please enter the 6-digit code');
      return;
    }

    setState(() => _verifying = true);
    final res = await BdappsService.verifyOtp(
      otp: _otp,
      referenceNo: widget.referenceNo,
    );

    final statusCode = res['statusCode']?.toString().toUpperCase() ?? '';
    final statusDetail = res['statusDetail']?.toString() ?? '';
    final subscriptionStatus =
        res['subscriptionStatus']?.toString().toUpperCase() ?? '';
    final success = statusCode == 'S1000' || subscriptionStatus == 'REGISTERED';

    if (!mounted) return;
    setState(() => _verifying = false);

    if (!success) {
      _snack(statusDetail.isNotEmpty ? statusDetail : 'Invalid OTP. Try again.');
      return;
    }

    await AuthService.instance.markAuthenticated(subscribed: true);
    if (!mounted) return;

    // OtpScreen is only reachable for new users (login screen bypasses
    // it for existing subscribers), so go to the registration flow first.
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
  }

  Future<void> _onResend() async {
    _startTimer();
    final res = await BdappsService.sendOtp(widget.phone);
    final ref = res['referenceNo']?.toString();
    if (ref != null && ref.isNotEmpty) {
      await AuthService.instance.setReferenceNo(ref);
    }
    if (!mounted) return;
    _snack(ref != null && ref.isNotEmpty
        ? 'A new code has been sent'
        : (res['statusDetail']?.toString() ?? 'Could not resend code'));
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  /// Masks the middle digits of a phone number for display: 01812XXXXXX.
  String _mask(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D+'), '');
    if (digits.length < 8) return phone;
    return '${digits.substring(0, 5)}XXXXXX';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.lg),
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const Text(
                  'Verify your number',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Enter the 6-digit code we sent to\n+880 ${_mask(widget.phone)}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                GlassCard(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (int i = 0; i < 6; i++)
                            _OtpBox(
                              controller: _controllers[i],
                              focusNode: _focusNodes[i],
                              onChanged: (v) => _onChange(i, v),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      AppButton(
                        label: _verifying ? 'Verifying…' : 'Verify',
                        icon: Icons.check_rounded,
                        onPressed: _verifying ? null : _onVerify,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _seconds > 0
                          ? Text(
                              'Resend code in 00:${_seconds.toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            )
                          : TextButton(
                              onPressed: _onResend,
                              child: const Text(
                                'Resend code',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OtpBox extends StatelessWidget {
  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.glassWhite, AppColors.glassWhiteSoft],
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: AppColors.glassShadow,
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Center(
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 1,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
          decoration: const InputDecoration(
            counterText: '',
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}
