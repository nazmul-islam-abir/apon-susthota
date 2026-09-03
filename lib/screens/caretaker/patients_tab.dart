/// Patients tab — the caretaker's home screen (Nexora Redesign).
///
/// Shows the list of active patients with high-fidelity technical styling.
/// The patient card visual treatment is shared with the home dashboard via
/// `CaretakerPatientCard` (see `lib/widgets/caretaker_patient_card.dart`).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user_profile.dart';
import '../../services/caretaker_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/caretaker_patient_card.dart';
import 'caretaker_doctor_profile_screen.dart';
import 'caretaker_empty_state.dart';
import 'caretaker_shell.dart' show bnGreeting;

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
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                _buildHero(prov),
                const SliverToBoxAdapter(child: SizedBox(height: 22)),
                if (prov.patientError != null)
                  SliverToBoxAdapter(
                    child: _PatientErrorBanner(error: prov.patientError!),
                  ),
                if (prov.patients.isEmpty &&
                    prov.pending.isEmpty &&
                    widget.onSwitchTab != null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: CaretakerEmptyState(onSwitchTab: widget.onSwitchTab!),
                  )
                else ...[
                  SliverToBoxAdapter(
                    child: _buildSectionTitle('সংযুক্ত রোগী', 'আপনার তত্ত্বাবধানে'),
                  ),
                  if (prov.loadingPatients && prov.patients.isEmpty)
                    const SliverFillRemaining(
                      child: Center(
                        child: CircularProgressIndicator(color: AppColors.svcHero),
                      ),
                    )
                  else if (prov.patients.isEmpty)
                    const SliverFillRemaining(child: _EmptyState())
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                      sliver: SliverList.separated(
                        itemCount: prov.patients.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) =>
                            CaretakerPatientCard(patient: prov.patients[i]),
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
    const url =
        'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/app/photo-1564352969906-8b7f46ba4b8b.avif?token=eyJraWQiOiJhZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJhcHAvcGhvdG8tMTU2NDM1Mjk2OTkwNi04YjdmNDZiYTRiOGIuYXZpZiIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODc4Njg2MjksImV4cCI6MTgxOTQwNDYyOX0.Jdl-6cqT6wHh_nv8j-7oD3zjU2KcoR4e5ohJVnZgTNs';
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
                      Text(
                        greeting,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'আপনার ${prov.patients.length} জন সংযুক্ত রোগী'
                        '${prov.pending.isNotEmpty ? ' • ${prov.pending.length}টি অনুরোধ অপেক্ষমাণ' : ''}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.zero,
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Text(
                          'পরিচর্যাকারী মোড',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
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
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.newsInk,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  sub,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.newsMuted.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const CaretakerDoctorProfileScreen(),
              ),
            ),
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
          const Text(
            'এখনো কোনো রোগী সংযুক্ত নেই',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.ink),
          ),
          const SizedBox(height: 8),
          const Text(
            '“খোঁজা” ট্যাব থেকে মোবাইল নম্বর দিয়ে\nরোগীকে খুঁজে সংযোগের অনুরোধ পাঠান।',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.smoke, height: 1.4),
          ),
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
        decoration: BoxDecoration(
          color: AppColors.rose.withValues(alpha: 0.08),
          borderRadius: BorderRadius.zero,
          border: Border.all(color: AppColors.rose.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.rose, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'লোড করা যায়নি: $error',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.rose,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}