import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists which parts of the first-launch flow the user has already
/// seen so we only show the marketing intro / hero video once.
///
/// Storage keys are namespaced under `onboarding.` so they don't
/// collide with anything else persisted by `shared_preferences`.
class OnboardingGate {
  OnboardingGate._();

  static const String _kIntroSeen = 'onboarding.intro_seen';
  static const String _kVideoSeen = 'onboarding.video_seen';

  static Future<bool> isIntroSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kIntroSeen) ?? false;
  }

  static Future<void> markIntroSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIntroSeen, true);
  }

  static Future<bool> isVideoSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kVideoSeen) ?? false;
  }

  static Future<void> markVideoSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kVideoSeen, true);
  }

  /// Wipes both flags. Useful for "Reset onboarding" debug actions
  /// or for testing the cold-start flow on a fresh install simulation.
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kIntroSeen);
    await prefs.remove(_kVideoSeen);
    _controller.reset();
  }

  /// In-memory step the current run is on. Set via the controller
  /// methods below. The root gate ([AponSusthotaApp]) watches this
  /// and rebuilds its `home:` accordingly.
  ///
  /// IMPORTANT: We deliberately do NOT use `Navigator.pushReplacement`
  /// inside the onboarding screens to advance to the next step. That
  /// messes up `MaterialApp.home` because replacing the home route
  /// leaves the underlying `home` reference stale — subsequent
  /// `popUntil` calls then "restore" the dead home route instead of
  /// landing on the new role-landing / dashboard.
  static final OnboardingFlowController _controller =
      OnboardingFlowController();

  static OnboardingFlowController get flow => _controller;
}

/// Reactive controller the root gate listens to. Each step's screen
/// calls one of the `markX` methods after it completes, which flips
/// `step` and triggers the gate to swap its `home:` to the next
/// widget.
enum OnboardingFlowStep { intro, video, done }

class OnboardingFlowController extends ChangeNotifier {
  OnboardingFlowStep _step = OnboardingFlowStep.intro;
  OnboardingFlowStep get step => _step;

  void markIntroDone() {
    if (_step != OnboardingFlowStep.video && _step != OnboardingFlowStep.done) {
      _step = OnboardingFlowStep.video;
      notifyListeners();
    }
  }

  void markVideoDone() {
    if (_step != OnboardingFlowStep.done) {
      _step = OnboardingFlowStep.done;
      notifyListeners();
    }
  }

  /// Re-arms the controller for a forced re-run (used after
  /// [OnboardingGate.reset]).
  void reset() {
    _step = OnboardingFlowStep.intro;
    notifyListeners();
  }
}

