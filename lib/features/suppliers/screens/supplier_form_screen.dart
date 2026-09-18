// -----------------------------------------------------------------------------
// 📁 lib/features/suppliers/screens/supplier_form_screen.dart
// شاشة إضافة / تعديل مورد — النسخة النهائية المتوافقة مع Yallah Accounts
// -----------------------------------------------------------------------------
import 'package:uuid/uuid.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/supplier.dart';
import '../services/supplier_service.dart';
import '../providers/supplier_provider.dart';
import '../../../core/constants/colors.dart';
import '../../../shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class SupplierFormScreen extends ConsumerStatefulWidget {
  final Supplier? supplier;

  const SupplierFormScreen({super.key, this.supplier});

  @override
  ConsumerState<SupplierFormScreen> createState() => _SupplierFormScreenState();
}

class _SupplierFormScreenState extends ConsumerState<SupplierFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _addressCtrl;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.supplier?.name ?? '');
    _phoneCtrl = TextEditingController(text: widget.supplier?.phone ?? '');
    _addressCtrl = TextEditingController(text: widget.supplier?.address ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      if (widget.supplier == null) {
        // إضافة مورد جديد
        await ref.read(suppliersNotifierProvider.notifier).addSupplier(
              Supplier(
                id: '',
                pid: const Uuid().v4(),
                name: _nameCtrl.text.trim(),
                phone: _phoneCtrl.text.trim(),
                address: _addressCtrl.text.trim(),
              ),
            );
      } else {
        // تعديل مورد
        await ref.read(suppliersNotifierProvider.notifier).updateSupplier(
              widget.supplier!.copyWith(
                name: _nameCtrl.text.trim(),
                phone: _phoneCtrl.text.trim(),
                address: _addressCtrl.text.trim(),
              ),
            );
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      final message = error is DuplicateSupplierException
          ? error.toString()
          : 'تعذر حفظ المورد: $error';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.supplier != null;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          title: Text(
            isEdit ? "تعديل المورد" : "إضافة مورد جديد",
            style: const TextStyle(color: Colors.white),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                context.isPhoneWidth ? 14 : 20,
                16,
                context.isPhoneWidth ? 14 : 20,
                24 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    // الاسم
                    TextFormField(
                      inputFormatters: const [YallaDigitNormalizer()],
                      controller: _nameCtrl,
                      textDirection: TextDirection.rtl,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      decoration: const InputDecoration(
                        labelText: "اسم المورد",
                        prefixIcon: Icon(Icons.storefront_outlined),
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? "الاسم مطلوب" : null,
                    ),
                    const SizedBox(height: 20),

                    // الهاتف
                    TextFormField(
                      inputFormatters: const [YallaDigitNormalizer()],
                      controller: _phoneCtrl,
                      textDirection: TextDirection.rtl,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      decoration: const InputDecoration(
                        labelText: "رقم الهاتف (اختياري)",
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // العنوان
                    TextFormField(
                      inputFormatters: const [YallaDigitNormalizer()],
                      controller: _addressCtrl,
                      textDirection: TextDirection.rtl,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.streetAddressLine1],
                      onFieldSubmitted: (_) {
                        if (!_saving) _save();
                      },
                      decoration: const InputDecoration(
                        labelText: "العنوان (اختياري)",
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                    ),
                    const SizedBox(height: 30),

                    // زر حفظ
                    SafeArea(
                      top: false,
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                          ),
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : Text(
                                  isEdit ? "حفظ التعديلات" : "إضافة المورد",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
