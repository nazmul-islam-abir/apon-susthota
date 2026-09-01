/// Caretaker read-only doctor report view.
///
/// Loads the patient's 30-day report and renders the same PDF that the
/// patient would share with their doctor. Caretaker cannot edit the
/// underlying data — only view + share.
library;

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../models/caretaker_patient_summary.dart';
import '../../models/doctor_report_input.dart';
import '../../models/thirty_day_report.dart';
import '../../services/caretaker_data_service.dart';
import '../../services/report_pdf.dart';
import '../../theme/app_theme.dart';
import '../../widgets/caretaker_viewer_header.dart';
import '../../widgets/mono_widgets.dart';

class CaretakerDoctorReportView extends StatefulWidget {
  final CaretakerPatientSummary patient;
  const CaretakerDoctorReportView({super.key, required this.patient});

  @override
  State<CaretakerDoctorReportView> createState() => _CaretakerDoctorReportViewState();
}

class _CaretakerDoctorReportViewState extends State<CaretakerDoctorReportView> {
  late Future<_ReportData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ReportData> _load() async {
    final uid = widget.patient.patientUserId;
    final report = await CaretakerDataService.getThirtyDayReport(patientUserId: uid);
    if (report == null) {
      throw StateError('প্রতিবেদন পাওয়া যায়নি');
    }
    final profile = await CaretakerDataService.getProfile(uid);
    return _ReportBundle(
      report: report,
      identity: DoctorReportInput(
        patientName: widget.patient.fullName,
        patientAge: profile?['age'] as int?,
        diabetesType: profile?['diabetes_type'] as String?,
        doctorName: null,
        mobile: null,
        email: null,
      ),
    );
  }

  Future<void> _openPdf(_ReportBundle bundle) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: LoadingMark(size: 40)),
    );
    try {
      final bytes = await DoctorReportPdf.build(
        report: bundle.report,
        patientName: bundle.identity.displayNameOrFallback,
        patientAge: bundle.identity.patientAge,
        diabetesType: bundle.identity.diabetesType,
        doctorName: bundle.identity.doctorName,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF তৈরি ব্যর্থ: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.svcCategoryBg,
      body: Column(
        children: [
          CaretakerViewerHeader(
            patient: widget.patient,
            screenTitle: 'ডাক্তারের প্রতিবেদন',
            action: IconButton(
              icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white),
              onPressed: () {
                // Will only fire after data loads — see FutureBuilder below.
              },
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.svcHero,
              onRefresh: () async {
                setState(() => _future = _load());
                await _future;
              },
              child: FutureBuilder<_ReportData>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done && !snap.hasData) {
                    return const Center(child: CircularProgressIndicator(color: AppColors.svcHero));
                  }
                  if (snap.hasError) {
                    return _buildError('${snap.error}');
                  }
                  final bundle = snap.data!;
                  if (bundle is! _ReportBundle) {
                    return const SizedBox.shrink();
                  }
                  return CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    slivers: [
                      SliverToBoxAdapter(child: _buildHero(bundle)),
                      SliverToBoxAdapter(child: _buildSummary(bundle)),
                      SliverToBoxAdapter(child: _buildPreview(bundle)),
                      const SliverToBoxAdapter(child: SizedBox(height: 40)),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: FutureBuilder<_ReportData>(
            future: _future,
            builder: (context, snap) {
              if (!snap.hasData || snap.data is! _ReportBundle) {
                return const SizedBox.shrink();
              }
              return MonoButton(
                label: 'PDF দেখুন / শেয়ার করুন',
                leading: Icons.picture_as_pdf_rounded,
                onPressed: () => _openPdf(snap.data! as _ReportBundle),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildError(String message) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.rose, size: 48),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800,
                color: AppColors.smoke,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(_ReportBundle b) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: MonoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_today_rounded, color: AppColors.svcHero, size: 18),
                const SizedBox(width: 8),
                const Text(
                  '৩০ দিনের প্রতিবেদন',
                  style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w900,
                    color: AppColors.smoke, letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              b.report.cycleRangeLabel,
              style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'দিন ${b.report.dayOfCycle} / 30${b.report.cycleComplete ? ' (সম্পন্ন)' : ''}',
              style: const TextStyle(
                fontSize: 12, color: AppColors.smoke,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(_ReportBundle b) {
    final t = b.report.totals;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.8,
        children: [
          _stat('মোট খাবার', '${t.loggedMealsTotal}', '৩০ দিনে', AppColors.cyan),
          _stat('ওষুধ', '${t.medTakenTotal}', 'ডোজ নেওয়া', AppColors.mintDeep),
          _stat('পানি', '${(t.waterMlTotal / 1000).toStringAsFixed(1)} L', 'মোট', AppColors.violetDeep),
          _stat('ব্যায়াম', '${t.workoutMinutesTotal}', 'মিনিট', AppColors.amber),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, String hint, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.line, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w900,
              color: AppColors.smoke, letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w900,
              color: color, letterSpacing: -0.3,
            ),
          ),
          Text(
            hint,
            style: const TextStyle(
              fontSize: 10, color: AppColors.smoke,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(_ReportBundle b) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: MonoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'প্রতিবেদনে যা যা থাকবে',
              style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w900,
                color: AppColors.newsInk,
              ),
            ),
            const SizedBox(height: 12),
            _previewRow(Icons.calendar_today_rounded, '৩০ দিনের দৈনিক সারাংশ'),
            _previewRow(Icons.restaurant_rounded, 'খাবার ও ম্যাক্রো বিশ্লেষণ'),
            _previewRow(Icons.medication_rounded, 'ওষুধের ডোজ ও মিস'),
            _previewRow(Icons.water_drop_rounded, 'পানি ও ব্যায়াম'),
            _previewRow(Icons.mood_rounded, 'মেজাজ ও ঘুম'),
            _previewRow(Icons.person_rounded, 'রোগীর সনাক্তকরণ তথ্য'),
            const SizedBox(height: 8),
            Text(
              'PDF টি ডাক্তারের সাথে শেয়ার করা যাবে।',
              style: const TextStyle(
                fontSize: 11, color: AppColors.smoke,
                fontWeight: FontWeight.w700, height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewRow(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, color: AppColors.svcHero, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

abstract class _ReportData {}

class _ReportBundle extends _ReportData {
  final ThirtyDayReport report;
  final DoctorReportInput identity;
  _ReportBundle({required this.report, required this.identity});
}