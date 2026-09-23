import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/utils/user_facing_error.dart';
import 'package:yalla_accounts/core/utils/yalla_digits.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_policy_cashflow_service.dart';

typedef InsuranceCashflowLoader = Future<InsurancePolicyCashflowSnapshot>
    Function(String policyId);
typedef InsuranceChequeBookLoader = Future<List<InsuranceChequeBookOption>>
    Function();

class PolicyPaymentsScreen extends StatefulWidget {
  const PolicyPaymentsScreen({
    super.key,
    required this.policyId,
    this.row,
    this.loader,
    this.chequeBookLoader,
  });

  final dynamic policyId;
  final Map<String, dynamic>? row;
  final InsuranceCashflowLoader? loader;
  final InsuranceChequeBookLoader? chequeBookLoader;

  @override
  State<PolicyPaymentsScreen> createState() => _PolicyPaymentsScreenState();
}

class _PolicyPaymentsScreenState extends State<PolicyPaymentsScreen> {
  final _date = DateFormat('yyyy-MM-dd', 'en_US');

  bool _loading = true;
  String? _error;
  InsurancePolicyCashflowSnapshot? _snapshot;

  String get _policyId => widget.policyId.toString().trim();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_policyId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'معرف وثيقة التأمين غير صالح.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await (widget.loader?.call(_policyId) ??
          InsurancePolicyCashflowService.load(_policyId));
      if (!mounted) return;
      setState(() {
        _snapshot = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = UserFacingError.message(e);
      });
    }
  }

  String _money(double value) => value.toStringAsFixed(2);

  String _methodLabel(String method) {
    switch (method.trim().toUpperCase()) {
      case 'CASH':
        return 'نقد';
      case 'CHEQUE':
        return 'شيك';
      case 'BANK':
        return 'بنك';
      case 'TRANSFER':
        return 'تحويل';
      case 'MIXED':
        return 'متعدد';
      default:
        return method.trim().isEmpty ? '-' : method;
    }
  }

  String _directionLabel(String direction) {
    switch (direction) {
      case 'CUSTOMER_RECEIPT':
        return 'قبض من العميل';
      case 'INSURER_PAYMENT':
        return 'دفع لشركة التأمين';
      case 'REFUND':
        return 'رد للعميل';
      default:
        return direction;
    }
  }

  Future<void> _pickDate({
    required DateTime current,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) onPicked(picked);
  }

  Future<void> _collectCustomer() async {
    final data = _snapshot;
    if (data == null || data.balances.customerOutstanding <= 0.005) return;

    final amount = TextEditingController(
      text: data.balances.customerOutstanding.toStringAsFixed(2),
    );
    final notes = TextEditingController();
    final chequeNo = TextEditingController();
    final bankName = TextEditingController();
    final drawerName = TextEditingController(text: data.insuredName);
    var method = 'CASH';
    var activityDate = DateTime.now();
    var chequeDueDate = DateTime.now().add(const Duration(days: 30));

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AdaptiveAlertDialog(
          title: const Text('قبض من العميل', textAlign: TextAlign.right),
          content: SizedBox(
            width:
                MediaQuery.sizeOf(context).width < 600 ? double.infinity : 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'المتبقي على العميل: ${_money(data.balances.customerOutstanding)}',
                    textAlign: TextAlign.right,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('insuranceCustomerReceiptAmount'),
                    controller: amount,
                    inputFormatters: const [YallaDigitNormalizer()],
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      labelText: 'المبلغ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: const Key('insuranceCustomerReceiptMethod'),
                    value: method,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'طريقة القبض',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'CASH', child: Text('نقد')),
                      DropdownMenuItem(value: 'BANK', child: Text('بنك')),
                      DropdownMenuItem(value: 'TRANSFER', child: Text('تحويل')),
                      DropdownMenuItem(value: 'CHEQUE', child: Text('شيك')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => method = value);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const Key('insuranceCustomerReceiptDate'),
                    onPressed: () => _pickDate(
                      current: activityDate,
                      onPicked: (value) =>
                          setDialogState(() => activityDate = value),
                    ),
                    icon: const Icon(Icons.event),
                    label: Text(_date.format(activityDate)),
                  ),
                  if (method == 'CHEQUE') ...[
                    const SizedBox(height: 10),
                    TextField(
                      key: const Key('insuranceReceiptChequeNumber'),
                      controller: chequeNo,
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(
                        labelText: 'رقم الشيك',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const Key('insuranceReceiptChequeBank'),
                      controller: bankName,
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(
                        labelText: 'البنك',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const Key('insuranceReceiptChequeDrawer'),
                      controller: drawerName,
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(
                        labelText: 'الساحب',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      key: const Key('insuranceReceiptChequeDueDate'),
                      onPressed: () => _pickDate(
                        current: chequeDueDate,
                        onPicked: (value) =>
                            setDialogState(() => chequeDueDate = value),
                      ),
                      icon: const Icon(Icons.event_busy),
                      label: Text('استحقاق ${_date.format(chequeDueDate)}'),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('insuranceCustomerReceiptNotes'),
                    controller: notes,
                    maxLines: 2,
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              key: const Key('insuranceCustomerReceiptSave'),
              onPressed: () {
                final value = double.tryParse(
                      YallaDigitNormalizer.normalize(amount.text)
                          .replaceAll(',', '.'),
                    ) ??
                    0;
                if (value <= 0 ||
                    value - data.balances.customerOutstanding > 0.005) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تحقق من مبلغ القبض والمتبقي على العميل.'),
                    ),
                  );
                  return;
                }
                if (method == 'CHEQUE' &&
                    (chequeNo.text.trim().isEmpty ||
                        bankName.text.trim().isEmpty ||
                        drawerName.text.trim().isEmpty)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('بيانات الشيك الأساسية مطلوبة.'),
                    ),
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('حفظ سند القبض'),
            ),
          ],
        ),
      ),
    );

    if (accepted == true) {
      final value = double.parse(
        YallaDigitNormalizer.normalize(amount.text).replaceAll(',', '.'),
      );
      Map<String, dynamic>? chequeDraft;
      if (method == 'CHEQUE') {
        chequeDraft = {
          'cheque_no': chequeNo.text.trim(),
          'drawer_name': drawerName.text.trim(),
          'bank_name': bankName.text.trim(),
          'issue_date': activityDate.toIso8601String(),
          'due_date': chequeDueDate.toIso8601String(),
        };
      }
      try {
        await InsurancePolicyCashflowService.collectCustomer(
          operationId:
              'UI-INS-RCPT-$_policyId-${DateTime.now().microsecondsSinceEpoch}',
          policyId: _policyId,
          amount: value,
          date: activityDate,
          method: method,
          notes: notes.text.trim(),
          chequeDraft: chequeDraft,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إنشاء سند القبض وترحيله بنجاح.')),
        );
        await _load();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserFacingError.message(e))),
        );
      }
    }

    amount.dispose();
    notes.dispose();
    chequeNo.dispose();
    bankName.dispose();
    drawerName.dispose();
  }

  Future<void> _payInsurer() async {
    final data = _snapshot;
    if (data == null || data.balances.insurerOutstanding <= 0.005) return;

    final amount = TextEditingController(
      text: data.balances.insurerOutstanding.toStringAsFixed(2),
    );
    final notes = TextEditingController();
    var method = 'CASH';
    var activityDate = DateTime.now();
    var chequeDueDate = DateTime.now().add(const Duration(days: 30));
    List<InsuranceChequeBookOption>? chequeBooks;
    String? selectedChequeBookId;
    String? chequeBookError;
    var chequeBooksLoading = false;

    Future<void> loadChequeBooks(
        StateSetter setDialogState, BuildContext context) async {
      if (chequeBooksLoading || chequeBooks != null) return;
      setDialogState(() {
        chequeBooksLoading = true;
        chequeBookError = null;
      });
      try {
        final loaded = await (widget.chequeBookLoader?.call() ??
            InsurancePolicyCashflowService.listOpenChequeBooks());
        if (!context.mounted) return;
        setDialogState(() {
          chequeBooks = loaded;
          selectedChequeBookId = loaded.isEmpty ? null : loaded.first.id;
          chequeBooksLoading = false;
          if (loaded.isEmpty) {
            chequeBookError = 'لا يوجد دفتر شيكات مفتوح يحتوي أرقامًا متاحة.';
          }
        });
      } catch (e) {
        if (!context.mounted) return;
        setDialogState(() {
          chequeBooksLoading = false;
          chequeBookError = UserFacingError.message(e);
        });
      }
    }

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          InsuranceChequeBookOption? selectedBook;
          final books = chequeBooks;
          if (books != null && selectedChequeBookId != null) {
            for (final book in books) {
              if (book.id == selectedChequeBookId) {
                selectedBook = book;
                break;
              }
            }
          }

          return AdaptiveAlertDialog(
            title: const Text('دفع لشركة التأمين', textAlign: TextAlign.right),
            content: SizedBox(
              width: MediaQuery.sizeOf(context).width < 600
                  ? double.infinity
                  : 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'المتبقي للشركة: ${_money(data.balances.insurerOutstanding)}',
                      textAlign: TextAlign.right,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const Key('insuranceInsurerPaymentAmount'),
                      controller: amount,
                      inputFormatters: const [YallaDigitNormalizer()],
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(
                        labelText: 'المبلغ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      key: const Key('insuranceInsurerPaymentMethod'),
                      value: method,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'طريقة الدفع',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'CASH', child: Text('نقد')),
                        DropdownMenuItem(value: 'BANK', child: Text('بنك')),
                        DropdownMenuItem(
                            value: 'TRANSFER', child: Text('تحويل')),
                        DropdownMenuItem(
                            value: 'CHEQUE', child: Text('شيك صادر')),
                      ],
                      onChanged: (value) async {
                        if (value == null) return;
                        setDialogState(() => method = value);
                        if (value == 'CHEQUE') {
                          await loadChequeBooks(setDialogState, context);
                        }
                      },
                    ),
                    if (method == 'CHEQUE') ...[
                      const SizedBox(height: 10),
                      if (chequeBooksLoading)
                        const LinearProgressIndicator()
                      else if (chequeBookError != null)
                        Text(
                          chequeBookError!,
                          key: const Key('insuranceInsurerChequeBookError'),
                          textAlign: TextAlign.right,
                          style: const TextStyle(color: Colors.redAccent),
                        )
                      else if (books != null && books.isNotEmpty) ...[
                        DropdownButtonFormField<String>(
                          key: const Key('insuranceInsurerChequeBook'),
                          value: selectedChequeBookId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'دفتر الشيكات',
                            border: OutlineInputBorder(),
                          ),
                          items: books
                              .map(
                                (book) => DropdownMenuItem(
                                  value: book.id,
                                  child: Text(book.label,
                                      overflow: TextOverflow.ellipsis),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) => setDialogState(
                              () => selectedChequeBookId = value),
                        ),
                        const SizedBox(height: 10),
                        InputDecorator(
                          key: const Key('insuranceInsurerChequeNextNumber'),
                          decoration: const InputDecoration(
                            labelText: 'رقم الشيك التالي - تلقائي',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            selectedBook == null
                                ? '-'
                                : '#${selectedBook.nextAvailableNumber} • ${selectedBook.bankAccountName}',
                            textAlign: TextAlign.right,
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          key: const Key('insuranceInsurerChequeDueDate'),
                          onPressed: () => _pickDate(
                            current: chequeDueDate,
                            onPicked: (value) =>
                                setDialogState(() => chequeDueDate = value),
                          ),
                          icon: const Icon(Icons.event_busy),
                          label: Text('استحقاق ${_date.format(chequeDueDate)}'),
                        ),
                      ],
                    ],
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      key: const Key('insuranceInsurerPaymentDate'),
                      onPressed: () => _pickDate(
                        current: activityDate,
                        onPicked: (value) =>
                            setDialogState(() => activityDate = value),
                      ),
                      icon: const Icon(Icons.event),
                      label: Text(_date.format(activityDate)),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const Key('insuranceInsurerPaymentNotes'),
                      controller: notes,
                      maxLines: 2,
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظات',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                key: const Key('insuranceInsurerPaymentSave'),
                onPressed: () {
                  final value = double.tryParse(
                        YallaDigitNormalizer.normalize(amount.text)
                            .replaceAll(',', '.'),
                      ) ??
                      0;
                  if (value <= 0 ||
                      value - data.balances.insurerOutstanding > 0.005) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تحقق من مبلغ الدفع والمتبقي للشركة.'),
                      ),
                    );
                    return;
                  }
                  if (method == 'CHEQUE') {
                    if (selectedChequeBookId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('اختر دفتر شيكات مفتوح.')),
                      );
                      return;
                    }
                    if (chequeDueDate.isBefore(activityDate)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('تاريخ استحقاق الشيك لا يسبق تاريخ إصداره.'),
                        ),
                      );
                      return;
                    }
                  }
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('حفظ سند الدفع'),
              ),
            ],
          );
        },
      ),
    );

    if (accepted == true) {
      final value = double.parse(
        YallaDigitNormalizer.normalize(amount.text).replaceAll(',', '.'),
      );
      final operationId =
          'UI-INS-PAY-$_policyId-${DateTime.now().microsecondsSinceEpoch}';
      try {
        if (method == 'CHEQUE') {
          await InsurancePolicyCashflowService.payInsurerByCheque(
            operationId: operationId,
            policyId: _policyId,
            amount: value,
            issueDate: activityDate,
            dueDate: chequeDueDate,
            chequeBookId: selectedChequeBookId!,
            notes: notes.text.trim(),
          );
        } else {
          await InsurancePolicyCashflowService.payInsurer(
            operationId: operationId,
            policyId: _policyId,
            amount: value,
            date: activityDate,
            method: method,
            notes: notes.text.trim(),
          );
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إنشاء سند الدفع وترحيله بنجاح.')),
        );
        await _load();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserFacingError.message(e))),
        );
      }
    }

    amount.dispose();
    notes.dispose();
  }

  Future<void> _reverse(InsurancePolicyCashflowMovement movement) async {
    final reason = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AdaptiveAlertDialog(
        title: const Text('عكس الحركة المالية', textAlign: TextAlign.right),
        content: TextField(
          key: const Key('insuranceMovementReversalReason'),
          controller: reason,
          maxLines: 3,
          textAlign: TextAlign.right,
          decoration: const InputDecoration(
            labelText: 'سبب العكس - إلزامي',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: const Key('insuranceMovementReverseConfirm'),
            onPressed: () {
              if (reason.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('سبب العكس مطلوب.')),
                );
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: const Text('عكس الحركة'),
          ),
        ],
      ),
    );

    if (accepted == true) {
      try {
        await InsurancePolicyCashflowService.reverseMovement(
          movement: movement,
          reason: reason.text,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم عكس الحركة وإعادة الأرصدة.')),
        );
        await _load();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserFacingError.message(e))),
        );
      }
    }
    reason.dispose();
  }

  Widget _metric(String title, double value, IconData icon) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(title, textAlign: TextAlign.right),
                const SizedBox(height: 4),
                Text(
                  _money(value),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _movementCard(InsurancePolicyCashflowMovement movement) {
    final posted = movement.isPosted;
    final reference = movement.receiptNumber != null
        ? 'سند قبض رقم ${movement.receiptNumber}'
        : movement.voucherId != null
            ? 'سند دفع ${movement.voucherId!}'
            : movement.key;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final title = Text(
                  _directionLabel(movement.direction),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                );
                final reverse = movement.canReverse
                    ? TextButton.icon(
                        key: Key('insuranceMovementReverse-${movement.key}'),
                        onPressed: () => _reverse(movement),
                        icon: const Icon(Icons.undo),
                        label: const Text('عكس'),
                      )
                    : null;
                if (constraints.maxWidth < 360) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      title,
                      if (reverse != null) reverse,
                    ],
                  );
                }
                return Row(
                  children: [
                    if (reverse != null) reverse,
                    const Spacer(),
                    Flexible(child: title),
                  ],
                );
              },
            ),
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 16,
              runSpacing: 6,
              children: [
                Text('المبلغ: ${_money(movement.amount)}'),
                Text('الطريقة: ${_methodLabel(movement.method)}'),
                Text('التاريخ: ${_date.format(movement.activityDate)}'),
                Text(reference),
                Text(posted ? 'مرحّل' : 'معكوس'),
                if (movement.chequeId != null)
                  Text(
                    'شيك ${movement.chequeNumber ?? '#${movement.chequeId}'}',
                    key: Key('insuranceChequeRef-${movement.key}'),
                  ),
                if ((movement.chequeStatus ?? '').trim().isNotEmpty)
                  Text('حالة الشيك: ${movement.chequeStatus}'),
                if ((movement.chequeDirection ?? '').trim().isNotEmpty)
                  Text('اتجاه الشيك: ${movement.chequeDirection}'),
                if ((movement.chequeBankName ?? '').trim().isNotEmpty)
                  Text('البنك: ${movement.chequeBankName}'),
                if (movement.chequeDueDate != null)
                  Text('استحقاق: ${_date.format(movement.chequeDueDate!)}'),
              ],
            ),
            if ((movement.notes ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(movement.notes!, textAlign: TextAlign.right),
            ],
            if ((movement.reversalReason ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'سبب العكس: ${movement.reversalReason!}',
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _snapshot;
    return Scaffold(
      key: const Key('insurancePolicyCashflowScreen'),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(
          data == null
              ? 'حركات وثيقة التأمين'
              : 'حركات الوثيقة ${data.policyNumber}',
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  ),
                )
              : data == null
                  ? const Center(child: Text('لا توجد بيانات'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(14),
                        children: [
                          Text(
                            [
                              if (data.insuredName.trim().isNotEmpty)
                                data.insuredName,
                              if (data.companyName.trim().isNotEmpty)
                                data.companyName,
                              if (data.vehiclePlate.trim().isNotEmpty)
                                data.vehiclePlate,
                            ].join(' • '),
                            textAlign: TextAlign.right,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _metric('إجمالي العميل', data.balances.sale,
                                  Icons.person_outline),
                              _metric('المقبوض', data.balances.customerReceipts,
                                  Icons.south_west),
                              _metric(
                                  'المتبقي على العميل',
                                  data.balances.customerOutstanding,
                                  Icons.pending_actions),
                              _metric(
                                  'مستحق الشركة',
                                  data.balances.insurerPayable,
                                  Icons.account_balance_outlined),
                              _metric(
                                  'المدفوع للشركة',
                                  data.balances.insurerPayments,
                                  Icons.north_east),
                              _metric(
                                  'المتبقي للشركة',
                                  data.balances.insurerOutstanding,
                                  Icons.account_balance_wallet_outlined),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              FilledButton.icon(
                                key: const Key('insuranceCollectCustomer'),
                                onPressed:
                                    data.balances.customerOutstanding > 0.005
                                        ? _collectCustomer
                                        : null,
                                icon: const Icon(Icons.receipt_long),
                                label: const Text('سند قبض من العميل'),
                              ),
                              OutlinedButton.icon(
                                key: const Key('insurancePayInsurer'),
                                onPressed:
                                    data.balances.insurerOutstanding > 0.005
                                        ? _payInsurer
                                        : null,
                                icon: const Icon(Icons.payments_outlined),
                                label: const Text('سند دفع لشركة التأمين'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'الحركات المالية',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (data.movements.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'لا توجد حركات مالية لهذه الوثيقة.',
                                textAlign: TextAlign.center,
                              ),
                            )
                          else
                            ...data.movements.map(_movementCard),
                        ],
                      ),
                    ),
    );
  }
}
