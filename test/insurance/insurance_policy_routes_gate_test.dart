import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';

void main() {
  test('all validated insurance routes are registered and open', () {
    final routes = [
      AppRoutes.insuranceAgentHome,
      AppRoutes.insuranceAgentCalculator,
      AppRoutes.insuranceAgentContacts,
      AppRoutes.insurancePoliciesList,
      AppRoutes.insuranceAgentAddNew,
      AppRoutes.insuranceAgentFinance,
      AppRoutes.insuranceAgentAlerts,
      AppRoutes.insuranceAgentReports,
      AppRoutes.insuranceAgentProducers,
      AppRoutes.insuranceAgentClaims,
      AppRoutes.insuranceAgentProducts,
    ];

    for (final route in routes) {
      expect(AppRoutes.isRegisteredRoute(route), isTrue, reason: route);
      expect(AppRoutes.isInsuranceAgentFrozenRoute(route), isFalse,
          reason: route);
    }
  });
}
