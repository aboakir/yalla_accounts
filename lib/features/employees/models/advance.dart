// 📁 lib/features/employees/models/advance.dart
//
// Advance — سجل سلفة/مكافأة/تسديد موظف (متوافق مع v30)
// الحقول تشمل method و glEntryId اختياريًا لانسجام الخدمات.
// نوع الحركة يدعم: 'advance' | 'bonus' | 'repayment'.
//
// Fields include optional method and glEntryId for service compatibility.
// Supported types: 'advance' | 'bonus' | 'repayment'.

class Advance {
  final String id; // UUID نصي | String UUID
  final String employeeId; // معرّف الموظف | Employee ID
  final double amount; // قيمة موجبة | Positive amount
  final String type; // 'advance' | 'bonus' | 'repayment'
  final DateTime date; // تاريخ السجل | Record date
  final String? method; // 'cash' | 'bank' | 'cheque' ... | Optional
  final String? note; // ملاحظة اختيارية | Optional note
  final int? glEntryId; // gl_entries.id المرتبط | Linked GL entry id

  const Advance({
    required this.id,
    required this.employeeId,
    required this.amount,
    required this.type,
    required this.date,
    this.method,
    this.note,
    this.glEntryId,
  });

  /// نسخ مع تعديلات | Copy with overrides
  Advance copyWith({
    String? id,
    String? employeeId,
    double? amount,
    String? type,
    DateTime? date,
    String? method,
    String? note,
    int? glEntryId,
  }) {
    return Advance(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      amount: amount ?? this.amount,
      type: (type ?? this.type).toLowerCase(),
      date: date ?? this.date,
      method: method ?? this.method,
      note: note ?? this.note,
      glEntryId: glEntryId ?? this.glEntryId,
    );
  }

  /// إلى خريطة DB (snake_case) | To DB map
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'employee_id': employeeId,
      'amount': amount,
      'type': type.toLowerCase(), // normalize
      'date': date.toIso8601String(),
      'method': method,
      'note': note,
      'gl_entry_id': glEntryId,
    };
  }

  /// من خريطة DB إلى كائن | From DB map
  factory Advance.fromMap(Map<String, Object?> map) {
    String readString(String key) => (map[key] ?? '').toString();

    final rawDate = map['date'];
    final parsedDate = rawDate is DateTime
        ? rawDate
        : DateTime.tryParse(readString('date')) ?? DateTime.now();

    int? readInt(String key) {
      final v = map[key];
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    double readDouble(String key) {
      final v = map[key];
      if (v is num) return v.toDouble();
      return double.tryParse(readString(key)) ?? 0.0;
    }

    return Advance(
      id: readString('id'),
      employeeId: readString('employee_id').isNotEmpty
          ? readString('employee_id')
          : readString('employeeId'),
      amount: readDouble('amount'),
      type: readString('type').toLowerCase(), // normalize
      date: parsedDate,
      method: map['method']?.toString(),
      note: map['note']?.toString(),
      glEntryId: readInt('gl_entry_id') ?? readInt('glEntryId'),
    );
  }

  @override
  String toString() =>
      'Advance(id: $id, employeeId: $employeeId, amount: $amount, type: $type, date: $date, method: $method, note: $note, glEntryId: $glEntryId)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Advance &&
        other.id == id &&
        other.employeeId == employeeId &&
        other.amount == amount &&
        other.type == type &&
        other.date == date &&
        other.method == method &&
        other.note == note &&
        other.glEntryId == glEntryId;
  }

  @override
  int get hashCode =>
      id.hashCode ^
      employeeId.hashCode ^
      amount.hashCode ^
      type.hashCode ^
      date.hashCode ^
      (method?.hashCode ?? 0) ^
      (note?.hashCode ?? 0) ^
      (glEntryId ?? 0).hashCode;
}
