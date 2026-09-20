import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/models/repair_list_filter.dart';

Repair repair({
  String id = 'r-1',
  String invoice = 'INV-77',
  String vehicleNumber = '12-345-67',
  String vehicleType = 'توسان',
  String vehicleModel = '2020',
  String beneficiary = 'أحمد محمد',
  String beneficiaryType = 'أفراد',
  String vehicleStatus = 'قيد الإصلاح',
  String paymentStatus = 'غير مسدد',
  bool archived = false,
  DateTime? date,
}) {
  return Repair(
    id: id,
    invoiceNumber: invoice,
    vehicleModel: vehicleModel,
    vehicleType: vehicleType,
    vehicleNumber: vehicleNumber,
    receivedDate: date ?? DateTime(2026, 9, 1),
    beneficiaryType: beneficiaryType,
    beneficiaryName: beneficiary,
    insuranceStatus: '',
    repairType: 'بودي ودهان',
    vehicleStatus: vehicleStatus,
    status: 'APPROVED',
    parts: const [],
    works: const [],
    fileValue: 100,
    paymentType: PaymentType.cash,
    paidAmount: paymentStatus == 'مسدد' ? 100 : 0,
    paymentStatus: paymentStatus,
    imagePaths: const [],
    isArchived: archived,
  );
}

void main() {
  test('P06 search covers file, invoice, vehicle and beneficiary identity', () {
    final target = repair();

    for (final query in [
      'r-1',
      'inv-77',
      '12-345',
      'توسان',
      '2020',
      'أحمد',
      'أفراد',
    ]) {
      expect(
        RepairListFilter(search: query).matches(target),
        isTrue,
        reason: 'query=$query',
      );
    }

    expect(
      const RepairListFilter(search: 'كورولا').matches(target),
      isFalse,
    );
  });

  test('P06 payment, vehicle, beneficiary and archive filters compose', () {
    final target = repair(
      beneficiaryType: 'شركة تأمين',
      vehicleStatus: 'جاهزة للتسليم',
      paymentStatus: 'مسدد جزئي',
      archived: true,
    );

    const matching = RepairListFilter(
      paymentStatus: 'مسدد جزئي',
      beneficiaryType: 'شركة تأمين',
      vehicleStatus: 'جاهزة للتسليم',
      archiveScope: RepairArchiveScope.archived,
    );

    expect(matching.matches(target), isTrue);

    expect(
      const RepairListFilter(
        archiveScope: RepairArchiveScope.active,
      ).matches(target),
      isFalse,
    );
  });

  test('P06 date range is inclusive at supplied boundaries', () {
    final target = repair(date: DateTime(2026, 9, 1, 12));

    expect(
      RepairListFilter(
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 1, 23, 59, 59),
      ).matches(target),
      isTrue,
    );

    expect(
      RepairListFilter(
        from: DateTime(2026, 9, 2),
      ).matches(target),
      isFalse,
    );
  });
}
