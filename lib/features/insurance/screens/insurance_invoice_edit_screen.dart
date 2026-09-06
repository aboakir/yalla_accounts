import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/insurance/models/insurance_invoice.dart';
import 'package:yalla_accounts/features/insurance/providers/insurance_invoice_provider.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class InsuranceInvoiceEditScreen extends ConsumerStatefulWidget {
  final InsuranceInvoice? invoice;

  const InsuranceInvoiceEditScreen({super.key, this.invoice});

  @override
  ConsumerState<InsuranceInvoiceEditScreen> createState() =>
      _InsuranceInvoiceEditScreenState();
}

class _InsuranceInvoiceEditScreenState
    extends ConsumerState<InsuranceInvoiceEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _invoiceNumberController;
  late TextEditingController _clientNameController;
  late TextEditingController _insuranceCompanyController;
  late TextEditingController _amountController;
  late TextEditingController _dateController;
  late TextEditingController _statusController;

  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    final invoice = widget.invoice;
    _invoiceNumberController =
        TextEditingController(text: invoice?.invoiceNumber ?? '');
    _clientNameController =
        TextEditingController(text: invoice?.clientName ?? '');
    _insuranceCompanyController =
        TextEditingController(text: invoice?.insuranceCompany ?? '');
    _amountController =
        TextEditingController(text: invoice?.amount.toString() ?? '0');
    _statusController = TextEditingController(text: invoice?.status ?? '');
    _selectedDate = invoice?.date ?? DateTime.now();
    _dateController = TextEditingController(text: _formatDate(_selectedDate!));
  }

  @override
  void dispose() {
    _invoiceNumberController.dispose();
    _clientNameController.dispose();
    _insuranceCompanyController.dispose();
    _amountController.dispose();
    _dateController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('ar'),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dateController.text = _formatDate(picked);
      });
    }
  }

  Future<void> _saveInvoice() async {
    if (!_formKey.currentState!.validate()) return;

    final invoice = InsuranceInvoice(
      id: widget.invoice?.id,
      invoiceNumber: _invoiceNumberController.text.trim(),
      clientName: _clientNameController.text.trim(),
      insuranceCompany: _insuranceCompanyController.text.trim(),
      amount: double.tryParse(_amountController.text.trim()) ?? 0,
      date: _selectedDate ?? DateTime.now(),
      status: _statusController.text.trim(),
    );

    if (widget.invoice == null) {
      await ref.read(insuranceInvoiceListProvider.notifier).addInvoice(invoice);
    } else {
      await ref
          .read(insuranceInvoiceListProvider.notifier)
          .updateInvoice(invoice);
    }

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.invoice != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'تعديل فاتورة تأمين' : 'إضافة فاتورة تأمين'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _invoiceNumberController,
                decoration: const InputDecoration(labelText: 'رقم الفاتورة'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'يرجى إدخال رقم الفاتورة';
                  }
                  return null;
                },
              ),
              TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _clientNameController,
                decoration: const InputDecoration(labelText: 'اسم العميل'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'يرجى إدخال اسم العميل';
                  }
                  return null;
                },
              ),
              TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _insuranceCompanyController,
                decoration: const InputDecoration(labelText: 'شركة التأمين'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'يرجى إدخال اسم شركة التأمين';
                  }
                  return null;
                },
              ),
              TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _amountController,
                decoration: const InputDecoration(labelText: 'المبلغ'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || double.tryParse(value.trim()) == null) {
                    return 'يرجى إدخال مبلغ صالح';
                  }
                  return null;
                },
              ),
              TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _dateController,
                decoration: const InputDecoration(
                  labelText: 'التاريخ',
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                readOnly: true,
                onTap: _selectDate,
              ),
              TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _statusController,
                decoration: const InputDecoration(labelText: 'الحالة'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'يرجى إدخال حالة الفاتورة';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saveInvoice,
                child: Text(isEditing ? 'تحديث' : 'حفظ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
