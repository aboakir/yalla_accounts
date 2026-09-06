import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/tables/repair_tables.dart';
import 'package:yalla_accounts/features/repairs/services/repair_workflow_service.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('P09 workflow completion', () {
    test('additive workflow schema preserves legacy repair rows', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);

      await db.execute('''
        CREATE TABLE repairs(
          id TEXT PRIMARY KEY,
          vehicleNumber TEXT,
          fileValue REAL
        )
      ''');
      await db.insert('repairs', <String, Object?>{
        'id': 'legacy-p09',
        'vehicleNumber': '11-222-33',
        'fileValue': 4200.0,
      });

      await RepairTables.ensureP09WorkflowSchema(db);

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='repair_workflow'",
      );
      expect(tables, hasLength(1));

      final info = await db.rawQuery('PRAGMA table_info(repair_workflow)');
      final columns = info.map((row) => row['name']?.toString()).toSet();
      expect(
        columns,
        containsAll(<String>{
          'repair_id',
          'stage',
          'damage_assessment',
          'quote_number',
          'quote_valid_until',
          'quote_sent_at',
          'approved_at',
          'approval_method',
          'rejected_at',
          'rejection_reason',
          'work_order_number',
          'work_order_started_at',
          'responsible_employee_id',
          'initial_qc_at',
          'qc_work_complete',
          'qc_finish_checked',
          'qc_cleanliness_checked',
          'qc_documentation_checked',
        }),
      );

      final legacy = (await db.query(
        'repairs',
        where: 'id = ?',
        whereArgs: const <Object?>['legacy-p09'],
      ))
          .single;
      expect(legacy['vehicleNumber'], '11-222-33');
      expect(legacy['fileValue'], 4200.0);
    });

    test('P09 core workflow stages remain present after later extensions', () {
      expect(
        P09RepairWorkflowStage.all,
        containsAll(<String>{
          P09RepairWorkflowStage.draft,
          P09RepairWorkflowStage.sent,
          P09RepairWorkflowStage.approved,
          P09RepairWorkflowStage.rejected,
          P09RepairWorkflowStage.workOrder,
          P09RepairWorkflowStage.inProgress,
          P09RepairWorkflowStage.readyForQc,
          P09RepairWorkflowStage.qcChecked,
        }),
      );
      // Later phases may append delivery/closure stages, but may not
      // remove or rename the P09 core stages above.
    });

    test('legacy saveAsQuote no longer auto-approves or enables ledger', () {
      final save = File(
        'lib/features/repairs/services/repair_save_service.dart',
      ).readAsStringSync();
      expect(save, contains("status: isLedgerEnabled ? 'APPROVED' : 'QUOTE'"));
      expect(save,
          contains('approvedAt: isLedgerEnabled ? DateTime.now() : null'));
      expect(save, contains("approvedBy: isLedgerEnabled ? 'SYSTEM' : null"));
      expect(save, contains('isLedgerEnabled: isLedgerEnabled'));
      expect(save,
          contains('finalApprovedAmount: isLedgerEnabled ? grandTotal : null'));
    });

    test('operational approval is isolated from invoice and GL code', () {
      final service = File(
        'lib/features/repairs/services/repair_workflow_service.dart',
      ).readAsStringSync();

      expect(service, contains('approveEstimate'));
      expect(service, contains('operational-only'));
      expect(service, isNot(contains('InvoiceService')));
      expect(service, isNot(contains('approveQuote(')));
      expect(service, isNot(contains('PostingEngine')));
      expect(service, isNot(contains('gl_entries')));
      expect(service, isNot(contains("'invoice_id':")));
    });

    test('Repair Details exposes one P09 workflow card on all layouts', () {
      final details = File(
        'lib/features/repairs/screens/repair_details_screen.dart',
      ).readAsStringSync();
      expect(details, contains('RepairWorkflowCard'));
      expect(details, contains('onShareEstimate: _sharePdf'));
      expect(RegExp(r'_buildWorkflowCard\(\)').allMatches(details).length,
          greaterThanOrEqualTo(4));
    });

    test('workflow UI keeps all required P09 actions after P13 extension', () {
      final widget = File(
        'lib/features/repairs/widgets/repair_workflow_card.dart',
      ).readAsStringSync();

      expect(widget, contains('إعداد عرض السعر'));
      expect(widget, contains('تسجيل إرسال العرض'));
      expect(widget, contains('تسجيل الموافقة'));
      expect(widget, contains('تسجيل الرفض'));
      expect(widget, contains('إنشاء أمر العمل'));
      expect(widget, contains('المسؤول / الفني'));
      expect(widget, contains('بدء التنفيذ'));
      expect(widget, contains('الفحص الأولي للجودة'));
      expect(widget, contains('الأعمال المطلوبة مكتملة'));
      // P13 may extend the same card after QC_CHECKED. The P09 regression
      // only guarantees that its own operational actions remain intact.
    });

    test('estimate copy shows quote number and validity in existing PDF', () {
      final pdf = File(
        'lib/features/repairs/services/repair_pdf_generator.dart',
      ).readAsStringSync();
      expect(pdf, contains("'رقم العرض: \${repair.quoteNumber}'"));
      expect(pdf,
          contains("'صالح حتى: \${dateFmt.format(repair.quoteValidUntil!)}'"));
    });

    test('P09 card uses responsive wrapping instead of fixed desktop layout',
        () {
      final widget = File(
        'lib/features/repairs/widgets/repair_workflow_card.dart',
      ).readAsStringSync();
      expect(widget, contains('Wrap('));
      expect(widget, contains('SingleChildScrollView('));
      expect(widget, isNot(contains('DataTable(')));
      expect(widget, isNot(contains('AlertDialog(')));
      expect(
          RegExp(r'(^|[^A-Za-z0-9_.])Row\s*\(', multiLine: true)
              .hasMatch(widget),
          isFalse);
    });
  });
}
