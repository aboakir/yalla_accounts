import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/features/employees/models/attendance.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class AttendanceCalendar extends StatelessWidget {
  final List<Attendance> records;
  final DateTime month;

  const AttendanceCalendar({
    super.key,
    required this.records,
    required this.month,
  });

  @override
  Widget build(BuildContext context) {
    final totalDays = DateUtils.getDaysInMonth(month.year, month.month);
    final days = List.generate(
      totalDays,
      (index) => DateTime(month.year, month.month, index + 1),
    );

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: days.length,
      itemBuilder: (context, index) {
        final day = days[index];
        final matched = records.firstWhere(
          (r) => isSameDate(r.date, day),
          orElse: () => Attendance(
            employeeId: '',
            date: day,
            status: 'غائب', id: '', // افتراضيًا غائب
          ),
        );

        final color = _statusColor(matched.status);
        final emoji = _statusEmoji(matched.status);

        return ListTile(
          leading: CircleAvatar(
            radius: 10,
            backgroundColor: color,
          ),
          title: Text(
            DateFormat('yyyy-MM-dd – EEEE', 'ar').format(day),
            style: const TextStyle(fontSize: 14),
          ),
          trailing: Text(
            '$emoji ${matched.status}',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
    );
  }

  bool isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// تحديد اللون حسب الحالة
  Color _statusColor(String status) {
    switch (status) {
      case 'حاضر':
        return AppColors.primary;
      case 'غائب':
        return Colors.red;
      case 'تأخير':
        return Colors.orange;
      case 'مغادرة':
        return Colors.purple;
      case 'إجازة':
        return Colors.blueGrey;
      default:
        return Colors.grey;
    }
  }

  /// تحديد رمز تعبيري حسب الحالة
  String _statusEmoji(String status) {
    switch (status) {
      case 'حاضر':
        return '✔️';
      case 'غائب':
        return '❌';
      case 'تأخير':
        return '⏰';
      case 'مغادرة':
        return '🚪';
      case 'إجازة':
        return '🌴';
      default:
        return '❓';
    }
  }
}
