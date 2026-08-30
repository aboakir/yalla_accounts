// 📁 lib/features/clients/screens/client_edit_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/features/clients/models/client.dart';
import 'package:yalla_accounts/features/clients/providers/client_list_provider.dart';
import 'package:yalla_accounts/features/clients/services/client_service.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class ClientEditScreen extends ConsumerStatefulWidget {
  final Client? client;

  const ClientEditScreen({super.key, this.client});

  @override
  ConsumerState<ClientEditScreen> createState() => _ClientEditScreenState();
}

class _ClientEditScreenState extends ConsumerState<ClientEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _addressController;

  // القيم المعتمدة
  final List<String> _types = const ['أفراد', 'شركة تأمين'];
  late String _type;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.client;
    _nameController = TextEditingController(text: c?.name ?? '');
    _phoneController = TextEditingController(text: c?.phone ?? '');
    _emailController = TextEditingController(text: c?.email ?? '');
    _addressController = TextEditingController(text: c?.address ?? '');
    _type = (c?.type ?? 'أفراد').trim();
    if (!_types.contains(_type)) _type = 'أفراد';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _saveClient() async {
    if (!_formKey.currentState!.validate()) return;

    final newClient = Client(
      id: widget.client?.id,
      name: _nameController.text.trim(),
      type: _type, // لا نتركه فارغ
      phone: _phoneController.text.trim(),
      email: _emailController.text.trim(),
      address: _addressController.text.trim(),
    );

    final isEditing = widget.client != null;
    final nameChanged = widget.client?.name != newClient.name;
    final typeChanged = widget.client?.type != newClient.type;

    setState(() => _saving = true);
    try {
      // منع التكرار (اسم + نوع) إذا تغيّر أي منهما أو إضافة جديدة
      if (!isEditing || nameChanged || typeChanged) {
        final exists = await ClientService.clientExists(newClient.name,
            type: newClient.type);
        if (exists) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❗ يوجد عميل بنفس الاسم والنوع')),
          );
          return;
        }
      }

      if (isEditing) {
        await ref.read(clientListProvider.notifier).updateClient(newClient);
      } else {
        await ref.read(clientListProvider.notifier).addClient(newClient);
      }

      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.client != null;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          title: Text(isEditing ? 'تعديل عميل' : 'إضافة عميل جديد'),
        ),
        body: AbsorbPointer(
          absorbing: _saving,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    children: [
                      // النوع
                      DropdownButtonFormField<String>(
                        value: _type,
                        items: _types
                            .map((t) =>
                                DropdownMenuItem(value: t, child: Text(t)))
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _type = v);
                        },
                        decoration: const InputDecoration(
                          labelText: 'نوع العميل',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // الاسم
                      TextFormField(
                        controller: _nameController,
                        textAlign: TextAlign.right,
                        decoration: const InputDecoration(
                          labelText: 'اسم العميل',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'يرجى إدخال اسم العميل';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // الهاتف (اختياري)
                      TextFormField(
                        controller: _phoneController,
                        textAlign: TextAlign.right,
                        decoration: const InputDecoration(
                          labelText: 'الهاتف (اختياري)',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 12),

                      // البريد (اختياري)
                      TextFormField(
                        controller: _emailController,
                        textAlign: TextAlign.right,
                        decoration: const InputDecoration(
                          labelText: 'البريد الإلكتروني (اختياري)',
                          border: OutlineInputBorder(),
                        ),
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

                      // العنوان (اختياري)
                      TextFormField(
                        controller: _addressController,
                        textAlign: TextAlign.right,
                        decoration: const InputDecoration(
                          labelText: 'العنوان (اختياري)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 20),

                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _saveClient,
                          child: Text(isEditing ? 'حفظ التعديلات' : 'حفظ'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_saving)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0x33000000),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
