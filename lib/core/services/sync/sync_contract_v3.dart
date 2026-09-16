class SyncContractV3 {
  SyncContractV3._();

  static const int version = 3;
  static const String versionHeader = 'x-yalla-sync-contract-version';
  static const int pushMaxChanges = 50;
  static const int pullMaxChanges = 200;
  static const int changePayloadMaxBytes = 524288;
  static const int requestMaxBytes = 2097152;
  static const String deviceProofAlgorithm = 'ED25519';
  static const String deviceProofCanonicalization = 'SORTED_JSON_UTF8_V1';
  static const String tombstoneRestoreMarker = '_sync_restore';

  static const Set<String> outboxStates = {
    'PENDING',
    'SENDING',
    'ACKNOWLEDGED',
    'CONFLICT',
    'REJECTED',
  };

  static const Map<String, int> errorStatus = {
    'SYNC_CONTRACT_VERSION_UNSUPPORTED': 400,
    'SYNC_BATCH_TOO_LARGE': 413,
    'SYNC_CHANGE_INVALID': 400,
    'SYNC_IDEMPOTENCY_CONFLICT': 409,
    'SYNC_REVISION_CONFLICT': 409,
    'SYNC_TOMBSTONE_CONFLICT': 409,
    'SYNC_CHECKPOINT_INVALID': 400,
    'SYNC_DEVICE_DENIED': 403,
    'SYNC_DEVICE_PROOF_INVALID': 403,
    'SYNC_REPLAY_DETECTED': 409,
    'SYNC_ORGANIZATION_DENIED': 403,
    'SYNC_ENTITY_TYPE_DENIED': 400,
    'SYNC_SERVER_BUSY': 503,
  };

  static bool supportsVersion(Object? value) => value == version;

  static void requirePushBatchSize(int length) {
    if (length < 1 || length > pushMaxChanges) {
      throw RangeError.range(length, 1, pushMaxChanges, 'length');
    }
  }

  static void requirePullLimit(int limit) {
    if (limit < 1 || limit > pullMaxChanges) {
      throw RangeError.range(limit, 1, pullMaxChanges, 'limit');
    }
  }

  static void requireCheckpoint(int sequence) {
    if (sequence < 0) {
      throw RangeError.value(sequence, 'sequence', 'Must be non-negative.');
    }
  }
}
