/// Release-scope switches for the first mobile beta.
///
/// Deferred features remain in source and can be re-enabled in a later release
/// without deleting their routes, services, or data model.
class ReleaseScopeConfig {
  const ReleaseScopeConfig._();

  /// P3-01: Repair Reports screen stays enabled, export actions are deferred.
  static const bool repairReportExportsEnabled = true;

  /// Employee advances/rewards UI is enabled; accounting remains on the canonical voucher/GL path.
  static const bool employeeAdvancesEnabled = true;

  /// Extended finance screens are exposed in navigation.
  static const bool extendedFinanceEnabled = true;

  /// Cheque management screens are exposed in navigation.
  static const bool chequesEnabled = true;

  /// Trial/pilot commercial builds keep the insurance UI hidden by default.
  /// Internal engineering builds may explicitly enable it for architecture tests.
  static const bool insurancePilotVisible = bool.fromEnvironment(
    'YALLA_INSURANCE_PILOT_VISIBLE',
    defaultValue: false,
  );

  /// The dashboard is active work in the commercial RC and is not frozen.
  static const bool dashboardFrozen = false;
}
