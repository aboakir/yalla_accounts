// 📁 lib/features/insurance_agent/calculator/widgets/category_selector.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import '../providers/insurance_calculator_provider.dart';
import '../models/insurance_category.dart';

class CategorySelector extends StatelessWidget {
  const CategorySelector({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InsuranceCalculatorProvider>();

    final selected = provider.category; // ممكن تكون null حسب مزودك

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'نوع المركبة / الفئة',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<InsuranceCategory>(
              value: selected,
              decoration: const InputDecoration(
                labelText: 'اختر الفئة',
              ),
              items: InsuranceCategories.all
                  .map(
                    (c) => DropdownMenuItem(
                      value: c,
                      child: Text(c.title),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) provider.setCategory(value);
              },
            ),
            const SizedBox(height: 8),
            Text(
              selected?.description ?? 'اختر فئة لعرض شرح مختصر هنا.',
              style: const TextStyle(
                color: AppColors.secondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
