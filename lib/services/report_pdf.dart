// lib/services/report_pdf.dart
//
// Builds the Bangla "ডাক্তারের রিপোর্ট" PDF for the 30-day patient cycle.
// Uses `package:pdf` for layout and `package:printing` for the preview / share
// entrypoint. Bangla glyphs are rendered with the bundled NotoSansBengali
// TTF (assets/fonts/) — built-in PDF fonts (Helvetica) only contain Latin
// glyphs and would otherwise render Bangla as the .notdef glyph.
//
// Output: a single multi-page `Uint8List` ready for Printing.layoutPdf() or
// for emailing via Printing.sharePdf().
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/thirty_day_report.dart';

class DoctorReportPdf {
  /// Single-shot builder: maps typed models → a multi-page Bangla PDF.
  ///
  /// Bangla glyphs require a TTF that actually contains Bengali codepoints.
  /// `pw.Font.helvetica()` only ships Latin glyphs, so the built-in fonts
  /// rendered every Bangla string as the `.notdef` glyph (a hollow box).
  /// We bundle NotoSansBengali (Regular + Bold) under `assets/fonts/` and
  /// load those bytes here. Both fonts are declared in `pubspec.yaml` under
  /// `flutter.fonts` so the asset bundle ships them with the app.
  static Future<Uint8List> build({
    required ThirtyDayReport report,
    required String patientName,
    required int? patientAge,
    required String? diabetesType,
    String? doctorName,
  }) async {
    final regularData =
        await rootBundle.load('assets/fonts/NotoSansBengali-Regular.ttf');
    final boldData =
        await rootBundle.load('assets/fonts/NotoSansBengali-Bold.ttf');
    final baseFont = pw.Font.ttf(regularData);
    final boldFont = pw.Font.ttf(boldData);

    final doc = pw.Document(title: 'ডাক্তারের রিপোর্ট');

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 32, 28, 32),
        theme: pw.ThemeData.withFont(
          base: baseFont,
          bold: boldFont,
        ),
        header: (ctx) => _header(report),
        footer: (ctx) => _footer(ctx, report),
        build: (ctx) => [
          _hero(report, patientName, patientAge, diabetesType, doctorName),
          pw.SizedBox(height: 14),
          _totalsTable(report),
          pw.SizedBox(height: 16),
          _daySectionTitle(),
          pw.SizedBox(height: 4),
          ..._dayRows(report),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _header(ThirtyDayReport r) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'ডাক্তারের রিপোর্ট (৩০ দিনের চক্র)',
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'আমার ডায়েট  ·  অ্যাপ:  amar-diet',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'চক্র শুরু: ${DateFormat('d MMM yyyy').format(r.cycleStart)}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
                pw.Text(
                  'রিপোর্ট তৈরি: ${DateFormat('d MMM yyyy, HH:mm').format(DateTime.now())}',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                ),
              ],
            ),
          ],
        ),
      );

  static pw.Widget _footer(pw.Context ctx, ThirtyDayReport r) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'দিন ${r.dayOfCycle} / ৩০  ·  অগ্রগতি ${(r.cycleProgress * 100).round()}%',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
            pw.Text(
              'পৃষ্ঠা ${ctx.pageNumber} / ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ],
        ),
      );

  static pw.Widget _hero(
    ThirtyDayReport r,
    String patientName,
    int? age,
    String? diabetesType,
    String? doctorName,
  ) {
    final df = DateFormat('d MMM yyyy');
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'রোগীর তথ্য',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _kv('নাম', patientName, flex: 3),
              _kv('বয়স', age == null ? '—' : '$age', flex: 1),
              _kv('ধরন', diabetesType ?? '—', flex: 2),
              _kv('ডাক্তার', doctorName ?? '—', flex: 2),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              _kv('চক্র শুরু', df.format(r.cycleStart), flex: 2),
              _kv('চক্র শেষ', df.format(r.cycleStart.add(const Duration(days: 29))), flex: 2),
              _kv('আজ', df.format(r.today), flex: 2),
              _kv('অবস্থান', 'দিন ${r.dayOfCycle} / ৩০', flex: 2),
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
            pw.Text(k,
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            pw.Text(v,
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );

  static pw.Widget _totalsTable(ThirtyDayReport r) {
    final t = r.totals;
    final medPct = (t.medAdherenceRatio * 100).round();
    final waterLiters = (t.waterMlTotal / 1000).toStringAsFixed(1);
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('৩০ দিনের সারাংশ',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Table(
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(2),
              2: pw.FlexColumnWidth(3),
              3: pw.FlexColumnWidth(2),
            },
            border: pw.TableBorder.symmetric(
              inside: const pw.BorderSide(color: PdfColors.grey300, width: 0.5),
            ),
            children: [
              _row('মোট পরিকল্পিত খাবার', '${t.plannedMealsTotal}',
                  'মোট লগকৃত খাবার', '${t.loggedMealsTotal}'),
              _row('ভালো / মাঝারি / খারাপ / অফপ্ল্যান',
                  '${t.goodMeals}/${t.moderateMeals}/${t.badMeals}/${t.offplanMeals}',
                  'খাবার অনুপরতি %',
                  '${t.mealAdherencePct.round()}%'),
              _row('মোট ক্যালোরি', '${t.kcalTotal} kcal',
                  'গড় অনুপরতি', '${t.avgAdherencePct}%'),
              _row('মোট পানি', '$waterLiters লিটার',
                  'লক্ষ্য (১.৫ লি/দিন)', '${(t.waterMlTotal / 1500).toStringAsFixed(1)} দিন'),
              _row('ওষুধ নেওয়া / সময়সূচী', '${t.medTakenTotal} / ${t.medScheduledTotal}',
                  'ওষুধ অনুপরতি', '$medPct%'),
              _row('ব্যায়াম সম্পন্ন', '${t.workoutsCompleted}',
                  'ব্যায়াম মোট সময়', '${t.workoutMinutesTotal} মিনিট'),
              _row('সক্রিয় দিন', '${t.daysLogged} / ৩০',
                  'চক্র অবস্থা',
                  r.cycleComplete ? 'পূর্ণ' : 'চলমান'),
            ],
          ),
        ],
      ),
    );
  }

  static pw.TableRow _row(String a, String av, String b, String bv) => pw.TableRow(
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(a, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800)),
                pw.Text(av,
                    style:
                        pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(b, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800)),
                pw.Text(bv,
                    style:
                        pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
        ],
      );

  static pw.Widget _daySectionTitle() => pw.Container(
        alignment: pw.Alignment.centerLeft,
        padding: const pw.EdgeInsets.only(top: 4, bottom: 4),
        child: pw.Text('দিন-ভিত্তিক বিস্তারিত (খাবার / পানি / ওষুধ / ব্যায়াম)',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      );

  static List<pw.Widget> _dayRows(ThirtyDayReport r) {
    final rows = <pw.Widget>[];
    final df = DateFormat('d MMM');

    for (final day in r.days) {
      rows.add(pw.Container(
        margin: const pw.EdgeInsets.only(top: 4, bottom: 4),
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          color: day.isToday
              ? PdfColors.blue50
              : (day.isFuture ? PdfColors.grey100 : PdfColors.white),
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'দিন ${day.dayOfCycle}  ·  ${day.bnWeekday}  ·  ${df.format(day.date)}',
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  'অনুপরতি ${day.adherencePct}%',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: _pdfAdherenceColor(day.adherencePct),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(_mealLine(day), style: const pw.TextStyle(fontSize: 9)),
                pw.Text(_medLine(day), style: const pw.TextStyle(fontSize: 9)),
                pw.Text(_workoutLine(day), style: const pw.TextStyle(fontSize: 9)),
                pw.Text(_waterLine(day), style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
            if (day.macros.kcal > 0 ||
                day.medicine.scheduled > 0 ||
                day.workouts.minutes > 0 ||
                day.waterMl > 0) ...[
              pw.SizedBox(height: 4),
              pw.Text(
                _macroLine(day),
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
              ),
            ],
          ],
        ),
      ));
    }
    return rows;
  }

  static String _mealLine(ThirtyDayReportDay d) {
    if (d.plannedMeals == 0 && d.loggedMeals.total == 0 && !d.isFuture) {
      return 'খাবার: কোনো রেকর্ড নেই';
    }
    if (d.isFuture) return 'খাবার: আগামী দিন';
    return 'খাবার: ${d.loggedMeals.good} ভালো · '
        '${d.loggedMeals.moderate} মাঝারি · '
        '${d.loggedMeals.bad} খারাপ · '
        '${d.loggedMeals.offplan} অফপ্ল্যান  '
        '(${d.loggedMeals.total}/${d.plannedMeals})';
  }

  static String _medLine(ThirtyDayReportDay d) {
    if (d.medicine.scheduled == 0 && d.medicine.taken == 0) return 'ওষুধ: —';
    return 'ওষুধ: ${d.medicine.taken}/${d.medicine.scheduled}'
        '${d.medicine.missed > 0 ? ' (মিস ${d.medicine.missed})' : ''}';
  }

  static String _workoutLine(ThirtyDayReportDay d) {
    if (d.workouts.doneAny == 0 && d.workouts.minutes == 0) return 'ব্যায়াম: —';
    return 'ব্যায়াম: ${d.workouts.completed} সম্পন্ন'
        '${d.workouts.partial > 0 ? ' + ${d.workouts.partial} আংশিক' : ''}'
        ' (${d.workouts.minutes} মিনিট)';
  }

  static String _waterLine(ThirtyDayReportDay d) {
    if (d.waterMl == 0) return 'পানি: —';
    return 'পানি: ${d.waterMl} মিলি';
  }

  static String _macroLine(ThirtyDayReportDay d) {
    if (d.macros.kcal == 0 && d.medicine.scheduled == 0) return '';
    final parts = <String>[];
    if (d.macros.kcal > 0) {
      parts.add('ক্যালোরি ${d.macros.kcal} ক্যাল · '
          'কার্ব ${d.macros.carbG}g · '
          'প্রোটিন ${d.macros.proteinG}g · '
          'ফ্যাট ${d.macros.fatG}g · '
          'সোডিয়াম ${d.macros.sodiumMg}mg');
    }
    if (d.workouts.minutes > 0) parts.add('ব্যায়াম ${d.workouts.minutes} মিনিট');
    return parts.join('   ·   ');
  }

  static PdfColor _pdfAdherenceColor(int pct) {
    if (pct >= 80) return PdfColors.green700;
    if (pct >= 55) return PdfColors.amber700;
    return PdfColors.red700;
  }
}
