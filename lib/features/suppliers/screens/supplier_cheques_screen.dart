// -----------------------------------------------------------------------------
// 📁 lib/features/suppliers/screens/supplier_cheques_screen.dart
//
// SupplierChequesScreen — شاشة شيكات المورد (PRO MAX v3 — FINAL CLEAN VERSION)
// -----------------------------------------------------------------------------
// • فلترة كاملة: بحث – نوع – حالة – بنك – فرع – عملة – مبلغ من/إلى – تواريخ.
// • شريط تنبيهات مثل شاشة الشيكات الرئيسية (متأخرة / اليوم / خلال 3 أيام).
// • Cards للموبايل / Table للديسكتوب.
// • فتح تفاصيل + تعديل + فتح قيد GL.
// • تصدير PDF + Excel للفلاتر الحالية فقط.
// • بدون أي تكرار — كود نظيف ومنظم بالكامل.
// -----------------------------------------------------------------------------
// • TextAlign.right فقط — بدون RTL إجباري.
// -----------------------------------------------------------------------------

import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';

import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/providers/cheque_provider.dart';
import 'package:yalla_accounts/features/cheques/screens/cheque_add_screen.dart';
import 'package:yalla_accounts/features/cheques/screens/cheque_details_screen.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class SupplierChequesScreen extends ConsumerStatefulWidget {
  final String supplierPid;
  final String supplierName;

  const SupplierChequesScreen({
    super.key,
    required this.supplierPid,
    required this.supplierName,
  });

  @override
  ConsumerState<SupplierChequesScreen> createState() =>
      _SupplierChequesScreenState();
}

class _SupplierChequesScreenState extends ConsumerState<SupplierChequesScreen> {
  final df = DateFormat('yyyy-MM-dd');

  // ----------------------------- فلاتر -----------------------------
  String? search;
  ChequeType? type;
  ChequeStatus? status;
  String? bank;
  String? branch;
  String? currency;
  double? minAmount;
  double? maxAmount;
  DateTime? issueFrom;
  DateTime? issueTo;
  DateTime? dueFrom;
  DateTime? dueTo;

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    final base = ref
        .watch(chequeProvider)
        .where((c) => c.supplierPid == widget.supplierPid)
        .toList();

    final filtered = _applyFilters(base);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: YallaAppBar(
        workshopName: "شيكات المورد",
        showSearch: false,
        showThemeToggle: false,
      ),
      drawer: isDesktop ? null : const YallaSidebar(),
      body: AdaptiveRow(
        children: [
          if (isDesktop) const YallaSidebar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _header(filtered),
                  const SizedBox(height: 12),
                  _summaryBar(filtered),
                  const SizedBox(height: 12),
                  _filtersCard(),
                  const SizedBox(height: 20),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text("لا توجد نتائج"))
                        : (isDesktop
                            ? _buildTable(filtered)
                            : _buildCards(filtered)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HEADER
  // ---------------------------------------------------------------------------
  Widget _header(List<Cheque> filtered) {
    return AdaptiveRow(
      children: [
        ElevatedButton.icon(
          icon: const Icon(Icons.table_view),
          label: const Text("Excel"),
          onPressed: () => _exportExcel(filtered),
        ),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text("PDF"),
          onPressed: () => _exportPdf(filtered),
        ),
        const Spacer(),
        Text(
          "شيكات المورد: ${widget.supplierName}",
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // SUMMARY BAR — شريط التنبيهات + التجميع
  // ---------------------------------------------------------------------------
  Widget _summaryBar(List<Cheque> list) {
    if (list.isEmpty) {
      return _chip("لا توجد نتائج", Colors.grey);
    }

    double total = 0;
    double overdue = 0;
    double todaySum = 0;
    double soonSum = 0;

    int overdueCount = 0;
    int todayCount = 0;
    int soonCount = 0;

    for (final c in list) {
      total += c.amount;
      final d = _daysToDue(c.dueDate);
      if (d < 0) {
        overdue += c.amount;
        overdueCount++;
      } else if (d == 0) {
        todaySum += c.amount;
        todayCount++;
      } else if (d > 0 && d <= 3) {
        soonSum += c.amount;
        soonCount++;
      }
    }

    String f(double v) => NumberFormat('#,##0.00', 'en').format(v);

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.end,
      children: [
        _chip("المجموع: ${f(total)}", Colors.blueGrey),
        if (overdueCount > 0)
          _chip("متأخرة: $overdueCount — ${f(overdue)}", Colors.red),
        if (todayCount > 0)
          _chip("اليوم: $todayCount — ${f(todaySum)}", Colors.orange),
        if (soonCount > 0)
          _chip("خلال 3 أيام: $soonCount — ${f(soonSum)}", Colors.green),
      ],
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(.09),
        borderRadius: BorderRadius.circular(22),
      ),
      child: AdaptiveRow(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info, color: color, size: 17),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // FILTERS CARD
  // ---------------------------------------------------------------------------
  Widget _filtersCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 14,
          runSpacing: 14,
          alignment: WrapAlignment.end,
          children: [
            _textField("بحث", (v) => search = v.trim()),
            _dropdownType(),
            _dropdownStatus(),
            _textField("البنك", (v) => bank = v.trim()),
            _textField("الفرع", (v) => branch = v.trim()),
            _textField("العملة", (v) => currency = v.trim()),
            _numberField("أقل مبلغ", (v) => minAmount = v),
            _numberField("أعلى مبلغ", (v) => maxAmount = v),
            _datePicker("إصدار من", issueFrom, (d) => issueFrom = d),
            _datePicker("إصدار إلى", issueTo, (d) => issueTo = d),
            _datePicker("استحقاق من", dueFrom, (d) => dueFrom = d),
            _datePicker("استحقاق إلى", dueTo, (d) => dueTo = d),
            ElevatedButton(
              child: const Text("تطبيق الفلاتر"),
              onPressed: () => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }

  Widget _textField(String label, Function(String) onChange) {
    return SizedBox(
      width: 180,
      child: TextField(
        inputFormatters: const [YallaDigitNormalizer()],
        decoration: InputDecoration(labelText: label),
        textAlign: TextAlign.right,
        onChanged: onChange,
      ),
    );
  }

  Widget _numberField(String label, Function(double?) onChange) {
    return SizedBox(
      width: 150,
      child: TextField(
        inputFormatters: const [YallaDigitNormalizer()],
        decoration: InputDecoration(labelText: label),
        keyboardType: TextInputType.number,
        textAlign: TextAlign.right,
        onChanged: (v) => onChange(double.tryParse(v)),
      ),
    );
  }

  Widget _dropdownType() {
    return SizedBox(
      width: 180,
      child: DropdownButtonFormField<ChequeType?>(
        value: type,
        decoration: const InputDecoration(labelText: "نوع الشيك"),
        items: const [
          DropdownMenuItem(value: null, child: Text("الكل")),
          DropdownMenuItem(value: ChequeType.incoming, child: Text("وارد")),
          DropdownMenuItem(value: ChequeType.outgoing, child: Text("صادر")),
          DropdownMenuItem(
              value: ChequeType.collection, child: Text("قيد التحصيل")),
        ],
        onChanged: (v) => setState(() => type = v),
      ),
    );
  }

  Widget _dropdownStatus() {
    return SizedBox(
      width: 180,
      child: DropdownButtonFormField<ChequeStatus?>(
        value: status,
        decoration: const InputDecoration(labelText: "الحالة"),
        items: ChequeStatus.values
            .map((e) => DropdownMenuItem(
                  value: e,
                  child: Text(_statusLabel(e)),
                ))
            .toList(),
        onChanged: (v) => setState(() => status = v),
      ),
    );
  }

  Widget _datePicker(String label, DateTime? value, Function(DateTime?) set) {
    return SizedBox(
      width: 180,
      child: GestureDetector(
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
          );
          if (d != null) setState(() => set(d));
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
  // APPLY FILTERS
  // ---------------------------------------------------------------------------
  List<Cheque> _applyFilters(List<Cheque> all) {
    return all.where((c) {
      if (search != null &&
          search!.isNotEmpty &&
          !c.chequeNo.contains(search!) &&
          !c.bankName.contains(search!)) {
        return false;
      }

      if (type != null && c.chequeType != type) return false;

      if (status != null && c.status != status) return false;

      if (bank != null && bank!.isNotEmpty && !c.bankName.contains(bank!)) {
        return false;
      }

      if (branch != null &&
          branch!.isNotEmpty &&
          !c.bankBranch.contains(branch!)) {
        return false;
      }

      if (currency != null && currency!.isNotEmpty && c.currency != currency) {
        return false;
      }

      if (minAmount != null && c.amount < minAmount!) return false;
      if (maxAmount != null && c.amount > maxAmount!) return false;

      if (issueFrom != null && c.issueDate.isBefore(issueFrom!)) return false;
      if (issueTo != null && c.issueDate.isAfter(issueTo!)) return false;

      if (dueFrom != null && c.dueDate.isBefore(dueFrom!)) return false;
      if (dueTo != null && c.dueDate.isAfter(dueTo!)) return false;

      return true;
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // TABLE — DESKTOP
  // ---------------------------------------------------------------------------
  Widget _buildTable(List<Cheque> list) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: AdaptiveDataTable(
        headingRowColor: MaterialStateProperty.all(AppColors.primary),
        headingTextStyle: const TextStyle(color: Colors.white),
        columns: const [
          DataColumn(label: Text("رقم الشيك")),
          DataColumn(label: Text("القيمة")),
          DataColumn(label: Text("النوع")),
          DataColumn(label: Text("الحالة")),
          DataColumn(label: Text("الإصدار")),
          DataColumn(label: Text("الاستحقاق")),
          DataColumn(label: Text("البنك / الفرع")),
          DataColumn(label: Text("إجراءات")),
        ],
        rows: list.map((c) {
          return DataRow(
            cells: [
              DataCell(Text(c.chequeNo)),
              DataCell(Text("${c.amount} ${c.currency}")),
              DataCell(Text(_typeLabel(c.chequeType))),
              DataCell(Text(_statusLabel(c.status))),
              DataCell(Text(df.format(c.issueDate))),
              DataCell(Text(df.format(c.dueDate))),
              DataCell(Text("${c.bankName} / ${c.bankBranch}")),
              DataCell(AdaptiveRow(
                children: [
                  IconButton(
                    icon: const Icon(Icons.visibility),
                    onPressed: () => _openDetails(c),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _openEdit(c),
                  ),
                  if (c.glEntryId != null)
                    IconButton(
                      icon: const Icon(Icons.receipt_long,
                          color: AppColors.primary),
                      onPressed: () => _openGL(c),
                    ),
                ],
              )),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CARDS — MOBILE
  // ---------------------------------------------------------------------------
  Widget _buildCards(List<Cheque> list) {
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (_, i) {
        final c = list[i];
        final days = _daysToDue(c.dueDate);
        final dueText = _dueBannerText(days);
        final dueColor = _dueBannerColor(days);

        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (dueText.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: dueColor.withOpacity(.13),
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
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 5),
                Text(
                  "${_typeLabel(c.chequeType)} • ${_statusLabel(c.status)}\n"
                  "${c.amount} ${c.currency}\n"
                  "${c.bankName} - ${c.bankBranch}\n"
                  "استحقاق: ${df.format(c.dueDate)}",
                  textAlign: TextAlign.right,
                ),
                AdaptiveRow(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                        icon: const Icon(Icons.visibility),
                        onPressed: () => _openDetails(c)),
                    IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _openEdit(c)),
                    if (c.glEntryId != null)
                      IconButton(
                        icon: const Icon(Icons.receipt_long,
                            color: AppColors.primary),
                        onPressed: () => _openGL(c),
                      ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  int _daysToDue(DateTime due) {
    final today = DateTime.now();
    final t = DateTime(today.year, today.month, today.day);
    return due.difference(t).inDays;
  }

  String _dueBannerText(int d) {
    if (d < 0) return "متأخر ${d.abs()} يوم";
    if (d == 0) return "مستحق اليوم";
    if (d == 1) return "يستحق غداً";
    if (d <= 3) return "يستحق خلال $d يوم";
    return "";
  }

  Color _dueBannerColor(int d) {
    if (d < 0) return Colors.red;
    if (d == 0) return Colors.orange.shade700;
    if (d <= 3) return Colors.orange;
    return Colors.transparent;
  }

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

  // ---------------------------------------------------------------------------
  // OPEN NAVIGATION ACTIONS
  // ---------------------------------------------------------------------------
  void _openDetails(Cheque c) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChequeDetailsScreen(cheque: c)),
    );
  }

  void _openEdit(Cheque c) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChequeAddScreen(editCheque: c)),
    );
  }

  void _openGL(Cheque c) {
    Navigator.pushNamed(
      context,
      "/finance/gl/entry",
      arguments: {"entryId": c.glEntryId},
    );
  }

  // ---------------------------------------------------------------------------
  // EXPORT — EXCEL
  // ---------------------------------------------------------------------------
  Future<void> _exportExcel(List<Cheque> list) async {
    final excel = Excel.createExcel();
    final sheet = excel['Cheques'];

    sheet.appendRow([
      TextCellValue("رقم الشيك"),
      TextCellValue("القيمة"),
      TextCellValue("النوع"),
      TextCellValue("الحالة"),
      TextCellValue("الإصدار"),
      TextCellValue("الاستحقاق"),
      TextCellValue("البنك"),
      TextCellValue("الفرع"),
    ]);

    for (final c in list) {
      sheet.appendRow([
        TextCellValue(c.chequeNo),
        DoubleCellValue(c.amount),
        TextCellValue(_typeLabel(c.chequeType)),
        TextCellValue(_statusLabel(c.status)),
        TextCellValue(df.format(c.issueDate)),
        TextCellValue(df.format(c.dueDate)),
        TextCellValue(c.bankName),
        TextCellValue(c.bankBranch),
      ]);
    }

    final bytes = excel.encode();
    if (bytes == null) return;

    final dir = await getDownloadsDirectory();
    final file = File(p.join(dir!.path, "supplier_cheques.xlsx"));

    await file.writeAsBytes(bytes);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("تم تصدير Excel بنجاح")),
    );
  }

  // ---------------------------------------------------------------------------
  // EXPORT — PDF
  // ---------------------------------------------------------------------------
  Future<void> _exportPdf(List<Cheque> list) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        build: (_) => [
          pw.Text(
            "شيكات المورد: ${widget.supplierName}",
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 20),
          pw.Table.fromTextArray(
            headers: [
              "رقم الشيك",
              "القيمة",
              "النوع",
              "الحالة",
              "الإصدار",
              "الاستحقاق",
              "البنك"
            ],
            data: list.map((c) {
              return [
                c.chequeNo,
                "${c.amount} ${c.currency}",
                _typeLabel(c.chequeType),
                _statusLabel(c.status),
                df.format(c.issueDate),
                df.format(c.dueDate),
                "${c.bankName} / ${c.bankBranch}",
              ];
            }).toList(),
          ),
        ],
      ),
    );

    final dir = await getDownloadsDirectory();
    final file = File(p.join(dir!.path, "supplier_cheques.pdf"));
    await file.writeAsBytes(await pdf.save());

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("تم تصدير PDF بنجاح")),
    );
  }
}
