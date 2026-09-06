import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:yalla_accounts/core/pdf/yalla_pdf_service.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/utils/public_text_sanitizer.dart';
import 'package:yalla_accounts/features/account_statements/customers/services/customer_account_statement_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_line_bridge.dart';

/// P15 official document layer.
///
/// This class never invents accounting totals:
/// - customer invoice totals come from `invoices`
/// - receipt totals/allocations come from P11 receipt header/allocation tables
/// - customer statements are rendered from the P12 GL-based statement object
class P15DocumentService {
  const P15DocumentService._();

  static double _d(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static String _money(Object? value) =>
      NumberFormat('#,##0.00', 'ar').format(_d(value));

  static String _date(Object? raw) {
    final dt = DateTime.tryParse((raw ?? '').toString());
    return dt == null
        ? (raw ?? '').toString()
        : DateFormat('yyyy-MM-dd').format(dt);
  }

  static Future<Uint8List> generateCustomerInvoicePdf(String invoiceId) async {
    final db = await DBService.database;
    final rows = await db.rawQuery('''
      SELECT
        i.*,
        c.name AS client_name,
        r.invoiceNumber AS repair_number,
        r.vehicleNumber AS vehicle_number,
        r.vehicleType AS vehicle_type,
        r.vehicleModel AS vehicle_model
      FROM invoices i
      LEFT JOIN clients c ON c.id=i.client_id
      LEFT JOIN repairs r ON r.id=i.repair_id
      WHERE i.id=?
      LIMIT 1
    ''', [invoiceId]);
    if (rows.isEmpty) throw StateError('Invoice $invoiceId not found.');
    final inv = rows.first;
    final repairId = (inv['repair_id'] ?? '').toString();
    final lines = repairId.isEmpty
        ? const RepairLineSnapshot()
        : await RepairLineBridge.load(repairId);

    final doc = await YallaPdfService.createDocument();
    final header = await YallaPdfService.buildHeader();
    final footer = await YallaPdfService.buildFooter();
    final note = PublicTextSanitizer.sanitize(inv['note'] ?? inv['notes']);

    final allLines = <Map<String, dynamic>>[
      ...lines.works.map((e) => {...e, 'kind': 'عمل'}),
      ...lines.parts.map((e) => {...e, 'kind': 'قطعة'}),
    ];

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(22),
        textDirection: pw.TextDirection.rtl,
        header: (_) => header,
        footer: (_) => footer,
        build: (_) => [
          pw.Center(
            child: YallaPdfService.ar(
              'فاتورة عميل',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 14),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey600, width: .6),
            children: [
              YallaPdfService.headerRow(['رقم الفاتورة', invoiceId]),
              YallaPdfService.headerRow(['التاريخ', _date(inv['date'])]),
              YallaPdfService.headerRow([
                'العميل',
                PublicTextSanitizer.sanitize(inv['client_name']).isEmpty
                    ? 'عميل ${(inv['client_id'] ?? '')}'
                    : PublicTextSanitizer.sanitize(inv['client_name'])
              ]),
              if (repairId.isNotEmpty)
                YallaPdfService.headerRow([
                  'ملف الإصلاح',
                  (inv['repair_number'] ?? repairId).toString(),
                ]),
              if ((inv['vehicle_number'] ?? '').toString().trim().isNotEmpty)
                YallaPdfService.headerRow([
                  'المركبة',
                  '${inv['vehicle_type'] ?? ''} ${inv['vehicle_model'] ?? ''} — ${inv['vehicle_number'] ?? ''}'
                      .trim(),
                ]),
            ],
          ),
          pw.SizedBox(height: 14),
          if (allLines.isNotEmpty) ...[
            YallaPdfService.ar('تفاصيل الأعمال والقطع',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey500, width: .5),
              children: [
                YallaPdfService.headerRow(
                    ['النوع', 'الوصف', 'الكمية', 'سعر الوحدة', 'الإجمالي']),
                ...allLines.map((line) {
                  final qty = _d(line['qty']);
                  final price = _d(line['price']);
                  final stored = _d(line['total']);
                  final total = stored != 0 ? stored : qty * price;
                  return pw.TableRow(children: [
                    YallaPdfService.cell(line['kind'].toString()),
                    YallaPdfService.cell(
                        PublicTextSanitizer.sanitize(line['name'])),
                    YallaPdfService.cell(qty.toStringAsFixed(2)),
                    YallaPdfService.cell(_money(price)),
                    YallaPdfService.cell(_money(total)),
                  ]);
                }),
              ],
            ),
            pw.SizedBox(height: 14),
          ],
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              width: 280,
              child: pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey600, width: .5),
                children: [
                  YallaPdfService.headerRow(
                      ['الصافي قبل الضريبة', _money(inv['subtotal'])]),
                  YallaPdfService.headerRow(
                      ['الضريبة', _money(inv['vat'] ?? inv['vat_amount'])]),
                  YallaPdfService.headerRow(['الإجمالي', _money(inv['total'])]),
                  YallaPdfService.headerRow(['المدفوع', _money(inv['paid'])]),
                  YallaPdfService.headerRow([
                    'حالة السداد',
                    PublicTextSanitizer.sanitize(inv['status'])
                  ]),
                ],
              ),
            ),
          ),
          if (note.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            YallaPdfService.ar('ملاحظات: $note'),
          ],
        ],
      ),
    );
    return doc.save();
  }

  static Future<Uint8List> generateReceiptPdf(int receiptNumber) async {
    final db = await DBService.database;
    final headers = await db.rawQuery('''
      SELECT h.*, c.name AS client_name
      FROM receipt_headers h
      LEFT JOIN clients c ON c.id=h.client_id
      WHERE h.receipt_number=?
      LIMIT 1
    ''', [receiptNumber]);
    if (headers.isEmpty) {
      throw StateError(
          'Receipt RC-${receiptNumber.toString().padLeft(6, '0')} not found.');
    }
    final h = headers.first;
    final allocations = await db.rawQuery('''
      SELECT
        a.repair_id,
        a.amount,
        a.allocation_type,
        r.invoiceNumber AS repair_number,
        r.vehicleNumber AS vehicle_number
      FROM receipt_allocations a
      LEFT JOIN repairs r ON r.id=a.repair_id
      WHERE a.receipt_number=?
      ORDER BY a.id
    ''', [receiptNumber]);

    final doc = await YallaPdfService.createDocument();
    final header = await YallaPdfService.buildHeader();
    final footer = await YallaPdfService.buildFooter();
    final rc = 'RC-${receiptNumber.toString().padLeft(6, '0')}';
    final notes = PublicTextSanitizer.sanitize(h['notes']);
    final status = (h['status'] ?? 'posted').toString().toLowerCase();
    final reversalOf = h['reversal_of_receipt_number'];

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(22),
        textDirection: pw.TextDirection.rtl,
        header: (_) => header,
        footer: (_) => footer,
        build: (_) => [
          pw.Center(
            child: YallaPdfService.ar(
              'سند قبض $rc',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 14),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey600, width: .6),
            children: [
              YallaPdfService.headerRow(['التاريخ', _date(h['date'])]),
              YallaPdfService.headerRow(
                  ['العميل', PublicTextSanitizer.sanitize(h['client_name'])]),
              YallaPdfService.headerRow(
                  ['طريقة الدفع', PublicTextSanitizer.sanitize(h['method'])]),
              YallaPdfService.headerRow(
                  ['إجمالي السند', _money(h['total_amount'])]),
              YallaPdfService.headerRow(
                  ['المخصص للملفات', _money(h['allocated_amount'])]),
              YallaPdfService.headerRow(
                  ['رصيد دائن للعميل', _money(h['credit_amount'])]),
              YallaPdfService.headerRow(
                  ['الحالة', status == 'reversed' ? 'معكوس' : 'مرحّل']),
              if (reversalOf != null)
                YallaPdfService.headerRow([
                  'عكس للسند',
                  'RC-${reversalOf.toString().padLeft(6, '0')}',
                ]),
            ],
          ),
          if (allocations.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            YallaPdfService.ar('توزيع السند',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey500, width: .5),
              children: [
                YallaPdfService.headerRow(
                    ['الملف', 'المركبة', 'النوع', 'المبلغ']),
                ...allocations.map((a) => pw.TableRow(children: [
                      YallaPdfService.cell(
                          (a['repair_number'] ?? a['repair_id'] ?? 'رصيد عام')
                              .toString()),
                      YallaPdfService.cell(
                          (a['vehicle_number'] ?? '').toString()),
                      YallaPdfService.cell(
                          PublicTextSanitizer.sanitize(a['allocation_type'])),
                      YallaPdfService.cell(_money(a['amount'])),
                    ])),
              ],
            ),
          ],
          if (notes.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            YallaPdfService.ar('ملاحظات: $notes'),
          ],
        ],
      ),
    );
    return doc.save();
  }

  static Future<Uint8List> generateCustomerStatementPdf(
    CustomerAccountStatement statement, {
    DateTime? from,
    DateTime? to,
  }) async {
    final doc = await YallaPdfService.createDocument();
    final header = await YallaPdfService.buildHeader();
    final footer = await YallaPdfService.buildFooter();
    final df = DateFormat('yyyy-MM-dd');

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18),
        textDirection: pw.TextDirection.rtl,
        header: (_) => header,
        footer: (_) => footer,
        build: (_) => [
          pw.Center(
            child: YallaPdfService.ar(
              'كشف حساب العميل — ${PublicTextSanitizer.sanitize(statement.clientName)}',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
          ),
          if (from != null || to != null) ...[
            pw.SizedBox(height: 6),
            pw.Center(
              child: YallaPdfService.ar(
                'الفترة: ${from == null ? 'البداية' : df.format(from)} → ${to == null ? 'اليوم' : df.format(to)}',
              ),
            ),
          ],
          pw.SizedBox(height: 12),
          pw.Wrap(spacing: 10, children: [
            YallaPdfService.ar(
                'الرصيد الافتتاحي: ${_money(statement.openingBalance)}'),
            YallaPdfService.ar(
                'الرصيد الختامي: ${_money(statement.closingBalance)}'),
          ]),
          pw.SizedBox(height: 10),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey500, width: .45),
            children: [
              YallaPdfService.headerRow(
                  ['التاريخ', 'البيان', 'المرجع', 'مدين', 'دائن', 'الرصيد']),
              ...statement.lines.map((line) => pw.TableRow(children: [
                    YallaPdfService.cell(df.format(line.date)),
                    YallaPdfService.cell(
                        PublicTextSanitizer.sanitize(line.description)),
                    YallaPdfService.cell(
                        PublicTextSanitizer.sanitize(line.reference)),
                    YallaPdfService.cell(_money(line.debit)),
                    YallaPdfService.cell(_money(line.credit)),
                    YallaPdfService.cell(_money(line.balance)),
                  ])),
            ],
          ),
        ],
      ),
    );
    return doc.save();
  }
}
