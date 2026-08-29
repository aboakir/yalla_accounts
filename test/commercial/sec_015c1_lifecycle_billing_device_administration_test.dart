import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current.path;
  String read(String relative) => File('$root/$relative').readAsStringSync();

  test('SEC.015C1 exposes direct lifecycle, billing and device controls', () {
    final screen =
        read('lib/features/auth/screens/yalla_control_center_screen.dart');

    expect(screen, contains('SUBSCRIPTION.ACTIVATE'));
    expect(screen, contains('SUBSCRIPTION.EXTEND'));
    expect(screen, contains('SUBSCRIPTION.MARK_PAID'));
    expect(screen, contains('SUBSCRIPTION.MARK_UNPAID'));
    expect(screen, contains('SUBSCRIPTION.SUSPEND'));
    expect(screen, contains('SUBSCRIPTION.REACTIVATE'));
    expect(screen, contains('SUBSCRIPTION.RENEW'));
    expect(screen, contains('DEVICE.ACTIVATE'));
    expect(screen, contains('DEVICE.DEACTIVATE'));
    expect(screen, contains('_SubscriptionAdministrationView'));
    expect(screen, contains('_DeviceAdministrationView'));
    expect(screen, contains('المدة المتبقية'));
    expect(screen, contains('تمديد التجربة'));
    expect(screen, contains('غير مدفوع'));
    expect(screen, contains('إعادة تفعيل'));
  });

  test('SEC.015C1 mutations still cross the authenticated server boundary', () {
    final screen =
        read('lib/features/auth/screens/yalla_control_center_screen.dart');
    final transport =
        read('lib/features/auth/services/yalla_admin_auth_service.dart');

    expect(screen, contains('submitPrivilegedAction'));
    expect(transport, contains('/v1/control-center/actions'));
    expect(transport, contains("'X-Yalla-CSRF'"));
    expect(transport, isNot(contains('sqflite')));
    expect(transport, isNot(contains('SharedPreferences')));
    expect(screen, isNot(contains('DatabaseMigration')));
  });

  test('SEC.015C1 local server applies the full subscription cycle', () {
    final server = read('tools/sec015a/dev_yalla_admin_server.ps1');

    expect(server, contains("'SUBSCRIPTION.ACTIVATE'"));
    expect(server, contains("'SUBSCRIPTION.EXTEND'"));
    expect(server, contains("'SUBSCRIPTION.MARK_PAID'"));
    expect(server, contains("'SUBSCRIPTION.MARK_UNPAID'"));
    expect(server, contains("'SUBSCRIPTION.SUSPEND'"));
    expect(server, contains("'SUBSCRIPTION.REACTIVATE'"));
    expect(server, contains("'SUBSCRIPTION.RENEW'"));
    expect(server, contains('billing_status'));
    expect(server, contains('remaining_days'));
    expect(server, contains('remaining_hours'));
    expect(server, contains("status = 'LOCAL_DEV_APPLIED'"));
    expect(
        server,
        isNot(contains(
            "status = if (\$changed) { 'LOCAL_DEV_APPLIED' } else { 'LOCAL_DEV_ACCEPTED' }")));
  });

  test('SEC.015C1 device activate/deactivate is server-authoritative', () {
    final server = read('tools/sec015a/dev_yalla_admin_server.ps1');

    expect(server, contains("'DEVICE.ACTIVATE'"));
    expect(server, contains("'DEVICE.DEACTIVATE'"));
    expect(server, contains("'SUSPENDED'"));
    expect(server, contains("'REVOKED','REPLACED'"));
    expect(server, contains('Terminal device state'));
    expect(server, contains('can_activate'));
    expect(server, contains('can_deactivate'));
  });

  test('SEC.015C1 does not migrate or write customer SQLite', () {
    final contract = read(
      'server/yalla_licensing_server/api/sec_015c1_lifecycle_billing_device_admin_contract.md',
    );
    final server = read('tools/sec015a/dev_yalla_admin_server.ps1');

    expect(contract, contains('customer SQLite database is not modified'));
    expect(contract, contains('server-side source of truth'));
    expect(
        contract,
        contains(
            'Trial → Active → Extended → Paid/Unpaid → Frozen → Reactivated'));
    expect(server, contains('LOCAL_DEVELOPMENT_ONLY'));
    expect(server, isNot(contains('D:\\\\YallaAccounts\\\\yalla_accounts.db')));
  });
}
