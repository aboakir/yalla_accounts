import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/tables/repair_tables.dart';
import 'package:yalla_accounts/features/repairs/services/repair_workflow_service.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('P13 final quality, delivery and closure', () {
    test('P13 schema is additive and includes an append-only event trail',
        () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('CREATE TABLE repairs(id TEXT PRIMARY KEY)');
      await db.insert('repairs', {'id': 'R-P13'});

      await RepairTables.ensureP09WorkflowSchema(db);

      final info = await db.rawQuery('PRAGMA table_info(repair_workflow)');
      final columns = info.map((row) => row['name']?.toString()).toSet();
      expect(
        columns,
        containsAll(<String>{
          'final_qc_at',
          'final_qc_by',
          'ready_for_delivery_at',
          'delivered_at',
          'handover_recipient',
          'handover_method',
          'handover_signature_path',
          'closed_at',
          'closed_by',
          'reopened_at',
          'reopen_reason',
          'reopen_count',
        }),
      );
      final events = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='repair_workflow_events'",
      );
      expect(events, hasLength(1));
    });

    test('workflow extends P09 through formal close', () {
      expect(
        P09RepairWorkflowStage.all,
        containsAll(<String>{
          P09RepairWorkflowStage.qcChecked,
          P09RepairWorkflowStage.finalQc,
          P09RepairWorkflowStage.readyForDelivery,
          P09RepairWorkflowStage.delivered,
          P09RepairWorkflowStage.closed,
        }),
      );
    });

    test('formal close gates on P10 truth without mutating posted accounting',
        () {
      final service = File(
        'lib/features/repairs/services/repair_workflow_service.dart',
      ).readAsStringSync();
      expect(service, contains('RepairFinancialTruthService.load'));
      expect(service, contains('truth.isFinanciallySettled'));
      expect(service, contains('truth.customerArBalance.abs()'));
      expect(service, contains("'status': 'CLOSED'"));
      expect(service, contains("'isArchived': 1"));
      expect(service, isNot(contains('DELETE FROM gl_')));
      expect(service, isNot(contains('delete(\'gl_entries\'')));
      expect(service, isNot(contains('update(\'gl_entries\'')));
    });

    test('P13 UI covers final QC rework, handover and formal close', () {
      final widget = File(
        'lib/features/repairs/widgets/repair_workflow_card.dart',
      ).readAsStringSync();
      expect(widget, contains('فحص الجودة النهائي'));
      expect(widget, contains('إرجاع للتنفيذ'));
      expect(widget, contains('اعتماد الجاهزية للتسليم'));
      expect(widget, contains('تسليم المركبة'));
      expect(widget, contains('اسم المستلم *'));
      expect(widget, contains('توقيع العميل اختياري'));
      expect(widget, contains('إغلاق رسمي'));
    });

    test('raw archive toggle is removed and reopen requires a reason', () {
      final screen = File(
        'lib/features/repairs/screens/repairs_screen.dart',
      ).readAsStringSync();
      expect(screen, isNot(contains("'أرشفة الملف'")));
      expect(screen, isNot(contains("'استعادة من الأرشيف'")));
      expect(screen, contains('إعادة فتح الملف المغلق'));
      expect(screen, contains('RepairWorkflowService.reopenClosed'));
      expect(screen, contains('سبب إعادة الفتح *'));
    });

    test('workflow-owned delivery statuses cannot be selected manually', () {
      final constants = File(
        'lib/features/repairs/constants/repair_status.dart',
      ).readAsStringSync();
      final intake = File(
        'lib/features/repairs/widgets/steps/step_work_data.dart',
      ).readAsStringSync();
      final edit = File(
        'lib/features/repairs/screens/edit_repair_screen.dart',
      ).readAsStringSync();
      final details = File(
        'lib/features/repairs/screens/repair_details_screen.dart',
      ).readAsStringSync();
      expect(constants, contains('kManualVehicleStatuses'));
      expect(constants, contains('kWorkflowVehicleStatuses'));
      expect(intake, contains('items: kManualVehicleStatuses'));
      expect(edit, contains('enabled: !kWorkflowVehicleStatuses.contains(e)'));
      expect(details, contains('workflowOwnsVehicleStatus'));
    });

    test('completed repairs and reports mean formal CLOSED, not archive', () {
      final completed = File(
        'lib/features/repairs/screens/completed_repairs_screen.dart',
      ).readAsStringSync();
      final reports = File(
        'lib/core/services/db/tables/report_tables.dart',
      ).readAsStringSync();
      final model = File(
        'lib/features/repairs/models/repair.dart',
      ).readAsStringSync();
      expect(completed, contains('repair.status == RepairStatusText.closed'));
      expect(reports, contains("status = 'CLOSED'"));
      expect(
          model, contains('isArchived && status == RepairStatusText.closed'));
    });
  });
}
