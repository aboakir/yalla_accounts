import 'dart:convert';

class OutboxSyncEnvelope {
  const OutboxSyncEnvelope({
    required this.id,
    required this.channel,
    required this.operation,
    required this.entityType,
    required this.entityId,
    required this.idempotencyKey,
    required this.payload,
    required this.attemptCount,
  });

  final String id;
  final String channel;
  final String operation;
  final String entityType;
  final String entityId;
  final String idempotencyKey;
  final Map<String, dynamic> payload;
  final int attemptCount;

  factory OutboxSyncEnvelope.fromRow(Map<String, dynamic> row) {
    String requiredText(String key) {
      final value = row[key]?.toString().trim() ?? '';
      if (value.isEmpty) {
        throw FormatException('Outbox message is missing $key.');
      }
      return value;
    }

    final decoded = jsonDecode(requiredText('payload_json'));
    if (decoded is! Map) {
      throw const FormatException('Outbox payload must be a JSON object.');
    }

    return OutboxSyncEnvelope(
      id: requiredText('id'),
      channel: requiredText('channel'),
      operation: requiredText('operation'),
      entityType: requiredText('entity_type'),
      entityId: requiredText('entity_id'),
      idempotencyKey: requiredText('idempotency_key'),
      payload: Map<String, dynamic>.from(decoded),
      attemptCount: (row['attempt_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class OutboxSyncAck {
  const OutboxSyncAck({
    required this.idempotencyKey,
    this.accepted = true,
    this.remoteId,
  });

  final String idempotencyKey;
  final bool accepted;
  final String? remoteId;
}

/// Server/backend boundary for P04 basic sync.
///
/// The current Yalla source contains no authoritative workshop-sync endpoint,
/// so P04 does not invent one. A real backend adapter must implement this
/// contract and return an acknowledgement carrying the same idempotency key.
abstract interface class OutboxSyncTransport {
  Future<OutboxSyncAck> send(OutboxSyncEnvelope message);
}

class OutboxSyncProtocolException implements Exception {
  const OutboxSyncProtocolException(this.message);

  final String message;

  @override
  String toString() => 'OutboxSyncProtocolException: $message';
}
