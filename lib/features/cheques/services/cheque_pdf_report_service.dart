import 'dart:typed_data';
import 'package:yalla_accounts/core/utils/money_formatter.dart';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_maturity_service.dart';

enum ChequePdfReportKind {
  incoming,
  outgoing,
  due,
  deposited,
  returned,
}

class ChequePdfReportService {
  ChequePdfReportService._();

  static Future<List<Cheque>> loadRows(
    ChequePdfReportKind kind, {
    DatabaseExecutor? executor,
    DateTime? asOf,
  }) async {
    final db = executor ?? await DBService.database;
    final rows = await db.query('cheques', orderBy: 'due_date, id');
    final cheques = rows.map(Cheque.fromMap).toList();
    final date = asOf ?? DateTime.now();
    switch (kind) {
      case ChequePdfReportKind.incoming:
        return cheques
            .where((c) => c.direction == ChequeDirection.received)
            .toList();
      case ChequePdfReportKind.outgoing:
        return cheques
            .where((c) => c.direction == ChequeDirection.issued)
            .toList();
      case ChequePdfReportKind.due:
        return cheques
            .where((c) => ChequeMaturityService.isActionableDue(c, asOf: date))
            .toList();
      case ChequePdfReportKind.deposited:
        return cheques
            .where((c) => c.status == ChequeStatus.deposited)
            .toList();
      case ChequePdfReportKind.returned:
        return cheques.where((c) => c.status == ChequeStatus.returned).toList();
    }
  }

  static List<Cheque> filterRows(Iterable<Cheque> rows,
      {String currency = '', ChequeStatus? status}) {
    final code = currency.trim().toUpperCase();
    return rows
        .where((c) =>
            (code.isEmpty || c.currency.toUpperCase() == code) &&
            (status == null || c.status == status))
        .toList(growable: false);
  }

  static Map<String, double> totalsByCurrency(Iterable<Cheque> rows) {
    final totals = <String, double>{};
    for (final cheque in rows) {
      final code = cheque.currency.trim().toUpperCase();
      totals.update(code, (amount) => amount + cheque.amount,
          ifAbsent: () => cheque.amount);
    }
    return totals;
  }

  static Future<Uint8List> generate(
    ChequePdfReportKind kind, {
    DatabaseExecutor? executor,
    DateTime? asOf,
    List<Cheque>? rowSnapshot,
  }) async {
    final pdf = await buildDocument(kind,
        executor: executor, asOf: asOf, rowSnapshot: rowSnapshot);
    return pdf.save();
  }

  static Future<pw.Document> buildDocument(
    ChequePdfReportKind kind, {
    DatabaseExecutor? executor,
    DateTime? asOf,
    List<Cheque>? rowSnapshot,
  }) async {
    final rows = List<Cheque>.unmodifiable(
        rowSnapshot ?? await loadRows(kind, executor: executor, asOf: asOf));
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Cairo-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Cairo-Bold.ttf'),
    );
    final arabicFallback = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf'),
    );
    final fallbacks = <pw.Font>[arabicFallback];
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: regular,
        bold: bold,
        fontFallback: fallbacks,
      ),
    );
    final totals = totalsByCurrency(rows);
    final totalText = totals.entries
        .map((e) =>
            MoneyFormatter.format(e.value, currencyCode: e.key, showCode: true))
        .join(' — ');
    final df = DateFormat('yyyy-MM-dd');
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        textDirection: pw.TextDirection.rtl,
        build: (_) => [
          pw.Text(
            _title(kind),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: bold,
              fontSize: 20,
              fontFallback: fallbacks,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'عدد الشيكات: ${rows.length} — إجمالي القيمة: $totalText',
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 14),
          pw.TableHelper.fromTextArray(
            headers: const [
              'رقم الشيك',
              'الاتجاه',
              'الساحب / المستفيد',
              'البنك',
              'القيمة',
              'العملة',
              'الإصدار',
              'الاستحقاق',
              'الحالة',
              'المرجع المالي',
            ],
            data: [
              for (final c in rows)
                [
                  c.chequeNo,
                  c.direction == ChequeDirection.received ? 'وارد' : 'صادر',
                  c.direction == ChequeDirection.received
                      ? c.drawerName
                      : (c.recipientName ?? '—'),
                  c.bankBranch.isEmpty
                      ? c.bankName
                      : '${c.bankName} — ${c.bankBranch}',
                  MoneyFormatter.number(c.amount, currencyCode: c.currency),
                  c.currency,
                  df.format(c.issueDate),
                  df.format(c.dueDate),
                  _status(c.status),
                  _reference(c),
                ],
            ],
            headerStyle: pw.TextStyle(
              font: bold,
              fontSize: 8,
              fontFallback: fallbacks,
            ),
            cellStyle: pw.TextStyle(
              font: regular,
              fontSize: 7,
              fontFallback: fallbacks,
            ),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.grey300,
            ),
            cellAlignment: pw.Alignment.centerRight,
          ),
        ],
      ),
    );
    return pdf;
  }

  static String _reference(Cheque c) {
    if (c.receiptVoucherId != null) return 'RC-${c.receiptVoucherId}';
    if ((c.paymentVoucherId ?? '').trim().isNotEmpty) {
      return 'PV-${c.paymentVoucherId}';
    }
    if ((c.sourceType ?? '').trim().isNotEmpty ||
        (c.sourceId ?? '').trim().isNotEmpty) {
      return '${c.sourceType ?? ''}/${c.sourceId ?? ''}';
    }
    return '—';
  }

  static String _title(ChequePdfReportKind kind) {
    switch (kind) {
      case ChequePdfReportKind.incoming:
        return 'تقرير الشيكات الواردة';
      case ChequePdfReportKind.outgoing:
        return 'تقرير الشيكات الصادرة';
      case ChequePdfReportKind.due:
        return 'تقرير الشيكات المستحقة';
      case ChequePdfReportKind.deposited:
        return 'تقرير الشيكات المودعة للتحصيل';
      case ChequePdfReportKind.returned:
        return 'تقرير الشيكات الراجعة';
    }
  }

  static String _status(ChequeStatus status) {
    switch (status) {
      case ChequeStatus.pending:
        return 'قديم/معلّق';
      case ChequeStatus.received:
        return 'مستلم';
      case ChequeStatus.held:
        return 'محتفظ به';
      case ChequeStatus.deposited:
        return 'مودع';
      case ChequeStatus.collected:
        return 'محصل';
      case ChequeStatus.endorsed:
        return 'مظهّر';
      case ChequeStatus.issued:
        return 'صادر';
      case ChequeStatus.delivered:
        return 'مسلّم';
      case ChequeStatus.presented:
        return 'مقدم/مستحق';
      case ChequeStatus.cleared:
        return 'مصروف';
      case ChequeStatus.returned:
        return 'راجع';
      case ChequeStatus.cancelled:
        return 'ملغى';
    }
  }
}
