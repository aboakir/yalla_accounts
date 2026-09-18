import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tools/validate_production_defines.dart' as production_defines;

void main() {
  test(
      'Phase 11 production define template contains the complete public contract',
      () {
    final file = File('deploy/production_defines.example.json');
    expect(file.existsSync(), isTrue);
    final values = Map<String, Object?>.from(
      jsonDecode(file.readAsStringSync()) as Map,
    );
    for (final key in const [
      'YALLA_LICENSING_BASE_URL',
      'YALLA_LICENSE_TRUSTED_KEY_SHA256',
      'YALLA_SUPABASE_URL',
      'YALLA_SUPABASE_PUBLISHABLE_KEY',
      'YALLA_CLOUD_AUTH_RELEASE_READY',
      'YALLA_STORE_DISTRIBUTION',
    ]) {
      expect(values.containsKey(key), isTrue, reason: 'Missing $key');
    }
    final licensing = Uri.parse(values['YALLA_LICENSING_BASE_URL']! as String);
    expect(licensing.scheme, 'https');
    expect(licensing.host, isNotEmpty);
    expect(licensing.userInfo, isEmpty);
    expect(licensing.hasQuery, isFalse);
    expect(licensing.hasFragment, isFalse);
    expect(licensing.path.isEmpty || licensing.path == '/', isTrue);
    final serialized = jsonEncode(values).toLowerCase();
    expect(serialized, isNot(contains('service_role')));
    expect(serialized, isNot(contains('private key')));
    expect(serialized, isNot(contains('postgresql://')));
  });

  test(
      'Phase 11 every commercial transport uses the same licensing origin define',
      () {
    for (final path in const [
      'lib/core/licensing/activation/activation_transport.dart',
      'lib/core/licensing/lifecycle/license_lifecycle_transport.dart',
      'lib/core/services/sync/outbox_sync_transport.dart',
      'lib/features/onboarding/customer_onboarding_client.dart',
      'lib/features/auth/services/yalla_admin_auth_service.dart',
    ]) {
      expect(
          File(path).readAsStringSync(), contains('YALLA_LICENSING_BASE_URL'));
    }
  });

  test('Phase 11 real production define file is excluded from source control',
      () {
    final ignore = File('.gitignore').readAsStringSync();
    expect(ignore, contains('/deploy/production_defines.json'));
    final cloud = File(
      'lib/features/cloud_auth/cloud_auth_config.dart',
    ).readAsStringSync();
    expect(cloud, contains('YALLA_SUPABASE_PUBLISHABLE_KEY'));
    expect(cloud, isNot(contains('YALLA_SUPABASE_SERVICE_ROLE_KEY')));
  });

  test(
      'Phase 11 validator rejects placeholders and accepts a complete production contract',
      () {
    final example = Map<String, Object?>.from(
      jsonDecode(
              File('deploy/production_defines.example.json').readAsStringSync())
          as Map,
    );
    expect(
      () => production_defines.validateProductionDefines(example),
      throwsFormatException,
    );
    final valid = <String, Object?>{
      'YALLA_LICENSING_BASE_URL': 'https://control.yalla.invalid',
      'YALLA_LICENSE_TRUSTED_KEY_SHA256': 'a' * 64,
      'YALLA_SUPABASE_URL': 'https://project.supabase.co',
      'YALLA_SUPABASE_PUBLISHABLE_KEY': 'sb_publishable_12345678901234567890',
      'YALLA_CLOUD_AUTH_RELEASE_READY': true,
      'YALLA_CLOUD_OAUTH_ENABLED': false,
      'YALLA_STORE_DISTRIBUTION': false,
    };
    expect(
      () => production_defines.validateProductionDefines(valid),
      returnsNormally,
    );
  });
}
