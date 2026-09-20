import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/screens/repairs_and_ar_screen.dart';

Repair _repair({
  required String id,
  required String name,
  required String number,
  required String type,
  required String paymentStatus,
  required String date,
}) =>
    Repair.fromMap({
      'id': id,
      'beneficiaryName': name,
      'beneficiaryType': type,
      'vehicleNumber': number,
      'vehicleType': 'Sedan',
      'receivedDate': date,
      'paymentStatus': paymentStatus,
      'fileValue': 1000,
    });

void main() {
  final repairs = <Repair>[
    _repair(
        id: 'I-PAID',
        name: 'أحمد',
        number: 'ABC-123',
        type: 'فرد',
        paymentStatus: 'مسدد',
        date: '2026-09-01'),
    _repair(
        id: 'I-PARTIAL',
        name: 'سامي',
        number: 'DEF-456',
        type: 'فرد',
        paymentStatus: 'مسدد جزئي',
        date: '2026-09-05'),
    _repair(
        id: 'INS-OPEN',
        name: 'شركة الأمان',
        number: 'INS-777',
        type: 'شركة تأمين',
        paymentStatus: 'غير مسدد',
        date: '2026-09-07'),
    _repair(
        id: 'I-OPEN',
        name: 'ليلى',
        number: 'XYZ-999',
        type: 'فرد',
        paymentStatus: 'غير مسدد',
        date: '2026-09-20'),
  ];

  test('FIN-UI-003 counts match the visible data set', () {
    final visible = filterFinancialReceivables(repairs, insuranceTab: false);
    final stats = financialReceivableStats(visible);
    expect(visible, hasLength(3));
    expect(stats, {
      'المجموع': 3,
      'مسدد': 1,
      'جزئي': 1,
      'غير مسدد': 1,
    });
  });

  test('FIN-UI-004 payment, date and customer-type filters work', () {
    final partial = filterFinancialReceivables(
      repairs,
      insuranceTab: false,
      paymentStatus: 'مسدد جزئي',
    );
    expect(partial.map((r) => r.id), ['I-PARTIAL']);

    final dated = filterFinancialReceivables(
      repairs,
      insuranceTab: false,
      dateRange: DateTimeRange(
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 10, 23, 59, 59),
      ),
    );
    expect(dated.map((r) => r.id), ['I-PAID', 'I-PARTIAL']);

    final insurance = filterFinancialReceivables(
      repairs,
      insuranceTab: true,
    );
    expect(insurance.map((r) => r.id), ['INS-OPEN']);
  });

  test('FIN-UI-005 search works across party, plate and vehicle type', () {
    final byPlate = filterFinancialReceivables(repairs,
        insuranceTab: false, search: 'abc-123');
    expect(byPlate.map((r) => r.id), ['I-PAID']);

    final byName = filterFinancialReceivables(repairs,
        insuranceTab: false, search: 'ليلى');
    expect(byName.map((r) => r.id), ['I-OPEN']);
  });

  test('FIN-UI-006 totals remain coherent after filtering', () {
    final visible = filterFinancialReceivables(
      repairs,
      insuranceTab: false,
      dateRange: DateTimeRange(
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 10, 23, 59, 59),
      ),
    );
    final stats = financialReceivableStats(visible);
    expect(stats['المجموع'], visible.length);
    expect((stats['مسدد']! + stats['جزئي']! + stats['غير مسدد']!),
        stats['المجموع']);
  });

  test('FIN-UI-002 chart labels cannot overlap and chart is not duplicated',
      () async {
    final sections = financialReceivablePieSections({
      'مسدد': 4,
      'جزئي': 3,
      'غير مسدد': 2,
    });
    expect(sections, hasLength(3));
    expect(sections.every((section) => section.showTitle == false), isTrue);

    final source = await File(
      'lib/features/repairs/screens/repairs_and_ar_screen.dart',
    ).readAsString();
    expect(RegExp(r'\bPieChart\(').allMatches(source), hasLength(1));
    expect(source, contains('_legendItem('));
  });
}
