import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('P04.3 mobile shell exposes truthful sync indicator', () {
    final bottom = File(
      'lib/core/widgets/mobile/yalla_mobile_bottom_nav.dart',
    ).readAsStringSync();
    final strip = File(
      'lib/core/widgets/mobile/yalla_sync_status_strip.dart',
    ).readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(bottom, contains('const YallaSyncStatusStrip()'));
    expect(strip, contains('محفوظ محليًا'));
    expect(strip, contains('متزامن'));
    expect(strip, contains('بدون اتصال'));
    expect(strip, contains('تعذرت المزامنة'));
    expect(
      main,
      contains('await OutboxSyncCoordinator.instance.start();'),
    );
  });

  test('P04.3 production source does not invent a sync URL', () {
    final transport = File(
      'lib/core/services/sync/outbox_sync_transport.dart',
    ).readAsStringSync();
    final coordinator = File(
      'lib/core/services/sync/outbox_sync_coordinator.dart',
    ).readAsStringSync();

    expect(transport, isNot(contains('https://')));
    expect(transport, isNot(contains('http://')));
    expect(coordinator, isNot(contains('https://')));
    expect(coordinator, isNot(contains('http://')));
    expect(
      coordinator,
      contains('ack.idempotencyKey != envelope.idempotencyKey'),
    );
  });
}
