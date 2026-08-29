/// Patients tab — the caretaker's home screen.
///
/// Shows the list of active patients (linked via caretaker_patient_links
/// WHERE status='active'). Each row shows:
///   * avatar (initials + accent ring)
///   * full name
///   * relationship (e.g. "পিতা", "মা")
///   * adherence pill (last-7-days meal adherence as a percentage)
///   * chevron
///
/// Tapping a row navigates to PatientDetailScreen.
///
/// The screen is pull-to-refresh and reacts to realtime updates
/// automatically via the wrapping CaretakerProvider.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/caretaker_patient_summary.dart';
import '../../models/user_profile.dart';
import '../../services/caretaker_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/back_scaffold.dart';
import 'caretaker_empty_state.dart';
import 'caretaker_shell.dart' show CaretakerHeaderStrip;
import 'patient_detail_screen.dart';

class PatientsTab extends StatefulWidget {
  /// Caretaker's own profile — used to greet them in the header strip.
  final UserProfile? profile;
  /// Called when the onboarding CTA "রোগী খুঁজুন" is tapped.
  /// Typically `(i) => caretakerShellRef.currentState?.switchTab(i)`.
  final ValueChanged<int>? onSwitchTab;
  const PatientsTab({super.key, this.profile, this.onSwitchTab});

  @override
  State<PatientsTab> createState() => _PatientsTabState();
}

class _PatientsTabState extends State<PatientsTab> {
  UserProfile? get _profile => widget.profile;
  ValueChanged<int>? get _onSwitchTab => widget.onSwitchTab;

  @override
  Widget build(BuildContext context) {
    return BackScaffold(
      title: 'রোগী',
      body: Consumer<CaretakerProvider>(
        builder: (context, prov, _) {
          return RefreshIndicator(
            color: AppColors.violetDeep,
            onRefresh: prov.refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: CaretakerHeaderStrip(
                    profile: _profile,
                    patientCount: prov.patients.length,
                    pendingCount: prov.pending.length,
                  ),
                ),
              // Surface RPC failures loudly. The previous design
              // swallowed the error inside `_refreshPatients` and
              // let the tab fall back to the empty state — that made
              // "patient accepted but caretaker sees empty" look
              // identical to "no patients at all", which is what
              // users kept reporting. We now render a red banner so
              // the next regression is impossible to miss.
              if (prov.patientError != null)
                SliverToBoxAdapter(
                  child: _PatientErrorBanner(error: prov.patientError!),
                ),
              if (prov.patients.isEmpty &&
                  prov.pending.isEmpty &&
                  _onSwitchTab != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: CaretakerEmptyState(
                    onSwitchTab: _onSwitchTab!,
                  ),
                )
              else ...[
                const SliverToBoxAdapter(
                    child: _Overline(text: 'সংযুক্ত রোগী')),
                if (prov.loadingPatients && prov.patients.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _LoadingBlock(),
                  )
                else if (prov.patients.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    sliver: SliverList.separated(
                      itemBuilder: (_, i) =>
                          _PatientCard(patient: prov.patients[i]),
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemCount: prov.patients.length,
                    ),
                  ),
              ],
            ],
          ),
        );
        },
      ),
    );
  }
}

class _Overline extends StatelessWidget {
  final String text;
  const _Overline({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.violet,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            // letterSpacing breaks Bengali conjuncts — keep at 0.
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.textMuted,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _PatientCard extends StatelessWidget {
  final CaretakerPatientSummary patient;
  const _PatientCard({required this.patient});

  @override
  Widget build(BuildContext context) {
    final subtitle = patient.subtitleBn;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          context.read<CaretakerProvider>().selectPatient(patient.patientUserId);
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PatientDetailScreen(patient: patient),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Avatar(name: patient.fullName),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      patient.fullName.isEmpty
                          ? 'রোগী'
                          : patient.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _AdherenceRow(patient: patient),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textDim,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdherenceRow extends StatelessWidget {
  final CaretakerPatientSummary patient;
  const _AdherenceRow({required this.patient});

  @override
  Widget build(BuildContext context) {
    final medLabel = patient.medicineAdherence7d == null
        ? '—'
        : '${(patient.medicineAdherence7d! * 100).round()}%';
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        _Pill(
          icon: Icons.restaurant_rounded,
          label: patient.adherencePillBn,
          color: _adherenceColor(patient.mealAdherence7d),
        ),
        _Pill(
          icon: Icons.medication_rounded,
          label: 'ওষুধ $medLabel',
          color: _adherenceColor(patient.medicineAdherence7d),
        ),
      ],
    );
  }

  Color _adherenceColor(double? pct) {
    if (pct == null) return AppColors.textDim;
    if (pct >= 0.75) return AppColors.cyan;
    if (pct >= 0.50) return AppColors.amber;
    return AppColors.rose;
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Pill({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  const _Avatar({required this.name});

  @override
  Widget build(BuildContext context) {
    final initials = _initials(name);
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.violet.withValues(alpha: 0.85),
            AppColors.violetDeep,
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  String _initials(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return 'র';
    final parts = s.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts[0].isNotEmpty ? parts[0][0] : '') +
          (parts[1].isNotEmpty ? parts[1][0] : '');
    }
    return s.characters.first.toUpperCase();
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.violet.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.people_outline_rounded,
                color: AppColors.violetDeep,
                size: 30,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'এখনো কোনো রোগী সংযুক্ত নেই',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'নিচের “খোঁজা” ট্যাব থেকে মোবাইল নম্বর দিয়ে\nরোগীকে খুঁজে সংযোগের অনুরোধ পাঠান।',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: AppColors.textMuted,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(40),
        child: CircularProgressIndicator(
          strokeWidth: 3,
          color: AppColors.violet,
        ),
      ),
    );
  }
}

/// Red banner shown when `get_caretaker_patient_list` fails.
///
/// Most commonly this surfaces a missing RPC on the server (e.g. the
/// per-user adherence variants `get_meal_adherence_for` /
/// `get_medicine_logs_for` from `supabasesql/13_workouts.sql` haven't
/// been re-applied after the SQL was edited). Without this banner the
/// empty state hides the failure and makes the symptom look like a
/// data bug rather than a missing migration.
class _PatientErrorBanner extends StatelessWidget {
  final Object error;
  const _PatientErrorBanner({required this.error});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.rose.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.rose.withValues(alpha: 0.30)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.rose,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'রোগীর তালিকা লোড করা যায়নি',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.rose,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$error',
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
