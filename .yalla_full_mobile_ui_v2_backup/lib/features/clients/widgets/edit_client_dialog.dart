import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/constants/insurance_companies.dart';
import 'package:yalla_accounts/features/clients/models/client.dart';
import 'package:yalla_accounts/features/clients/services/client_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class EditClientDialog extends StatefulWidget {
  final Client client;

  const EditClientDialog({super.key, required this.client});

  @override
  State<EditClientDialog> createState() => _EditClientDialogState();
}

class _EditClientDialogState extends State<EditClientDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController; // لاسم الأفراد
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _addressController;
  late TextEditingController _notesController;

  // النوع في الواجهة (عربي فقط)
  static const List<String> _typesUi = ['أفراد', 'شركة تأمين'];
  late String _clientTypeUi; // قيمة من _typesUi دومًا

  // للشركات فقط
  String? _selectedInsuranceCompany;

  @override
  void initState() {
    super.initState();

    _clientTypeUi = _normalizeUiType(widget.client.type);

    _nameController = TextEditingController(
      text: widget.client.isIndividual ? widget.client.name : '',
    );
    _phoneController = TextEditingController(text: widget.client.phone);
    _emailController = TextEditingController(text: widget.client.email);
    _addressController = TextEditingController(text: widget.client.address);
    _notesController = TextEditingController(text: widget.client.notes);

    if (_clientTypeUi == 'شركة تأمين') {
      // إن كان اسم شركة التأمين موجودًا ضمن القائمة نعتمده كبداية
      _selectedInsuranceCompany =
          insuranceCompanies.contains(widget.client.name)
              ? widget.client.name
              : null;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // نحافظ على العربي فقط
  String _normalizeUiType(String v) {
    final s = v.trim().toLowerCase();
    if (s == 'شركة تأمين' || s == 'تأمين' || s == 'insurance') {
      return 'شركة تأمين';
    }
    return 'أفراد'; // يشمل individual وأي قيم قديمة
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // الاسم بحسب النوع
    final String finalName = _clientTypeUi == 'شركة تأمين'
        ? (_selectedInsuranceCompany ?? '').trim()
        : _nameController.text.trim();

    // نبني الكائن المحدث — النوع عربي فقط
    final updated = Client(
      id: widget.client.id,
      name: finalName,
      type: _clientTypeUi, // عربي: 'أفراد' | 'شركة تأمين'
      phone: _phoneController.text.trim(),
      email: _emailController.text.trim(),
      address: _addressController.text.trim(),
      notes: _notesController.text.trim(),
    );

    // منع التكرار في حال تغير الاسم أو النوع (اختياري – خفيف)
    final changedName = updated.name != widget.client.name;
    final changedType = updated.type != _normalizeUiType(widget.client.type);
    if (changedName || changedType) {
      final exists =
          await ClientService.clientExists(updated.name, type: updated.type);
      if (exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❗ يوجد عميل بنفس الاسم والنوع')),
        );
        return;
      }
    }

    await ClientService.updateClient(updated);
    if (mounted) Navigator.pop(context, true);
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.primary),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AdaptiveAlertDialog(
        title: const Text('تعديل بيانات العميل'),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // نوع العميل (عربي فقط)
                DropdownButtonFormField<String>(
                  value: _clientTypeUi,
                  decoration: _inputDecoration('نوع العميل'),
                  items: _typesUi
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() {
                      _clientTypeUi = val;
                      if (_clientTypeUi == 'شركة تأمين') {
                        _selectedInsuranceCompany =
                            insuranceCompanies.contains(widget.client.name)
                                ? widget.client.name
                                : null;
                      } else {
                        _nameController.text = widget.client.name;
                        _selectedInsuranceCompany = null;
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),

                // إذا شركة تأمين → قائمة الشركات
                if (_clientTypeUi == 'شركة تأمين')
                  DropdownButtonFormField<String>(
                    value: _selectedInsuranceCompany,
                    isExpanded: true,
                    decoration: _inputDecoration('اسم شركة التأمين'),
                    items: insuranceCompanies
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (val) => setState(() {
                      _selectedInsuranceCompany = val;
                    }),
                    validator: (val) => val == null || val.isEmpty
                        ? 'يرجى اختيار الشركة'
                        : null,
                  ),

                // إذا أفراد → حقل اسم العميل
                if (_clientTypeUi == 'أفراد') ...[
                  TextFormField(
                    controller: _nameController,
                    textAlign: TextAlign.right,
                    decoration: _inputDecoration('اسم العميل'),
                    validator: (val) => val == null || val.trim().isEmpty
                        ? 'الاسم مطلوب'
                        : null,
                  ),
                ],

                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  textAlign: TextAlign.right,
                  decoration: _inputDecoration('رقم الهاتف (اختياري)'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  textAlign: TextAlign.right,
                  decoration: _inputDecoration('البريد الإلكتروني (اختياري)'),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    final v = value?.trim() ?? '';
                    if (v.isEmpty) return null;
                    final ok = RegExp(r'^\S+@\S+\.\S+$').hasMatch(v);
                    if (!ok) return 'يرجى إدخال بريد إلكتروني صالح';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  textAlign: TextAlign.right,
                  decoration: _inputDecoration('العنوان (اختياري)'),
                ),
                const SizedBox(height: 12),

                // 🆕 الملاحظات
                TextFormField(
                  controller: _notesController,
                  textAlign: TextAlign.right,
                  minLines: 2,
                  maxLines: 4,
                  decoration: _inputDecoration('ملاحظات (اختياري)'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: _save,
            child: const Text('حفظ التعديل'),
          ),
        ],
      ),
    );
  }
}
