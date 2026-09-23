// 📁 lib/features/repairs/screens/repair_reports_screen.dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:excel/excel.dart' as ex;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/release/release_scope_config.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/providers/repair_reports_provider.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class RepairReportsScreen extends ConsumerStatefulWidget {
  const RepairReportsScreen({super.key});

  @override
  ConsumerState<RepairReportsScreen> createState() =>
      _RepairReportsScreenState();
}

class _RepairReportsScreenState extends ConsumerState<RepairReportsScreen> {
  String filterType = 'الكل';
  String? selectedYear;
  String? selectedMonth;
  String? selectedPaymentStatus;
  String? selectedVehicleStatus;

  final List<String> filterOptions = [
    'الكل',
    'حسب السنة',
    'حسب الشهر',
    'حسب السنة والشهر'
  ];
  final List<String> years = List.generate(20, (i) => (2015 + i).toString());
  final List<String> months =
      List.generate(12, (i) => (i + 1).toString().padLeft(2, '0'));
  final List<String> paymentStatuses = [
    'الكل',
    'مسدد',
    'غير مسدد',
    'مسدد جزئيًا'
  ];
  final List<String> vehicleStatuses = [
    'الكل',
    'قيد الإصلاح',
    'تم التسليم',
    'جاهز للتسليم'
  ];

  Future<void> exportRepairsToExcel(List<Repair> repairs) async {
    final excel = ex.Excel.createExcel();
    final sheet = excel['تقرير'];
    sheet.appendRow([
      ex.TextCellValue('رقم المركبة'),
      ex.TextCellValue('نوع المركبة'),
      ex.TextCellValue('نوع الإصلاح'),
      ex.TextCellValue('قيمة الملف'),
      ex.TextCellValue('مدفوع'),
      ex.TextCellValue('متبقي'),
      ex.TextCellValue('تاريخ الاستلام'),
    ]);
    for (var r in repairs) {
      sheet.appendRow([
        ex.TextCellValue(r.vehicleNumber),
        ex.TextCellValue(r.vehicleType),
        ex.TextCellValue(r.repairType),
        ex.TextCellValue(r.fileValue.toStringAsFixed(0)),
        ex.TextCellValue(r.paidAmount.toStringAsFixed(0)),
        ex.TextCellValue((r.fileValue - r.paidAmount).toStringAsFixed(0)),
        ex.TextCellValue(DateFormat('yyyy-MM-dd').format(r.receivedDate)),
      ]);
    }
    final fileBytes = excel.encode();
    if (fileBytes != null) {
      await Printing.sharePdf(
        bytes: Uint8List.fromList(fileBytes),
        filename: 'تقرير_الإصلاح.xlsx',
      );
    }
  }

  Future<void> exportRepairsToPdf(List<Repair> repairs) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Text('📊 تقرير الإصلاح', style: const pw.TextStyle(fontSize: 18)),
          pw.SizedBox(height: 12),
          pw.Table.fromTextArray(
            headers: [
              'رقم المركبة',
              'نوع المركبة',
              'نوع الإصلاح',
              'قيمة الملف',
              'المدفوع',
              'المتبقي',
              'تاريخ الاستلام',
            ],
            data: repairs
                .map((r) => [
                      r.vehicleNumber,
                      r.vehicleType,
                      r.repairType,
                      r.fileValue.toStringAsFixed(0),
                      r.paidAmount.toStringAsFixed(0),
                      (r.fileValue - r.paidAmount).toStringAsFixed(0),
                      DateFormat('yyyy-MM-dd').format(r.receivedDate),
                    ])
                .toList(),
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    final reports = ref.watch(repairReportsProvider);
    if (reports.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (reports.hasError) {
      return Scaffold(
        body:
            Center(child: Text('تعذر تحميل تقرير الإصلاحات: ${reports.error}')),
      );
    }
    final repairs = reports.value ?? const <Repair>[];

    List<Repair> filtered = repairs.where((r) {
      final d = r.receivedDate;
      if (filterType == 'حسب السنة' && selectedYear != null) {
        if (d.year.toString() != selectedYear) return false;
      }
      if (filterType == 'حسب الشهر' && selectedMonth != null) {
        if (d.month.toString().padLeft(2, '0') != selectedMonth) return false;
      }
      if (filterType == 'حسب السنة والشهر' &&
          selectedYear != null &&
          selectedMonth != null) {
        if (d.year.toString() != selectedYear ||
            d.month.toString().padLeft(2, '0') != selectedMonth) {
          return false;
        }
      }
      if (selectedPaymentStatus != null && selectedPaymentStatus != 'الكل') {
        if (r.paymentStatus != selectedPaymentStatus) return false;
      }
      if (selectedVehicleStatus != null && selectedVehicleStatus != 'الكل') {
        if (r.vehicleStatus != selectedVehicleStatus) return false;
      }
      return true;
    }).toList();

    final totalPaid = filtered.fold(0.0, (sum, r) => sum + r.paidAmount);
    final totalValue = filtered.fold(0.0, (sum, r) => sum + r.fileValue);
    final remaining = totalValue - totalPaid;
    final unpaidCount = filtered.where((r) => r.paymentStatus != 'مسدد').length;

    final revenuePerMonth = <String, double>{};
    for (var r in filtered) {
      final key = DateFormat('yyyy-MM').format(r.receivedDate);
      revenuePerMonth[key] = (revenuePerMonth[key] ?? 0) + r.paidAmount;
    }
    final chartItems = revenuePerMonth.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Scaffold(
      drawer: isDesktop
          ? null
          : Drawer(
              width: MediaQuery.sizeOf(context).width,
              shape: const RoundedRectangleBorder(),
              child: const SafeArea(
                child: YallaSidebar(currentRoute: '/repairs/repair-reports'),
              ),
            ),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text('📊 تقارير الإصلاح',
            style: TextStyle(color: Colors.white)),
        centerTitle: true,
        actions: [
          if (ReleaseScopeConfig.repairReportExportsEnabled)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
              onPressed: () => exportRepairsToPdf(filtered),
            ),
          if (ReleaseScopeConfig.repairReportExportsEnabled)
            IconButton(
              icon: const Icon(Icons.table_chart, color: Colors.white),
              onPressed: () => exportRepairsToExcel(filtered),
            ),
          if (unpaidCount > 0)
            IconButton(
              icon: const Icon(Icons.warning_amber, color: Colors.yellow),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => AdaptiveAlertDialog(
                    title: const Text('تنبيه الملفات غير المسددة'),
                    content: Text(
                        'يوجد $unpaidCount ملف غير مسدد في النتائج الحالية.'),
                    actions: [
                      TextButton(
                        child: const Text('تم'),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return AdaptiveRow(
            children: [
              if (isDesktop)
                const SizedBox(
                  width: 260,
                  child: YallaSidebar(currentRoute: '/repairs/repair-reports'),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ListView(
                    children: [
                      if (constraints.maxWidth < 600)
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _phoneDropdown(
                              value: filterType,
                              label: 'الفترة',
                              items: filterOptions,
                              onChanged: (val) =>
                                  setState(() => filterType = val!),
                            ),
                            if (filterType.contains('السنة'))
                              _phoneDropdown(
                                value: selectedYear,
                                label: 'السنة',
                                items: years,
                                onChanged: (val) =>
                                    setState(() => selectedYear = val),
                              ),
                            if (filterType.contains('الشهر'))
                              _phoneDropdown(
                                value: selectedMonth,
                                label: 'الشهر',
                                items: months,
                                onChanged: (val) =>
                                    setState(() => selectedMonth = val),
                              ),
                            _phoneDropdown(
                              value: selectedPaymentStatus ?? 'الكل',
                              label: 'الدفع',
                              items: paymentStatuses,
                              onChanged: (val) =>
                                  setState(() => selectedPaymentStatus = val),
                            ),
                            _phoneDropdown(
                              value: selectedVehicleStatus ?? 'الكل',
                              label: 'حالة المركبة',
                              items: vehicleStatuses,
                              onChanged: (val) =>
                                  setState(() => selectedVehicleStatus = val),
                            ),
                          ],
                        )
                      else
                        AdaptiveRow(
                          children: [
                            DropdownButton<String>(
                              value: filterType,
                              items: filterOptions
                                  .map((e) => DropdownMenuItem(
                                      value: e, child: Text(e)))
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => filterType = val!),
                            ),
                            const SizedBox(width: 12),
                            if (filterType.contains('السنة'))
                              DropdownButton<String>(
                                value: selectedYear,
                                hint: const Text('اختر السنة'),
                                items: years
                                    .map((y) => DropdownMenuItem(
                                        value: y, child: Text(y)))
                                    .toList(),
                                onChanged: (val) =>
                                    setState(() => selectedYear = val),
                              ),
                            const SizedBox(width: 12),
                            if (filterType.contains('الشهر'))
                              DropdownButton<String>(
                                value: selectedMonth,
                                hint: const Text('اختر الشهر'),
                                items: months
                                    .map((m) => DropdownMenuItem(
                                        value: m, child: Text(m)))
                                    .toList(),
                                onChanged: (val) =>
                                    setState(() => selectedMonth = val),
                              ),
                            const SizedBox(width: 12),
                            DropdownButton<String>(
                              value: selectedPaymentStatus ?? 'الكل',
                              items: paymentStatuses
                                  .map((s) => DropdownMenuItem(
                                      value: s, child: Text(s)))
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => selectedPaymentStatus = val),
                            ),
                            const SizedBox(width: 12),
                            DropdownButton<String>(
                              value: selectedVehicleStatus ?? 'الكل',
                              items: vehicleStatuses
                                  .map((s) => DropdownMenuItem(
                                      value: s, child: Text(s)))
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => selectedVehicleStatus = val),
                            ),
                          ],
                        ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _summaryBox('عدد الملفات', '${filtered.length}',
                              Icons.folder),
                          _summaryBox(
                              'قيمة الملفات',
                              MoneyFormatter.format(totalValue),
                              Icons.monetization_on),
                          _summaryBox('مدفوع', MoneyFormatter.format(totalPaid),
                              Icons.paid),
                          _summaryBox('متبقي', MoneyFormatter.format(remaining),
                              Icons.hourglass_bottom),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: constraints.maxWidth < 600 ? 160 : 200,
                        child: PieChart(
                          PieChartData(sections: [
                            PieChartSectionData(
                                value: totalPaid,
                                title: 'مدفوع',
                                color: AppColors.primary),
                            PieChartSectionData(
                                value: remaining,
                                title: 'متبقي',
                                color: Colors.red),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: constraints.maxWidth < 600 ? 190 : 220,
                        child: _revenueBarChart(
                          chartItems,
                          phone: constraints.maxWidth < 600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _revenueBarChart(
    List<MapEntry<String, double>> chartItems, {
    required bool phone,
  }) {
    if (chartItems.isEmpty) {
      return const Center(
        child: Text('لا توجد بيانات شهرية ضمن الفلاتر الحالية'),
      );
    }

    final maxRevenue = chartItems.fold<double>(
      0,
      (current, item) => item.value > current ? item.value : current,
    );
    final chartMaxY = maxRevenue <= 0 ? 1.0 : maxRevenue * 1.12;
    final titleInterval = chartMaxY <= 2 ? 1.0 : chartMaxY / 2;

    return Directionality(
      textDirection: ui.TextDirection.ltr,
      child: ClipRect(
        child: BarChart(
          BarChartData(
            minY: 0,
            maxY: chartMaxY,
            alignment: BarChartAlignment.spaceAround,
            barGroups: chartItems.asMap().entries.map((e) {
              return BarChartGroupData(
                x: e.key,
                barRods: [
                  BarChartRodData(
                    toY: e.value.value,
                    width: phone ? 14 : 18,
                    color: AppColors.primary,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                ],
              );
            }).toList(),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 1,
                  reservedSize: 30,
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();
                    if (i < 0 || i >= chartItems.length) {
                      return const SizedBox.shrink();
                    }
                    return SideTitleWidget(
                      axisSide: meta.axisSide,
                      space: 6,
                      child: Text(
                        chartItems[i].key.substring(5),
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(fontSize: 11),
                      ),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: titleInterval,
                  reservedSize: phone ? 58 : 68,
                  getTitlesWidget: (value, meta) {
                    return SideTitleWidget(
                      axisSide: meta.axisSide,
                      space: 6,
                      child: SizedBox(
                        width: phone ? 50 : 60,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            _compactAxisValue(value),
                            maxLines: 1,
                            softWrap: false,
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            gridData: const FlGridData(
              show: true,
              drawVerticalLine: false,
            ),
          ),
        ),
      ),
    );
  }

  String _compactAxisValue(double value) {
    final absolute = value.abs();
    if (absolute >= 1000000) {
      final scaled = value / 1000000;
      return '${scaled.toStringAsFixed(scaled.abs() >= 10 ? 0 : 1)}M';
    }
    if (absolute >= 1000) {
      final scaled = value / 1000;
      return '${scaled.toStringAsFixed(scaled.abs() >= 10 ? 0 : 1)}K';
    }
    return value.toStringAsFixed(absolute >= 10 ? 0 : 1);
  }

  Widget _phoneDropdown({
    required String? value,
    required String label,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final width = (MediaQuery.sizeOf(context).width - 42) / 2;
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        items: items
            .map((item) => DropdownMenuItem(value: item, child: Text(item)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _summaryBox(String title, String value, IconData icon) {
    final phone = MediaQuery.sizeOf(context).width < 600;
    final width = phone ? (MediaQuery.sizeOf(context).width - 44) / 2 : 160.0;
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontSize: 13)),
          Text(value,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
