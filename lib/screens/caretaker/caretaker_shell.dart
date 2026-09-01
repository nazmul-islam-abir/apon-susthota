/// Caretaker app shell (Nexora Redesign).
///
/// Top-level scaffold for users who signed up as caregiver (role =
/// 'caretaker' in `user_profiles`). Matches the structure of the
/// patient `HomeShell` but themed for the Caretaker experience.
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
  final UserProfile? profile;
  const CaretakerShell({super.key, this.profile});

  @override
  State<CaretakerShell> createState() => _CaretakerShellState();
}

class _CaretakerShellState extends State<CaretakerShell>
    with TabHistoryMixin<CaretakerShell> {
  int _index = 0;
  final List<Widget?> _cache = List.filled(4, null);

  @override
  int get tabCount => 4;

  @override
  int get currentTabIndex => _index;

  @override
  void selectTab(int next) {
    HapticFeedback.selectionClick();
    setState(() => _index = next);
  }

  void switchTab(int i) => onTabTapped(i);

  Widget _pageAt(int i) => _cache[i] ??= _buildPage(i);

  Widget _buildPage(int i) {
    switch (i) {
      case 0:
        return PatientsTab(
          profile: widget.profile,
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
    for (var i = 0; i < _cache.length; i++) _cache[i] = null;
    TabHistory.detach(this);
    clearTabHistory();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CaretakerProvider(variant: CaretakerProviderVariant.caretaker)..attachRealtime(),
      child: Consumer<CaretakerProvider>(
        builder: (context, prov, _) {
          return AppShellScaffold(
            onLogoutRequested: () => performShellLogout(context),
            showTopBar: false, // We use custom Heros in tabs for Nexora look
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
String bnGreeting() {
  final hour = DateTime.now().hour;
  if (hour < 5) return 'শুভ রাত্রি';
  if (hour < 12) return 'সুপ্রভাত';
  if (hour < 17) return 'শুভ দুপুর';
  if (hour < 21) return 'শুভ সন্ধ্যা';
  return 'শুভ রাত্রি';
}

/// Small header chip strip rendered above content in sub-pages.
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
    final greet = bnGreeting();
    final greeting = name.isEmpty ? greet : '$greet, ${name.split(' ').first}';
    
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.newsInk,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'আপনার $patientCount জন সংযুক্ত রোগী'
                  '${pendingCount > 0 ? ' • $pendingCountটি অনুরোধ অপেক্ষমাণ' : ''}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.smoke,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const RoleChip(role: UserRoleView.caregiver),
        ],
      ),
    );
  }
}
