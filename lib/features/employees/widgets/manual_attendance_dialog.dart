// lib/features/employees/widgets/manual_attendance_dialog.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:yalla_accounts/features/employees/models/attendance.dart';
import 'package:yalla_accounts/features/employees/models/employee.dart';

class ManualAttendanceDialog extends StatefulWidget {
  final Employee employee;
  final DateTime date;
  final Attendance? existingRecord;

  const ManualAttendanceDialog({
    super.key,
    required this.employee,
    required this.date,
    this.existingRecord,
  });

  @override
  State<ManualAttendanceDialog> createState() => _ManualAttendanceDialogState();
}

class _ManualAttendanceDialogState extends State<ManualAttendanceDialog> {
  final _formKey = GlobalKey<FormState>();
  String status = 'حاضر';
  String? checkIn;
  String? checkOut;
  String? notes;

  @override
  void initState() {
    super.initState();
    final record = widget.existingRecord;
    if (record != null) {
      status = record.status;
      checkIn = record.checkIn;
      checkOut = record.checkOut;
      notes = record.notes;
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    final record = Attendance(
      id: widget.existingRecord?.id ?? const Uuid().v4(),
      employeeId: widget.employee.id,
      date: widget.date,
      status: status,
      checkIn: checkIn,
      checkOut: checkOut,
      hoursWorked: _calculateHoursWorked(checkIn, checkOut),
      notes: notes,
    );

    Navigator.of(context).pop(record);
  }

  double? _calculateHoursWorked(String? inTime, String? outTime) {
    if (inTime == null || outTime == null) return null;
    try {
      final format = DateFormat("HH:mm");
      final inDate = format.parse(inTime);
      final outDate = format.parse(outTime);
      final diff = outDate.difference(inDate).inMinutes / 60.0;
      return diff > 0 ? diff : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('EEEE dd MMMM yyyy', 'ar').format(widget.date);

    return AlertDialog(
      title: Text('إدخال حضور يدوي - $dateLabel'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'الحالة'),
                value: status,
                onChanged: (val) => setState(() => status = val!),
                items: ['حاضر', 'غائب', 'تأخير', 'إجازة', 'مغادرة']
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
              ),
              if (status == 'حاضر' || status == 'تأخير') ...[
                TextFormField(
                  initialValue: checkIn,
                  decoration: const InputDecoration(
                      labelText: 'وقت الدخول (مثال: 08:30)'),
                  onSaved: (val) => checkIn = val,
                ),
                TextFormField(
                  initialValue: checkOut,
                  decoration: const InputDecoration(
                      labelText: 'وقت الخروج (مثال: 16:30)'),
                  onSaved: (val) => checkOut = val,
                ),
              ],
              TextFormField(
                initialValue: notes,
                decoration: const InputDecoration(labelText: 'ملاحظات'),
                onSaved: (val) => notes = val,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء')),
        ElevatedButton(onPressed: _submit, child: const Text('حفظ')),
      ],
    );
  }
}
