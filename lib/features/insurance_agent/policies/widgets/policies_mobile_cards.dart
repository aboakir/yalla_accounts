// 📁 lib/features/insurance_agent/policies/widgets/policies_mobile_cards.dart
//
// PoliciesMobileCards — list wrapper for Mobile/Tablet
// Uses PolicyMobileCard

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'policy_mobile_card.dart';

class PoliciesMobileCards extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final bool busy;
  final DateFormat dateFormat;

  final Future<void> Function(Map<String, dynamic> row) onOpenDetails;
  final Future<void> Function(Map<String, dynamic> row) onOpenEdit;
  final Future<void> Function(Map<String, dynamic> row) onOpenPayments;
  final Future<void> Function(Map<String, dynamic> row) onDelete;

  const PoliciesMobileCards({
    super.key,
    required this.items,
    required this.busy,
    required this.dateFormat,
    required this.onOpenDetails,
    required this.onOpenEdit,
    required this.onOpenPayments,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (busy) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) {
      return const Center(child: Text('لا يوجد بوالص لهذا الشهر'));
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final r = items[i];

        return PolicyMobileCard(
          row: r,
          dateFormat: dateFormat,
          onDetails: () => onOpenDetails(r),
          onEdit: () => onOpenEdit(r),
          onPayments: () => onOpenPayments(r),
          onDelete: () => onDelete(r),
        );
      },
    );
  }
}
