// 📁 lib/features/employees/screens/salary_details_screen.dart
//
// SalaryDetailsScreen — عرض راتب موظف لشهر محدد (عرض فقط)
// - بدون أي نشر GL أو مزامنة جانبية.
// - يعتمد SalaryDatabaseService.getSalary(employeeId, month).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/employees/models/employee.dart';
import 'package:yalla_accounts/features/employees/models/salary.dart';
import 'package:yalla_accounts/features/employees/services/salary_database_service.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class SalaryDetailsScreen extends ConsumerStatefulWidget {
  final Employee employee;
  const SalaryDetailsScreen({super.key, required this.employee});

  @override
  ConsumerState<SalaryDetailsScreen> createState() =>
      _SalaryDetailsScreenState();
}

class _SalaryDetailsScreenState extends ConsumerState<SalaryDetailsScreen> {
  DateTime selectedMonth = DateTime.now();
  Salary? salary;
  bool isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSalary();
  }

  Future<void> _loadSalary() async {
    setState(() {
      isLoading = true;
      _errorMessage = null;
    });

    final monthKey = DateFormat('yyyy-MM').format(selectedMonth);

    try {
      salary = await SalaryDatabaseService.getSalary(
        employeeId: widget.employee.id,
        month: monthKey,
      );
    } catch (e) {
      _errorMessage = 'حدث خطأ أثناء تحميل البيانات: $e';
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedMonth,
      firstDate: DateTime(2022, 1, 1),
      lastDate: DateTime.now(),
      helpText: 'اختر شهر الراتب',
    );
    if (picked != null) {
      setState(() => selectedMonth = DateTime(picked.year, picked.month));
      await _loadSalary();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 900;

    final netSalary = salary?.total ?? 0.0;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('تفاصيل الراتب'),
        backgroundColor: AppColors.primary,
        actions: [
          IconButton(
              icon: const Icon(Icons.calendar_month), onPressed: _pickMonth),
          IconButton(
              icon: const Icon(Icons.print), onPressed: () {/* TODO: PDF */}),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(12),
        child: ElevatedButton.icon(
          onPressed: () {/* TODO: تعديل بيانات الموظف */},
          icon: const Icon(Icons.edit),
          label: const Text('تعديل بيانات الموظف'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Text(_errorMessage!,
                      style: const TextStyle(color: Colors.red)))
              : Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _buildHeader(widget.employee, netSalary),
                          const SizedBox(height: 20),
                          isWide
                              ? AdaptiveRow(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                        child: _buildLeft(widget.employee)),
                                    const SizedBox(width: 20),
                                    Expanded(
                                        child: _buildRight(salary, netSalary)),
                                  ],
                                )
                              : Column(
                                  children: [
                                    _buildLeft(widget.employee),
                                    const SizedBox(height: 20),
                                    _buildRight(salary, netSalary),
                                  ],
                                ),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _buildHeader(Employee employee, double netSalary) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: AdaptiveRow(
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: AppColors.primary.withOpacity(0.1),
              child: Text(
                employee.fullName.isNotEmpty ? employee.fullName[0] : '?',
                style:
                    const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(employee.fullName,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(employee.jobTitle,
                      style: const TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            ),
            Column(
              children: [
                Text('الراتب الصافي',
                    style: TextStyle(color: Colors.grey.shade600)),
                const SizedBox(height: 4),
                Text('${MoneyFormatter.format(netSalary)}',
                    style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 20)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeft(Employee employee) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: Colors.white,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('البيانات الشخصية'),
            _infoRow('الرقم الوظيفي', employee.employeeCode),
            _infoRow('رقم الهاتف', employee.phone),
            _infoRow('البريد الإلكتروني', employee.email),
            _infoRow(
                'العنوان', employee.address.isEmpty ? '—' : employee.address),
            const SizedBox(height: 12),
            _sectionTitle('الملاحظات'),
            Text(employee.notes.isEmpty ? 'لا توجد ملاحظات' : employee.notes,
                style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildRight(Salary? salary, double netSalary) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: Colors.white,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('بيانات الراتب'),
            _infoRow(
                'الشهر', DateFormat('MMMM yyyy', 'ar').format(selectedMonth)),
            _infoRow('الراتب الأساسي',
                salary == null ? '—' : '${MoneyFormatter.format(salary.base)}'),
            _infoRow(
                'السلفة',
                salary == null
                    ? '—'
                    : '${MoneyFormatter.format(salary.advance)}'),
            _infoRow('الراتب الصافي', '${MoneyFormatter.format(netSalary)}'),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _infoRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: AdaptiveRow(
        children: [
          const SizedBox(width: 6),
          Expanded(
              flex: 4,
              child: Text('$title:', style: const TextStyle(fontSize: 14))),
          Expanded(
              flex: 6,
              child: Text(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}
