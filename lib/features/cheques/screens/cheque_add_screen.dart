// -----------------------------------------------------------------------------
// ChequeAddScreen — PRO Production Version (Endorsed/Locked/Copy/UI Enhanced)
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

import '../models/cheque.dart';
import '../providers/cheque_provider.dart';

class ChequeAddScreen extends ConsumerStatefulWidget {
  final Cheque? editCheque;
  final bool embedded;

  const ChequeAddScreen({
    super.key,
    this.editCheque,
    this.embedded = false,
  });

  @override
  ConsumerState<ChequeAddScreen> createState() => _ChequeAddScreenState();
}

class _ChequeAddScreenState extends ConsumerState<ChequeAddScreen> {
  final _formKey = GlobalKey<FormState>();

  final chequeNoCtrl = TextEditingController();
  final drawerNameCtrl = TextEditingController();
  final bankNameCtrl = TextEditingController();
  final branchCtrl = TextEditingController();
  final amountCtrl = TextEditingController();
  final notesCtrl = TextEditingController();

  ChequeType? chequeType;
  ChequeStatus? chequeStatus;
  String? currency;

  String? supplierPid;
  List<Map<String, dynamic>> suppliers = [];

  DateTime? issueDate;
  DateTime? dueDate;
  final df = DateFormat('yyyy-MM-dd');

  bool isEndorsedLocked = false;
  bool isPaymentLocked = false;

  @override
  void initState() {
    super.initState();
    _loadSuppliers();

    final c = widget.editCheque;
    if (c != null) {
      chequeNoCtrl.text = c.chequeNo;
      drawerNameCtrl.text = c.drawerName;
      bankNameCtrl.text = c.bankName;
      branchCtrl.text = c.bankBranch;
      amountCtrl.text = c.amount.toString();
      notesCtrl.text = c.notes ?? '';

      chequeType = c.chequeType;
      chequeStatus = c.status;
      currency = c.currency;
      supplierPid = c.supplierPid;

      issueDate = c.issueDate;
      dueDate = c.dueDate;

      if (c.isEndorsed == 1) isEndorsedLocked = true;

      if (c.linkedPaymentIds.isNotEmpty) {
        isPaymentLocked = true;
      }
    }
  }

  @override
  void dispose() {
    chequeNoCtrl.dispose();
    drawerNameCtrl.dispose();
    bankNameCtrl.dispose();
    branchCtrl.dispose();
    amountCtrl.dispose();
    notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          MediaQuery.sizeOf(context).width < 600 ? 12 : 24,
          12,
          MediaQuery.sizeOf(context).width < 600 ? 12 : 24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _card(context, _buildForm(context)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: const YallaAppBar(
        workshopName: 'Yalla Accounts',
        showThemeToggle: false,
        showSearch: false,
      ),
      drawer: const YallaSidebar(),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            MediaQuery.sizeOf(context).width < 600 ? 12 : 24,
            12,
            MediaQuery.sizeOf(context).width < 600 ? 12 : 24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: _card(context, _buildForm(context)),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, Widget child) {
    final phone = MediaQuery.sizeOf(context).width < 600;
    return Center(
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(phone ? 14 : 24),
        constraints: const BoxConstraints(maxWidth: 760),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
                color: Colors.black12, blurRadius: 12, offset: Offset(0, 3)),
          ],
        ),
        child: child,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // FORM
  // ---------------------------------------------------------------------------
  Widget _buildForm(BuildContext context) {
    final locked = isEndorsedLocked || isPaymentLocked;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.editCheque == null ? 'إضافة شيك' : 'تعديل الشيك',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          if (isEndorsedLocked)
            _lockBanner("هذا الشيك مظهّر — لا يمكن تعديل بياناته"),
          if (isPaymentLocked)
            _lockBanner("هذا الشيك مرتبط بدفعة — لا يمكن تعديل بياناته"),
          const SizedBox(height: 12),
          _section("نسخ بيانات من شيك آخر"),
          _copyChequeButton(),
          const Divider(height: 32),
          _section('معلومات الشيك'),
          _input(chequeNoCtrl, 'رقم الشيك', locked: locked),
          _input(drawerNameCtrl, 'اسم محرر الشيك', locked: locked),
          const SizedBox(height: 20),
          _section('النوع والحالة'),
          _dropdownEnum<ChequeType>(
            label: 'نوع الشيك',
            value: chequeType,
            items: ChequeType.values,
            formatter: _fmtType,
            onChanged: locked ? null : (v) => setState(() => chequeType = v),
          ),
          if (chequeType == ChequeType.outgoing)
            _supplierDropdown(locked: locked),
          _dropdownEnum<ChequeStatus>(
            label: 'حالة الشيك',
            value: chequeStatus,
            items: ChequeStatus.values,
            formatter: _fmtStatus,
            onChanged: locked ? null : (v) => setState(() => chequeStatus = v),
          ),
          const SizedBox(height: 20),
          _section('تفاصيل البنك'),
          _input(bankNameCtrl, 'اسم البنك', locked: locked),
          _input(branchCtrl, 'الفرع', locked: locked),
          const SizedBox(height: 20),
          _section('القيمة'),
          _input(amountCtrl, 'المبلغ',
              type: TextInputType.number, locked: locked),
          _dropdown(
            label: 'العملة',
            value: currency,
            items: const {
              'ILS': 'شيكل',
              'USD': 'دولار',
              'JOD': 'دينار',
              'EUR': 'يورو'
            },
            onChanged: locked ? null : (v) => setState(() => currency = v),
          ),
          const SizedBox(height: 20),
          _section('التواريخ'),
          _dateField('تاريخ الإصدار', issueDate,
              locked ? null : (v) => setState(() => issueDate = v)),
          _dateField('تاريخ الاستحقاق', dueDate,
              locked ? null : (v) => setState(() => dueDate = v)),
          const SizedBox(height: 20),
          _section('ملاحظات'),
          _input(notesCtrl, 'ملاحظات', maxLines: 3, locked: false),
          const SizedBox(height: 30),
          locked
              ? _lockedButton()
              : SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.save),
                    label: const Text('حفظ'),
                    onPressed: () => _save(context),
                  ),
                ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SAVE
  // ---------------------------------------------------------------------------
  Future<void> _save(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;

    if (chequeType == null || chequeStatus == null || currency == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("يرجى تعبئة جميع البيانات الأساسية")),
      );
      return;
    }

    if (chequeType == ChequeType.outgoing && supplierPid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("يجب اختيار المورد للشيك الصادر")),
      );
      return;
    }

    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("قيمة الشيك يجب أن تكون أكبر من صفر")),
      );
      return;
    }

    if (issueDate != null && dueDate != null && dueDate!.isBefore(issueDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("تاريخ الاستحقاق يجب أن يكون بعد تاريخ الإصدار")),
      );
      return;
    }

    final now = DateTime.now();

    final c = widget.editCheque;
    final cheque = Cheque(
      id: c?.id,
      uuid: c?.uuid ?? now.millisecondsSinceEpoch.toString(),
      chequeNo: chequeNoCtrl.text.trim(),
      chequeType: chequeType!,
      status: chequeStatus!,
      drawerName: drawerNameCtrl.text.trim(),
      bankName: bankNameCtrl.text.trim(),
      bankBranch: branchCtrl.text.trim(),
      amount: amount,
      currency: currency!,
      issueDate: issueDate ?? now,
      dueDate: dueDate ?? now,
      notes: notesCtrl.text.trim(),
      createdAt: c?.createdAt ?? now,
      updatedAt: now,
      sourceType: c?.sourceType,
      sourceId: c?.sourceId,
      supplierPid:
          chequeType == ChequeType.outgoing ? supplierPid : c?.supplierPid,
      clientId: c?.clientId,
      originChequeId: c?.originChequeId,
      isEndorsed: c?.isEndorsed ?? 0,
      endorsedAt: c?.endorsedAt,
      linkedPaymentIds: c?.linkedPaymentIds ?? [],
      linkedRepairIds: c?.linkedRepairIds ?? [],
    );

    final notifier = ref.read(chequeProvider.notifier);

    if (c == null) {
      await notifier.addCheque(cheque);
    } else {
      await notifier.updateCheque(cheque);
    }

    if (!context.mounted) return;
    Navigator.pop(context, true);
  }

  // ---------------------------------------------------------------------------
  // COPY CHEQUE FEATURE
  // ---------------------------------------------------------------------------
  Widget _copyChequeButton() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadCheques(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.isEmpty) {
          return const Text("لا يوجد شيكات للنسخ", textAlign: TextAlign.right);
        }

        final list = snap.data!;
        return DropdownButtonFormField<Map<String, dynamic>>(
          decoration: const InputDecoration(labelText: "اختيار شيك للنسخ"),
          items: list
              .map(
                (m) => DropdownMenuItem(
                  value: m,
                  child: Text("${m['cheque_no']} — ${m['drawer_name']}"),
                ),
              )
              .toList(),
          onChanged: (m) {
            chequeNoCtrl.text = m!['cheque_no'];
            drawerNameCtrl.text = m['drawer_name'];
            bankNameCtrl.text = m['bank_name'];
            branchCtrl.text = m['bank_branch'];
            amountCtrl.text = m['amount'].toString();
            currency = m['currency'];
            supplierPid = m['supplier_pid']?.toString();
            setState(() {});
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _loadCheques() async {
    final db = await DBService.database;
    return db.query("cheques", orderBy: "created_at DESC", limit: 50);
  }

  // ---------------------------------------------------------------------------
  // UI HELPERS
  // ---------------------------------------------------------------------------
  Widget _section(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
      );

  Widget _lockBanner(String text) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Text(text,
          textAlign: TextAlign.right,
          style: TextStyle(color: Colors.red.shade800, fontSize: 15)),
    );
  }

  Widget _input(
    TextEditingController c,
    String label, {
    TextInputType type = TextInputType.text,
    int maxLines = 1,
    required bool locked,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        enabled: !locked,
        keyboardType: type,
        textAlign: TextAlign.right,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
        validator: (v) =>
            (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null,
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required String? value,
    required Map<String, String> items,
    Function(String?)? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(labelText: label),
        items: items.entries
            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
            .toList(),
        onChanged: onChanged,
        validator: (v) => v == null ? 'هذا الحقل مطلوب' : null,
      ),
    );
  }

  Widget _dropdownEnum<T>({
    required String label,
    required T? value,
    required List<T> items,
    required String Function(T) formatter,
    Function(T?)? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<T>(
        value: value,
        decoration: InputDecoration(labelText: label),
        items: items
            .map((e) => DropdownMenuItem(value: e, child: Text(formatter(e))))
            .toList(),
        onChanged: onChanged,
        validator: (v) => v == null ? 'هذا الحقل مطلوب' : null,
      ),
    );
  }

  Widget _dateField(
    String label,
    DateTime? date,
    Function(DateTime?)? onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: onChanged == null
            ? null
            : () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) onChanged(picked);
              },
        child: InputDecorator(
          decoration: InputDecoration(labelText: label),
          child: Text(
            date == null ? 'اختر تاريخ' : df.format(date),
            textAlign: TextAlign.right,
          ),
        ),
      ),
    );
  }

  Widget _supplierDropdown({required bool locked}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: supplierPid,
        decoration: const InputDecoration(labelText: "المورّد"),
        items: suppliers
            .map(
              (s) => DropdownMenuItem<String>(
                value: s['id'].toString(),
                child: Text("${s['name']} (ID: ${s['id']})"),
              ),
            )
            .toList(),
        onChanged: locked ? null : (v) => setState(() => supplierPid = v),
        validator: (v) {
          if (chequeType == ChequeType.outgoing && v == null) {
            return "يجب اختيار المورد للشيك الصادر";
          }
          return null;
        },
      ),
    );
  }

  String _fmtType(ChequeType t) {
    switch (t) {
      case ChequeType.incoming:
        return 'وارد';
      case ChequeType.outgoing:
        return 'صادر';
      case ChequeType.collection:
        return 'قيد التحصيل';
    }
  }

  String _fmtStatus(ChequeStatus s) {
    switch (s) {
      case ChequeStatus.pending:
        return 'مُعلّق';
      case ChequeStatus.collected:
        return 'مُحصّل';
      case ChequeStatus.returned:
        return 'راجع';
      case ChequeStatus.cancelled:
        return 'ملغى';
      case ChequeStatus.delivered:
        return 'مُسلّم';
      case ChequeStatus.deposited:
        return 'مودع';
    }
  }

  Widget _lockedButton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        "لا يمكن حفظ التعديلات لأن الشيك مظهّر أو مرتبط بدفعة",
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.black87),
      ),
    );
  }

  Future<void> _loadSuppliers() async {
    final db = await DBService.database;
    suppliers = await db.query("suppliers", orderBy: "name ASC");
    setState(() {});
  }
}
