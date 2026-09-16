import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/services/sync/sync_contract_v3.dart';

void main() {
  Map<String, dynamic> registry() {
    final raw = File('contracts/sync-v3.registry.json').readAsStringSync();
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  test('Phase 04 Accounts constants match the final v3 registry', () {
    final contract = registry();
    final transport = Map<String, dynamic>.from(contract['transport'] as Map);
    final limits = Map<String, dynamic>.from(contract['batch_limits'] as Map);
    final errors = Map<String, dynamic>.from(contract['error_codes'] as Map);

    expect(contract['sync_contract_version'], SyncContractV3.version);
    expect(transport['version_header'], SyncContractV3.versionHeader);
    expect(limits['push_max_changes'], SyncContractV3.pushMaxChanges);
    expect(limits['pull_max_changes'], SyncContractV3.pullMaxChanges);
    expect(errors, SyncContractV3.errorStatus);
    expect((contract['concurrency'] as Map)['last_write_wins'], isFalse);
    expect((contract['device_proof'] as Map)['required'], isTrue);
    expect((contract['device_proof'] as Map)['algorithm'],
        SyncContractV3.deviceProofAlgorithm);
    expect((contract['device_proof'] as Map)['canonicalization'],
        SyncContractV3.deviceProofCanonicalization);
    final tombstone = Map<String, dynamic>.from(contract['tombstone'] as Map);
    final restore = Map<String, dynamic>.from(tombstone['restore'] as Map);
    expect(tombstone['silent_resurrection'], 'REJECT');
    expect(restore['operation'], 'UPSERT');
    expect(restore['payload_marker'], SyncContractV3.tombstoneRestoreMarker);
    expect(restore['required_value'], isTrue);
  });
  test('Phase 04 bounds and checkpoints fail closed', () {
    expect(() => SyncContractV3.requirePushBatchSize(0), throwsRangeError);
    expect(() => SyncContractV3.requirePushBatchSize(51), throwsRangeError);
    expect(() => SyncContractV3.requirePullLimit(0), throwsRangeError);
    expect(() => SyncContractV3.requirePullLimit(201), throwsRangeError);
    expect(() => SyncContractV3.requireCheckpoint(-1), throwsRangeError);
    expect(() => SyncContractV3.requirePushBatchSize(50), returnsNormally);
    expect(() => SyncContractV3.requirePullLimit(200), returnsNormally);
    expect(() => SyncContractV3.requireCheckpoint(0), returnsNormally);
  });

  test('Phase 04 registry pins push pull conflict and compatibility rules', () {
    final contract = registry();
    expect(contract['push'], isA<Map>());
    expect(contract['pull'], isA<Map>());
    expect(contract['conflict'], isA<Map>());
    expect(contract['error'], isA<Map>());
    expect(
      (contract['compatibility'] as Map)['unknown_request_fields'],
      'REJECT',
    );
    expect((contract['compatibility'] as Map)['unsupported_version'], 'REJECT');
    expect(
      (contract['idempotency'] as Map)['same_key_different_payload'],
      'REJECT',
    );
    expect((contract['conflict'] as Map)['silent_overwrite'], isFalse);
    expect((contract['device_proof'] as Map)['signed_material'],
        'SHA256_CANONICAL_REQUEST_WITHOUT_DEVICE_PROOF');
  });
}
