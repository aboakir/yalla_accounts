import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/cloud_auth/cloud_auth_service.dart';
import 'activation/activation_service.dart';
import 'activation/activation_transport.dart';
import 'customer_bearer_token_provider.dart';
import 'lifecycle/license_lifecycle_service.dart';
import 'lifecycle/license_lifecycle_transport.dart';
import 'validation/periodic_license_validation_service.dart';

final customerBearerTokenProvider = Provider<CustomerBearerTokenProvider>(
    (ref) => ref.watch(supabaseIdentityProvider).verifiedAccessToken);
final activationTransportProvider = Provider<ActivationTransport>((ref) {
  final client = HttpClient();
  ref.onDispose(() => client.close(force: true));
  return HttpActivationTransport(
      httpClient: client,
      bearerTokenProvider: ref.watch(customerBearerTokenProvider));
});
final licenseLifecycleTransportProvider =
    Provider<LicenseLifecycleTransport>((ref) {
  final client = HttpClient();
  ref.onDispose(() => client.close(force: true));
  return HttpLicenseLifecycleTransport(
      httpClient: client,
      bearerTokenProvider: ref.watch(customerBearerTokenProvider));
});
final activationServiceProvider = Provider((ref) =>
    ActivationService(transport: ref.watch(activationTransportProvider)));
final licenseLifecycleServiceProvider = Provider((ref) =>
    LicenseLifecycleService(
        transport: ref.watch(licenseLifecycleTransportProvider)));
final periodicLicenseValidationServiceProvider = Provider((ref) =>
    PeriodicLicenseValidationService(
        lifecycleService: ref.watch(licenseLifecycleServiceProvider)));
final commercialValidationSchedulerProvider = Provider<void>((ref) {
  final service = ref.watch(periodicLicenseValidationServiceProvider);
  var active = true;
  Future<void> evaluate(String reason) async {
    if (!active) return;
    try {
      await service.evaluate(reason: reason);
    } catch (_) {
      // Existing signed offline deadlines remain authoritative on failure.
    }
  }

  unawaited(Future<void>(() => evaluate('STARTUP')));
  final timer = Timer.periodic(
      const Duration(hours: 1), (_) => unawaited(evaluate('HOURLY_RUNTIME')));
  ref.onDispose(() {
    active = false;
    timer.cancel();
  });
});
