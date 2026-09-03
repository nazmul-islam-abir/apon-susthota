/// A tiny singleton that owns the app's root `NavigatorState`.
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

import '../screens/medicine_screen.dart';
import '../screens/water_screen.dart';
import 'app_events.dart';

class AppNavigator {
  AppNavigator._();

  /// Single root navigator key. Wired into the root `MaterialApp`.
  /// Settable so `main.dart` can re-use the same key it already owns
  /// for the exit-confirmer flow, avoiding two competing globals.
  static GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();

  /// Notifier flipped by `main.dart` whenever the BDApps session state
  /// changes. Any code path (login button, logout button, profile
  /// completion save) can `signedInNotifier.value = true|false` to
  /// flip the app's root gate without having to find a BuildContext.
  static ValueNotifier<bool>? signedInNotifier;

  /// Re-point the global key (called from `main.dart` after the
  /// `_AponSusthotaAppState` builds, so the scheduler can reach the
  /// same `NavigatorState` the app is actually using).
  static void attach(GlobalKey<NavigatorState> sourceKey) {
    key = sourceKey;
  }

  /// Wire up the global signed-in notifier so any code path can flip
  /// it. Called from `main.dart`.
  static void attachSignedInNotifier(ValueNotifier<bool> notifier) {
    signedInNotifier = notifier;
  }

  /// Convenience for sign-in code paths (e.g. _completeLogin). Flips
  /// the notifier and pops the stack to root.
  ///
  /// Why the popUntil matters:
  ///   The root `MaterialApp` uses `home:` (not `pages:`), so
  ///   ValueListenableBuilder swaps the home widget when the notifier
  ///   flips — but pushed routes (OTP screen, login screen) above the
  ///   home remain mounted. The user sees the OTP screen even though
  ///   `signedInNotifier.value == true`. Popping the stack in a
  ///   post-frame callback clears those leftovers so the new
  ///   `RoleRouter` / `HomeShell` lands cleanly.
  static void markSignedIn({bool value = true}) {
    signedInNotifier?.value = value;
    if (value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Guard: pop only if we haven't already popped to root.
        final nav = key.currentState;
        if (nav != null && nav.canPop()) {
          nav.popUntil((route) => route.isFirst);
        }
      });
    }
  }

  /// Convenience for sign-out code paths (drawer logout, profile logout,
  /// caretaker logout). Flips the notifier to false so the ValueListenableBuilder
  /// in main.dart swaps back to RoleLandingScreen.
  static void markSignedOut() {
    final n = signedInNotifier;
    debugPrint('[AppNavigator] markSignedOut called. notifier=${n != null ? "present (was=${n.value})" : "NULL"}');
    if (n != null) n.value = false;
  }

  /// Convenience for callers that already have a context — pushes
  /// the given route on the root navigator so it survives the
  /// current tab being unmounted.
  static Future<T?> push<T>(WidgetBuilder builder) {
    final nav = key.currentState;
    if (nav == null) return Future<T?>.value(null);
    return nav.push<T>(MaterialPageRoute(builder: builder));
  }

  /// Push a route by name on the root navigator, popping everything
  /// above the first route so a notification tap always lands on a
  /// fresh stack regardless of which tab was active.
  static Future<T?> pushNamed<T>(String routeName) {
    final nav = key.currentState;
    if (nav == null) return Future<T?>.value(null);
    return nav.pushNamedAndRemoveUntil<T>(routeName, (r) => r.isFirst);
  }

  /// Called by `LocalNotifications` when the user taps a reminder.
  /// Decodes the `v1:<type>:<id>:<iso>` payload and routes to the
  /// right screen.
  ///
  /// Routing strategy:
  ///   * medicine → push `MedicineScreen` (it's not a tab).
  ///   * meal     → ask HomeShell to switch to tab 1.
  ///   * workout  → ask HomeShell to switch to tab 2.
  ///   * water    → push `WaterScreen` (it's not a tab).
  ///   * test     → no-op.
  ///
  /// Returns true if it took an action.
  static bool pushTaskDestination(String payload) {
    final parts = payload.split(':');
    if (parts.length < 3 || parts[0] != 'v1') return false;
    switch (parts[1]) {
      case 'medicine':
        push((_) => const MedicineScreen());
        return true;
      case 'meal':
        AppEvents.requestTab(1); // meal tab
        return true;
      case 'workout':
        AppEvents.requestTab(2); // workout tab
        return true;
      case 'water':
        push((_) => const WaterScreen());
        return true;
      case 'test':
        return false;
    }
    return false;
  }
}