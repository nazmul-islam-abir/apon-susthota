/// Tracks the user's bottom-nav tab history so the Android system back
/// gesture can "snap back through tabs" the same way it pops a Navigator
/// route.
///
/// Two shells (`HomeShell` for patients, `CaretakerShell` for caretakers)
/// use an `IndexedStack` of bottom-nav tabs. Switching tabs does NOT
/// push a Navigator route, so a vanilla `PopScope` would fall straight
/// through to the exit dialog. This mixin makes tab taps behave like a
/// stack — tap Dashboard → Workout → AI, then back, and the user lands
/// on Workout (not the exit dialog).
///
/// Usage:
///
/// ```dart
/// class _HomeShellState extends State<HomeShell>
///     with TabHistoryMixin {
///   int _index = 0;
///   @override int get tabCount => _navItems.length;
///   @override int get currentTabIndex => _index;
///   @override void selectTab(int next) { setState(() => _index = next); }
///
///   @override
///   Widget build(BuildContext context) {
///     return Scaffold(
///       body: IndexedStack(...),
///       bottomNavigationBar: ...(onTap: onTabTapped),
///     );
///   }
///
///   @override
///   void dispose() {
///     clearTabHistory();
///     super.dispose();
///   }
/// }
/// ```
///
/// Then any widget in the tree (e.g. `ExitConfirmer`, `BackScaffold`)
/// can call `TabHistory.maybePop(context)` to ask the active shell to
/// pop one tab off its history. Returns `false` when the history is
/// already empty so the caller knows to show the exit popup.
library;

import 'package:flutter/widgets.dart';

/// Backend interface — implemented by anything that mixes in
/// [TabHistoryMixin] and is registered with `TabHistory.attach`. Public
/// because Dart's `mixin M implements X` requires `X` to be public.
abstract class TabHistoryBackend {
  bool popTabHistory();
}

/// Static facade so widgets that aren't part of the shell (e.g.
/// `ExitConfirmer`, `BackScaffold`) can pop the active shell's tab
/// history without holding a reference to it.
///
/// Design note: we deliberately use a *static singleton* rather than a
/// marker-state pattern because Dart's `findAncestorStateOfType<T>()`
/// requires `T` to be a concrete subtype. Implementing a marker
/// `abstract class TabHistoryHost implements TabHistoryMixin<W>` from
/// two different `State<X>` classes causes "conflicting generic
/// interfaces" errors. The static reference bypasses this — exactly
/// one shell is "active" at a time (the patient OR the caretaker), so
/// a single pointer suffices.
class TabHistory {
  TabHistory._();

  /// Currently-active shell, or `null` if no shell is mounted. Set by
  /// a shell's `initState` via `attach(this)` and cleared by its
  /// `dispose` via `detach(this)`. Only one shell is ever active (the
  /// patient vs caretaker choice is exclusive), so a single pointer
  /// is enough.
  static TabHistoryBackend? _active;

  /// Set the active shell. Called from a shell's `initState`.
  /// Idempotent — calling twice with the same instance is a no-op.
  static void attach(TabHistoryBackend backend) {
    _active = backend;
  }

  /// Clear the active shell if it matches `backend`. Called from
  /// `dispose`. Safe to call with a stale reference.
  static void detach(TabHistoryBackend backend) {
    if (identical(_active, backend)) _active = null;
  }

  /// Asks the active shell to pop one tab off its history.
  ///
  /// Returns `true` if a pop happened, `false` if there was no active
  /// shell or the history was already at the root. Either failure mode
  /// means "there is nothing more to pop, surface the exit
  /// confirmation".
  static bool maybePop() {
    final active = _active;
    if (active == null) return false;
    return active.popTabHistory();
  }
}

/// Mixin that owns a tab-history stack. Implemented by the two
/// `IndexedStack`-based shells (patient + caretaker).
mixin TabHistoryMixin<W extends StatefulWidget> on State<W>
    implements TabHistoryBackend {
  /// Stack of previously-selected tab indices. The bottom of the stack
  /// is the first tab the user opened after launch (usually 0 =
  /// Dashboard / Patients). When [_tabHistory] is empty, the shell is
  /// at its root and a further back press should surface the exit
  /// confirmation, not pop a tab.
  final List<int> _tabHistory = <int>[];

  /// Shell-implemented: how many tabs the bottom nav has. Used only by
  /// [onTabTapped] to guard against out-of-range taps.
  int get tabCount;

  /// Shell-implemented: which tab is currently selected.
  int get currentTabIndex;

  /// Shell-implemented: actually change the selected tab. Pure
  /// setState + side-effects (haptic, controller.jumpTo). MUST NOT
  /// touch [_tabHistory] itself — callers must go through
  /// [onTabTapped].
  void selectTab(int next);

  @override
  void initState() {
    super.initState();
    // Register as the active shell so BackScaffold / ExitConfirmer can
    // reach this mixin's [popTabHistory] through the static facade.
    TabHistory.attach(this);
  }

  /// Called by the bottom-nav `onTap`. Pushes the current tab onto the
  /// history before switching so the next system-back returns to it.
  ///
  /// Same-tab taps are a no-op (the user is just re-asserting the
  /// current tab — no history change).
  void onTabTapped(int next) {
    if (next == currentTabIndex) return;
    if (next < 0 || next >= tabCount) return;
    _tabHistory.add(currentTabIndex);
    selectTab(next);
  }

  /// Pop one tab off the history and switch to it. Returns `true` if a
  /// pop happened, `false` if the history is empty (caller should
  /// show the exit confirmation).
  @override
  bool popTabHistory() {
    if (_tabHistory.isEmpty) return false;
    final prev = _tabHistory.removeLast();
    selectTab(prev);
    return true;
  }

  /// Reset the history. Called from `dispose()` so a re-mounted shell
  /// (e.g. after logout) doesn't inherit stale entries.
  void clearTabHistory() {
    _tabHistory.clear();
  }
}
