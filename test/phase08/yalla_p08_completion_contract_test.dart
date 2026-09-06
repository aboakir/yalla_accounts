import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P08 repair details completion contract', () {
    late String details;

    setUpAll(() {
      details = File(
        'lib/features/repairs/screens/repair_details_screen.dart',
      ).readAsStringSync();
    });

    test(
        'payments use the official receipt voucher and settled files are guarded',
        () {
      expect(details, contains('AppRoutes.receiptVoucher'));
      expect(details, contains('_repair.remainingAmount <= 0.005'));
      expect(details, contains('if (remaining > 0.005)'));
      expect(details, isNot(contains('PaymentService.insertAndPostReceipt')));
      expect(details, isNot(contains('final payment = Payment(')));
    });

    test('notes are visible without leaking internal YALLA markers', () {
      expect(details, contains('String get _visibleNotes'));
      expect(details, contains("!line.startsWith('[YALLA_')"));
      expect(details, contains("'الملاحظات'"));
      expect(details, contains('_buildNotesCard()'));
    });

    test(
        'existing repair edit history is read without creating a new audit system',
        () {
      expect(details, contains("name = 'repair_edit_history'"));
      expect(details, contains("'repair_edit_history'"));
      expect(details, contains("where: 'repair_id = ?'"));
      expect(details, contains("orderBy: 'created_at DESC'"));
      expect(details, contains("'سجل التغييرات'"));
    });

    test('operational states use canonical repair status sources', () {
      expect(details, contains('kVehicleStatuses'));
      expect(details, contains('kVehicleStatusAliases'));
      expect(details, contains('kInsuranceFollowups'));
      expect(details,
          isNot(contains('static const List<String> _vehicleOptions')));
      expect(details,
          isNot(contains('static const List<String> _insuranceOptions')));
    });

    test('phone tablet desktop breakpoints are respected', () {
      expect(details, contains('width < YallaBreakpoints.phone'));
      expect(details, contains('width >= YallaBreakpoints.desktop'));
      expect(details, contains('if (isDesktop)'));
      expect(details, contains("tooltip: 'القائمة'"));
      expect(details, isNot(contains('الشاشة صغيرة جدًا')));
      expect(details, isNot(contains('>= 1000')));
    });

    test('P08 does not increase legacy raw desktop-prone widgets', () {
      final rawRow = RegExp(r'(^|[^A-Za-z0-9_.])Row\s*\(', multiLine: true);
      final rawTable =
          RegExp(r'(^|[^A-Za-z0-9_.])DataTable\s*\(', multiLine: true);
      final rawDialog =
          RegExp(r'(^|[^A-Za-z0-9_.])AlertDialog\s*\(', multiLine: true);

      // P08 Audit baseline already had four raw Row usages in this screen.
      // This phase must not add new raw desktop-prone layout primitives.
      expect(rawRow.allMatches(details).length, lessThanOrEqualTo(4));
      expect(rawTable.hasMatch(details), isFalse);
      expect(rawDialog.hasMatch(details), isFalse);
    });
  });
}
