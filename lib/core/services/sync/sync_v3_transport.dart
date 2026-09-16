import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../device_identity/device_identity.dart';
import '../../device_identity/device_identity_service.dart';
import '../../licensing/customer_bearer_token_provider.dart';
import 'sync_contract_v3.dart';

class SyncV3PushResult {
  const SyncV3PushResult(
      {required this.changeId,
      required this.idempotencyKey,
      required this.disposition,
      this.serverSequence,
      this.conflictId,
      this.errorCode});
  final String changeId;
  final String idempotencyKey;
  final String disposition;
  final int? serverSequence;
  final String? conflictId;
  final String? errorCode;
}

class SyncV3PullChange {
  const SyncV3PullChange(
      {required this.serverSequence,
      required this.changeId,
      required this.organizationId,
      required this.entityType,
      required this.entityId,
      required this.entityUuid,
      required this.operation,
      required this.revision,
      required this.occurredAt,
      required this.payload});
  final int serverSequence;
  final String changeId;
  final String organizationId;
  final String entityType;
  final String entityId;
  final String entityUuid;
  final String operation;
  final int revision;
  final DateTime occurredAt;
  final Map<String, Object?> payload;
}

class SyncV3PushResponse {
  const SyncV3PushResponse(this.results);
  final List<SyncV3PushResult> results;
}

class SyncV3PullResponse {
  const SyncV3PullResponse(
      {required this.fromSequence,
      required this.nextSequence,
      required this.hasMore,
      required this.changes});
  final int fromSequence;
  final int nextSequence;
  final bool hasMore;
  final List<SyncV3PullChange> changes;
}

abstract interface class SyncV3Transport {
  bool get isConfigured;
  Future<SyncV3PushResponse> push(List<Map<String, Object?>> rows);
  Future<SyncV3PullResponse> pull(
      {required int afterServerSequence, int limit});
}

class SyncV3TransportException implements Exception {
  const SyncV3TransportException(this.message, {this.statusCode, this.code});
  final String message;
  final int? statusCode;
  final String? code;
  @override
  String toString() => 'SyncV3TransportException: $message';
}

class HttpSyncV3Transport implements SyncV3Transport {
  HttpSyncV3Transport(
      {Uri? baseUri,
      HttpClient? httpClient,
      required this.bearerTokenProvider,
      DeviceIdentityService? deviceIdentityService,
      this.timeout = const Duration(seconds: 20),
      this.allowInsecureLoopbackForTesting = false})
      : _baseUri = baseUri ?? _environmentBaseUri(),
        _httpClient = httpClient ?? HttpClient(),
        _deviceIdentity = deviceIdentityService ?? DeviceIdentityService();

  final Uri? _baseUri;
  final HttpClient _httpClient;
  final CustomerBearerTokenProvider bearerTokenProvider;
  final DeviceIdentityService _deviceIdentity;
  final Duration timeout;
  final bool allowInsecureLoopbackForTesting;
  static const _uuid = Uuid();

  @override
  bool get isConfigured => _baseUri != null;

  static Uri? _environmentBaseUri() {
    const configured = String.fromEnvironment('YALLA_LICENSING_BASE_URL');
    final raw = configured.trim();
    return raw.isEmpty ? null : Uri.tryParse(raw);
  }

  @override
  Future<SyncV3PushResponse> push(List<Map<String, Object?>> rows) async {
    SyncContractV3.requirePushBatchSize(rows.length);
    final identity = await _deviceIdentity.ensureCurrent();
    final changes = rows
        .map((row) => _changeFromOutbox(row, identity))
        .toList(growable: false);
    final body = await _signedBody(identity, <String, Object?>{
      'sync_contract_version': SyncContractV3.version,
      'request_id': _uuid.v4(),
      'organization_id': identity.organizationId,
      'installation_id': identity.installationId,
      'device_id': identity.deviceId,
      'changes': changes,
    });
    final response = await _post('/v1/sync/push', body, identity);
    final raw = response['results'];
    if (raw is! List) {
      throw const SyncV3TransportException('Sync push results are invalid.');
    }
    return SyncV3PushResponse(raw.map((item) {
      if (item is! Map) {
        throw const SyncV3TransportException('Sync push result is invalid.');
      }
      final map = Map<String, Object?>.from(item);
      final conflict = map['conflict'];
      return SyncV3PushResult(
        changeId: _requiredString(map, 'change_id'),
        idempotencyKey: _requiredString(map, 'idempotency_key'),
        disposition: _requiredString(map, 'disposition'),
        serverSequence: (map['server_sequence'] as num?)?.toInt(),
        conflictId:
            conflict is Map ? conflict['conflict_id']?.toString() : null,
        errorCode: map['error_code']?.toString(),
      );
    }).toList(growable: false));
  }

  @override
  Future<SyncV3PullResponse> pull(
      {required int afterServerSequence,
      int limit = SyncContractV3.pullMaxChanges}) async {
    SyncContractV3.requireCheckpoint(afterServerSequence);
    SyncContractV3.requirePullLimit(limit);
    final identity = await _deviceIdentity.ensureCurrent();
    final body = await _signedBody(identity, <String, Object?>{
      'sync_contract_version': SyncContractV3.version,
      'request_id': _uuid.v4(),
      'organization_id': identity.organizationId,
      'installation_id': identity.installationId,
      'device_id': identity.deviceId,
      'after_server_sequence': afterServerSequence,
      'limit': limit,
    });
    final response = await _post('/v1/sync/pull', body, identity);
    final raw = response['changes'];
    if (raw is! List) {
      throw const SyncV3TransportException('Sync pull changes are invalid.');
    }
    final changes = raw.map((item) {
      if (item is! Map) {
        throw const SyncV3TransportException('Sync pull change is invalid.');
      }
      final map = Map<String, Object?>.from(item);
      final payload = map['payload'];
      if (payload is! Map) {
        throw const SyncV3TransportException('Sync pull payload is invalid.');
      }
      return SyncV3PullChange(
        serverSequence: (map['server_sequence'] as num).toInt(),
        changeId: _requiredString(map, 'change_id'),
        organizationId: _requiredString(map, 'organization_id'),
        entityType: _requiredString(map, 'entity_type'),
        entityId: _requiredString(map, 'entity_id'),
        entityUuid: _requiredString(map, 'entity_uuid'),
        operation: _requiredString(map, 'operation'),
        revision: (map['revision'] as num).toInt(),
        occurredAt: DateTime.parse(_requiredString(map, 'occurred_at')).toUtc(),
        payload: Map<String, Object?>.from(payload),
      );
    }).toList(growable: false);
    return SyncV3PullResponse(
      fromSequence: (response['from_server_sequence'] as num).toInt(),
      nextSequence: (response['next_server_sequence'] as num).toInt(),
      hasMore: response['has_more'] == true,
      changes: changes,
    );
  }

  Map<String, Object?> _changeFromOutbox(
      Map<String, Object?> row, DeviceIdentity identity) {
    final organizationId = row['organization_id']?.toString() ?? '';
    if (organizationId != identity.organizationId) {
      throw const SyncV3TransportException(
          'Outbox organization does not match this device.');
    }
    final decoded = jsonDecode(row['payload_json']!.toString());
    if (decoded is! Map) {
      throw const SyncV3TransportException('Outbox payload must be an object.');
    }
    final payload = Map<String, Object?>.from(decoded);
    return <String, Object?>{
      'change_id': row['change_id']!.toString(),
      'organization_id': organizationId,
      'entity_type': row['entity_type']!.toString(),
      'entity_id': row['entity_id']!.toString(),
      'entity_uuid': row['entity_uuid']!.toString(),
      'operation': row['operation']!.toString(),
      'base_revision': (row['base_revision'] as num).toInt(),
      'revision': (row['revision'] as num).toInt(),
      'idempotency_key': row['idempotency_key']!.toString(),
      'occurred_at': row['occurred_at']!.toString(),
      'payload': payload,
      'payload_sha256':
          sha256.convert(utf8.encode(_canonical(payload))).toString(),
    };
  }

  Future<Map<String, Object?>> _signedBody(
      DeviceIdentity identity, Map<String, Object?> unsigned) async {
    final digest = sha256.convert(utf8.encode(_canonical(unsigned))).bytes;
    final proof = await _deviceIdentity.signChallenge(digest);
    if (proof.deviceId != identity.deviceId ||
        proof.algorithm != SyncContractV3.deviceProofAlgorithm) {
      throw const SyncV3TransportException('Device proof identity mismatch.');
    }
    return <String, Object?>{
      ...unsigned,
      'device_proof': <String, Object?>{
        'algorithm': proof.algorithm,
        'body_sha256':
            sha256.convert(utf8.encode(_canonical(unsigned))).toString(),
        'signature': proof.signatureBase64Url,
      },
    };
  }

  Future<Map<String, Object?>> _post(
      String path, Map<String, Object?> body, DeviceIdentity identity) async {
    final base = _baseUri;
    if (base == null) {
      throw const SyncV3TransportException(
          'Yalla sync server is not configured.');
    }
    final loopback = base.host == '127.0.0.1' ||
        base.host == 'localhost' ||
        base.host == '::1';
    if (!(base.scheme == 'https' && base.host.isNotEmpty) &&
        !(allowInsecureLoopbackForTesting &&
            base.scheme == 'http' &&
            loopback)) {
      throw const SyncV3TransportException('Sync server URL must use HTTPS.');
    }
    final token = (await bearerTokenProvider())?.trim() ?? '';
    if (token.isEmpty) {
      throw const SyncV3TransportException(
          'Authenticated customer session is required.');
    }
    try {
      final request =
          await _httpClient.postUrl(base.resolve(path)).timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers
          .set(SyncContractV3.versionHeader, '${SyncContractV3.version}');
      request.headers.set('x-yalla-installation-id', identity.installationId);
      request.write(jsonEncode(body));
      final response = await request.close().timeout(timeout);
      final raw = await utf8.decoder.bind(response).join().timeout(timeout);
      Object? decoded;
      try {
        decoded = raw.isEmpty ? <String, Object?>{} : jsonDecode(raw);
      } catch (_) {
        throw SyncV3TransportException('Sync server returned invalid JSON.',
            statusCode: response.statusCode);
      }
      if (decoded is! Map) {
        throw SyncV3TransportException('Sync server returned invalid response.',
            statusCode: response.statusCode);
      }
      final map = Map<String, Object?>.from(decoded);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SyncV3TransportException(
            map['message']?.toString() ?? 'Sync request rejected.',
            statusCode: response.statusCode,
            code: map['code']?.toString());
      }
      if (map['sync_contract_version'] != SyncContractV3.version) {
        throw SyncV3TransportException(
            'Sync response contract version mismatch.',
            statusCode: response.statusCode);
      }
      return map;
    } on SyncV3TransportException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } on SocketException {
      rethrow;
    } on HandshakeException catch (error) {
      throw SocketException('Secure sync connection failed: $error');
    }
  }

  static String _canonical(Object? value) {
    Object? normalize(Object? input) {
      if (input is Map) {
        final keys = input.keys.map((e) => e.toString()).toList()..sort();
        return <String, Object?>{
          for (final key in keys) key: normalize(input[key])
        };
      }
      if (input is List) return input.map(normalize).toList(growable: false);
      return input;
    }

    return jsonEncode(normalize(value));
  }

  static String _requiredString(Map<String, Object?> map, String key) {
    final value = map[key]?.toString().trim() ?? '';
    if (value.isEmpty) {
      throw SyncV3TransportException('Missing server field: $key.');
    }
    return value;
  }
}
