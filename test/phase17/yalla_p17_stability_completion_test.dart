import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  group('P17 source contracts', () {
    test('all persisted workshop photos pass the central optimizer', () {
      final storage = read('lib/core/storage/yalla_storage_service.dart');
      final imageService = read('lib/core/services/image_storage_service.dart');
      expect(storage, contains('optimizeImageBytes('));
      expect(storage, contains('final optimized = await optimizeImageBytes('));
      expect(storage, contains('compute<Map<String, Object?>'));
      expect(imageService, contains('YallaStorageService.optimizeImageBytes('));
    });

    test('repair list is paged and image rows are batch-loaded', () {
      final service =
          read('lib/features/repairs/services/repairs_service.dart');
      final screen =
          read('lib/features/repairs/screens/repairs_list_screen.dart');
      expect(service, contains('_listImagePathsForRepairIds'));
      expect(service, contains(r'WHERE repair_id IN ($placeholders)'));
      expect(screen, contains('static const int _pageSize = 40;'));
      expect(screen, contains('limit: _pageSize'));
      expect(screen, contains('offset: _nextOffset'));
      expect(screen, isNot(contains('DBService.getRepairThumbnailPath')));
    });

    test('thumbnail decode size and PDF legacy-image optimization are bounded',
        () {
      final stored = read('lib/core/storage/yalla_stored_image.dart');
      final pdf =
          read('lib/features/repairs/services/repair_pdf_generator.dart');
      expect(stored, contains('effectiveCacheWidth'));
      expect(stored, contains('effectiveCacheHeight'));
      expect(stored, contains('cacheHeight: effectiveCacheHeight'));
      expect(pdf, contains('maxDimension: 1200'));
      expect(pdf, contains('quality: 72'));
      expect(pdf, isNot(contains('final imageBytes = <Uint8List>[];')));
    });

    test('heavy repair image scoring runs through compute', () {
      final service =
          read('lib/features/repairs/services/repairs_service.dart');
      expect(service, contains("compute<String, Map<String, double>?>"));
      expect(service, contains('_scoreImagePayload'));
    });

    test('critical data screens distinguish loading empty and error with retry',
        () {
      final repairs =
          read('lib/features/repairs/screens/repairs_list_screen.dart');
      final payments = read(
          'lib/features/finance/payments/screens/payment_list_screen.dart');
      for (final source in <String>[repairs, payments]) {
        expect(source, contains('LoadingWidget'));
        expect(source, contains('ErrorDisplay'));
        expect(source, contains('YallaEmptyState'));
      }
      expect(repairs, contains('onRetry: _loadRepairs'));
      expect(payments, contains('onRetry: _load'));
    });

    test('bootstrap failure is recoverable without creating a replacement DB',
        () {
      final main = read('lib/main.dart');
      expect(
          main, contains('class _BootstrapFailureApp extends StatefulWidget'));
      expect(main, contains('Future<void> _retry() async'));
      expect(main, contains("'إعادة المحاولة'"));
      expect(main, contains('لن يتم إنشاء قاعدة بديلة'));
    });

    test('fixed voucher dialogs use the adaptive phone-safe surface', () {
      for (final path in <String>[
        'lib/features/vouchers/dialogs/employees_payment_dialog.dart',
        'lib/features/vouchers/dialogs/supplier_purchase_dialog.dart',
        'lib/features/vouchers/dialogs/purchases_dialog.dart',
        'lib/features/vouchers/dialogs/expense_voucher_dialog.dart',
      ]) {
        final source = read(path);
        expect(source, contains('AdaptiveDialogSurface('));
        expect(
            source, isNot(contains('insetPadding: const EdgeInsets.all(40)')));
      }
    });

    test('responsive wrappers derive 600/1024 from one canonical source', () {
      final responsive = read('lib/shared/widgets/responsive.dart');
      final builder = read('lib/shared/layouts/responsive_builder.dart');
      final adaptive = read('lib/shared/widgets/adaptive_layout.dart');
      expect(responsive, contains('YallaBreakpoints.tablet'));
      expect(responsive, contains('YallaBreakpoints.desktop'));
      expect(builder, contains('design.YallaBreakpoints.tablet'));
      expect(adaptive, contains('design.YallaBreakpoints.tablet'));
    });

    test('sync failure UX exposes retry only when a transport exists', () {
      final source =
          read('lib/core/widgets/mobile/yalla_sync_status_strip.dart');
      expect(source, contains('snapshot.transportConfigured'));
      expect(source, contains('UnifiedSyncCoordinatorV3.instance.cycle()'));
      expect(source, isNot(contains('OutboxSyncCoordinator.instance.drain()')));
      expect(source, contains("'إعادة المحاولة'"));
    });
  });
}
