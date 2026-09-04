import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/bdapps/bdapps_service.dart';
import '../../theme/app_theme.dart';

/// Lets a user check their BDApps subscription status by entering the
/// mobile number they registered with.
///
/// Calls `BdappsService.check_subscription.php` and renders the
/// response (`subscriptionStatus`, `statusCode`, `statusDetail`, …) in
/// a clear card so the user knows whether they are REGISTERED,
/// GRACE, UNREGISTERED, or whether the lookup failed.
class SubscriptionCheckScreen extends StatefulWidget {
  const SubscriptionCheckScreen({super.key});

  @override
  State<SubscriptionCheckScreen> createState() =>
      _SubscriptionCheckScreenState();
}

class _SubscriptionCheckScreenState extends State<SubscriptionCheckScreen> {
  final _phone = TextEditingController();
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _result;
  String _normalized = '';

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final raw = _phone.text.trim();
    if (!BdappsService.isValidBdMobile(raw)) {
      setState(() => _error = 'একটি বৈধ বাংলাদেশি মোবাইল নম্বর দিন (01XXXXXXXXX)');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    final normalized = BdappsService.normalizeMobile(raw);
    final res = await BdappsService.checkSubscription(normalized);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _normalized = normalized;
      _result = res;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isActive = BdappsService.isUserActive(_result ?? const {});
    final accent = _result == null
        ? AppColors.violet
        : isActive
            ? AppColors.mint
            : AppColors.rose;

    return Scaffold(
      backgroundColor: AppColors.void2,
      appBar: AppBar(
        backgroundColor: AppColors.void2,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.ink),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'সাবস্ক্রিপশন চেক',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: AppColors.ink,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.violet.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: AppColors.violet.withValues(alpha: 0.2),
                  ),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      color: AppColors.violet,
                      size: 22,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'আপনার BDApps সাবস্ক্রিপশন বর্তমানে সক্রিয় আছে কি না দেখতে নম্বর দিন। সার্ভার থেকে সরাসরি স্ট্যাটাস দেখানো হবে।',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.smoke,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'মোবাইল নম্বর',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.smoke,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
                  LengthLimitingTextInputFormatter(14),
                ],
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
                decoration: InputDecoration(
                  hintText: '01XXXXXXXXX',
                  prefixIcon: const Padding(
                    padding: EdgeInsets.fromLTRB(16, 18, 8, 18),
                    child: Text(
                      '+88',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.smoke,
                      ),
                    ),
                  ),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 0, minHeight: 0),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: const BorderSide(color: AppColors.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide:
                        const BorderSide(color: AppColors.violet, width: 1.5),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.danger,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              _PrimaryCta(
                label: 'সাবস্ক্রিপশন চেক করুন',
                loading: _loading,
                onPressed: _loading ? null : _check,
              ),
              if (_result != null) ...[
                const SizedBox(height: 24),
                _ResultCard(
                  result: _result!,
                  normalized: _normalized,
                  isActive: isActive,
                  accent: accent,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Raw response',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.smoke,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        const JsonEncoder.withIndent('  ').convert(_result!),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.smoke,
                          fontFamily: 'monospace',
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const Text(
                'REGISTERED / GRACE মানে আপনার সাবস্ক্রিপশন সক্রিয়। UNREGISTERED মানে আবার সাবস্ক্রাইব করা প্রয়োজন।',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.smoke,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final Map<String, dynamic> result;
  final String normalized;
  final bool isActive;
  final Color accent;

  const _ResultCard({
    required this.result,
    required this.normalized,
    required this.isActive,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final status = (result['subscriptionStatus'] ?? '').toString();
    final statusCode = (result['statusCode'] ?? '').toString();
    final detail = (result['statusDetail'] ?? '').toString();
    final ok = result['ok'] == true;
    final message = (result['message'] ?? '').toString();

    final headline = status.isEmpty
        ? (ok ? 'লুকআপ সম্পন্ন' : 'লুকআপ ব্যর্থ')
        : status;
    final verdict = isActive ? 'সক্রিয় সাবস্ক্রিপশন' : 'সাবস্ক্রিপশন নেই';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isActive
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  color: accent,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      verdict,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: accent,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      headline,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Row(label: 'নম্বর', value: normalized),
          _Row(label: 'statusCode', value: statusCode),
          if (detail.isNotEmpty) _Row(label: 'statusDetail', value: detail),
          if (message.isNotEmpty) _Row(label: 'message', value: message),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.smoke,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryCta extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  const _PrimaryCta({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return SizedBox(
      height: 56,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Ink(
            decoration: BoxDecoration(
              gradient: disabled
                  ? null
                  : const LinearGradient(
                      colors: [AppColors.violet, AppColors.violetDeep],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              color: disabled ? AppColors.surfaceHigh : null,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: disabled ? AppColors.line : Colors.transparent,
              ),
            ),
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(AppColors.onAccent),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.search_rounded,
                          color: disabled ? AppColors.smoke : AppColors.onAccent,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color:
                                disabled ? AppColors.smoke : AppColors.onAccent,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
