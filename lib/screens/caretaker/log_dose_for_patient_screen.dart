/// Placeholder for the caretaker's "mark a medicine dose on the
/// patient's behalf" screen.
///
/// The real implementation needs the write-passthrough SQL
/// (`30_caretaker_write_passthrough.sql` — currently doc-only).
/// Until that lands this stub renders a friendly Bangla "coming
/// soon" surface so the navigation button on the patient detail
/// screen still compiles and responds to taps.
library;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class LogDoseForPatientScreen extends StatelessWidget {
  final String patientUserId;
  final String? patientName;
  const LogDoseForPatientScreen({
    super.key,
    required this.patientUserId,
    this.patientName,
  });

  @override
  Widget build(BuildContext context) {
    final name = (patientName ?? '').trim();
    return Scaffold(
      backgroundColor: AppColors.void2,
      appBar: AppBar(
        backgroundColor: AppColors.void2,
        foregroundColor: AppColors.text,
        title: const Text(
          'রোগীর পক্ষে ওষুধ লগ',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.cyan.withValues(alpha: 0.16),
                      AppColors.violet.withValues(alpha: 0.10),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.medication_rounded,
                  color: AppColors.cyanDeep,
                  size: 44,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                name.isEmpty
                    ? 'রোগীর পক্ষে ওষুধ �গ'
                    : '$name-এর পক্ষে ওষুধ লগ',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'শীঘ্রই আসছে। পরিচর্যাকারীর পক্ষে �ষুধের ডোজ '
                'চিহ্নিত করতে SQL RPC (write-passthrough) প্রয়োজন।',
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
      ),
    );
  }
}