import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/employees/models/employee.dart';
import 'package:yalla_accounts/features/employees/services/employee_service.dart';
import 'package:yalla_accounts/features/suppliers/services/supplier_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('YA-HUMAN-003 quick employee uses real employee master data', () async {
    final dir = await Directory.systemTemp.createTemp('quick_employee_');
    final db = await DatabaseMigration.initDatabase(
      pathOverride: '${dir.path}/test.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);
    try {
      final code = 'EMP-QA-003';
      await EmployeeService.addEmployee(
        Employee.fromMap(<String, dynamic>{
          'id': '',
          'full_name': 'QA Technician',
          'employee_code': code,
          'job_title': 'فني',
          'hire_date': DateTime(2026, 9, 19).toIso8601String(),
          'status': 'active',
          'contract_type': 'monthly',
          'base_salary': 0.0,
          'payment_method': 'cash',
        }),
      );
      final employees = await EmployeeService.getAllEmployees();
      final created = employees.where((e) => e.employeeCode == code).toList();
      expect(created, hasLength(1));
      expect(created.single.id, isNotEmpty);
      expect(created.single.fullName, 'QA Technician');
    } finally {
      DatabaseMigration.useDatabaseForTesting(null);
      if (db.isOpen) await db.close();
      await dir.delete(recursive: true);
    }
  });

  test('YA-HUMAN-016 quick supplier uses real supplier master data', () async {
    final dir = await Directory.systemTemp.createTemp('quick_supplier_');
    final db = await DatabaseMigration.initDatabase(
      pathOverride: '${dir.path}/test.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);
    try {
      final id = await SupplierService.insertOrGetSupplierId('QA Supplier');
      expect(int.tryParse(id), greaterThan(0));
      final suppliers = await SupplierService.getAllSuppliers();
      final created = suppliers.where((s) => s.id == id).toList();
      expect(created, hasLength(1));
      expect(created.single.name, 'QA Supplier');
      expect(created.single.pid, isNotEmpty);
    } finally {
      DatabaseMigration.useDatabaseForTesting(null);
      if (db.isOpen) await db.close();
      await dir.delete(recursive: true);
    }
  });

  test('Phase 5 UI keeps quick creation inside current workflows', () {
    final employeeSource = File(
      'lib/features/repairs/widgets/repair_workflow_card.dart',
    ).readAsStringSync();
    final supplierSource = File(
      'lib/features/finance/purchases/screens/purchase_create_screen.dart',
    ).readAsStringSync();

    expect(employeeSource, contains('إضافة موظف سريع'));
    expect(employeeSource, contains('EmployeeService.addEmployee'));
    expect(employeeSource, contains('إضافة واختيار'));

    expect(supplierSource, contains('SupplierService.insertOrGetSupplierId'));
    expect(supplierSource, contains('كمورد جديد'));
    expect(supplierSource, isNot(contains('txn.insert("suppliers"')));
  });
}
