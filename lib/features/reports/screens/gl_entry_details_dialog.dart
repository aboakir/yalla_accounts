import 'package:yalla_accounts/core/utils/user_facing_error.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/accounting_integrity_service.dart';

Future<void> showGlEntryDetails(BuildContext context, int entryId) async {
  try {
    final db = await DBService.database;
    final entries =
        await db.query('gl_entries', where: 'id=?', whereArgs: [entryId]);
    if (entries.isEmpty) throw StateError('القيد غير موجود');
    final entry = entries.first;
    final trace = await AccountingIntegrityService.traceSourceOn(db,
        source: '${entry['source']}', sourceId: '${entry['source_id']}');
    final lines = await db.rawQuery(
        '''SELECT l.*, a.code, a.name AS account_name
      FROM gl_lines l JOIN accounts a ON a.id=l.account_id WHERE l.entry_id=? ORDER BY l.id''',
        [entryId]);
    final document = trace['source_document'] as Map?;
    if (!context.mounted) return;
    await showDialog<void>(
        context: context,
        builder: (context) => AdaptiveAlertDialog(
              title: Text('تفاصيل القيد #$entryId'),
              content: SizedBox(
                  width: 650,
                  child: SingleChildScrollView(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                        for (final field in <String, Object?>{
                          'المرجع': entry['ref'],
                          'الوصف': entry['note'],
                          'نوع المصدر': entry['source'],
                          'معرّف المستند': entry['source_id'],
                          'رقم المستند': entry['source_number'],
                          'تاريخ الحركة': entry['date'],
                          'وقت التسجيل': entry['created_at'],
                          'أنشأه المستخدم': entry['created_by'],
                          if (entry['reversal_of'] != null)
                            'عكس القيد': entry['reversal_of'],
                        }.entries)
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: SelectableText(
                                  '${field.key}: ${field.value ?? 'غير مسجل تاريخياً'}')),
                        const Divider(),
                        for (final line in lines)
                          ListTile(
                              dense: true,
                              title: Text(
                                  '${line['code']} — ${line['account_name']}'),
                              subtitle: Text(
                                  'مدين: ${line['debit']}    دائن: ${line['credit']}')),
                        const Divider(),
                        const Text('المستند الأصلي',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        if (document == null)
                          const Text(
                              'لا يتوفر مستند محفوظ لهذا المصدر؛ بيانات الربط أعلاه محفوظة مع القيد.'),
                        if (document != null)
                          for (final key in [
                            'id',
                            'date',
                            'voucher_number',
                            'invoice_number',
                            'amount',
                            'amount_total',
                            'total',
                            'method',
                            'notes',
                            'note'
                          ])
                            if (document[key] != null)
                              SelectableText('${{
                                'id': 'الرقم الداخلي',
                                'date': 'التاريخ',
                                'voucher_number': 'رقم السند',
                                'invoice_number': 'رقم الفاتورة',
                                'amount': 'المبلغ',
                                'amount_total': 'الإجمالي',
                                'total': 'الإجمالي',
                                'method': 'طريقة السداد',
                                'notes': 'ملاحظات',
                                'note': 'الوصف'
                              }[key]}: ${document[key]}'),
                      ]))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إغلاق'))
              ],
            ));
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تعذر عرض القيد: ${UserFacingError.message(e)}')));
    }
  }
}
