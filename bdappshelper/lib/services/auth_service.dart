import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'bdapps_service.dart';
import 'hive_store.dart';

/// Holds the authenticated session for the lifetime of the app.
class AuthService extends ChangeNotifier {
  AuthService._();

  static final AuthService instance = AuthService._();

  static const _kPhone = 'auth.phone';
  static const _kReferenceNo = 'auth.referenceNo';
  static const _kIsAuthed = 'auth.isAuthed';
  static const _kIsSubscribed = 'auth.isSubscribed';

  String? _phone;
  String? _referenceNo;
  bool _isAuthenticated = false;
  bool _isSubscribed = false;
  bool _hydrated = false;

  String? get phone => _phone;
  String? get referenceNo => _referenceNo;
  bool get isAuthenticated => _isAuthenticated;
  bool get isSubscribed => _isSubscribed;
  bool get isHydrated => _hydrated;

  Future<void> hydrate() async {
    if (_hydrated) return;
    final prefs = await SharedPreferences.getInstance();
    _phone = prefs.getString(_kPhone);
    _referenceNo = prefs.getString(_kReferenceNo);
    _isAuthenticated = prefs.getBool(_kIsAuthed) ?? false;
    _isSubscribed = prefs.getBool(_kIsSubscribed) ?? false;
    _hydrated = true;
    notifyListeners();
  }

  /// Force-checks the subscription status with BDApps.
  /// Returns false if the user is no longer subscribed (unregistered).
  Future<bool> revalidateSubscription() async {
    if (!_isAuthenticated || _phone == null) return true;

    try {
      final res = await BdappsService.checkSubscription(_phone!);
      final stillActive = BdappsService.isUserActive(res);

      if (!stillActive) {
        // User unsubscribed externally! Log them out immediately.
        await signOut();
        return false;
      }
      
      // Update local state if it changed (e.g. from GRACE back to REGISTERED)
      if (_isSubscribed != stillActive) {
        await markSubscribed(stillActive);
      }
      return true;
    } catch (e) {
      // If network error, don't kick them out, just assume they are fine for now
      return true;
    }
  }

  Future<void> setPhone(String phone) async {
    _phone = phone;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPhone, phone);
    notifyListeners();
  }

  Future<void> setReferenceNo(String ref) async {
    _referenceNo = ref;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kReferenceNo, ref);
    notifyListeners();
  }

  Future<void> markAuthenticated({bool subscribed = true}) async {
    _isAuthenticated = true;
    _isSubscribed = subscribed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIsAuthed, true);
    await prefs.setBool(_kIsSubscribed, subscribed);
    // Pre-open the user's Hive boxes so the first screen render does
    // not race the lazy box-opening.
    if (_phone != null && _phone!.isNotEmpty) {
      await HiveStore.instance.preOpenUser(_phone!);
    }
    notifyListeners();
  }

  Future<void> markSubscribed(bool value) async {
    _isSubscribed = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIsSubscribed, value);
    notifyListeners();
  }

  Future<void> signOut() async {
    // Clear any cached boxes for the previous user.
    final previousPhone = _phone;
    _phone = null;
    _referenceNo = null;
    _isAuthenticated = false;
    _isSubscribed = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPhone);
    await prefs.remove(_kReferenceNo);
    await prefs.setBool(_kIsAuthed, false);
    await prefs.setBool(_kIsSubscribed, false);
    if (previousPhone != null && previousPhone.isNotEmpty) {
      await HiveStore.instance.clearPhone(previousPhone);
    }
    notifyListeners();
  }
}
