/// Second step of signup: pick the role (Patient | Caregiver).
///
/// Shown after the auth_screen lets a new user create their account
/// but before the onboarding/profile screen. For legacy users
/// (accounts created before the role system shipped), this screen is
/// NOT shown — they auto-become Patient and skip straight to the
/// onboarding form.
///
/// Behaviour:
///   1. Two big role cards with Bengali copy + an icon each.
///   2. Caregiver card expands a `relationship` text field (e.g.
///      "ছেলে", "স্বামী", "পরিচর্যাকারী").
///   3. "চালিয়ে যান" button:
///      * For patient  → writes role='patient' to user_profiles,
///        pops back to onboarding.
///      * For caregiver → writes role='caretaker' + relationship,
///        pops back to a special empty-state (the caretaker app has
///        no onboarding form).
///
/// The role write goes through a single UPDATE on user_profiles
/// (via `updateRoleAndRelationship` we will add when we wire B7's
/// service surface into the call site). For now we hit the same
/// RPC we'll add to the migration set to keep this file standalone.
library;

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';

/// Reasons the user picked this role. Used for telemetry + to drive
/// the post-role-select routing.
enum RoleChoice { patient, caregiver }

/// Full-screen modal pushed after signup. Stateless; expects to be
/// popped by the caller once the user picks a role.
class RoleSelectScreen extends StatefulWidget {
  const RoleSelectScreen({super.key});

  @override
  State<RoleSelectScreen> createState() => _RoleSelectScreenState();
}

class _RoleSelectScreenState extends State<RoleSelectScreen> {
  RoleChoice? _choice;
  final _relationshipCtrl = TextEditingController();
  bool _saving = false;
  String? _errorText;

  @override
  void dispose() {
    _relationshipCtrl.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final l = AppLocalizations.of(context)!;
    if (_choice == null) return;
    if (_choice == RoleChoice.caregiver &&
        _relationshipCtrl.text.trim().isEmpty) {
      setState(() => _errorText = l.roleSelectRelationshipRequired);
      return;
    }
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      // 1. Persist on user_profiles (service exposes this from B7).
      final roleStr =
          _choice == RoleChoice.patient ? 'patient' : 'caretaker';
      await SupabaseService.updateRoleAndRelationship(
        role: roleStr,
        caretakerRelationship: _choice == RoleChoice.caregiver
            ? _relationshipCtrl.text.trim()
            : null,
      );

      if (!mounted) return;
      // 2. Tell the caller which role was picked. Auth_screen pops
      //    back and routes to onboarding (patient) or empty
      //    caretaker state (caretaker).
      Navigator.of(context).pop(_choice);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorText = l.roleSelectSaveFailed(e.toString());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        foregroundColor: AppColors.ink,
        title: Overline(l.roleSelectTitle),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.roleSelectHeadline,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              Text(
                l.roleSelectBlurb,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.smoke,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              _RoleCard(
                selected: _choice == RoleChoice.patient,
                icon: Icons.person_rounded,
                title: l.roleCardPatientTitle,
                englishHint: l.roleCardPatientEn,
                description: l.roleCardPatientDesc,
                accent: AppColors.cyan,
                onTap: () => setState(() => _choice = RoleChoice.patient),
              ),
              const SizedBox(height: 14),
              _RoleCard(
                selected: _choice == RoleChoice.caregiver,
                icon: Icons.favorite_outline_rounded,
                title: l.roleCardCaregiverTitle,
                englishHint: l.roleCardCaregiverEn,
                description: l.roleCardCaregiverDesc,
                accent: AppColors.violet,
                onTap: () => setState(() => _choice = RoleChoice.caregiver),
              ),
              if (_choice == RoleChoice.caregiver) ...[
                const SizedBox(height: 18),
                Overline(l.roleSelectRelationshipOverline),
                const SizedBox(height: 6),
                _RelationshipField(controller: _relationshipCtrl),
              ],
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.health_and_safety_outlined,
                      size: 18,
                      color: AppColors.cyan,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l.roleSelectClinicalNote,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.smoke,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (_errorText != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: Color(0xFFB91C1C),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorText!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFFB91C1C),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: double.infinity,
                child: MonoButton(
                  label: _saving ? l.roleSelectSaving : l.roleSelectContinue,
                  leading: _saving
                      ? Icons.hourglass_top_rounded
                      : Icons.arrow_forward_rounded,
                  onPressed: (_choice == null || _saving)
                      ? null
                      : _continue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String englishHint;
  final String description;
  final Color accent;
  final VoidCallback onTap;

  const _RoleCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.englishHint,
    required this.description,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.08) : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: selected ? accent : AppColors.line,
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? accent : AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: selected ? AppColors.void1 : accent,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          englishHint,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.smoke,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.smoke,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? accent : AppColors.smoke,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RelationshipField extends StatelessWidget {
  final TextEditingController controller;
  const _RelationshipField({required this.controller});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.line),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: TextField(
        controller: controller,
        maxLength: 40,
        textInputAction: TextInputAction.done,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
        decoration: InputDecoration(
          counterText: '',
          border: InputBorder.none,
          hintText: l.roleSelectRelationshipHint,
          hintStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppColors.smoke,
          ),
        ),
      ),
    );
  }
}
