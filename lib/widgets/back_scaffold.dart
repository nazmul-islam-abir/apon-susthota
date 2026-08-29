/// Reusable scaffold-with-back-button used by every screen that
/// previously lacked an AppBar.
///
/// The 11 screens the user flagged (5 patient tabs + 2 patient pushed
/// routes + 4 caretaker tabs + 1 caretaker search variant) all rendered
/// a custom `Container`-based top header instead of an `AppBar`. That
/// meant there was no visible back chevron and no Android system-back
/// affordance. `BackScaffold` standardises all of them onto a single
/// consistent pattern.
///
/// Behaviour of the back chevron:
///
///   1. If the [Navigator] stack has a pushed sub-route on top of this
///      screen, the chevron pops it (the standard `Navigator.maybePop`
///      semantics). The system back gesture does the same.
///   2. Otherwise we ask [TabHistory.maybePop] to "snap back" one tab
///      in the bottom-nav history stack. If the user has drilled
///      Dashboard → Workout → AI Chat via bottom-nav taps, hitting
///      back from AI Chat lands them on Workout, another back on
///      Dashboard, another back shows the exit popup.
///   3. If neither stack has anything to pop, we defer to the
///      surrounding `ExitConfirmer` by simply doing nothing — Flutter's
///      `PopScope` there will catch the gesture and show the dialog.
///
/// All of this happens through `Navigator.maybePop` for pushed routes
/// + `TabHistory.maybePop` for tabs, so the visual chevron and the
/// system back gesture are kept in lockstep — tapping one is identical
/// to tapping the other.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'tab_history_mixin.dart';

/// Top app-bar + body. Drop-in replacement for screens that previously
/// built their own `Container`-based header.
class BackScaffold extends StatelessWidget {
  /// Body of the screen (a [ListView], a [Column], a [Stack], etc.).
  final Widget body;

  /// Optional headline to render in the centre of the bar. Bangla text
  /// works fine (the bar uses an `AppBar` font which falls through to
  /// the configured `Theme.textTheme.titleMedium`).
  final String? title;

  /// Background colour of the top bar. Defaults to the cream
  /// `newsSurface` so it blends with the shell's chrome.
  final Color? backgroundColor;

  /// Optional trailing widget — typically a hamburger, save button, or
  /// overflow menu. The bar reserves a fixed 48-px slot for this so the
  /// title stays centred regardless of the action's width.
  final Widget? action;

  /// Padding on the trailing edge of the [action]. Use this when the
  /// action is an icon button that should flush against the right
  /// edge (e.g. the AI Chat drawer hamburger).
  final EdgeInsetsGeometry? actionPadding;

  /// Total height of the top bar. Defaults to `kToolbarHeight` (56 dp)
  /// so the bar matches Material's standard top-bar height. Override
  /// for screens that want a chunkier header.
  final double toolbarHeight;

  /// Whether the chevron should *only* call `Navigator.maybePop` and
  /// never pop the tab history. Useful on screens that exist purely
  /// inside a tab (so the visual back chevron always stays
  /// "exit-the-screen-or-pop-the-pushed-route", never "switch tabs").
  ///
  /// Leave `false` (the default) — most users want the chevron and
  /// system back to behave identically, and the tab-snap behaviour
  /// feels natural.
  final bool disableTabSnap;

  /// Optional callback that overrides the default "pop navigator →
  /// pop tab history" chain. When provided, the back chevron and the
  /// system back gesture both call this instead. Use for screens that
  /// want a custom back handler (e.g. show a "discard changes?"
  /// dialog).
  final VoidCallback? onBack;

  const BackScaffold({
    super.key,
    required this.body,
    this.title,
    this.backgroundColor,
    this.action,
    this.actionPadding,
    this.toolbarHeight = kToolbarHeight,
    this.disableTabSnap = false,
    this.onBack,
  });

  /// Try to pop the route stack first (sub-routes), then the tab
  /// history, then fall through to the surrounding `ExitConfirmer`.
  /// Returns `true` if either stack was popped.
  bool _handleBack(BuildContext context) {
    if (onBack != null) {
      onBack!();
      return true;
    }
    final navigator = Navigator.of(context);
    // 1. Pushed sub-route on top of this screen: pop it.
    if (navigator.canPop()) {
      HapticFeedback.selectionClick();
      navigator.pop();
      return true;
    }
    // 2. Tab-history (Dashboard → Workout → AI → back → Workout).
    if (!disableTabSnap) {
      if (TabHistory.maybePop()) {
        HapticFeedback.selectionClick();
        return true;
      }
    }
    // 3. Nothing left — let the surrounding ExitConfirmer surface the
    //    dialog. We return false so the caller's `onPopInvokedWithResult`
    //    knows not to do anything itself.
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? AppColors.newsSurface;
    return PopScope(
      // We intercept the back gesture so the system MUST NOT pop on
      // its own; we decide whether to pop a route or a tab. The
      // surrounding ExitConfirmer still runs the exit dialog logic
      // because we're nested inside it in the widget tree.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack(context);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: bg,
            elevation: 0,
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: toolbarHeight,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Centre title — only when supplied. When null the
                    // stack still holds its height (so the body
                    // appears 56 dp below), but nothing is rendered in
                    // the middle.
                    if (title != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 56, right: 90),
                          child: Text(
                            title!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.newsInk,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                      ),
                    // Leading back chevron. Always renders so the user
                    // can see the affordance — even on the Dashboard
                    // where it triggers the exit dialog.
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        tooltip: 'ফিরে যান',
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: AppColors.newsInk,
                          size: 22,
                        ),
                        onPressed: () => _handleBack(context),
                      ),
                    ),
                    // Trailing action slot — flush right. Caller
                    // supplies an icon button / overflow menu / etc.
                    if (action != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: actionPadding ??
                              const EdgeInsets.only(right: 4),
                          child: action,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // Hairline divider between bar and body — subtle visual
          // anchor without forcing a hard shadow on the bar.
          Container(height: 1, color: AppColors.newsDivider),
          Expanded(child: body),
        ],
      ),
    );
  }
}
