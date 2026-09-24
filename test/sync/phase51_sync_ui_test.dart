import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/services/sync/sync_state_service.dart';
import 'package:yalla_accounts/core/widgets/mobile/yalla_sync_status_strip.dart';

void main() {
  testWidgets('phase51 sync UI exposes clear Arabic states', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: YallaSyncStatusStrip())),
    );

    SyncStateService.instance.setSynced();
    await tester.pump();
    expect(find.text('متزامن'), findsOneWidget);

    SyncStateService.instance.setSyncing(pendingCount: 4, sendingCount: 4);
    await tester.pump();
    expect(find.textContaining('4 متبقي'), findsOneWidget);

    SyncStateService.instance.setOffline('offline');
    await tester.pump();
    expect(find.textContaining('بدون اتصال'), findsOneWidget);

    SyncStateService.instance.setFailed('server');
    await tester.pump();
    expect(find.textContaining('تعذرت المزامنة'), findsOneWidget);

    SyncStateService.instance.setLocalOnly(
      pendingCount: 3,
      failedCount: 0,
      sendingCount: 0,
    );
    await tester.pump();
    expect(find.textContaining('3 بانتظار المزامنة'), findsOneWidget);
  });
}
