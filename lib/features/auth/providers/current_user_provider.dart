import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';

final currentUserProvider = StateProvider<AppUser?>((ref) => null);

final isLoggedInProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserProvider);
  return user != null;
});
