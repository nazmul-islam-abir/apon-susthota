import 'package:flutter/material.dart';

import '../services/app_navigator.dart';
import '../services/bdapps/bdapps_service.dart';
import '../services/bdapps/bdapps_session_service.dart';

/// Shared confirmation + execution flow for the three account-management
/// actions exposed on both the **patient** and **caretaker** profile
/// screens:
///
///   * [confirmLogout]    – show the logout dialog.
///   * [runUnsubscribe]   – show the unsubscribe dialog, then call
///                          `BdappsService.unsubscribe` + local
///                          `BdappsSessionService.signOut`.
///   * [runDeleteAccount] – two-step confirmation (warning + typed
///                          last-4-digits), then BDApps unsubscribe +
///                          `bdapps_delete_account` RPC + local
///                          `signOut`.
///
/// All three return `true` when the user confirmed AND the local
/// sign-out completed (so the gate in `main.dart` has flipped to the
/// landing screen). Returning `false` means either the user cancelled
/// or an early failure short-circuited the flow.
class AccountActions {
  AccountActions._();

  // ====================================================================
  // 1. Logout
  // ====================================================================

  static Future<bool> confirmLogout(BuildContext context) async {
    final ok = await _confirm(
      context,
      title: 'লগআউট নিশ্চিত করুন',
      body: 'আপনি কি সত্যিই অ্যাকাউন্ট থেকে বের হয়ে যেতে চান?',
      confirmLabel: 'হ্যাঁ, লগআউট',
      destructive: true,
    );
    if (!ok) return false;

    try {
      await BdappsSessionService.instance.signOut();
      if (context.mounted) AppNavigator.markSignedOut();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ====================================================================
  // 2. Unsubscribe (two-step)
  // ====================================================================

  static Future<bool> runUnsubscribe(BuildContext context) async {
    final first = await _confirm(
      context,
      title: 'সাবস্ক্রিপশন বাতিল করুন',
      body:
          'আপনার দৈনিক ২.৭৮ টাকার সাবস্ক্রিপশন বাতিল হয়ে যাবে। অ্যাপের সব ফিচার আর '
          'ব্যবহার করতে পারবেন না।\n\nআপনার সার্ভারের সব ডেটা (প্রোফাইল, খাবার, ওষুধ, '
          'ব্যায়াম) সংরক্ষিত থাকবে — পরে আবার OTP দিয়ে সাবস্ক্রাইব করে লগইন করতে পারবেন।',
      confirmLabel: 'হ্যাঁ, বাতিল করুন',
      destructive: true,
    );
    if (!first) return false;

    final mobile = BdappsSessionService.instance.mobile;
    if (mobile == null || mobile.isEmpty) {
      if (!context.mounted) return false;
      _toast(context, 'মোবাইল নম্বর পাওয়া যায়নি');
      return false;
    }

    if (!context.mounted) return false;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await BdappsService.unsubscribe(mobile);
      final ok = BdappsService.isUnsubscribed(res);
      if (!context.mounted) return false;
      if (ok) {
        messenger.showSnackBar(const SnackBar(
          content: Text(
            'সাবস্ক্রিপশন সফলভাবে বাতিল হয়েছে।',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ));
        await BdappsSessionService.instance.signOut();
        if (context.mounted) AppNavigator.markSignedOut();
        return true;
      }
      messenger.showSnackBar(SnackBar(
        content: Text(
          res['statusDetail']?.toString() ??
              res['message']?.toString() ??
              'সাবস্ক্রিপশন বাতিল করা যায়নি',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ));
      return false;
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('নেটওয়ার্ক সমস্যা: ${e.toString()}'),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return false;
    }
  }

  // ====================================================================
  // 3. Delete account (warning + typed last-4-digits confirm)
  // ====================================================================

  static Future<bool> runDeleteAccount(BuildContext context) async {
    final mobile = BdappsSessionService.instance.mobile;
    if (mobile == null || mobile.isEmpty) {
      _toast(context, 'মোবাইল নম্বর পাওয়া যায়নি');
      return false;
    }
    // Last 4 digits of the canonical mobile — used as the typed
    // confirmation key, e.g. "8801712345678" → "5678".
    final last4 = _lastNDigits(mobile, 4);
    if (last4.length != 4) {
      _toast(context, 'মোবাইল নম্বর সঠিক নয়');
      return false;
    }

    // --- Step 1: warning dialog ---
    final warning = await _confirm(
      context,
      title: 'অ্যাকাউন্ট মুছে ফেলুন',
      body:
          'আপনার BDApps সাবস্ক্রিপশন বাতিল হবে এবং আপনার সব সার্ভার ডেটা (প্রোফাইল, '
          'খাবার, ওষুধ, ব্যায়াম, সেটিংস) স্থায়ীভাবে মুছে যাবে।\n\n'
          'এই নম্বর দিয়ে আবার নতুন অ্যাকাউন্ট খোলা যাবে (অন্য ভূমিকায় — রোগী '
          'বা পরিচর্যাকারী)।\n\n'
          'এই কাজ ফিরিয়ে আনা যাবে না।',
      confirmLabel: 'হ্যাঁ, মুছে ফেলতে চাই',
      destructive: true,
    );
    if (!warning) return false;

    // --- Step 2: typed-confirmation ---
    if (!context.mounted) return false;
    final typed = await _typedConfirm(
      context,
      hint: last4,
      expected: last4,
      title: 'অ্যাকাউন্ট মুছে ফেলুন',
    );
    if (typed == null) return false;
    if (typed.trim() != last4) {
      if (!context.mounted) return false;
      _toast(context, 'ডিজিট মেলেনি — বাতিল করা হলো');
      return false;
    }

    // --- Step 3: actually delete (unsubscribe + RPC + signOut) ---
    if (!context.mounted) return false;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
      content: Text(
        'অ্যাকাউন্ট মুছে ফেলা হচ্ছে…',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: 2),
    ));

    try {
      final result = await BdappsSessionService.instance.deleteAccount();
      if (!context.mounted) return false;
      if (result.success) {
        messenger.showSnackBar(const SnackBar(
          content: Text(
            'অ্যাকাউন্ট সফলভাবে মুছে ফেলা হয়েছে।',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ));
        AppNavigator.markSignedOut();
        return true;
      }
      messenger.showSnackBar(SnackBar(
        content: Text(
          result.errorMessage ?? 'অ্যাকাউন্ট মুছে ফেলা যায়নি',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ));
      return false;
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('নেটওয়ার্ক সমস্যা: ${e.toString()}'),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return false;
    }
  }

  // ====================================================================
  // Internal helpers
  // ====================================================================

  /// Plain confirmation dialog with title + body + Yes/No buttons.
  /// Returns true when the user picked the destructive confirm action.
  static Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
    required bool destructive,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Text(
          body,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('না'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor:
                  destructive ? const Color(0xFFFF5252) : null,
            ),
            child: Text(
              confirmLabel,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
    return result == true;
  }

  /// Typed-confirmation dialog: the user must type [expected]
  /// correctly before the destructive button enables.
  ///
  /// Returns the typed string when the user confirms, or `null` when
  /// they cancel.
  static Future<String?> _typedConfirm(
    BuildContext context, {
    required String title,
    required String hint,
    required String expected,
  }) async {
    final controller = TextEditingController();
    final canConfirm = ValueNotifier<bool>(false);

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                  fontSize: 14,
                ),
                children: [
                  const TextSpan(
                      text: 'নিশ্চিত করতে আপনার মোবাইল নম্বরের শেষ ৪ ডিজিট '),
                  TextSpan(
                    text: hint,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                    ),
                  ),
                  const TextSpan(text: ' — লিখুন।'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 8,
              ),
              decoration: const InputDecoration(
                counterText: '',
                hintText: '••••',
                hintStyle: TextStyle(letterSpacing: 8),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide:
                      BorderSide(color: Color(0xFFE9ECEF)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide:
                      BorderSide(color: Color(0xFF1F3D2B), width: 2),
                ),
              ),
              onChanged: (_) {
                canConfirm.value = controller.text.trim() == expected;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('বাতিল'),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: canConfirm,
            builder: (_, enabled, __) => TextButton(
              onPressed:
                  enabled ? () => Navigator.pop(ctx, controller.text) : null,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFFF5252),
              ),
              child: const Text(
                'মুছে ফেলুন',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
    canConfirm.dispose();
    return result;
  }

  /// Last N digits of [mobile] (digits-only). Returns '' if fewer.
  static String _lastNDigits(String mobile, int n) {
    final digits = mobile.replaceAll(RegExp(r'\D+'), '');
    if (digits.length < n) return digits;
    return digits.substring(digits.length - n);
  }

  static void _toast(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        message,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ));
  }
}
