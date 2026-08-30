import 'package:sqflite/sqflite.dart';

import '../services/db/db_service.dart';
import 'organization_identity.dart';

typedef OrganizationDatabaseProvider = Future<Database> Function();

/// Read-only access to the permanent organization identity established by
/// SEC.001. Mutation of organization identity is intentionally not exposed to
/// the desktop client.
class OrganizationIdentityService {
  OrganizationIdentityService({OrganizationDatabaseProvider? databaseProvider})
      : _databaseProvider = databaseProvider ?? (() => DBService.database);

  final OrganizationDatabaseProvider _databaseProvider;

  Future<OrganizationIdentity> current() async {
    final db = await _databaseProvider();
    final rows = await db.rawQuery('''
      SELECT
        oi.organization_id,
        oi.created_at,
        o.display_name,
        o.country_code,
        o.status
      FROM organization_identity oi
      INNER JOIN organizations o ON o.id = oi.organization_id
      WHERE oi.singleton_id = 1
      LIMIT 1
    ''');

    if (rows.isEmpty) {
      throw StateError('Organization identity is not initialized.');
    }

    final row = rows.first;
    final organizationId = row['organization_id']?.toString() ?? '';
    if (!_looksLikeUuid(organizationId)) {
      throw StateError('Organization identity is invalid.');
    }

    final createdAt = DateTime.tryParse(row['created_at']?.toString() ?? '');
    if (createdAt == null) {
      throw StateError('Organization identity timestamp is invalid.');
    }

    return OrganizationIdentity(
      organizationId: organizationId,
      status: row['status']?.toString() ?? 'unknown',
      createdAt: createdAt,
      displayName: _cleanNullable(row['display_name']),
      countryCode: _cleanNullable(row['country_code']),
    );
  }

  Future<String> requireOrganizationId() async {
    return (await current()).organizationId;
  }

  static String? _cleanNullable(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static bool _looksLikeUuid(String value) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-'
      r'[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
  }
}
