// 📁 lib/features/cheques/widgets/cheque_filters.dart
//
// ChequeFilters — ودجت الفلاتر لشاشة الشيكات
// --------------------------------------------------------
// - بحث
// - فلترة حالة الشيك
// - فلترة نوع الشيك (وارد/صادر/قيد التحصيل)
// - تاريخ من/إلى
// - زر مسح الفلاتر
// --------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class ChequeFilters extends StatelessWidget {
  final TextEditingController searchCtrl;

  final ChequeType? selectedType;
  final ChequeStatus? selectedStatus;

  final DateTime? fromDate;
  final DateTime? toDate;

  // String? لأننا نمرر enum.name
  final void Function(String?) onTypeChanged;
  final void Function(String?) onStatusChanged;

  final VoidCallback onClearDates;
  final Future<void> Function() onPickFrom;
  final Future<void> Function() onPickTo;

  final VoidCallback onApplyFilters;

  const ChequeFilters({
    super.key,
    required this.searchCtrl,
    required this.selectedType,
    required this.selectedStatus,
    required this.fromDate,
    required this.toDate,
    required this.onTypeChanged,
    required this.onStatusChanged,
    required this.onClearDates,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onApplyFilters,
  });

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd');

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          // --------------------------------------------------------
          // 🔍 حقل البحث
          // --------------------------------------------------------
          TextField(
            inputFormatters: const [YallaDigitNormalizer()],
            controller: searchCtrl,
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              labelText: 'بحث (رقم الشيك / البنك / الساحب)',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        searchCtrl.clear();
                        onApplyFilters();
                      },
                    ),
            ),
            onChanged: (_) => onApplyFilters(),
            onSubmitted: (_) => onApplyFilters(),
          ),

          const SizedBox(height: 10),

          AdaptiveRow(
            children: [
              // --------------------------------------------------------
              // نوع الشيك
              // --------------------------------------------------------
              Expanded(
                child: DropdownButtonFormField<String?>(
                  value: selectedType?.name,
                  decoration: const InputDecoration(
                    labelText: 'نوع الشيك',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text('كل الأنواع'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'incoming',
                      child: Text('وارد'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'outgoing',
                      child: Text('صادر'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'collection',
                      child: Text('قيد التحصيل'),
                    ),
                  ],
                  onChanged: onTypeChanged,
                ),
              ),

              const SizedBox(width: 8),

              // --------------------------------------------------------
              // حالة الشيك
              // --------------------------------------------------------
              Expanded(
                child: DropdownButtonFormField<String?>(
                  value: selectedStatus?.name,
                  decoration: const InputDecoration(
                    labelText: 'الحالة',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text('كل الحالات'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'pending',
                      child: Text('قيد الانتظار'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'collected',
                      child: Text('مُحصَّل'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'returned',
                      child: Text('راجع'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'cancelled',
                      child: Text('ملغى'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'delivered',
                      child: Text('مسلم لطرف آخر'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'deposited',
                      child: Text('مودع'),
                    ),
                  ],
                  onChanged: onStatusChanged,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          AdaptiveRow(
            children: [
              // --------------------------------------------------------
              // من تاريخ
              // --------------------------------------------------------
              Expanded(
                child: InkWell(
                  onTap: onPickFrom,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'من تاريخ',
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: Icon(Icons.event),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        fromDate == null ? '—' : df.format(fromDate!),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // --------------------------------------------------------
              // إلى تاريخ
              // --------------------------------------------------------
              Expanded(
                child: InkWell(
                  onTap: onPickTo,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'إلى تاريخ',
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: Icon(Icons.event),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        toDate == null ? '—' : df.format(toDate!),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // --------------------------------------------------------
              // مسح التاريخ
              // --------------------------------------------------------
              IconButton(
                onPressed: onClearDates,
                icon: const Icon(Icons.close),
                tooltip: 'مسح التاريخ',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
