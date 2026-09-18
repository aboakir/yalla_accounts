// -----------------------------------------------------------------------------
// 📁 lib/features/cheques/screens/cheques_list_screen.dart
//
// ChequesListScreen — PRO MAX v4 (بدون تغيير على ChequeProvider القديم)
// -----------------------------------------------------------------------------
// • يعتمد على chequeProvider + chequeFilterProvider + chequeFilterSyncProvider
// • فلترة أساسية من الـ Provider: بحث / نوع / حالة / تاريخ إصدار / استحقاق
// • فلترة متقدمة محلية: بنك / فرع / عملة / مبلغ من/إلى
// • أزرار فلترة ذكية: 3 أيام / متأخرة / اليوم / الأسبوع
// • عرض days-to-due + Banner ملون في الكروت
// • شريط تنبيهات أعلى الشاشة: متأخرة / اليوم / خلال 3 أيام (عدد + مجموع)
// • تلوين الحالات والأنواع
// • ربط المورد/العميل + زر فتح الدفعة (linkedPaymentId) في الكروت
// • DataTable للديسكتوب / Cards للموبايل
// • تصدير Excel للبيانات بعد الفلترة (الأساسية + المحلية)
// -----------------------------------------------------------------------------

import 'dart:io';
import 'package:yalla_accounts/core/pdf/yalla_pdf_service.dart';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

import '../models/cheque.dart';
import '../providers/cheque_provider.dart';
import 'cheque_details_screen.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class ChequesListScreen extends ConsumerStatefulWidget {
  const ChequesListScreen({super.key});

  @override
  ConsumerState<ChequesListScreen> createState() => _ChequesListScreenState();
}

class _ChequesListScreenState extends ConsumerState<ChequesListScreen> {
  final df = DateFormat('yyyy-MM-dd');

  // فلترة محلية إضافية (لا علاقة لها بـ ChequeFilter في الـ Provider)
  String? _bankFilter;
  String? _branchFilter;
  String? _currencyFilter;
  double? _amountMin;
  double? _amountMax;

  @override
  Widget build(BuildContext context) {
    // الفلتر الحالي من الـ Provider (بحث، نوع، حالة، تواريخ فقط)
    final filter = ref.watch(chequeFilterProvider);

    // تفعيل الـ Sync — أي تغيير على الفلتر يحدث Reload من الـ Service
    ref.watch(chequeFilterSyncProvider);

    // قائمة الشيكات المفلترة من الـ Service (حسب ChequeFilter القديم)
    final baseList = ref.watch(chequeProvider);

    // تطبيق الفلاتر المحلية الإضافية
    final list = _applyLocalFilters(baseList);

    final isDesktop = Responsive.isDesktop(context);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: const YallaAppBar(
        workshopName: "Yallah Accounts",
        showThemeToggle: false,
        showSearch: false,
      ),
      drawer: isDesktop ? null : const YallaSidebar(),
      body: AdaptiveRow(
        children: [
          if (isDesktop) const YallaSidebar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: NestedScrollView(
                headerSliverBuilder: (_, __) => [
                  SliverToBoxAdapter(
                      child: Column(children: [
                    _buildHeader(list),
                    const SizedBox(height: 16),
                    _buildDueSummaryBar(list),
                    const SizedBox(height: 20),
                    _buildFilterCard(filter),
                    const SizedBox(height: 20),
                    _quickFilters(filter),
                    const SizedBox(height: 20),
                  ]))
                ],
                body: _buildList(list),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: null,
    );
  }

  // ---------------------------------------------------------------------------
  // تطبيق الفلاتر المحلية (بنك / فرع / عملة / مبلغ من-إلى)
  // ---------------------------------------------------------------------------
  List<Cheque> _applyLocalFilters(List<Cheque> source) {
    return source.where((c) {
      // بنك
      if (_bankFilter != null && _bankFilter!.trim().isNotEmpty) {
        final v = _bankFilter!.toLowerCase();
        if (!c.bankName.toLowerCase().contains(v)) return false;
      }

      // فرع
      if (_branchFilter != null && _branchFilter!.trim().isNotEmpty) {
        final v = _branchFilter!.toLowerCase();
        if (!c.bankBranch.toLowerCase().contains(v)) return false;
      }

      // عملة
      if (_currencyFilter != null && _currencyFilter!.trim().isNotEmpty) {
        final v = _currencyFilter!.toLowerCase();
        if (!c.currency.toLowerCase().contains(v)) return false;
      }

      // مبلغ من
      if (_amountMin != null && c.amount < _amountMin!) return false;

      // مبلغ إلى
      if (_amountMax != null && c.amount > _amountMax!) return false;

      return true;
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // HEADER
  // ---------------------------------------------------------------------------
  Widget _buildHeader(List<Cheque> list) {
    return AdaptiveRow(
      children: [
        ElevatedButton.icon(
          icon: const Icon(Icons.download),
          label: const Text("تصدير Excel"),
          onPressed: list.isEmpty ? null : () => _exportExcel(list),
        ),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text("تصدير PDF"),
          onPressed: list.isEmpty ? null : () => _exportPdf(list),
        ),
        const Spacer(),
        const Text(
          "قوائم الشيكات",
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // SUMMARY BAR — تنبيهات الشيكات (متأخرة / اليوم / خلال 3 أيام)
  // ---------------------------------------------------------------------------
  Widget _buildDueSummaryBar(List<Cheque> list) {
    if (list.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text(
          "لا توجد شيكات في النتائج الحالية",
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 13,
            color: Colors.black54,
          ),
        ),
      );
    }

    int overdueCount = 0;
    double overdueSum = 0;

    int todayCount = 0;
    double todaySum = 0;

    int soonCount = 0; // 1–3 أيام
    double soonSum = 0;

    for (final c in list) {
      final days = _daysToDue(c.dueDate);
      if (days < 0) {
        overdueCount++;
        overdueSum += c.amount;
      } else if (days == 0) {
        todayCount++;
        todaySum += c.amount;
      } else if (days > 0 && days <= 3) {
        soonCount++;
        soonSum += c.amount;
      }
    }

    final hasAnyAlert = overdueCount > 0 || todayCount > 0 || soonCount > 0;

    if (!hasAnyAlert) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text(
          "لا توجد شيكات متأخرة أو مستحقة خلال 3 أيام.",
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 13,
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    String formatAmount(double v) => NumberFormat('#,##0.00', 'en').format(v);

    List<Widget> chips = [];

    if (overdueCount > 0) {
      chips.add(_summaryChip(
        label: "متأخرة: $overdueCount شيك — ${formatAmount(overdueSum)}",
        color: Colors.red,
      ));
    }

    if (todayCount > 0) {
      chips.add(_summaryChip(
        label: "مستحقة اليوم: $todayCount — ${formatAmount(todaySum)}",
        color: Colors.orange.shade700,
      ));
    }

    if (soonCount > 0) {
      chips.add(_summaryChip(
        label: "خلال 3 أيام: $soonCount شيك — ${formatAmount(soonSum)}",
        color: Colors.orange,
      ));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: chips,
      ),
    );
  }

  Widget _summaryChip({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: AdaptiveRow(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // FILTER CARD — يستخدم فقط حقول ChequeFilter القديمة + فلاتر محلية جديدة
  // ---------------------------------------------------------------------------
  Widget _buildFilterCard(ChequeFilter filter) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Wrap(
          spacing: 16,
          runSpacing: 16,
          alignment: WrapAlignment.end,
          children: [
            _searchField(filter),
            _typeDropdown(filter),
            _statusDropdown(filter),
            _bankField(),
            _currencyField(),
            _branchField(),
            _currencyField(),
            _amountMinField(),
            _amountMaxField(),
            _datePicker(
              "إصدار من",
              filter.issueFrom,
              (v) => _updateFilter(filter.copyWith(issueFrom: v)),
            ),
            _datePicker(
              "إصدار إلى",
              filter.issueTo,
              (v) => _updateFilter(filter.copyWith(issueTo: v)),
            ),
            _datePicker(
              "استحقاق من",
              filter.dueFrom,
              (v) => _updateFilter(filter.copyWith(dueFrom: v)),
            ),
            _datePicker(
              "استحقاق إلى",
              filter.dueTo,
              (v) => _updateFilter(filter.copyWith(dueTo: v)),
            ),
          ],
        ),
      ),
    );
  }

  void _updateFilter(ChequeFilter f) {
    ref.read(chequeFilterProvider.notifier).state = f;
  }

  // ---------------------------------------------------------------------------
  // Quick Filters — Buttons (تتحكم فقط بتواريخ الاستحقاق من ChequeFilter)
  // ---------------------------------------------------------------------------
  Widget _quickFilters(ChequeFilter filter) {
    return AdaptiveRow(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _quickBtn("3 أيام", Colors.orange, () {
          final now = DateTime.now();
          _updateFilter(
            filter.copyWith(
              dueFrom: DateTime(now.year, now.month, now.day),
              dueTo: DateTime(now.year, now.month, now.day)
                  .add(const Duration(days: 3)),
            ),
          );
        }),
        const SizedBox(width: 8),
        _quickBtn("متأخرة", Colors.red, () {
          final now = DateTime.now();
          _updateFilter(
            filter.copyWith(
              dueFrom: null,
              dueTo: DateTime(now.year, now.month, now.day)
                  .subtract(const Duration(days: 1)),
            ),
          );
        }),
        const SizedBox(width: 8),
        _quickBtn("اليوم", AppColors.primary, () {
          final now = DateTime.now();
          final d = DateTime(now.year, now.month, now.day);
          _updateFilter(
            filter.copyWith(
              dueFrom: d,
              dueTo: d,
            ),
          );
        }),
        const SizedBox(width: 8),
        _quickBtn("الأسبوع", Colors.blueGrey, () {
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
          final endOfWeek = startOfWeek.add(const Duration(days: 6));
          _updateFilter(
            filter.copyWith(
              dueFrom: startOfWeek,
              dueTo: endOfWeek,
            ),
          );
        }),
      ],
    );
  }

  Widget _quickBtn(String label, Color color, VoidCallback onTap) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
      onPressed: onTap,
      child: Text(label),
    );
  }

  // ---------------------------------------------------------------------------
  // FILTER INPUTS (جزء منها يغير ChequeFilter، والباقي محلي فقط)
  // ---------------------------------------------------------------------------
  Widget _searchField(ChequeFilter f) {
    return SizedBox(
      width: 220,
      child: TextField(
        inputFormatters: const [YallaDigitNormalizer()],
        decoration: const InputDecoration(
          labelText: "بحث...",
          prefixIcon: Icon(Icons.search),
        ),
        textAlign: TextAlign.right,
        onChanged: (v) =>
            _updateFilter(f.copyWith(search: v.trim().isEmpty ? null : v)),
      ),
    );
  }

  // فلاتر محلية: بنك / فرع / عملة / مبلغ من / مبلغ إلى
  Widget _bankField() {
    return SizedBox(
      width: 180,
      child: TextField(
        inputFormatters: const [YallaDigitNormalizer()],
        decoration: const InputDecoration(labelText: "البنك"),
        textAlign: TextAlign.right,
        onChanged: (v) {
          setState(() {
            _bankFilter = v.trim().isEmpty ? null : v.trim();
          });
        },
      ),
    );
  }

  Widget _branchField() {
    return SizedBox(
      width: 180,
      child: TextField(
        inputFormatters: const [YallaDigitNormalizer()],
        decoration: const InputDecoration(labelText: "الفرع"),
        textAlign: TextAlign.right,
        onChanged: (v) {
          setState(() {
            _branchFilter = v.trim().isEmpty ? null : v.trim();
          });
        },
      ),
    );
  }

  Widget _currencyField() {
    return SizedBox(
      width: 180,
      child: TextField(
        inputFormatters: const [YallaDigitNormalizer()],
        decoration: const InputDecoration(labelText: "العملة"),
        textAlign: TextAlign.right,
        onChanged: (v) {
          setState(() {
            _currencyFilter = v.trim().isEmpty ? null : v.trim();
          });
        },
      ),
    );
  }

  Widget _amountMinField() {
    return SizedBox(
      width: 160,
      child: TextField(
        inputFormatters: const [YallaDigitNormalizer()],
        decoration: const InputDecoration(labelText: "أقل مبلغ"),
        keyboardType: TextInputType.number,
        textAlign: TextAlign.right,
        onChanged: (v) {
          setState(() {
            _amountMin = double.tryParse(v.trim());
          });
        },
      ),
    );
  }

  Widget _amountMaxField() {
    return SizedBox(
      width: 160,
      child: TextField(
        inputFormatters: const [YallaDigitNormalizer()],
        decoration: const InputDecoration(labelText: "أعلى مبلغ"),
        keyboardType: TextInputType.number,
        textAlign: TextAlign.right,
        onChanged: (v) {
          setState(() {
            _amountMax = double.tryParse(v.trim());
          });
        },
      ),
    );
  }

  Widget _typeDropdown(ChequeFilter f) {
    return SizedBox(
      width: 180,
      child: DropdownButtonFormField<ChequeType?>(
        isExpanded: true,
        value: f.type,
        decoration: const InputDecoration(labelText: "نوع الشيك"),
        items: [
          const DropdownMenuItem(value: null, child: Text("الكل")),
          ...ChequeType.values.map(
            (e) => DropdownMenuItem(value: e, child: Text(_typeLabel(e))),
          )
        ],
        onChanged: (v) => _updateFilter(f.copyWith(type: v)),
      ),
    );
  }

  Widget _statusDropdown(ChequeFilter f) {
    return SizedBox(
      width: 180,
      child: DropdownButtonFormField<ChequeStatus?>(
        isExpanded: true,
        value: f.status,
        decoration: const InputDecoration(labelText: "الحالة"),
        items: [
          const DropdownMenuItem(value: null, child: Text("الكل")),
          ...ChequeStatus.values.map(
            (e) => DropdownMenuItem(value: e, child: Text(_statusLabel(e))),
          )
        ],
        onChanged: (v) => _updateFilter(f.copyWith(status: v)),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DATE PICKER
  // ---------------------------------------------------------------------------
  Widget _datePicker(
    String label,
    DateTime? value,
    Function(DateTime?) onChange,
  ) {
    return SizedBox(
      width: 180,
      child: GestureDetector(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
          );
          if (picked != null) onChange(picked);
        },
        child: InputDecorator(
          decoration: InputDecoration(labelText: label),
          child: Text(
            value == null ? "غير محدد" : df.format(value),
            textAlign: TextAlign.right,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // LIST VIEW (Responsive)
  // ---------------------------------------------------------------------------
  Widget _buildList(List<Cheque> list) {
    if (list.isEmpty) {
      return const Center(
        child: Text(
          "لا يوجد شيكات مطابقة",
          style: TextStyle(fontSize: 16),
        ),
      );
    }

    return Responsive.isDesktop(context)
        ? _buildTable(list)
        : _buildCards(list);
  }

  // ---------------------------------------------------------------------------
  // TABLE — DESKTOP VIEW
  // ---------------------------------------------------------------------------
  Widget _buildTable(List<Cheque> list) {
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: AdaptiveDataTable(
            headingRowColor: MaterialStateColor.resolveWith(
              (_) => AppColors.primary,
            ),
            headingTextStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
            columns: const [
              DataColumn(label: Text("رقم الشيك")),
              DataColumn(label: Text("القيمة")),
              DataColumn(label: Text("النوع")),
              DataColumn(label: Text("الحالة")),
              DataColumn(label: Text("البنك")),
              DataColumn(label: Text("الفرع")),
              DataColumn(label: Text("المحرر")),
              DataColumn(label: Text("إصدار")),
              DataColumn(label: Text("استحقاق")),
              DataColumn(label: Text("باقي")),
              DataColumn(label: Text("إجراءات")),
            ],
            rows: list.map((c) {
              final days = _daysToDue(c.dueDate);
              final dueText = _dueBannerText(days);
              final dueColor = _dueBannerColor(days);

              return DataRow(
                cells: [
                  DataCell(Text(c.chequeNo)),
                  DataCell(Text("${c.amount} ${c.currency}")),
                  DataCell(_coloredType(c.chequeType)),
                  DataCell(_coloredStatus(c.status)),
                  DataCell(Text(c.bankName)),
                  DataCell(Text(c.bankBranch)),
                  DataCell(Text(c.drawerName)), // ★★ المحرّر هنا ★★
                  DataCell(Text(df.format(c.issueDate))),
                  DataCell(Text(df.format(c.dueDate))),
                  DataCell(
                    Text(
                      dueText,
                      style: TextStyle(
                        color: dueColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  DataCell(
                    AdaptiveRow(
                      children: [
                        IconButton(
                          tooltip: "تفاصيل الشيك",
                          icon: const Icon(Icons.visibility),
                          onPressed: () => _openDetails(c),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _openEdit(c),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: null, // معطّل
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CARDS — MOBILE VIEW
  // ---------------------------------------------------------------------------
  Widget _buildCards(List<Cheque> list) {
    return Scrollbar(
        thumbVisibility: true,
        child: ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) {
            final c = list[i];
            final days = _daysToDue(c.dueDate);
            final dueText = _dueBannerText(days);
            final dueColor = _dueBannerColor(days);

            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (dueText.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: dueColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          dueText,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: dueColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    Text(
                      "رقم الشيك: ${c.chequeNo}",
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "${_typeLabel(c.chequeType)} • ${_statusLabel(c.status)}\n"
                      "${c.amount} ${c.currency}\n"
                      "${c.bankName} - ${c.bankBranch}\n"
                      "الحالة الزمنية: $dueText\n"
                      "إصدار: ${df.format(c.issueDate)}\n"
                      "استحقاق: ${df.format(c.dueDate)}\n"
                      "باقي: $dueText",
                      textAlign: TextAlign.right,
                    ),
                    const SizedBox(height: 10),
                    AdaptiveRow(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.visibility),
                          onPressed: () => _openDetails(c),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _openEdit(c),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: null, // معطّل
                        ),
                      ],
                    ),
                    _linksSection(c),
                  ],
                ),
              ),
            );
          },
        ));
  }

  // ---------------------------------------------------------------------------
  // LINKS: المورد – العميل – الدفعة (في الكروت فقط)
  // ---------------------------------------------------------------------------
  Widget _linksSection(Cheque c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (c.supplierPid != null)
          TextButton.icon(
            icon: const Icon(Icons.store, size: 18),
            label: const Text("فتح حساب المورد"),
            onPressed: () {
              Navigator.pushNamed(
                context,
                AppRoutes.supplierPayables,
                arguments: {
                  'supplierId': c.supplierPid,
                  'supplierName': (c.recipientName?.trim().isNotEmpty ?? false)
                      ? c.recipientName
                      : 'المورد',
                },
              );
            },
          ),
        if (c.clientId != null)
          TextButton.icon(
            icon: const Icon(Icons.person, size: 18),
            label: const Text("فتح حساب العميل"),
            onPressed: () {
              Navigator.pushNamed(
                context,
                AppRoutes.clientStatement,
                arguments: {
                  'clientId': c.clientId,
                  'clientName':
                      c.drawerName.trim().isNotEmpty ? c.drawerName : 'العميل',
                },
              );
            },
          ),
// روابط الدفعات (حسب الملفات المرتبطة)
        if (c.linkedRepairIds.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final rid in c.linkedRepairIds)
                TextButton.icon(
                  icon: const Icon(Icons.attach_money, size: 18),
                  label: Text("دفعة مرتبطة – ملف $rid"),
                  onPressed: () => AppRoutes.openRepairById(context, rid),
                ),
            ],
          ),

        if (c.glEntryId != null)
          TextButton.icon(
            icon: const Icon(Icons.receipt_long, size: 18),
            label: const Text("فتح قيد GL"),
            onPressed: () => AppRoutes.openGlEntry(context, c.glEntryId!),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // DAYS TO DUE + TEXT + COLOR
  // ---------------------------------------------------------------------------
  int _daysToDue(DateTime due) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return due.difference(today).inDays;
  }

  String _dueBannerText(int days) {
    if (days < 0) return "متأخر ${days.abs()} يوم";
    if (days == 0) return "مستحق اليوم";
    if (days == 1) return "يستحق غداً";
    if (days <= 3) return "يستحق خلال $days يوم";
    return "";
  }

  Color _dueBannerColor(int days) {
    if (days < 0) return Colors.red;
    if (days == 0) return Colors.orange.shade700;
    if (days <= 3) return Colors.orange;
    return Colors.transparent;
  }

  // ---------------------------------------------------------------------------
  // ENUM LABELS + تلوين
  // ---------------------------------------------------------------------------
  String _typeLabel(ChequeType t) {
    switch (t) {
      case ChequeType.incoming:
        return "وارد";
      case ChequeType.outgoing:
        return "صادر";
      case ChequeType.collection:
        return "قيد التحصيل";
    }
  }

  String _statusLabel(ChequeStatus s) {
    switch (s) {
      case ChequeStatus.pending:
        return "معلّق";
      case ChequeStatus.collected:
        return "مُحصّل";
      case ChequeStatus.returned:
        return "راجع";
      case ChequeStatus.cancelled:
        return "ملغى";
      case ChequeStatus.delivered:
        return "مُسلّم";
      case ChequeStatus.deposited:
        return "مودع";
    }
  }

  Widget _coloredType(ChequeType t) {
    Color color;
    switch (t) {
      case ChequeType.incoming:
        color = AppColors.primary;
        break;
      case ChequeType.outgoing:
        color = Colors.red;
        break;
      case ChequeType.collection:
        color = Colors.blue;
        break;
    }
    return Text(
      _typeLabel(t),
      style: TextStyle(fontWeight: FontWeight.bold, color: color),
    );
  }

  Widget _coloredStatus(ChequeStatus s) {
    Color color;
    switch (s) {
      case ChequeStatus.pending:
        color = Colors.orange;
        break;
      case ChequeStatus.collected:
        color = AppColors.primary;
        break;
      case ChequeStatus.returned:
        color = Colors.red;
        break;
      case ChequeStatus.cancelled:
        color = Colors.grey;
        break;
      case ChequeStatus.delivered:
        color = Colors.blueGrey;
        break;
      case ChequeStatus.deposited:
        color = Colors.blue;
        break;
    }
    return Text(
      _statusLabel(s),
      style: TextStyle(fontWeight: FontWeight.bold, color: color),
    );
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------
  void _openDetails(Cheque c) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChequeDetailsScreen(cheque: c),
      ),
    );
  }

  Future<void> _openEdit(Cheque c) async {
    await AppRoutes.pushNamedSafe(
      context,
      AppRoutes.chequesEdit,
      arguments: c,
    );
  }

  // ---------------------------------------------------------------------------
  // EXPORT EXCEL — يستخدم القائمة بعد الفلترة (Provider + محلي)
  // ---------------------------------------------------------------------------
  Future<void> _exportExcel(List<Cheque> data) async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Cheques'];

      sheet.appendRow([TextCellValue("عدد السجلات: ${data.length}")]);
      sheet.appendRow([
        TextCellValue("رقم الشيك"),
        TextCellValue("القيمة"),
        TextCellValue("النوع"),
        TextCellValue("الحالة"),
        TextCellValue("البنك"),
        TextCellValue("الإصدار"),
        TextCellValue("الاستحقاق"),
        TextCellValue("باقي"),
      ]);

      for (final c in data) {
        final days = _daysToDue(c.dueDate);
        sheet.appendRow([
          TextCellValue(c.chequeNo),
          TextCellValue("${c.amount} ${c.currency}"),
          TextCellValue(_typeLabel(c.chequeType)),
          TextCellValue(_statusLabel(c.status)),
          TextCellValue("${c.bankName} - ${c.bankBranch}"),
          TextCellValue(df.format(c.issueDate)),
          TextCellValue(df.format(c.dueDate)),
          TextCellValue(_dueBannerText(days)),
        ]);
      }

      final bytes = excel.encode();
      if (bytes == null) throw "Excel encoding failed";

      Directory baseDir;
      try {
        baseDir = await getDownloadsDirectory() ??
            await getApplicationDocumentsDirectory();
      } catch (_) {
        baseDir = await getApplicationDocumentsDirectory();
      }

      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filePath = p.join(baseDir.path, "yalla_cheques_$ts.xlsx");
      final file = File(filePath);
      await file.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);

      _snack("تم حفظ الملف:\n$filePath");
    } catch (e) {
      _snack("خطأ أثناء التصدير: $e");
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, textAlign: TextAlign.right),
      ),
    );
  }

// ---------------------------------------------------------------------------
// EXPORT PDF — يعتمد على YallaPdfService (مركزي + خطوط + RTL + تنسيق أرقام)
// ---------------------------------------------------------------------------
  Future<void> _exportPdf(List<Cheque> data) async {
    try {
      // 1) تجهيز عنوان التقرير
      const title = "قوائم الشيكات";

      // 2) تجهيز الأعمدة
      final headers = [
        "رقم الشيك",
        "القيمة",
        "النوع",
        "الحالة",
        "البنك",
        "الإصدار",
        "الاستحقاق",
        "المحرر",
      ];

      // 3) تجهيز البيانات (صفوف PDF)
      final rows = data.map((c) {
        return [
          c.chequeNo,
          "${NumberFormat('#,##0.00', 'en').format(c.amount)} ${c.currency}",
          _typeLabel(c.chequeType),
          _statusLabel(c.status),
          "${c.bankName} - ${c.bankBranch}",
          df.format(c.issueDate),
          df.format(c.dueDate),
          c.drawerName,
        ];
      }).toList();

      // 4) طلب PDF جاهز من الخدمة المركزية
      final pdfBytes = await YallaPdfService.generateTablePdf(
        title: title,
        headers: headers,
        rows: rows,
      );

      // 5) اختيار مجلد الحفظ
      Directory baseDir;
      try {
        baseDir = await getDownloadsDirectory() ??
            await getApplicationDocumentsDirectory();
      } catch (_) {
        baseDir = await getApplicationDocumentsDirectory();
      }

      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filePath = p.join(baseDir.path, "yalla_cheques_$ts.pdf");

      final file = File(filePath);
      await file.writeAsBytes(pdfBytes);

      _snack("تم حفظ ملف PDF:\n$filePath");
    } catch (e) {
      _snack("خطأ أثناء التصدير: $e");
    }
  }
}
