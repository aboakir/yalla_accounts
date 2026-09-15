import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/security/release_diagnostics.dart';

void main() {
  test('Phase 10 release diagnostics never expose raw startup errors', () {
    const secret = 'db=C:/private/yalla.db token=TOP-SECRET';
    final public = ReleaseDiagnostics.publicFailureText(
      StateError(secret),
      debugMode: false,
    );
    expect(public, 'رمز الخطأ: STARTUP_BLOCKED');
    expect(public, isNot(contains('private')));
    expect(public, isNot(contains('TOP-SECRET')));

    final debug = ReleaseDiagnostics.publicFailureText(
      StateError(secret),
      debugMode: true,
    );
    expect(debug, contains(secret));
  });

  test('Phase 10 bootstrap routes diagnostics through debug-only boundary', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains('ReleaseDiagnostics.debug('));
    expect(source, contains('ReleaseDiagnostics.publicFailureText(_error)'));
    expect(source, isNot(contains('debugPrint(')));
    expect(source, isNot(contains('_error.toString()')));
  });
}
