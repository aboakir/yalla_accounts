// 📁 lib/features/account_statements/shared/account_statement_model.dart
//
// AccountStatementModel — النموذج الأساسي لعرض كشف حساب لأي طرف
// يعتمد حصرياً على DBService + journal_entries + gl_lines.
// مناسب لكشوف: العملاء، الموردين، الموظفين، شركات التأمين.
//
// يحتوي على:
// - معلومات الطرف (الاسم + النوع)
// - الفترة الزمنية (اختيارية)
// - رصيد أول المدة
// - قائمة الحركات الكاملة (مدين/دائن/وصف/تاريخ/مرجع)
// - المجموع المدين والدائن
// - الرصيد النهائي (مدين/دائن)

class AccountStatementModel {
  final String partyId; // نفس party_id في gl_lines
  final String partyName; // الاسم (عميل/مورد/موظف/تأمين)
  final String partyType; // CLIENT / SUPPLIER / EMPLOYEE / INSURANCE

  final DateTime? fromDate; // بداية الفترة
  final DateTime? toDate; // نهاية الفترة

  final double openingBalance; // رصيد أول المدة
  final double totalDebit; // مجموع المدين
  final double totalCredit; // مجموع الدائن
  final double closingBalance; // الرصيد النهائي

  final List<AccountStatementEntry> entries; // قائمة السطور

  const AccountStatementModel({
    required this.partyId,
    required this.partyName,
    required this.partyType,
    required this.fromDate,
    required this.toDate,
    required this.openingBalance,
    required this.totalDebit,
    required this.totalCredit,
    required this.closingBalance,
    required this.entries,
  });
}

// ----------------------------------------------------------------------
// السطر الواحد من كشف الحساب
// ----------------------------------------------------------------------

class AccountStatementEntry {
  final DateTime date; // تاريخ الحركة
  final String description; // الوصف
  final double debit; // مدين
  final double credit; // دائن
  final double balance; // الرصيد بعد الحركة
  final String source; // مصدر الحركة: REPAIR / PAYMENT / PURCHASE / MANUAL
  final String referenceId; // رقم الملف/العملية
  final String? note; // ملاحظة إضافية (اختياري)

  const AccountStatementEntry({
    required this.date,
    required this.description,
    required this.debit,
    required this.credit,
    required this.balance,
    required this.source,
    required this.referenceId,
    this.note,
  });
}
