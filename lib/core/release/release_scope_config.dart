/// Release-scope switches for the first mobile beta.
///
/// Deferred features remain in source and can be re-enabled in a later release
/// without deleting their routes, services, or data model.
class ReleaseScopeConfig {
  const ReleaseScopeConfig._();

  /// P3-01: Repair Reports screen stays enabled, export actions are deferred.
  static const bool repairReportExportsEnabled = false;

  /// P3-02/P3-03: direct employee advances/rewards UI is deferred.
  /// Employee advances continue through the canonical payment-voucher path.
  static const bool employeeAdvancesEnabled = false;

  /// P3-04: only the stable finance core is exposed in the first beta.
  static const bool extendedFinanceEnabled = false;

  /// P3-05: cheque management screens are deferred from release navigation.
  static const bool chequesEnabled = false;

  /// P3-06: dashboard is approved/frozen and must not be modified in Stage 3.
  static const bool dashboardFrozen = true;
}
