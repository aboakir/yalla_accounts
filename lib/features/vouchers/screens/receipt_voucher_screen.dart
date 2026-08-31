// ---------------------------------------------------------------------------
// 📁 lib/features/finance/vouchers/receipt_voucher_screen.dart
// ReceiptVoucherScreen — FINAL 2025 CLEAN VERSION
// - متوافق تمامًا مع Payment model الجديد
// - بدون partyId
// - يحتوي isIncome في كل عملية دفع
// - دعم كامل لسداد ملفات إصلاح + سداد عام
// - متوافق مع الشيكات الجديدة
// ---------------------------------------------------------------------------

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/colors.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import '../../../core/services/db_service.dart';
import '../../../core/widgets/yalla_appbar.dart';
import '../../../core/widgets/sidebar/yalla_sidebar.dart';
import '../../../shared/widgets/responsive.dart';

import '../../../features/settings/services/workshop_settings_service.dart';
import '../../../features/settings/models/workshop_settings.dart';

import '../../finance/payments/models/payment.dart';
import '../../finance/payments/services/payment_service.dart';

import 'package:yalla_accounts/features/cheques/widgets/steps/cheque_step_entry.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

// ============================================================================

class ReceiptVoucherScreen extends StatefulWidget {
  const ReceiptVoucherScreen({super.key});

  @override
  State<ReceiptVoucherScreen> createState() => _ReceiptVoucherScreenState();
}

class _ReceiptVoucherScreenState extends State<ReceiptVoucherScreen> {
  final _formKey = GlobalKey<FormState>();

  String selectedClientType = "CLIENT";
  String? selectedClientId;
  String selectedMethod = "CASH";
  DateTime selectedDate = DateTime.now();

  final TextEditingController amountCtrl = TextEditingController();
  final TextEditingController notesCtrl = TextEditingController();

  WorkshopSettings? settings;

  List<Map<String, Object?>> clients = [];
  List<Map<String, Object?>> insurances = [];

  List<_RepairItem> selectedRepairs = [];
  List<Map<String, Object?>> repairsPool = [];

  double totalPayment = 0.0;
  bool loading = true;
  bool _isSaving = false;

  Map<String, dynamic>? _pendingCheque;

  final NumberFormat _currency = NumberFormat('#,##0.00', 'ar');

// ============================================================================

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    settings = await WorkshopSettingsService.instance.getOrDefaults();
    await _loadClients();
    await _loadInsurances();
    setState(() => loading = false);
  }

  Future<void> _loadClients() async {
    final db = await DBService.database;
    clients = await db.rawQuery("""
      SELECT id, name FROM clients
      WHERE type != 'شركة تأمين'
      ORDER BY name
    """);
  }

  Future<void> _loadInsurances() async {
    final db = await DBService.database;
    insurances = await db.rawQuery("""
      SELECT id, name FROM clients
      WHERE type = 'شركة تأمين'
      ORDER BY name
    """);
  }

  Future<void> _loadRepairsPool() async {
    if (selectedClientId == null) return;

    final db = await DBService.database;

    repairsPool = await db.rawQuery("""
      SELECT 
        id, vehicleType, vehicleModel, vehicleNumber,
        fileValue, total_paid_amount, receivedDate, thumbnail_path
      FROM repairs
      WHERE client_id = ?
        AND (isArchived IS NULL OR isArchived = 0)
        AND (fileValue > IFNULL(total_paid_amount, 0))
      ORDER BY receivedDate DESC
    """, [selectedClientId]);
  }

// ============================================================================

  Future<void> _openRepairsPicker() async {
    await _loadRepairsPool();

    if (repairsPool.isEmpty) {
      _snack("لا يوجد ملفات مفتوحة لهذا العميل.");
      return;
    }

    List<String> temp = selectedRepairs.map((e) => e.id).toList();
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          return AdaptiveAlertDialog(
            title: const Text("اختر الملفات المطلوب سدادها",
                textAlign: TextAlign.center),
            content: SizedBox(
              width: MediaQuery.sizeOf(ctx).width < 600 ? double.infinity : 700,
              height: MediaQuery.sizeOf(ctx).width < 600
                  ? (MediaQuery.sizeOf(ctx).height * 0.62)
                      .clamp(320.0, 500.0)
                      .toDouble()
                  : 500,
              child: ListView.builder(
                itemCount: repairsPool.length,
                itemBuilder: (_, i) {
                  final r = repairsPool[i];
                  final rid = r["id"].toString();
                  final selected = temp.contains(rid);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: AdaptiveRow(
                      children: [
                        _buildRepairImage(r["thumbnail_path"]?.toString()),
                        const SizedBox(width: 16),
                        _buildRepairInfo(r),
                        Checkbox(
                          value: selected == true,
                          onChanged: (v) {
                            setD(() {
                              v == true ? temp.add(rid) : temp.remove(rid);
                            });
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("إلغاء"),
              ),
              ElevatedButton(
                onPressed: () {
                  selectedRepairs.clear();
                  for (final r in repairsPool) {
                    final rid = r["id"].toString();
                    if (temp.contains(rid)) {
                      selectedRepairs.add(
                        _RepairItem(
                          id: rid,
                          type: "${r["vehicleType"]}",
                          model: "${r["vehicleModel"]}",
                          number: "${r["vehicleNumber"]}",
                          fileValue: (r["fileValue"] as num).toDouble(),
                          paid:
                              (r["total_paid_amount"] as num?)?.toDouble() ?? 0,
                        ),
                      );
                    }
                  }
                  _recalculateTotal();
                  setState(() {});
                  Navigator.pop(ctx);
                },
                child: const Text("تأكيد"),
              ),
            ],
          );
        },
      ),
    );
  }

// ============================================================================

  Widget _buildRepairImage(String? path) {
    if (path == null || path.isEmpty) {
      return Container(
        width: 70,
        height: 70,
        alignment: Alignment.center,
        color: Colors.grey.shade200,
        child: const Icon(Icons.car_crash),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(
        File(path),
        width: 70,
        height: 70,
        fit: BoxFit.cover,
      ),
    );
  }

  Widget _buildRepairInfo(Map<String, Object?> r) {
    final receive = DateTime.tryParse("${r["receivedDate"]}");

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("${r["vehicleType"]} ${r["vehicleModel"]}",
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text("رقم: ${r["vehicleNumber"]}"),
          if (receive != null)
            Text(
              DateFormat('yyyy-MM-dd').format(receive),
              style: const TextStyle(color: Colors.grey),
            ),
        ],
      ),
    );
  }

// ============================================================================

  void _recalculateTotal() {
    totalPayment =
        selectedRepairs.fold(0.0, (s, r) => s + (r.paymentAmount ?? 0.0));
    setState(() {});
  }

// ============================================================================
// ★★★ النسخة المصححة من _saveVoucher — لا تحتوي partyId وتضيف isIncome ★★★
// ============================================================================

  Future<void> _saveVoucher() async {
    if (_isSaving) return;
    if (selectedClientId == null) return _snack("اختر العميل");

    final totalAmount = selectedRepairs.isNotEmpty
        ? totalPayment
        : (double.tryParse(amountCtrl.text.trim()) ?? 0.0);

    if (totalAmount <= 0) return _snack("المبلغ غير صالح");

    final payMethod = selectedMethod == "CASH"
        ? "cash"
        : selectedMethod == "BANK"
            ? "bank"
            : "cheque";

    if (selectedMethod == "CHEQUE") {
      if (_pendingCheque == null) {
        return _snack("أدخل بيانات الشيك أولًا");
      }

      // One physical cheque is one financial instrument/source document.
      // Do not split one cheque into independent PAYMENT documents.
      if (selectedRepairs.length > 1) {
        return _snack(
          "الشيك الواحد يجب ربطه بملف واحد أو بسند قبض عام. "
          "أنشئ سندًا منفصلًا لكل شيك.",
        );
      }
    }

    if (mounted) setState(() => _isSaving = true);

    try {
      if (selectedRepairs.isNotEmpty) {
        for (final r in selectedRepairs) {
          final amt = r.paymentAmount ?? 0;
          if (amt <= 0) continue;

          final payment = Payment(
            id: "",
            clientId: int.tryParse(selectedClientId!),
            repairId: r.id,
            relatedRepairId: r.id,
            invoiceId: null,
            amount: amt,
            date: selectedDate,
            method: payMethod,
            accountName: null,
            status: "confirmed",
            notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
            attachments: null,
            glEntryId: null,
            chequeId: null,
            isIncome: true,
          );

          await PaymentService.insertAndPostReceipt(
            payment: payment,
            customerName: "",
            method: payMethod,
            updateInvoice: true,
            chequeDraft: selectedMethod == "CHEQUE" ? _pendingCheque : null,
          );
        }
      } else {
        final payment = Payment(
          id: "",
          clientId: int.tryParse(selectedClientId!),
          repairId: null,
          relatedRepairId: null,
          invoiceId: null,
          amount: totalAmount,
          date: selectedDate,
          method: payMethod,
          accountName: null,
          status: "confirmed",
          notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
          attachments: null,
          glEntryId: null,
          chequeId: null,
          isIncome: true,
        );

        await PaymentService.insertAndPostReceipt(
          payment: payment,
          customerName: "",
          method: payMethod,
          updateInvoice: false,
          chequeDraft: selectedMethod == "CHEQUE" ? _pendingCheque : null,
        );
      }

      if (!mounted) return;
      _snack("تم حفظ سند القبض بنجاح");
      _resetForm();
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.receiptVouchersList,
        (route) => route.settings.name == AppRoutes.dashboard || route.isFirst,
      );
    } catch (e) {
      if (mounted) _snack("خطأ أثناء الحفظ: $e");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

// ============================================================================

  void _resetForm() {
    selectedClientType = "CLIENT";
    selectedClientId = null;
    selectedMethod = "CASH";
    selectedDate = DateTime.now();
    selectedRepairs.clear();
    amountCtrl.clear();
    notesCtrl.clear();
    totalPayment = 0.0;
    _pendingCheque = null;
    setState(() {});
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

// ============================================================================
// UI
// ============================================================================

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: YallaAppBar(
        workshopName: settings?.workshopName ?? "",
        showThemeToggle: false,
        showSearch: false,
      ),
      drawer: isDesktop ? null : const YallaSidebar(),
      body: AdaptiveRow(
        children: [
          if (isDesktop) const YallaSidebar(),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : _buildForm(),
          ),
        ],
      ),
    );
  }

// ============================================================================

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(context.isPhoneWidth ? 12 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const Text(
                  "سند قبض",
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary),
                ),
                const SizedBox(height: 25),
                _buildClientType(),
                _buildClientSelector(),
                if (selectedClientId != null) _buildRepairSection(),
                if (selectedClientId != null && selectedRepairs.isEmpty)
                  _buildGeneralPaymentBox(),
                _buildPaymentMethod(),
                _buildDatePicker(),
                _buildNotes(),
                const SizedBox(height: 20),
                _buildSaveButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

// ============================================================================

  Widget _buildClientType() {
    return _card(
      title: "نوع العميل",
      child: DropdownButtonFormField(
        value: selectedClientType,
        items: const [
          DropdownMenuItem(value: "CLIENT", child: Text("عميل عادي")),
          DropdownMenuItem(value: "INSURANCE", child: Text("شركة تأمين")),
        ],
        onChanged: (v) {
          selectedClientType = v!;
          selectedClientId = null;
          selectedRepairs.clear();
          totalPayment = 0;
          amountCtrl.clear();
          setState(() {});
        },
      ),
    );
  }

  Future<void> _openClientPicker() async {
    final data = selectedClientType == "CLIENT" ? clients : insurances;

    final TextEditingController searchCtrl = TextEditingController();
    List<Map<String, Object?>> filtered = List.from(data);

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setD) {
            return AdaptiveAlertDialog(
              title: const Text("اختر العميل", textAlign: TextAlign.center),
              content: SizedBox(
                width:
                    MediaQuery.sizeOf(ctx).width < 600 ? double.infinity : 500,
                height: MediaQuery.sizeOf(ctx).width < 600
                    ? (MediaQuery.sizeOf(ctx).height * 0.58)
                        .clamp(300.0, 500.0)
                        .toDouble()
                    : 500,
                child: Column(
                  children: [
                    TextField(
                      controller: searchCtrl,
                      decoration: const InputDecoration(
                        hintText: "ابحث باسم العميل",
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        setD(() {
                          filtered = data
                              .where((c) => c["name"]
                                  .toString()
                                  .toLowerCase()
                                  .contains(v.toLowerCase()))
                              .toList();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final c = filtered[i];
                          return ListTile(
                            title: Text(c["name"].toString()),
                            onTap: () {
                              selectedClientId = c["id"].toString();
                              selectedRepairs.clear();
                              totalPayment = 0;
                              Navigator.pop(ctx);
                              setState(() {});
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("إلغاء"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildClientSelector() {
    final data = selectedClientType == "CLIENT" ? clients : insurances;

    final selectedName = selectedClientId == null
        ? ""
        : data
            .firstWhere((e) => e["id"].toString() == selectedClientId)["name"]
            .toString();

    return _card(
      title: selectedClientType == "CLIENT" ? "العميل" : "شركة تأمين",
      child: InkWell(
        onTap: _openClientPicker,
        child: InputDecorator(
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
          child: Text(
            selectedName.isEmpty ? "اضغط لاختيار العميل" : selectedName,
            style: TextStyle(
              color: selectedName.isEmpty ? Colors.grey : Colors.black,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRepairSection() {
    return _card(
      title: "ملفات الإصلاح",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdaptiveRow(
            children: [
              ElevatedButton(
                onPressed: _openRepairsPicker,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary),
                child: const Text("اختيار الملفات"),
              ),
              const SizedBox(width: 12),
              if (selectedRepairs.isNotEmpty)
                ElevatedButton(
                  onPressed: () {
                    selectedRepairs.clear();
                    totalPayment = 0;
                    setState(() {});
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text("إلغاء الكل"),
                ),
            ],
          ),
          if (selectedRepairs.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              "المبلغ الإجمالي: ${_currency.format(totalPayment)}",
              style: const TextStyle(
                  color: Colors.green,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Column(children: selectedRepairs.map(_repairPaymentTile).toList()),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                "يمكنك اختيار ملفات محددة أو سداد مبلغ عام بدون ملفات",
                style: TextStyle(color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGeneralPaymentBox() {
    return _card(
      title: "مبلغ عام",
      child: TextFormField(
        controller: amountCtrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          hintText: "المبلغ",
          border: OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _buildPaymentMethod() {
    return _card(
      title: "طريقة الدفع",
      child: DropdownButtonFormField(
        value: selectedMethod,
        items: const [
          DropdownMenuItem(value: "CASH", child: Text("نقدًا")),
          DropdownMenuItem(value: "BANK", child: Text("بنك")),
          DropdownMenuItem(value: "CHEQUE", child: Text("شيك")),
        ],
        onChanged: (v) async {
          selectedMethod = v!;
          setState(() {});

          if (selectedMethod == "CHEQUE") {
            double amt = selectedRepairs.isEmpty
                ? double.tryParse(amountCtrl.text.trim()) ?? 0
                : totalPayment;

            if (amt <= 0) {
              _snack("أدخل مبلغ صحيح قبل اختيار الشيك");
              selectedMethod = "CASH";
              setState(() {});
              return;
            }

            final data = await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => ChequeStepEntry(
                amount: amt,
                onSubmit: (d) => Navigator.pop(ctx, d),
              ),
            );

            if (data == null) {
              selectedMethod = "CASH";
              setState(() {});
              return;
            }

            _pendingCheque = data;
          }
        },
      ),
    );
  }

  Widget _buildDatePicker() {
    return _card(
      title: "تاريخ السند",
      child: GestureDetector(
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: selectedDate,
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
          );
          if (d != null) {
            selectedDate = d;
            setState(() {});
          }
        },
        child: InputDecorator(
          decoration: const InputDecoration(border: OutlineInputBorder()),
          child: Text(DateFormat('yyyy-MM-dd').format(selectedDate)),
        ),
      ),
    );
  }

  Widget _buildNotes() {
    return _card(
      title: "ملاحظات",
      child: TextFormField(
        controller: notesCtrl,
        maxLines: 3,
        decoration: const InputDecoration(hintText: "اختياري"),
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveVoucher,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          padding: const EdgeInsets.all(18),
        ),
        child: _isSaving
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text("حفظ السند", style: TextStyle(fontSize: 18)),
      ),
    );
  }

// ============================================================================

  Widget _card({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _repairPaymentTile(_RepairItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("${item.type} ${item.model} — رقم ${item.number}",
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          Text("قيمة الملف: ${_currency.format(item.fileValue)}"),
          Text("المدفوع سابقًا: ${_currency.format(item.paid)}"),
          Text("المتبقي: ${_currency.format(item.remaining)}"),
          const SizedBox(height: 10),
          TextFormField(
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              hintText: "المدفوع الآن",
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              item.paymentAmount = double.tryParse(v) ?? 0.0;
              _recalculateTotal();
            },
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// موديل إصلاح داخلي بسيط
// ============================================================================

class _RepairItem {
  final String id;
  final String type;
  final String model;
  final String number;
  final double fileValue;
  final double paid;

  double? paymentAmount;

  _RepairItem({
    required this.id,
    required this.type,
    required this.model,
    required this.number,
    required this.fileValue,
    required this.paid,
  });

  double get remaining => fileValue - paid;
}
