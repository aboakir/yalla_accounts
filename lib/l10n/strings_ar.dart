// 📁 lib/l10n/strings_ar.dart
class S {
  static const m = {
    'invoice': 'فاتورة',
    'gl_entry': 'قيد محاسبي',
    'gl_browser': 'متصفح القيود',
    'payments': 'الدفعات',
    'open_gl_browser': 'فتح متصفح القيود',
    'view_gl_entry': 'عرض القيد',
    'post_gl': 'ترحيل القيد',
    'reverse': 'عكس القيد',
    'balanced': 'متوازن',
    'not_balanced': 'غير متوازن',
    'copy_id': 'نسخ المعرّف',
    'refresh': 'تحديث',
    'date': 'التاريخ',
    'subtotal': 'الإجمالي قبل الضريبة',
    'vat': 'الضريبة',
    'total': 'الإجمالي',
    'paid': 'المدفوع',
    'status': 'الحالة',
    'method': 'طريقة الدفع',
    'note': 'ملاحظة',
    'client_id': 'رقم العميل',
    'gl_entry_hash': 'رقم القيد',
    'no_gl_lines': 'لا توجد سطور للقيد',
    'no_entries': 'لا توجد قيود',
    'add_payment': 'إضافة دفعة',
    'open_invoice': 'فتح الفاتورة',
    'repair': 'ملف الإصلاح',
  };
  static String t(String k) => m[k] ?? k;
}
