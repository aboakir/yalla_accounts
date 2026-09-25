import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('Phase 12 release matrix pins the current compatibility train', () {
    final matrix =
        jsonDecode(read('release/version_matrix.json')) as Map<String, dynamic>;
    final pubspec = read('pubspec.yaml');
    final db = read('lib/core/services/db/database_constants.dart');
    final sync = read('lib/core/services/sync/sync_contract_v3.dart');
    final activation =
        read('lib/core/licensing/activation/activation_transport.dart');

    expect(matrix['matrix_schema'], 1);
    expect(matrix['release_train'], 'UNIFIED-20260920');
    expect(pubspec, contains('version: ${matrix['accounts_version']}'));
    expect(db, contains('dbVersion = ${matrix['accounts_db_schema_version']}'));
    expect(
        sync,
        contains(
            'static const int version = ${matrix['sync_contract_version']}'));
    expect(
        activation,
        contains(
            "'contract_version': ${matrix['commercial_contract_version']}"));
  });
  test('Phase 12 active CI is pinned and contains no test tunnel authority',
      () {
    final files = [
      '.github/workflows/yalla_accounts_ci.yml',
      '.github/workflows/yalla_accounts_release_candidate.yml',
      '.github/workflows/yalla_unsigned_ios.yml',
      'codemagic.yaml',
    ];
    final source = files.map(read).join('\n');
    expect(source, contains("FLUTTER_VERSION: '3.44.8'"));
    expect(source, isNot(contains('lhr.life')));
    expect(source, isNot(contains('trycloudflare')));
    expect(source, isNot(contains('127.0.0.1')));
    expect(source, isNot(contains('localhost')));
    expect(RegExp(r'(?<!\$\{\{ secrets\.)\b[0-9a-f]{64}\b').hasMatch(source),
        isFalse);
  });

  test('Phase 12 CI gates tests, signing, artifacts and provenance', () {
    final ci = read('.github/workflows/yalla_accounts_ci.yml');
    final rc = read('.github/workflows/yalla_accounts_release_candidate.yml');
    final manifest = read('tools/release/write_artifact_manifest.mjs');

    expect(ci, contains('flutter test --no-pub --concurrency=1'));
    expect(ci, contains('test/accounting'));
    expect(ci, contains('test/sync'));
    expect(ci, contains('flutter build windows --release'));
    expect(rc, contains('YALLA_ANDROID_KEYSTORE_B64'));
    expect(rc, contains('flutter build apk --release'));
    expect(rc, contains('flutter build appbundle --release'));
    expect(rc, contains('flutter build windows --release'));
    expect(rc, contains('flutter build web --release'));
    expect(rc, contains('Yallah_Accounts_Web.zip'));
    expect(rc, contains('deploy\\production_public_config.json'));
    final publicConfig = jsonDecode(
      read('deploy/production_public_config.json'),
    ) as Map<String, dynamic>;
    expect(
      publicConfig['YALLAH_COMMERCIAL_BACKEND_URL'],
      'https://api.yallah.ps',
    );
    expect(
      publicConfig['YALLA_LICENSING_BASE_URL'],
      'https://api.yallah.ps',
    );
    expect(
        rc, contains('--dart-define-from-file=deploy/production_defines.json'));
    expect(manifest, contains('source_commit'));
    expect(manifest, contains('matrix_sha256'));
    expect(manifest, contains('sha256'));
  });
  test('Phase 12 iOS verification is explicit and source is not mutated in CI',
      () {
    final github = read('.github/workflows/yalla_unsigned_ios.yml');
    final codemagic = read('codemagic.yaml');
    final pubspec = read('pubspec.yaml');

    expect(github, contains('--no-codesign'));
    expect(codemagic, contains('--no-codesign'));
    expect(github, contains('cp ci/Podfile ios/Podfile'));
    expect(codemagic, contains('cp ci/Podfile ios/Podfile'));
    expect(github, isNot(contains('speech_to_text')));
    expect(codemagic, isNot(contains('speech_to_text')));
    expect(pubspec, isNot(contains('speech_to_text:')));
  });

  test('Phase 12 release candidate fails closed on protected inputs', () {
    final rc = read('.github/workflows/yalla_accounts_release_candidate.yml');
    expect(rc, contains('Production public config is missing.'));
    expect(rc, contains('deploy\\production_public_config.json'));
    expect(rc, contains('Android release signing secrets are missing.'));
    expect(rc, contains('dart run tools/validate_production_defines.dart'));
    expect(rc, contains('node tools/release/validate_release_matrix.mjs'));
    expect(rc, contains('Remove-Item deploy\\production_defines.json'));
  });
}
