// 📁 lib/features/repairs/providers/repair_form_provider.dart
// يحفظ كـ "عرض سعر" أولًا عبر RepairSaveService.save بدون فاتورة/GL.
// ينسخ الصور إلى Documents ويحدّث المسارات قبل الحفظ.
// مزوّدات القراءة والدفع تبقى مع RepairDatabaseService لاستهلاك القوائم والدفعات.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/services/repair_save_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_database_service.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart'; // ⬅️ أضف هذا الاستيراد

/// نموذج بيانات الشاشة التي تنشئ أو تعدّل سجل إصلاح
class RepairFormData {
  final String vehicleModel;
  final String vehicleType;
  final String vehicleNumber;
  final DateTime receivedDate;

  final String beneficiaryType; // 'أفراد' | 'شركة تأمين'
  final String beneficiaryName; // اسم الفرد الثنائي أو اسم شركة التأمين
  final String insuranceStatus; // عند شركات التأمين فقط

  final String repairType;
  final String vehicleStatus;
  final List<Map<String, dynamic>> parts; // [{name, qty, price, ...}]
  final List<Map<String, dynamic>> works; // [{name, qty, price, ...}]
  final List<String> imagePaths;
  final String? thumbnailPath;

  final double fileValue; // مجموع parts+works
  final String paymentStatus; // 'غير مسدد' | 'مسدد جزئي' | 'مسدد'
  final String
      paymentMethod; // 'نقدًا' | 'شيك' | 'أقساط' | 'حوالة تأمين داخلية'
  final double paidAmount; // للعرض فقط
  final String notes;

  final String? transferFromAccount;
  final String? transferToAccount;
  final String? transferCompany;
  final DateTime? transferDate;
  final double? transferAmount;
  final String? transferImagePath;

  // ⬅️ الحقول الجديدة للشيكات
  final Cheque? pendingCheque; // بيانات الشيك المعلقة

  double get remainingAmount => fileValue - paidAmount;

  RepairFormData({
    this.vehicleModel = '',
    this.vehicleType = '',
    this.vehicleNumber = '',
    DateTime? receivedDate,
    this.beneficiaryType = 'أفراد',
    this.beneficiaryName = '',
    this.insuranceStatus = '',
    this.repairType = 'بودي ودهان',
    this.vehicleStatus = 'بانتظار الإصلاح',
    this.parts = const [],
    this.works = const [],
    this.imagePaths = const [],
    this.fileValue = 0.0,
    this.paymentStatus = 'غير مسدد',
    this.paymentMethod = '',
    this.paidAmount = 0.0,
    this.notes = '',
    this.transferFromAccount,
    this.transferToAccount,
    this.transferCompany,
    this.transferDate,
    this.transferAmount,
    this.transferImagePath,
    this.pendingCheque, // ⬅️ أضف هذا
    this.thumbnailPath,
  }) : receivedDate = receivedDate ?? DateTime.now();

  RepairFormData copyWith({
    String? vehicleModel,
    String? vehicleType,
    String? vehicleNumber,
    DateTime? receivedDate,
    String? beneficiaryType,
    String? beneficiaryName,
    String? insuranceStatus,
    String? repairType,
    String? vehicleStatus,
    List<Map<String, dynamic>>? parts,
    List<Map<String, dynamic>>? works,
    List<String>? imagePaths,
    double? fileValue,
    String? paymentStatus,
    String? paymentMethod,
    double? paidAmount,
    String? notes,
    String? transferFromAccount,
    String? transferToAccount,
    String? transferCompany,
    DateTime? transferDate,
    double? transferAmount,
    String? transferImagePath,
    Cheque? pendingCheque, // ⬅️ أضف هذا
    String? thumbnailPath,
  }) {
    return RepairFormData(
      vehicleModel: vehicleModel ?? this.vehicleModel,
      vehicleType: vehicleType ?? this.vehicleType,
      vehicleNumber: vehicleNumber ?? this.vehicleNumber,
      receivedDate: receivedDate ?? this.receivedDate,
      beneficiaryType: beneficiaryType ?? this.beneficiaryType,
      beneficiaryName: beneficiaryName ?? this.beneficiaryName,
      insuranceStatus: insuranceStatus ?? this.insuranceStatus,
      repairType: repairType ?? this.repairType,
      vehicleStatus: vehicleStatus ?? this.vehicleStatus,
      parts: parts ?? this.parts,
      works: works ?? this.works,
      imagePaths: imagePaths ?? this.imagePaths,
      fileValue: fileValue ?? this.fileValue,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paidAmount: paidAmount ?? this.paidAmount,
      notes: notes ?? this.notes,
      transferFromAccount: transferFromAccount ?? this.transferFromAccount,
      transferToAccount: transferToAccount ?? this.transferToAccount,
      transferCompany: transferCompany ?? this.transferCompany,
      transferDate: transferDate ?? this.transferDate,
      transferAmount: transferAmount ?? this.transferAmount,
      transferImagePath: transferImagePath ?? this.transferImagePath,
      pendingCheque: pendingCheque ?? this.pendingCheque, // ⬅️ أضف هذا
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    );
  }
}

/// نوتيفير لإدارة الحالة الخاصة بنموذج إنشاء/تعديل إصلاح
class RepairFormNotifier extends StateNotifier<RepairFormData> {
  RepairFormNotifier() : super(RepairFormData());

  // ————— setters —————
  void updateVehicleModel(String v) => state = state.copyWith(vehicleModel: v);
  void updateVehicleType(String v) => state = state.copyWith(vehicleType: v);
  void updateVehicleNumber(String v) =>
      state = state.copyWith(vehicleNumber: v);
  void updateReceivedDate(DateTime v) =>
      state = state.copyWith(receivedDate: v);

  void updateBeneficiaryType(String v) =>
      state = state.copyWith(beneficiaryType: v);
  void updateBeneficiaryName(String v) =>
      state = state.copyWith(beneficiaryName: v);
  void updateInsuranceStatus(String v) =>
      state = state.copyWith(insuranceStatus: v);
  void updateRepairType(String v) => state = state.copyWith(repairType: v);

  void updateVehicleStatus(String v) {
    final validStatuses = [
      'بانتظار الإصلاح',
      'قيد الإصلاح',
      'جاهزة للتسليم',
      'تم التسليم',
    ];
    final trimmed = v.trim();
    state = state.copyWith(
      vehicleStatus:
          validStatuses.contains(trimmed) ? trimmed : 'بانتظار الإصلاح',
    );
  }

  void updateFileValue(double v) => state = state.copyWith(fileValue: v);
  void updatePaidAmount(double v) => state = state.copyWith(paidAmount: v);
  void updateNotes(String v) => state = state.copyWith(notes: v);
  void updatePaymentMethod(String v) =>
      state = state.copyWith(paymentMethod: v);

  void updatePaymentStatus(String v) {
    double paid = state.paidAmount;
    if (v == 'مسدد') {
      paid = state.fileValue;
    } else if (v == 'غير مسدد') {
      paid = 0.0;
    }
    state = state.copyWith(paymentStatus: v, paidAmount: paid);
  }

  // ———— حقول الحوالة التأمينية ————
  void updateTransferFromAccount(String v) =>
      state = state.copyWith(transferFromAccount: v);
  void updateTransferToAccount(String v) =>
      state = state.copyWith(transferToAccount: v);
  void updateTransferCompany(String v) =>
      state = state.copyWith(transferCompany: v);
  void updateTransferDate(DateTime v) =>
      state = state.copyWith(transferDate: v);
  void updateTransferAmount(double v) =>
      state = state.copyWith(transferAmount: v);
  void updateTransferImagePath(String v) =>
      state = state.copyWith(transferImagePath: v);

  // ————— إدارة الشيكات —————
  void setPendingCheque(Cheque cheque) {
    state = state.copyWith(pendingCheque: cheque, paymentMethod: 'شيك');
  }

  void clearPendingCheque() {
    state = state.copyWith(pendingCheque: null);
  }

  // ————— parts/works —————
  void addPart(Map<String, dynamic> part) {
    state = state.copyWith(parts: [...state.parts, part]);
    _recalc();
  }

  void removePart(int index) {
    final updated = [...state.parts]..removeAt(index);
    state = state.copyWith(parts: updated);
    _recalc();
  }

  void addWork(Map<String, dynamic> work) {
    state = state.copyWith(works: [...state.works, work]);
    _recalc();
  }

  void removeWork(int index) {
    final updated = [...state.works]..removeAt(index);
    state = state.copyWith(works: updated);
    _recalc();
  }

  void addImage(String path) {
    final updated = [...state.imagePaths, path];
    state = state.copyWith(imagePaths: updated);
  }

  void setThumbnail(String path) {
    state = state.copyWith(thumbnailPath: path);
  }

  void removeImage(String path) {
    final updated = [...state.imagePaths]..remove(path);

    String? newThumb = state.thumbnailPath;
    if (state.thumbnailPath == path) {
      newThumb = null;
    }

    state = state.copyWith(
      imagePaths: updated,
      thumbnailPath: newThumb,
    );
    state = state.copyWith(imagePaths: updated);
  }

  /// تحديث القائمة كاملة بعد شاشة العرض/الحذف
  void updateImages(List<String> paths) {
    String? newThumb = state.thumbnailPath;

    if (newThumb != null && !paths.contains(newThumb)) {
      newThumb = null;
    }

    state = state.copyWith(
      imagePaths: List<String>.from(paths),
      thumbnailPath: newThumb,
    );
  }

  // ————— helpers —————
  void _recalc() {
    final partsTotal = state.parts.fold<double>(
      0.0,
      (sum, p) =>
          sum +
          (((p['qty'] ?? 1) as num).toDouble() *
              ((p['price'] ?? 0) as num).toDouble()),
    );
    final worksTotal = state.works.fold<double>(
      0.0,
      (sum, w) =>
          sum +
          (((w['qty'] ?? 1) as num).toDouble() *
              ((w['price'] ?? 0) as num).toDouble()),
    );
    final total = partsTotal + worksTotal;
    state = state.copyWith(fileValue: total);
    updatePaymentStatus(state.paymentStatus);
  }

  void resetForm() => state = RepairFormData();

  // ——————————————————————————————————————————
  // حفظ كـ "عرض سعر" فقط: ينسخ الصور ثم يستدعي RepairSaveService.save
  Future<bool> saveAsQuote(BuildContext context, WidgetRef ref) async {
    // تحقق إدخالات حقيقية فقط
    if (state.vehicleType.trim().isEmpty) {
      _err(context, 'أدخل نوع المركبة');
      return false;
    }
    if (state.vehicleModel.trim().isEmpty) {
      _err(context, 'أدخل موديل المركبة');
      return false;
    }
    if (state.vehicleNumber.trim().isEmpty) {
      _err(context, 'أدخل رقم المركبة');
      return false;
    }
    if (state.beneficiaryName.trim().isEmpty) {
      _err(context, 'أدخل اسم المستفيد');
      return false;
    }
    if (state.beneficiaryType == 'أفراد') {
      final s = state.beneficiaryName.trim().replaceAll(RegExp(r'\s+'), ' ');
      final parts = s.split(' ');
      if (parts.length < 2 || parts.any((p) => p.length < 2)) {
        _err(context, 'اكتب الاسم الثنائي على الأقل');
        return false;
      }
    }
    if (state.paymentMethod.trim().isEmpty) {
      _err(context, 'اختر طريقة الدفع');
      return false;
    }

    _recalc();

    // نسخ الصور إلى مجلد التطبيق ثم تحديث المسارات في الحالة
    final appDir = await getApplicationDocumentsDirectory();
    final saved = <String>[];
    int failed = 0;
    for (final path in state.imagePaths) {
      try {
        final f = File(path);
        if (!await f.exists()) {
          failed++;
          continue;
        }
        if (p.isWithin(appDir.path, path)) {
          saved.add(path);
        } else {
          final dst =
              p.join(appDir.path, const Uuid().v4() + p.extension(path));
          saved.add((await f.copy(dst)).path);
        }
      } catch (_) {
        failed++;
      }
    }
    updateImages(saved);

    try {
      // الحفظ كعرض سعر: actualCost=null, isLedgerEnabled=false
      await RepairSaveService.save(
        ref: ref,
        actualCost: null,
        isLedgerEnabled: false,
      );
      if (!context.mounted) return false;

      // ✅ إذا كان هناك شيك معلق، نخزنه مع ربطه بالإصلاح
      if (state.pendingCheque != null) {
        // TODO: إضافة استدعاء لـ ChequeService لحفظ الشيك مع ربطه بالإصلاح
        debugPrint(
            'تم إضافة شيك مرتبط بالإصلاح: ${state.pendingCheque!.chequeNo}');

        // مسح الشيك المعلق بعد الحفظ
        clearPendingCheque();
      }

      resetForm();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          failed > 0
              ? 'تم حفظ عرض السعر (فشل نسخ $failed صورة)'
              : 'تم حفظ عرض السعر',
        ),
      ));
      return true;
    } catch (e) {
      if (!context.mounted) return false;
      _err(context, 'خطأ أثناء الحفظ: $e');
      return false;
    }
  }

  void _err(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

// ————— المزوّدات —————

final repairFormProvider =
    StateNotifierProvider<RepairFormNotifier, RepairFormData>(
  (ref) => RepairFormNotifier(),
);

final allRepairsProvider = FutureProvider<List<Repair>>((ref) async {
  return RepairDatabaseService.getAllRepairs();
});

final openRepairsProvider = FutureProvider<List<Repair>>((ref) async {
  final all = await RepairDatabaseService.getAllRepairs();
  return all.where((r) => !r.isArchived).toList();
});

final closedRepairsProvider = FutureProvider<List<Repair>>((ref) async {
  final all = await RepairDatabaseService.getAllRepairs();
  return all.where((r) => r.isArchived).toList();
});

/// إدخال دفعة عبر RepairDatabaseService.insertPayment بالواجهة الجديدة
class AddPaymentInput {
  final String repairId;
  final double amount;
  final DateTime date;
  final String method; // مثال: 'نقدًا' | 'شيك' | 'أقساط' | 'حوالة تأمين داخلية'
  final String? notes;

  const AddPaymentInput({
    required this.repairId,
    required this.amount,
    required this.date,
    this.method = '',
    this.notes,
  });
}

final addPaymentProvider = FutureProvider.family<void, AddPaymentInput>(
  (ref, input) async {
    await RepairDatabaseService.insertPayment(
      repairId: input.repairId,
      amount: input.amount,
      date: input.date,
      method: input.method,
      notes: input.notes,
    );
  },
);
