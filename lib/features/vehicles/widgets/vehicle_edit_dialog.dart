import 'package:yalla_accounts/core/utils/user_facing_error.dart';
import 'package:flutter/material.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/clients/models/client.dart';
import 'package:yalla_accounts/features/clients/services/client_service.dart';
import 'package:yalla_accounts/features/vehicles/models/vehicle.dart';
import 'package:yalla_accounts/features/vehicles/services/vehicle_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class VehicleEditDialog extends StatefulWidget {
  const VehicleEditDialog({
    super.key,
    this.vehicle,
  });

  final Vehicle? vehicle;

  @override
  State<VehicleEditDialog> createState() => _VehicleEditDialogState();
}

class _VehicleEditDialogState extends State<VehicleEditDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _numberController;
  late final TextEditingController _typeController;
  late final TextEditingController _modelController;
  late final TextEditingController _notesController;

  List<Client> _clients = const [];
  int _selectedClientId = 0;
  bool _loadingClients = true;
  bool _saving = false;

  bool get _numberLocked =>
      widget.vehicle != null && widget.vehicle!.repairCount > 0;

  @override
  void initState() {
    super.initState();
    final vehicle = widget.vehicle;
    _numberController = TextEditingController(text: vehicle?.number ?? '');
    _typeController = TextEditingController(text: vehicle?.type ?? '');
    _modelController = TextEditingController(text: vehicle?.model ?? '');
    _notesController = TextEditingController(text: vehicle?.notes ?? '');
    _selectedClientId = vehicle?.clientId ?? 0;
    _loadClients();
  }

  Future<void> _loadClients() async {
    final clients = await ClientService.getAllClients();
    if (!mounted) return;
    setState(() {
      _clients = clients;
      _loadingClients = false;
    });
  }

  @override
  void dispose() {
    _numberController.dispose();
    _typeController.dispose();
    _modelController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;

    setState(() => _saving = true);
    try {
      final value = Vehicle(
        id: widget.vehicle?.id,
        number: _numberController.text.trim(),
        type: _typeController.text.trim(),
        model: _modelController.text.trim(),
        clientId: _selectedClientId == 0 ? null : _selectedClientId,
        notes: _notesController.text.trim(),
        repairCount: widget.vehicle?.repairCount ?? 0,
      );

      if (widget.vehicle == null) {
        await VehicleService.insertVehicle(value);
      } else {
        await VehicleService.updateVehicle(value);
      }

      if (mounted) Navigator.pop(context, true);
    } on DuplicateVehicleException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(UserFacingError.message(error))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _dec(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AdaptiveAlertDialog(
        title: Text(
          widget.vehicle == null ? 'إضافة مركبة' : 'تعديل المركبة',
        ),
        content: SizedBox(
          width: 480,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    inputFormatters: const [YallaDigitNormalizer()],
                    controller: _numberController,
                    enabled: !_numberLocked,
                    textAlign: TextAlign.right,
                    decoration: _dec(
                      _numberLocked
                          ? 'رقم المركبة — مثبت لوجود سجل إصلاح'
                          : 'رقم المركبة',
                    ),
                    validator: (value) {
                      final v = value?.trim() ?? '';
                      if (v.isEmpty) return 'رقم المركبة مطلوب';
                      if (v.length < 3) return 'رقم المركبة قصير جدًا';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    inputFormatters: const [YallaDigitNormalizer()],
                    controller: _typeController,
                    textAlign: TextAlign.right,
                    decoration: _dec('نوع المركبة'),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'نوع المركبة مطلوب';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    inputFormatters: const [YallaDigitNormalizer()],
                    controller: _modelController,
                    textAlign: TextAlign.right,
                    decoration: _dec('الموديل / السنة'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: _selectedClientId,
                    decoration: _dec('المالك / العميل'),
                    items: [
                      const DropdownMenuItem<int>(
                        value: 0,
                        child: Text('بدون عميل مرتبط'),
                      ),
                      ..._clients.where((client) => client.id != null).map(
                            (client) => DropdownMenuItem<int>(
                              value: client.id!,
                              child: Text(client.name),
                            ),
                          ),
                    ],
                    onChanged: _loadingClients
                        ? null
                        : (value) {
                            setState(() {
                              _selectedClientId = value ?? 0;
                            });
                          },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    inputFormatters: const [YallaDigitNormalizer()],
                    controller: _notesController,
                    minLines: 2,
                    maxLines: 5,
                    textAlign: TextAlign.right,
                    decoration: _dec('ملاحظات (اختياري)'),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ'),
          ),
        ],
      ),
    );
  }
}
