import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_client.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_service.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_offline_lease.dart';
import 'package:yalla_accounts/features/commercial_registration/commercial_first_run_screen.dart';
import 'package:yalla_accounts/features/startup/startup_screen.dart';

void main() {
  test('commercial startup integration compiles', () {
    expect(CommercialBackendClient, isNotNull);
    expect(CommercialBackendService, isNotNull);
    expect(CommercialOfflineLease, isNotNull);
    expect(CommercialFirstRunScreen, isNotNull);
    expect(StartupScreen, isNotNull);
  });
}
