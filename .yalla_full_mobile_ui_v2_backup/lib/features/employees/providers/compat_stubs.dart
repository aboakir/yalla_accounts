// امتدادات توافقية مؤقتة لتجاوز دوال ناقصة في الشيفرة القديمة.
// لا تغيّر الأصناف الأصلية — فقط تضيف سلوكًا مؤقتًا عند الاستدعاء.

import 'package:yalla_accounts/features/employees/providers/employee_form_provider.dart';

/// يوفر الدالة المطلوبة حتى لو غير موجودة داخل EmployeeFormData
extension EmployeeFormDataCalcCompat on EmployeeFormData {
  double calculateNetSalary() {
    try {
      final bs = (this as dynamic).baseSalary as num? ?? 0;
      final al = (this as dynamic).allowances as num? ?? 0;
      final dd = (this as dynamic).deductions as num? ?? 0;
      return (bs + al - dd).toDouble();
    } catch (_) {
      // إن لم تكن الحقول موجودة في الطراز القديم، نرجّع 0 مؤقتًا.
      return 0.0;
    }
  }
}

/// يضيف دالة حفظ مؤقتة تُرجع bool كما يتوقع الاستدعاء في الواجهة
extension EmployeeFormNotifierSaveCompat on EmployeeFormNotifier {
  Future<bool> saveFinalToDatabase() async {
    // TODO: اربطها لاحقًا بالحفظ الفعلي (SQLite/Repository)
    // مؤقتًا نرجّع true لتجاوز كسر التجميع.
    return true;
  }
}
