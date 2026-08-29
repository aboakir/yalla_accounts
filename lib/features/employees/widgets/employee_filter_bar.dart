import 'package:flutter/material.dart';

class EmployeeFilterBar extends StatelessWidget {
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onStatusChanged;
  final String selectedStatus;

  const EmployeeFilterBar({
    super.key,
    required this.onSearchChanged,
    required this.onStatusChanged,
    required this.selectedStatus,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            decoration: InputDecoration(
              labelText: 'بحث بالاسم أو المسمى',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: onSearchChanged,
            autocorrect: true,
            textInputAction: TextInputAction.search,
            keyboardType: TextInputType.text,
            autofillHints: const [AutofillHints.name],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: selectedStatus.isNotEmpty ? selectedStatus : 'الكل',
            decoration: InputDecoration(
              labelText: 'الحالة',
              prefixIcon: const Icon(Icons.filter_alt),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            items: const [
              DropdownMenuItem(value: 'الكل', child: Text('الكل')),
              DropdownMenuItem(value: 'نشط', child: Text('نشط')),
              DropdownMenuItem(value: 'مجمّد', child: Text('مجمّد')),
              DropdownMenuItem(value: 'موقوف', child: Text('موقوف')),
            ],
            onChanged: (val) {
              if (val != null) {
                onStatusChanged(val);
              }
            },
          ),
        ],
      ),
    );
  }
}
