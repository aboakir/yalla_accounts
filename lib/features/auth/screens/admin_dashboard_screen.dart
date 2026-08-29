// 📁 lib/features/auth/screens/admin_dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';
import 'package:yalla_accounts/features/auth/widgets/add_user_dialog.dart';
import 'package:yalla_accounts/features/auth/widgets/edit_user_dialog.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<AppUser> _pendingUsers = [];
  List<AppUser> _activeUsers = [];
  List<AppUser> _frozenUsers = [];
  List<AppUser> _filteredUsers = [];

  final TextEditingController _searchController = TextEditingController();
  String _currentView = 'active';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    final users = await ref.read(userServiceProvider).getAllUsers();

    setState(() {
      _pendingUsers = users.where((u) => u.status == 'pending').toList();
      _activeUsers = users.where((u) => u.status == 'active').toList();
      _frozenUsers = users
          .where((u) => u.status == 'frozen' || u.status == 'inactive')
          .toList();
      _updateFilteredUsers();
    });
  }

  void _updateFilteredUsers() {
    switch (_currentView) {
      case 'pending':
        _filteredUsers = _pendingUsers;
        break;
      case 'frozen':
        _filteredUsers = _frozenUsers;
        break;
      case 'active':
      default:
        _filteredUsers = _activeUsers;
    }
  }

  void _filterUsers(String query) {
    final listToFilter = _currentView == 'pending'
        ? _pendingUsers
        : _currentView == 'frozen'
            ? _frozenUsers
            : _activeUsers;
    setState(() {
      _filteredUsers = listToFilter
          .where((u) =>
              u.name.toLowerCase().contains(query.toLowerCase()) ||
              u.email.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  Future<void> _logout() async {
    await ref.read(authSessionServiceProvider).logout();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _toggleFreeze(AppUser user) async {
    final newStatus = user.status == 'frozen' ? 'active' : 'frozen';
    await ref.read(userServiceProvider).updateStatus(user.id, newStatus);
    await _loadUsers();
  }

  Future<void> _showAddUserDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => const AddUserDialog(),
    );
    if (result == true) await _loadUsers();
  }

  Future<void> _showEditUserDialog(AppUser user) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => EditUserDialog(user: user),
    );
    if (result == true) await _loadUsers();
  }

  Future<void> _deleteUser(AppUser user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد التعطيل'),
        content: Text('هل تريد تعطيل المستخدم ${user.name}؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تعطيل')),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(userServiceProvider).deleteUser(user.id);
      await _loadUsers();
    }
  }

  Future<void> _approveUser(AppUser user) async {
    await ref.read(userServiceProvider).updateStatus(user.id, 'active');
    await _loadUsers();
  }

  Widget _buildRoleChip(String role) {
    return Chip(label: Text(RoleKeys.displayNameAr(role)));
  }

  DataRow _buildUserRow(AppUser user) {
    return DataRow(cells: [
      DataCell(Text(user.name)),
      DataCell(Text(user.email)),
      DataCell(_buildRoleChip(user.role)),
      DataCell(Text(_translateStatus(user.status))),
      DataCell(Row(children: [
        if (_currentView == 'pending')
          IconButton(
            icon: const Icon(Icons.check, color: Colors.green),
            tooltip: 'قبول المستخدم',
            onPressed: () => _approveUser(user),
          )
        else ...[
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'تعديل',
            onPressed: () => _showEditUserDialog(user),
          ),
          IconButton(
            icon: Icon(user.status == 'frozen' ? Icons.lock_open : Icons.lock),
            tooltip: user.status == 'frozen' ? 'إلغاء التجميد' : 'تجميد الحساب',
            onPressed: () => _toggleFreeze(user),
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'تعطيل المستخدم',
            onPressed: () => _deleteUser(user),
          ),
        ]
      ])),
    ]);
  }

  void _changeView(int index) {
    setState(() {
      _currentView = ['pending', 'active', 'frozen'][index];
      _updateFilteredUsers();
      _searchController.clear();
    });
  }

  String _translateStatus(String status) {
    switch (status) {
      case 'active':
        return 'نشط';
      case 'frozen':
        return 'مجمد';
      case 'pending':
        return 'في الانتظار';
      case 'inactive':
        return 'غير نشط';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    if (currentUser == null || !currentUser.isOwner) {
      return const Scaffold(
        body: Center(child: Text('لا تملك صلاحية الوصول لهذه الشاشة')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة تحكم المدير'),
        backgroundColor: AppColors.primary,
        bottom: TabBar(
          controller: _tabController,
          onTap: _changeView,
          tabs: const [
            Tab(text: 'طلبات الاشتراك'),
            Tab(text: 'النشطين'),
            Tab(text: 'المجمدين'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'طلبات الاشتراك المعلقة',
            icon: const Icon(Icons.subscriptions),
            onPressed: () {
              Navigator.pushNamed(context, '/admin-subscriptions');
            },
          ),
          IconButton(
              onPressed: _showAddUserDialog,
              icon: const Icon(Icons.person_add)),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'بحث بالاسم أو البريد',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: _filterUsers,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('الاسم')),
                    DataColumn(label: Text('البريد')),
                    DataColumn(label: Text('الدور')),
                    DataColumn(label: Text('الحالة')),
                    DataColumn(label: Text('إجراءات')),
                  ],
                  rows: _filteredUsers.map(_buildUserRow).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
