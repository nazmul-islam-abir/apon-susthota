import 'dart:convert';
import 'package:http/http.dart' as http;

/// HTTP wrapper for the BDApps CPanel backend (NADB26045).
///
/// All endpoints accept `application/x-www-form-urlencoded` POST
/// bodies and respond with JSON. This is a direct port of the
/// reference implementation in the original BDApps sample repo.
///
/// Endpoints used:
///   * send_otp.php        — request a 6-digit OTP
///   * verify_otp.php      — verify an OTP against its reference no.
///   * check_subscription  — does this number have an active
///                            subscription (REGISTERED/GRACE)?
class BdappsService {
  BdappsService._();

  /// CPanel base URL. Override here if your account uses a different
  /// app code (e.g. NADB12345).
  static const String _base = 'https://aponshusthota.byabir.com/bdApps/';

  static const Map<String, String> _headers = {
    'Content-Type': 'application/x-www-form-urlencoded',
    'Accept': 'application/json',
  };

  static const Duration _timeout = Duration(seconds: 60);

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
    final normalized = normalizeMobile(mobile);
    print('[BdappsService] Requesting OTP for: $normalized');
    final body = <String, String>{'user_mobile': normalized};
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

  /// Unsubscribes the user from BDApps (calls `unsubscribe.php` with
  /// `action=0`). After a successful unsubscribe the platform will
  /// refuse subsequent OTPs for this number until they re-subscribe.
  static Future<Map<String, dynamic>> unsubscribe(String mobile) async {
    final body = <String, String>{'user_mobile': normalizeMobile(mobile)};
    return _post('$_base/unsubscribe.php', body);
  }

  /// Returns true when the unsubscribe response indicates the operator
  /// accepted the request (statusCode `S1000` or subscriptionStatus
  /// `UNREGISTERED`).
  static bool isUnsubscribed(Map<String, dynamic> res) {
    final statusCode = res['statusCode']?.toString().toUpperCase().trim() ?? '';
    final sub = res['subscriptionStatus']?.toString().toUpperCase().trim() ?? '';
    return statusCode == 'S1000' || sub == 'UNREGISTERED';
  }

  /// Returns true when the user has an active subscription OR is in a
  /// non-`UNREGISTERED` state (e.g. `INITIAL CHARGING PENDING`,
  /// `REGISTERED`, `GRACE`).
  static bool isUserActive(Map<String, dynamic> check) {
    final status = check['subscriptionStatus']?.toString().toUpperCase().trim();
    if (status == null || status.isEmpty) return false;
    if (status == 'UNREGISTERED') return false;
    return true;
  }

  /// Returns true when the response from `send_otp.php` indicates the
  /// number is already registered on the BDApps platform (statusCode
  /// `E1351`, or a message containing "already registered"). In that
  /// case the caller should bypass OTP and sign the user in directly.
  static bool isAlreadyRegisteredError(Map<String, dynamic> res) {
    final statusCode = res['statusCode']?.toString().toUpperCase().trim() ?? '';
    final message = (res['message']?.toString() ?? '').toLowerCase();
    final detail = (res['statusDetail']?.toString() ?? '').toLowerCase();
    if (statusCode == 'E1351') return true;
    return message.contains('already registered') ||
        detail.contains('already registered');
  }

  static Future<Map<String, dynamic>> _post(
    String url,
    Map<String, String> body,
  ) async {
    try {
      print('[BdappsService] POST to $url with body: $body (timeout: $_timeout)');
      final response = await http
          .post(Uri.parse(url), headers: _headers, body: body)
          .timeout(_timeout);
      if (response.body.isEmpty) {
        return {
          'ok': false,
          'error': 'Empty response from server',
          'httpCode': response.statusCode,
          'statusCode': 'E0000',
          'statusDetail': 'Empty response from server',
        };
      }
      final decoded = jsonDecode(response.body);
      // Preserve the original PHP payload regardless of the Map's
      // runtime type — always cast through a typed copy so callers see
      // every key (statusCode, statusDetail, message, referenceNo, …)
      // even when PHP returns a `Map<dynamic, dynamic>`.
      Map<String, dynamic>? payload;
      if (decoded is Map) {
        payload = Map<String, dynamic>.from(decoded);
      }
      if (payload != null) {
        payload['httpCode'] = response.statusCode;
        payload['ok'] = response.statusCode == 200 &&
            payload['success'] != false &&
            (payload['statusCode']?.toString().toUpperCase().startsWith('E') != true);
        return payload;
      }
      return {
        'ok': false,
        'error': 'Unexpected response',
        'raw': response.body,
        'httpCode': response.statusCode,
        'statusCode': 'E0000',
        'statusDetail': 'Unexpected response shape',
      };
    } catch (e) {
      return {
        'ok': false,
        'error': e.toString(),
        'statusCode': 'E0000',
        'statusDetail': e.toString(),
      };
    }
  }
}
