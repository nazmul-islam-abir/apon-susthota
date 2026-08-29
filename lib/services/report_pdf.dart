// lib/services/report_pdf.dart
//
// Builds the high-fidelity professional Bangla "ডাক্তারের রিপোর্ট" PDF.
// Reverted to stable bangla_pdf and optimized for performance.
import 'dart:typed_data';

import 'package:bangla_pdf/bangla_pdf.dart' as b_pdf;
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
    // 1. Load fonts for fallback rendering (bangla_pdf handles primary shaping)
    final regularData = await rootBundle.load('assets/fonts/NotoSansBengali-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/NotoSansBengali-Bold.ttf');
    final baseFont = pw.Font.ttf(regularData);
    final boldFont = pw.Font.ttf(boldData);

    final doc = pw.Document(title: 'ডাক্তারের রিপোর্ট');
    
    // 2. Parallel fetch for all daily logs to avoid timeouts
    final activeDays = report.days.where((d) => !d.isFuture && d.hasAnyActivity).toList();
    final List<DayFullReport> dayDetails = await Future.wait(
      activeDays.map((d) => SupabaseService.getDayFullReport(date: d.date).catchError((_) {
        return DayFullReport(
          date: d.date, 
          isToday: d.isToday, 
          isFuture: false, 
          mealsSummary: {}, 
          macros: const DayMacros(), 
          meals: [], 
          meds: [], 
          waterLogs: [], 
          workouts: []
        );
      }))
    );

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
          _summaryGrid(report),
          pw.SizedBox(height: 24),
          pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 5),
            decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.teal900, width: 1.5))),
            child: b_pdf.Text(
              'প্রতিদিনের বিস্তারিত রিপোর্ট (খাবার, ওষুধ, ব্যায়াম ও পানি)',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.teal900),
            ),
          ),
          pw.SizedBox(height: 12),
          for (final day in dayDetails) _dayBlock(day, report.dayByDate(day.date)),
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
            b_pdf.Text('ডাক্তারের রিপোর্ট (৩০ দিন)', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            b_pdf.Text('প্রস্তুতকারক: আপন সুস্থতা অ্যাপ', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          ],
        ),
        b_pdf.Text('তারিখ: ${DateFormat('d MMM yyyy').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      ],
    ),
  );

  static pw.Widget _footer(pw.Context ctx, ThirtyDayReport r) => pw.Container(
    padding: const pw.EdgeInsets.only(top: 8),
    decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        b_pdf.Text('দিন ${r.dayOfCycle}/৩০ • গড় ধারাবাহিকতা ${r.totals.avgAdherencePct}%', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        b_pdf.Text('পৃষ্ঠা ${ctx.pageNumber} / ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      ],
    ),
  );

  static pw.Widget _hero(ThirtyDayReport r, String name, int? age, String? type, String? doc) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: const pw.BoxDecoration(color: PdfColors.teal50),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          b_pdf.Text(name, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.teal900)),
          pw.SizedBox(height: 6),
          pw.Row(
            children: [
              if (age != null) _kv('বয়স', '$age বছর', flex: 1),
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
        b_pdf.Text(k, style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
        b_pdf.Text(v, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.teal800)),
      ],
    ),
  );

  static pw.Widget _summaryGrid(ThirtyDayReport r) {
    final t = r.totals;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        b_pdf.Text('৩০ দিনের সামগ্রিক সারাংশ', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
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

  static pw.Widget _th(String t) => pw.Padding(padding: const pw.EdgeInsets.all(6), child: b_pdf.Text(t, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)));
  static pw.TableRow _tr(String a, String b, String c) => pw.TableRow(
    children: [
      pw.Padding(padding: const pw.EdgeInsets.all(6), child: b_pdf.Text(a, style: const pw.TextStyle(fontSize: 9))),
      pw.Padding(padding: const pw.EdgeInsets.all(6), child: b_pdf.Text(b, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
      pw.Padding(padding: const pw.EdgeInsets.all(6), child: b_pdf.Text(c, style: const pw.TextStyle(fontSize: 9))),
    ],
  );

  static pw.Widget _dayBlock(DayFullReport d, ThirtyDayReportDay? meta) {
    final adherence = meta?.adherencePct ?? 0;
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 16),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300, width: 0.5)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            color: PdfColors.grey50,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                b_pdf.Text('${DateFormat('EEEE, d MMMM yyyy').format(d.date)} (দিন ${meta?.dayOfCycle})', 
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.teal800)),
                b_pdf.Text('অনুপরতি: $adherence%', 
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: adherence >= 80 ? PdfColors.green700 : PdfColors.orange700)),
              ],
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5))),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _miniMacro('Kcal', '${d.macros.kcal}'),
                _miniMacro('Carb', '${d.macros.carbG}g'),
                _miniMacro('Prot', '${d.macros.proteinG}g'),
                _miniMacro('Fat', '${d.macros.fatG}g'),
              ],
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(10),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (d.meals.isNotEmpty) _cat('খাবার', d.meals.map((m) => '${m.time}: ${m.nameBn.isEmpty ? m.nameEn : m.nameBn} (${m.impact})').join('; '), PdfColors.orange800),
                if (d.meds.isNotEmpty) _cat('ওষুধ', d.meds.map((m) => '${m.scheduledAt}: ${m.name} (${m.status})').join('; '), PdfColors.purple800),
                if (d.workouts.isNotEmpty) _cat('ব্যায়াম', d.workouts.map((w) => '${w.name} (${w.durationMin} মি)').join('; '), PdfColors.teal800),
                if (d.waterLogs.isNotEmpty) _cat('পানি', '${d.waterLogs.length} বার পানে ${d.waterLogs.fold(0, (sum, w) => sum + w.ml)} মিলি', PdfColors.blue800),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _miniMacro(String k, String v) => pw.Column(
    children: [
      b_pdf.Text(k, style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
      b_pdf.Text(v, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
    ],
  );

  static pw.Widget _cat(String title, String val, PdfColor color) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: b_pdf.Text(
        '$title: $val',
        style: pw.TextStyle(fontSize: 8, color: PdfColors.grey800),
      ),
    );
  }
}
