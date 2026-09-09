import 'dart:math' as math;
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/finance/services/financial_overview_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';
import 'package:yalla_accounts/features/settings/services/workshop_settings_service.dart';
import 'package:yalla_accounts/features/settings/services/commercial_settings_service.dart';

enum DashboardPeriod {
  today('اليوم'),
  week('الأسبوع'),
  month('الشهر');

  const DashboardPeriod(this.label);
  final String label;
  DateTime start(DateTime now) {
    final day = DateTime(now.year, now.month, now.day);
    return switch (this) {
      today => day,
      week => day.subtract(Duration(days: now.weekday % 7)),
      month => DateTime(now.year, now.month),
    };
  }
}

class DashboardStep {
  const DashboardStep(
      this.id, this.title, this.reason, this.impact, this.action, this.route,
      {this.repairId, this.priority = 0});
  final String id, title, reason, impact, action, route;
  final String? repairId;
  final int priority;
}

class DashboardCar {
  const DashboardCar(this.id, this.name, this.stage, this.since, this.remaining,
      this.value, this.cost, this.insurance);
  final String id, name, stage;
  final DateTime? since;
  final double remaining, value, cost;
  final bool insurance;
  bool get ready => stage == 'جاهز للتسليم';
}

class DailyDashboardData {
  const DailyDashboardData(
      {required this.name,
      this.logo,
      required this.currency,
      required this.today,
      required this.period,
      required this.cars,
      required this.newFiles,
      required this.previousFiles,
      required this.materials,
      required this.issues,
      required this.now,
      this.lastEntry,
      this.recentFiles = const []});
  final String name, currency;
  final String? logo;
  final FinancialOverviewSnapshot today, period;
  final List<DashboardCar> cars;
  final List<Map<String, Object?>> recentFiles;
  final int newFiles, previousFiles;
  final List<String> materials;
  final List<DashboardStep> issues;
  final DateTime now;
  final Map<String, Object?>? lastEntry;
  double get readyAmount =>
      cars.where((c) => c.ready).fold(0, (n, c) => n + c.remaining);
  String money(double value) =>
      '${NumberFormat('#,##0.##').format(value)} $currency';
}

/// Read-only dashboard projection. Cash and liabilities use the existing GL
/// overview; repair balances use the canonical receipt SQL, never paid caches.
class DailyDashboardService {
  static Future<DailyDashboardData> load(DashboardPeriod period) async {
    final settings = await WorkshopSettingsService.instance.getSettings();
    final currency = await CommercialSettingsService.instance.get();
    final db = await DBService.database;
    return db.transaction((tx) => loadOn(tx, period, DateTime.now(),
        name: settings?.workshopName ?? 'ورشتي',
        logo: settings?.logoPath,
        currency: currency.currencySymbol));
  }

  static String stage(String? workflow, String legacy) {
    if (workflow == null || workflow.isEmpty) {
      if (legacy == 'جاهزة للتسليم') return 'جاهز للتسليم';
      if (legacy == 'تم التسليم') return 'تم التسليم';
      return legacy.isEmpty ? 'استلام وتقدير' : legacy;
    }
    return switch (workflow) {
      'DRAFT' || 'SENT' || 'APPROVED' => 'استلام وتقدير',
      'WORK_ORDER' || 'IN_PROGRESS' => 'قيد العمل',
      'READY_FOR_QC' || 'QC_CHECKED' || 'FINAL_QC' => 'فحص الجودة',
      'READY_FOR_DELIVERY' => 'جاهز للتسليم',
      'DELIVERED' || 'CLOSED' => 'تم التسليم',
      'REJECTED' => 'عرض مرفوض',
      _ => 'تحتاج مراجعة المرحلة',
    };
  }

  static Future<DailyDashboardData> loadOn(
      DatabaseExecutor db, DashboardPeriod selected, DateTime now,
      {String name = 'ورشتي', String? logo, String currency = '₪'}) async {
    final start = selected.start(now);
    final day = DashboardPeriod.today.start(now);
    final end = day.add(const Duration(days: 1));
    final finance =
        await FinancialOverviewService.loadOn(db, from: start, to: now);
    final today = selected == DashboardPeriod.today
        ? finance
        : await FinancialOverviewService.loadOn(db, from: day, to: now);
    final tables =
        (await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
            .map((row) => row['name'])
            .toSet();
    // These optional modules create their own tables on first use. Do not
    // create schema or pretend missing cost data is a known expense.
    final costs = tables.contains('repair_cost_entries')
        ? "SELECT repair_id,SUM(total_cost) AS cost FROM repair_cost_entries WHERE status='ACTIVE' GROUP BY repair_id"
        : 'SELECT NULL AS repair_id, 0 AS cost WHERE 0';
    final rows = await db.rawQuery('''
      SELECT r.*, w.stage AS workflow_stage, w.updated_at AS stage_updated,
        COALESCE(p.paid,0) AS canonical_paid,
        COALESCE(c.cost,0) AS direct_cost
      FROM repairs r LEFT JOIN repair_workflow w ON w.repair_id=r.id
      LEFT JOIN (${RepairFinancialTruthService.paidByRepairSql}) p ON p.repair_id=r.id
      LEFT JOIN ($costs) c ON c.repair_id=r.id
      WHERE COALESCE(r.isArchived,0)=0 AND UPPER(COALESCE(r.status,'')) NOT IN ('CANCELLED','VOID')
        AND substr(r.receivedDate,1,10) < substr(?,1,10)
    ''', [end.toIso8601String()]);
    double d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    final cars = rows
        .map((r) => DashboardCar(
            '${r['id']}',
            [r['beneficiaryName'], r['vehicleNumber']]
                .where((v) => v != null && '$v'.isNotEmpty)
                .join(' • '),
            stage(
                r['workflow_stage'] as String?, '${r['vehicleStatus'] ?? ''}'),
            DateTime.tryParse('${r['stage_updated'] ?? r['receivedDate']}'),
            math.max(0, d(r['fileValue']) - d(r['canonical_paid'])),
            d(r['fileValue']),
            d(r['direct_cost']),
            '${r['beneficiaryType']}'.contains('تأمين') ||
                '${r['beneficiaryType']}'.toLowerCase().contains('insurance')))
        .where((c) => c.stage != 'تم التسليم' && c.stage != 'عرض مرفوض')
        .toList();
    Future<int> count(DateTime from, DateTime to) async {
      final result = await db.rawQuery(
          "SELECT COUNT(*) n FROM repairs WHERE substr(receivedDate,1,10)>=substr(?,1,10) AND substr(receivedDate,1,10)<substr(?,1,10) AND UPPER(COALESCE(status,'')) NOT IN ('CANCELLED','VOID')",
          [from.toIso8601String(), to.toIso8601String()]);
      return (result.first['n'] as num).toInt();
    }

    final elapsed = end.difference(start);
    final newFiles = await count(start, end);
    final previousFiles = await count(start.subtract(elapsed), start);
    final materials = !tables.contains('raw_materials')
        ? <Map<String, Object?>>[]
        : await db.rawQuery(
            'SELECT name FROM raw_materials WHERE quantity<=0 ORDER BY name');
    final issues = <DashboardStep>[];
    final receipts = await db.rawQuery(
        "SELECT receipt_number FROM receipt_headers WHERE LOWER(status)='posted' AND allocated_amount=0 AND date>=? AND date<? LIMIT 1",
        [
          start.toIso8601String().substring(0, 10),
          end.toIso8601String().substring(0, 10)
        ]);
    if (receipts.isNotEmpty) {
      issues.add(DashboardStep(
          'unallocated',
          'راجع قبضًا غير موزع على ملف',
          'السند ${receipts.first['receipt_number']} مسجل على الحساب؛ قد يكون رصيدًا مقدمًا صحيحًا.',
          'تحقق من التخصيص قبل أي تعديل.',
          'افتح سندات القبض',
          AppRoutes.receiptVouchersList,
          priority: 58));
    }
    final vouchers = await db.rawQuery(
        "SELECT id FROM vouchers WHERE UPPER(status) NOT IN ('VOID','REVERSED','CANCELLED') AND (TRIM(COALESCE(party_type,''))='' OR TRIM(COALESCE(party_id,''))='') AND date>=? AND date<? LIMIT 1",
        [
          start.toIso8601String().substring(0, 10),
          end.toIso8601String().substring(0, 10)
        ]);
    if (vouchers.isNotEmpty) {
      issues.add(DashboardStep(
          'voucher',
          'راجع تصنيف وجهة سند الصرف',
          'السند ${vouchers.first['id']} تنقصه بيانات جهة أو تصنيف.',
          'يسهّل تتبع المصروف وتصحيحه.',
          'افتح سندات الصرف',
          AppRoutes.paymentVouchersList,
          priority: 68));
    }
    final invoices = await db.rawQuery(
        "SELECT i.id FROM purchase_invoices i WHERE UPPER(COALESCE(i.status,'')) NOT IN ('VOID','CANCELLED','REVERSED') AND (NOT EXISTS(SELECT 1 FROM suppliers s WHERE s.id=i.supplier_id) OR NOT EXISTS(SELECT 1 FROM purchase_invoice_lines l WHERE l.invoice_id=i.id)) LIMIT 1");
    if (invoices.isNotEmpty) {
      issues.add(DashboardStep(
          'invoice',
          'أكمل بيانات فاتورة شراء',
          'الفاتورة ${invoices.first['id']} تحتاج مراجعة المورد أو البنود.',
          'يمنع نقص معلومات التكلفة.',
          'افتح المشتريات',
          AppRoutes.purchasesList,
          priority: 65));
    }
    final recentFiles = await db.rawQuery("""
      SELECT id, vehicleType, vehicleModel, vehicleNumber, beneficiaryName,
        vehicleStatus, receivedDate
      FROM repairs
      WHERE UPPER(COALESCE(status,'')) NOT IN ('CANCELLED','VOID')
        AND substr(receivedDate,1,10) < substr(?,1,10)
      ORDER BY receivedDate DESC, id DESC LIMIT 5
    """, [end.toIso8601String()]);
    final last = await db.rawQuery(
        'SELECT id,date,ref,source_number,note,created_at FROM gl_entries ORDER BY COALESCE(created_at,date) DESC,id DESC LIMIT 1');
    return DailyDashboardData(
        name: name,
        logo: logo,
        currency: currency,
        today: today,
        period: finance,
        cars: cars,
        recentFiles: recentFiles,
        newFiles: newFiles,
        previousFiles: previousFiles,
        materials: materials.map((m) => '${m['name']}').toList(),
        issues: issues,
        now: now,
        lastEntry: last.isEmpty ? null : last.first);
  }

  /// Ranking favors immediate cash, urgency and a traceable document. No write
  /// action is performed here; all recommendations open existing review flows.
  static List<DashboardStep> recommendations(
      DailyDashboardData data, DashboardPeriod period) {
    final steps = <DashboardStep>[...data.issues];
    final ready =
        data.cars.where((c) => c.ready && c.remaining > 0.005).toList();
    if (ready.isNotEmpty) {
      steps.add(DashboardStep(
          'collect',
          'حصّل ${data.money(data.readyAmount)} من الملفات الجاهزة',
          'يوجد ${ready.length} ملف جاهز للتسليم وله مبلغ متبقٍ.',
          'يعزز السيولة ويخفف الذمم خلال ${period.label}.',
          'افتح الملفات',
          AppRoutes.repairs,
          repairId: ready.first.id,
          priority: 100));
    }
    final available = math.max(0.0, data.period.liquidFunds);
    if (data.period.supplierPayables > 0 && available > 0) {
      steps.add(DashboardStep(
          'supplier',
          'راجع دفعة مورد ضمن السيولة',
          'التزامات الموردين ${data.money(data.period.supplierPayables)} والسيولة ${data.money(available)}.',
          'ابدأ بالمورد الضروري للتوريد، بعد حجز احتياجات التشغيل.',
          'افتح الذمم',
          AppRoutes.suppliersPayablesList,
          priority: 82));
    }
    final costly =
        data.cars.where((c) => c.value > 0 && c.cost >= c.value * .9).toList();
    if (costly.isNotEmpty) {
      steps.add(DashboardStep(
          'cost',
          'راجع تكلفة ${costly.first.name}',
          'التكلفة المسجلة ${data.money(costly.first.cost)} مقابل قيمة ملف ${data.money(costly.first.value)}.',
          'راجع الهامش قبل شراء إضافي؛ القيمة ليست تقدير تكلفة.',
          'افتح الملف',
          AppRoutes.repairs,
          repairId: costly.first.id,
          priority: 90));
    }
    final stalled = data.cars
        .where((c) =>
            !c.ready &&
            c.since != null &&
            data.now.difference(c.since!).inDays >= 3)
        .toList();
    if (stalled.isNotEmpty) {
      steps.add(DashboardStep(
          'stalled',
          'حرّك ملف ${stalled.first.name}',
          'مرحلة ${stalled.first.stage} لم تتحدث منذ ${data.now.difference(stalled.first.since!).inDays} أيام.',
          'تحقق من العائق لفتح مساحة لسيارة أخرى.',
          'افتح الملف',
          AppRoutes.repairs,
          repairId: stalled.first.id,
          priority: 78));
    }
    final insurance = data.cars.where((c) => c.ready && c.insurance).toList();
    if (insurance.isNotEmpty) {
      steps.add(DashboardStep(
          'insurance',
          'راجع مستندات مطالبة التأمين',
          'الملف ${insurance.first.name} جاهز؛ تحقق من اكتمال المستندات وإرسال المطالبة.',
          'قد يسرّع بدء إجراءات التحصيل.',
          'افتح الملف',
          AppRoutes.repairs,
          repairId: insurance.first.id,
          priority: 85));
    }
    final waiting =
        data.cars.where((c) => c.ready && c.remaining <= 0.005).toList();
    if (waiting.isNotEmpty) {
      steps.add(DashboardStep(
          'handover',
          'نسّق استلام ${waiting.first.name}',
          'السيارة جاهزة ومسددّة ولم توثق كتسليم.',
          'يفرغ مكانًا في الورشة.',
          'افتح الملف',
          AppRoutes.repairs,
          repairId: waiting.first.id,
          priority: 72));
    }
    if (data.materials.isNotEmpty) {
      steps.add(DashboardStep(
          'stock',
          'راجع شراء المواد النافدة',
          '${data.materials.length} مادة برصيد صفر أو أقل، منها ${data.materials.first}.',
          'قارن عرض جملة باحتياج العمل والسيولة قبل الشراء.',
          'افتح المخزون',
          AppRoutes.rawMaterials,
          priority: 76));
    }
    final nearPayday = data.now.weekday >= 4 || data.now.day >= 25;
    if (nearPayday && available > 0 && data.period.payrollPayables > 0) {
      steps.add(DashboardStep(
          'payroll',
          'راجع توزيع دفعات الموظفين',
          'استحقاق الرواتب ${data.money(data.period.payrollPayables)} مع اقتراب نهاية الأسبوع أو الشهر.',
          'راجع السلف السابقة؛ أي سلفة معتمدة تصرف بسند صرف فقط.',
          'افتح الموظفين',
          AppRoutes.employeeList,
          priority: 70));
    }
    if (data.period.customerReceivables > 0 && ready.isEmpty) {
      steps.add(DashboardStep(
          'debts',
          'تابع الذمم القابلة للتحصيل',
          'رصيد العملاء المدين ${data.money(data.period.customerReceivables)}؛ راجع الملفات قبل التواصل.',
          'حدّد دفعة يمكن تحصيلها خلال ${period.label}.',
          'افتح الذمم',
          AppRoutes.clientArrears,
          priority: 80));
    }
    if (data.newFiles < data.previousFiles) {
      steps.add(DashboardStep(
          'marketing',
          'تابع العملاء لتنشيط الحجوزات',
          '${data.newFiles} ملف جديد مقابل ${data.previousFiles} في الفترة السابقة المماثلة.',
          'راجع العملاء وقدّم موعدًا مناسبًا أو صور أعمال بإذنهم.',
          'افتح العملاء',
          AppRoutes.clients,
          priority: 45));
    }
    steps.sort((a, b) => b.priority.compareTo(a.priority));
    final fallback = [
      const DashboardStep(
          'new',
          'ابدأ بإضافة ملف إصلاح جديد',
          'سجل العميل والمركبة والأعمال المتفق عليها.',
          'يصبح العمل قابلًا للمتابعة والتوثيق.',
          'ملف إصلاح',
          AppRoutes.repairsAdd),
      const DashboardStep(
          'receipt',
          'راجع المقبوضات الفعلية اليوم',
          'إن استلمت مبلغًا، سجله بسند قبض وربطه بجهته.',
          'يحافظ على سجل الصندوق مكتملًا.',
          'افتح سند قبض',
          AppRoutes.receiptVoucher),
      const DashboardStep(
          'open',
          'راجع الملفات المفتوحة',
          'حدّث مرحلة العمل عند تقدم السيارة فعليًا.',
          'يوضح الأولوية التالية لفريق الورشة.',
          'افتح الملفات',
          AppRoutes.repairs),
    ];
    return [...steps, ...fallback].take(3).toList(growable: false);
  }
}
