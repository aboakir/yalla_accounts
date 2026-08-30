// 📁 lib/shared/errors/app_errors.dart
//
// أخطاء موحّدة للتعامل مع السلوك المحاسبي/الـDB/الـUI
// الهدف: throw نظيف + رسائل مستخدم واضحة

class AppError implements Exception {
  final String code;
  final String message;
  const AppError(this.code, this.message);

  @override
  String toString() => '$code: $message';
}

/// DB أخطاء قاعدة البيانات
class DbError extends AppError {
  const DbError(String message) : super('DB_ERROR', message);
}

/// GL أخطاء القيود المحاسبية
class GlError extends AppError {
  const GlError(String message) : super('GL_ERROR', message);
}

/// مدخلات غير صالحة
class ValidationError extends AppError {
  const ValidationError(String message) : super('VALIDATION_ERROR', message);
}

/// بيانات ناقصة أو غير موجودة
class NotFoundError extends AppError {
  const NotFoundError(String message) : super('NOT_FOUND', message);
}

/// حالة غير منطقية في النظام (مثلاً توازن غير صحيح)
class StateIntegrityError extends AppError {
  const StateIntegrityError(String message)
      : super('STATE_INTEGRITY_ERROR', message);
}

/// فشل عملية (مثلاً فشل ترحيل/عكس)
class OperationError extends AppError {
  const OperationError(String message) : super('OPERATION_FAILED', message);
}

// ✅ استخدم رسائل عربية قصيرة وواضحة عند الرمي
// مثال:
// throw ValidationError("المبلغ يجب أن يكون أكبر من صفر");
// throw NotFoundError("المورّد غير موجود");
// throw GlError("القيد غير متوازن");
