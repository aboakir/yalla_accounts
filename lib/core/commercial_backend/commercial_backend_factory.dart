import 'commercial_backend_client.dart';
import 'commercial_backend_environment.dart';
import 'commercial_backend_service.dart';

CommercialBackendService? createCommercialBackendService() {
  final baseUri = CommercialBackendEnvironment.baseUri;
  if (baseUri == null) return null;

  return CommercialBackendService(
    client: CommercialBackendClient(
      baseUri: baseUri,
      allowInsecureLoopbackForTesting:
          CommercialBackendEnvironment.allowInsecureLoopback,
    ),
  );
}
