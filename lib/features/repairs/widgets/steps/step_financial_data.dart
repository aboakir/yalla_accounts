// 📁 lib/features/repairs/widgets/steps/step_financial_data.dart
//
// محدث بالكامل + دعم فتح الاعتماد بالقوة عبر forceEnableApprove.
// لا تعديل على الحسابات أو الجلب أو التحقق.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/clients/services/client_service.dart';
import 'package:yalla_accounts/features/repairs/providers/repair_form_provider.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class StepFinancialData extends ConsumerStatefulWidget {
  final GlobalKey<FormState> formKey;

  /// يفتح عناصر الاعتماد حتى لو المتبقي > 0
  final bool forceEnableApprove;

  /// callback لإضافة شيك
  final VoidCallback? onChequePaymentSelected;

  const StepFinancialData({
    super.key,
    required this.formKey,
    this.forceEnableApprove = true,
    this.onChequePaymentSelected,
  });

  /// مساعد خارجي لحساب إمكانية الاعتماد
  static bool canApprove(WidgetRef ref, {bool force = false}) {
    final f = ref.read(repairFormProvider);
    final remaining = (f.fileValue - f.paidAmount).clamp(0, f.fileValue);
    return force || remaining == 0;
  }

  static bool validateStep(WidgetRef ref, GlobalKey<FormState> formKey) {
    final f = ref.read(repairFormProvider);

    final ok = formKey.currentState?.validate() ?? false;
    if (!ok) return false;

    if (f.paymentStatus == 'مسدد جزئي') {
      if (f.paidAmount <= 0) return false;
      if (f.paidAmount > f.fileValue) return false;
    }

    if (f.paymentMethod == 'حوالة تأمين داخلية') {
      if ((f.transferFromAccount ?? '').trim().isEmpty) return false;
      if ((f.transferToAccount ?? '').trim().isEmpty) return false;
      if ((f.transferCompany ?? '').trim().isEmpty) return false;
      if (f.transferDate == null) return false;
      if ((f.transferAmount ?? 0) <= 0) return false;
    }

    return true;
  }

  @override
  ConsumerState<StepFinancialData> createState() => _StepFinancialDataState();
}

class _StepFinancialDataState extends ConsumerState<StepFinancialData> {
  // Controllers
  late final TextEditingController _paidCtrl;
  late final TextEditingController _transferAmountCtrl;
  late final TextEditingController _transferDateCtrl;

  DateTime? _transferDate;
  File? _transferImage;

  List<String> _insurers = [];
  bool _loadingInsurers = true;

  final _numFmt = NumberFormat('#,##0.00', 'en_US');

  @override
  void initState() {
    super.initState();
    final f = ref.read(repairFormProvider);

    _paidCtrl = TextEditingController(
      text: f.paidAmount > 0 ? MoneyFormatter.number(f.paidAmount) : '',
    );

    _transferAmountCtrl = TextEditingController(
      text: f.transferAmount != null && f.transferAmount! > 0
          ? MoneyFormatter.number(f.transferAmount!)
          : '',
    );

    _transferDate = f.transferDate;
    _transferDateCtrl = TextEditingController(
      text: _transferDate != null
          ? DateFormat('yyyy-MM-dd').format(_transferDate!)
          : '',
    );

    if (f.transferImagePath != null && f.transferImagePath!.isNotEmpty) {
      final file = File(f.transferImagePath!);
      if (file.existsSync()) _transferImage = file;
    }

    _loadInsurers();
  }

  Future<void> _loadInsurers() async {
    try {
      final names = await ClientService.getClientNamesByType('شركة تأمين');
      if (!mounted) return;
      setState(() {
        _insurers = names;
        _loadingInsurers = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingInsurers = false);
    }
  }

  @override
  void dispose() {
    _paidCtrl.dispose();
    _transferAmountCtrl.dispose();
    _transferDateCtrl.dispose();
    super.dispose();
  }

  // ————— Helpers —————

  String _sanitizeNumber(String input) {
    final s = input.replaceAll(',', '').trim();
    final parts = s.split('.');
    if (parts.length <= 2) return s;
    return '${parts.first}.${parts.sublist(1).join()}';
  }

  double _parseNumber(String s) {
    final clean = _sanitizeNumber(s);
    return double.tryParse(clean) ?? 0.0;
  }

  Future<void> _pickTransferImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (picked == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final transfersDir = Directory(p.join(dir.path, 'transfers'));
    if (!transfersDir.existsSync()) {
      await transfersDir.create(recursive: true);
    }
    final newPath = p.join(transfersDir.path, p.basename(picked.path));
    await File(picked.path).copy(newPath);

    setState(() => _transferImage = File(newPath));
    ref.read(repairFormProvider.notifier).updateTransferImagePath(newPath);
  }

  Future<void> _pickTransferDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _transferDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _transferDate = picked;
        _transferDateCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
      });
      ref.read(repairFormProvider.notifier).updateTransferDate(picked);
    }
  }

  void _clearTransferFields() {
    // محليًا
    setState(() {
      _transferImage = null;
      _transferDate = null;
      _transferDateCtrl.clear();
      _transferAmountCtrl.clear();
    });
    // في الـ provider
    final n = ref.read(repairFormProvider.notifier);
    n.updateTransferFromAccount('');
    n.updateTransferToAccount('');
    n.updateTransferCompany('');
    n.updateTransferAmount(0);
    n.updateTransferImagePath('');
    // لا نفرض تاريخ
  }

  @override
  Widget build(BuildContext context) {
    final form = ref.watch(repairFormProvider);
    final notifier = ref.read(repairFormProvider.notifier);

    final remaining =
        (form.fileValue - form.paidAmount).clamp(0, form.fileValue);
    final remColor = remaining == 0 ? Colors.green : Colors.red;

    // هذا المتغير استخدمه لتمكين أي زر/سويتش اعتماد في نفس الويجت أو خارجه
    final canApprove = widget.forceEnableApprove || remaining == 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Form(
        key: widget.formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'البيانات المالية والملاحظات',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),

            // قيمة الملف (قراءة فقط)
            TextFormField(
              inputFormatters: const [YallaDigitNormalizer()],
              readOnly: true,
              initialValue: _numFmt.format(form.fileValue),
              decoration: _dec('قيمة الملف (تحسب تلقائيًا)'),
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 20),

            // طريقة الدفع
            DropdownButtonFormField<String>(
              value: form.paymentMethod.isNotEmpty ? form.paymentMethod : null,
              decoration: _dec('طريقة الدفع'),
              items: const [
                DropdownMenuItem(value: 'نقدًا', child: Text('نقدًا')),
                DropdownMenuItem(value: 'شيك', child: Text('شيك')),
                DropdownMenuItem(value: 'أقساط', child: Text('أقساط')),
                DropdownMenuItem(
                    value: 'حوالة تأمين داخلية',
                    child: Text('حوالة تأمين داخلية')),
              ],
              onChanged: (v) {
                if (v == null) return;
                notifier.updatePaymentMethod(v);
                if (v != 'حوالة تأمين داخلية') {
                  _clearTransferFields();
                }
                setState(() {});
              },
              validator: (v) => v == null ? 'اختر طريقة الدفع' : null,
            ),
            const SizedBox(height: 16),

            // حالة السداد
            DropdownButtonFormField<String>(
              value: form.paymentStatus.isNotEmpty ? form.paymentStatus : null,
              decoration: _dec('حالة السداد'),
              items: const [
                DropdownMenuItem(value: 'غير مسدد', child: Text('غير مسدد')),
                DropdownMenuItem(value: 'مسدد جزئي', child: Text('مسدد جزئي')),
                DropdownMenuItem(value: 'مسدد', child: Text('مسدد')),
              ],
              onChanged: (v) {
                if (v == null) return;
                notifier.updatePaymentStatus(v);

                if (v == 'مسدد') {
                  notifier.updatePaidAmount(form.fileValue);
                  _paidCtrl.text = MoneyFormatter.number(form.fileValue);
                } else if (v == 'مسدد جزئي') {
                  final current = _parseNumber(_paidCtrl.text);
                  final safe =
                      current > form.fileValue ? form.fileValue : current;
                  notifier.updatePaidAmount(safe);
                } else {
                  notifier.updatePaidAmount(0);
                  _paidCtrl.clear();
                }
                setState(() {});
              },
              validator: (v) => v == null ? 'اختر حالة السداد' : null,
            ),
            const SizedBox(height: 16),

            // المبلغ المدفوع عند مسدد جزئي
            if (form.paymentStatus == 'مسدد جزئي') ...[
              TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _paidCtrl,
                decoration: _dec('المبلغ المدفوع'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.green),
                onChanged: (s) {
                  final val = _parseNumber(s);
                  final safe = val > form.fileValue ? form.fileValue : val;
                  if ((safe - val).abs() > 1e-9) {
                    _paidCtrl.text = MoneyFormatter.number(safe);
                    _paidCtrl.selection = TextSelection.fromPosition(
                      TextPosition(offset: _paidCtrl.text.length),
                    );
                  }
                  notifier.updatePaidAmount(safe);
                  setState(() {});
                },
                validator: (s) {
                  final v = _parseNumber(s ?? '');
                  if (v <= 0) return 'أدخل المبلغ المدفوع';
                  if (v > form.fileValue) return 'لا يمكن أن يتجاوز قيمة الملف';
                  return null;
                },
              ),
              const SizedBox(height: 20),
            ],

            // زر إضافة بيانات الشيك (يظهر فقط عند اختيار طريقة الدفع "شيك")
            if (form.paymentMethod == 'شيك' &&
                widget.onChequePaymentSelected != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (form.pendingCheque != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'شيك رقم: ${form.pendingCheque!.chequeNo}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'البنك: ${form.pendingCheque!.bankName}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            'المبلغ: ${form.pendingCheque!.amount} ${form.pendingCheque!.currency}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.receipt_long, size: 18),
                      label: const Text('إضافة بيانات الشيك'),
                      onPressed: widget.onChequePaymentSelected,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // حوالة تأمين داخلية (حقول إضافية)
            if (form.paymentMethod == 'حوالة تأمين داخلية') ...[
              TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                initialValue: form.transferFromAccount,
                decoration: _dec('من حساب'),
                textAlign: TextAlign.right,
                onChanged: notifier.updateTransferFromAccount,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'أدخل الحساب المحوِّل'
                    : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                initialValue: form.transferToAccount,
                decoration: _dec('إلى حساب'),
                textAlign: TextAlign.right,
                onChanged: notifier.updateTransferToAccount,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'أدخل الحساب المستفيد'
                    : null,
              ),
              const SizedBox(height: 12),

              // شركة التأمين من قاعدة البيانات
              _loadingInsurers
                  ? const Center(child: CircularProgressIndicator())
                  : DropdownButtonFormField<String>(
                      value: (form.transferCompany?.isNotEmpty ?? false)
                          ? form.transferCompany
                          : null,
                      decoration: _dec('شركة التأمين'),
                      items: _insurers
                          .map((c) => DropdownMenuItem(
                                value: c,
                                child: Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(c)),
                              ))
                          .toList(),
                      onChanged: (c) {
                        if (c != null) notifier.updateTransferCompany(c);
                      },
                      validator: (v) => v == null ? 'اختر شركة التأمين' : null,
                    ),
              const SizedBox(height: 12),

              OutlinedButton.icon(
                onPressed: _pickTransferImage,
                icon: const Icon(Icons.upload_file),
                label: Text(_transferImage != null
                    ? 'تم تحميل صورة التحويل'
                    : 'تحميل صورة التحويل'),
              ),
              if (_transferImage != null)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Center(
                    child:
                        Icon(Icons.check_circle, color: Colors.green, size: 28),
                  ),
                ),
              const SizedBox(height: 12),

              // تاريخ التحويل
              TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _transferDateCtrl,
                readOnly: true,
                decoration: _dec('تاريخ التحويل'),
                textAlign: TextAlign.right,
                onTap: _pickTransferDate,
                validator: (_) =>
                    (_transferDate == null) ? 'اختر تاريخ التحويل' : null,
              ),
              const SizedBox(height: 12),

              // قيمة الحوالة
              TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _transferAmountCtrl,
                decoration: _dec('قيمة الحوالة'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                onChanged: (s) {
                  final v = _parseNumber(s);
                  ref.read(repairFormProvider.notifier).updateTransferAmount(v);
                },
                validator: (s) =>
                    (_parseNumber(s ?? '') <= 0) ? 'أدخل قيمة الحوالة' : null,
              ),
              const SizedBox(height: 20),
            ],

            // المتبقي
            AdaptiveRow(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'المتبقي:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  '${MoneyFormatter.format(remaining)}'
                  '${canApprove ? '' : ' '}',
                  style: TextStyle(
                    color: remColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            // ملاحظات
            const Text(
              'ملاحظات إضافية',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),

            TextFormField(
              inputFormatters: const [YallaDigitNormalizer()],
              initialValue: form.notes,
              maxLines: 3,
              textAlign: TextAlign.right,
              decoration: _dec('أدخل ملاحظات عامة حول هذا الملف'),
              onChanged: notifier.updateNotes,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.grey),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
      );
}
