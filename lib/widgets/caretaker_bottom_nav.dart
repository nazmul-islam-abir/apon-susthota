/// Caretaker-facing bottom navigation. Four icons-only tabs in the order
/// a caregiver reaches for most often:
///
///   0 Patients   — full list of linked patients, tap to drill in
///   1 Today      — at-a-glance "what needs attention today" view
///   2 Inbox      — incoming link requests + sent pending list
///   3 Search     — discover new patients by mobile number
///
/// Reuses the same morphing notch package as the patient shell.
library;

// ignore_for_file: implementation_imports

import 'package:animated_notch_bottom_bar/src/models/bottom_bar_item_model.dart';
import 'package:animated_notch_bottom_bar/src/notch_bottom_bar.dart';
import 'package:animated_notch_bottom_bar/src/notch_bottom_bar_controller.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// One tab in the caretaker bottom nav. The label comes from the active
/// `AppLocalizations` so it flips when the user toggles the language pill.
class CaretakerNavItem {
  final String Function(AppLocalizations l) label;
  final IconData icon;
  final IconData outline;
  const CaretakerNavItem({
    required this.label,
    required this.icon,
    required this.outline,
  });
}

class CaretakerBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Builder for the four tabs. Kept as a getter (rather than a static
  /// const list) because the label needs context-dependent localization
  /// — the previous static-const pattern would have been a per-tab
  /// Locale-aware dict, which is what we're moving away from.
  List<CaretakerNavItem> _items(AppLocalizations l) => [
        CaretakerNavItem(
          label: (_) => l.caretakerNavPatients,
          icon: Icons.people_alt,
          outline: Icons.people_alt_outlined,
        ),
        CaretakerNavItem(
          label: (_) => l.caretakerNavToday,
          icon: Icons.today_rounded,
          outline: Icons.today_outlined,
        ),
        CaretakerNavItem(
          label: (_) => l.caretakerNavInbox,
          icon: Icons.inbox,
          outline: Icons.inbox_outlined,
        ),
        CaretakerNavItem(
          label: (_) => l.caretakerNavSearch,
          icon: Icons.search,
          outline: Icons.search_outlined,
        ),
      ];

  const CaretakerBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final items = _items(l);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: AnimatedNotchBottomBar(
        // The AnimatedNotchBottomBar allocates space for the label
        // band even when `showLabel: false`. Using a slightly smaller
        // width (~92% of screen) keeps the bar from kissing the edge
        // on narrow devices, and gives the Bangla labels room to
        // breathe under each icon.
        bottomBarWidth: MediaQuery.of(context).size.width * 0.92,
        notchBottomBarController:
            NotchBottomBarController(index: currentIndex),
        bottomBarItems: List<BottomBarItem>.generate(
          items.length,
          (i) => BottomBarItem(
            inActiveItem: Icon(
              items[i].outline,
              size: 22,
              color: AppColors.newsInk.withValues(alpha: 0.55),
            ),
            activeItem: Icon(
              items[i].icon,
              size: 22,
              color: Colors.white,
            ),
            itemLabel: items[i].label(l),
          ),
        ),
        onTap: onTap,
        kIconSize: 22,
        kBottomRadius: 28,
        // Caretaker app shows labels — the patient shell does, so the
        // caretaker shell should too. Caretakers spend more time
        // scanning tab labels (they're reading names + statuses, not
        // tapping) than the patient.
        showLabel: true,
        color: Colors.white,
        // Caretaker bar uses the violet accent so it's visually distinct
        // from the patient shell — the user always knows which shell
        // they're in at a glance.
        notchColor: AppColors.violetDeep,
        showShadow: true,
        elevation: 6,
        shadowElevation: 6,
      ),
    );
  }
}
