// lib/features/payments/models/payment_record.dart

class PaymentRecord {
  final String id;
  final String repairId;
  final double amount;
  final DateTime date;
  final String notes;

  PaymentRecord({
    required this.id,
    required this.repairId,
    required this.amount,
    required this.date,
    required this.notes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'repairId': repairId,
      'amount': amount,
      'date': date.toIso8601String(),
      'notes': notes,
    };
  }

  factory PaymentRecord.fromMap(Map<String, dynamic> map) {
    return PaymentRecord(
      id: map['id'],
      repairId: map['repairId'],
      amount: map['amount'],
      date: DateTime.parse(map['date']),
      notes: map['notes'],
    );
  }
}
