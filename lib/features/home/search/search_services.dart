// 📁 lib/features/home/search/search_services.dart

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/home/search/search_result.dart';

// نطاقات ثانية
import 'package:yalla_accounts/features/repairs/services/repair_database_service.dart';
import 'package:yalla_accounts/features/raw_materials/services/raw_material_service.dart';
import 'package:yalla_accounts/features/employees/services/employee_service.dart';

/// خدمة بحث عامة عبر نطاقات متعددة
class SearchServices {
  /// يبحث في scopes المحددة عن query ويرجع قائمة من SearchResult
  static Future<List<SearchResult>> searchAll(
    String query,
    List<String> scopes,
  ) async {
    final q = query.trim().toLowerCase();
    final List<SearchResult> results = [];

    // إصلاحات
    if (scopes.contains('repairs')) {
      final repairs = await RepairDatabaseService.getAllRepairs();
      for (final r in repairs) {
        final vehicleNumber = (r.vehicleNumber).toLowerCase();
        final invoiceNumber = (r.invoiceNumber).toLowerCase();
        if (vehicleNumber.contains(q) || invoiceNumber.contains(q)) {
          results.add(
            SearchResult(
              title: 'أمر إصلاح: ${r.vehicleNumber}',
              subtitle: 'الحالة: ${r.paymentStatus}',
              icon: Icons.directions_car,
              route: '/repairs/${r.id}',
            ),
          );
        }
      }
    }

    // المواد الخام
    if (scopes.contains('raw_materials')) {
      final materials = await RawMaterialService.getAllRawMaterials();
      for (final m in materials) {
        final name = (m.name).toLowerCase();
        final sku = (m.sku ?? '').toLowerCase();
        if (name.contains(q) || sku.contains(q)) {
          results.add(
            SearchResult(
              title: 'مادة خام: ${m.name}',
              subtitle: 'المخزون: ${m.quantity}',
              icon: Icons.inventory_2,
              route: '/raw_materials/${m.id}',
            ),
          );
        }
      }
    }

    // الموظفين
    if (scopes.contains('employees')) {
      final employees = await EmployeeService.getAllEmployees();
      for (final e in employees) {
        final full = e.fullName.toLowerCase();
        final id = e.id.toLowerCase();
        if (full.contains(q) || id.contains(q)) {
          results.add(
            SearchResult(
              title: 'موظف: ${e.fullName}',
              subtitle: 'الوظيفة: ${e.jobTitle}',
              icon: Icons.people,
              route: '/employees/${e.id}',
            ),
          );
        }
      }
    }

    // جهات الاتصال (عملاء + مورّدين) عبر خدمة داخلية خفيفة
    final contactService = _ContactService();

    if (scopes.contains('clients')) {
      final clients = await contactService.getClients();
      for (final c in clients) {
        if (c.name.toLowerCase().contains(q) ||
            c.id.toString().contains(query)) {
          results.add(
            SearchResult(
              title: 'عميل: ${c.name}',
              subtitle: 'الهاتف: ${c.phone ?? '—'}',
              icon: Icons.person,
              route: '/clients/${c.id}',
            ),
          );
        }
      }
    }

    if (scopes.contains('suppliers')) {
      final suppliers = await contactService.getSuppliers();
      for (final s in suppliers) {
        if (s.name.toLowerCase().contains(q) ||
            s.id.toString().contains(query)) {
          results.add(
            SearchResult(
              title: 'مورد: ${s.name}',
              subtitle: 'الهاتف: ${s.phone ?? '—'}',
              icon: Icons.local_shipping,
              route: '/suppliers/${s.id}',
            ),
          );
        }
      }
    }

    return results;
  }
}

/// ─────────────────────────────────────────────────────────
/// خدمة داخلية بسيطة لسحب العملاء والموردين من DBService مباشرة
/// بدون الاعتماد على خدمات أخرى (تفادي missing imports).
/// ─────────────────────────────────────────────────────────
class _ContactService {
  Future<Database> _db() => DBService.database;

  Future<List<_Contact>> getClients() async {
    final db = await _db();
    final rows = await db.query(
      'clients',
      columns: ['id', 'name', 'phone'],
      orderBy: 'LOWER(name)',
    );
    return rows
        .map((m) => _Contact(
              id: (m['id'] as num).toInt(),
              name: (m['name'] ?? '').toString(),
              phone: m['phone']?.toString(),
            ))
        .toList();
  }

  Future<List<_Contact>> getSuppliers() async {
    final db = await _db();
    final rows = await db.query(
      'suppliers',
      columns: ['id', 'name', 'phone'],
      orderBy: 'LOWER(name)',
    );
    return rows
        .map((m) => _Contact(
              id: (m['id'] ?? '').toString(), // suppliers.id عندك TEXT
              name: (m['name'] ?? '').toString(),
              phone: m['phone']?.toString(),
            ))
        .toList();
  }
}

class _Contact {
  final Object id; // clients: int, suppliers: String
  final String name;
  final String? phone;
  _Contact({required this.id, required this.name, this.phone});
}
