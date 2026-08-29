/// A tiny singleton that owns the app's root `NavigatorState`.
///
///
/// The `MoodTaskScheduler` (and any other foreground service in
/// the future) needs a way to push routes when the user might be
/// on any tab — dashboard, meal, workout, analytics, AI chat. The
/// cleanest way to do that without being handed a `BuildContext`
/// from outside the widget tree is to register the root
/// `MaterialApp.navigatorKey` once at startup and look it up from
/// anywhere.
///
/// Wired up in `main.dart` via:
/// ```dart
/// MaterialApp(
///   navigatorKey: AppNavigator.key,
///   ...
/// )
/// ```
library;

import 'package:flutter/material.dart';

class AppNavigator {
  AppNavigator._();

  /// Single root navigator key. Wired into the root `MaterialApp`.
  /// Settable so `main.dart` can re-use the same key it already owns
  /// for the exit-confirmer flow, avoiding two competing globals.
  static GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();

  /// Re-point the global key (called from `main.dart` after the
  /// `_AponSusthotaAppState` builds, so the scheduler can reach the
  /// same `NavigatorState` the app is actually using).
  static void attach(GlobalKey<NavigatorState> sourceKey) {
    key = sourceKey;
  }

  /// Convenience for callers that already have a context — pushes
  /// the given route on the root navigator so it survives the
  /// current tab being unmounted.
  static Future<T?> push<T>(WidgetBuilder builder) {
    final nav = key.currentState;
    if (nav == null) return Future<T?>.value(null);
    return nav.push<T>(MaterialPageRoute(builder: builder));
  }
}