import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';
import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_platform_policy.dart';
import 'package:yalla_accounts/core/services/db/db_service.dart';

enum DataHealthStatus {
  pass,
  warning,
  error,
  repairable,
}

class DataHealthItem {
  const DataHealthItem({
    required this.id,
    required this.title,
    required this.message,
    required this.status,
    this.affected = 0,
    this.amount,
  });

  final String id;
  final String title;
  final String message;
  final DataHealthStatus status;
  final int affected;
  final double? amount;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'message': message,
        'status': status.name.toUpperCase(),
        'affected': affected,
        if (amount != null) 'amount': amount,
      };
}

class DataHealthReport {
  const DataHealthReport({
    required this.generatedAt,
    required this.dbVersion,
    required this.items,
  });

  final DateTime generatedAt;
  final int dbVersion;
  final List<DataHealthItem> items;

  int get passCount =>
      items.where((item) => item.status == DataHealthStatus.pass).length;

  int get warningCount =>
      items.where((item) => item.status == DataHealthStatus.warning).length;

  int get errorCount =>
      items.where((item) => item.status == DataHealthStatus.error).length;

  int get repairableCount =>
      items.where((item) => item.status == DataHealthStatus.repairable).length;

  bool get hasBlockingIssues => errorCount > 0;

  Map<String, Object?> toJson() => {
        'generated_at': generatedAt.toIso8601String(),
        'db_version': dbVersion,
        'summary': {
          'pass': passCount,
          'warning': warningCount,
          'error': errorCount,
          'repairable': repairableCount,
        },
        'items': items.map((item) => item.toJson()).toList(),
      };
}

class DataHealthRepairResult {
  const DataHealthRepairResult({
    required this.backupPath,
    required this.logId,
    required this.changes,
    required this.report,
  });

  final String backupPath;
  final int logId;
  final Map<String, int> changes;
  final DataHealthReport report;
}

class _RepairDetailAudit {
  const _RepairDetailAudit({
    required this.cacheMismatchCount,
    required this.fileValueMismatchCount,
    required this.fileValueMismatchAmount,
    required this.malformedCount,
  });

  final int cacheMismatchCount;
  final int fileValueMismatchCount;
  final double fileValueMismatchAmount;
  final int malformedCount;
}

class DataHealthService {
  DataHealthService._();

  static final DataHealthService instance = DataHealthService._();

  Future<DataHealthReport> runHealthCheck({
    bool exportReport = false,
  }) async {
    final db = await DBService.database;
    final report = await _runWithDb(db);

    if (exportReport) {
      await export(report);
    }

    return report;
  }

  Future<String> export(DataHealthReport report) async {
    final downloads = await _downloadsDirectory();
    if (!downloads.existsSync()) {
      downloads.createSync(recursive: true);
    }

    final stamp = _fileStamp(DateTime.now());
    final file = File(
      '${downloads.path}${Platform.pathSeparator}'
      'Yalla_Data_Health_$stamp.json',
    );

    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report.toJson()),
      flush: true,
    );

    return file.path;
  }

  Future<DataHealthRepairResult> repairSafeIssues() async {
    final db = await DBService.database;
    final before = await _runWithDb(db);

    if (before.repairableCount == 0) {
      final backupPath = await _createBackup(db);
      final logId = await db.insert(
        'data_health_repair_log',
        {
          'run_at': DateTime.now().toIso8601String(),
          'backup_path': backupPath,
          'changes_json': '{}',
          'before_summary': jsonEncode(before.toJson()['summary']),
          'after_summary': jsonEncode(before.toJson()['summary']),
        },
      );

      return DataHealthRepairResult(
        backupPath: backupPath,
        logId: logId,
        changes: const {},
        report: before,
      );
    }

    final backupPath = await _createBackup(db);
    final changes = <String, int>{};

    final after = await db.transaction<DataHealthReport>((txn) async {
      changes['invoice_posting_cache'] = await _repairInvoicePostingCache(txn);

      changes['voucher_posting_cache'] = await _repairVoucherPostingCache(txn);

      changes['payment_gl_cache'] = await _repairPaymentPostingCache(txn);

      changes['repair_invoice_cache'] = await _repairRepairInvoiceCache(txn);

      changes['supplier_accounts_created'] =
          await _repairMissingSupplierAccounts(txn);

      changes['cheque_document_links'] = await _repairChequeDocumentLinks(txn);

      changes['repair_detail_caches'] = await _repairRepairDetailCaches(txn);

      changes['repair_payment_caches'] = await _repairRepairPaymentCaches(txn);

      changes['settlement_schema'] = await _repairSettlementSchema(txn);

      final candidate = await _runWithDb(txn);

      if (candidate.errorCount > before.errorCount) {
        throw StateError(
          'Data-health repair introduced a new blocking error. '
          'The transaction will be rolled back.',
        );
      }

      if (candidate.repairableCount != 0) {
        throw StateError(
          'One or more deterministic repairs did not validate. '
          'The transaction will be rolled back.',
        );
      }

      return candidate;
    });

    final logId = await db.insert(
      'data_health_repair_log',
      {
        'run_at': DateTime.now().toIso8601String(),
        'backup_path': backupPath,
        'changes_json': jsonEncode(changes),
        'before_summary': jsonEncode(before.toJson()['summary']),
        'after_summary': jsonEncode(after.toJson()['summary']),
      },
    );

    final downloads = await _downloadsDirectory();
    final logFile = File(
      '${downloads.path}${Platform.pathSeparator}'
      'Yalla_Data_Health_Repair_${_fileStamp(DateTime.now())}.json',
    );

    await logFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'backup_path': backupPath,
        'log_id': logId,
        'changes': changes,
        'before': before.toJson(),
        'after': after.toJson(),
      }),
      flush: true,
    );

    return DataHealthRepairResult(
      backupPath: backupPath,
      logId: logId,
      changes: Map.unmodifiable(changes),
      report: after,
    );
  }

  Future<DataHealthReport> _runWithDb(DatabaseExecutor db) async {
    final version = await _firstInt(
      db,
      'PRAGMA user_version',
    );

    final items = <DataHealthItem>[];

    items.add(
      DataHealthItem(
        id: 'db_version',
        title: 'إصدار قاعدة البيانات',
        message: version == DatabaseConstants.dbVersion
            ? 'قاعدة البيانات على الإصدار المعتمد v$version.'
            : 'إصدار القاعدة v$version بينما التطبيق يتوقع '
                'v${DatabaseConstants.dbVersion}.',
        status: version == DatabaseConstants.dbVersion
            ? DataHealthStatus.pass
            : DataHealthStatus.error,
        affected: version == DatabaseConstants.dbVersion ? 0 : 1,
      ),
    );

    final integrityRows = await db.rawQuery('PRAGMA integrity_check');
    final integrityOk = integrityRows.isNotEmpty &&
        integrityRows.first.values.first.toString().toLowerCase() == 'ok';

    items.add(
      DataHealthItem(
        id: 'sqlite_integrity',
        title: 'سلامة SQLite',
        message: integrityOk
            ? 'فحص integrity_check سليم.'
            : 'SQLite أبلغ عن خلل بنيوي في قاعدة البيانات.',
        status: integrityOk ? DataHealthStatus.pass : DataHealthStatus.error,
        affected: integrityOk ? 0 : integrityRows.length,
      ),
    );

    final foreignKeyViolations =
        (await db.rawQuery('PRAGMA foreign_key_check')).length;

    items.add(
      _zeroIsPass(
        id: 'foreign_keys',
        title: 'المفاتيح الخارجية',
        count: foreignKeyViolations,
        okMessage: 'لا توجد مخالفات Foreign Key.',
        issueMessage: 'توجد مراجع بين الجداول غير سليمة.',
        issueStatus: DataHealthStatus.error,
      ),
    );

    final unbalancedGl = await _firstInt(
      db,
      '''
      SELECT COUNT(*)
      FROM (
        SELECT e.id
        FROM gl_entries e
        LEFT JOIN gl_lines l ON l.entry_id=e.id
        GROUP BY e.id
        HAVING ABS(COALESCE(SUM(l.debit),0) -
                   COALESCE(SUM(l.credit),0)) > 0.01
      )
      ''',
    );

    items.add(
      _zeroIsPass(
        id: 'gl_balance',
        title: 'توازن القيود العامة',
        count: unbalancedGl,
        okMessage: 'كل قيود GL متوازنة.',
        issueMessage: 'يوجد قيد أو أكثر غير متوازن.',
        issueStatus: DataHealthStatus.error,
      ),
    );

    final duplicateGlSources = await _firstInt(
      db,
      '''
      SELECT COUNT(*)
      FROM (
        SELECT source, source_id
        FROM gl_entries
        GROUP BY source, source_id
        HAVING COUNT(*) > 1
      )
      ''',
    );

    items.add(
      _zeroIsPass(
        id: 'gl_duplicate_source',
        title: 'منع الترحيل المكرر',
        count: duplicateGlSources,
        okMessage: 'لا يوجد source/source_id مكرر في GL.',
        issueMessage: 'تم اكتشاف ترحيل مكرر لنفس المستند.',
        issueStatus: DataHealthStatus.error,
      ),
    );

    final badGlReferences = await _firstInt(
      db,
      '''
      SELECT
        (SELECT COUNT(*)
         FROM gl_lines l
         LEFT JOIN gl_entries e ON e.id=l.entry_id
         WHERE e.id IS NULL)
        +
        (SELECT COUNT(*)
         FROM gl_lines l
         LEFT JOIN accounts a ON a.id=l.account_id
         WHERE a.id IS NULL)
      ''',
    );

    items.add(
      _zeroIsPass(
        id: 'gl_references',
        title: 'مراجع GL',
        count: badGlReferences,
        okMessage: 'كل أسطر GL مرتبطة بقيد وحساب صالحين.',
        issueMessage: 'يوجد GL Line بلا قيد أو بلا حساب صالح.',
        issueStatus: DataHealthStatus.error,
      ),
    );

    final missingDocumentGl = await _firstInt(
      db,
      '''
      SELECT
        (SELECT COUNT(*)
         FROM invoices i
         WHERE NOT EXISTS(
           SELECT 1 FROM gl_entries e
           WHERE e.source='INVOICE' AND e.source_id=i.id
         ))
        +
        (SELECT COUNT(*)
         FROM vouchers v
         WHERE NOT EXISTS(
           SELECT 1 FROM gl_entries e
           WHERE e.source='VOUCHER' AND e.source_id=v.id
         ))
        +
        (SELECT COUNT(*)
         FROM payments p
         WHERE p.isIncome=1
           AND NOT EXISTS(
             SELECT 1 FROM gl_entries e
             WHERE e.source='PAYMENT' AND e.source_id=p.id
           ))
        +
        (SELECT COUNT(*)
         FROM purchase_invoices p
         WHERE NOT EXISTS(
           SELECT 1 FROM gl_entries e
           WHERE e.source='PURCHASE' AND e.source_id=p.id
         ))
      ''',
    );

    items.add(
      _zeroIsPass(
        id: 'document_gl_coverage',
        title: 'تغطية المستندات المحاسبية',
        count: missingDocumentGl,
        okMessage: 'الفواتير والسندات والقبوض والمشتريات المرحّلة لها GL.',
        issueMessage: 'يوجد مستند محاسبي بلا GL متوقع.',
        issueStatus: DataHealthStatus.error,
      ),
    );

    final orphanBusinessGl = await _firstInt(
      db,
      '''
      SELECT
        (SELECT COUNT(*)
         FROM gl_entries e
         WHERE e.source='INVOICE'
           AND NOT EXISTS(SELECT 1 FROM invoices i WHERE i.id=e.source_id))
        +
        (SELECT COUNT(*)
         FROM gl_entries e
         WHERE e.source='VOUCHER'
           AND NOT EXISTS(SELECT 1 FROM vouchers v WHERE v.id=e.source_id))
        +
        (SELECT COUNT(*)
         FROM gl_entries e
         WHERE e.source='PAYMENT'
           AND NOT EXISTS(SELECT 1 FROM payments p WHERE p.id=e.source_id))
        +
        (SELECT COUNT(*)
         FROM gl_entries e
         WHERE e.source='PURCHASE'
           AND NOT EXISTS(
             SELECT 1 FROM purchase_invoices p WHERE p.id=e.source_id
           ))
      ''',
    );

    items.add(
      _zeroIsPass(
        id: 'orphan_business_gl',
        title: 'قيود بلا مستند أصلي',
        count: orphanBusinessGl,
        okMessage: 'لا توجد قيود تشغيلية يتيمة.',
        issueMessage: 'يوجد GL لمستند أعمال غير موجود.',
        issueStatus: DataHealthStatus.error,
      ),
    );

    final postingCacheMismatch = await _firstInt(
      db,
      '''
      SELECT
        (SELECT COUNT(*)
         FROM invoices i
         LEFT JOIN gl_entries e
           ON e.source='INVOICE' AND e.source_id=i.id
         WHERE COALESCE(i.post_to_gl,0) <>
               CASE WHEN e.id IS NULL THEN 0 ELSE 1 END
            OR COALESCE(i.gl_entry_id,0) <> COALESCE(e.id,0))
        +
        (SELECT COUNT(*)
         FROM vouchers v
         LEFT JOIN gl_entries e
           ON e.source='VOUCHER' AND e.source_id=v.id
         WHERE COALESCE(v.is_posted,0) <>
               CASE WHEN e.id IS NULL THEN 0 ELSE 1 END
            OR COALESCE(v.gl_entry_id,0) <> COALESCE(e.id,0))
        +
        (SELECT COUNT(*)
         FROM payments p
         LEFT JOIN gl_entries e
           ON e.source='PAYMENT' AND e.source_id=p.id
         WHERE e.id IS NOT NULL
           AND COALESCE(p.gl_entry_id,0) <> e.id)
      ''',
    );

    items.add(
      _zeroIsPass(
        id: 'posting_cache',
        title: 'حالة الترحيل المخزنة',
        count: postingCacheMismatch,
        okMessage: 'حقول حالة الترحيل متطابقة مع GL.',
        issueMessage: 'حقول Cache لا تطابق GL ويمكن مزامنتها بأمان.',
        issueStatus: DataHealthStatus.repairable,
      ),
    );

    final repairInvoiceLinkMismatch = await _firstInt(
      db,
      '''
      SELECT COUNT(*)
      FROM repairs r
      JOIN invoices i ON i.repair_id=r.id
      WHERE COALESCE(r.invoice_id,'') <> i.id
      ''',
    );

    items.add(
      _zeroIsPass(
        id: 'repair_invoice_link',
        title: 'ربط Repair ↔ Invoice',
        count: repairInvoiceLinkMismatch,
        okMessage: 'روابط Repair/Invoice متزامنة.',
        issueMessage: 'رابط Repair/Invoice المخزن يحتاج مزامنة.',
        issueStatus: DataHealthStatus.repairable,
      ),
    );

    final invoiceRelationshipErrors = await _firstInt(
      db,
      '''
      SELECT
        (SELECT COUNT(*)
         FROM (
           SELECT repair_id
           FROM invoices
           WHERE repair_id IS NOT NULL AND TRIM(repair_id)<>''
           GROUP BY repair_id
           HAVING COUNT(*) > 1
         ))
        +
        (SELECT COUNT(*)
         FROM invoices i
         LEFT JOIN repairs r ON r.id=i.repair_id
         WHERE i.repair_id IS NOT NULL
           AND TRIM(i.repair_id)<>''
           AND r.id IS NULL)
      ''',
    );

    items.add(
      _zeroIsPass(
        id: 'invoice_relationship',
        title: 'سلامة علاقة الفاتورة بملف الإصلاح',
        count: invoiceRelationshipErrors,
        okMessage: 'لا توجد فاتورة يتيمة أو أكثر من فاتورة لنفس Repair.',
        issueMessage: 'علاقة Repair/Invoice تحتوي خطأ بنيويًا.',
        issueStatus: DataHealthStatus.error,
      ),
    );

    final repairInvoiceMismatch = await db.rawQuery(
      '''
      SELECT
        COUNT(*) AS c,
        COALESCE(SUM(ABS(COALESCE(r.fileValue,0) -
                         COALESCE(i.total,0))),0) AS amount
      FROM repairs r
      JOIN invoices i ON i.repair_id=r.id
      WHERE ABS(COALESCE(r.fileValue,0) -
                COALESCE(i.total,0)) > 0.01
      ''',
    );

    final mismatchCount = _asInt(repairInvoiceMismatch.first['c']);
    final mismatchAmount = _asDouble(
      repairInvoiceMismatch.first['amount'],
    );

    items.add(
      DataHealthItem(
        id: 'repair_invoice_amount_warning',
        title: 'اختلاف Repair عن الفاتورة التاريخية',
        message: mismatchCount == 0
            ? 'لا توجد فروقات بين القيمة التشغيلية والفاتورة.'
            : 'يوجد $mismatchCount ملفًا تغيرت قيمته التشغيلية عن '
                'الفاتورة المرحّلة. هذا تحذير مراجعة ولا يعاد كتابة '
                'الفاتورة تلقائيًا.',
        status: mismatchCount == 0
            ? DataHealthStatus.pass
            : DataHealthStatus.warning,
        affected: mismatchCount,
        amount: mismatchCount == 0 ? null : mismatchAmount,
      ),
    );

    final detailAudit = await _auditRepairDetails(db);

    items.add(
      DataHealthItem(
        id: 'repair_detail_cache',
        title: 'تفاصيل Repair المشتقة',
        message: detailAudit.malformedCount > 0
            ? 'يوجد JSON غير صالح أو قيمة سالبة في تفاصيل Repair.'
            : detailAudit.cacheMismatchCount > 0
                ? 'repair_lines لا يطابق parts/works ويمكن إعادة بنائه '
                    'بصورة حتمية.'
                : 'repair_lines يطابق parts/works.',
        status: detailAudit.malformedCount > 0
            ? DataHealthStatus.error
            : detailAudit.cacheMismatchCount > 0
                ? DataHealthStatus.repairable
                : DataHealthStatus.pass,
        affected: detailAudit.malformedCount > 0
            ? detailAudit.malformedCount
            : detailAudit.cacheMismatchCount,
      ),
    );

    items.add(
      DataHealthItem(
        id: 'repair_file_value_warning',
        title: 'قيمة Repair مقابل تفاصيله',
        message: detailAudit.fileValueMismatchCount == 0
            ? 'مجموع parts/works يطابق fileValue لكل الملفات.'
            : 'يوجد ${detailAudit.fileValueMismatchCount} Repair يحتاج '
                'مراجعة تشغيلية لأن تفاصيله لا تطابق fileValue.',
        status: detailAudit.fileValueMismatchCount == 0
            ? DataHealthStatus.pass
            : DataHealthStatus.warning,
        affected: detailAudit.fileValueMismatchCount,
        amount: detailAudit.fileValueMismatchCount == 0
            ? null
            : detailAudit.fileValueMismatchAmount,
      ),
    );

    final repairPaymentCacheMismatch = await _firstInt(
      db,
      '''
      WITH paid AS (
        SELECT repair_id, 1 AS payment_count, paid FROM (${RepairFinancialTruthService.paidByRepairSql})
      )
      SELECT COUNT(*)
      FROM repairs r
      LEFT JOIN paid p ON p.repair_id=r.id
      WHERE COALESCE(p.payment_count,0) > 0
        AND (
          ABS(COALESCE(r.total_paid_amount,0)-COALESCE(p.paid,0)) > 0.01
         OR ABS(COALESCE(r.paidAmount,0)-COALESCE(p.paid,0)) > 0.01
         OR COALESCE(r.paymentStatus,'') <>
            CASE
              WHEN COALESCE(r.fileValue,0) <= 0.005 THEN 'مسدد'
              WHEN COALESCE(p.paid,0) <= 0.005 THEN 'غير مسدد'
              WHEN COALESCE(p.paid,0)+0.005 >= COALESCE(r.fileValue,0) THEN 'مسدد'
              ELSE 'مسدد جزئي'
            END
        )
      ''',
    );

    items.add(
      _zeroIsPass(
        id: 'repair_payment_cache',
        title: 'مطابقة مدفوع Repair مع Payments',
        count: repairPaymentCacheMismatch,
        okMessage: 'paidAmount و total_paid_amount مطابقان لـ GL receipts.',
        issueMessage:
            'يوجد Repair cache لا يطابق المدفوعات ويمكن إصلاحه بأمان.',
        issueStatus: DataHealthStatus.repairable,
      ),
    );

    final legacyRepairPaymentEvidence = await _firstInt(
      db,
      '''
      SELECT COUNT(*)
      FROM repairs r
      WHERE COALESCE(r.total_paid_amount,r.paidAmount,0) > 0.01
        AND NOT EXISTS(
          SELECT 1
          FROM payments p
          WHERE COALESCE(p.isIncome,1)=1
            AND (
              p.repair_id=r.id
              OR (COALESCE(p.repair_id,'')='' AND p.relatedRepairId=r.id)
            )
        )
      ''',
    );

    items.add(
      DataHealthItem(
        id: 'legacy_repair_payment_evidence',
        title: 'دفعات Repair تاريخية بلا Payment rows',
        message: legacyRepairPaymentEvidence == 0
            ? 'لا توجد دفعات تاريخية تعتمد على cache فقط.'
            : 'يوجد $legacyRepairPaymentEvidence Repair يحتوي مبلغًا مدفوعًا '
                'قديمًا بلا Payment rows. لا يتم تصفيره أو اختلاق سند قبض تلقائيًا.',
        status: legacyRepairPaymentEvidence == 0
            ? DataHealthStatus.pass
            : DataHealthStatus.warning,
        affected: legacyRepairPaymentEvidence,
      ),
    );

    final repairArReconciliation = await db.rawQuery(
      '''
      WITH paid AS (
        SELECT repair_id, 1 AS payment_count, paid FROM (${RepairFinancialTruthService.paidByRepairSql})
      ),
      ar AS (
        SELECT
          l.repair_id,
          SUM(l.debit-l.credit) AS balance
        FROM gl_lines l
        LEFT JOIN accounts a ON a.id=l.account_id
        WHERE l.repair_id IS NOT NULL
          AND (
            a.code LIKE '1200.C%'
            OR UPPER(COALESCE(l.party_type,'')) IN ('CLIENT','CUSTOMER')
          )
        GROUP BY l.repair_id
      )
      SELECT
        COUNT(*) AS c,
        COALESCE(SUM(ABS(
          (COALESCE(r.fileValue,0)-COALESCE(p.paid,0))
          - COALESCE(ar.balance,0)
        )),0) AS amount
      FROM repairs r
      LEFT JOIN paid p ON p.repair_id=r.id
      LEFT JOIN ar ON ar.repair_id=r.id
      WHERE ABS(
        (COALESCE(r.fileValue,0)-COALESCE(p.paid,0))
        - COALESCE(ar.balance,0)
      ) > 0.01
      ''',
    );

    final repairArMismatchCount = _asInt(repairArReconciliation.first['c']);
    final repairArMismatchAmount =
        _asDouble(repairArReconciliation.first['amount']);

    items.add(
      DataHealthItem(
        id: 'repair_ar_reconciliation',
        title: 'مطابقة Repair مع ذمم GL',
        message: repairArMismatchCount == 0
            ? 'قيمة كل Repair ناقص مدفوعاته تطابق رصيد AR المرتبط به في GL.'
            : 'يوجد $repairArMismatchCount Repair لا يطابق رصيده المالي في GL. '
                'لا يتم إصلاح هذا الفرق تلقائيًا؛ يلزم Reversal/Adjustment رسمي.',
        status: repairArMismatchCount == 0
            ? DataHealthStatus.pass
            : DataHealthStatus.error,
        affected: repairArMismatchCount,
        amount: repairArMismatchCount == 0 ? null : repairArMismatchAmount,
      ),
    );

    final missingSupplierAccounts = await _firstInt(
      db,
      '''
      SELECT COUNT(*)
      FROM suppliers s
      WHERE NOT EXISTS(
        SELECT 1
        FROM accounts a
        WHERE a.code = printf('2200.S%04d', s.id)
      )
      ''',
    );

    items.add(
      _zeroIsPass(
        id: 'supplier_account_mapping',
        title: 'حسابات الموردين',
        count: missingSupplierAccounts,
        okMessage: 'كل مورد لديه حساب AP أساسي 2200.S####.',
        issueMessage: 'يوجد مورد بلا حساب AP أساسي ويمكن إنشاؤه بأمان.',
        issueStatus: DataHealthStatus.repairable,
      ),
    );

    final legacySupplierNet = await db.rawQuery(
      '''
      SELECT
        COUNT(*) AS accounts_with_balance,
        COALESCE(SUM(ABS(balance)),0) AS amount
      FROM (
        SELECT
          a.id,
          COALESCE(SUM(l.credit-l.debit),0) AS balance
        FROM accounts a
        LEFT JOIN gl_lines l ON l.account_id=a.id
        WHERE a.code LIKE '2000.S%'
           OR a.code LIKE '2200.SS%'
        GROUP BY a.id
        HAVING ABS(COALESCE(SUM(l.credit-l.debit),0)) > 0.01
      )
      ''',
    );

    final legacySupplierBalanceCount =
        _asInt(legacySupplierNet.first['accounts_with_balance']);
    final legacySupplierAmount = _asDouble(legacySupplierNet.first['amount']);

    items.add(
      DataHealthItem(
        id: 'legacy_supplier_balance',
        title: 'أرصدة حسابات الموردين القديمة',
        message: legacySupplierBalanceCount == 0
            ? 'الحسابات القديمة محتفظ بها تاريخيًا لكن صافيها صفر.'
            : 'يوجد رصيد متبقٍ في حساب مورد قديم خارج 2200.S####.',
        status: legacySupplierBalanceCount == 0
            ? DataHealthStatus.pass
            : DataHealthStatus.error,
        affected: legacySupplierBalanceCount,
        amount: legacySupplierBalanceCount == 0 ? null : legacySupplierAmount,
      ),
    );

    final supplierAdvances = await db.rawQuery(
      '''
      SELECT
        COUNT(*) AS c,
        COALESCE(SUM(ABS(balance)),0) AS amount
      FROM (
        SELECT
          a.id,
          COALESCE(SUM(l.credit-l.debit),0) AS balance
        FROM accounts a
        LEFT JOIN gl_lines l ON l.account_id=a.id
        WHERE a.code GLOB '2200.S[0-9][0-9][0-9][0-9]'
        GROUP BY a.id
        HAVING COALESCE(SUM(l.credit-l.debit),0) < -0.01
      )
      ''',
    );

    final advanceCount = _asInt(supplierAdvances.first['c']);
    final advanceAmount = _asDouble(supplierAdvances.first['amount']);

    items.add(
      DataHealthItem(
        id: 'supplier_advances',
        title: 'دفعات مقدمة للموردين',
        message: advanceCount == 0
            ? 'لا توجد أرصدة مدينة على حسابات الموردين.'
            : 'يوجد $advanceCount مورد برصيد مدين. يعامل كدفعة مقدمة '
                'ولا يُمسح تلقائيًا.',
        status: advanceCount == 0
            ? DataHealthStatus.pass
            : DataHealthStatus.warning,
        affected: advanceCount,
        amount: advanceCount == 0 ? null : advanceAmount,
      ),
    );

    final settlementOrphans = await _firstInt(
      db,
      '''
      SELECT COUNT(*)
      FROM invoice_settlements s
      LEFT JOIN vouchers v ON v.id=s.voucher_id
      LEFT JOIN purchase_invoices i
        ON CAST(i.id AS TEXT)=CAST(s.invoice_id AS TEXT)
      WHERE v.id IS NULL OR i.id IS NULL
      ''',
    );

    items.add(
      _zeroIsPass(
        id: 'invoice_settlements',
        title: 'تسويات فواتير الموردين',
        count: settlementOrphans,
        okMessage: 'لا توجد Settlement يتيمة.',
        issueMessage: 'يوجد Settlement يشير إلى سند أو فاتورة غير موجودة.',
        issueStatus: DataHealthStatus.error,
      ),
    );

    final settlementType = await _settlementInvoiceIdType(db);

    items.add(
      DataHealthItem(
        id: 'settlement_schema',
        title: 'نوع معرف فاتورة المشتريات في Settlement',
        message: settlementType == 'TEXT'
            ? 'invoice_settlements.invoice_id يستخدم TEXT/UUID.'
            : 'invoice_id معلن كـ$settlementType ويجب توحيده إلى TEXT.',
        status: settlementType == 'TEXT'
            ? DataHealthStatus.pass
            : DataHealthStatus.repairable,
        affected: settlementType == 'TEXT' ? 0 : 1,
      ),
    );

    final chequeCacheMismatch = await _chequeDocumentCacheMismatch(db);
    final chequeMissingInstrument = await _chequeDocumentMissingInstrument(db);
    final orphanChequeSource = await _orphanChequeSources(db);

    items.add(
      _zeroIsPass(
        id: 'cheque_document_cache',
        title: 'ربط مستندات الشيك',
        count: chequeCacheMismatch,
        okMessage: 'cheque_id متطابق مع سجل الشيك المرتبط.',
        issueMessage: 'يوجد Cheque موجود لكن cheque_id في المستند غير متزامن.',
        issueStatus: DataHealthStatus.repairable,
      ),
    );

    items.add(
      _zeroIsPass(
        id: 'cheque_document_integrity',
        title: 'سلامة مستندات الشيك',
        count: chequeMissingInstrument + orphanChequeSource,
        okMessage: 'كل مستند Cheque مرتبط بأداة مالية حقيقية والعكس.',
        issueMessage: 'يوجد مستند Cheque بلا سجل شيك أو شيك بلا مستند أصلي.',
        issueStatus: DataHealthStatus.error,
      ),
    );

    final incompleteCheques = await _firstInt(
      db,
      '''
      SELECT COUNT(*)
      FROM cheques
      WHERE COALESCE(is_legacy_incomplete,0)=1
      ''',
    );

    items.add(
      DataHealthItem(
        id: 'legacy_incomplete_cheques',
        title: 'شيكات تاريخية ناقصة البيانات',
        message: incompleteCheques == 0
            ? 'كل الشيكات تحتوي بيانات تشغيلية مكتملة.'
            : 'يوجد $incompleteCheques شيك تاريخي مستعاد يحتاج استكمال '
                'الرقم والبنك/الاستحقاق قبل أي حركة لاحقة.',
        status: incompleteCheques == 0
            ? DataHealthStatus.pass
            : DataHealthStatus.warning,
        affected: incompleteCheques,
      ),
    );

    final repairHistoryNet = await _firstInt(
      db,
      '''
      SELECT COUNT(*)
      FROM (
        SELECT a.id
        FROM gl_lines l
        JOIN gl_entries e ON e.id=l.entry_id
        JOIN accounts a ON a.id=l.account_id
        WHERE e.source IN ('REPAIR_REV','REPAIR_ADJ','P0_REPAIR_FIX')
        GROUP BY a.id
        HAVING ABS(SUM(l.debit-l.credit)) > 0.01
      )
      ''',
    );

    items.add(
      _zeroIsPass(
        id: 'repair_history_neutralization',
        title: 'تحييد تعديلات Repair التاريخية',
        count: repairHistoryNet,
        okMessage: 'أثر REPAIR_REV/REPAIR_ADJ التاريخي محيّد محاسبيًا.',
        issueMessage: 'التعديلات التاريخية لملفات الإصلاح ما زال لها أثر صافٍ.',
        issueStatus: DataHealthStatus.error,
      ),
    );

    return DataHealthReport(
      generatedAt: DateTime.now(),
      dbVersion: version,
      items: List.unmodifiable(items),
    );
  }

  DataHealthItem _zeroIsPass({
    required String id,
    required String title,
    required int count,
    required String okMessage,
    required String issueMessage,
    required DataHealthStatus issueStatus,
  }) {
    return DataHealthItem(
      id: id,
      title: title,
      message: count == 0 ? okMessage : issueMessage,
      status: count == 0 ? DataHealthStatus.pass : issueStatus,
      affected: count,
    );
  }

  Future<int> _firstInt(
    DatabaseExecutor db,
    String sql, [
    List<Object?>? args,
  ]) async {
    final rows = await db.rawQuery(sql, args);
    if (rows.isEmpty || rows.first.isEmpty) return 0;
    return _asInt(rows.first.values.first);
  }

  int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  double _round2(double value) => double.parse(value.toStringAsFixed(2));

  List<Map<String, dynamic>>? _decodeRepairItems(Object? raw) {
    if (raw == null) return <Map<String, dynamic>>[];

    Object? decoded = raw;

    if (raw is String) {
      final text = raw.trim();
      if (text.isEmpty) return <Map<String, dynamic>>[];

      try {
        decoded = jsonDecode(text);
      } catch (_) {
        return null;
      }
    }

    if (decoded is! List) return null;

    final result = <Map<String, dynamic>>[];

    for (final item in decoded) {
      if (item is! Map) return null;
      result.add(Map<String, dynamic>.from(item));
    }

    return result;
  }

  Map<String, dynamic>? _normalizeRepairItem(
    Map<String, dynamic> item,
  ) {
    final name = (item['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;

    var qty = _asDouble(item['qty']);
    if (qty <= 0) qty = 1.0;

    final rawPrice = item['price'] ?? item['amount'] ?? item['cost'];
    final price = _asDouble(rawPrice);

    if (price < 0) {
      throw StateError('Negative Repair line price: $name');
    }

    return {
      ...item,
      'name': name,
      'qty': qty,
      'price': price,
      'total': _round2(qty * price),
    };
  }

  Future<_RepairDetailAudit> _auditRepairDetails(
    DatabaseExecutor db,
  ) async {
    final repairs = await db.query(
      'repairs',
      columns: ['id', 'parts', 'works', 'fileValue'],
    );

    final lineSummaryRows = await db.rawQuery(
      '''
      SELECT
        repair_id,
        COUNT(*) AS c,
        COALESCE(SUM(total),0) AS total
      FROM repair_lines
      GROUP BY repair_id
      ''',
    );

    final lineSummary = <String, Map<String, Object?>>{
      for (final row in lineSummaryRows) row['repair_id'].toString(): row,
    };

    var cacheMismatchCount = 0;
    var fileValueMismatchCount = 0;
    var fileValueMismatchAmount = 0.0;
    var malformedCount = 0;

    for (final repair in repairs) {
      final repairId = repair['id']?.toString() ?? '';
      if (repairId.isEmpty) {
        malformedCount++;
        continue;
      }

      final parts = _decodeRepairItems(repair['parts']);
      final works = _decodeRepairItems(repair['works']);

      if (parts == null || works == null) {
        malformedCount++;
        continue;
      }

      try {
        final normalized = <Map<String, dynamic>>[];

        for (final item in parts) {
          final value = _normalizeRepairItem(item);
          if (value != null) normalized.add(value);
        }

        for (final item in works) {
          final value = _normalizeRepairItem(item);
          if (value != null) normalized.add(value);
        }

        final canonicalCount = normalized.length;
        final canonicalTotal = _round2(
          normalized.fold<double>(
            0.0,
            (sum, item) => sum + _asDouble(item['total']),
          ),
        );

        final summary = lineSummary[repairId];
        final lineCount = _asInt(summary?['c']);
        final lineTotal = _round2(_asDouble(summary?['total']));

        if (lineCount != canonicalCount ||
            (lineTotal - canonicalTotal).abs() > 0.01) {
          cacheMismatchCount++;
        }

        final fileValue = _round2(_asDouble(repair['fileValue']));
        if ((fileValue - canonicalTotal).abs() > 0.01) {
          fileValueMismatchCount++;
          fileValueMismatchAmount += (fileValue - canonicalTotal).abs();
        }
      } catch (_) {
        malformedCount++;
      }
    }

    return _RepairDetailAudit(
      cacheMismatchCount: cacheMismatchCount,
      fileValueMismatchCount: fileValueMismatchCount,
      fileValueMismatchAmount: _round2(fileValueMismatchAmount),
      malformedCount: malformedCount,
    );
  }

  Future<String> _settlementInvoiceIdType(
    DatabaseExecutor db,
  ) async {
    final table = await db.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type='table' AND name='invoice_settlements'",
    );

    if (table.isEmpty) return 'MISSING';

    final info = await db.rawQuery(
      'PRAGMA table_info(invoice_settlements)',
    );

    for (final column in info) {
      if (column['name']?.toString() == 'invoice_id') {
        return (column['type'] ?? '').toString().toUpperCase();
      }
    }

    return 'MISSING';
  }

  Future<int> _chequeDocumentCacheMismatch(
    DatabaseExecutor db,
  ) async {
    return _firstInt(
      db,
      '''
      SELECT
        (SELECT COUNT(*)
         FROM vouchers v
         JOIN cheques c
           ON c.source_type='VOUCHER' AND c.source_id=v.id
         WHERE LOWER(COALESCE(v.method,''))='cheque'
           AND CAST(COALESCE(v.cheque_id,'0') AS INTEGER) <> c.id)
        +
        (SELECT COUNT(*)
         FROM payments p
         JOIN cheques c
           ON c.source_type='PAYMENT' AND c.source_id=p.id
         WHERE LOWER(COALESCE(p.method,''))='cheque'
           AND COALESCE(p.cheque_id,0) <> c.id)
      ''',
    );
  }

  Future<int> _chequeDocumentMissingInstrument(
    DatabaseExecutor db,
  ) async {
    return _firstInt(
      db,
      '''
      SELECT
        (SELECT COUNT(*)
         FROM vouchers v
         WHERE LOWER(COALESCE(v.method,''))='cheque'
           AND NOT EXISTS(
             SELECT 1 FROM cheques c
             WHERE c.source_type='VOUCHER' AND c.source_id=v.id
           ))
        +
        (SELECT COUNT(*)
         FROM payments p
         WHERE LOWER(COALESCE(p.method,''))='cheque'
           AND NOT EXISTS(
             SELECT 1 FROM cheques c
             WHERE c.source_type='PAYMENT' AND c.source_id=p.id
           ))
      ''',
    );
  }

  Future<int> _orphanChequeSources(
    DatabaseExecutor db,
  ) async {
    return _firstInt(
      db,
      '''
      SELECT COUNT(*)
      FROM cheques c
      WHERE
        (c.source_type='VOUCHER'
         AND NOT EXISTS(
           SELECT 1 FROM vouchers v WHERE v.id=c.source_id
         ))
        OR
        (c.source_type='PAYMENT'
         AND NOT EXISTS(
           SELECT 1 FROM payments p WHERE p.id=c.source_id
         ))
      ''',
    );
  }

  Future<int> _repairInvoicePostingCache(
    DatabaseExecutor db,
  ) async {
    return db.rawUpdate(
      '''
      UPDATE invoices
      SET
        gl_entry_id = (
          SELECT e.id
          FROM gl_entries e
          WHERE e.source='INVOICE' AND e.source_id=invoices.id
          LIMIT 1
        ),
        post_to_gl = CASE
          WHEN EXISTS(
            SELECT 1 FROM gl_entries e
            WHERE e.source='INVOICE' AND e.source_id=invoices.id
          ) THEN 1 ELSE 0 END
      WHERE
        COALESCE(gl_entry_id,0) <>
          COALESCE((
            SELECT e.id
            FROM gl_entries e
            WHERE e.source='INVOICE' AND e.source_id=invoices.id
            LIMIT 1
          ),0)
        OR COALESCE(post_to_gl,0) <>
          CASE WHEN EXISTS(
            SELECT 1 FROM gl_entries e
            WHERE e.source='INVOICE' AND e.source_id=invoices.id
          ) THEN 1 ELSE 0 END
      ''',
    );
  }

  Future<int> _repairVoucherPostingCache(
    DatabaseExecutor db,
  ) async {
    return db.rawUpdate(
      '''
      UPDATE vouchers
      SET
        gl_entry_id = (
          SELECT e.id
          FROM gl_entries e
          WHERE e.source='VOUCHER' AND e.source_id=vouchers.id
          LIMIT 1
        ),
        is_posted = CASE
          WHEN EXISTS(
            SELECT 1 FROM gl_entries e
            WHERE e.source='VOUCHER' AND e.source_id=vouchers.id
          ) THEN 1 ELSE 0 END
      WHERE
        COALESCE(gl_entry_id,0) <>
          COALESCE((
            SELECT e.id
            FROM gl_entries e
            WHERE e.source='VOUCHER' AND e.source_id=vouchers.id
            LIMIT 1
          ),0)
        OR COALESCE(is_posted,0) <>
          CASE WHEN EXISTS(
            SELECT 1 FROM gl_entries e
            WHERE e.source='VOUCHER' AND e.source_id=vouchers.id
          ) THEN 1 ELSE 0 END
      ''',
    );
  }

  Future<int> _repairPaymentPostingCache(
    DatabaseExecutor db,
  ) async {
    return db.rawUpdate(
      '''
      UPDATE payments
      SET gl_entry_id = (
        SELECT e.id
        FROM gl_entries e
        WHERE e.source='PAYMENT' AND e.source_id=payments.id
        LIMIT 1
      )
      WHERE EXISTS(
        SELECT 1 FROM gl_entries e
        WHERE e.source='PAYMENT' AND e.source_id=payments.id
      )
      AND COALESCE(gl_entry_id,0) <>
          COALESCE((
            SELECT e.id
            FROM gl_entries e
            WHERE e.source='PAYMENT' AND e.source_id=payments.id
            LIMIT 1
          ),0)
      ''',
    );
  }

  Future<int> _repairRepairInvoiceCache(
    DatabaseExecutor db,
  ) async {
    final updated = await db.rawUpdate(
      '''
      UPDATE repairs
      SET invoice_id = (
        SELECT i.id
        FROM invoices i
        WHERE i.repair_id=repairs.id
        LIMIT 1
      )
      WHERE EXISTS(
        SELECT 1 FROM invoices i WHERE i.repair_id=repairs.id
      )
      AND COALESCE(invoice_id,'') <>
          COALESCE((
            SELECT i.id
            FROM invoices i
            WHERE i.repair_id=repairs.id
            LIMIT 1
          ),'')
      ''',
    );

    final columns = await db.rawQuery('PRAGMA table_info(repairs)');
    final hasLegacy = columns.any(
      (column) => column['name']?.toString() == 'invoiceId',
    );

    if (hasLegacy) {
      await db.rawUpdate(
        '''
        UPDATE repairs
        SET invoiceId=invoice_id
        WHERE COALESCE(invoice_id,'')<>''
          AND COALESCE(invoiceId,'')<>COALESCE(invoice_id,'')
        ''',
      );
    }

    return updated;
  }

  Future<int> _repairMissingSupplierAccounts(
    DatabaseExecutor db,
  ) async {
    final suppliers = await db.rawQuery(
      '''
      SELECT s.id, s.name
      FROM suppliers s
      WHERE NOT EXISTS(
        SELECT 1 FROM accounts a
        WHERE a.code=printf('2200.S%04d',s.id)
      )
      ''',
    );

    var created = 0;
    final now = DateTime.now().toIso8601String();

    for (final supplier in suppliers) {
      final id = _asInt(supplier['id']);
      if (id <= 0) continue;

      final result = await db.insert(
        'accounts',
        {
          'code': '2200.S${id.toString().padLeft(4, '0')}',
          'name': supplier['name']?.toString() ?? 'Supplier $id',
          'type': 'LIABILITY',
          'normal_balance': 'CREDIT',
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      if (result > 0) created++;
    }

    return created;
  }

  Future<int> _repairChequeDocumentLinks(
    DatabaseExecutor db,
  ) async {
    var changed = 0;

    changed += await db.rawUpdate(
      '''
      UPDATE vouchers
      SET cheque_id=CAST((
        SELECT c.id
        FROM cheques c
        WHERE c.source_type='VOUCHER' AND c.source_id=vouchers.id
        LIMIT 1
      ) AS TEXT)
      WHERE LOWER(COALESCE(method,''))='cheque'
        AND EXISTS(
          SELECT 1 FROM cheques c
          WHERE c.source_type='VOUCHER' AND c.source_id=vouchers.id
        )
        AND CAST(COALESCE(cheque_id,'0') AS INTEGER) <>
            COALESCE((
              SELECT c.id
              FROM cheques c
              WHERE c.source_type='VOUCHER' AND c.source_id=vouchers.id
              LIMIT 1
            ),0)
      ''',
    );

    changed += await db.rawUpdate(
      '''
      UPDATE payments
      SET cheque_id=(
        SELECT c.id
        FROM cheques c
        WHERE c.source_type='PAYMENT' AND c.source_id=payments.id
        LIMIT 1
      )
      WHERE LOWER(COALESCE(method,''))='cheque'
        AND EXISTS(
          SELECT 1 FROM cheques c
          WHERE c.source_type='PAYMENT' AND c.source_id=payments.id
        )
        AND COALESCE(cheque_id,0) <>
            COALESCE((
              SELECT c.id
              FROM cheques c
              WHERE c.source_type='PAYMENT' AND c.source_id=payments.id
              LIMIT 1
            ),0)
      ''',
    );

    return changed;
  }

  Future<int> _repairRepairPaymentCaches(
    DatabaseExecutor db,
  ) async {
    final rows = await db.rawQuery('''
      WITH paid AS (
        SELECT repair_id, 1 AS payment_count, paid FROM (${RepairFinancialTruthService.paidByRepairSql})
      )
      SELECT
        r.id,
        COALESCE(r.fileValue,0) AS file_value,
        COALESCE(p.paid,0) AS paid
      FROM repairs r
      LEFT JOIN paid p ON p.repair_id=r.id
      WHERE COALESCE(p.payment_count,0) > 0
        AND (
          ABS(COALESCE(r.total_paid_amount,0)-COALESCE(p.paid,0)) > 0.01
         OR ABS(COALESCE(r.paidAmount,0)-COALESCE(p.paid,0)) > 0.01
         OR COALESCE(r.paymentStatus,'') <>
            CASE
              WHEN COALESCE(r.fileValue,0) <= 0.005 THEN 'مسدد'
              WHEN COALESCE(p.paid,0) <= 0.005 THEN 'غير مسدد'
              WHEN COALESCE(p.paid,0)+0.005 >= COALESCE(r.fileValue,0) THEN 'مسدد'
              ELSE 'مسدد جزئي'
            END
        )
    ''');

    var changed = 0;
    for (final row in rows) {
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final fileValue = _asDouble(row['file_value']);
      final paid = _round2(_asDouble(row['paid']));
      final status = fileValue <= 0.005
          ? 'مسدد'
          : paid <= 0.005
              ? 'غير مسدد'
              : paid + 0.005 >= fileValue
                  ? 'مسدد'
                  : 'مسدد جزئي';
      changed += await db.update(
        'repairs',
        {
          'paidAmount': paid,
          'total_paid_amount': paid,
          'paymentStatus': status,
        },
        where: 'id=?',
        whereArgs: [id],
      );
    }
    return changed;
  }

  Future<int> _repairRepairDetailCaches(
    DatabaseExecutor db,
  ) async {
    final audit = await _auditRepairDetails(db);

    if (audit.malformedCount > 0) {
      return 0;
    }

    if (audit.cacheMismatchCount == 0) {
      return 0;
    }

    final repairs = await db.query(
      'repairs',
      columns: ['id', 'parts', 'works', 'created_at'],
    );

    var repaired = 0;

    for (final repair in repairs) {
      final repairId = repair['id']?.toString() ?? '';
      if (repairId.isEmpty) continue;

      final parts = _decodeRepairItems(repair['parts']);
      final works = _decodeRepairItems(repair['works']);
      if (parts == null || works == null) continue;

      final normalizedParts = <Map<String, dynamic>>[];
      final normalizedWorks = <Map<String, dynamic>>[];

      try {
        for (final item in parts) {
          final normalized = _normalizeRepairItem(item);
          if (normalized != null) normalizedParts.add(normalized);
        }

        for (final item in works) {
          final normalized = _normalizeRepairItem(item);
          if (normalized != null) normalizedWorks.add(normalized);
        }
      } catch (_) {
        continue;
      }

      final expectedCount = normalizedParts.length + normalizedWorks.length;
      final expectedTotal = _round2(
        [...normalizedParts, ...normalizedWorks].fold<double>(
          0.0,
          (sum, item) => sum + _asDouble(item['total']),
        ),
      );

      final current = await db.rawQuery(
        '''
        SELECT COUNT(*) AS c, COALESCE(SUM(total),0) AS total
        FROM repair_lines
        WHERE repair_id=?
        ''',
        [repairId],
      );

      final currentCount = _asInt(current.first['c']);
      final currentTotal = _round2(_asDouble(current.first['total']));

      if (currentCount == expectedCount &&
          (currentTotal - expectedTotal).abs() <= 0.01) {
        continue;
      }

      await db.delete(
        'repair_lines',
        where: 'repair_id=?',
        whereArgs: [repairId],
      );

      Future<void> insertLines(
        String type,
        List<Map<String, dynamic>> lines,
      ) async {
        for (var index = 0; index < lines.length; index++) {
          final line = lines[index];

          await db.insert(
            'repair_lines',
            {
              'id': '$repairId:$type:$index',
              'repair_id': repairId,
              'line_type': type,
              'name': line['name'],
              'qty': line['qty'],
              'price': line['price'],
              'total': line['total'],
              'notes': line['notes'],
              'created_at': repair['created_at'],
            },
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
      }

      await insertLines('part', normalizedParts);
      await insertLines('work', normalizedWorks);

      await db.update(
        'repairs',
        {
          'parts': jsonEncode(normalizedParts),
          'works': jsonEncode(normalizedWorks),
        },
        where: 'id=?',
        whereArgs: [repairId],
      );

      repaired++;
    }

    return repaired;
  }

  Future<int> _repairSettlementSchema(
    DatabaseExecutor db,
  ) async {
    final type = await _settlementInvoiceIdType(db);
    if (type == 'TEXT') return 0;

    final table = await db.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type='table' AND name='invoice_settlements'",
    );

    if (table.isEmpty) {
      await _createSettlementTable(db);
      return 1;
    }

    await db.execute('DROP TABLE IF EXISTS invoice_settlements_health;');

    await db.execute(
      '''
      CREATE TABLE invoice_settlements_health (
        id TEXT PRIMARY KEY,
        supplier_id INTEGER NOT NULL,
        invoice_id TEXT NOT NULL,
        voucher_id TEXT NOT NULL,
        amount_applied REAL NOT NULL,
        created_at TEXT
      )
      ''',
    );

    await db.execute(
      '''
      INSERT INTO invoice_settlements_health(
        id,
        supplier_id,
        invoice_id,
        voucher_id,
        amount_applied,
        created_at
      )
      SELECT
        id,
        supplier_id,
        CAST(invoice_id AS TEXT),
        voucher_id,
        amount_applied,
        created_at
      FROM invoice_settlements
      ''',
    );

    await db.execute('DROP TABLE invoice_settlements;');
    await db.execute(
      'ALTER TABLE invoice_settlements_health '
      'RENAME TO invoice_settlements',
    );

    await _createSettlementIndexes(db);
    return 1;
  }

  Future<void> _createSettlementTable(
    DatabaseExecutor db,
  ) async {
    await db.execute(
      '''
      CREATE TABLE IF NOT EXISTS invoice_settlements (
        id TEXT PRIMARY KEY,
        supplier_id INTEGER NOT NULL,
        invoice_id TEXT NOT NULL,
        voucher_id TEXT NOT NULL,
        amount_applied REAL NOT NULL,
        created_at TEXT
      )
      ''',
    );

    await _createSettlementIndexes(db);
  }

  Future<void> _createSettlementIndexes(
    DatabaseExecutor db,
  ) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_settlements_supplier '
      'ON invoice_settlements(supplier_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_settlements_invoice '
      'ON invoice_settlements(invoice_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_settlements_voucher '
      'ON invoice_settlements(voucher_id)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_settlements_voucher_invoice '
      'ON invoice_settlements(voucher_id, invoice_id)',
    );
  }

  Future<String> _createBackup(Database db) async {
    final downloads = await _downloadsDirectory();
    final backupDir = Directory(
      '${downloads.path}${Platform.pathSeparator}'
      'Yalla_Backups${Platform.pathSeparator}DataHealth',
    );

    if (!backupDir.existsSync()) {
      backupDir.createSync(recursive: true);
    }

    final backupPath = '${backupDir.path}${Platform.pathSeparator}'
        'yalla_accounts_health_${_fileStamp(DateTime.now())}.db';

    await DatabasePlatformPolicy.checkpoint(db, mode: 'FULL');

    final escapedBackupPath = backupPath.replaceAll("'", "''");

    try {
      await db.execute("VACUUM INTO '$escapedBackupPath'");
    } catch (_) {
      await DatabasePlatformPolicy.checkpoint(db);
      final sourcePath = await DatabaseConstants.dbFilePath();
      await File(sourcePath).copy(backupPath);
    }

    return backupPath;
  }

  Future<Directory> _downloadsDirectory() async {
    final userProfile = Platform.environment['USERPROFILE'];

    if (userProfile != null && userProfile.trim().isNotEmpty) {
      return Directory(
        '$userProfile${Platform.pathSeparator}Downloads',
      );
    }

    final dbPath = await DatabaseConstants.dbFilePath();
    return File(dbPath).parent;
  }

  String _fileStamp(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');

    return '${value.year}'
        '${two(value.month)}'
        '${two(value.day)}_'
        '${two(value.hour)}'
        '${two(value.minute)}'
        '${two(value.second)}';
  }
}
