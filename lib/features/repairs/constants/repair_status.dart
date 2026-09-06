// 📁 lib/features/repairs/constants/repair_status.dart
//
// RepairStatus — القوائم الثابتة الموحّدة لجميع الشاشات.
// تشمل حالات المركبة، أنواع العمل، حالات الدفع، المتابعة التأمينية،
// وثوابت مسار الاعتماد (status) الخاصة بسجل الإصلاح.
//

// 🧩 حالات المركبة
const List<String> kVehicleStatuses = [
  'بانتظار الإصلاح',
  'قيد الإصلاح',
  'جاهزة للتسليم',
  'تم التسليم',
];

// P13: these two states are owned by the formal workflow and must not be
// selected manually from intake/edit forms.
const List<String> kManualVehicleStatuses = [
  'بانتظار الإصلاح',
  'قيد الإصلاح',
];

const List<String> kWorkflowVehicleStatuses = [
  'جاهزة للتسليم',
  'تم التسليم',
];

// 🧩 أنواع العمل
const List<String> kRepairTypes = [
  'بودي ودهان',
  'توريد قطع',
  'دهان وتوريد قطع',
];

// 🧩 حالات السداد / الدفع
const List<String> kPaymentStatuses = [
  'غير مسدد',
  'مسدد جزئي',
  'مسدد',
];

// 🧩 متابعة شركات التأمين
const List<String> kInsuranceFollowups = [
  'المركبة قيد الإصلاح',
  'بانتظار تسليم الفاتورة',
  'بانتظار تسديد التعويضات',
  'بانتظار تسديد المالية',
  'بانتظار الصرف',
  'تم الصرف',
];

// 🧩 مسار الاعتماد (يحفظ في repairs.status)
const String kRepairStatusQuote = 'QUOTE';
const String kRepairStatusApproved = 'APPROVED';
const String kRepairStatusInProgress = 'IN_PROGRESS';
const String kRepairStatusClosed = 'CLOSED';

const List<String> kRepairStatusAll = [
  kRepairStatusQuote,
  kRepairStatusApproved,
  kRepairStatusInProgress,
  kRepairStatusClosed,
];

bool isQuoteStatus(String? s) => s == kRepairStatusQuote;
bool isApprovedStatus(String? s) => s == kRepairStatusApproved;

// 🧩 تطبيع القيم (Normalize)
String? normalizeOrNull(String? value, List<String> validValues) {
  if (value == null) return null;
  for (final v in validValues) {
    if (v.trim() == value.trim()) return v;
  }
  return null;
}

// 🧩 تطبيع مع مراعاة المرادفات
String? normalizeValue(String? value, List<String> validValues,
    {Map<String, String>? aliases}) {
  if (value == null) return null;
  final val = value.trim();

  if (aliases != null && aliases.containsKey(val)) {
    return aliases[val];
  }

  for (final v in validValues) {
    if (v.trim() == val) return v;
  }
  return null;
}

// 🧩 مرادفات نصية لحالات المركبة (توحيد الاختلافات الشائعة)
const Map<String, String> kVehicleStatusAliases = {
  'قيد الاصلاح': 'قيد الإصلاح',
  'بانتظار الاصلاح': 'بانتظار الإصلاح',
  'جاهزه للتسليم': 'جاهزة للتسليم',
};
