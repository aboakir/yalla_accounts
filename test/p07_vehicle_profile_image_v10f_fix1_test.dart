import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/features/vehicles/models/vehicle.dart';

void main() {
  test('vehicle projection carries canonical repair profile path', () {
    const vehicle = Vehicle(
      number: '9007654',
      type: 'tucson',
      model: '2022',
      profileImagePath: '/tmp/profile.jpg',
    );

    expect(vehicle.profileImagePath, '/tmp/profile.jpg');
    expect(
        vehicle.copyWith(repairCount: 3).profileImagePath, '/tmp/profile.jpg');
  });

  test(
      'V10F FIX1 wires one canonical thumbnail through the three requested views',
      () {
    String source(String path) => File(path).readAsStringSync();

    final service =
        source('lib/features/repairs/services/repairs_service.dart');
    final details =
        source('lib/features/repairs/screens/repair_details_screen.dart');
    final repairs = source('lib/features/repairs/screens/repairs_screen.dart');
    final vehicles =
        source('lib/features/repairs/screens/vehicles_list_screen.dart');
    final vehicleService =
        source('lib/features/vehicles/services/vehicle_service.dart');
    final receipt =
        source('lib/features/vouchers/screens/receipt_voucher_screen.dart');

    expect(service, contains('autoSelectCoverAndSave'));
    expect(service, contains('centerSharpness'));
    expect(service, contains('contrastScore'));

    expect(details, contains('await svc.autoSelectCoverAndSave'));
    expect(repairs, contains('final profilePath = r.thumbnailPath?.trim();'));
    expect(repairs, contains('YallaStoredImage('));
    expect(repairs, contains('storedPath: profilePath'));

    expect(vehicleService, contains('repair.thumbnailPath?.trim()'));
    expect(vehicles, contains('vehicle.profileImagePath'));
    expect(vehicles, contains('_VehicleProfileThumb'));

    expect(receipt, contains('thumbnail_path'));
    expect(receipt, contains('_buildRepairImage'));
    expect(receipt, contains('YallaStoredImage('));
  });
}
