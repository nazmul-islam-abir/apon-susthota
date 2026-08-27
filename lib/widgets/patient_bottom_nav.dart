/// Patient-facing bottom navigation — extracted from HomeShell so both
/// the patient shell and any future "preview as patient" debug view
/// can mount the same morphing notch bar.
///
/// The bar uses the `animated_notch_bottom_bar` package's internal
/// `src/` files because the package's public entry file is malformed
/// in this toolchain.
library;

// ignore_for_file: implementation_imports

import 'package:animated_notch_bottom_bar/src/models/bottom_bar_item_model.dart';
import 'package:animated_notch_bottom_bar/src/notch_bottom_bar.dart';
import 'package:animated_notch_bottom_bar/src/notch_bottom_bar_controller.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One tab descriptor for the patient shell's bottom nav.
class PatientNavItem {
  final String label;
  final IconData icon;
  final IconData outline;
  const PatientNavItem({
    required this.label,
    required this.icon,
    required this.outline,
  });
}

/// Patient bottom nav. Five icons-only tabs in dashboard-first order.
class PatientBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const List<PatientNavItem> items = [
    PatientNavItem(
      label: 'ড্যাশবোর্ড',
      icon: Icons.insights,
      outline: Icons.insights_outlined,
    ),
    PatientNavItem(
      label: 'আজ',
      icon: Icons.restaurant_menu,
      outline: Icons.restaurant_menu_outlined,
    ),
    PatientNavItem(
      label: 'ব্যায়াম',
      icon: Icons.fitness_center,
      outline: Icons.fitness_center_outlined,
    ),
    PatientNavItem(
      label: 'বিশ্লেষণ',
      icon: Icons.bar_chart_rounded,
      outline: Icons.bar_chart_outlined,
    ),
    PatientNavItem(
      label: 'AI সহকারী',
      icon: Icons.smart_toy,
      outline: Icons.smart_toy_outlined,
    ),
  ];

  const PatientBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: AnimatedNotchBottomBar(
        bottomBarWidth: MediaQuery.of(context).size.width - 32,
        // The package exposes a controller for programmatic jumps. We
        // hand the widget a fresh controller each rebuild — AnimatedNotchBottomBar
        // re-syncs to whatever tab is currently active through the index in
        // bottomBarItems' active flag (which we control via `currentIndex`).
        notchBottomBarController: NotchBottomBarController(index: currentIndex),
        bottomBarItems: List<BottomBarItem>.generate(
          items.length,
          (i) => BottomBarItem(
            inActiveItem: Icon(
              items[i].outline,
              size: 24,
              color: AppColors.newsInk.withValues(alpha: 0.55),
            ),
            activeItem: Icon(
              items[i].icon,
              size: 24,
              color: Colors.white,
            ),
            itemLabel: items[i].label,
          ),
        ),
        onTap: onTap,
        kIconSize: 24,
        kBottomRadius: 28,
        showLabel: false,
        color: Colors.white,
        notchColor: AppColors.newsInk,
        showShadow: true,
        elevation: 6,
        shadowElevation: 6,
      ),
    );
  }
}
