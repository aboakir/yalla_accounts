import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user.dart';

/// مزود الحالة لحفظ بيانات المستخدم المسجل حالياً أو null إذا لم يتم تسجيل الدخول
final authProvider = StateProvider<User?>((ref) => null);

/// مزود إضافي لعرض حالة تسجيل الدخول (مسجل أو لا)
final isAuthenticatedProvider = Provider<bool>((ref) {
  final user = ref.watch(authProvider);
  return user != null;
});
