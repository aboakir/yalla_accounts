// 📁 lib/features/employees/models/attendance.dart

class Attendance {
  final String id;
  final String employeeId;
  final DateTime date;
  final String status; // حاضر، غائب، عطلة، إلخ
  final String? checkIn;
  final String? checkOut;
  final double? hoursWorked;
  final String? notes;

  Attendance({
    required this.id,
    required this.employeeId,
    required this.date,
    required this.status,
    this.checkIn,
    this.checkOut,
    this.hoursWorked,
    this.notes,
  });

  /// إنشاء Attendance من Map
  factory Attendance.fromMap(Map<String, dynamic> map) {
    return Attendance(
      id: map['id'] ?? '',
      employeeId: map['employeeId'] ?? '',
      date: DateTime.tryParse(map['date'] ?? '') ?? DateTime.now(),
      status: map['status'] ?? 'غير محدد',
      checkIn: map['checkIn'],
      checkOut: map['checkOut'],
      hoursWorked: (map['hoursWorked'] as num?)?.toDouble(),
      notes: map['notes'],
    );
  }

  /// تحويل Attendance إلى Map لتخزينها في قاعدة البيانات
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'employeeId': employeeId,
      'date': date.toIso8601String(),
      'status': status,
      'checkIn': checkIn,
      'checkOut': checkOut,
      'hoursWorked': hoursWorked,
      'notes': notes,
    };
  }

  /// إنشاء نسخة معدلة من Attendance
  Attendance copyWith({
    String? id,
    String? employeeId,
    DateTime? date,
    String? status,
    String? checkIn,
    String? checkOut,
    double? hoursWorked,
    String? notes,
  }) {
    return Attendance(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      date: date ?? this.date,
      status: status ?? this.status,
      checkIn: checkIn ?? this.checkIn,
      checkOut: checkOut ?? this.checkOut,
      hoursWorked: hoursWorked ?? this.hoursWorked,
      notes: notes ?? this.notes,
    );
  }
}
