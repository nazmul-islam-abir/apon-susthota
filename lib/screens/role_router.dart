/// Role-aware top-level router.
///
/// Sits between the BDApps landing/login flow and the two app shells.
/// Once a user is signed in we read their `role` from `user_profiles`
/// (or the locally-cached value set by [BdappsSessionService]) and
/// hand them off to either the patient or caretaker shell.
///
/// Routing decisions:
///   * signed out                → RoleLandingScreen
///   * signed in, role 'patient' → patient shell (HomeShell)
///   * signed in, role 'caregiver' → caretaker shell
///   * signed in, role unknown / null → patient shell (default), but
///                                       surfaces a one-shot dialog
///                                       suggesting role selection so
///                                       caretakers who signed up before
///                                       this column existed can opt in.
///   * signed in but `profile_completed = false` (BDApps first login)
///     → surfaces the [ProfileCompletionDialog] on top of the shell.
///
/// The router is intentionally read-only: it doesn't own any state.
/// Both shells carry their own providers (CaretakerProvider for the
/// caretaker shell, the existing auth/profile providers for the
/// patient shell) and we don't introduce a third listener here.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/bdapps/bdapps_session_service.dart';
import 'auth/profile_completion_dialog.dart';
import 'auth/role_landing_screen.dart';
import 'caretaker/caretaker_profile_screen.dart';
import 'home_shell.dart';
import 'caretaker/caretaker_shell.dart';
import 'onboarding_screen.dart';
import 'auth/role_choice.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

enum _ShellKind { auth, patient, caretaker, needsRoleSelection }

class _RoutedShell {
  final _ShellKind kind;
  final UserProfile? profile;
  final bool profileCompleted;
  const _RoutedShell.kind(this.kind)
      : profile = null,
        profileCompleted = false;
  const _RoutedShell.shell(
    this.kind,
    this.profile, {
    this.profileCompleted = false,
  });
  const _RoutedShell.needsRoleSelection(this.profile)
      : kind = _ShellKind.needsRoleSelection,
        profileCompleted = false;
}

/// Top-level entry for signed-in users. Decides which shell to mount.
class RoleRouter extends StatefulWidget {
  const RoleRouter({super.key});

  @override
  State<RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<RoleRouter> {
  /// Three possible screens we might mount. Keeping all three behind a
  /// single state field avoids a "null child" flicker on first build.
  late Future<_RoutedShell> _future;

  /// Cached BuildContext from the latest build. Used by post-frame
  /// callbacks (e.g. showing the profile-completion dialog) so we
  /// don't need to capture it inside addPostFrameCallback.
  BuildContext? _navContext;

  @override
  void initState() {
    super.initState();
    _future = _decide();
  }

  /// Re-run the routing decision. Called from a one-shot dialog that
  /// asks the user to pick a role if their `user_profiles.role` is
  /// still null (legacy sign-ups before the column was added).
  Future<void> _retry() async {
    setState(() => _future = _decide());
    await _future;
  }

  Future<_RoutedShell> _decide() async {
    final user = SupabaseService.currentUser;
    // BDApps-only path: we may have a role/profile_completed cached
    // locally but no Supabase auth user yet (in-flight BDApps login
    // where the session RPC failed). Fall back to landing if both
    // signals are absent.
    if (user == null && BdappsSessionService.instance.role == null) {
      return const _RoutedShell.kind(_ShellKind.auth);
    }
    UserProfile? profile;
    try {
      profile = await SupabaseService.fetchProfile();
    } catch (e) {
      debugPrint('RoleRouter: fetchProfile failed: $e');
    }
    final cachedRole = BdappsSessionService.instance.role;
    final cachedProfileCompleted =
        BdappsSessionService.instance.profileCompleted;
    final serverProfileCompleted =
        profile?.profileCompleted ?? cachedProfileCompleted;

    // Defensive completion check: once a user has both a real name
    // AND a unique username, consider the profile "good enough" for
    // the post-login prompt even if the server-side
    // profile_completed flag somehow stayed false. This is the
    // signal the popup itself describes ("নাম ও ইউজারনেম"). Without
    // this guard the popup keeps nagging every launch.
    final hasName =
        (profile?.fullName?.trim().isNotEmpty ?? false);
    final hasUsername =
        (profile?.username?.trim().isNotEmpty ?? false);
    final profileCompleted =
        serverProfileCompleted || (hasName && hasUsername);

    final role = (profile?.role ?? cachedRole ?? 'patient')
        .toString()
        .trim()
        .toLowerCase();
    if (role == 'caretaker' || role == 'caregiver') {
      return _RoutedShell.shell(
        _ShellKind.caretaker,
        profile,
        profileCompleted: profileCompleted,
      );
    }
    if (profile?.role == null && cachedRole == null) {
      return _RoutedShell.needsRoleSelection(profile);
    }
    return _RoutedShell.shell(
      _ShellKind.patient,
      profile,
      profileCompleted: profileCompleted,
    );
  }

  Future<void> _promptRoleSelection(UserProfile? profile) async {
    final result = await showDialog<RoleChoice>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: const _RoleSelectionDialog(),
        ),
      ),
    );
    if (!mounted) return;
    if (result == null) {
      // User closed the dialog → keep them in the patient shell as a
      // safe default. The dialog button is the only escape, but we
      // still guard this in case of programmatic dismiss.
      setState(() {
        _future = Future.value(
          _RoutedShell.shell(_ShellKind.patient, profile),
        );
      });
      return;
    }
    try {
      await SupabaseService.updateRoleAndRelationship(
        role: result == RoleChoice.caregiver ? 'caretaker' : 'patient',
        caretakerRelationship: result == RoleChoice.caregiver
            ? (profile?.caretakerRelationship ?? 'পরিবার')
            : null,
      );
    } catch (e) {
      debugPrint('RoleRouter: updateRoleAndRelationship failed: $e');
    }
    await _retry();
  }

  Future<void> _promptProfileCompletion(_RoutedShell routed) async {
    final ctx = _navContext;
    if (ctx == null || !mounted) return;
    final role = routed.profile?.role ??
        BdappsSessionService.instance.role ??
        'patient';
    final result =
        await ProfileCompletionDialog.show(ctx, role: role);
    if (!mounted) return;
    // Re-evaluate routing so the dialog doesn't reappear after the
    // user submits the onboarding flow (which flips profileCompleted).
    if (result) {
      // User chose "এখনই সম্পূর্ণ করুন" — push the correct onboarding screen.
      // ignore: use_build_context_synchronously
      if (role == 'caretaker' || role == 'caregiver') {
        await Navigator.of(ctx).push(MaterialPageRoute(
          builder: (_) => const CaretakerProfileScreen(),
        ));
      } else {
        await Navigator.of(ctx).push(MaterialPageRoute(
          builder: (_) => OnboardingScreen(edit: routed.profile),
        ));
      }
    }
    if (!mounted) return;
    setState(() => _future = _decide());
  }

  @override
  Widget build(BuildContext context) {
    _navContext = context;
    return FutureBuilder<_RoutedShell>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _SplashShell();
        }
        final routed = snap.data;
        if (routed == null) {
          return const RoleLandingScreen();
        }
        Widget child;
        switch (routed.kind) {
          case _ShellKind.auth:
            return const RoleLandingScreen();
          case _ShellKind.patient:
            child = HomeShell(profile: routed.profile);
            break;
          case _ShellKind.caretaker:
            child = CaretakerShell(profile: routed.profile);
            break;
          case _ShellKind.needsRoleSelection:
            // Defer the dialog until after first frame so the dialog
            // gets a clean context (no overlay race).
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _promptRoleSelection(routed.profile);
            });
            child = HomeShell(profile: routed.profile);
            break;
        }
        // Surface the BDApps profile-completion prompt whenever the
        // user is freshly onboarded. Returning users skip the dialog.
        if (!routed.profileCompleted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _promptProfileCompletion(routed);
          });
        }
        return child;
      },
    );
  }
}

/// Plain splash surface shown while [RoleRouter] fetches the profile.
/// Matches the app's cream/paper background so the transition is invisible.
class _SplashShell extends StatelessWidget {
  const _SplashShell();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.void2,
      body: Center(
        child: CircularProgressIndicator(
          strokeWidth: 3,
          color: AppColors.cyan,
        ),
      ),
    );
  }
}

/// One-shot dialog shown to legacy users who signed up before the
/// `role` column existed. Mirrors the role-select screen's options.
class _RoleSelectionDialog extends StatelessWidget {
  const _RoleSelectionDialog();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'আপনি কোন ভূমিকায় ব্যবহার করবেন?',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'নিজের ডায়েট পরিচালনা করুন, অথবা পরিবারের কাউকে দেখাশোনা করুন।',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textMuted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _PickCard(
                  title: 'রোগী',
                  icon: Icons.person_rounded,
                  accent: AppColors.cyan,
                  onTap: () => Navigator.of(context).pop(RoleChoice.patient),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PickCard(
                  title: 'কেয়ারগিভার',
                  icon: Icons.volunteer_activism_rounded,
                  accent: AppColors.violet,
                  onTap: () => Navigator.of(context).pop(RoleChoice.caregiver),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PickCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
  const _PickCard({
    required this.title,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accent, size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}