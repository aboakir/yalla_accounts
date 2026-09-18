/// Release-scope switches for the first mobile beta.
///
/// Deferred features remain in source and can be re-enabled in a later release
/// without deleting their routes, services, or data model.
class ReleaseScopeConfig {
  const ReleaseScopeConfig._();

  /// P3-01: Repair Reports screen stays enabled, export actions are deferred.
  static const bool repairReportExportsEnabled = false;

  /// Employee advances/rewards UI is enabled; accounting remains on the canonical voucher/GL path.
  static const bool employeeAdvancesEnabled = true;

  /// Extended finance screens are exposed in navigation.
  static const bool extendedFinanceEnabled = true;

  /// Cheque management screens are exposed in navigation.
  static const bool chequesEnabled = true;

  /// P3-06: dashboard is approved/frozen and must not be modified in Stage 3.
  static const bool dashboardFrozen = true;
}
