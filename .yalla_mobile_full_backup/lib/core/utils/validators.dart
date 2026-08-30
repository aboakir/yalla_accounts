class Validators {
  static String? validateRequired(String? value,
      {String fieldName = 'هذا الحقل'}) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName مطلوب';
    }
    return null;
  }

  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'البريد الإلكتروني مطلوب';
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) return 'بريد إلكتروني غير صالح';
    return null;
  }

  static String? validatePhone(String? value) {
    if (value == null || value.isEmpty) return 'رقم الهاتف مطلوب';
    final phoneRegex = RegExp(r'^[0-9]{7,15}$');
    if (!phoneRegex.hasMatch(value)) return 'رقم هاتف غير صالح';
    return null;
  }

  static String? validateNumber(String? value, {String fieldName = 'القيمة'}) {
    if (value == null || value.isEmpty) return '$fieldName مطلوبة';
    final number = double.tryParse(value);
    if (number == null) return '$fieldName يجب أن تكون رقمًا';
    return null;
  }

  static String? validatePositiveNumber(String? value,
      {String fieldName = 'القيمة'}) {
    final error = validateNumber(value, fieldName: fieldName);
    if (error != null) return error;
    if (double.parse(value!) <= 0) return '$fieldName يجب أن تكون أكبر من صفر';
    return null;
  }
}
