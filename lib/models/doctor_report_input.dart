// lib/models/doctor_report_input.dart
//
// Bundle of typed identity fields the Doctor Report PDF + screen pull from
// user_profiles and auth metadata, so callers don't fan out a dozen getters
// across the PDF builder.
class DoctorReportInput {
  final String patientName;
  final int? patientAge;
  final String? diabetesType;
  final String? doctorName;
  final String? mobile;
  final String? email;

  const DoctorReportInput({
    required this.patientName,
    this.patientAge,
    this.diabetesType,
    this.doctorName,
    this.mobile,
    this.email,
  });

  factory DoctorReportInput.guest() => const DoctorReportInput(patientName: 'অতিথি');

  String get displayNameOrFallback =>
      patientName.trim().isEmpty ? 'রোগী' : patientName;
}
