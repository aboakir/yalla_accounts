import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/services/db/db_service.dart';
import '../../core/services/db/tables/organization_identity_tables.dart';
import '../../core/services/db/tables/owner_bootstrap_tables.dart';
import 'customer_onboarding_client.dart';
import 'customer_onboarding_service.dart';

class ApprovedOnboardingActivationException implements Exception {
  const ApprovedOnboardingActivationException(this.code);
  final String code;

  @override
  String toString() => 'ApprovedOnboardingActivationException: $code';
}

final approvedOnboardingActivationServiceProvider =
    Provider((ref) => ApprovedOnboardingActivationService(
          client: ref.watch(customerOnboardingClientProvider),
          database: () => DBService.database,
        ));

class ApprovedOnboardingActivationService {
  ApprovedOnboardingActivationService({
    required this.client,
    required this.database,
  });

  final CustomerOnboardingClient client;
  final Future<Database> Function() database;

  Future<CustomerOnboardingStatus> prepare() async {
    final session = await client.sessionProvider();
    final status = await client.send(session, 'status', const {});
    if (!status.approved) {
      throw const ApprovedOnboardingActivationException(
        'ONBOARDING_NOT_APPROVED',
      );
    }
    final canonicalOrganizationId =
        status.data['organization_id']?.toString() ?? '';
    if (!_looksLikeUuid(canonicalOrganizationId)) {
      throw const ApprovedOnboardingActivationException(
        'INVALID_CANONICAL_ORGANIZATION',
      );
    }

    final db = await database();
    await db.transaction((txn) async {
      final staged = await txn.query(
        'pending_customer_onboarding',
        where: 'auth_user_id = ?',
        whereArgs: [session.authUserId],
        limit: 2,
      );
      if (staged.length != 1 ||
          staged.single['owner_stage'] != 'APPROVED_AWAITING_ACTIVATION') {
        throw const ApprovedOnboardingActivationException(
          'APPROVED_STAGE_MISSING',
        );
      }
      final cachedRaw = staged.single['response_json']?.toString();
      final cached = cachedRaw == null
          ? null
          : jsonDecode(cachedRaw) as Map<String, dynamic>?;
      if (cached == null ||
          cached['request_id']?.toString() != status.requestId ||
          cached['organization_id']?.toString() != canonicalOrganizationId) {
        throw const ApprovedOnboardingActivationException(
          'CACHED_APPROVAL_MISMATCH',
        );
      }

      final identity = await txn.query(
        'organization_identity',
        where: 'singleton_id = 1',
        limit: 2,
      );
      if (identity.length != 1) {
        throw const ApprovedOnboardingActivationException(
          'LOCAL_ORGANIZATION_MISSING',
        );
      }
      final currentOrganizationId =
          identity.single['organization_id']?.toString() ?? '';
      if (!_looksLikeUuid(currentOrganizationId)) {
        throw const ApprovedOnboardingActivationException(
          'LOCAL_ORGANIZATION_INVALID',
        );
      }

      await _assertFreshPreActivation(txn, currentOrganizationId);
      if (currentOrganizationId == canonicalOrganizationId) {
        return;
      }

      await _assertNoBusinessScopeReferences(
        txn,
        currentOrganizationId,
        canonicalOrganizationId,
      );

      final canonicalExists = await txn.query(
        'organizations',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [canonicalOrganizationId],
        limit: 1,
      );
      if (canonicalExists.isNotEmpty) {
        throw const ApprovedOnboardingActivationException(
          'CANONICAL_ORGANIZATION_ALREADY_EXISTS',
        );
      }

      final draftRaw = staged.single['draft_json']?.toString();
      final draft = draftRaw == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(draftRaw) as Map);
      final serverTime =
          DateTime.parse(status.data['server_time']!.toString()).toUtc();
      final now = serverTime.toIso8601String();
      await txn.insert('organizations', {
        'id': canonicalOrganizationId,
        'display_name': draft['organization_name']?.toString(),
        'country_code': draft['country_code']?.toString(),
        'status': 'active',
        'created_at': now,
        'updated_at': now,
      });

      final bootstrapChanged = await txn.update(
        'owner_bootstrap_state',
        {
          'organization_id': canonicalOrganizationId,
          'updated_at': now,
        },
        where: 'singleton_id = 1 AND organization_id = ? AND status = ?',
        whereArgs: [currentOrganizationId, 'PENDING'],
      );
      if (bootstrapChanged != 1) {
        throw const ApprovedOnboardingActivationException(
          'OWNER_BOOTSTRAP_SCOPE_CONFLICT',
        );
      }

      final identityChanged = await txn.update(
        'organization_identity',
        {'organization_id': canonicalOrganizationId},
        where: 'singleton_id = 1 AND organization_id = ?',
        whereArgs: [currentOrganizationId],
      );
      if (identityChanged != 1) {
        throw const ApprovedOnboardingActivationException(
          'ORGANIZATION_BINDING_CONFLICT',
        );
      }
      final deleted = await txn.delete(
        'organizations',
        where: 'id = ?',
        whereArgs: [currentOrganizationId],
      );
      if (deleted != 1) {
        throw const ApprovedOnboardingActivationException(
          'PLACEHOLDER_ORGANIZATION_NOT_REMOVED',
        );
      }
    });

    await OrganizationIdentityTables.validate(db);
    await OwnerBootstrapTables.validate(db);
    return status;
  }

  Future<void> _assertFreshPreActivation(
    DatabaseExecutor db,
    String organizationId,
  ) async {
    final users = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM users',
        )) ??
        0;
    final devices = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM installation_identity',
        )) ??
        0;
    final receipts = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM license_activation_state',
        )) ??
        0;
    final workshops = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM workshop_settings',
        )) ??
        0;
    if (users != 0 || devices != 0 || receipts != 0 || workshops != 0) {
      throw const ApprovedOnboardingActivationException(
        'LOCAL_WORKSHOP_ALREADY_OPERATIONAL',
      );
    }

    final bootstrap = await db.query(
      'owner_bootstrap_state',
      where: 'singleton_id = 1 AND organization_id = ?',
      whereArgs: [organizationId],
      limit: 2,
    );
    if (bootstrap.length != 1 || bootstrap.single['status'] != 'PENDING') {
      throw const ApprovedOnboardingActivationException(
        'OWNER_BOOTSTRAP_NOT_PENDING',
      );
    }
  }

  Future<void> _assertNoBusinessScopeReferences(
    DatabaseExecutor db,
    String organizationId,
    String canonicalOrganizationId,
  ) async {
    final registry = await db.query(
      'sync_entity_registry',
      where: 'organization_id = ?',
      whereArgs: [organizationId],
    );
    if (registry.any((row) => (row['revision'] as num?)?.toInt() != 0)) {
      throw const ApprovedOnboardingActivationException(
        'SYNC_REGISTRY_ALREADY_ACTIVE',
      );
    }

    final historical = await db.query(
      'sync_change_log',
      where: 'organization_id = ?',
      whereArgs: [organizationId],
    );
    final invalidHistory = historical.any((row) =>
        row['origin'] != 'baseline' ||
        row['operation'] != 'created' ||
        row['attribution_state'] != 'historical' ||
        (row['revision'] as num?)?.toInt() != 0);
    if (invalidHistory) {
      throw const ApprovedOnboardingActivationException(
        'SYNC_HISTORY_ALREADY_ACTIVE',
      );
    }

    final linkedBaseline = Sqflite.firstIntValue(await db.rawQuery(
          '''SELECT COUNT(*) FROM sync_outbox_links l
             JOIN sync_change_log c ON c.change_id = l.change_id
             WHERE c.organization_id = ?''',
          [organizationId],
        )) ??
        0;
    if (linkedBaseline != 0) {
      throw const ApprovedOnboardingActivationException(
        'SYNC_BASELINE_ALREADY_QUEUED',
      );
    }

    final remoteCandidates = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM sync_remote_candidates WHERE organization_id = ?',
          [organizationId],
        )) ??
        0;
    if (remoteCandidates != 0) {
      throw const ApprovedOnboardingActivationException(
        'SYNC_REMOTE_STATE_PRESENT',
      );
    }

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    );
    const allowed = {
      'organization_identity',
      'owner_bootstrap_state',
      'sync_entity_registry',
      'sync_change_log',
    };
    for (final row in tables) {
      final name = row['name']?.toString() ?? '';
      if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name)) continue;
      final info = await db.rawQuery('PRAGMA table_info("$name")');
      if (!info.any((column) => column['name'] == 'organization_id')) continue;
      final count = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM "$name" WHERE organization_id = ?',
            [organizationId],
          )) ??
          0;
      if (count != 0 && !allowed.contains(name)) {
        throw ApprovedOnboardingActivationException(
          'LOCAL_SCOPE_NOT_EMPTY:$name',
        );
      }
    }

    if (registry.isNotEmpty) {
      await db.update(
        'sync_entity_registry',
        {'organization_id': canonicalOrganizationId},
        where: 'organization_id = ?',
        whereArgs: [organizationId],
      );
    }
  }

  static bool _looksLikeUuid(String value) => RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-'
        r'[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
      ).hasMatch(value);
}
