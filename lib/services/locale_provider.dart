import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the active app locale and persists the user's choice to
/// SharedPreferences so it survives app restarts.
///
/// Default is Bangla (`bn`) — the language the app launched in and the
/// one every screen is hardcoded in. The pill on the dashboard calls
/// [setByCode] to switch between `'bn'` and `'en'`; everything that
/// watches this provider rebuilds with the new locale.
class LocaleProvider extends ChangeNotifier {
  static const String _prefsKey = 'app.locale';

  static const Locale _bangla = Locale('bn');
  static const Locale _english = Locale('en');

  Locale _locale = _bangla;
  bool _hydrated = false;

  LocaleProvider();

  Locale get locale => _locale;
  String get languageCode => _locale.languageCode;
  bool get isHydrated => _hydrated;

  /// Read the persisted choice once on startup. Safe to call multiple
  /// times — only the first call performs the I/O.
  Future<void> hydrate() async {
    if (_hydrated) return;
    try {
      final p = await SharedPreferences.getInstance();
      final code = p.getString(_prefsKey);
      if (code == 'en') {
        _locale = _english;
      } else {
        _locale = _bangla;
      }
    } catch (e) {
      debugPrint('LocaleProvider.hydrate failed: $e');
    } finally {
      _hydrated = true;
      notifyListeners();
    }
  }

  Future<void> setByCode(String code) async {
    final next = code == 'en' ? _english : _bangla;
    if (next.languageCode == _locale.languageCode) return;
    _locale = next;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_prefsKey, next.languageCode);
    } catch (e) {
      debugPrint('LocaleProvider.setByCode persist failed: $e');
    }
  }

  Future<void> setLocale(Locale next) => setByCode(next.languageCode);
}
