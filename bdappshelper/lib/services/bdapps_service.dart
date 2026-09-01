import 'dart:convert';
import 'package:http/http.dart' as http;

/// HTTP wrapper for the BDApps CPanel backend (NADB26045).
///
/// All endpoints accept `application/x-www-form-urlencoded` POST bodies and
/// respond with JSON. See `mybackend/index.php` for the full contract.
class BdappsService {
  BdappsService._();

  static const String _base = 'https://bdappsdigitalapps.com/NADB26045';

  static const Map<String, String> _headers = {
    'Content-Type': 'application/x-www-form-urlencoded',
    'Accept': 'application/json',
  };

  static const Duration _timeout = Duration(seconds: 30);

  /// Normalizes a Bangladeshi mobile number to `8801XXXXXXXXX` form.
  /// Accepts `01XXXXXXXXX`, `8801XXXXXXXXX`, or `881XXXXXXXXX`.
  static String normalizeMobile(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D+'), '');
    if (digits.startsWith('880') && digits.length == 13) {
      return digits;
    }
    if (digits.startsWith('88') && digits.length == 12) {
      return '8${digits.substring(2)}';
    }
    if (digits.startsWith('0') && digits.length == 11) {
      return '880${digits.substring(1)}';
    }
    return digits;
  }

  /// Validates the form `01XXXXXXXXX` (11 digits, starts with 01[3-9]).
  static bool isValidBdMobile(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D+'), '');
    return RegExp(r'^01[3-9][0-9]{8}$').hasMatch(digits);
  }

  /// Requests an OTP be sent to the user. Returns the BDApps response or a
  /// network error.
  static Future<Map<String, dynamic>> sendOtp(String mobile) async {
    final body = <String, String>{'user_mobile': normalizeMobile(mobile)};
    return _post('$_base/send_otp.php', body);
  }

  /// Verifies the OTP against the BDApps reference number.
  static Future<Map<String, dynamic>> verifyOtp({
    required String otp,
    required String referenceNo,
  }) async {
    final body = <String, String>{
      'Otp': otp,
      'referenceNo': referenceNo,
    };
    return _post('$_base/verify_otp.php', body);
  }

  /// Checks whether the subscriber is currently REGISTERED.
  static Future<Map<String, dynamic>> checkSubscription(String mobile) async {
    final body = <String, String>{'user_mobile': normalizeMobile(mobile)};
    return _post('$_base/check_subscription.php', body);
  }

  /// Returns true when the user has an active subscription OR is in a
  /// non-`UNREGISTERED` state (e.g. `INITIAL CHARGING PENDING`, `REGISTERED`,
  /// `GRACE`). Only `UNREGISTERED` should go through the OTP flow.
  ///
  /// Relies on `subscriptionStatus` rather than `isSubscribed` because the
  /// operator returns `isSubscribed: false` for transitional states like
  /// `INITIAL CHARGING PENDING` even though the user shouldn't be re-OTP'd.
  static bool isUserActive(Map<String, dynamic> check) {
    final status = check['subscriptionStatus']?.toString().toUpperCase().trim();
    if (status == null || status.isEmpty) return false;
    if (status == 'UNREGISTERED') return false;
    return true;
  }

  /// Unsubscribes a user from the service.
  static Future<Map<String, dynamic>> unsubscribe(String mobile) async {
    final body = <String, String>{'user_mobile': normalizeMobile(mobile)};
    return _post('$_base/unsubscribe.php', body);
  }

  static Future<Map<String, dynamic>> _post(
    String url,
    Map<String, String> body,
  ) async {
    try {
      final response = await http
          .post(Uri.parse(url), headers: _headers, body: body)
          .timeout(_timeout);
      if (response.body.isEmpty) {
        return {
          'ok': false,
          'error': 'Empty response from server',
          'httpCode': response.statusCode,
        };
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        decoded['httpCode'] = response.statusCode;
        decoded['ok'] = response.statusCode == 200;
      }
      return decoded is Map<String, dynamic>
          ? decoded
          : {'ok': false, 'error': 'Unexpected response', 'raw': response.body};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }
}
