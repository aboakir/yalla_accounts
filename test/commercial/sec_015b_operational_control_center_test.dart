import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current.path;
  String read(String relative) => File('$root/$relative').readAsStringSync();

  test('SEC.015B Control Center is operational and app-themed', () {
    final screen =
        read('lib/features/auth/screens/yalla_control_center_screen.dart');
    expect(screen, contains('AppColors.scaffoldBg'));
    expect(screen, contains('AppColors.primary'));
    expect(screen, contains("'onboarding'"));
    expect(screen, contains("'customer-preview'"));
    expect(screen, contains('إنشاء زبون جديد'));
    expect(screen, contains('معاينة تطبيق العميل'));
    expect(screen, contains('createCustomerOrganization'));
    expect(screen, contains('approveCustomerOnboarding'));
  });

  test('SEC.015B customer can submit onboarding request from same login screen',
      () {
    final login = read('lib/features/auth/screens/login_screen.dart');
    final transport =
        read('lib/features/auth/services/yalla_admin_auth_service.dart');
    expect(login, contains('طلب إنشاء منشأة / اشتراك جديد'));
    expect(login, contains('_requestNewCustomerOrganization'));
    expect(transport, contains('/v1/customer-onboarding/request'));
    expect(
        transport, contains('/v1/control-center/customer-onboarding/create'));
    expect(
        transport, contains('/v1/control-center/customer-onboarding/approve'));
  });

  test('SEC.015B local dev server persists operational control-center data',
      () {
    final server = read('tools/sec015a/dev_yalla_admin_server.ps1');
    expect(server, contains("Ensure-StateCollection 'onboarding_requests'"));
    expect(server, contains('New-CustomerProvision'));
    expect(server, contains("'/v1/customer-onboarding/request'"));
    expect(server, contains("'/v1/control-center/customer-onboarding/create'"));
    expect(
        server, contains("'/v1/control-center/customer-onboarding/approve'"));
    expect(server, contains("'/onboarding-requests'"));
    expect(server, contains('pending_activations'));
    expect(server, contains('audit_logs'));
  });

  test('SEC.015B customer preview uses local owner session only', () {
    final screen =
        read('lib/features/auth/screens/yalla_control_center_screen.dart');
    final sessions =
        read('lib/features/auth/services/auth_session_service.dart');
    expect(screen, contains('getOwner()'));
    expect(screen, contains('keepSignedIn: false'));
    expect(screen, contains('DashboardScreen'));
    expect(screen, contains('endEphemeralPreviewSession'));
    expect(screen, contains('هذا ليس دخولًا إلى بيانات عميل بعيد'));
    expect(sessions, contains('Future<void> endEphemeralPreviewSession()'));
  });
}
