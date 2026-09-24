enum CommercialBackendRuntimeMode {
  unknown,
  full,
  readOnly,
  blocked,
}

class CommercialBackendWriteBlocked implements Exception {
  const CommercialBackendWriteBlocked(this.mode, this.operation);

  final CommercialBackendRuntimeMode mode;
  final String operation;

  @override
  String toString() => 'CommercialBackendWriteBlocked($mode): $operation';
}

class CommercialBackendRuntimeAccess {
  CommercialBackendRuntimeAccess._();

  static CommercialBackendRuntimeMode _mode =
      CommercialBackendRuntimeMode.unknown;

  static CommercialBackendRuntimeMode get mode => _mode;

  static bool get canWrite => _mode == CommercialBackendRuntimeMode.full;
  static bool get canRead =>
      _mode == CommercialBackendRuntimeMode.full ||
      _mode == CommercialBackendRuntimeMode.readOnly;

  static void applyAccessMode(String accessMode) {
    _mode = switch (accessMode.trim().toUpperCase()) {
      'FULL' => CommercialBackendRuntimeMode.full,
      'READ_ONLY' => CommercialBackendRuntimeMode.readOnly,
      'BLOCKED' => CommercialBackendRuntimeMode.blocked,
      _ => CommercialBackendRuntimeMode.unknown,
    };
  }

  static void reset() {
    _mode = CommercialBackendRuntimeMode.unknown;
  }

  static void requireWrite(String operation) {
    if (!canWrite) {
      throw CommercialBackendWriteBlocked(_mode, operation);
    }
  }
}
