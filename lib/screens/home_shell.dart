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
import 'meal_plan_screen.dart';
import 'dashboard_screen.dart';
import 'medicine_screen.dart';
import 'workout_screen.dart';
import 'analytics_screen.dart';

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
///   4  Medicine    — pill schedule + dose log
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
      label: 'ওষুধ',
      icon: Icons.medication,
      outline: Icons.medication_outlined,
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
        return const MedicineScreen();
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
    return Scaffold(
      // Transparent so the brand-pink canvas drifts behind the pages.
      backgroundColor: Colors.transparent,
      // IndexedStack with a single pre-built child keeps the active tab's
      // state (scroll position, animations) alive when the user swaps tabs,
      // and previously-visited tabs are kept alive in [_cache] so they
      // don't refetch either. Only the active tab's `initState` runs
      // each time it is selected for the first time — that's what kills
      // the cold-start RPC storm.
      body: IndexedStack(
        index: _index,
        children: List<Widget>.generate(5, _pageAt),
      ),
      // Floating navbar — wrapped with side + bottom padding so the bar
      // hangs as a pill above the bottom edge instead of stretching
      // edge-to-edge. Matches the modern floating-nav look used in the
      // rest of the app's screens.
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: AnimatedNotchBottomBar(
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
            kBottomRadius: 28,
            // Icons only — no text labels under each tab.
            showLabel: false,
            // News/blog look: dark pill indicator on a white bar.
            notchColor: AppColors.newsInk,
            color: AppColors.newsSurface,
            showShadow: true,
            elevation: 6,
            shadowElevation: 8,
          ),
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
