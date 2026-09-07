import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/features/repairs/services/repair_payer_bridge.dart';

void main() {
  group('Stage 2 P1-01 payer source of truth', () {
    test('explicit payer markers win over legacy payment defaults', () {
      expect(
        RepairPayerBridge.resolve(
          notes: '[YALLA_PAYER] العميل',
          paymentType: 'insurance',
        ),
        RepairPayerKind.customer,
      );
      expect(
        RepairPayerBridge.resolve(
          notes: '[YALLA_PAYER] شركة تأمين',
          paymentType: 'cash',
        ),
        RepairPayerKind.insurance,
      );
      expect(
        RepairPayerBridge.resolve(
          notes: '[YALLA_PAYER] مختلط',
          paymentType: 'cash',
        ),
        RepairPayerKind.mixed,
      );
    });

    test('legacy cash stays unknown while explicit legacy types are preserved',
        () {
      expect(
        RepairPayerBridge.resolve(notes: '', paymentType: 'cash'),
        RepairPayerKind.legacyUnknown,
      );
      expect(
        RepairPayerBridge.resolve(notes: '', paymentType: 'insurance'),
        RepairPayerKind.insurance,
      );
      expect(
        RepairPayerBridge.resolve(notes: '', paymentType: 'mixed'),
        RepairPayerKind.mixed,
      );
    });

    test('insurance identity marker is stable and replaceable', () {
      const original = '''
[YALLA_PAYER] شركة تأمين
شركة التأمين: ترست
[YALLA_INSURANCE_CLIENT_ID] 12
''';
      expect(RepairPayerBridge.insuranceClientIdFromNotes(original), 12);
      expect(
        RepairPayerBridge.insuranceCompanyNameFromNotes(original),
        'ترست',
      );

      final updated = RepairPayerBridge.withInsuranceClientId(original, 44);
      expect(RepairPayerBridge.insuranceClientIdFromNotes(updated), 44);
      expect('[YALLA_INSURANCE_CLIENT_ID]'.allMatches(updated).length, 1);
    });
  });
}
