import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';

void main() {
  test('tested policy routes are open while later insurance routes stay frozen',
      () {
    expect(AppRoutes.isInsuranceAgentFrozenRoute(AppRoutes.insuranceAgentHome),
        isFalse);
    expect(
        AppRoutes.isInsuranceAgentFrozenRoute(
            AppRoutes.insuranceAgentCalculator),
        isFalse);
    expect(
        AppRoutes.isInsuranceAgentFrozenRoute(AppRoutes.insuranceAgentContacts),
        isFalse);
    expect(
        AppRoutes.isInsuranceAgentFrozenRoute(AppRoutes.insurancePoliciesList),
        isFalse);
    expect(
        AppRoutes.isInsuranceAgentFrozenRoute(AppRoutes.insuranceAgentAddNew),
        isFalse);

    expect(
        AppRoutes.isInsuranceAgentFrozenRoute(AppRoutes.insuranceAgentFinance),
        isTrue);
    expect(
        AppRoutes.isInsuranceAgentFrozenRoute(AppRoutes.insuranceAgentAlerts),
        isTrue);
    expect(
        AppRoutes.isInsuranceAgentFrozenRoute(AppRoutes.insuranceAgentReports),
        isTrue);
    expect(
        AppRoutes.isInsuranceAgentFrozenRoute(
            AppRoutes.insuranceAgentProducers),
        isTrue);
  });
}
