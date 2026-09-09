import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'arabic_pdf_text.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/storage/yalla_storage_service.dart';
import 'package:yalla_accounts/features/settings/models/workshop_settings.dart';
import 'package:yalla_accounts/features/settings/services/workshop_settings_service.dart';

/// Both ledger screens export the complete selected period from the GL.
/// Search results are not an account balance and must not become a statement.
class AccountLedgerPdf {
  static Future<Uint8List> generateForAccount(int accountId,
      {DateTime? from, DateTime? to}) async {
    if (from != null && to != null && from.isAfter(to)) {
      throw ArgumentError('بداية الفترة بعد نهايتها');
    }
    final db = await DBService.database;
    final ws = await WorkshopSettingsService.instance.getOrDefaults();
    final snapshot = await db.transaction((txn) async {
      final accounts =
          await txn.query('accounts', where: 'id=?', whereArgs: [accountId]);
      if (accounts.isEmpty) throw StateError('الحساب غير موجود');
      final start =
          from == null ? null : DateFormat('yyyy-MM-dd', 'en').format(from);
      final end = to == null ? null : DateFormat('yyyy-MM-dd', 'en').format(to);
      final openingRows = start == null
          ? null
          : await txn.rawQuery(
              'SELECT COALESCE(SUM(l.debit-l.credit),0) balance FROM gl_lines l JOIN gl_entries e ON e.id=l.entry_id WHERE l.account_id=? AND substr(e.date,1,10)<?',
              [accountId, start]);
      final rows = await txn.rawQuery(
          'SELECT e.date, e.ref, e.note, e.source, e.source_id, l.debit, l.credit FROM gl_lines l JOIN gl_entries e ON e.id=l.entry_id WHERE l.account_id=?'
          '${start == null ? '' : ' AND substr(e.date,1,10)>=?'}'
          '${end == null ? '' : ' AND substr(e.date,1,10)<=?'} ORDER BY e.date,e.id,l.id',
          [accountId, if (start != null) start, if (end != null) end]);
      return (
        accounts.single,
        openingRows == null
            ? 0.0
            : (openingRows.single['balance'] as num).toDouble(),
        rows
      );
    });
    return generate(
        workshop: ws,
        accountName: '${snapshot.$1['code']} - ${snapshot.$1['name']}',
        from: from,
        to: to,
        opening: snapshot.$2,
        rows: snapshot.$3);
  }

  static Future<Uint8List> generate(
      {required WorkshopSettings workshop,
      required String accountName,
      DateTime? from,
      DateTime? to,
      required double opening,
      required List<Map<String, Object?>> rows}) async {
    // Required embedded fonts: fail closed rather than emit Helvetica squares.
    final regular = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf'));
    final bold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoNaskhArabic-Bold.ttf'));
    final latin =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Tahoma-Regular.ttf'));
    final doc = pw.Document(
        theme: pw.ThemeData.withFont(
            base: regular, bold: bold, fontFallback: [latin]));
    pw.MemoryImage? logo;
    if ((workshop.logoPath ?? '').isNotEmpty) {
      final path =
          await YallaStorageService.resolveExistingPath(workshop.logoPath!);
      if (path != null) logo = pw.MemoryImage(await File(path).readAsBytes());
    }
    final money = NumberFormat('#,##0.00', 'en');
    String amount(double n) => money.format(n);
    String date(DateTime? d, String otherwise) =>
        d == null ? otherwise : DateFormat('yyyy-MM-dd', 'en').format(d);
    pw.Widget text(String value,
        {bool number = false, bool strong = false, double size = 10}) {
      final style = pw.TextStyle(
          font: number ? latin : (strong ? bold : regular), fontSize: size);
      return number
          ? pw.Text(value, textDirection: pw.TextDirection.ltr, style: style)
          : ArabicPdfText.build(value, style: style, latin: latin);
    }

    pw.Widget cell(String value, {bool number = false, bool strong = false}) =>
        pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: text(value, number: number, strong: strong));
    double debit = 0, credit = 0, balance = opening;
    final entries = <pw.TableRow>[];
    entries.add(pw.TableRow(children: [
      cell(amount(opening), number: true),
      cell(''),
      cell(''),
      cell('رصيد افتتاحي', strong: true),
      cell(date(from, '-'), number: true)
    ]));
    for (final row in rows) {
      final d = (row['debit'] as num?)?.toDouble() ?? 0;
      final c = (row['credit'] as num?)?.toDouble() ?? 0;
      if (!d.isFinite || !c.isFinite || d < 0 || c < 0) {
        throw StateError('قيمة قيد غير صالحة');
      }
      debit += d;
      credit += c;
      balance += d - c;
      final description = (row['description'] ?? row['note'] ?? '').toString();
      final reference = (row['ref'] ?? row['source_id'] ?? '').toString();
      entries.add(pw.TableRow(children: [
        cell(amount(balance), number: true),
        cell(amount(c), number: true),
        cell(amount(d), number: true),
        pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  text(description.isEmpty ? 'حركة مالية' : description),
                  if (reference.isNotEmpty)
                    text(reference,
                        number: !RegExp(r'[\u0600-\u06ff]').hasMatch(reference),
                        size: 8)
                ])),
        cell(row['date'].toString().replaceAll('T', ' ').split('.').first,
            number: true)
      ]));
    }
    doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        maxPages: 1000,
        textDirection: pw.TextDirection.rtl,
        header: (context) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Row(children: [
                    pw.Expanded(
                        child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                            children: [
                          text(workshop.workshopName ?? 'الورشة',
                              strong: true, size: 19),
                          text([workshop.city, workshop.address]
                              .whereType<String>()
                              .where((v) => v.isNotEmpty)
                              .join(' - ')),
                        ])),
                    if (logo != null)
                      pw.SizedBox(
                          width: 60,
                          height: 50,
                          child: pw.Image(logo, fit: pw.BoxFit.contain))
                  ]),
                  pw.SizedBox(height: 8),
                  text('دفتر الأستاذ - كشف حساب', strong: true, size: 16),
                  text(accountName, strong: true, size: 12),
                  text(
                      'الفترة: ${date(from, 'منذ البداية')}  إلى  ${date(to, 'حتى آخر حركة')}'),
                  pw.Divider(color: PdfColors.grey400)
                ]),
        footer: (context) => pw.Column(children: [
              pw.Divider(color: PdfColors.grey300),
              pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    text('${context.pageNumber} / ${context.pagesCount}',
                        number: true, size: 9),
                    text(workshop.phone1 ?? '', number: true, size: 9),
                    text('جميع الحركات ضمن الفترة', size: 9)
                  ])
            ]),
        build: (context) => [
              text(
                  'الرصيد الموجب مدين، والسالب دائن. العملة: ${MoneyFormatter.currencyCode}',
                  size: 9),
              pw.SizedBox(height: 8),
              pw.Table(
                  border:
                      pw.TableBorder.all(color: PdfColors.grey300, width: .4),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(1.25),
                    1: pw.FlexColumnWidth(1.1),
                    2: pw.FlexColumnWidth(1.1),
                    3: pw.FlexColumnWidth(3.4),
                    4: pw.FlexColumnWidth(1.65)
                  },
                  children: [
                    pw.TableRow(
                        repeat: true,
                        decoration:
                            const pw.BoxDecoration(color: PdfColors.grey200),
                        children: [
                          cell('الرصيد المتحرك', strong: true),
                          cell('دائن', strong: true),
                          cell('مدين', strong: true),
                          cell('البيان / المرجع', strong: true),
                          cell('التاريخ والوقت', strong: true)
                        ]),
                    ...entries,
                    pw.TableRow(
                        decoration:
                            const pw.BoxDecoration(color: PdfColors.grey100),
                        children: [
                          cell(amount(balance), number: true, strong: true),
                          cell(amount(credit), number: true, strong: true),
                          cell(amount(debit), number: true, strong: true),
                          cell('الإجمالي / الرصيد الختامي', strong: true),
                          cell('')
                        ])
                  ]),
              if (rows.isEmpty) text('لا توجد حركات خلال الفترة المحددة.'),
            ]));
    return doc.save();
  }
}
