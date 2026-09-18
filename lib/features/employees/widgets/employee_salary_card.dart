import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/employees/models/employee.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class EmployeeSalaryCard extends ConsumerStatefulWidget {
  final Employee employee;
  const EmployeeSalaryCard({super.key, required this.employee});

  @override
  ConsumerState<EmployeeSalaryCard> createState() => _EmployeeSalaryCardState();
}

class _EmployeeSalaryCardState extends ConsumerState<EmployeeSalaryCard> {
  late TextEditingController advanceController;

  @override
  void initState() {
    super.initState();
    advanceController = TextEditingController(
      text: widget.employee.advances.toStringAsFixed(2),
    );
  }

  @override
  void didUpdateWidget(covariant EmployeeSalaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.employee.advances != widget.employee.advances) {
      advanceController.text = widget.employee.advances.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    advanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final netSalary = widget.employee.baseSalary +
        widget.employee.allowances -
        widget.employee.deductions -
        widget.employee.advances;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AdaptiveRow(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // معلومات الموظف
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.employee.fullName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                      'الراتب الأساسي: ${MoneyFormatter.format(widget.employee.baseSalary)}'),
                  Text(
                      'السلفة الحالية: ${MoneyFormatter.format(widget.employee.advances)}'),
                ],
              ),
            ),

            // إدخال سلفة جديدة
            Expanded(
              child: Column(
                children: [
                  const Text('السلف من سند الصرف فقط'),
                  const SizedBox(height: 4),
                  TextFormField(
                    inputFormatters: const [YallaDigitNormalizer()],
                    controller: advanceController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                      border: OutlineInputBorder(),
                    ),
                    readOnly: true,
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // الراتب الصافي
            Column(
              children: [
                const Text('الراتب الصافي'),
                const SizedBox(height: 6),
                Text(
                  MoneyFormatter.format(netSalary),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
