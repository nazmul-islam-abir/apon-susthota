/// Role-aware top-level router.
///
/// Sits between `AuthScreen` and the two app shells. Once a user is
/// signed in we read their `role` from `user_profiles` and hand them
/// off to either the patient or caretaker shell.
///
/// Routing decisions:
///   * signed out                → AuthScreen
///   * signed in, role 'patient' → patient shell (HomeShell)
///   * signed in, role 'caregiver' → caretaker shell
///   * signed in, role unknown / null → patient shell (default), but
///                                       surfaces a one-shot dialog
///                                       suggesting role selection so
///                                       caretakers who signed up before
///                                       this column existed can opt in.
///
/// The router is intentionally read-only: it doesn't own any state.
/// Both shells carry their own providers (CaretakerProvider for the
/// caretaker shell, the existing auth/profile providers for the
/// patient shell) and we don't introduce a third listener here.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import 'auth_screen.dart';
import 'home_shell.dart';
import 'caretaker/caretaker_shell.dart';
import 'role_select_screen.dart' show RoleChoice;
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

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
    if (user == null) {
      return const _RoutedShell.kind(_ShellKind.auth);
    }
    UserProfile? profile;
    try {
      profile = await SupabaseService.fetchProfile();
    } catch (e) {
      debugPrint('RoleRouter: fetchProfile failed: $e');
    }
    final role = (profile?.role ?? 'patient').trim().toLowerCase();
    if (role == 'caretaker' || role == 'caregiver') {
      return _RoutedShell.shell(_ShellKind.caretaker, profile);
    }
    if (profile?.role == null || (profile?.role ?? '').isEmpty) {
      return _RoutedShell.needsRoleSelection(profile);
    }
    return _RoutedShell.shell(_ShellKind.patient, profile);
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
        _future = Future.value(_RoutedShell.shell(_ShellKind.patient, profile));
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_RoutedShell>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _SplashShell();
        }
        final routed = snap.data;
        if (routed == null) {
          return const AuthScreen();
        }
        switch (routed.kind) {
          case _ShellKind.auth:
            return const AuthScreen();
          case _ShellKind.patient:
            return HomeShell(profile: routed.profile);
          case _ShellKind.caretaker:
            return CaretakerShell(profile: routed.profile);
          case _ShellKind.needsRoleSelection:
            // Defer the dialog until after first frame so the dialog
            // gets a clean context (no overlay race).
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _promptRoleSelection(routed.profile);
            });
            return HomeShell(profile: routed.profile);
        }
      },
    );
  }
}

enum _ShellKind { auth, patient, caretaker, needsRoleSelection }

class _RoutedShell {
  final _ShellKind kind;
  final UserProfile? profile;
  const _RoutedShell.kind(this.kind) : profile = null;
  const _RoutedShell.shell(this.kind, this.profile);
  const _RoutedShell.needsRoleSelection(this.profile) : kind = _ShellKind.needsRoleSelection;
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
          Text(
            'আপনি কোন ভূমিকায় ব্যবহার করবেন?',
            style: const TextStyle(
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
