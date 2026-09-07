import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/features/employees/services/attendance_database_service.dart';

void main() {
  test('Stage 4 lateness deduction uses worked hourly rate', () {
    expect(
      AttendanceDatabaseService.computeLateDeduction(
        lateMinutes: 60,
        hourlyRate: 20,
      ),
      20,
    );
  });

  test('Stage 4 overtime addition is deterministic', () {
    expect(
      AttendanceDatabaseService.computeOvertimeAddition(
        overtimeHours: 2,
        hourlyRate: 20,
        overtimeMultiplier: 1.5,
      ),
      60,
    );
  });
}
