// 📁 lib/features/insurance_agent/policies/models/policy_draft.dart
//
// PolicyDraft — نموذج مؤقت لتجميع بيانات البوليصة عبر عدة خطوات (Wizard)
// ✅ يدعم خطط الدفع: نقد / شيكات / نقد+شيكات / تقسيط / تقسيط بكمبيالة / تقسيط بدون كمبيالة
// ✅ جاهز لاحقًا للتحويل إلى DB عبر toMap()

class PolicyDraft {
  // ===== Canonical identity / idempotency =====
  String? operationId;
  String? documentNumber;
  String? policyNumber;
  String? previousPolicyId;
  DateTime? postingDate;

  // ===== Vehicle (الحقول الجديدة) =====
  String? vehiclePlate; // رقم اللوحة
  String? vehicleMake; // الشركة/النوع
  String? vehicleModelYear; // موديل السنة
  String? engineCc; // حجم المحرك CC (نص)
  String? engineNumber;
  String? chassisNumber;

  // ===== Legacy (للتوافق) =====
  String? vehicleType;
  String? vehicleNumber;
  String? engineSize;

  // ===== Insured =====
  String? insuredName;
  String? insuredPhone;

  // ===== Company & Dates =====
  int? insuranceCompanyId;
  String? companyName;
  String? productId;
  String? coverageType;
  final List<String> coverageIds = [];
  DateTime? startDate;
  DateTime? endDate;
  bool isVip = false;

  // ===== Pricing =====
  double? buyPrice;
  double? sellPrice;

  // ===== Payment Plan =====
  PolicyPaymentPlan payment = PolicyPaymentPlan();

  // ===== Notes =====
  String? notes;

  PolicyDraft();

  void reset() {
    operationId = null;
    documentNumber = null;
    policyNumber = null;
    previousPolicyId = null;
    postingDate = null;

    vehiclePlate = null;
    vehicleMake = null;
    vehicleModelYear = null;
    engineCc = null;
    engineNumber = null;
    chassisNumber = null;

    vehicleType = null;
    vehicleNumber = null;
    engineSize = null;

    insuredName = null;
    insuredPhone = null;

    insuranceCompanyId = null;
    companyName = null;
    productId = null;
    coverageType = null;
    coverageIds.clear();
    startDate = null;
    endDate = null;
    isVip = false;

    buyPrice = null;
    sellPrice = null;

    payment = PolicyPaymentPlan();

    notes = null;
  }

  // توافُق: لو في مكان يستخدم الحقول القديمة
  void syncLegacyFromNew() {
    vehicleNumber = vehiclePlate;
    vehicleType = vehicleMake;
    engineSize = engineCc;
  }

  bool get isValidBasic {
    final plate = (vehiclePlate ?? vehicleNumber ?? '').trim();
    final company = (companyName ?? '').trim();
    final insurerPolicyNumber = (policyNumber ?? '').trim();
    return plate.isNotEmpty &&
        company.isNotEmpty &&
        insurerPolicyNumber.isNotEmpty &&
        startDate != null &&
        endDate != null;
  }
}

/// ============================================================================
/// Payment Plan Models
/// ============================================================================

enum PolicyPaymentPlanType {
  cashOnly,
  chequesOnly,
  cashPlusCheques,
  installmentsWithPromissory,
  installmentsNoPromissory,
}

class PolicyPaymentPlan {
  PolicyPaymentPlanType type = PolicyPaymentPlanType.cashOnly;

  /// Canonical receipt method for the immediate part of the plan.
  /// Supported values are CASH and BANK.
  String immediatePaymentMethod = 'CASH';

  // Cash
  double? cashAmount;

  // Cheques
  final List<PolicyChequeItem> cheques = [];

  // Installments
  final List<PolicyInstallmentItem> installments = [];

  // Promissory notes (كمبيالات)
  final List<PolicyPromissoryItem> promissories = [];

  void clearAllDetails() {
    cashAmount = null;
    cheques.clear();
    installments.clear();
    promissories.clear();
  }

  double get totalCheques => cheques.fold(0.0, (p, e) => p + (e.amount ?? 0.0));

  double get totalInstallments =>
      installments.fold(0.0, (p, e) => p + (e.amount ?? 0.0));

  double get totalPromissories =>
      promissories.fold(0.0, (p, e) => p + (e.amount ?? 0.0));

  double get totalCash => cashAmount ?? 0.0;

  double totalByType() {
    switch (type) {
      case PolicyPaymentPlanType.cashOnly:
        return totalCash;
      case PolicyPaymentPlanType.chequesOnly:
        return totalCheques;
      case PolicyPaymentPlanType.cashPlusCheques:
        return totalCash + totalCheques;
      case PolicyPaymentPlanType.installmentsNoPromissory:
        return totalInstallments;
      case PolicyPaymentPlanType.installmentsWithPromissory:
        return promissories.isNotEmpty ? totalPromissories : totalInstallments;
    }
  }

  /// تحقق صارم — يرجّع قائمة مشاكل (فاضية يعني تمام)
  List<String> validateAgainst(double? sellPrice) {
    final issues = <String>[];
    final sell = sellPrice ?? 0.0;

    if (sell <= 0) {
      issues.add('سعر بيع البوليصة مطلوب وأكبر من 0');
      return issues;
    }

    switch (type) {
      case PolicyPaymentPlanType.cashOnly:
        if (cashAmount == null || cashAmount! <= 0) {
          issues.add('مطلوب إدخال مبلغ الدفع النقدي');
        }
        break;

      case PolicyPaymentPlanType.chequesOnly:
        if (cheques.isEmpty) issues.add('أضف شيك واحد على الأقل');
        for (final c in cheques) {
          issues.addAll(c.validate());
        }
        break;

      case PolicyPaymentPlanType.cashPlusCheques:
        if (cashAmount == null || cashAmount! <= 0) {
          issues.add('مطلوب إدخال مبلغ الدفعة النقدية');
        }
        if (cheques.isEmpty) issues.add('أضف شيك واحد على الأقل');
        for (final c in cheques) {
          issues.addAll(c.validate());
        }
        break;

      case PolicyPaymentPlanType.installmentsNoPromissory:
        if (installments.isEmpty) issues.add('أضف قسط واحد على الأقل');
        for (final i in installments) {
          issues.addAll(i.validate());
        }
        break;

      case PolicyPaymentPlanType.installmentsWithPromissory:
        if (installments.isEmpty && promissories.isEmpty) {
          issues.add('أضف جدول أقساط/كمبيالات');
        }
        for (final i in installments) {
          issues.addAll(i.validate());
        }
        for (final p in promissories) {
          issues.addAll(p.validate(requireImage: true));
        }
        break;
    }

    final total = totalByType();
    final diff = (total - sell).abs();

    if (diff > 0.01) {
      issues.add('مجموع المدفوعات يجب أن يساوي سعر البيع تمامًا');
    }

    return issues;
  }
}

class PolicyChequeItem {
  DateTime? issueDate;
  DateTime? dueDate;
  double? amount;
  String? bankName;
  String? drawerName;
  String? chequeNumber;
  String? imagePath; // لاحقًا عبر picker

  List<String> validate() {
    final issues = <String>[];
    if (issueDate == null) issues.add('تاريخ إصدار الشيك مطلوب');
    if (dueDate == null) issues.add('تاريخ استحقاق الشيك مطلوب');
    if (issueDate != null && dueDate != null && dueDate!.isBefore(issueDate!)) {
      issues.add('تاريخ استحقاق الشيك لا يجوز أن يسبق تاريخ الإصدار');
    }
    if (amount == null || amount! <= 0) issues.add('قيمة الشيك مطلوبة');
    if ((bankName ?? '').trim().isEmpty) issues.add('اسم البنك مطلوب');
    if ((drawerName ?? '').trim().isEmpty) issues.add('اسم الساحب مطلوب');
    if ((chequeNumber ?? '').trim().isEmpty) issues.add('رقم الشيك مطلوب');
    return issues;
  }
}

class PolicyInstallmentItem {
  DateTime? dueDate;
  double? amount;
  String? note;

  List<String> validate() {
    final issues = <String>[];
    if (dueDate == null) issues.add('تاريخ القسط مطلوب');
    if (amount == null || amount! <= 0) issues.add('قيمة القسط مطلوبة');
    return issues;
  }
}

class PolicyPromissoryItem {
  DateTime? dueDate;
  double? amount;
  String? imagePath;

  List<String> validate({bool requireImage = false}) {
    final issues = <String>[];
    if (dueDate == null) issues.add('تاريخ الكمبيالة مطلوب');
    if (amount == null || amount! <= 0) issues.add('قيمة الكمبيالة مطلوبة');
    if (requireImage && (imagePath ?? '').trim().isEmpty) {
      issues.add('صورة الكمبيالة مطلوبة');
    }
    return issues;
  }
}
