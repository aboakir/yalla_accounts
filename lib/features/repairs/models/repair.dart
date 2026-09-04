// 📁 lib/features/repairs/models/repair.dart
//
// Model متوافق مع DB v30+.
// • يدعم حقول عرض السعر: status, quote_number, quote_valid_until, approved_at, approved_by.
// • يدعم صورة غلاف الإصلاح: thumbnail_path + thumbnail_updated_at.
// • toMap يكتب فقط الأعمدة الموجودة فعليًا بجدول repairs.
// • fromMap مرن ويقرأ snake_case/camelCase.
// • Parsing آمن للقيم والقوائم مع دعم أرقام epoch للوقت.
// • حاسبات جاهزة للحالة المالية + مساعدين لمسار عرض السعر.

import 'dart:convert';
import 'package:flutter/foundation.dart';

// ================= Payment Type =================
enum PaymentType {
  cash,
  check,
  installment,
  insuranceTransfer,
}

// ================= Repair Status (quote workflow) =================
class RepairStatusText {
  static const quote = 'QUOTE';
  static const approved = 'APPROVED';
  static const invoiced = 'INVOICED';
  static const closed = 'CLOSED';
}

// ================= Parse helpers ===================

double? tryDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

// ================= Checks & Installments ===================
class CheckDetail {
  final double amount;
  final String issueDate;
  final String dueDate;
  final String? receiver;
  final String? from;
  final String? note;
  final String? checkNumber;
  final String? bankName;
  final String? checkOwner;
  final String? drawer;

  CheckDetail({
    required this.amount,
    required this.issueDate,
    required this.dueDate,
    this.receiver,
    this.from,
    this.note,
    this.checkNumber,
    this.bankName,
    this.checkOwner,
    this.drawer,
  });

  static double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  Map<String, dynamic> toMap() => {
        'amount': amount,
        'issueDate': issueDate,
        'dueDate': dueDate,
        'receiver': receiver,
        'from': from,
        'note': note,
        'checkNumber': checkNumber,
        'bankName': bankName,
        'checkOwner': checkOwner,
        'drawer': drawer,
      };

  factory CheckDetail.fromMap(Map<String, dynamic> map) => CheckDetail(
        amount: _asDouble(map['amount']),
        issueDate: (map['issueDate'] ?? map['issue_date'] ?? '').toString(),
        dueDate: (map['dueDate'] ?? map['due_date'] ?? '').toString(),
        receiver: map['receiver']?.toString(),
        from: map['from']?.toString(),
        note: map['note']?.toString(),
        checkNumber: map['checkNumber']?.toString(),
        bankName: map['bankName']?.toString(),
        checkOwner: map['checkOwner']?.toString(),
        drawer: map['drawer']?.toString(),
      );

  bool validateDates() {
    try {
      DateTime.parse(issueDate);
      DateTime.parse(dueDate);
      return true;
    } catch (_) {
      return false;
    }
  }
}

class Installment {
  final double amount;
  final String dueDate;
  final bool paid;
  final String? receiver;
  final String? from;
  final String? note;

  Installment({
    required this.amount,
    required this.dueDate,
    this.paid = false,
    this.receiver,
    this.from,
    this.note,
  });

  static double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  Map<String, dynamic> toMap() => {
        'amount': amount,
        'dueDate': dueDate,
        'paid': paid,
        'receiver': receiver,
        'from': from,
        'note': note,
      };

  factory Installment.fromMap(Map<String, dynamic> map) => Installment(
        amount: _asDouble(map['amount']),
        dueDate: (map['dueDate'] ?? map['due_date'] ?? '').toString(),
        paid: map['paid'] == true ||
            map['paid'] == 1 ||
            '${map['paid']}' == 'true',
        receiver: map['receiver']?.toString(),
        from: map['from']?.toString(),
        note: map['note']?.toString(),
      );

  bool validateDueDate() {
    try {
      DateTime.parse(dueDate);
      return true;
    } catch (_) {
      return false;
    }
  }
}

// ======================== Repair Model ========================
class Repair {
  // ---- Identity ----
  final String id;
  final String invoiceNumber;

  // ---- Vehicle ----
  final String vehicleModel;
  final String vehicleType;
  final String vehicleNumber;
  final DateTime receivedDate;

  // ---- Beneficiary / Client ----
  final String beneficiaryType;
  final String beneficiaryName;
  final int? clientId;

  // ---- Status ----
  final String insuranceStatus;
  final String repairType;
  final String vehicleStatus;

  // ---- Quote workflow ----
  final String status;
  final String? quoteNumber;
  final DateTime? quoteValidUntil;
  final DateTime? approvedAt;
  final String? approvedBy;

  // ---- Follow-up ----
  final String? insuranceFollowUpStatus;

  // ---- Lines ----
  final List<Map<String, dynamic>> parts;
  final List<Map<String, dynamic>> works;

  // ---- Finance ----
  final double fileValue;
  final PaymentType paymentType;
  final double paidAmount;
  final String? paymentStatus;

  // ---- external ----
  final List<CheckDetail>? checkDetails;
  final List<Installment>? installmentSchedule;

  // ---- Notes & Images ----
  final String? notes;
  final List<String> imagePaths;

  // ---- Cover ----
  final String? thumbnailPath;
  final DateTime? thumbnailUpdatedAt;

  // ---- Transfers ----
  final String? transferFromAccount;
  final String? transferToAccount;
  final String? transferCompany;
  final DateTime? transferDate;
  final double? transferAmount;
  final String? transferImagePath;

  // ---- Flags ----
  final bool isArchived;
  final double? actualCost;
  final double? workCost;
  final double? incomeAmount;
  final bool isLedgerEnabled;
  final bool isLedgerSynced;
  final double? finalApprovedAmount;
  final String? invoiceId;

  // ---- Timestamps ----
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // ---------------- CONSTRUCTOR ----------------

  Repair({
    required this.id,
    required this.invoiceNumber,
    required this.vehicleModel,
    required this.vehicleType,
    required this.vehicleNumber,
    required this.receivedDate,
    required this.beneficiaryType,
    required this.beneficiaryName,
    this.clientId,
    required this.insuranceStatus,
    required this.repairType,
    required this.vehicleStatus,
    required this.status,
    this.quoteNumber,
    this.quoteValidUntil,
    this.approvedAt,
    this.approvedBy,
    this.insuranceFollowUpStatus,
    required this.parts,
    required this.works,
    required this.fileValue,
    required this.paymentType,
    required this.paidAmount,
    this.paymentStatus,
    this.checkDetails,
    this.installmentSchedule,
    this.notes,
    required this.imagePaths,
    this.thumbnailPath,
    this.thumbnailUpdatedAt,
    this.transferFromAccount,
    this.transferToAccount,
    this.transferCompany,
    this.transferDate,
    this.transferAmount,
    this.transferImagePath,
    this.isArchived = false,
    this.actualCost,
    this.workCost,
    this.incomeAmount,
    this.isLedgerEnabled = false,
    this.isLedgerSynced = false,
    this.finalApprovedAmount,
    this.invoiceId,
    this.createdAt,
    this.updatedAt,
  });

  // ---------------- COPYWITH ----------------
  Repair copyWith({
    String? id,
    String? invoiceNumber,
    String? vehicleModel,
    String? vehicleType,
    String? vehicleNumber,
    DateTime? receivedDate,
    String? beneficiaryType,
    String? beneficiaryName,
    int? clientId,
    String? insuranceStatus,
    String? repairType,
    String? vehicleStatus,
    String? status,
    String? quoteNumber,
    DateTime? quoteValidUntil,
    DateTime? approvedAt,
    String? approvedBy,
    String? insuranceFollowUpStatus,
    List<Map<String, dynamic>>? parts,
    List<Map<String, dynamic>>? works,
    double? fileValue,
    PaymentType? paymentType,
    double? paidAmount,
    String? paymentStatus,
    List<CheckDetail>? checkDetails,
    List<Installment>? installmentSchedule,
    String? notes,
    List<String>? imagePaths,
    String? thumbnailPath,
    DateTime? thumbnailUpdatedAt,
    String? transferFromAccount,
    String? transferToAccount,
    String? transferCompany,
    DateTime? transferDate,
    double? transferAmount,
    String? transferImagePath,
    bool? isArchived,
    double? actualCost,
    double? workCost,
    double? incomeAmount,
    bool? isLedgerEnabled,
    bool? isLedgerSynced,
    double? finalApprovedAmount,
    String? invoiceId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Repair(
      id: id ?? this.id,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      vehicleModel: vehicleModel ?? this.vehicleModel,
      vehicleType: vehicleType ?? this.vehicleType,
      vehicleNumber: vehicleNumber ?? this.vehicleNumber,
      receivedDate: receivedDate ?? this.receivedDate,
      beneficiaryType: beneficiaryType ?? this.beneficiaryType,
      beneficiaryName: beneficiaryName ?? this.beneficiaryName,
      clientId: clientId ?? this.clientId,
      insuranceStatus: insuranceStatus ?? this.insuranceStatus,
      repairType: repairType ?? this.repairType,
      vehicleStatus: vehicleStatus ?? this.vehicleStatus,
      status: status ?? this.status,
      quoteNumber: quoteNumber ?? this.quoteNumber,
      quoteValidUntil: quoteValidUntil ?? this.quoteValidUntil,
      approvedAt: approvedAt ?? this.approvedAt,
      approvedBy: approvedBy ?? this.approvedBy,
      insuranceFollowUpStatus:
          insuranceFollowUpStatus ?? this.insuranceFollowUpStatus,
      parts: parts ?? this.parts,
      works: works ?? this.works,
      fileValue: fileValue ?? this.fileValue,
      paymentType: paymentType ?? this.paymentType,
      paidAmount: paidAmount ?? this.paidAmount,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      checkDetails: checkDetails ?? this.checkDetails,
      installmentSchedule: installmentSchedule ?? this.installmentSchedule,
      notes: notes ?? this.notes,
      imagePaths: imagePaths ?? this.imagePaths,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      thumbnailUpdatedAt: thumbnailUpdatedAt ?? this.thumbnailUpdatedAt,
      transferFromAccount: transferFromAccount ?? this.transferFromAccount,
      transferToAccount: transferToAccount ?? this.transferToAccount,
      transferCompany: transferCompany ?? this.transferCompany,
      transferDate: transferDate ?? this.transferDate,
      transferAmount: transferAmount ?? this.transferAmount,
      transferImagePath: transferImagePath ?? this.transferImagePath,
      isArchived: isArchived ?? this.isArchived,
      actualCost: actualCost ?? this.actualCost,
      workCost: workCost ?? this.workCost,
      incomeAmount: incomeAmount ?? this.incomeAmount,
      isLedgerEnabled: isLedgerEnabled ?? this.isLedgerEnabled,
      isLedgerSynced: isLedgerSynced ?? this.isLedgerSynced,
      finalApprovedAmount: finalApprovedAmount ?? this.finalApprovedAmount,
      invoiceId: invoiceId ?? this.invoiceId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // ---------------- TOMAP ----------------
  Map<String, dynamic> toMap() => {
        'id': id,
        'invoiceNumber': invoiceNumber,
        'vehicleModel': vehicleModel,
        'vehicleType': vehicleType,
        'vehicleNumber': vehicleNumber,
        'receivedDate': receivedDate.toIso8601String(),
        'beneficiaryType': beneficiaryType,
        'beneficiaryName': beneficiaryName,
        'client_id': clientId,
        'insuranceStatus': insuranceStatus,
        'repairType': repairType,
        'vehicleStatus': vehicleStatus,
        'status': status,
        'quote_number': quoteNumber,
        'quote_valid_until': quoteValidUntil?.toIso8601String(),
        'approved_at': approvedAt?.toIso8601String(),
        'approved_by': approvedBy,
        'parts': jsonEncode(parts),
        'works': jsonEncode(works),
        'fileValue': fileValue,
        'paymentType': describeEnum(paymentType),
        'paidAmount': paidAmount,
        'paymentStatus': paymentStatus,
        'notes': notes,
        'imagePaths': jsonEncode(imagePaths),
        'thumbnail_path': thumbnailPath,
        'thumbnail_updated_at': thumbnailUpdatedAt?.toIso8601String(),
        'transferFromAccount': transferFromAccount,
        'transferToAccount': transferToAccount,
        'transferCompany': transferCompany,
        'transferDate': transferDate?.toIso8601String(),
        'transferAmount': transferAmount,
        'transferImagePath': transferImagePath,
        'isArchived': isArchived ? 1 : 0,
        'actualCost': actualCost,
        'workCost': workCost,
        'incomeAmount': incomeAmount,
        'isLedgerEnabled': isLedgerEnabled ? 1 : 0,
        'isLedgerSynced': isLedgerSynced ? 1 : 0,
        'finalApprovedAmount': finalApprovedAmount,
        // P0.006 — canonical Repair -> Invoice compatibility link.
        // The authoritative relationship is invoices.repair_id.
        'invoice_id': invoiceId,
      };

  // ---------------- FROMMAP ----------------
  factory Repair.fromMap(Map<String, dynamic> map) {
    DateTime? parseDateTime(dynamic v) {
      if (v == null) return null;
      if (v is int) {
        final isSeconds = v < 20000000000;
        return DateTime.fromMillisecondsSinceEpoch(isSeconds ? v * 1000 : v);
      }
      final s = v.toString().trim();
      if (s.isEmpty) return null;
      final n = int.tryParse(s);
      if (n != null) return parseDateTime(n);
      return DateTime.tryParse(s);
    }

    List<Map<String, dynamic>> parseJsonMapList(dynamic v) {
      if (v == null) return <Map<String, dynamic>>[];
      try {
        final decoded = v is String ? jsonDecode(v) : v;
        return List<Map<String, dynamic>>.from(decoded as List);
      } catch (_) {
        return <Map<String, dynamic>>[];
      }
    }

    List<String> parseJsonStringList(dynamic v) {
      if (v == null) return <String>[];
      try {
        final decoded = v is String ? jsonDecode(v) : v;
        return List<String>.from(decoded as List);
      } catch (_) {
        return <String>[];
      }
    }

    List<CheckDetail>? parseChecks(dynamic v) {
      if (v == null) return null;
      try {
        final list = v is String ? jsonDecode(v) : v;
        return (list as List)
            .map((e) => CheckDetail.fromMap(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {
        return null;
      }
    }

    List<Installment>? parseInst(dynamic v) {
      if (v == null) return null;
      try {
        final list = v is String ? jsonDecode(v) : v;
        return (list as List)
            .map((e) => Installment.fromMap(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {
        return null;
      }
    }

    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString());
    }

    String asString(dynamic v) => v?.toString() ?? '';

    final createdAt = parseDateTime(map['created_at']);
    final updatedAt = parseDateTime(map['updated_at']);

    PaymentType parsePaymentType(dynamic v) {
      final s = (v ?? map['payment_type'] ?? 'cash').toString();
      try {
        return PaymentType.values.byName(s);
      } catch (_) {
        return PaymentType.values.firstWhere(
          (e) => describeEnum(e) == s,
          orElse: () => PaymentType.cash,
        );
      }
    }

    return Repair(
      id: asString(map['id']),
      invoiceNumber: asString(map['invoiceNumber'] ?? map['invoice_number']),
      vehicleModel: asString(map['vehicleModel'] ?? map['vehicle_model']),
      vehicleType: asString(map['vehicleType'] ?? map['vehicle_type']),
      vehicleNumber: asString(map['vehicleNumber'] ?? map['vehicle_number']),
      receivedDate:
          parseDateTime(map['receivedDate'] ?? map['received_date']) ??
              DateTime.fromMillisecondsSinceEpoch(0),

      beneficiaryType:
          asString(map['beneficiary_type'] ?? map['beneficiaryType']),
      beneficiaryName:
          asString(map['beneficiaryName'] ?? map['beneficiary_name']),
      clientId: parseInt(map['client_id'] ?? map['clientId']),
      insuranceStatus:
          asString(map['insuranceStatus'] ?? map['insurance_status']),
      repairType: asString(map['repairType'] ?? map['repair_type']),
      vehicleStatus: asString(map['repair_status'] ?? map['vehicleStatus']),

      // Quote workflow
      status: (map['status'] ?? '').toString().isNotEmpty
          ? map['status'].toString()
          : RepairStatusText.invoiced,
      quoteNumber: (map['quoteNumber'] ?? map['quote_number'])?.toString(),
      quoteValidUntil:
          parseDateTime(map['quoteValidUntil'] ?? map['quote_valid_until']),
      approvedAt: parseDateTime(map['approvedAt'] ?? map['approved_at']),
      approvedBy: (map['approvedBy'] ?? map['approved_by'])?.toString(),

      insuranceFollowUpStatus:
          (map['insurance_followup'] ?? map['insuranceFollowUpStatus'])
              ?.toString(),

      parts: parseJsonMapList(map['parts']),
      works: parseJsonMapList(map['works']),
      fileValue: tryDouble(map['fileValue']) ??
          tryDouble(map['file_value']) ??
          tryDouble(map['total_file_value']) ??
          tryDouble(map['finalApprovedAmount']) ??
          tryDouble(map['final_approved_amount']) ??
          0.0,
      paymentType: parsePaymentType(map['paymentType']),

      // ---------------------- أهم سطر تم إصلاحه ----------------------
      paidAmount: tryDouble(map['total_paid_amount']) ??
          tryDouble(map['paid_amount']) ??
          tryDouble(map['paidAmount']) ??
          0.0,
      // -------------------------------------------------------------

      paymentStatus:
          map['paymentStatus']?.toString() ?? map['payment_status']?.toString(),

      checkDetails: parseChecks(map['checkDetails']),
      installmentSchedule: parseInst(map['installmentSchedule']),

      notes: map['notes']?.toString(),
      imagePaths: parseJsonStringList(map['imagePaths']),

      // Cover
      thumbnailPath:
          (map['thumbnail_path'] ?? map['thumbnailPath'])?.toString(),
      thumbnailUpdatedAt: parseDateTime(
          map['thumbnail_updated_at'] ?? map['thumbnailUpdatedAt']),

      // Transfers
      transferFromAccount: map['transferFromAccount']?.toString(),
      transferToAccount: map['transferToAccount']?.toString(),
      transferCompany: map['transferCompany']?.toString(),
      transferDate: parseDateTime(map['transferDate'] ?? map['transfer_date']),
      transferAmount: tryDouble(map['transferAmount']),
      transferImagePath: map['transferImagePath']?.toString(),

      // Flags
      isArchived: (map['isArchived'] == 1) || (map['isArchived'] == true),
      actualCost: tryDouble(map['actualCost']),
      workCost: tryDouble(map['workCost']),
      incomeAmount: tryDouble(map['incomeAmount']),
      isLedgerEnabled:
          (map['isLedgerEnabled'] == 1) || (map['isLedgerEnabled'] == true),
      isLedgerSynced:
          (map['isLedgerSynced'] == 1) || (map['isLedgerSynced'] == true),
      finalApprovedAmount: tryDouble(map['finalApprovedAmount']),

      invoiceId: (map['invoice_id'] ?? map['invoiceId'])?.toString(),

      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  // ================= Computed ===================
  static double _lineValue(Map<String, dynamic> item) {
    final explicit = tryDouble(item['total']);
    if (explicit != null && explicit != 0) return explicit;
    final qty = tryDouble(item['qty'] ?? item['quantity']) ?? 1.0;
    final price = tryDouble(
          item['price'] ?? item['unit_price'] ?? item['unitPrice'],
        ) ??
        0.0;
    return (qty <= 0 ? 1.0 : qty) * price;
  }

  double get totalPartsPrice =>
      parts.fold<double>(0.0, (sum, item) => sum + _lineValue(item));

  double get totalWorksPrice =>
      works.fold<double>(0.0, (sum, item) => sum + _lineValue(item));

  /// Canonical commercial value is the persisted repair fileValue.
  /// The line totals are descriptive/detail data and may intentionally exclude
  /// customer/insurer supplied parts.
  double get totalFileValue => fileValue;

  double get totalPaidAmount {
    double total = paidAmount;
    if (checkDetails != null) {
      total += checkDetails!.fold<double>(0.0, (s, c) => s + c.amount);
    }
    if (installmentSchedule != null) {
      total += installmentSchedule!
          .where((inst) => inst.paid)
          .fold<double>(0.0, (s, inst) => s + inst.amount);
    }
    if (transferAmount != null) {
      total += transferAmount!;
    }
    return total;
  }

  double get remainingAmount {
    final value = totalFileValue - totalPaidAmount;
    return value < 0 ? 0.0 : value;
  }

  bool get isClosed => remainingAmount <= 0;

  String get computedPaymentStatus {
    if (totalFileValue <= 0) return 'مسدد';
    if (totalPaidAmount <= 0) return 'غير مسدد';
    if (totalPaidAmount >= totalFileValue) return 'مسدد';
    return 'مسدد جزئي';
  }

  String get displayPaymentStatus => (paymentStatus?.trim().isNotEmpty ?? false)
      ? paymentStatus!.trim()
      : computedPaymentStatus;

  String get customerName => beneficiaryName;

  String get paymentMethodText {
    switch (paymentType) {
      case PaymentType.cash:
        return 'نقداً';
      case PaymentType.check:
        return 'شيك';
      case PaymentType.installment:
        return 'أقساط';
      case PaymentType.insuranceTransfer:
        return 'تحويل بنكي/تأمين';
    }
  }

  String get paymentMethod {
    switch (paymentType) {
      case PaymentType.cash:
        return 'صندوق';
      case PaymentType.check:
      case PaymentType.insuranceTransfer:
        return 'بنك';
      case PaymentType.installment:
        return 'أقساط';
    }
  }

  double get remaining => remainingAmount;

  bool validate() {
    if (invoiceNumber.isEmpty ||
        vehicleModel.isEmpty ||
        vehicleType.isEmpty ||
        vehicleNumber.isEmpty ||
        beneficiaryName.isEmpty ||
        parts.isEmpty) {
      return false;
    }
    if (checkDetails != null && checkDetails!.any((c) => !c.validateDates())) {
      return false;
    }
    if (installmentSchedule != null &&
        installmentSchedule!.any((i) => !i.validateDueDate())) {
      return false;
    }
    return true;
  }
}
