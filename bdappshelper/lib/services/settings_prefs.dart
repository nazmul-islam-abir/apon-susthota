import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent preferences for app-level settings (theme, notifications,
/// language). Keeps keys in one place so every screen reads the same names.
class SettingsPrefs {
  SettingsPrefs._();

  static const _kDarkMode = 'settings.darkMode';
  static const _kNotifications = 'settings.notifications';
  static const _kLanguage = 'settings.language';

  static Future<bool> getDarkMode() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kDarkMode) ?? false;
  }

  static Future<bool> setDarkMode(bool value) async {
    final p = await SharedPreferences.getInstance();
    final ok = await p.setBool(_kDarkMode, value);
    darkModeNotifier.value = value;
    return ok;
  }

  static Future<bool> getNotifications() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kNotifications) ?? true;
  }

  static Future<bool> setNotifications(bool value) async {
    final p = await SharedPreferences.getInstance();
    return p.setBool(_kNotifications, value);
  }

  static Future<String> getLanguage() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kLanguage) ?? 'English';
  }

  static Future<bool> setLanguage(String value) async {
    final p = await SharedPreferences.getInstance();
    return p.setString(_kLanguage, value);
  }

  /// Notifier used by [main.dart] so toggling dark mode from Settings
  /// immediately rebuilds MaterialApp.
  static final ValueNotifier<bool> darkModeNotifier = ValueNotifier<bool>(false);

  static Future<void> hydrateNotifiers() async {
    darkModeNotifier.value = await getDarkMode();
  }
}