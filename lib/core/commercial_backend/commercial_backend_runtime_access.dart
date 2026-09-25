import 'commercial_backend_models.dart';
import 'commercial_offline_lease.dart';

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

class CommercialBackendEntitlementBlocked implements Exception {
  const CommercialBackendEntitlementBlocked(
    this.feature,
    this.status, {
    this.limitCode,
  });
  final String feature;
  final String status;
  final String? limitCode;

  String get userMessage => switch (status) {
        'LIMIT_REACHED' => 'تم الوصول إلى حد الحزمة الحالية.',
        'READ_ONLY' => 'هذه الميزة متاحة للعرض فقط حاليًا.',
        'BLOCKED' => 'الحساب أو الاشتراك موقوف.',
        _ => 'هذه الميزة غير متاحة في الحزمة الحالية.',
      };

  @override
  String toString() =>
      'CommercialBackendEntitlementBlocked($feature, $status, $limitCode)';
}

class CommercialBackendRuntimeAccess {
  CommercialBackendRuntimeAccess._();

  static CommercialBackendRuntimeMode _mode =
      CommercialBackendRuntimeMode.unknown;
  static String? _organizationId;
  static String? _subscriptionId;
  static String? _planCode;
  static int _revision = 0;
  static Map<String, CommercialFeatureEntitlement> _features = const {};
  static Map<String, CommercialLimitEntitlement> _limits = const {};

  static CommercialBackendRuntimeMode get mode => _mode;
  static bool get canWrite => _mode == CommercialBackendRuntimeMode.full;
  static bool get canRead =>
      _mode == CommercialBackendRuntimeMode.full ||
      _mode == CommercialBackendRuntimeMode.readOnly;
  static String? get organizationId => _organizationId;
  static String? get subscriptionId => _subscriptionId;
  static String? get planCode => _planCode;
  static int get entitlementRevision => _revision;
  static int get maxUsers => _limits['MAX_USERS']?.value ?? 0;
  static int get maxDevices => _limits['MAX_DEVICES']?.value ?? 0;
  static Map<String, CommercialFeatureEntitlement> get features =>
      Map.unmodifiable(_features);
  static Map<String, CommercialLimitEntitlement> get limits =>
      Map.unmodifiable(_limits);

  static void applyAccessMode(String accessMode) {
    _mode = _parseMode(accessMode);
  }

  static void applyLicense(LicenseCheckResult result) {
    _mode = _parseMode(result.accessMode);
    _organizationId = result.organizationId;
    _subscriptionId = result.subscriptionId;
    _planCode = result.planCode;
    _revision = result.entitlementRevision;
    _features = Map.unmodifiable(result.features);
    _limits = Map.unmodifiable(result.limits);
  }

  static void applyOfflineLease(CommercialOfflineLease lease) {
    _mode = _parseMode(lease.accessMode);
    _organizationId = lease.organizationId;
    _subscriptionId = lease.subscriptionId;
    _planCode = lease.planCode;
    _revision = lease.entitlementRevision;
    _features = Map.unmodifiable(lease.features);
    _limits = Map.unmodifiable(lease.limits);
  }

  static CommercialBackendRuntimeMode _parseMode(String accessMode) {
    return switch (accessMode.trim().toUpperCase()) {
      'FULL' => CommercialBackendRuntimeMode.full,
      'READ_ONLY' => CommercialBackendRuntimeMode.readOnly,
      'BLOCKED' => CommercialBackendRuntimeMode.blocked,
      _ => CommercialBackendRuntimeMode.unknown,
    };
  }

  static void reset() {
    _mode = CommercialBackendRuntimeMode.unknown;
    _organizationId = null;
    _subscriptionId = null;
    _planCode = null;
    _revision = 0;
    _features = const {};
    _limits = const {};
  }

  static void requireWrite(String operation) {
    if (!canWrite) {
      throw CommercialBackendWriteBlocked(_mode, operation);
    }
  }

  static bool canReadFeature(String feature) {
    if (!canRead) return false;
    final state = _features[feature]?.state;
    return state == 'ENABLED' || state == 'READ_ONLY';
  }

  static void requireFeature(
    String feature, {
    String? limitCode,
    int delta = 0,
  }) {
    if (_mode == CommercialBackendRuntimeMode.blocked ||
        _mode == CommercialBackendRuntimeMode.unknown) {
      throw CommercialBackendEntitlementBlocked(feature, 'BLOCKED');
    }
    final entitlement = _features[feature];
    if (entitlement == null || entitlement.locked) {
      throw CommercialBackendEntitlementBlocked(feature, 'PLAN_REQUIRED');
    }
    if (_mode == CommercialBackendRuntimeMode.readOnly ||
        entitlement.readOnly) {
      throw CommercialBackendEntitlementBlocked(feature, 'READ_ONLY');
    }
    if (limitCode != null) {
      final limit = _limits[limitCode];
      if (limit != null &&
          !limit.unlimited &&
          (limit.used + delta) > limit.value) {
        throw CommercialBackendEntitlementBlocked(
          feature,
          'LIMIT_REACHED',
          limitCode: limitCode,
        );
      }
    }
  }
}
