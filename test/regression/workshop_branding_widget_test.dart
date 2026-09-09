import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/core/widgets/sidebar/sidebar_header.dart';
import 'package:yalla_accounts/features/settings/models/workshop_settings.dart';
import 'package:yalla_accounts/features/settings/providers/workshop_settings_provider.dart';

void main() {
  testWidgets('sidebar and appbar refresh identity and use the same saved logo',
      (tester) async {
    await tester.runAsync(() async {
      PackageInfo.setMockInitialValues(
          appName: 'Test',
          packageName: 'test',
          version: '1',
          buildNumber: '1',
          buildSignature: '');
      final logo = File('assets/logo/logo.png').absolute;
      var name = 'ورشة أولى';
      final container = ProviderContainer(overrides: [
        workshopSettingsProvider.overrideWith((ref) async =>
            WorkshopSettings(workshopName: name, logoPath: logo.path)),
      ]);
      try {
        await container.read(workshopSettingsProvider.future);
        await tester.pumpWidget(UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
                home: Scaffold(
              appBar: const YallaAppBar(workshopName: 'stale', logoPath: ''),
              body: SizedBox(
                  width: 320,
                  child: SidebarHeader(isCollapsed: false, onToggle: () {})),
            ))));
        await tester.pumpAndSettle();
        expect(find.text('ورشة أولى'), findsOneWidget);
        expect(find.text('أهلاً بعودتك، ورشة أولى'), findsOneWidget);
        expect(
            tester
                .widgetList<Image>(find.byType(Image))
                .where((w) => w.image is FileImage)
                .length,
            2);
        name = 'ورشة معدلة';
        container.invalidate(workshopSettingsProvider);
        await container.read(workshopSettingsProvider.future);
        await tester.pumpAndSettle();
        expect(find.text('أهلاً بعودتك، ورشة معدلة'), findsOneWidget);
        expect(find.text('ورشة معدلة'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        container.dispose();
      }
    });
  });
}
