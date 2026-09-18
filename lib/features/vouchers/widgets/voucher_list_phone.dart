import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat, DateFormat;
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/core/utils/yalla_digits.dart';

String voucherMethodLabel(Object? raw) {
  return switch ((raw ?? '').toString().toLowerCase()) {
    'cash' => 'نقدًا',
    'bank' => 'حساب بنكي',
    'bank_transfer' || 'transfer' => 'تحويل بنكي',
    'card' => 'بطاقة',
    'cheque' || 'check' => 'شيك',
    'الكل' => 'كل طرق الدفع',
    _ => (raw ?? 'غير محدد').toString(),
  };
}

/// One scroll surface; cards grow with content and text size.
class VoucherListPhone extends StatelessWidget {
  const VoucherListPhone(
      {super.key,
      required this.isReceipt,
      required this.rows,
      required this.today,
      required this.month,
      required this.method,
      required this.methods,
      required this.onSearch,
      required this.onMethod,
      required this.onRefresh,
      required this.onExport,
      required this.onDocument,
      required this.numberLabel,
      this.onReverse});
  final bool isReceipt;
  final List<Map<String, Object?>> rows;
  final double today, month;
  final String method;
  final List<String> methods;
  final ValueChanged<String> onSearch, onMethod;
  final Future<void> Function() onRefresh;
  final VoidCallback onExport;
  final void Function(Map<String, Object?>) onDocument;
  final void Function(Map<String, Object?>)? onReverse;
  final String Function(Map<String, Object?>) numberLabel;

  String money(num amount) => NumberFormat('#,##0.00', 'en').format(amount);

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView.builder(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          itemCount: rows.length + 1,
          itemBuilder: (context, index) {
            if (index > 0) return _card(context, rows[index - 1]);
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(
                        child: Text(isReceipt ? 'سندات القبض' : 'سندات الصرف',
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.bold))),
                    IconButton(
                        tooltip: 'تحديث',
                        onPressed: onRefresh,
                        icon: const Icon(Icons.refresh)),
                  ]),
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 6),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _metric('عدد السندات', rows.length.toString(),
                                    color),
                                _metric(isReceipt ? 'قبض اليوم' : 'صرف اليوم',
                                    money(today), color),
                                _metric(isReceipt ? 'قبض الشهر' : 'صرف الشهر',
                                    money(month), color),
                              ]))),
                  const SizedBox(height: 12),
                  TextField(
                    inputFormatters: const [YallaDigitNormalizer()],
                    onChanged: onSearch,
                    decoration: InputDecoration(
                      hintText: isReceipt
                          ? 'بحث بالعميل أو رقم السند أو المبلغ'
                          : 'بحث بالمستفيد أو رقم السند أو المبلغ',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: method,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'طريقة الدفع', border: OutlineInputBorder()),
                    items: methods
                        .map((m) => DropdownMenuItem(
                            value: m, child: Text(voucherMethodLabel(m))))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) onMethod(value);
                    },
                  ),
                  Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton.icon(
                          onPressed: rows.isEmpty ? null : onExport,
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('تصدير القائمة PDF'))),
                  if (rows.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('لا توجد سندات مطابقة',
                            textAlign: TextAlign.center)),
                ]);
          },
        ),
      ),
    );
  }

  Widget _metric(String title, String value, Color color) => Expanded(
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(children: [
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: color))),
          ])));

  Widget _card(BuildContext context, Map<String, Object?> row) {
    final rawDate = (row['date'] ?? '').toString();
    final parsedDate = DateTime.tryParse(rawDate);
    final date = parsedDate == null
        ? rawDate
        : DateFormat('yyyy-MM-dd', 'en').format(parsedDate);
    final reversed =
        (row['status'] ?? '').toString().toUpperCase() == 'REVERSED' ||
            ((row['reversal_lines'] as num?) ?? 0) > 0;
    final party =
        (row[isReceipt ? 'clientName' : 'party_name'] ?? '').toString().trim();
    final note = (row['notes'] ?? '').toString().trim();
    final gl =
        (row[isReceipt ? 'gl_entry_ids' : 'gl_entry_id'] ?? '').toString();
    return Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
                party.isEmpty
                    ? (isReceipt ? 'عميل غير محدد' : 'مستفيد غير محدد')
                    : party,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(numberLabel(row),
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            Text(MoneyFormatter.format((row['amount'] as num?) ?? 0),
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary)),
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 6, children: [
              Text(date, textDirection: TextDirection.ltr),
              Text(voucherMethodLabel(row['method'])),
              Text(reversed ? 'يتضمن عكسًا محاسبيًا' : 'مسجل'),
            ]),
            if (note.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 8), child: Text(note)),
            if (gl.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('القيد المحاسبي: $gl',
                      style: Theme.of(context).textTheme.bodySmall)),
            const Divider(),
            Wrap(spacing: 8, runSpacing: 4, children: [
              TextButton.icon(
                  onPressed: () => onDocument(row),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('فتح السند PDF')),
              if (onReverse != null && !reversed)
                TextButton.icon(
                    onPressed: () => onReverse!(row),
                    icon: const Icon(Icons.undo),
                    label: const Text('إلغاء السند')),
            ]),
          ]),
        ));
  }
}
