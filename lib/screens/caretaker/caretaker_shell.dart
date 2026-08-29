/// Caretaker app shell.
///
/// Top-level scaffold for users who signed up as caregiver (role =
/// 'caretaker' in `user_profiles`). Mirrors the structure of the
/// patient `HomeShell`:
///
///   ┌──────────────────────────────────────────┐
///   │  Brand bar (drawer hamburger + wordmark) │
///   ├──────────────────────────────────────────┤
///   │                                          │
///   │          active tab content              │
///   │                                          │
///   ├──────────────────────────────────────────┤
///   │  bottom nav (4 tabs)                     │
///   └──────────────────────────────────────────┘
///
/// The bottom nav reuses the same morphing notch pattern as the
/// patient shell but with violet accents so the two shells are
/// visually distinct. The shell wraps every tab with a single
/// `CaretakerProvider` so the realtime subscription and patient list
/// are shared across tabs — selecting a patient in the patient list
/// tab and drilling into the detail screen reuses the same in-memory
/// state instead of refetching.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/user_profile.dart';
import '../../services/caretaker_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/apon_susthota_shell.dart';
import '../../widgets/caretaker_bottom_nav.dart';
import '../../widgets/role_chip.dart';
import '../../widgets/tab_history_mixin.dart';
import 'patients_tab.dart';
import 'caretaker_today_tab.dart';
import 'caretaker_inbox_tab.dart';
import 'people_search_screen.dart';

class CaretakerShell extends StatefulWidget {
  /// The signed-in caretaker's profile. Carried in so the shell can
  /// show their name in the brand bar without re-fetching.
  final UserProfile? profile;

  const CaretakerShell({super.key, this.profile});

  @override
  State<CaretakerShell> createState() => _CaretakerShellState();
}

class _CaretakerShellState extends State<CaretakerShell>
    with TabHistoryMixin<CaretakerShell> {
  int _index = 0;

  // Cached tab bodies — same trick as HomeShell: keep scroll
  // positions alive when switching tabs.
  final List<Widget?> _cache = List.filled(4, null);

  // ── TabHistoryMixin bindings ─────────────────────────────────────────
  @override
  int get tabCount => 4;

  @override
  int get currentTabIndex => _index;

  @override
  void selectTab(int next) {
    HapticFeedback.selectionClick();
    setState(() => _index = next);
  }

  /// Public hook for tabs (notably the onboarding empty state)
  /// to switch tabs without owning the state. Goes through
  /// [onTabTapped] so the bottom-nav history is recorded — otherwise
  /// the empty-state CTA would jump to a tab that can't be popped
  /// back from, which would confuse users.
  void switchTab(int i) => onTabTapped(i);

  Widget _pageAt(int i) => _cache[i] ??= _buildPage(i);

  Widget _buildPage(int i) {
    switch (i) {
      case 0:
        return PatientsTab(
          profile: widget.profile,
          // The empty-state CTA jumps to the People search tab.
          onSwitchTab: switchTab,
        );
      case 1:
        return CaretakerTodayTab(profile: widget.profile);
      case 2:
        return const CaretakerInboxTab();
      case 3:
        return const PeopleSearchScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  void dispose() {
    for (var i = 0; i < _cache.length; i++) {
      _cache[i] = null;
    }
    // Detach from TabHistory so a future HomeShell mount doesn't see
    // a stale reference, and so the static `_active` pointer doesn't
    // dangle after this shell is gone.
    TabHistory.detach(this);
    clearTabHistory();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) =>
          CaretakerProvider(variant: CaretakerProviderVariant.caretaker)
            ..attachRealtime(),
      child: Consumer<CaretakerProvider>(
        builder: (context, prov, _) {
          return AppShellScaffold(
            onLogoutRequested: () => performShellLogout(context),
            // Always render the brand top bar on every caretaker tab.
            // The previous `showTopBar: isPatientsTab` flag left the
            // ইনবক্স / আজ / খোঁজা tabs without a visible hamburger or
            // wordmark, which made the chrome feel inconsistent and
            // pushed the CaretakerHeaderStrip greeting under the system
            // status bar (causing the "top is cropped" symptom users
            // were seeing on those tabs).
            showTopBar: true,
            body: IndexedStack(
              index: _index,
              children: List<Widget>.generate(4, _pageAt),
            ),
            bottomBar: CaretakerBottomNav(
              currentIndex: _index,
              onTap: onTabTapped,
            ),
          );
        },
      ),
    );
  }
}

/// Returns a Bangla "time-of-day" salutation matching local Asia/Dhaka time.
String _bnGreeting() {
  final hour = DateTime.now().hour;
  if (hour < 5) return 'শুভ রাত্রি';
  if (hour < 12) return 'সুপ্রভাত';
  if (hour < 17) return 'শুভ দুপুর';
  if (hour < 21) return 'শুভ সন্ধ্যা';
  return 'শুভ রাত্রি';
}

/// Small header chip strip rendered above the patients tab content.
/// Shows the caregiver's name + the role chip so it's obvious which
/// lens the data is being shown through.
class CaretakerHeaderStrip extends StatelessWidget {
  final UserProfile? profile;
  final int patientCount;
  final int pendingCount;
  const CaretakerHeaderStrip({
    super.key,
    required this.profile,
    required this.patientCount,
    required this.pendingCount,
  });

  @override
  Widget build(BuildContext context) {
    final name = (profile?.fullName ?? '').trim();
    final greet = _bnGreeting();
    final greeting = name.isEmpty ? greet : '$greet, ${name.split(' ').first}';
    // The shared AppShellScaffold now sits the brand bar above this
    // strip, so the body's top inset is already handled. Adding
    // `padding.top` here would double-inset on notched devices and
    // push the greeting down with a visible gap. The previous
    // `EdgeInsets.fromLTRB(20, 12 + padTop, …)` was correct when the
    // bar was a `Positioned(top: 0, …)` overlay, but no longer.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: AppColors.text,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'আপনার $patientCount জন সংযুক্ত রোগী'
                  '${pendingCount > 0 ? ' • $pendingCountটি অনুরোধ অপেক্ষমাণ' : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const RoleChip(role: UserRoleView.caregiver),
        ],
      ),
    );
  }
}
