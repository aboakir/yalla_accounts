import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';

/// مزود لإدارة قائمة المستخدمين مع تحميل وتحديث البيانات
final userListProvider =
    StateNotifierProvider<UserListNotifier, List<AppUser>>((ref) {
  return UserListNotifier(ref);
});

class UserListNotifier extends StateNotifier<List<AppUser>> {
  final Ref ref;

  UserListNotifier(this.ref) : super([]) {
    loadUsers();
  }

  Future<void> loadUsers() async {
    try {
      final users = await ref.read(userServiceProvider).getAllUsers();
      state = users;
    } catch (e) {
      state = [];
    }
  }

  Future<void> refresh() => loadUsers();

  void addOrUpdateUser(AppUser user) {
    final index = state.indexWhere((u) => u.id == user.id);
    if (index == -1) {
      state = [...state, user];
    } else {
      final newList = [...state];
      newList[index] = user;
      state = newList;
    }
  }

  void removeUserById(String id) {
    state = state.where((user) => user.id != id).toList();
  }
}

/// ✅ مزود المستخدم الحالي
final currentUserProvider = Provider<AppUser?>((ref) {
  final userList = ref.watch(userListProvider);
  return userList.isNotEmpty ? userList.first : null;
});
