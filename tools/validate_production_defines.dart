import 'dart:convert';
import 'dart:io';

FormatException _invalid(String message) => FormatException(message);

Uri _httpsUri(Object? raw, String name, {bool originOnly = false}) {
  if (raw is! String || raw.trim().isEmpty) {
    throw _invalid('$name is required');
  }
  final uri = Uri.tryParse(raw.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    throw _invalid('$name must be a safe HTTPS URI');
  }
  if (originOnly &&
      (uri.hasQuery || (uri.path.isNotEmpty && uri.path != '/'))) {
    throw _invalid('$name must be an HTTPS origin only');
  }
  return uri;
}

void validateProductionDefines(Map<String, Object?> data) {
  const required = <String>{
    'YALLA_LICENSING_BASE_URL',
    'YALLA_LICENSE_TRUSTED_KEY_SHA256',
    'YALLA_SUPABASE_URL',
    'YALLA_SUPABASE_PUBLISHABLE_KEY',
    'YALLA_CLOUD_AUTH_RELEASE_READY',
    'YALLA_CLOUD_OAUTH_ENABLED',
    'YALLA_STORE_DISTRIBUTION',
  };
  final missing = required.difference(data.keys.toSet());
  if (missing.isNotEmpty) {
    throw _invalid('missing ${missing.join(', ')}');
  }

  _httpsUri(
    data['YALLA_LICENSING_BASE_URL'],
    'YALLA_LICENSING_BASE_URL',
    originOnly: true,
  );
  _httpsUri(
    data['YALLA_SUPABASE_URL'],
    'YALLA_SUPABASE_URL',
    originOnly: true,
  );
  final hashes = data['YALLA_LICENSE_TRUSTED_KEY_SHA256'];
  if (hashes is! String ||
      hashes
          .split(',')
          .map((value) => value.trim())
          .any((value) => !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value))) {
    throw _invalid('YALLA_LICENSE_TRUSTED_KEY_SHA256 must contain 64-hex pins');
  }

  final publicKey = data['YALLA_SUPABASE_PUBLISHABLE_KEY'];
  if (publicKey is! String ||
      !publicKey.startsWith('sb_publishable_') ||
      publicKey.length <= 20) {
    throw _invalid('Supabase publishable key is invalid');
  }

  for (final name in const <String>[
    'YALLA_CLOUD_AUTH_RELEASE_READY',
    'YALLA_CLOUD_OAUTH_ENABLED',
    'YALLA_STORE_DISTRIBUTION',
  ]) {
    if (data[name] is! bool) {
      throw _invalid('$name must be boolean');
    }
  }
  if (data['YALLA_CLOUD_AUTH_RELEASE_READY'] != true) {
    throw _invalid('cloud auth must be release-ready');
  }
  final encoded = jsonEncode(data);
  if (encoded.contains('REPLACE_') ||
      encoded.contains('project-ref') ||
      encoded.contains('example.com') ||
      encoded.contains('service_role') ||
      encoded.contains('BEGIN PRIVATE KEY') ||
      encoded.contains('postgres://') ||
      encoded.contains('postgresql://')) {
    throw _invalid('placeholder or secret material detected');
  }
}

Never _fail(String message) {
  stderr.writeln('Production defines validation: FAIL ($message)');
  exit(2);
}

void main(List<String> args) {
  if (args.length != 1) {
    _fail('usage: dart tools/validate_production_defines.dart <json>');
  }
  final file = File(args.single);
  if (!file.existsSync()) _fail('file not found');
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, dynamic>) _fail('root must be an object');
    validateProductionDefines(Map<String, Object?>.from(decoded));
    stdout.writeln('Production defines validation: PASS');
  } on FormatException catch (error) {
    _fail(error.message);
  } catch (_) {
    _fail('invalid JSON');
  }
}
