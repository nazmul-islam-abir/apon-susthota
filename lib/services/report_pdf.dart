// lib/services/report_pdf.dart
//
// Builds the professional Bangla "ডাক্তারের রিপোর্ট" PDF for the 30-day patient cycle.
// Overhauled (v5) to include full day-by-day details (meals, meds, water, workout).
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/thirty_day_report.dart';
import 'supabase_service.dart';

class DoctorReportPdf {
  static Future<Uint8List> build({
    required ThirtyDayReport report,
    required String patientName,
    required int? patientAge,
    required String? diabetesType,
    String? doctorName,
  }) async {
    final regularData = await rootBundle.load('assets/fonts/NotoSansBengali-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/NotoSansBengali-Bold.ttf');
    final baseFont = pw.Font.ttf(regularData);
    final boldFont = pw.Font.ttf(boldData);

    final doc = pw.Document(title: 'ডাক্তারের রিপোর্ট');
    
    // Fetch full details for all active days to make the PDF exhaustive
    final List<DayFullReport> dayDetails = [];
    for (final d in report.days) {
      if (!d.isFuture && d.hasAnyActivity) {
        try {
          final detail = await SupabaseService.getDayFullReport(date: d.date);
          dayDetails.add(detail);
        } catch (_) {}
      }
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
        header: (ctx) => _header(report),
        footer: (ctx) => _footer(ctx, report),
        build: (ctx) => [
          _hero(report, patientName, patientAge, diabetesType, doctorName),
          pw.SizedBox(height: 20),
          _totalsGrid(report),
          pw.SizedBox(height: 24),
          pw.Text('প্রতিদিনের বিস্তারিত রিপোর্ট', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          for (final day in dayDetails) _dayDetailBlock(day),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _header(ThirtyDayReport r) => pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 8),
    decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5))),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('ডাক্তারের রিপোর্ট (৩০ দিন)', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.Text('প্রস্তুতকারক: আপন সুস্থতা অ্যাপ', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          ],
        ),
        pw.Text('রিপোর্ট তারিখ: ${DateFormat('d MMM yyyy').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      ],
    ),
  );

  static pw.Widget _footer(pw.Context ctx, ThirtyDayReport r) => pw.Container(
    padding: const pw.EdgeInsets.only(top: 8),
    decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('দিন ${r.dayOfCycle}/৩০ • গড় অনুপরতি ${r.totals.avgAdherencePct}%', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        pw.Text('পৃষ্ঠা ${ctx.pageNumber} / ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      ],
    ),
  );

  static pw.Widget _hero(ThirtyDayReport r, String name, int? age, String? type, String? doc) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: const pw.BoxDecoration(color: PdfColors.grey100),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(name, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.teal900)),
          pw.SizedBox(height: 4),
          pw.Row(
            children: [
              if (age != null) _kv('বয়স', '$age', flex: 1),
              _kv('ডায়াবেটিস', type ?? '—', flex: 2),
              _kv('ডাক্তার', doc ?? '—', flex: 2),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              _kv('চক্র শুরু', DateFormat('d MMM yyyy').format(r.cycleStart), flex: 1),
              _kv('অবস্থা', r.cycleComplete ? 'সম্পন্ন' : 'চলমান (দিন ${r.dayOfCycle})', flex: 1),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _kv(String k, String v, {int flex = 1}) => pw.Expanded(
    flex: flex,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(k, style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
        pw.Text(v, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
      ],
    ),
  );

  static pw.Widget _totalsGrid(ThirtyDayReport r) {
    final t = r.totals;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('৩০ দিনের সামগ্রিক সারাংশ', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey50),
              children: [
                _th('বিভাগ'), _th('পরিমাণ'), _th('লক্ষ্য/অনুপরতি'),
              ],
            ),
            _tr('খাবার', '${t.loggedMealsTotal} বার', '${t.mealAdherencePct.round()}%'),
            _tr('পানি', '${(t.waterMlTotal/1000).toStringAsFixed(1)}L', 'গড় ${(t.waterMlTotal/30/1000).toStringAsFixed(1)}L/দিন'),
            _tr('ওষুধ', '${t.medTakenTotal}/${t.medScheduledTotal}', '${(t.medAdherenceRatio*100).round()}%'),
            _tr('ব্যায়াম', '${t.workoutsCompleted} টি', '${t.workoutMinutesTotal} মিনিট'),
            _tr('ক্যালোরি', '${t.kcalTotal} kcal', 'গড় ${(t.kcalTotal/30).round()} kcal/দিন'),
          ],
        ),
      ],
    );
  }

  static pw.Widget _th(String t) => pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(t, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)));
  static pw.TableRow _tr(String a, String b, String c) => pw.TableRow(
    children: [
      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(a, style: const pw.TextStyle(fontSize: 9))),
      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(b, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(c, style: const pw.TextStyle(fontSize: 9))),
    ],
  );

  static pw.Widget _dayDetailBlock(DayFullReport d) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 16),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300, width: 0.5)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('${DateFormat('EEEE, d MMMM yyyy').format(d.date)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.teal800)),
              pw.Text('Kcal: ${d.macros.kcal} | Carb: ${d.macros.carbG}g | Prot: ${d.macros.proteinG}g', style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
          pw.SizedBox(height: 8),
          if (d.meals.isNotEmpty) _detailLine('খাবার', d.meals.map((m) => '${m.time}: ${m.nameBn.isEmpty ? m.nameEn : m.nameBn} (${m.impact})').join('; ')),
          if (d.meds.isNotEmpty) _detailLine('ওষুধ', d.meds.map((m) => '${m.scheduledAt}: ${m.name} (${m.status})').join('; ')),
          if (d.workouts.isNotEmpty) _detailLine('ব্যায়াম', d.workouts.map((w) => '${w.name} (${w.durationMin} মি)').join('; ')),
          if (d.waterLogs.isNotEmpty) _detailLine('পানি', '${d.waterLogs.length} বার (${d.waterLogs.fold(0, (sum, w) => sum + w.ml)} মিলি)'),
        ],
      ),
    );
  }

  static pw.Widget _detailLine(String label, String val) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 2),
    child: pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(text: '$label: ', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
          pw.TextSpan(text: val, style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    ),
  );
}
