/// Patients tab — the caretaker's home screen (Nexora Redesign).
///
/// Shows the list of active patients with high-fidelity technical styling.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/caretaker_patient_summary.dart';
import '../../models/user_profile.dart';
import '../../services/caretaker_provider.dart';
import '../../theme/app_theme.dart';
import 'caretaker_empty_state.dart';
import 'caretaker_doctor_profile_screen.dart';
import 'caretaker_shell.dart' show bnGreeting;
import 'patient_detail_screen.dart';

class PatientsTab extends StatefulWidget {
  final UserProfile? profile;
  final ValueChanged<int>? onSwitchTab;
  const PatientsTab({super.key, this.profile, this.onSwitchTab});

  @override
  State<PatientsTab> createState() => _PatientsTabState();
}

class _PatientsTabState extends State<PatientsTab> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.svcCategoryBg,
      body: Consumer<CaretakerProvider>(
        builder: (context, prov, _) {
          return RefreshIndicator(
            color: AppColors.svcHero,
            onRefresh: prov.refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              slivers: [
                _buildHero(prov),
                const SliverToBoxAdapter(child: SizedBox(height: 22)),
                
                if (prov.patientError != null)
                  SliverToBoxAdapter(child: _PatientErrorBanner(error: prov.patientError!)),
                
                if (prov.patients.isEmpty && prov.pending.isEmpty && widget.onSwitchTab != null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: CaretakerEmptyState(onSwitchTab: widget.onSwitchTab!),
                  )
                else ...[
                  SliverToBoxAdapter(child: _buildSectionTitle('সংযুক্ত রোগী', 'আপনার তত্ত্বাবধানে')),
                  if (prov.loadingPatients && prov.patients.isEmpty)
                    const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: AppColors.svcHero)))
                  else if (prov.patients.isEmpty)
                    const SliverFillRemaining(child: _EmptyState())
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 140),
                      sliver: SliverList.separated(
                        itemCount: prov.patients.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => _PatientCard(patient: prov.patients[i]),
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

  Widget _buildHero(CaretakerProvider prov) {
    const url = 'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/app/photo-1564352969906-8b7f46ba4b8b.avif?token=eyJraWQiOiJhZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJhcHAvcGhvdG8tMTU2NDM1Mjk2OTkwNi04YjdmNDZiYTRiOGIuYXZpZiIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODc4Njg2MjksImV4cCI6MTgxOTQwNDYyOX0.Jdl-6cqT6wHh_nv8j-7oD3zjU2KcoR4e5ohJVnZgTNs';
    final name = (widget.profile?.fullName ?? '').trim();
    final greeting = name.isEmpty ? bnGreeting() : '${bnGreeting()}, ${name.split(' ').first}';

    return SliverToBoxAdapter(
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.svcHero,
          image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover, opacity: 0.7),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: Container(color: Colors.black.withValues(alpha: 0.35))),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SafeArea(bottom: false, child: SizedBox(height: 20)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(greeting, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -1)),
                      const SizedBox(height: 8),
                      Text(
                        'আপনার ${prov.patients.length} জন সংযুক্ত রোগী'
                        '${prov.pending.isNotEmpty ? ' • ${prov.pending.length}টি অনুরোধ অপেক্ষমাণ' : ''}',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.zero, border: Border.all(color: Colors.white24)),
                        child: const Text('পরিচর্যাকারী মোড', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, String sub) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.newsInk, letterSpacing: -0.3)),
                Text(sub, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.newsMuted.withValues(alpha: 0.8))),
              ],
            ),
          ),
          InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const CaretakerDoctorProfileScreen(),
            )),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.svcHero,
                borderRadius: BorderRadius.zero,
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.medical_services_rounded, color: Colors.white, size: 14),
                  SizedBox(width: 6),
                  Text(
                    'আমার প্রোফাইল',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
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
    final mealPct = patient.mealAdherence7d ?? 0.0;
    final medPct = patient.medicineAdherence7d ?? 0.0;

    return InkWell(
      onTap: () {
        context.read<CaretakerProvider>().selectPatient(patient.patientUserId);
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => PatientDetailScreen(patient: patient)));
      },
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: AppColors.line, width: 1.2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 12, offset: const Offset(0, 6))],
        ),
        child: Column(
          children: [
            Row(
              children: [
                _Avatar(name: patient.fullName, avatarUrl: patient.avatarUrl, size: 56),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        patient.fullName.isEmpty ? 'রোগী' : patient.fullName,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.ink, height: 1.1),
                      ),
                      const SizedBox(height: 4),
                      Text(patient.subtitleBn, style: const TextStyle(fontSize: 12, color: AppColors.smoke, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.lineStrong, size: 16),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: _CompactProgress(label: 'খাবার', value: mealPct, color: AppColors.svcHero)),
                const SizedBox(width: 20),
                Expanded(child: _CompactProgress(label: 'ওষুধ', value: medPct, color: AppColors.mintDeep)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactProgress extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _CompactProgress({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.smoke, letterSpacing: 0.5)),
            Text('${(value * 100).round()}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: color)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.zero,
          child: Container(
            height: 4,
            width: double.infinity,
            color: color.withValues(alpha: 0.1),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: Container(color: color),
            ),
          ),
        ),
      ],
    );
  }
}

class _AdherenceRow extends StatelessWidget {
  final CaretakerPatientSummary patient;
  const _AdherenceRow({required this.patient});

  @override
  Widget build(BuildContext context) {
    final medLabel = patient.medicineAdherence7d == null ? '—' : '${(patient.medicineAdherence7d! * 100).round()}%';
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        _TechnicalPill(icon: Icons.restaurant_rounded, label: patient.adherencePillBn, pct: patient.mealAdherence7d),
        _TechnicalPill(icon: Icons.medication_rounded, label: 'ওষুধ $medLabel', pct: patient.medicineAdherence7d),
      ],
    );
  }
}

class _TechnicalPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final double? pct;
  const _TechnicalPill({required this.icon, required this.label, this.pct});

  @override
  Widget build(BuildContext context) {
    final color = _adherenceColor(pct);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.zero, border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: color, height: 1.0)),
        ],
      ),
    );
  }

  Color _adherenceColor(double? pct) {
    if (pct == null) return AppColors.smoke;
    if (pct >= 0.75) return AppColors.svcHero;
    if (pct >= 0.50) return AppColors.amber;
    return AppColors.rose;
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final double size;
  const _Avatar({required this.name, this.avatarUrl, this.size = 52});

  @override
  Widget build(BuildContext context) {
    final initials = _initials(name);
    final url = avatarUrl?.trim();
    final hasAvatar = url != null && url.isNotEmpty;

    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: AppColors.svcHero,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.svcHeroAccent, width: 1.5),
      ),
      clipBehavior: Clip.hardEdge,
      alignment: Alignment.center,
      child: hasAvatar
          ? Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Text(
                initials,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.35,
                  fontWeight: FontWeight.w900,
                ),
              ),
              loadingBuilder: (ctx, child, p) {
                if (p == null) return child;
                return Text(
                  initials,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: size * 0.35,
                    fontWeight: FontWeight.w900,
                  ),
                );
              },
            )
          : Text(
              initials,
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.35,
                fontWeight: FontWeight.w900,
              ),
            ),
    );
  }

  String _initials(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return 'র';
    final parts = s.split(RegExp(r'\s+'));
    if (parts.length >= 2) return (parts[0][0]) + (parts[1][0]);
    return s.characters.first.toUpperCase();
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.people_outline_rounded, color: AppColors.lineStrong, size: 64),
          const SizedBox(height: 16),
          const Text('এখনো কোনো রোগী সংযুক্ত নেই', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.ink)),
          const SizedBox(height: 8),
          const Text('“খোঁজা” ট্যাব থেকে মোবাইল নম্বর দিয়ে\nরোগীকে খুঁজে সংযোগের অনুরোধ পাঠান।', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.smoke, height: 1.4)),
        ],
      ),
    );
  }
}

class _PatientErrorBanner extends StatelessWidget {
  final Object error;
  const _PatientErrorBanner({required this.error});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.rose.withValues(alpha: 0.08), borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.rose.withValues(alpha: 0.3))),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.rose, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text('লোড করা যায়নি: $error', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.rose))),
          ],
        ),
      ),
    );
  }
}
