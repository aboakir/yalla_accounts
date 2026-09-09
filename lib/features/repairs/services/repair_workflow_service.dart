import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/services/current_user_context.dart';
import 'package:yalla_accounts/core/services/offline_outbox_service.dart';
import 'package:yalla_accounts/core/services/db/tables/repair_tables.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
import 'package:yalla_accounts/features/auth/services/audit_trail_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_auto_accounting_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';

class P09RepairWorkflowStage {
  P09RepairWorkflowStage._();

  static const draft = 'DRAFT';
  static const sent = 'SENT';
  static const approved = 'APPROVED';
  static const rejected = 'REJECTED';
  static const workOrder = 'WORK_ORDER';
  static const inProgress = 'IN_PROGRESS';
  static const readyForQc = 'READY_FOR_QC';
  static const qcChecked = 'QC_CHECKED';
  static const finalQc = 'FINAL_QC';
  static const readyForDelivery = 'READY_FOR_DELIVERY';
  static const delivered = 'DELIVERED';
  static const closed = 'CLOSED';

  static const all = <String>{
    draft,
    sent,
    approved,
    rejected,
    workOrder,
    inProgress,
    readyForQc,
    qcChecked,
    finalQc,
    readyForDelivery,
    delivered,
    closed,
  };
}

class RepairWorkflowState {
  final String repairId;
  final String stage;
  final String damageAssessment;
  final String? quoteNumber;
  final DateTime? quoteValidUntil;
  final DateTime? quoteSentAt;
  final DateTime? approvedAt;
  final String? approvedBy;
  final String? approvalMethod;
  final String? approvalNote;
  final DateTime? rejectedAt;
  final String? rejectionReason;
  final DateTime? workOrderStartedAt;
  final String? workOrderNumber;
  final String? responsibleEmployeeId;
  final DateTime? initialQcAt;
  final String? initialQcBy;
  final String? initialQcNotes;
  final bool qcWorkComplete;
  final bool qcFinishChecked;
  final bool qcCleanlinessChecked;
  final bool qcDocumentationChecked;
  final DateTime? finalQcAt;
  final String? finalQcBy;
  final String? finalQcNotes;
  final bool finalQcWorkVerified;
  final bool finalQcFinishVerified;
  final bool finalQcCleanlinessVerified;
  final bool finalQcDocumentationVerified;
  final DateTime? readyForDeliveryAt;
  final String? readyForDeliveryBy;
  final DateTime? deliveredAt;
  final String? deliveredBy;
  final String? handoverRecipient;
  final String? handoverMethod;
  final String? handoverNote;
  final String? handoverSignaturePath;
  final DateTime? closedAt;
  final String? closedBy;
  final String? closureNote;
  final DateTime? reopenedAt;
  final String? reopenedBy;
  final String? reopenReason;
  final int reopenCount;

  const RepairWorkflowState({
    required this.repairId,
    required this.stage,
    required this.damageAssessment,
    this.quoteNumber,
    this.quoteValidUntil,
    this.quoteSentAt,
    this.approvedAt,
    this.approvedBy,
    this.approvalMethod,
    this.approvalNote,
    this.rejectedAt,
    this.rejectionReason,
    this.workOrderStartedAt,
    this.workOrderNumber,
    this.responsibleEmployeeId,
    this.initialQcAt,
    this.initialQcBy,
    this.initialQcNotes,
    this.qcWorkComplete = false,
    this.qcFinishChecked = false,
    this.qcCleanlinessChecked = false,
    this.qcDocumentationChecked = false,
    this.finalQcAt,
    this.finalQcBy,
    this.finalQcNotes,
    this.finalQcWorkVerified = false,
    this.finalQcFinishVerified = false,
    this.finalQcCleanlinessVerified = false,
    this.finalQcDocumentationVerified = false,
    this.readyForDeliveryAt,
    this.readyForDeliveryBy,
    this.deliveredAt,
    this.deliveredBy,
    this.handoverRecipient,
    this.handoverMethod,
    this.handoverNote,
    this.handoverSignaturePath,
    this.closedAt,
    this.closedBy,
    this.closureNote,
    this.reopenedAt,
    this.reopenedBy,
    this.reopenReason,
    this.reopenCount = 0,
  });

  factory RepairWorkflowState.fromMap(Map<String, Object?> map) {
    DateTime? date(Object? value) {
      if (value == null) return null;
      return DateTime.tryParse(value.toString());
    }

    bool flag(Object? value) => value == 1 || value == true || '$value' == '1';

    final rawStage = (map['stage'] ?? P09RepairWorkflowStage.draft).toString();
    return RepairWorkflowState(
      repairId: (map['repair_id'] ?? '').toString(),
      stage: P09RepairWorkflowStage.all.contains(rawStage)
          ? rawStage
          : P09RepairWorkflowStage.draft,
      damageAssessment: (map['damage_assessment'] ?? '').toString(),
      quoteNumber: map['quote_number']?.toString(),
      quoteValidUntil: date(map['quote_valid_until']),
      quoteSentAt: date(map['quote_sent_at']),
      approvedAt: date(map['approved_at']),
      approvedBy: map['approved_by']?.toString(),
      approvalMethod: map['approval_method']?.toString(),
      approvalNote: map['approval_note']?.toString(),
      rejectedAt: date(map['rejected_at']),
      rejectionReason: map['rejection_reason']?.toString(),
      workOrderStartedAt: date(map['work_order_started_at']),
      workOrderNumber: map['work_order_number']?.toString(),
      responsibleEmployeeId: map['responsible_employee_id']?.toString(),
      initialQcAt: date(map['initial_qc_at']),
      initialQcBy: map['initial_qc_by']?.toString(),
      initialQcNotes: map['initial_qc_notes']?.toString(),
      qcWorkComplete: flag(map['qc_work_complete']),
      qcFinishChecked: flag(map['qc_finish_checked']),
      qcCleanlinessChecked: flag(map['qc_cleanliness_checked']),
      qcDocumentationChecked: flag(map['qc_documentation_checked']),
      finalQcAt: date(map['final_qc_at']),
      finalQcBy: map['final_qc_by']?.toString(),
      finalQcNotes: map['final_qc_notes']?.toString(),
      finalQcWorkVerified: flag(map['final_qc_work_verified']),
      finalQcFinishVerified: flag(map['final_qc_finish_verified']),
      finalQcCleanlinessVerified: flag(map['final_qc_cleanliness_verified']),
      finalQcDocumentationVerified:
          flag(map['final_qc_documentation_verified']),
      readyForDeliveryAt: date(map['ready_for_delivery_at']),
      readyForDeliveryBy: map['ready_for_delivery_by']?.toString(),
      deliveredAt: date(map['delivered_at']),
      deliveredBy: map['delivered_by']?.toString(),
      handoverRecipient: map['handover_recipient']?.toString(),
      handoverMethod: map['handover_method']?.toString(),
      handoverNote: map['handover_note']?.toString(),
      handoverSignaturePath: map['handover_signature_path']?.toString(),
      closedAt: date(map['closed_at']),
      closedBy: map['closed_by']?.toString(),
      closureNote: map['closure_note']?.toString(),
      reopenedAt: date(map['reopened_at']),
      reopenedBy: map['reopened_by']?.toString(),
      reopenReason: map['reopen_reason']?.toString(),
      reopenCount: int.tryParse('${map['reopen_count'] ?? 0}') ?? 0,
    );
  }
}

class RepairWorkflowService {
  RepairWorkflowService._();

  static Future<void> ensureSchema() async {
    final db = await DBService.database;
    await RepairTables.ensureP09WorkflowSchema(db);
  }

  static Future<RepairWorkflowState> load(String repairId) async {
    final db = await DBService.database;
    await RepairTables.ensureP09WorkflowSchema(db);
    await _ensureRow(db, repairId);
    final rows = await db.query(
      'repair_workflow',
      where: 'repair_id = ?',
      whereArgs: [repairId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('تعذر تحميل سير عمل ملف الإصلاح');
    }
    return RepairWorkflowState.fromMap(rows.first);
  }

  static Future<void> prepareEstimate({
    required String repairId,
    required String damageAssessment,
    required DateTime validUntil,
  }) async {
    final p16Actor =
        await AuthorizationGuard.require(PermissionKeys.repairWorkflow);
    final db = await DBService.database;
    await RepairTables.ensureP09WorkflowSchema(db);
    await _ensureRow(db, repairId);
    final current = await load(repairId);
    if (current.stage != P09RepairWorkflowStage.draft &&
        current.stage != P09RepairWorkflowStage.rejected) {
      throw StateError('لا يمكن تعديل عرض السعر بعد انتقاله لهذه المرحلة');
    }

    final now = DateTime.now();
    final quoteNumber = (current.quoteNumber ?? '').trim().isNotEmpty
        ? current.quoteNumber!.trim()
        : _newQuoteNumber(repairId, now);

    await SyncFoundationService.transaction(db, (tx) async {
      await tx.update(
        'repair_workflow',
        {
          'stage': P09RepairWorkflowStage.draft,
          'damage_assessment': damageAssessment.trim(),
          'quote_number': quoteNumber,
          'quote_valid_until': validUntil.toIso8601String(),
          'quote_sent_at': null,
          'approved_at': null,
          'approved_by': null,
          'approval_method': null,
          'approval_note': null,
          'rejected_at': null,
          'rejection_reason': null,
          'updated_at': now.toIso8601String(),
        },
        where: 'repair_id = ?',
        whereArgs: [repairId],
      );

      // Keep the legacy Repair model/PDF fields synchronized without touching
      // repairs.status, invoiceId, GL, or any posted accounting state.
      await tx.update(
        'repairs',
        {
          'quote_number': quoteNumber,
          'quote_valid_until': validUntil.toIso8601String(),
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [repairId],
      );
    });
    await AuditTrailService.log(
      actorUserId: p16Actor?.id,
      actorRole: p16Actor?.role,
      action: 'REPAIR_ESTIMATE_PREPARED',
      entityType: 'repair',
      entityId: repairId,
      after: {
        'stage': P09RepairWorkflowStage.draft,
        'damage_assessment': damageAssessment.trim(),
        'quote_number': quoteNumber,
        'quote_valid_until': validUntil.toIso8601String(),
      },
    );
  }

  static Future<void> markEstimateSent(String repairId) async {
    final current = await load(repairId);
    if (current.stage != P09RepairWorkflowStage.draft) {
      throw StateError(
          'يجب أن يكون عرض السعر في مرحلة الإعداد قبل تسجيل إرساله');
    }
    if ((current.quoteNumber ?? '').trim().isEmpty) {
      throw StateError('أعد عرض السعر أولًا قبل تسجيل الإرسال');
    }
    await _updateStage(
      repairId,
      P09RepairWorkflowStage.sent,
      extra: {'quote_sent_at': DateTime.now().toIso8601String()},
    );
  }

  static Future<void> approveEstimate({
    required String repairId,
    required String method,
    String? note,
  }) async {
    final current = await load(repairId);
    if (current.stage != P09RepairWorkflowStage.sent) {
      throw StateError('لا يمكن تسجيل الموافقة قبل إرسال عرض السعر');
    }
    final actor = await CurrentUserContext.userId();
    final now = DateTime.now();
    await _updateStage(
      repairId,
      P09RepairWorkflowStage.approved,
      extra: {
        'approved_at': now.toIso8601String(),
        'approved_by': actor ?? 'LOCAL_USER',
        'approval_method': method.trim(),
        'approval_note': _nullIfBlank(note),
        'rejected_at': null,
        'rejection_reason': null,
      },
    );

    // Deliberately DO NOT update repairs.status/approved_at/approved_by here.
    // Those legacy fields are coupled to invoicing in older code. P09 approval
    // is operational-only and must never create an invoice or GL entry.
  }

  static Future<void> rejectEstimate({
    required String repairId,
    String? reason,
  }) async {
    final current = await load(repairId);
    if (current.stage != P09RepairWorkflowStage.sent) {
      throw StateError('لا يمكن تسجيل الرفض قبل إرسال عرض السعر');
    }
    await _updateStage(
      repairId,
      P09RepairWorkflowStage.rejected,
      extra: {
        'rejected_at': DateTime.now().toIso8601String(),
        'rejection_reason': _nullIfBlank(reason),
      },
    );
  }

  static Future<void> reopenRejectedEstimate(String repairId) async {
    final current = await load(repairId);
    if (current.stage != P09RepairWorkflowStage.rejected) {
      throw StateError('الملف ليس في حالة عرض سعر مرفوض');
    }
    await _updateStage(
      repairId,
      P09RepairWorkflowStage.draft,
      extra: {
        'quote_sent_at': null,
        'rejected_at': null,
        'rejection_reason': null,
      },
    );
  }

  static Future<void> createWorkOrder({
    required String repairId,
    String? responsibleEmployeeId,
  }) async {
    final current = await load(repairId);
    if (current.stage != P09RepairWorkflowStage.approved) {
      throw StateError('أمر العمل يتطلب موافقة العميل أولًا');
    }
    final now = DateTime.now();
    await _updateStage(
      repairId,
      P09RepairWorkflowStage.workOrder,
      extra: {
        'work_order_started_at': now.toIso8601String(),
        'work_order_number': _newWorkOrderNumber(repairId, now),
        'responsible_employee_id': _nullIfBlank(responsibleEmployeeId),
      },
    );
  }

  static Future<void> assignResponsible({
    required String repairId,
    required String employeeId,
  }) async {
    final p16Actor =
        await AuthorizationGuard.require(PermissionKeys.repairWorkflow);
    final db = await DBService.database;
    await RepairTables.ensureP09WorkflowSchema(db);
    await _ensureRow(db, repairId);
    final before = await _loadStateOn(db, repairId);
    await SyncFoundationService.writeOn(
        db,
        (syncTxn) => syncTxn.update(
              'repair_workflow',
              {
                'responsible_employee_id': employeeId.trim(),
                'updated_at': DateTime.now().toIso8601String(),
              },
              where: 'repair_id = ?',
              whereArgs: [repairId],
            ));
    await AuditTrailService.log(
      actorUserId: p16Actor?.id,
      actorRole: p16Actor?.role,
      action: 'REPAIR_RESPONSIBLE_ASSIGNED',
      entityType: 'repair',
      entityId: repairId,
      before: {'responsible_employee_id': before.responsibleEmployeeId},
      after: {'responsible_employee_id': employeeId.trim()},
    );
  }

  static Future<void> startWork(String repairId) async {
    final current = await load(repairId);
    if (current.stage != P09RepairWorkflowStage.workOrder) {
      throw StateError('يجب إنشاء أمر العمل أولًا');
    }
    if ((current.responsibleEmployeeId ?? '').trim().isEmpty) {
      throw StateError('عيّن المسؤول/الفني قبل بدء التنفيذ');
    }
    await _updateStage(repairId, P09RepairWorkflowStage.inProgress);
  }

  static Future<void> markReadyForQc(String repairId) async {
    final current = await load(repairId);
    if (current.stage != P09RepairWorkflowStage.inProgress) {
      throw StateError('الملف ليس قيد التنفيذ');
    }
    await _updateStage(repairId, P09RepairWorkflowStage.readyForQc);
  }

  static Future<void> completeInitialQc({
    required String repairId,
    required bool workComplete,
    required bool finishChecked,
    required bool cleanlinessChecked,
    required bool documentationChecked,
    String? notes,
  }) async {
    final current = await load(repairId);
    if (current.stage != P09RepairWorkflowStage.readyForQc) {
      throw StateError('الملف ليس جاهزًا للفحص الأولي');
    }
    if (!(workComplete &&
        finishChecked &&
        cleanlinessChecked &&
        documentationChecked)) {
      throw StateError('يجب استكمال جميع نقاط الفحص الأولي');
    }
    final actor = await CurrentUserContext.userId();
    await _updateStage(
      repairId,
      P09RepairWorkflowStage.qcChecked,
      extra: {
        'initial_qc_at': DateTime.now().toIso8601String(),
        'initial_qc_by': actor ?? 'LOCAL_USER',
        'initial_qc_notes': _nullIfBlank(notes),
        'qc_work_complete': 1,
        'qc_finish_checked': 1,
        'qc_cleanliness_checked': 1,
        'qc_documentation_checked': 1,
      },
    );
  }

  // ======================================================================
  // P13 FINAL QUALITY / DELIVERY / CLOSURE
  // ======================================================================

  static Future<void> completeFinalQc({
    required String repairId,
    required bool workVerified,
    required bool finishVerified,
    required bool cleanlinessVerified,
    required bool documentationVerified,
    String? notes,
  }) async {
    if (!(workVerified &&
        finishVerified &&
        cleanlinessVerified &&
        documentationVerified)) {
      throw StateError('يجب استكمال جميع نقاط فحص الجودة النهائي');
    }
    final actor = await CurrentUserContext.userId() ?? 'LOCAL_USER';
    final now = DateTime.now();
    await _transitionP13(
      repairId: repairId,
      expectedStage: P09RepairWorkflowStage.qcChecked,
      nextStage: P09RepairWorkflowStage.finalQc,
      eventType: 'FINAL_QC_PASSED',
      actor: actor,
      extra: {
        'final_qc_at': now.toIso8601String(),
        'final_qc_by': actor,
        'final_qc_notes': _nullIfBlank(notes),
        'final_qc_work_verified': 1,
        'final_qc_finish_verified': 1,
        'final_qc_cleanliness_verified': 1,
        'final_qc_documentation_verified': 1,
      },
      eventNote: _nullIfBlank(notes),
    );
  }

  static Future<void> returnFinalQcToWork({
    required String repairId,
    required String reason,
  }) async {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw StateError('اكتب سبب إعادة المركبة للتنفيذ');
    }
    final actor = await CurrentUserContext.userId() ?? 'LOCAL_USER';
    await _transitionP13(
      repairId: repairId,
      expectedStage: P09RepairWorkflowStage.qcChecked,
      nextStage: P09RepairWorkflowStage.inProgress,
      eventType: 'FINAL_QC_REWORK_REQUIRED',
      actor: actor,
      repairUpdates: const {'vehicleStatus': 'قيد الإصلاح'},
      eventNote: cleanReason,
    );
  }

  static Future<void> markReadyForDelivery(String repairId) async {
    final actor = await CurrentUserContext.userId() ?? 'LOCAL_USER';
    final now = DateTime.now();
    await _transitionP13(
      repairId: repairId,
      expectedStage: P09RepairWorkflowStage.finalQc,
      nextStage: P09RepairWorkflowStage.readyForDelivery,
      eventType: 'READY_FOR_DELIVERY',
      actor: actor,
      extra: {
        'ready_for_delivery_at': now.toIso8601String(),
        'ready_for_delivery_by': actor,
      },
      repairUpdates: const {'vehicleStatus': 'جاهزة للتسليم'},
    );
  }

  static Future<void> recordDelivery({
    required String repairId,
    required String recipientName,
    required String proofMethod,
    String? note,
    String? signaturePath,
  }) async {
    final recipient = recipientName.trim();
    final method = proofMethod.trim();
    if (recipient.isEmpty) {
      throw StateError('اسم مستلم المركبة مطلوب');
    }
    if (method.isEmpty) {
      throw StateError('طريقة إثبات التسليم مطلوبة');
    }
    final actor = await CurrentUserContext.userId() ?? 'LOCAL_USER';
    final now = DateTime.now();
    await _transitionP13(
      repairId: repairId,
      expectedStage: P09RepairWorkflowStage.readyForDelivery,
      nextStage: P09RepairWorkflowStage.delivered,
      eventType: 'CUSTOMER_HANDOVER',
      actor: actor,
      extra: {
        'delivered_at': now.toIso8601String(),
        'delivered_by': actor,
        'handover_recipient': recipient,
        'handover_method': method,
        'handover_note': _nullIfBlank(note),
        'handover_signature_path': _nullIfBlank(signaturePath),
      },
      repairUpdates: const {'vehicleStatus': 'تم التسليم'},
      eventNote: _nullIfBlank(note) == null
          ? '$recipient — $method'
          : '$recipient — $method — ${note!.trim()}',
    );
  }

  static Future<void> closeRepair({
    required String repairId,
    String? note,
  }) async {
    final p16Actor =
        await AuthorizationGuard.require(PermissionKeys.repairClose);
    final actor =
        p16Actor?.id ?? await CurrentUserContext.userId() ?? 'LOCAL_USER';
    final now = DateTime.now();
    final db = await DBService.database;
    await RepairTables.ensureP09WorkflowSchema(db);

    await DBService.inTx((tx) async {
      await _ensureRow(tx, repairId);
      final state = await _loadStateOn(tx, repairId);
      if (state.stage != P09RepairWorkflowStage.delivered) {
        throw StateError('يجب تسليم المركبة وتوثيق الاستلام قبل إغلاق الملف');
      }

      final repairRows = await tx.query(
        'repairs',
        columns: const ['id', 'status', 'isArchived'],
        where: 'id = ?',
        whereArgs: [repairId],
        limit: 1,
      );
      if (repairRows.isEmpty) throw StateError('ملف الإصلاح غير موجود');
      final legacyStatus = (repairRows.first['status'] ?? '').toString();
      if (legacyStatus == RepairAutoAccountingService.cancelledStatus) {
        throw StateError('الملف الملغى لا يمكن إغلاقه كملف مكتمل');
      }

      final truth = await RepairFinancialTruthService.load(
        repairId,
        executor: tx,
      );
      if (!truth.isFinanciallySettled) {
        throw StateError(
          'لا يمكن إغلاق الملف: المتبقي ${truth.remaining.toStringAsFixed(2)}. '
          'التسليم مسموح، لكن الإغلاق يتطلب تسوية الذمة.',
        );
      }
      if (truth.customerArBalance.abs() > 0.01) {
        throw StateError(
          'لا يمكن إغلاق الملف: رصيد ذمة GL المرتبط بالملف '
          '${truth.customerArBalance.toStringAsFixed(2)} غير مسوّى.',
        );
      }
      await tx.update(
        'repair_workflow',
        {
          'stage': P09RepairWorkflowStage.closed,
          'closed_at': now.toIso8601String(),
          'closed_by': actor,
          'closure_note': _nullIfBlank(note),
          'updated_at': now.toIso8601String(),
        },
        where: 'repair_id = ?',
        whereArgs: [repairId],
      );
      await tx.update(
        'repairs',
        {
          'status': 'CLOSED',
          'vehicleStatus': 'تم التسليم',
          'isArchived': 1,
          'updated_at': now.toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [repairId],
      );
      await _insertP13Event(
        tx,
        repairId: repairId,
        eventType: 'REPAIR_CLOSED',
        fromStage: state.stage,
        toStage: P09RepairWorkflowStage.closed,
        actor: actor,
        note: _nullIfBlank(note),
        createdAt: now,
      );
      await _enqueueRepairWorkflowSync(
        tx,
        repairId: repairId,
        action: 'close',
        stage: P09RepairWorkflowStage.closed,
        now: now,
      );
    });
    await AuditTrailService.log(
      actorUserId: p16Actor?.id,
      actorRole: p16Actor?.role,
      action: 'REPAIR_CLOSED',
      entityType: 'repair',
      entityId: repairId,
      after: {'stage': P09RepairWorkflowStage.closed, 'isArchived': 1},
      reason: note,
    );
  }

  static Future<void> reopenClosed({
    required String repairId,
    required String reason,
  }) async {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) throw StateError('سبب إعادة فتح الملف مطلوب');
    final p16Actor =
        await AuthorizationGuard.require(PermissionKeys.repairReopen);
    final actor =
        p16Actor?.id ?? await CurrentUserContext.userId() ?? 'LOCAL_USER';
    final now = DateTime.now();
    final db = await DBService.database;
    await RepairTables.ensureP09WorkflowSchema(db);

    await DBService.inTx((tx) async {
      await _ensureRow(tx, repairId);
      final state = await _loadStateOn(tx, repairId);
      if (state.stage != P09RepairWorkflowStage.closed) {
        throw StateError('إعادة الفتح متاحة فقط للملف المغلق رسميًا');
      }
      final repairRows = await tx.query(
        'repairs',
        columns: const ['status', 'isArchived'],
        where: 'id = ?',
        whereArgs: [repairId],
        limit: 1,
      );
      if (repairRows.isEmpty) throw StateError('ملف الإصلاح غير موجود');
      if ((repairRows.first['status'] ?? '').toString() != 'CLOSED') {
        throw StateError('حالة الملف لا تطابق إغلاق P13 الرسمي');
      }

      await tx.update(
        'repair_workflow',
        {
          'stage': P09RepairWorkflowStage.inProgress,
          'final_qc_at': null,
          'final_qc_by': null,
          'final_qc_notes': null,
          'final_qc_work_verified': 0,
          'final_qc_finish_verified': 0,
          'final_qc_cleanliness_verified': 0,
          'final_qc_documentation_verified': 0,
          'ready_for_delivery_at': null,
          'ready_for_delivery_by': null,
          'delivered_at': null,
          'delivered_by': null,
          'handover_recipient': null,
          'handover_method': null,
          'handover_note': null,
          'handover_signature_path': null,
          'closed_at': null,
          'closed_by': null,
          'closure_note': null,
          'reopened_at': now.toIso8601String(),
          'reopened_by': actor,
          'reopen_reason': cleanReason,
          'reopen_count': state.reopenCount + 1,
          'updated_at': now.toIso8601String(),
        },
        where: 'repair_id = ?',
        whereArgs: [repairId],
      );
      await tx.update(
        'repairs',
        {
          'status': 'IN_PROGRESS',
          'vehicleStatus': 'قيد الإصلاح',
          'isArchived': 0,
          'updated_at': now.toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [repairId],
      );
      await _insertP13Event(
        tx,
        repairId: repairId,
        eventType: 'REPAIR_REOPENED',
        fromStage: P09RepairWorkflowStage.closed,
        toStage: P09RepairWorkflowStage.inProgress,
        actor: actor,
        note: cleanReason,
        createdAt: now,
      );
      await _enqueueRepairWorkflowSync(
        tx,
        repairId: repairId,
        action: 'reopen',
        stage: P09RepairWorkflowStage.inProgress,
        now: now,
      );
    });
    await AuditTrailService.log(
      actorUserId: p16Actor?.id,
      actorRole: p16Actor?.role,
      action: 'REPAIR_REOPENED',
      entityType: 'repair',
      entityId: repairId,
      before: {'stage': P09RepairWorkflowStage.closed, 'isArchived': 1},
      after: {'stage': P09RepairWorkflowStage.inProgress, 'isArchived': 0},
      reason: cleanReason,
    );
  }

  static Future<RepairWorkflowState> _loadStateOn(
    DatabaseExecutor db,
    String repairId,
  ) async {
    final rows = await db.query(
      'repair_workflow',
      where: 'repair_id = ?',
      whereArgs: [repairId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('تعذر تحميل سير عمل ملف الإصلاح');
    return RepairWorkflowState.fromMap(rows.first);
  }

  static Future<void> _transitionP13({
    required String repairId,
    required String expectedStage,
    required String nextStage,
    required String eventType,
    required String actor,
    Map<String, Object?> extra = const {},
    Map<String, Object?> repairUpdates = const {},
    String? eventNote,
  }) async {
    final p16Actor =
        await AuthorizationGuard.require(PermissionKeys.repairWorkflow);
    final db = await DBService.database;
    await RepairTables.ensureP09WorkflowSchema(db);
    final now = DateTime.now();
    await DBService.inTx((tx) async {
      await _ensureRow(tx, repairId);
      final current = await _loadStateOn(tx, repairId);
      if (current.stage != expectedStage) {
        throw StateError('المرحلة الحالية لا تسمح بهذه العملية');
      }
      await tx.update(
        'repair_workflow',
        {
          'stage': nextStage,
          ...extra,
          'updated_at': now.toIso8601String(),
        },
        where: 'repair_id = ?',
        whereArgs: [repairId],
      );
      if (repairUpdates.isNotEmpty) {
        await tx.update(
          'repairs',
          {...repairUpdates, 'updated_at': now.toUtc().toIso8601String()},
          where: 'id = ?',
          whereArgs: [repairId],
        );
      }
      await _insertP13Event(
        tx,
        repairId: repairId,
        eventType: eventType,
        fromStage: current.stage,
        toStage: nextStage,
        actor: actor,
        note: eventNote,
        createdAt: now,
      );
      if (repairUpdates.isNotEmpty) {
        await _enqueueRepairWorkflowSync(
          tx,
          repairId: repairId,
          action: eventType.toLowerCase(),
          stage: nextStage,
          now: now,
        );
      }
    });
    await AuditTrailService.log(
      actorUserId: p16Actor?.id,
      actorRole: p16Actor?.role,
      action: eventType,
      entityType: 'repair',
      entityId: repairId,
      before: {'stage': expectedStage},
      after: {'stage': nextStage, ...extra, ...repairUpdates},
      reason: eventNote,
    );
  }

  static Future<void> _insertP13Event(
    DatabaseExecutor db, {
    required String repairId,
    required String eventType,
    required String fromStage,
    required String toStage,
    required String actor,
    String? note,
    required DateTime createdAt,
  }) async {
    await db.insert('repair_workflow_events', {
      'repair_id': repairId,
      'event_type': eventType,
      'from_stage': fromStage,
      'to_stage': toStage,
      'actor_id': actor,
      'note': _nullIfBlank(note),
      'created_at': createdAt.toIso8601String(),
    });
  }

  static Future<void> _enqueueRepairWorkflowSync(
    DatabaseExecutor db, {
    required String repairId,
    required String action,
    required String stage,
    required DateTime now,
  }) async {
    await OfflineOutboxService.enqueue(
      db,
      channel: OfflineOutboxService.channelSync,
      operation: 'UPSERT',
      entityType: 'repair',
      entityId: repairId,
      idempotencyKey:
          'repair:$repairId:p13:$action:${now.microsecondsSinceEpoch}',
      payload: {
        'schema': 1,
        'entity_type': 'repair',
        'entity_id': repairId,
        'workflow_stage': stage,
        'p13_action': action,
      },
    );
  }

  static Future<void> _updateStage(
    String repairId,
    String stage, {
    Map<String, Object?> extra = const {},
  }) async {
    if (!P09RepairWorkflowStage.all.contains(stage)) {
      throw ArgumentError.value(
          stage, 'stage', 'Unknown repair workflow stage');
    }
    final p16Actor =
        await AuthorizationGuard.require(PermissionKeys.repairWorkflow);
    final db = await DBService.database;
    await RepairTables.ensureP09WorkflowSchema(db);
    await _ensureRow(db, repairId);
    final before = await _loadStateOn(db, repairId);
    await SyncFoundationService.writeOn(
        db,
        (syncTxn) => syncTxn.update(
              'repair_workflow',
              {
                'stage': stage,
                ...extra,
                'updated_at': DateTime.now().toIso8601String(),
              },
              where: 'repair_id = ?',
              whereArgs: [repairId],
            ));
    await AuditTrailService.log(
      actorUserId: p16Actor?.id,
      actorRole: p16Actor?.role,
      action: 'REPAIR_WORKFLOW_CHANGED',
      entityType: 'repair',
      entityId: repairId,
      before: {'stage': before.stage},
      after: {'stage': stage, ...extra},
    );
  }

  static Future<void> _ensureRow(
    DatabaseExecutor db,
    String repairId,
  ) async {
    final cleanId = repairId.trim();
    if (cleanId.isEmpty) throw ArgumentError('repairId is required');
    final now = DateTime.now().toIso8601String();
    String seedStage = P09RepairWorkflowStage.draft;
    String? seedQuoteNumber;
    String? seedQuoteValidUntil;

    final repairs = await db.query(
      'repairs',
      columns: <String>[
        'status',
        'invoice_id',
        'invoiceId',
        'quote_number',
        'quote_valid_until',
      ],
      where: 'id = ?',
      whereArgs: <Object?>[cleanId],
      limit: 1,
    );
    if (repairs.isNotEmpty) {
      final repair = repairs.first;
      final legacyStatus = (repair['status'] ?? '').toString().trim();
      final invoiceId =
          (repair['invoice_id'] ?? repair['invoiceId'] ?? '').toString().trim();
      if (legacyStatus == 'CLOSED') {
        seedStage = P09RepairWorkflowStage.closed;
      } else if (legacyStatus == 'IN_PROGRESS') {
        seedStage = P09RepairWorkflowStage.inProgress;
      } else if (invoiceId.isNotEmpty || legacyStatus == 'INVOICED') {
        // Legacy invoice means the commercial approval already happened.
        // Do not trust bare APPROVED because old saveAsQuote could set it
        // automatically without a real customer approval.
        seedStage = P09RepairWorkflowStage.approved;
      }
      seedQuoteNumber = repair['quote_number']?.toString();
      seedQuoteValidUntil = repair['quote_valid_until']?.toString();
    }

    await SyncFoundationService.writeOn(
        db,
        (syncTxn) => syncTxn.insert(
              'repair_workflow',
              {
                'repair_id': cleanId,
                'stage': seedStage,
                'damage_assessment': '',
                'quote_number': _nullIfBlank(seedQuoteNumber),
                'quote_valid_until': _nullIfBlank(seedQuoteValidUntil),
                'created_at': now,
                'updated_at': now,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            ));
  }

  static String _newQuoteNumber(String repairId, DateTime now) {
    String two(int value) => value.toString().padLeft(2, '0');
    final cleaned = repairId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final tail = cleaned.length <= 6
        ? cleaned.toUpperCase()
        : cleaned.substring(cleaned.length - 6).toUpperCase();
    final suffix = tail.isEmpty ? 'LOCAL' : tail;
    return 'Q-${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}-$suffix';
  }

  static String _newWorkOrderNumber(String repairId, DateTime now) {
    String two(int value) => value.toString().padLeft(2, '0');
    final cleaned = repairId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final tail = cleaned.length <= 6
        ? cleaned.toUpperCase()
        : cleaned.substring(cleaned.length - 6).toUpperCase();
    final suffix = tail.isEmpty ? 'LOCAL' : tail;
    return 'WO-${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}-$suffix';
  }

  static String? _nullIfBlank(String? value) {
    final clean = value?.trim();
    return (clean == null || clean.isEmpty) ? null : clean;
  }
}
