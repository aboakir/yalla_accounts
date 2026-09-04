import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/features/repairs/services/repair_auto_accounting_service.dart';

void main() {
  group('P07 auto accounting V10B', () {
    final works = <Map<String, dynamic>>[
      <String, dynamic>{
        'name': 'دهان',
        'qty': 1.0,
        'price': 400.0,
        'total': 400.0
      },
    ];
    final parts = <Map<String, dynamic>>[
      <String, dynamic>{
        'name': 'قطعة',
        'qty': 2.0,
        'price': 100.0,
        'total': 200.0
      },
    ];

    test('workshop supplied parts enter repair value', () {
      expect(
        RepairAutoAccountingService.computeAccountingTotal(
          works: works,
          parts: parts,
          notes: '[YALLA_PARTS_SUPPLY] الورشة',
        ),
        600.0,
      );
    });

    test('customer or insurer supplied parts do not enter repair value', () {
      for (final source in <String>['العميل', 'شركة التأمين']) {
        expect(
          RepairAutoAccountingService.computeAccountingTotal(
            works: works,
            parts: parts,
            notes: '[YALLA_PARTS_SUPPLY] $source',
          ),
          400.0,
        );
      }
    });

    test('zero-value repair is a valid settled file', () {
      expect(
        RepairAutoAccountingService.computeAccountingTotal(
          works: const <Map<String, dynamic>>[],
          parts: const <Map<String, dynamic>>[],
          notes: '[YALLA_PARTS_SUPPLY] الورشة',
        ),
        0.0,
      );
      expect(RepairAutoAccountingService.paymentStatusFor(0.0, 0.0), 'مسدد');
    });
  });
}
