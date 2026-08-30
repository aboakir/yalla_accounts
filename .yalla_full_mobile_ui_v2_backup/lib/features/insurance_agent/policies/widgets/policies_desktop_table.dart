// 📁 lib/features/insurance_agent/policies/widgets/policies_desktop_table.dart
//
// ✅ Desktop table for policies
// ✅ NEW: shows Document Type + Car Price columns

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/utils/policy_filters.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class PoliciesDesktopTable extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final bool busy;
  final DateFormat dateFormat;

  final void Function(Map<String, dynamic> row) onOpenDetails;
  final void Function(Map<String, dynamic> row) onOpenEdit;
  final void Function(Map<String, dynamic> row) onOpenPayments;
  final void Function(Map<String, dynamic> row) onDelete;

  PoliciesDesktopTable({
    super.key,
    required this.items,
    required this.busy,
    required this.dateFormat,
    required this.onOpenDetails,
    required this.onOpenEdit,
    required this.onOpenPayments,
    required this.onDelete,
  });

  final NumberFormat _nfInt = NumberFormat.decimalPattern('en_US');

  String _resolveFirst(Map<String, dynamic> r, List<String> keys,
      {String fallback = '-'}) {
    for (final k in keys) {
      final v = r[k];
      if (v == null) continue;
      final t = v.toString().trim();
      if (t.isNotEmpty) return t;
    }
    return fallback;
  }

  String _formatDateOnly(dynamic raw) {
    final d = PolicyFilters.parsePolicyDate(raw);
    if (d == null) return '-';
    return dateFormat.format(d); // yyyy-MM-dd
  }

  String _formatPhone(dynamic raw) {
    if (raw == null) return '-';
    final s = raw.toString().trim();
    if (s.isEmpty) return '-';
    if (RegExp(r'^\d+$').hasMatch(s) && s.length == 9 && !s.startsWith('0')) {
      return '0$s';
    }
    return s;
  }

  bool _isVip(Map<String, dynamic> r) {
    final v = r['is_vip'] ?? r['vip'] ?? r['VIP'];
    if (v == null) return false;
    if (v is int) return v == 1;
    final s = v.toString().trim();
    return s == '1' || s.toLowerCase() == 'true' || s == 'نعم';
  }

  String _statusLabel(Map<String, dynamic> r) {
    try {
      final end = PolicyFilters.parsePolicyDate(r['end_date']);
      if (end == null) return '—';

      final now = DateTime.now();
      final diff =
          end.difference(DateTime(now.year, now.month, now.day)).inDays;

      if (diff < 0) return 'منتهية';
      if (diff <= 12) return 'تنتهي قريباً';
      if (diff <= 30) return 'تنتهي خلال 30 يوم';
      return 'سارية';
    } catch (_) {
      return '—';
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'منتهية':
        return Colors.red;
      case 'تنتهي قريباً':
        return Colors.orange;
      case 'تنتهي خلال 30 يوم':
        return Colors.deepOrange;
      case 'سارية':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _docTypeLabel(Map<String, dynamic> r) {
    final raw = _resolveFirst(
      r,
      [
        'document_type',
        'policy_document_type',
        'coverage_type',
        'policy_type',
        'insurance_type',
      ],
      fallback: '',
    ).trim();

    if (raw.isEmpty) return '-';

    final low = raw.toLowerCase();
    if (raw == 'طرف ثالث' ||
        low == 'third' ||
        low == 'tp' ||
        low == 'third_party') {
      return 'طرف ثالث';
    }
    if (raw == 'شامل' || low == 'comprehensive' || low == 'full') {
      return 'شامل';
    }
    return raw;
  }

  String _carPriceLabel(Map<String, dynamic> r) {
    final raw = _resolveFirst(
      r,
      [
        'car_price',
        'vehicle_price',
        'vehicle_value',
        'market_value',
        'carValue',
        'vehicleValue',
        'price',
      ],
      fallback: '',
    ).trim();

    if (raw.isEmpty) return '-';

    final cleaned = raw.replaceAll(',', '').trim();
    final n = double.tryParse(cleaned);
    if (n == null) return raw;

    if (n == n.roundToDouble()) {
      return _nfInt.format(n.round());
    }
    return n.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const Center(child: CircularProgressIndicator());
    }

    if (items.isEmpty) {
      return const Center(child: Text('لا يوجد بيانات'));
    }

    // ✅ ترتيب الأعمدة (يمين ← يسار) مثل واجهتك
    final columns = <String>[
      'رقم المركبة',
      'المؤمن له',
      'الهاتف',
      'الشركة',
      'نوع الوثيقة',
      'سعر المركبة',
      'بداية',
      'نهاية',
      'الحالة',
      'VIP',
      'إجراءات',
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E8EC)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: AdaptiveDataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF4F6F8)),
          dataRowMinHeight: 52,
          dataRowMaxHeight: 60,
          columns: columns
              .map(
                (t) => DataColumn(
                  label: Text(
                    t,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              )
              .toList(),
          rows: items.map((r) {
            final plate = _resolveFirst(
              r,
              [
                'vehicle_plate',
                'vehicle_number',
                'car_plate',
                'plate_no',
                'plate'
              ],
              fallback: '-',
            );

            final insured = _resolveFirst(
              r,
              [
                'insured_name',
                'policy_holder_name',
                'customer_name',
                'client_name',
                'name',
                'owner_name',
              ],
              fallback: '-',
            );

            final phone = _formatPhone(_resolveFirst(
              r,
              [
                'insured_phone',
                'policy_holder_phone',
                'phone',
                'phone1',
                'mobile',
                'client_phone',
                'customer_phone',
                'owner_phone',
                'insured_mobile',
                'holder_mobile',
              ],
              fallback: '',
            ));

            final company = _resolveFirst(
              r,
              ['company_name', 'insurance_company', 'company'],
              fallback: '-',
            );

            final docType = _docTypeLabel(r);
            final carPrice = _carPriceLabel(r);

            final start = _formatDateOnly(_resolveFirst(
              r,
              ['start_date', 'policy_start', 'start'],
              fallback: '',
            ));
            final end = _formatDateOnly(_resolveFirst(
              r,
              ['end_date', 'policy_end', 'end'],
              fallback: '',
            ));

            final status = _statusLabel(r);
            final vip = _isVip(r) ? 'نعم' : 'لا';

            return DataRow(
              cells: [
                DataCell(Text(plate, textAlign: TextAlign.right)),
                DataCell(Text(insured, textAlign: TextAlign.right)),
                DataCell(Text(phone, textAlign: TextAlign.right)),
                DataCell(Text(company, textAlign: TextAlign.right)),
                DataCell(Text(docType, textAlign: TextAlign.right)),
                DataCell(Text(carPrice, textAlign: TextAlign.right)),
                DataCell(Text(start, textAlign: TextAlign.right)),
                DataCell(Text(end, textAlign: TextAlign.right)),
                DataCell(
                  Text(
                    status,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: _statusColor(status),
                    ),
                  ),
                ),
                DataCell(Text(vip, textAlign: TextAlign.right)),
                DataCell(
                  AdaptiveRow(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'عرض',
                        onPressed: () => onOpenDetails(r),
                        icon: const Icon(Icons.remove_red_eye,
                            color: Colors.green),
                      ),
                      IconButton(
                        tooltip: 'تعديل',
                        onPressed: () => onOpenEdit(r),
                        icon: Icon(Icons.edit, color: AppColors.primary),
                      ),
                      IconButton(
                        tooltip: 'دفعات',
                        onPressed: () => onOpenPayments(r),
                        icon: const Icon(Icons.payments, color: Colors.orange),
                      ),
                      IconButton(
                        tooltip: 'حذف',
                        onPressed: () => onDelete(r),
                        icon: const Icon(Icons.delete, color: Colors.red),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
