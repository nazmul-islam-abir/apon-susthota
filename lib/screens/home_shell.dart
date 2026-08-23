// ignore_for_file: implementation_imports
// We import the package's src/* files directly because the package's
// public entry file (`package:animated_notch_bottom_bar/animated_notch_bottom_bar.dart`)
// is malformed in this toolchain. The src files compile fine.
import 'package:animated_notch_bottom_bar/src/models/bottom_bar_item_model.dart';
import 'package:animated_notch_bottom_bar/src/notch_bottom_bar.dart';
import 'package:animated_notch_bottom_bar/src/notch_bottom_bar_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../widgets/apon_susthota_shell.dart';
import 'meal_plan_screen.dart';
import 'dashboard_screen.dart';
import 'workout_screen.dart';
import 'analytics_screen.dart';
import 'ai_chat_screen.dart';

/// Main shell with an `AnimatedNotchBottomBar` icons-only bottom bar.
///
/// The bar uses the package's morphing circular notch indicator — far
/// more premium than Material's default NavigationBar — and only shows
/// the icon for each tab (no text labels).
///
/// Tab order (dashboard-first redesign):
///   0  Dashboard   — landing page (profile + features + clinical snapshot)
///   1  Meal        — today's meal plan / checklist
///   2  Workout     — daily workout + 30-day progressive program
///   3  Analytics   — 7-day adherence, macro charts, streaks
///   4  AI Assistantâ€” Bangla diabetic-care chatbot (5 prompts/day, Groq)
///
/// The Profile screen is intentionally *not* in the bottom navbar —
/// it's a single-tap from the top of the Dashboard.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  /// Landing page is the new Dashboard.
  int _index = 0;

  /// Each screen is built on demand the first time its tab is opened
  /// and then kept alive in [_cache] so it doesn't refetch when the
  /// user navigates away and back. This replaces the previous
  /// IndexedStack which mounted all 5 tabs at once and caused every
  /// screen's `_load()` to fire in parallel during cold start (the
  /// dominant source of the "app crashes on launch" symptom).
  late final List<Widget?> _cache =
      List<Widget?>.filled(5, null, growable: false);

  final NotchBottomBarController _notchCtrl =
      NotchBottomBarController(index: 0);

  /// 5 entries — one per tab. The package throws if you go beyond 5.
  static const List<_NavItem> _navItems = <_NavItem>[
    _NavItem(
      label: 'ড্যাশবোর্ড',
      icon: Icons.insights,
      outline: Icons.insights_outlined,
    ),
    _NavItem(
      label: 'আজ',
      icon: Icons.restaurant_menu,
      outline: Icons.restaurant_menu_outlined,
    ),
    _NavItem(
      label: 'ব্যায়াম',
      icon: Icons.fitness_center,
      outline: Icons.fitness_center_outlined,
    ),
    _NavItem(
      label: 'বিশ্লেষণ',
      icon: Icons.bar_chart_rounded,
      outline: Icons.bar_chart_outlined,
    ),
    _NavItem(
      label: 'AI সহকারী',
      icon: Icons.smart_toy,
      outline: Icons.smart_toy_outlined,
    ),
  ];

  Widget _pageAt(int i) {
    return _cache[i] ??= _buildPage(i);
  }

  Widget _buildPage(int i) {
    switch (i) {
      case 0:
        return const DashboardScreen();
      case 1:
        return const MealPlanScreen();
      case 2:
        return const WorkoutScreen();
      case 3:
        return const AnalyticsScreen();
      case 4:
        return const AiChatScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  void _onTap(int i) {
    if (i == _index) return;
    HapticFeedback.selectionClick();
    setState(() => _index = i);
    _notchCtrl.jumpTo(i);
  }

  @override
  void dispose() {
    // Drop the cached tabs so their pending _load() futures have no
    // mounted State to setState() into. Without this, an in-flight
    // dashboard fetch can resolve after the user signed out and the
    // HomeShell has already been replaced by AuthScreen — Flutter
    // then throws "setState() called after dispose()" inside the
    // FutureBuilder, leaving the navigator in a half-mounted state.
    for (var i = 0; i < _cache.length; i++) {
      _cache[i] = null;
    }
    _notchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The top bar (drawer hamburger + app name) is intentionally only shown
    // on the Dashboard tab. Meal/Workout/Analytics/AI each bring their own
    // internal app-bar header at the top of their scrollable, so a global
    // floating pill on top of those screens would just clobber their header.
    final isDashboard = _index == 0;

    return AppShellScaffold(
      onLogoutRequested: () => performShellLogout(context),
      // Only mount the floating top bar on the Dashboard tab.
      showTopBar: isDashboard,
      // The shell wraps the IndexedStack so the floating hamburger button
      // and side drawer are available on every tab. The IndexedStack keeps
      // each tab's scroll position and animations alive when swapping.
      body: IndexedStack(
        index: _index,
        children: List<Widget>.generate(5, _pageAt),
      ),
      // Floating navbar — matches the reference design (image 2): a white
      // pill-shaped AnimatedNotchBottomBar with a soft drop shadow and a
      // dark morphing notch indicator under the active tab. The bar sits
      // inside 16-px side+bottom padding so it floats as a single rounded
      // unit above the tab content, instead of being pinned edge-to-edge.
      // Shown on *every* tab — the global bottom-nav is the primary way to
      // switch tabs; the drawer only carries tabs that aren't in the bar.
      bottomBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: AnimatedNotchBottomBar(
          // Lock the bar to the exact inner width of the floating pill
          // (screen width minus the 16-px outer padding on each side).
          // Without this, the package assumes an unconstrained width and
          // the notch indicator drifts horizontally relative to the
          // active tab on different screen sizes.
          bottomBarWidth: MediaQuery.of(context).size.width - 32,
          notchBottomBarController: _notchCtrl,
          bottomBarItems: List<BottomBarItem>.generate(
            _navItems.length,
            (i) => BottomBarItem(
              inActiveItem: Icon(
                _navItems[i].outline,
                size: 24,
                color: AppColors.newsInk.withValues(alpha: 0.55),
              ),
              activeItem: Icon(
                _navItems[i].icon,
                size: 24,
                color: Colors.white,
              ),
              itemLabel: _navItems[i].label, // tooltip when showLabel: false
            ),
          ),
          onTap: _onTap,
          kIconSize: 24,
          // Big rounded pill — matches the reference.
          kBottomRadius: 28,
          // Icons only — no text labels under each tab.
          showLabel: false,
          // Reference look: white pill body with a soft drop shadow, dark
          // morphing notch indicator that travels to whichever tab is
          // currently active.
          color: Colors.white,
          notchColor: AppColors.newsInk,
          showShadow: true,
          elevation: 6,
          shadowElevation: 6,
        ),
      ),
    );
  }
}

/// Internal nav-item descriptor kept private to this file.
class _NavItem {
  final String label;
  final IconData icon;
  final IconData outline;
  const _NavItem({
    required this.label,
    required this.icon,
    required this.outline,
  });
}
