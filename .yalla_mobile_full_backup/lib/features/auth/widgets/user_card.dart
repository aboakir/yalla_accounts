// lib/features/auth_management/widgets/user_card.dart

import 'package:flutter/material.dart';
import '../models/app_user.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class UserCard extends StatelessWidget {
  final AppUser user;
  final VoidCallback? onTap;

  const UserCard({super.key, required this.user, this.onTap});

  Color _roleColor(String role) {
    switch (role) {
      case 'admin':
        return AppColors.primary;
      case 'manager':
        return Colors.orange;
      default:
        return Colors.grey.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withOpacity(0.2),
          foregroundColor: AppColors.primary,
          child: Text(
            user.name.isNotEmpty ? user.name[0].toUpperCase() : '',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
          ),
        ),
        title: Text(
          user.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(user.email),
        trailing: Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
          decoration: BoxDecoration(
            color: _roleColor(user.role).withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _capitalize(user.role),
            style: TextStyle(
              color: _roleColor(user.role),
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        onTap: onTap,
      ),
    );
  }

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }
}
