// -----------------------------------------------------------------------------
// 📁 lib/core/pdf/supplier_ledger_pdf.dart
// Supplier Ledger PDF — FINAL PROFESSIONAL VERSION
// كشف حساب مورد + تفاصيل الفواتير + سندات الدفع + رصيد متحرك
// -----------------------------------------------------------------------------

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:yalla_accounts/core/services/db_service.dart';

class SupplierLedgerPdf {
  static final _nf = NumberFormat('#,##0.00', 'ar');
  static final _df = DateFormat('yyyy-MM-dd', 'ar');

  // ===========================================================================
  static Future<void> generate({
    required String supplierId,
    required String supplierName,
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await DBService.database;

    final fromIso = from != null ? from.toIso8601String() : '2000-01-01';
    final toIso = (to ?? DateTime.now()).toIso8601String();

    // -------------------------------------------------------------------------
    // 1) جلب فواتير الشراء
    // -------------------------------------------------------------------------
    final invoices = await db.rawQuery('''
      SELECT id, date, amount_total
      FROM purchase_invoices
      WHERE supplier_id = ?
        AND date(date) BETWEEN date(?) AND date(?)
      ORDER BY date ASC
    ''', [supplierId, fromIso, toIso]);

    // -------------------------------------------------------------------------
    // 2) جلب بنود الفواتير
    // -------------------------------------------------------------------------
    final Map<int, List<Map<String, Object?>>> invoiceLines = {};

    for (final inv in invoices) {
      final invId = (inv['id'] as num).toInt();
      invoiceLines[invId] = await db.rawQuery('''
        SELECT item_name, qty, unit_price, total
        FROM purchase_invoice_lines
        WHERE invoice_id = ?
      ''', [invId]);
    }

    // -------------------------------------------------------------------------
    // 3) جلب سندات الدفع للمورد
    // -------------------------------------------------------------------------
    final payments = await db.rawQuery('''
      SELECT date, amount
      FROM purchase_payments
      WHERE supplier_id = ?
        AND date(date) BETWEEN date(?) AND date(?)
      ORDER BY date ASC
    ''', [supplierId, fromIso, toIso]);

    // -------------------------------------------------------------------------
    // 4) دمج الحركات (Ledger)
    // -------------------------------------------------------------------------
    final List<_LedgerRow> ledger = [];

    for (final inv in invoices) {
      ledger.add(
        _LedgerRow(
          date: inv['date'].toString(),
          description: 'فاتورة شراء',
          debit: (inv['amount_total'] as num).toDouble(),
          credit: 0,
          invoiceId: (inv['id'] as num).toInt(),
        ),
      );
    }

    for (final p in payments) {
      ledger.add(
        _LedgerRow(
          date: p['date'].toString(),
          description: 'سند دفع',
          debit: 0,
          credit: (p['amount'] as num).toDouble(),
        ),
      );
    }

    ledger.sort((a, b) => a.date.compareTo(b.date));

    // -------------------------------------------------------------------------
    // 5) إعداد PDF
    // -------------------------------------------------------------------------
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf'),
    );

    final pdf = pw.Document();
    double balance = 0;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: font),
        build: (context) {
          return [
            _header(supplierName, from, to),
            pw.SizedBox(height: 10),

            // ======================= جدول كشف الحساب =========================
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey),
              columnWidths: const {
                0: pw.FlexColumnWidth(2),
                1: pw.FlexColumnWidth(4),
                2: pw.FlexColumnWidth(2),
                3: pw.FlexColumnWidth(2),
                4: pw.FlexColumnWidth(2),
              },
              children: [
                _ledgerHeader(),
                ...ledger.map((row) {
                  balance += row.debit - row.credit;

                  return pw.TableRow(
                    children: [
                      _td(row.date),
                      _td(row.description),
                      _td(row.debit > 0 ? _nf.format(row.debit) : ''),
                      _td(row.credit > 0 ? _nf.format(row.credit) : ''),
                      _td(_nf.format(balance)),
                    ],
                  );
                }),
              ],
            ),

            pw.SizedBox(height: 16),

            // ======================= تفاصيل الفواتير =========================
            ...ledger
                .where((e) => e.invoiceId != null)
                .map((e) => _invoiceBlock(
                      e.invoiceId!,
                      invoiceLines[e.invoiceId!]!,
                    )),
          ];
        },
      ),
    );

    // -------------------------------------------------------------------------
    // 6) حفظ وفتح
    // -------------------------------------------------------------------------
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'supplier_ledger_$supplierId.pdf'));

    await file.writeAsBytes(await pdf.save());
    await OpenFile.open(file.path);
  }

  // ===========================================================================
  static pw.Widget _header(
    String supplierName,
    DateTime? from,
    DateTime? to,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('كشف حساب مورد',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.Text('المورد: $supplierName'),
        pw.Text(
          'الفترة: ${from != null ? _df.format(from) : 'منذ البداية'} → ${_df.format(to ?? DateTime.now())}',
        ),
        pw.Divider(),
      ],
    );
  }

  static pw.TableRow _ledgerHeader() {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: [
        _th('التاريخ'),
        _th('البيان'),
        _th('عليه'),
        _th('له'),
        _th('الرصيد'),
      ],
    );
  }

  static pw.Widget _invoiceBlock(
    int invoiceId,
    List<Map<String, Object?>> lines,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 10),
        pw.Text('تفاصيل فاتورة رقم: $invoiceId',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey),
          columnWidths: const {
            0: pw.FlexColumnWidth(4),
            1: pw.FlexColumnWidth(1),
            2: pw.FlexColumnWidth(2),
            3: pw.FlexColumnWidth(2),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _th('الصنف'),
                _th('الكمية'),
                _th('السعر'),
                _th('الإجمالي'),
              ],
            ),
            ...lines.map((r) {
              return pw.TableRow(
                children: [
                  _td(r['item_name']),
                  _td(r['qty']),
                  _td(_nf.format(r['unit_price'] ?? 0)),
                  _td(_nf.format(r['total'] ?? 0)),
                ],
              );
            }),
          ],
        ),
      ],
    );
  }

  static pw.Widget _th(String text) => pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child:
            pw.Text(text, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      );

  static pw.Widget _td(Object? value) => pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(value?.toString() ?? ''),
      );
}

// ============================================================================
// نموذج داخلي
// ============================================================================
class _LedgerRow {
  final String date;
  final String description;
  final double debit;
  final double credit;
  final int? invoiceId;

  _LedgerRow({
    required this.date,
    required this.description,
    required this.debit,
    required this.credit,
    this.invoiceId,
  });
}
