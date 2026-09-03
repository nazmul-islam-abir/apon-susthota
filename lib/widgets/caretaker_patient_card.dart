/// Reusable patient card for the caretaker dashboard and patient-list tab.
///
/// Extracted from `lib/screens/caretaker/patients_tab.dart` so the new home
/// dashboard and any future caretaker-facing list can share the same
/// high-fidelity visual treatment (avatar + name + meal/medicine progress).
library;

import 'package:flutter/material.dart';

import '../models/caretaker_patient_summary.dart';
import '../screens/caretaker/patient_detail_screen.dart';
import '../services/caretaker_provider.dart';
import '../theme/app_theme.dart';
import 'package:provider/provider.dart';

class CaretakerPatientCard extends StatelessWidget {
  final CaretakerPatientSummary patient;
  const CaretakerPatientCard({super.key, required this.patient});

  @override
  Widget build(BuildContext context) {
    final mealPct = patient.mealAdherence7d ?? 0.0;
    final medPct = patient.medicineAdherence7d ?? 0.0;

    return InkWell(
      onTap: () {
        context.read<CaretakerProvider>().selectPatient(patient.patientUserId);
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PatientDetailScreen(patient: patient)),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: AppColors.line, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
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
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.ink,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        patient.subtitleBn,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.smoke,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: AppColors.lineStrong,
                  size: 16,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _CompactProgress(
                    label: 'খাবার',
                    value: mealPct,
                    color: AppColors.svcHero,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: _CompactProgress(
                    label: 'ওষুধ',
                    value: medPct,
                    color: AppColors.mintDeep,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class CaretakerCompactProgress extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const CaretakerCompactProgress({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return _CompactProgress(label: label, value: value, color: color);
  }
}

class _CompactProgress extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _CompactProgress({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: AppColors.smoke,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              '${(value * 100).round()}%',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
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
      width: size,
      height: size,
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
