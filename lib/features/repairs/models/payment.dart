// 📁 lib/features/repairs/models/payment.dart

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'repair.dart'; // لاستيراد تعريف PaymentType

/// موديل يمثل دفعة مالية مرتبطة بإصلاح مركبة
class Payment {
  final int? id; // معرف الدفعة (من قاعدة البيانات SQLite)
  final String repairId; // معرّف الفاتورة/الإصلاح المرتبط (مفتاح خارجي)
  final double amount; // قيمة الدفعة
  final PaymentType paymentType; // طريقة الدفع (نقد، شيك، أقساط، حوالة تأمين)
  final DateTime date; // تاريخ الدفعة
  final String recipient; // اسم المستلم (في حال الشيكات أو التحويل)
  final String fromRecipient; // الجهة المحولة / من المستلم (إن وجدت)
  final String notes; // ملاحظات إضافية

  Payment({
    this.id,
    required this.repairId,
    required this.amount,
    required this.paymentType,
    required this.date,
    required this.recipient,
    required this.fromRecipient,
    required this.notes,
  });

  /// إنشاء نسخة جديدة مع تعديل بعض الحقول فقط
  Payment copyWith({
    int? id,
    String? repairId,
    double? amount,
    PaymentType? paymentType,
    DateTime? date,
    String? recipient,
    String? fromRecipient,
    String? notes,
  }) {
    return Payment(
      id: id ?? this.id,
      repairId: repairId ?? this.repairId,
      amount: amount ?? this.amount,
      paymentType: paymentType ?? this.paymentType,
      date: date ?? this.date,
      recipient: recipient ?? this.recipient,
      fromRecipient: fromRecipient ?? this.fromRecipient,
      notes: notes ?? this.notes,
    );
  }

  /// تحويل كائن دفعة إلى خريطة (Map) لحفظها في قاعدة البيانات
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'repair_id': repairId,
      'amount': amount,
      'payment_type': describeEnum(paymentType), // حفظ اسم enum
      'date': DateFormat('yyyy-MM-dd').format(date),
      'recipient': recipient,
      'from_recipient': fromRecipient,
      'notes': notes,
    };
  }

  /// إنشاء كائن دفعة من خريطة (Map) مقروءة من قاعدة البيانات
  factory Payment.fromMap(Map<String, dynamic> map) {
    // تعيين PaymentType من القيمة المخزنة، أو القيمة الافتراضية cash إذا لم توجد
    PaymentType parsedType = PaymentType.cash;
    if (map['payment_type'] != null) {
      parsedType = PaymentType.values.firstWhere(
        (e) => describeEnum(e) == (map['payment_type'] as String),
        orElse: () => PaymentType.cash,
      );
    }

    return Payment(
      id: map['id'] as int?,
      repairId: map['repair_id'] as String,
      amount: (map['amount'] as num).toDouble(),
      paymentType: parsedType,
      date: DateFormat('yyyy-MM-dd').parse(map['date'] as String),
      recipient: map['recipient'] as String? ?? '',
      fromRecipient: map['from_recipient'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
    );
  }
}
