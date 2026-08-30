// 📁 lib/features/finance/models/ledger_entry.dart

class LedgerEntry {
  final int? id;
  final String date;
  final String description;
  final String debitAccount;
  final String creditAccount;
  final double amount;
  final String referenceType;
  final String referenceId;
  final bool isApproved;
  final String? transactionType; // ✅ جديد

  LedgerEntry({
    this.id,
    required this.date,
    required this.description,
    required this.debitAccount,
    required this.creditAccount,
    required this.amount,
    required this.referenceType,
    required this.referenceId,
    this.isApproved = false,
    this.transactionType, // ✅ جديد
  });

  LedgerEntry copyWith({
    int? id,
    String? date,
    String? description,
    String? debitAccount,
    String? creditAccount,
    double? amount,
    String? referenceType,
    String? referenceId,
    bool? isApproved,
    String? transactionType,
  }) {
    return LedgerEntry(
      id: id ?? this.id,
      date: date ?? this.date,
      description: description ?? this.description,
      debitAccount: debitAccount ?? this.debitAccount,
      creditAccount: creditAccount ?? this.creditAccount,
      amount: amount ?? this.amount,
      referenceType: referenceType ?? this.referenceType,
      referenceId: referenceId ?? this.referenceId,
      isApproved: isApproved ?? this.isApproved,
      transactionType: transactionType ?? this.transactionType,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'date': date,
      'description': description,
      'debit_account': debitAccount,
      'credit_account': creditAccount,
      'amount': amount,
      'reference_type': referenceType,
      'reference_id': referenceId,
      'is_approved': isApproved ? 1 : 0,
      'transaction_type': transactionType, // ✅ جديد
    };
    if (id != null) map['id'] = id!;
    return map;
  }

  factory LedgerEntry.fromMap(Map<String, dynamic> map) {
    return LedgerEntry(
      id: map['id'] as int?,
      date: map['date'] ?? '',
      description: map['description'] ?? '',
      debitAccount: map['debit_account'] ?? '',
      creditAccount: map['credit_account'] ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      referenceType: map['reference_type'] ?? '',
      referenceId: map['reference_id'] ?? '',
      isApproved: map['is_approved'] == 1,
      transactionType: map['transaction_type'], // ✅ جديد
    );
  }
}
