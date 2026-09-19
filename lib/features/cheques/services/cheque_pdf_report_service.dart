import 'dart:typed_data';

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

  static Future<Uint8List> generate(
    ChequePdfReportKind kind, {
    DatabaseExecutor? executor,
    DateTime? asOf,
  }) async {
    final rows = await loadRows(kind, executor: executor, asOf: asOf);
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Cairo-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Cairo-Bold.ttf'),
    );
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    final total = rows.fold<double>(0, (sum, c) => sum + c.amount);
    final df = DateFormat('yyyy-MM-dd');
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => [
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text(
                  _title(kind),
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: bold, fontSize: 20),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'عدد الشيكات: ${rows.length} — إجمالي القيمة: ${total.toStringAsFixed(2)}',
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
                        c.direction == ChequeDirection.received
                            ? 'وارد'
                            : 'صادر',
                        c.direction == ChequeDirection.received
                            ? c.drawerName
                            : (c.recipientName ?? '—'),
                        c.bankBranch.isEmpty
                            ? c.bankName
                            : '${c.bankName} — ${c.bankBranch}',
                        c.amount.toStringAsFixed(2),
                        c.currency,
                        df.format(c.issueDate),
                        df.format(c.dueDate),
                        _status(c.status),
                        _reference(c),
                      ],
                  ],
                  headerStyle: pw.TextStyle(font: bold, fontSize: 8),
                  cellStyle: pw.TextStyle(font: regular, fontSize: 7),
                  headerDecoration: const pw.BoxDecoration(
                    color: PdfColors.grey300,
                  ),
                  cellAlignment: pw.Alignment.centerRight,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return pdf.save();
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
