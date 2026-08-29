// 📁 lib/features/finance/models/journal_entry.dart
//
// JournalEntry Model — واقعي بالكامل بدون بيانات وهمية.
// متوافق مع جدول journal_entries المستخدم في JournalService.
//
// الحقول:
// - id: رقم تسلسلي تلقائي.
// - date: تاريخ القيد (من قاعدة البيانات فقط).
// - description: نص القيد.
// - debit / credit: القيم الفعلية.
// - accountName: اسم الحساب الفعلي.
// - relatedRepairId: معرّف الإصلاح أو العملية المرتبطة.

class JournalEntry {
  final int? id;
  final DateTime date;
  final String description;
  final double debit;
  final double credit;
  final String accountName;
  final String? relatedRepairId;

  const JournalEntry({
    this.id,
    required this.date,
    required this.description,
    required this.debit,
    required this.credit,
    required this.accountName,
    this.relatedRepairId,
  });

  /// بناء من قاعدة البيانات (بدون استخدام now كبديل وهمي)
  factory JournalEntry.fromMap(Map<String, dynamic> map) {
    final rawDate = map['date'];
    DateTime parsedDate;

    if (rawDate is String && rawDate.isNotEmpty) {
      parsedDate = DateTime.tryParse(rawDate) ?? DateTime(1970);
    } else {
      parsedDate = DateTime(1970);
    }

    return JournalEntry(
      id: map['id'] is int
          ? map['id'] as int
          : int.tryParse('${map['id'] ?? ''}'),
      date: parsedDate,
      description: map['description'] ?? '',
      debit: (map['debit'] as num?)?.toDouble() ?? 0.0,
      credit: (map['credit'] as num?)?.toDouble() ?? 0.0,
      accountName: map['accountName'] ?? '',
      relatedRepairId: map['relatedRepairId']?.toString(),
    );
  }

  /// تحويل إلى Map لتخزينها في SQLite
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'date': date.toIso8601String(),
      'description': description,
      'debit': debit,
      'credit': credit,
      'accountName': accountName,
      'relatedRepairId': relatedRepairId,
    };
    if (id != null) map['id'] = id!;
    return map;
  }

  /// إنشاء نسخة جديدة معدّلة من القيد
  JournalEntry copyWith({
    int? id,
    DateTime? date,
    String? description,
    double? debit,
    double? credit,
    String? accountName,
    String? relatedRepairId,
  }) {
    return JournalEntry(
      id: id ?? this.id,
      date: date ?? this.date,
      description: description ?? this.description,
      debit: debit ?? this.debit,
      credit: credit ?? this.credit,
      accountName: accountName ?? this.accountName,
      relatedRepairId: relatedRepairId ?? this.relatedRepairId,
    );
  }

  /// helpers
  bool get isDebit => debit > 0 && credit == 0;
  bool get isCredit => credit > 0 && debit == 0;
  double get netAmount => debit - credit;
}
