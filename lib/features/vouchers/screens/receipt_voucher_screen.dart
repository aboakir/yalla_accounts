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
import 'package:yalla_accounts/core/storage/yalla_stored_image.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/colors.dart';
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

import 'package:yalla_accounts/core/utils/yalla_digits.dart';
// ============================================================================

class ReceiptVoucherScreen extends StatefulWidget {
  final String? initialRepairId;
  final int? initialClientId;
  final String? initialClientType;

  const ReceiptVoucherScreen({
    super.key,
    this.initialRepairId,
    this.initialClientId,
    this.initialClientType,
  });

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
  double availableCredit = 0.0;
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
    await _applyInitialRepairPrefill();
    if (mounted) setState(() => loading = false);
  }

  Future<void> _applyInitialRepairPrefill() async {
    final repairId = widget.initialRepairId?.trim() ?? '';
    if (repairId.isEmpty) return;

    final db = await DBService.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        r.id,
        r.vehicleType,
        r.vehicleModel,
        r.vehicleNumber,
        r.fileValue,
        IFNULL(r.total_paid_amount, 0) AS paid,
        r.client_id,
        c.type AS client_type
      FROM repairs r
      LEFT JOIN clients c ON c.id = r.client_id
      WHERE r.id = ?
        AND (r.isArchived IS NULL OR r.isArchived = 0)
      LIMIT 1
      ''',
      [repairId],
    );
    if (rows.isEmpty) return;

    final row = rows.first;
    final fileValue = (row['fileValue'] as num?)?.toDouble() ?? 0.0;
    final paid = (row['paid'] as num?)?.toDouble() ?? 0.0;
    final remaining = fileValue - paid;

    // A fully settled/zero-value repair must never turn into a generic
    // unallocated receipt just because it was opened from the repair menu.
    if (remaining <= 0.005) return;

    final rowClientId = row['client_id'];
    final clientId = widget.initialClientId ??
        (rowClientId is num
            ? rowClientId.toInt()
            : int.tryParse(rowClientId?.toString() ?? ''));
    if (clientId == null) return;

    final clientIdText = clientId.toString();
    final existsInInsurance =
        insurances.any((c) => c['id'].toString() == clientIdText);
    final existsInClients =
        clients.any((c) => c['id'].toString() == clientIdText);
    if (!existsInInsurance && !existsInClients) return;

    selectedClientType = existsInInsurance ? 'INSURANCE' : 'CLIENT';
    selectedClientId = clientIdText;
    selectedRepairs = <_RepairItem>[
      _RepairItem(
        id: row['id'].toString(),
        type: row['vehicleType']?.toString() ?? '',
        model: row['vehicleModel']?.toString() ?? '',
        number: row['vehicleNumber']?.toString() ?? '',
        fileValue: fileValue,
        paid: paid,
      ),
    ];
    totalPayment = 0.0;
    await _refreshCustomerCredit();
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

  Future<void> _refreshCustomerCredit() async {
    final clientId = int.tryParse(selectedClientId ?? '');
    if (clientId == null) {
      if (mounted) setState(() => availableCredit = 0.0);
      return;
    }
    final value = await PaymentService.customerCreditForClient(clientId);
    if (mounted) setState(() => availableCredit = value);
  }

  Future<void> _applyCustomerCredit() async {
    final clientId = int.tryParse(selectedClientId ?? '');
    if (clientId == null) return _snack('اختر العميل أولًا');
    if (availableCredit <= 0.005) return _snack('لا يوجد رصيد دائن متاح');
    if (selectedRepairs.isEmpty) return _snack('اختر ملف إصلاح لتخصيص الرصيد');
    if (totalPayment > 0.005) {
      return _snack('استخدم الرصيد الدائن قبل إدخال مبلغ قبض جديد');
    }

    _RepairItem? target;
    if (selectedRepairs.length == 1) {
      target = selectedRepairs.first;
    } else {
      final repairId = await showDialog<String>(
        context: context,
        builder: (ctx) => AdaptiveAlertDialog(
          title: const Text('اختر الملف لتخصيص الرصيد'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: selectedRepairs
                  .where((r) => r.remaining > 0.005)
                  .map(
                    (r) => ListTile(
                      title: Text('${r.type} ${r.model} — ${r.number}'),
                      subtitle:
                          Text('المتبقي: ${_currency.format(r.remaining)}'),
                      onTap: () => Navigator.pop(ctx, r.id),
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
          ],
        ),
      );
      if (repairId == null) return;
      for (final item in selectedRepairs) {
        if (item.id == repairId) {
          target = item;
          break;
        }
      }
    }
    final selectedTarget = target;
    if (selectedTarget == null || selectedTarget.remaining <= 0.005) {
      return _snack('الملف المحدد مسدد بالكامل');
    }

    final maxAmount = availableCredit < selectedTarget.remaining
        ? availableCredit
        : selectedTarget.remaining;
    final controller = TextEditingController(
      text: maxAmount.toStringAsFixed(2),
    );
    final requested = await showDialog<double>(
      context: context,
      builder: (ctx) => AdaptiveAlertDialog(
        title: const Text('استخدام الرصيد الدائن'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('الرصيد المتاح: ${_currency.format(availableCredit)}'),
            Text('متبقي الملف: ${_currency.format(selectedTarget.remaining)}'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              inputFormatters: const [YallaDigitNormalizer()],
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'المبلغ المراد تخصيصه',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              Navigator.pop(ctx, value);
            },
            child: const Text('تخصيص'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (requested == null || requested <= 0.005) return;

    try {
      final applied = await PaymentService.allocateCustomerCreditToRepair(
        clientId: clientId,
        repairId: selectedTarget.id,
        amount: requested,
        notes: 'تخصيص رصيد دائن من شاشة سند القبض',
      );
      selectedTarget.paid += applied;
      selectedTarget.paymentAmount = 0.0;
      totalPayment = 0.0;
      await _refreshCustomerCredit();
      if (mounted) setState(() {});
      _snack('تم تخصيص ${_currency.format(applied)} من رصيد العميل للملف');
    } catch (e) {
      _snack('تعذر تخصيص الرصيد: $e');
    }
  }

  Future<void> _openRepairsPicker() async {
    await _loadRepairsPool();

    if (repairsPool.isEmpty) {
      _snack("لا يوجد ملفات مفتوحة لهذا العميل.");
      return;
    }

    List<String> temp = selectedRepairs.map((e) => e.id).toList();

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
    return YallaStoredImage(
      storedPath: path,
      width: 70,
      height: 70,
      cacheWidth: 220,
      borderRadius: BorderRadius.circular(8),
      fallback: Container(
        width: 70,
        height: 70,
        alignment: Alignment.center,
        color: Colors.grey.shade200,
        child: const Icon(Icons.directions_car_outlined),
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

    final clientId = int.tryParse(selectedClientId!);
    if (clientId == null) return _snack("بيانات العميل غير صالحة");
    final generalAmount = selectedRepairs.isEmpty
        ? (double.tryParse(amountCtrl.text.trim()) ?? 0.0)
        : 0.0;
    final totalAmount =
        selectedRepairs.isNotEmpty ? totalPayment : generalAmount;
    if (totalAmount <= 0) return _snack("المبلغ غير صالح");

    final payMethod = selectedMethod == "CASH"
        ? "cash"
        : selectedMethod == "BANK_TRANSFER"
            ? "bank_transfer"
            : selectedMethod == "CARD"
                ? "card"
                : "cheque";

    if (selectedMethod == "CHEQUE" && _pendingCheque == null) {
      return _snack("أدخل بيانات الشيك أولًا");
    }

    if (mounted) setState(() => _isSaving = true);
    try {
      final result = await PaymentService.insertCanonicalReceipt(
        clientId: clientId,
        customerName: _selectedClientName(),
        method: payMethod,
        date: selectedDate,
        allocations: selectedRepairs
            .where((r) => (r.paymentAmount ?? 0) > 0)
            .map((r) => ReceiptAllocationInput(
                  repairId: r.id,
                  amount: r.paymentAmount ?? 0,
                ))
            .toList(),
        unallocatedAmount: generalAmount,
        notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
        chequeDraft: selectedMethod == "CHEQUE" ? _pendingCheque : null,
      );

      if (!mounted) return;
      final number = result.receiptNumber.toString().padLeft(6, '0');
      final creditText = result.customerCredit > 0.005
          ? " — رصيد دائن: ${_currency.format(result.customerCredit)}"
          : "";
      _snack("تم حفظ سند RC-$number بنجاح$creditText");
      _resetForm();
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _snack("خطأ أثناء الحفظ: $e");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _selectedClientName() {
    final data = selectedClientType == "CLIENT" ? clients : insurances;
    if (selectedClientId == null) return '';
    for (final row in data) {
      if (row['id'].toString() == selectedClientId) {
        return row['name']?.toString() ?? '';
      }
    }
    return '';
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
    availableCredit = 0.0;
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
                if (selectedClientId != null && availableCredit > 0.005)
                  _buildCustomerCreditCard(),
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
          availableCredit = 0;
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
                      inputFormatters: const [YallaDigitNormalizer()],
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
                            onTap: () async {
                              selectedClientId = c["id"].toString();
                              selectedRepairs.clear();
                              totalPayment = 0;
                              await _refreshCustomerCredit();
                              if (!mounted) return;
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
      title: widget.initialRepairId == null
          ? "ملفات الإصلاح"
          : "ملف الإصلاح المرتبط بالسند",
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

  Widget _buildCustomerCreditCard() {
    return _card(
      title: 'رصيد العميل الدائن',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _currency.format(availableCredit),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'هذا المبلغ مقبوض سابقًا وغير مخصص لملف. تخصيصه لا ينشئ قبضًا جديدًا.',
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: selectedRepairs.isEmpty ? null : _applyCustomerCredit,
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: const Text('استخدام الرصيد في ملف إصلاح'),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneralPaymentBox() {
    return _card(
      title: "مبلغ عام",
      child: TextFormField(
        inputFormatters: const [YallaDigitNormalizer()],
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
          DropdownMenuItem(value: "BANK_TRANSFER", child: Text("تحويل بنكي")),
          DropdownMenuItem(value: "CARD", child: Text("بطاقة")),
          DropdownMenuItem(value: "CHEQUE", child: Text("شيك")),
        ],
        onChanged: (v) async {
          selectedMethod = v!;
          setState(() {});

          if (selectedMethod == "CHEQUE") {
            if (selectedRepairs.length > 1) {
              _snack(
                  "الشيك الواحد يجب ربطه بملف واحد فقط. أنشئ سندًا منفصلًا لكل شيك.");
              selectedMethod = "CASH";
              setState(() {});
              return;
            }
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
        inputFormatters: const [YallaDigitNormalizer()],
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
            inputFormatters: const [YallaDigitNormalizer()],
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
  double paid;

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
