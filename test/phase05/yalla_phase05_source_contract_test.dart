import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('P05 client and vehicle source contract is complete', () {
    final migration = File(
      'lib/core/services/db/database_migration.dart',
    ).readAsStringSync();
    final constants = File(
      'lib/core/services/db/database_constants.dart',
    ).readAsStringSync();
    final clients = File(
      'lib/features/clients/services/client_service.dart',
    ).readAsStringSync();
    final clientEdit = File(
      'lib/features/clients/screens/client_edit_screen.dart',
    ).readAsStringSync();
    final clientProfile = File(
      'lib/features/clients/widgets/client_details_dialog.dart',
    ).readAsStringSync();
    final vehicles = File(
      'lib/features/repairs/screens/vehicles_list_screen.dart',
    ).readAsStringSync();
    final repairSave = File(
      'lib/features/repairs/services/repair_save_service.dart',
    ).readAsStringSync();

    expect(migration, contains('await VehicleTables.ensure(db);'));
    expect(constants, contains("'vehicles'"));

    expect(clients, contains('ClientProfileSnapshot'));
    expect(clients, contains('findDuplicateIdOn'));
    expect(clients, contains("entityType: 'client'"));
    expect(clientEdit, contains('notes: _notesController.text.trim()'));
    expect(clientProfile, contains('آخر ملفات الإصلاح'));

    expect(vehicles, contains('VehicleService.getAllVehicles()'));
    expect(vehicles, contains('VehicleHistoryDialog'));
    expect(
      vehicles,
      contains('if (MediaQuery.sizeOf(context).width >= 600)'),
    );
    expect(
      vehicles,
      isNot(contains('RepairDatabaseService.getAllRepairs()')),
    );

    expect(
      repairSave,
      contains('ClientService.upsertFromRepairOn('),
    );
    expect(
      repairSave,
      contains('VehicleService.upsertFromRepairOn('),
    );
  });

  test('P05 keeps DB version and routes compatible', () {
    final constants = File(
      'lib/core/services/db/database_constants.dart',
    ).readAsStringSync();
    final routes = File(
      'lib/core/routes/app_routes.dart',
    ).readAsStringSync();

    final version = int.parse(
      RegExp(r'static const int dbVersion = (\d+);')
          .firstMatch(constants)!
          .group(1)!,
    );
    expect(version, greaterThanOrEqualTo(76));
    expect(
        routes, contains("static const vehiclesList = '/repairs/vehicles';"));
    expect(routes, contains('VehiclesListScreen(initialVehicleId: vehicleId)'));
    expect(
      routes,
      contains('return _page(settings, const ClientEditScreen());'),
    );
  });
}
