// 📁 lib/features/finance/models/accounts_receivable_entry.dart
//
// AccountsReceivableEntry — موديل خفيف ومتوافق مع كل الاستخدامات الحالية.
// الحقول:
//
// - id:          معرف السجل (String?)
// - repairId:    معرف ملف الإصلاح (String?)
// - amount:      المبلغ (double)
// - date:        تاريخ إنشاء/تسجيل السجل (ISO String?)
// - isPaid:      هل هو دفعة فعلية؟ (true) أم استحقاق متبقّي؟ (false)
// - paidDate:    تاريخ الدفع إن كانت دفعة (ISO String?)
// - dueDate:     تاريخ الاستحقاق (ISO String?)
// - customer:    اسم العميل (String?)
// - method:      طريقة الدفع/نوع السجل (String?)
//
// ملاحظات:
// - هذا الموديل يُستخدم لعرض عناصر الذمم: الدفعات (isPaid=true) + عنصر متبقّي واحد (isPaid=false).
// - لا يعتمد على جدول AR فعلي؛ الخدمة تبنيه من payments/repairs/invoices.

class AccountsReceivableEntry {
  final String? id;
  final String? repairId;
  final double amount;
  final String? date;
  final bool isPaid;
  final String? paidDate;
  final String? dueDate;
  final String? customer;
  final String? method;

  const AccountsReceivableEntry({
    this.id,
    this.repairId,
    required this.amount,
    this.date,
    required this.isPaid,
    this.paidDate,
    this.dueDate,
    this.customer,
    this.method,
  });

  AccountsReceivableEntry copyWith({
    String? id,
    String? repairId,
    double? amount,
    String? date,
    bool? isPaid,
    String? paidDate,
    String? dueDate,
    String? customer,
    String? method,
  }) {
    return AccountsReceivableEntry(
      id: id ?? this.id,
      repairId: repairId ?? this.repairId,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      isPaid: isPaid ?? this.isPaid,
      paidDate: paidDate ?? this.paidDate,
      dueDate: dueDate ?? this.dueDate,
      customer: customer ?? this.customer,
      method: method ?? this.method,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'repairId': repairId,
      'amount': amount,
      'date': date,
      'isPaid': isPaid ? 1 : 0, // للتوافق مع SQLite
      'paidDate': paidDate,
      'dueDate': dueDate,
      'customer': customer,
      'method': method,
    };
  }

  factory AccountsReceivableEntry.fromMap(Map<String, dynamic> map) {
    double toDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    bool toBool(dynamic v) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      final s = v?.toString().toLowerCase();
      if (s == 'true') return true;
      if (s == 'false') return false;
      return false;
    }

    return AccountsReceivableEntry(
      id: map['id']?.toString(),
      repairId: map['repairId']?.toString() ?? map['repair_id']?.toString(),
      amount: toDouble(map['amount']),
      date: map['date']?.toString(),
      isPaid: toBool(map['isPaid']),
      paidDate: map['paidDate']?.toString(),
      dueDate: map['dueDate']?.toString(),
      customer: map['customer']?.toString(),
      method: map['method']?.toString(),
    );
  }

  @override
  String toString() =>
      'AR(id:$id, repairId:$repairId, amount:$amount, isPaid:$isPaid, method:$method)';
}
