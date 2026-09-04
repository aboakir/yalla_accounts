import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String source(String path) => File(path).readAsStringSync();

  test('V10J defines one canonical cross-platform Yalla storage root', () {
    final storage = source('lib/core/storage/yalla_storage_service.dart');

    expect(storage, contains(r"D:\YallaAccounts"));
    expect(storage, contains('getApplicationSupportDirectory'));
    expect(storage, contains("'YallaAccounts'"));
    expect(storage, contains("'repairs'"));
    expect(storage, contains("'insurance'"));
    expect(storage, contains("'documents'"));
    expect(storage, contains("'backups'"));
  });

  test('new repair intake no longer persists picker paths directly', () {
    final intake =
        source('lib/features/repairs/screens/add_repair_screen.dart');

    expect(intake, contains('YallaStorageService.saveImageFromPath'));
    expect(intake, isNot(contains('repair_intake_photos')));
  });

  test('repair and insurance images share canonical storage service', () {
    final imageStorage = source('lib/core/services/image_storage_service.dart');
    final policy = source(
        'lib/features/insurance_agent/policies/screens/policy_details_screen.dart');

    expect(imageStorage, contains('YallaStorageService.saveImage'));
    expect(imageStorage, contains('resolveStoredPath'));
    expect(policy, contains('YallaStorageService.resolveExistingPath'));
  });

  test('all requested repair profile views resolve stored paths', () {
    final repairs = source('lib/features/repairs/screens/repairs_screen.dart');
    final vehicles =
        source('lib/features/repairs/screens/vehicles_list_screen.dart');
    final receipt =
        source('lib/features/vouchers/screens/receipt_voucher_screen.dart');
    final dashboard = source('lib/features/home/screens/dashboard_screen.dart');

    expect(repairs, contains('YallaStoredImage'));
    expect(vehicles, contains('YallaStoredImage'));
    expect(receipt, contains('YallaStoredImage'));
    expect(dashboard, contains('YallaStoredImage'));
  });

  test('repair and insurance PDFs use Yalla storage hierarchy', () {
    final repairPdf =
        source('lib/features/repairs/services/repair_pdf_generator.dart');
    final policyList = source(
        'lib/features/insurance_agent/policies/screens/policies_list_screen.dart');

    expect(repairPdf, contains("module: 'repairs'"));
    expect(policyList, contains("module: 'insurance'"));
  });

  test('legacy iOS absolute paths are rebased instead of trusted forever', () {
    final storage = source('lib/core/storage/yalla_storage_service.dart');

    expect(storage, contains("final marker = '/YallaAccounts/';"));
    expect(storage, contains("'repair_intake_photos'"));
    expect(storage, contains("'repair_signatures'"));
    expect(storage, contains('resolveExistingPath'));
  });
}
