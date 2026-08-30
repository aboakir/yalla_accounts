import 'package:intl/intl.dart';

class PolicyFilters {
  /// ✅ Public static parser (used by screen + table)
  static DateTime? parsePolicyDate(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;

    // ISO: yyyy-MM-dd OR yyyy-MM-ddTHH:mm:ss
    try {
      return DateTime.parse(s);
    } catch (_) {}

    // dd/MM/yyyy
    try {
      return DateFormat('dd/MM/yyyy').parseStrict(s);
    } catch (_) {}

    return null;
  }

  static bool _isExpired(Map<String, dynamic> r) {
    final end = parsePolicyDate(r['end_date']);
    if (end == null) return false;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return end.isBefore(today);
  }

  static bool _isExpiringWithinDays(Map<String, dynamic> r, int days) {
    final end = parsePolicyDate(r['end_date']);
    if (end == null) return false;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (end.isBefore(today)) return false;
    return end.isBefore(now.add(Duration(days: days)));
  }

  static bool matchesFilters(
    Map<String, dynamic> r, {
    required String query,
    required String? companyFilter,
    required bool vipOnly,
    required bool expiredOnly,
    required bool expiringSoonOnly,
    required bool expiring30Only,
  }) {
    final plate = (r['vehicle_plate'] ?? '').toString();
    final name = (r['insured_name'] ?? '').toString();
    final phone = (r['insured_phone'] ?? '').toString();
    final company = (r['company_name'] ?? '').toString();

    if (query.isNotEmpty) {
      final hay = '$plate $name $phone $company'.toLowerCase();
      if (!hay.contains(query.toLowerCase())) return false;
    }

    if (companyFilter != null && company != companyFilter) return false;

    final isVip = (r['is_vip'] ?? 0) == 1;
    if (vipOnly && !isVip) return false;

    if (expiredOnly && !_isExpired(r)) return false;

    // 12 days
    if (expiringSoonOnly && !_isExpiringWithinDays(r, 12)) return false;

    // 30 days
    if (expiring30Only && !_isExpiringWithinDays(r, 30)) return false;

    return true;
  }
}
