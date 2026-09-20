// 📁 lib/features/insurance_agent/policies/utils/policy_date_utils.dart
//
// PolicyDateUtils — Helpers for parsing dates + status flags
// - parsePolicyDate
// - isExpiredPolicy
// - isExpiringSoonPolicy (within N days)
// - resolvePolicyStatus (text + color key)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class PolicyDateUtils {
  PolicyDateUtils._();

  /// Parse date from:
  /// - ISO: yyyy-MM-dd or yyyy-MM-ddTHH:mm:ss
  /// - dd/MM/yyyy
  /// Returns null if invalid.
  static DateTime? parsePolicyDate(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;

    // ISO
    try {
      return DateTime.parse(s);
    } catch (_) {}

    // dd/MM/yyyy
    try {
      return DateFormat('dd/MM/yyyy').parseStrict(s);
    } catch (_) {}

    return null;
  }

  /// Expired if end_date < today (date-only comparison).
  static bool isExpiredPolicy(Map<String, dynamic> row) {
    final end = parsePolicyDate(row['end_date']);
    if (end == null) return false;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return end.isBefore(today);
  }

  /// Expiring soon if end_date is within [days] starting today (and not expired).
  static bool isExpiringSoonPolicy(
    Map<String, dynamic> row, {
    int days = 12,
  }) {
    final end = parsePolicyDate(row['end_date']);
    if (end == null) return false;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (end.isBefore(today)) return false;
    return end.isBefore(now.add(Duration(days: days)));
  }

  /// Returns status label + color (not AppColors, pure UI color).
  static PolicyStatus resolvePolicyStatus(
    Map<String, dynamic> row, {
    int soonDays = 12,
  }) {
    final expired = isExpiredPolicy(row);
    if (expired) {
      return const PolicyStatus(label: 'منتهية', color: Colors.red);
    }

    final soon = isExpiringSoonPolicy(row, days: soonDays);
    if (soon) {
      return const PolicyStatus(label: 'تنتهي قريباً', color: Colors.orange);
    }

    return const PolicyStatus(label: 'سارية', color: AppColors.primary);
  }
}

class PolicyStatus {
  final String label;
  final Color color;
  const PolicyStatus({required this.label, required this.color});
}
