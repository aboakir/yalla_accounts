// 📁 lib/features/repairs/services/repairs_filters_service.dart
//
// RepairsFilterService — إدارة فلاتر قسم الإصلاحات + Riverpod state + Presets

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateUtils;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/services/repairs_service.dart';

// ====================== نموذج الفلترة ======================

@immutable
class RepairsFilter {
  final String? from;
  final String? to;
  final String? repairStatus;
  final String? paymentStatus;
  final bool insuranceOnly;
  final String? search;
  final bool newestFirst;

  const RepairsFilter({
    this.from,
    this.to,
    this.repairStatus,
    this.paymentStatus,
    this.insuranceOnly = false,
    this.search,
    this.newestFirst = true,
  });

  RepairsFilter copyWith({
    String? from,
    String? to,
    String? repairStatus,
    String? paymentStatus,
    bool? insuranceOnly,
    String? search,
    bool? newestFirst,
  }) {
    return RepairsFilter(
      from: from ?? this.from,
      to: to ?? this.to,
      repairStatus: repairStatus ?? this.repairStatus,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      insuranceOnly: insuranceOnly ?? this.insuranceOnly,
      search: search ?? this.search,
      newestFirst: newestFirst ?? this.newestFirst,
    );
  }

  bool get isActive =>
      (from?.isNotEmpty == true) ||
      (to?.isNotEmpty == true) ||
      (repairStatus?.isNotEmpty == true) ||
      (paymentStatus?.isNotEmpty == true) ||
      insuranceOnly ||
      (search?.trim().isNotEmpty == true);

  String badgeText() {
    final parts = <String>[];
    if (from != null || to != null) {
      parts.add('من ${from ?? '...'} إلى ${to ?? '...'}');
    }
    if (repairStatus?.isNotEmpty == true) {
      parts.add('حالة إصلاح: $repairStatus');
    }
    if (paymentStatus?.isNotEmpty == true) parts.add('سداد: $paymentStatus');
    if (insuranceOnly) parts.add('تأمين فقط');
    if (search?.trim().isNotEmpty == true) parts.add('بحث: ${search!.trim()}');
    return parts.isEmpty ? 'بدون فلاتر' : parts.join(' • ');
  }

  Map<String, dynamic> toMap() => {
        'from': from,
        'to': to,
        'repairStatus': repairStatus,
        'paymentStatus': paymentStatus,
        'insuranceOnly': insuranceOnly,
        'search': search,
        'newestFirst': newestFirst,
      };

  factory RepairsFilter.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const RepairsFilter();
    String? s(dynamic v) => v?.toString();
    bool b(dynamic v) {
      if (v == null) return false;
      final t = v.toString().toLowerCase();
      return t == 'true' || t == '1' || t == 'yes';
    }

    final from = _normalizeDate(s(map['from']));
    final to = _normalizeDate(s(map['to']));

    return RepairsFilter(
      from: from,
      to: to,
      repairStatus: s(map['repairStatus']),
      paymentStatus: s(map['paymentStatus']),
      insuranceOnly: b(map['insuranceOnly']),
      search: s(map['search']),
      newestFirst: !(s(map['newestFirst'])?.toLowerCase() == 'false'),
    );
  }

  String toJson() => jsonEncode(toMap());
  factory RepairsFilter.fromJson(String src) =>
      RepairsFilter.fromMap(jsonDecode(src));
}

// ====================== Presets ======================

class RepairsFilterPresets {
  static RepairsFilter today() {
    final d = DateTime.now();
    final s = _fmt(d);
    return RepairsFilter(from: s, to: s);
  }

  static RepairsFilter thisWeek() {
    final now = DateTime.now();
    final weekStart = _weekStart(now);
    final weekEnd = DateUtils.dateOnly(weekStart.add(const Duration(days: 6)));
    return RepairsFilter(from: _fmt(weekStart), to: _fmt(weekEnd));
  }

  static RepairsFilter last30Days() {
    final now = DateTime.now();
    final start = DateUtils.dateOnly(now.subtract(const Duration(days: 29)));
    final end = DateUtils.dateOnly(now);
    return RepairsFilter(from: _fmt(start), to: _fmt(end));
  }

  static RepairsFilter thisMonth() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 0);
    return RepairsFilter(from: _fmt(start), to: _fmt(end));
  }
}

// ====================== Fetch Service ======================

class RepairsFilterService {
  static Future<List<Repair>> fetch(RepairsFilter f,
      {int? limit, int? offset}) async {
    final svc = await RepairsService.instance();
    return svc.list(
      from: f.from,
      to: f.to,
      repairStatus: f.repairStatus,
      paymentStatus: f.paymentStatus,
      insuranceOnly: f.insuranceOnly,
      search: f.search,
      newestFirst: f.newestFirst,
      limit: limit,
      offset: offset,
    );
  }
}

// ====================== Riverpod Provider ======================

class RepairsFilterNotifier extends StateNotifier<RepairsFilter> {
  RepairsFilterNotifier() : super(const RepairsFilter());

  void setDateRange({String? from, String? to}) => state =
      state.copyWith(from: _normalizeDate(from), to: _normalizeDate(to));

  void setRepairStatus(String? v) =>
      state = state.copyWith(repairStatus: _emptyToNull(v));

  void setPaymentStatus(String? v) =>
      state = state.copyWith(paymentStatus: _emptyToNull(v));

  void setInsuranceOnly(bool v) => state = state.copyWith(insuranceOnly: v);

  void setSearch(String? q) => state = state.copyWith(search: _emptyToNull(q));

  void setNewestFirst(bool v) => state = state.copyWith(newestFirst: v);

  void clear() => state = const RepairsFilter();
}

final repairsFilterProvider =
    StateNotifierProvider<RepairsFilterNotifier, RepairsFilter>(
  (ref) => RepairsFilterNotifier(),
);

// ====================== Helpers ======================

String? _normalizeDate(String? s) {
  if (s == null) return null;
  final t = s.trim();
  if (t.isEmpty) return null;
  try {
    final dt = DateTime.parse(t);
    return _fmt(dt);
  } catch (_) {
    return null;
  }
}

String? _emptyToNull(String? v) {
  if (v == null) return null;
  final s = v.trim();
  return s.isEmpty ? null : s;
}

DateTime _weekStart(DateTime d) {
  final wd = d.weekday;
  final delta = wd - DateTime.monday;
  return DateUtils.dateOnly(d.subtract(Duration(days: delta)));
}

String _fmt(DateTime d) {
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year}-$mm-$dd';
}
