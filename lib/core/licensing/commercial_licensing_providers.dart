import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/cloud_auth/cloud_auth_service.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_environment.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_secure_store.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_factory.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_runtime_access.dart';
import 'activation/activation_service.dart';
import 'activation/activation_transport.dart';
import 'customer_bearer_token_provider.dart';
import 'lifecycle/license_lifecycle_service.dart';
import 'lifecycle/license_lifecycle_transport.dart';
import 'validation/periodic_license_validation_service.dart';
import '../services/sync/unified_sync_coordinator_v3.dart';
import '../services/sync/unified_sync_inbound_router.dart';
import '../services/sync/sync_v3_transport.dart';

final customerBearerTokenProvider =
    Provider<CustomerBearerTokenProvider>((ref) {
  if (CommercialBackendEnvironment.enabled) {
    final store = CommercialBackendSecureStore();
    return () async => (await store.read()).deviceToken;
  }
  return ref.watch(supabaseIdentityProvider).verifiedAccessToken;
});
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
final secureSyncTransportProvider = Provider<SyncV3Transport?>((ref) {
  final client = HttpClient();
  ref.onDispose(() => client.close(force: true));
  final phpBackend = CommercialBackendEnvironment.enabled;
  final transport = HttpSyncV3Transport(
    baseUri: phpBackend ? CommercialBackendEnvironment.baseUri : null,
    httpClient: client,
    bearerTokenProvider: ref.watch(customerBearerTokenProvider),
    allowInsecureLoopbackForTesting:
        phpBackend && CommercialBackendEnvironment.allowInsecureLoopback,
    phpCommercialBackend: phpBackend,
  );
  return transport.isConfigured ? transport : null;
});

final commercialSyncSchedulerProvider = Provider<void>((ref) {
  final transport = ref.watch(secureSyncTransportProvider);
  UnifiedSyncCoordinatorV3.instance.configureInboundApplier(
    UnifiedSyncInboundRouter.apply,
  );
  if (transport == null) {
    UnifiedSyncCoordinatorV3.instance.clearTransport();
  } else {
    UnifiedSyncCoordinatorV3.instance.configureTransport(transport);
  }
  ref.onDispose(() {
    UnifiedSyncCoordinatorV3.instance.clearTransport();
    UnifiedSyncCoordinatorV3.instance.clearInboundApplier();
  });
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
  var active = true;
  Future<void> evaluate(String reason) async {
    if (!active) return;
    try {
      if (CommercialBackendEnvironment.enabled) {
        final service = createCommercialBackendService();
        final license = await service?.checkCurrentLicense();
        if (license != null) {
          CommercialBackendRuntimeAccess.applyAccessMode(license.accessMode);
        }
        return;
      }
      final service = ref.read(periodicLicenseValidationServiceProvider);
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
