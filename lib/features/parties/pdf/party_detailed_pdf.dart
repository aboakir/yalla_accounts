import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:yalla_accounts/core/pdf/yalla_pdf_service.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import '../services/party_report_service.dart';

class PartyDetailedPdf {
  static String date(Object? v) =>
      v == null || '$v'.isEmpty ? 'غير مسجل' : '$v'.replaceFirst('T', ' ');
  static String text(Map<String, Object?> r, List<String> keys) {
    for (final k in keys) {
      if (r[k] != null && r[k].toString().isNotEmpty) return r[k].toString();
    }
    return '—';
  }

  static String money(Object? v) => v == null
      ? '—'
      : MoneyFormatter.format(v is num ? v : num.tryParse('$v') ?? 0);
  static pw.Widget heading(String t) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 10),
      child: pw.Text(t,
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)));
  static pw.Widget cell(String t) => pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(t, style: const pw.TextStyle(fontSize: 9)));
  static pw.Widget table(List<String> h, List<List<String>> rows) => pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: .4),
          children: [
            pw.TableRow(
                repeat: true,
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: h.reversed.map(cell).toList()),
            ...rows.map(
                (r) => pw.TableRow(children: r.reversed.map(cell).toList()))
          ]);
  static Future<Uint8List> generate(DetailedPartyReport r,
      {String period = 'كل التواريخ', bool workshopHeader = true}) async {
    final doc = await YallaPdfService.createDocument();
    final header =
        workshopHeader ? await YallaPdfService.buildHeader() : pw.SizedBox();
    final s = r.statement;
    final widgets = <pw.Widget>[
      heading('كشف حساب تفصيلي: ${s.displayName}'),
      pw.Text('الفترة: $period'),
      pw.Text('إصدار الكشف: ${date(DateTime.now().toIso8601String())}'),
      pw.Text(
          'المدين يزيد ما لك، والدائن يزيد ما عليك. الرصيد الموجب لك والسالب عليك. الصافي لا ينشئ مقاصة أو سدادًا.'),
      table([
        'افتتاحي',
        'مدين الفترة',
        'دائن الفترة',
        'ختامي'
      ], [
        [
          money(s.openingBalance),
          money(s.lines.fold<double>(0.0, (n, l) => n + l.debit)),
          money(s.lines.fold<double>(0.0, (n, l) => n + l.credit)),
          money(s.closingBalance)
        ]
      ]),
      heading('الحركات المالية'),
      table(
          [
            'التاريخ والوقت المسجل',
            'المستند والبيان',
            'مدين',
            'دائن',
            'الرصيد'
          ],
          s.lines
              .map((l) => [
                    date(r.dates[l.entryId]),
                    '${l.description} / ${l.sourceNumber.isEmpty ? l.entryId.toString() : l.sourceNumber} / ${l.source}',
                    money(l.debit),
                    money(l.credit),
                    money(l.runningBalance)
                  ])
              .toList()),
      heading('سندات القبض والصرف'),
      table(
          [
            'النوع والرقم',
            'التاريخ والوقت',
            'المبلغ',
            'العملة',
            'طريقة الدفع',
            'المرجع والملاحظات'
          ],
          r.payments
              .map((p) => [
                    '${text(p, ['voucher_type'])} / ${text(p, [
                          'voucher_number',
                          'id'
                        ])}',
                    date(p['date']),
                    money(p['amount']),
                    text(p, ['currency']),
                    text(p, ['method']),
                    '${text(p, ['reference', 'invoice_id'])} / ${text(p, [
                          'notes',
                          'note'
                        ])}'
                  ])
              .toList()),
      heading('تفاصيل الفواتير المرتبطة بالحركات'),
      pw.Text(
          'تفاصيل مرجعية لا تُجمع مرة ثانية مع الحركات. قد تكون الفاتورة سابقة للفترة عند سدادها خلالها.'),
    ];
    for (final d in r.documents) {
      final h = d.header;
      widgets.addAll([
        heading('فاتورة ${d.kind} / ${text(h, ['invoice_number', 'id'])}'),
        pw.Text(
            'تاريخ الفاتورة: ${date(h['date'])} | وقت الإنشاء المسجل: ${date(h['created_at'])}'),
        if (d.vehicle.isNotEmpty)
          pw.Text(
              'المركبة: ${text(d.vehicle, ['vehicleType'])} ${text(d.vehicle, [
                'vehicleModel'
              ])} | اللوحة: ${text(d.vehicle, [
                'vehicleNumber'
              ])} | ملف الإصلاح: ${text(d.vehicle, [
                'invoiceNumber',
                'id'
              ])} | الاستلام: ${date(d.vehicle['receivedDate'])}'),
        table(
            ['البند', 'التصنيف', 'الكمية', 'سعر الوحدة', 'الإجمالي', 'ملاحظات'],
            d.items
                .map((i) => [
                      text(i, ['item_name', 'item', 'name']),
                      i['line_type'] == 'work'
                          ? 'أجور / أعمال'
                          : i['line_type'] == 'part'
                              ? 'قطع'
                              : text(i, ['category']),
                      text(i, ['qty']),
                      money(i[d.kind == 'بيع' ? 'price' : 'unit_price']),
                      money(i['total']),
                      text(i, ['notes', 'note'])
                    ])
                .toList()),
        if (d.items.isEmpty)
          pw.Text('لا توجد بنود تفصيلية محفوظة لهذا المستند.'),
        if (d.kind == 'بيع')
          pw.Text(
              'مصدر البنود: ملف الإصلاح المرتبط؛ القيم المالية المعتمدة من رأس الفاتورة. الكمية ليست ساعات عمل إلا إذا سُجلت بهذه الوحدة.'),
        table([
          'قبل الضريبة',
          'الضريبة',
          'إجمالي الفاتورة'
        ], [
          [
            money(h['subtotal']),
            money(h[d.kind == 'بيع' ? 'vat_amount' : 'vat']),
            money(h[d.kind == 'بيع' ? 'total' : 'amount_total'])
          ]
        ]),
        pw.Text('ملاحظات: ${text(h, ['notes', 'note'])}'),
      ]);
    }
    widgets.add(pw.Text(
        'الأوقات كما حُفظت. غير مسجل يعني عدم توفر القيمة؛ لا يُفترض وقت أو مدة عمل.'));
    doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        maxPages: 1000,
        margin: const pw.EdgeInsets.all(24),
        textDirection: pw.TextDirection.rtl,
        header: (_) => header,
        footer: (c) => pw.Text('صفحة ${c.pageNumber} / ${c.pagesCount}'),
        build: (_) => widgets));
    return doc.save();
  }
}
