import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';

Iterable<File> _dartFiles() sync* {
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      yield entity;
    }
  }
}

String _withoutComments(String source) {
  var value = source.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  value = value
      .split('\n')
      .map((line) => line.replaceFirst(RegExp(r'//.*$'), ''))
      .join('\n');
  return value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Phase 1 route audit has no legacy broken route targets', () {
    const forbidden = <String>{
      '/repair-analytics',
      '/suppliers/details',
      '/clients/details',
      '/repairs/details',
      '/finance/journal/entry',
    };

    final offenders = <String>[];
    for (final file in _dartFiles()) {
      final source = _withoutComments(file.readAsStringSync());
      for (final route in forbidden) {
        if (source.contains("'$route'") || source.contains('"$route"')) {
          offenders.add('${file.path}: $route');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Legacy broken routes found: ${offenders.join(', ')}');
  });

  test('Dynamic named navigation is guarded by the route registry', () {
    final directDynamic = RegExp(
      r'(?:pushNamed(?:<[^>]+>)?|pushReplacementNamed|'
      r'pushNamedAndRemoveUntil)\s*\(\s*route\b',
    );
    final offenders = <String>[];

    for (final file in _dartFiles()) {
      final source = _withoutComments(file.readAsStringSync());
      if (!directDynamic.hasMatch(source)) continue;
      if (!source.contains('isRegisteredRoute(route)')) {
        offenders.add(file.path);
      }
    }

    expect(offenders, isEmpty,
        reason: 'Unguarded dynamic navigation: ${offenders.join(', ')}');
  });

  test('UnderConstruction is limited to intentional unavailable sections', () {
    final source = File('lib/core/routes/app_routes.dart').readAsStringSync();
    final matches = RegExp(
      r"_under\(\s*settings\s*,\s*'([^']+)'\s*\)",
      multiLine: true,
    ).allMatches(source);

    final titles = matches.map((m) => m.group(1)).whereType<String>().toSet();
    expect(
        titles,
        equals(<String>{
          'لوحة الإدارة',
          'لوحة المدير',
          'شاشة الجرد والمخزون',
          'إعدادات المستخدم',
          'إعدادات الواجهة',
        }));
    expect(source, isNot(contains("return _under(settings, 'شاشة غير موجودة")));
  });

  test('Every registered named route resolves without throwing', () {
    for (final routeName in AppRoutes.registeredRoutes) {
      expect(
        () => AppRoutes.onGenerateRoute(RouteSettings(name: routeName)),
        returnsNormally,
        reason: 'Failed route: $routeName',
      );
    }
  });

  test('Missing route data falls back to a safe real screen', () {
    final repair = AppRoutes.onGenerateRoute(
      const RouteSettings(name: AppRoutes.repairDetail),
    );
    final cheque = AppRoutes.onGenerateRoute(
      const RouteSettings(name: AppRoutes.chequesEdit),
    );
    final gl = AppRoutes.onGenerateRoute(
      const RouteSettings(name: AppRoutes.financeGLEntry),
    );
    final invoice = AppRoutes.onGenerateRoute(
      const RouteSettings(name: AppRoutes.invoiceView),
    );

    expect(repair.settings.name, AppRoutes.repairsList);
    expect(cheque.settings.name, AppRoutes.chequesList);
    expect(gl.settings.name, AppRoutes.financeGL);
    expect(invoice.settings.name, AppRoutes.financeDashboard);
  });

  test('Unknown route falls back to dashboard, never placeholder', () {
    final route = AppRoutes.onGenerateRoute(
      const RouteSettings(name: '/definitely-not-registered'),
    );
    expect(route.settings.name, AppRoutes.dashboard);
  });
}
