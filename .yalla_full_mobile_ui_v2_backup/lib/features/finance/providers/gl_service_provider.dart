// TODO Implement this library.
// 📁 lib/features/finance/providers/gl_service_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/finance/services/gl_service.dart';

// تعريف الـ provider لـ GLService
final glServiceProvider = Provider<GLService>((ref) {
  return GLService();
});
