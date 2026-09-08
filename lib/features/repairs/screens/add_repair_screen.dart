import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/services/db/tables/vehicle_tables.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/storage/yalla_storage_service.dart';
import 'package:yalla_accounts/core/storage/yalla_stored_image.dart';
import 'package:yalla_accounts/features/clients/services/client_service.dart';
import 'package:yalla_accounts/features/repairs/models/repair_intake_draft.dart';
import 'package:yalla_accounts/features/repairs/services/repair_intake_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_auto_accounting_service.dart';
import 'package:yalla_accounts/features/vehicles/services/vehicle_service.dart';

import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/core/utils/yalla_digits.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

/// P07 — fast repair intake wizard.
///
/// This screen intentionally stops at documented intake. Estimate, approval,
/// work lines and accounting are later phases and do not belong here.
class AddRepairScreen extends StatefulWidget {
  const AddRepairScreen({super.key});

  @override
  State<AddRepairScreen> createState() => _AddRepairScreenState();
}

class _AddRepairScreenState extends State<AddRepairScreen> {
  static const _stepTitles = <String>[
    'العميل',
    'المركبة',
    'نوع الملف',
    'الاستلام',
    'الأضرار',
    'التوثيق',
    'المراجعة',
  ];

  final _picker = ImagePicker();
  final _clientSearchController = TextEditingController();
  final _vehicleSearchController = TextEditingController();
  final _odometerController = TextEditingController();
  final _intakeNotesController = TextEditingController();
  final _damageController = TextEditingController();
  final _insuranceCompanyController = TextEditingController();
  final _claimNumberController = TextEditingController();
  final _worksTotalController = TextEditingController();
  final _partsTotalController = TextEditingController();
  final _signatureKey = GlobalKey<_SignaturePadState>();
  final List<_RepairLineDraft> _works = <_RepairLineDraft>[];
  final List<_RepairLineDraft> _parts = <_RepairLineDraft>[];

  int _step = 0;
  bool _busy = false;
  bool _loadingClients = true;
  bool _loadingVehicles = false;

  List<_ClientChoice> _clients = const <_ClientChoice>[];
  List<_VehicleChoice> _vehicles = const <_VehicleChoice>[];
  _ClientChoice? _client;
  _VehicleChoice? _vehicle;

  DateTime _receivedDate = DateTime.now();
  int _fuelLevel = 50;
  bool? _hasPreviousDamage;
  final List<String> _photoPaths = <String>[];
  String _repairScope = 'إصلاح فقط';
  String _worksPricingMode = 'detailed';
  String _partsPricingMode = 'detailed';
  String _partsSupplySource = 'الورشة';
  String _payer = 'العميل';
  String _consentMethod = 'بدون توثيق';
  String? _savedSignaturePath;

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  @override
  void dispose() {
    _clientSearchController.dispose();
    _vehicleSearchController.dispose();
    _odometerController.dispose();
    _intakeNotesController.dispose();
    _damageController.dispose();
    _insuranceCompanyController.dispose();
    _claimNumberController.dispose();
    _worksTotalController.dispose();
    _partsTotalController.dispose();
    super.dispose();
  }

  int? _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  Future<void> _loadClients({int? selectId}) async {
    setState(() => _loadingClients = true);
    try {
      final db = await DBService.database;
      final rows = await db.query(
        'clients',
        columns: const <String>['id', 'name', 'type'],
        orderBy: 'LOWER(name) ASC',
      );
      final items = rows
          .map(
            (row) => _ClientChoice(
              id: _asInt(row['id']) ?? 0,
              name: (row['name'] ?? '').toString().trim(),
              type: (row['type'] ?? 'أفراد').toString().trim(),
            ),
          )
          .where((item) => item.id > 0 && item.name.isNotEmpty)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _clients = items;
        _loadingClients = false;
        if (selectId != null) {
          for (final item in items) {
            if (item.id == selectId) {
              _client = item;
              break;
            }
          }
        }
      });
      if (selectId != null && _client != null) {
        await _loadVehicles();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingClients = false);
      _showError('تعذر تحميل العملاء', error);
    }
  }

  Future<void> _loadVehicles({int? selectId}) async {
    final client = _client;
    if (client == null) {
      setState(() => _vehicles = const <_VehicleChoice>[]);
      return;
    }
    setState(() => _loadingVehicles = true);
    try {
      final db = await DBService.database;
      final rows = await db.query(
        VehicleTables.tableName,
        columns: const <String>['id', 'number', 'type', 'model', 'client_id'],
        where: 'client_id = ?',
        whereArgs: <Object?>[client.id],
        orderBy: 'LOWER(number) ASC',
      );
      final items = rows
          .map(
            (row) => _VehicleChoice(
              id: _asInt(row['id']) ?? 0,
              number: (row['number'] ?? '').toString().trim(),
              type: (row['type'] ?? '').toString().trim(),
              model: (row['model'] ?? '').toString().trim(),
            ),
          )
          .where((item) => item.id > 0 && item.number.isNotEmpty)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _vehicles = items;
        _loadingVehicles = false;
        if (selectId != null) {
          for (final item in items) {
            if (item.id == selectId) {
              _vehicle = item;
              break;
            }
          }
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingVehicles = false);
      _showError('تعذر تحميل مركبات العميل', error);
    }
  }

  Future<void> _addClient() async {
    final nameController = TextEditingController();
    var type = 'أفراد';
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AdaptiveAlertDialog(
          title: const Text('إضافة عميل سريع'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  inputFormatters: const [YallaDigitNormalizer()],
                  controller: nameController,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'اسم العميل *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(
                    labelText: 'نوع العميل',
                    border: OutlineInputBorder(),
                  ),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem(value: 'أفراد', child: Text('أفراد')),
                    DropdownMenuItem(
                      value: 'شركة تأمين',
                      child: Text('شركة تأمين'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => type = value);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(
                  dialogContext,
                  <String, String>{'name': name, 'type': type},
                );
              },
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    if (result == null) return;

    try {
      final id = await ClientService.insertOrGetClientId(
        result['name']!,
        result['type']!,
      );
      if (!mounted) return;
      await _loadClients(selectId: id);
    } catch (error) {
      if (!mounted) return;
      _showError('تعذر إضافة العميل', error);
    }
  }

  Future<void> _addVehicle() async {
    final client = _client;
    if (client == null) return;

    final numberController = TextEditingController();
    final typeController = TextEditingController();
    final modelController = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => AdaptiveAlertDialog(
        title: const Text('إضافة مركبة سريعة'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: numberController,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'رقم المركبة *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: typeController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'نوع المركبة',
                  hintText: 'مثال: توسان',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: modelController,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'الموديل / السنة',
                  hintText: 'مثال: 2022',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final number = numberController.text.trim();
              if (number.isEmpty) return;
              Navigator.pop(
                dialogContext,
                <String, String>{
                  'number': number,
                  'type': typeController.text.trim(),
                  'model': modelController.text.trim(),
                },
              );
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
    numberController.dispose();
    typeController.dispose();
    modelController.dispose();
    if (result == null) return;

    try {
      final db = await DBService.database;
      final normalized = VehicleTables.normalizeNumber(result['number']!);
      final existing = await db.query(
        VehicleTables.tableName,
        columns: const <String>['id', 'client_id'],
        where: 'normalized_number = ?',
        whereArgs: <Object?>[normalized],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        final existingId = _asInt(existing.first['id']);
        final existingClientId = _asInt(existing.first['client_id']);
        if (existingClientId != null && existingClientId != client.id) {
          throw StateError('هذه المركبة مسجلة لعميل آخر. راجع ملكيتها أولًا.');
        }
        if (!mounted) return;
        await _loadVehicles(selectId: existingId);
        return;
      }

      final id = await DBService.inTx<int>(
        (txn) => VehicleService.upsertFromRepairOn(
          txn,
          number: result['number']!,
          type: result['type']!,
          model: result['model']!,
          clientId: client.id,
        ),
      );
      if (!mounted) return;
      await _loadVehicles(selectId: id);
    } catch (error) {
      if (!mounted) return;
      _showError('تعذر إضافة المركبة', error);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_photoPaths.length >= 8) {
      _showMessage('الحد الأقصى في الاستلام السريع هو 8 صور.');
      return;
    }
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 2400,
      );
      if (picked == null) return;
      final persisted = await _persistPickedImage(picked.path);
      if (!mounted) return;
      setState(() => _photoPaths.add(persisted));
    } catch (error) {
      if (!mounted) return;
      _showError('تعذر إضافة الصورة', error);
    }
  }

  Future<String> _persistPickedImage(String sourcePath) async {
    final vehicle = _vehicle;
    final client = _client;
    return YallaStorageService.saveImageFromPath(
      sourcePath: sourcePath,
      module: 'repairs',
      vehicleType: vehicle?.type ?? 'vehicle',
      vehicleNumber: vehicle?.number ?? 'no_number',
      beneficiaryName: client?.name ?? 'client',
      date: _receivedDate,
    );
  }

  Future<void> _selectReceivedDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _receivedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (selected == null || !mounted) return;
    final now = DateTime.now();
    setState(() {
      _receivedDate = DateTime(
        selected.year,
        selected.month,
        selected.day,
        now.hour,
        now.minute,
      );
    });
  }

  String _dateLabel(DateTime date) => '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  bool _validateCurrentStep({bool announce = true}) {
    String? error;
    switch (_step) {
      case 0:
        if (_client == null) error = 'اختر العميل أو أضف عميلًا جديدًا.';
        break;
      case 1:
        if (_vehicle == null) error = 'اختر المركبة أو أضف مركبة جديدة.';
        break;
      case 2:
        if (_repairScope.isEmpty) {
          error = 'اختر نوع الملف.';
        } else if (_payer.isEmpty) {
          error = 'اختر جهة الدفع.';
        } else if (_payer != 'العميل' &&
            _insuranceCompanyController.text.trim().isEmpty) {
          error = 'أدخل اسم شركة التأمين حتى تنتقل جهة الدفع مع الملف.';
        } else if ((_repairScope == 'إصلاح فقط' ||
                _repairScope == 'إصلاح + قطع') &&
            _worksPricingMode == 'detailed' &&
            _works.isEmpty) {
          error = 'أضف عمل إصلاح واحدًا على الأقل، أو اختر إدخال إجمالي القسم.';
        } else if ((_repairScope == 'إصلاح فقط' ||
                _repairScope == 'إصلاح + قطع') &&
            _worksPricingMode == 'total' &&
            _parseMoney(_worksTotalController.text) <= 0) {
          error = 'أدخل إجمالي أعمال الإصلاح.';
        } else if ((_repairScope == 'قطع فقط' ||
                _repairScope == 'إصلاح + قطع') &&
            _partsPricingMode == 'detailed' &&
            _parts.isEmpty) {
          error =
              'أضف قطعة واحدة على الأقل، أو اختر إجمالي القسم / كشف بدون أسعار.';
        } else if ((_repairScope == 'قطع فقط' ||
                _repairScope == 'إصلاح + قطع') &&
            _partsPricingMode == 'total' &&
            _parseMoney(_partsTotalController.text) <= 0) {
          error = 'أدخل إجمالي قيمة القطع.';
        } else if ((_repairScope == 'قطع فقط' ||
                _repairScope == 'إصلاح + قطع') &&
            _partsPricingMode == 'list' &&
            _parts.isEmpty) {
          error = 'أضف قطعة واحدة على الأقل إلى الكشف.';
        }
        break;
      case 3:
        final odometer = int.tryParse(_odometerController.text.trim());
        if (odometer == null || odometer < 0) {
          error = 'أدخل قراءة عداد صحيحة.';
        }
        break;
      case 4:
        if (_hasPreviousDamage == null) {
          error = 'حدد هل توجد أضرار سابقة.';
        } else if (_hasPreviousDamage == true &&
            _damageController.text.trim().isEmpty) {
          error = 'صف الأضرار السابقة باختصار.';
        }
        break;
      case 5:
        // التوثيق اختياري: لا تمنع المراجعة بسبب الصور أو توقيع العميل.
        break;
    }
    if (error != null && announce) _showMessage(error);
    return error == null;
  }

  Future<void> _next() async {
    if (!_validateCurrentStep()) return;
    FocusScope.of(context).unfocus();

    if (_step == 5 && _consentMethod == 'توقيع على الشاشة') {
      final signatureState = _signatureKey.currentState;
      if (signatureState?.hasInk ?? false) {
        _savedSignaturePath = await signatureState!.exportPng();
      }
    }

    if (!mounted) return;
    if (_step < _stepTitles.length - 1) {
      setState(() => _step++);
    }
  }

  void _back() {
    FocusScope.of(context).unfocus();
    if (_step > 0) {
      setState(() => _step--);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _save() async {
    final client = _client;
    final vehicle = _vehicle;
    if (client == null || vehicle == null) {
      _showMessage('بيانات العميل أو المركبة غير مكتملة.');
      return;
    }
    final odometer = int.tryParse(_odometerController.text.trim());
    if (odometer == null || odometer < 0) {
      _showMessage('قراءة العداد غير صحيحة.');
      return;
    }
    setState(() => _busy = true);
    try {
      final signaturePath = _savedSignaturePath ?? '';
      final consentNote = _consentMethod == 'بدون توثيق'
          ? 'توثيق موافقة العميل: غير موثق (اختياري)'
          : 'توثيق موافقة العميل: $_consentMethod';
      final manualNotes = _intakeNotesController.text.trim();
      final insuranceCompany = _insuranceCompanyController.text.trim();
      final claimNumber = _claimNumberController.text.trim();
      final persistedNotes = <String>[
        '[YALLA_SCOPE] $_repairScope',
        '[YALLA_PAYER] $_payer',
        '[YALLA_WORKS_PRICING] $_worksPricingMode',
        '[YALLA_PARTS_PRICING] $_partsPricingMode',
        '[YALLA_PARTS_SUPPLY] $_partsSupplySource',
        if (_worksPricingMode == 'total')
          '[YALLA_WORKS_TOTAL] ${_sectionTotal(isPart: false)}',
        if (_partsPricingMode == 'total')
          '[YALLA_PARTS_TOTAL] ${_sectionTotal(isPart: true)}',
        if (_works.isNotEmpty)
          'أعمال الإصلاح: ${_linesNote(_works, isPart: false)}',
        if (_parts.isNotEmpty)
          'القطع المطلوبة: ${_linesNote(_parts, isPart: true)}',
        if (_payer != 'العميل' && insuranceCompany.isNotEmpty)
          'شركة التأمين: $insuranceCompany',
        if (_payer != 'العميل' && claimNumber.isNotEmpty)
          'رقم المطالبة: $claimNumber',
        if (manualNotes.isNotEmpty) manualNotes,
        consentNote,
      ].join('\n');
      final previousDamage = _hasPreviousDamage == true
          ? _damageController.text.trim()
          : 'لا يوجد ضرر سابق حسب إفادة العميل';
      final draft = RepairIntakeDraft(
        clientId: client.id,
        clientName: client.name,
        clientType: client.type,
        vehicleNumber: vehicle.number,
        vehicleType: vehicle.type,
        vehicleModel: vehicle.model,
        receivedDate: _receivedDate,
        odometer: odometer,
        fuelLevel: _fuelLevel,
        previousDamage: previousDamage,
        photoPaths: List<String>.unmodifiable(_photoPaths),
        customerSignaturePath: signaturePath,
        notes: persistedNotes,
      );
      final repairId = await DBService.inTx<String>((txn) async {
        final id = await RepairIntakeService.saveOn(txn, draft);
        await _persistRepairLinesOn(txn, id);
        await RepairAutoAccountingService.finalizeNewRepairOn(txn, id);
        return id;
      });
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ واعتماد ملف الإصلاح تلقائيًا.')),
      );
      Navigator.of(context).pop(repairId);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showError('تعذر حفظ ملف الاستلام', error);
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _showError(String title, Object error) {
    final message = error.toString().replaceFirst('StateError: ', '');
    showDialog<void>(
      context: context,
      builder: (context) => AdaptiveAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسنًا'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final phone = width < 600;

    final yallaTheme = baseTheme.copyWith(
      scaffoldBackgroundColor: AppColors.scaffoldBg,
      colorScheme: baseTheme.colorScheme.copyWith(
        primary: AppColors.primary,
        secondary: AppColors.primary,
        surface: Colors.white,
      ),
      inputDecorationTheme: baseTheme.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: AppColors.inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.lightGrey),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
        ),
      ),
    );

    return Theme(
      data: yallaTheme,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: AppColors.scaffoldBg,
          appBar: AppBar(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            surfaceTintColor: AppColors.primary,
            elevation: 0,
            title: const Text(
              'فتح ملف إصلاح جديد',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            centerTitle: phone,
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Column(
                  children: <Widget>[
                    _ProgressHeader(
                      step: _step,
                      titles: _stepTitles,
                      compact: phone,
                    ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: KeyedSubtree(
                          key: ValueKey<int>(_step),
                          child: _buildStep(yallaTheme, phone),
                        ),
                      ),
                    ),
                    _buildFooter(phone),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(bool phone) {
    final last = _step == _stepTitles.length - 1;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.lightGrey)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding:
              EdgeInsets.fromLTRB(phone ? 16 : 24, 12, phone ? 16 : 24, 12),
          child: Row(
            children: <Widget>[
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  minimumSize: Size(phone ? 108.0 : 132.0, 46),
                ),
                onPressed: _busy ? null : _back,
                icon: const Icon(Icons.arrow_forward),
                label: Text(_step == 0 ? 'إلغاء' : 'السابق'),
              ),
              const Spacer(),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: Size(phone ? 118.0 : 148.0, 46),
                ),
                onPressed: _busy ? null : (last ? _save : _next),
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        last ? Icons.check_circle_outline : Icons.arrow_back),
                label: Text(last ? 'فتح الملف' : 'التالي'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(ThemeData theme, bool phone) {
    switch (_step) {
      case 0:
        return _clientStep(theme);
      case 1:
        return _vehicleStep(theme);
      case 2:
        return _scopeStep(theme);
      case 3:
        return _receptionStep(theme);
      case 4:
        return _damageStep(theme);
      case 5:
        return _documentationStep(theme, phone);
      case 6:
        return _reviewStep(theme);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _stepContainer({required Widget child}) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.lightGrey),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.035),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ],
    );
  }

  Widget _clientStep(ThemeData theme) {
    final query = _clientSearchController.text.trim().toLowerCase();
    final visible = _clients.where((item) {
      if (query.isEmpty) return true;
      return item.name.toLowerCase().contains(query) ||
          item.type.toLowerCase().contains(query);
    }).toList(growable: false);

    return _stepContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _stepIntro(
            icon: Icons.person_search_outlined,
            title: 'من هو صاحب المركبة؟',
            subtitle: 'اختر عميلًا موجودًا أو أضفه خلال ثوانٍ.',
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  inputFormatters: const [YallaDigitNormalizer()],
                  controller: _clientSearchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'ابحث باسم العميل',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _addClient,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('عميل جديد'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_loadingClients)
            const Center(child: CircularProgressIndicator())
          else if (visible.isEmpty)
            _emptyCard('لا يوجد عميل مطابق. أضف العميل من الزر أعلاه.')
          else
            ...visible.map(
              (item) => _SelectionCard(
                selected: _client?.id == item.id,
                title: item.name,
                subtitle: item.type.isEmpty ? 'عميل' : item.type,
                icon: Icons.person_outline,
                onTap: () async {
                  setState(() {
                    _client = item;
                    _vehicle = null;
                    _vehicleSearchController.clear();
                  });
                  await _loadVehicles();
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _vehicleStep(ThemeData theme) {
    final client = _client;
    final query = _vehicleSearchController.text.trim().toLowerCase();
    final visible = _vehicles.where((item) {
      if (query.isEmpty) return true;
      return item.number.toLowerCase().contains(query) ||
          item.type.toLowerCase().contains(query) ||
          item.model.toLowerCase().contains(query);
    }).toList(growable: false);

    return _stepContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _stepIntro(
            icon: Icons.directions_car_filled_outlined,
            title: 'أي مركبة سنستلم؟',
            subtitle: client == null
                ? 'اختر العميل أولًا.'
                : 'مركبات ${client.name} فقط، لمنع ربط الملف بالشخص الخطأ.',
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  inputFormatters: const [YallaDigitNormalizer()],
                  controller: _vehicleSearchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'ابحث بالرقم أو النوع أو الموديل',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: client == null ? null : _addVehicle,
                icon: const Icon(Icons.add_road),
                label: const Text('مركبة جديدة'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_loadingVehicles)
            const Center(child: CircularProgressIndicator())
          else if (visible.isEmpty)
            _emptyCard('لا توجد مركبات لهذا العميل بعد. أضف المركبة الآن.')
          else
            ...visible.map(
              (item) => _SelectionCard(
                selected: _vehicle?.id == item.id,
                title: item.number,
                subtitle: <String>[item.type, item.model]
                    .where((value) => value.trim().isNotEmpty)
                    .join(' • '),
                icon: Icons.directions_car_outlined,
                onTap: () => setState(() => _vehicle = item),
              ),
            ),
        ],
      ),
    );
  }

  double _parseMoney(String value) {
    final normalized = value
        .replaceAll(',', '')
        .replaceAll('٫', '.')
        .replaceAll('٬', '')
        .trim();
    return double.tryParse(normalized) ?? 0;
  }

  double _linesTotal(List<_RepairLineDraft> lines) =>
      lines.fold<double>(0, (sum, line) => sum + line.total);

  double _sectionTotal({required bool isPart}) {
    final mode = isPart ? _partsPricingMode : _worksPricingMode;
    if (mode == 'total') {
      return _parseMoney(
        isPart ? _partsTotalController.text : _worksTotalController.text,
      );
    }
    if (mode == 'list') return 0;
    return _linesTotal(isPart ? _parts : _works);
  }

  String _pricingModeLabel(String mode) {
    switch (mode) {
      case 'total':
        return 'إجمالي للقسم';
      case 'list':
        return 'كشف بدون أسعار';
      default:
        return 'تسعير تفصيلي';
    }
  }

  String _money(double value) => MoneyFormatter.number(value);

  String get _currencySymbol => MoneyFormatter.symbol;

  String _linesNote(List<_RepairLineDraft> lines, {required bool isPart}) {
    final mode = isPart ? _partsPricingMode : _worksPricingMode;
    if (lines.isEmpty) return '';
    if (mode == 'detailed') {
      return lines
          .map((line) =>
              '${line.name} | ${line.qty} × ${line.price.toStringAsFixed(2)} = ${line.total.toStringAsFixed(2)}')
          .join(' ؛ ');
    }
    return lines.map((line) => '${line.name} | الكمية ${line.qty}').join(' ؛ ');
  }

  String _linesReview(List<_RepairLineDraft> lines, {required bool isPart}) {
    final mode = isPart ? _partsPricingMode : _worksPricingMode;
    if (lines.isEmpty) return 'لا توجد بنود تفصيلية.';
    if (mode == 'detailed') {
      return lines
          .map((line) =>
              '• ${line.name}: ${line.qty} × ${_money(line.price)} = ${_money(line.total)} $_currencySymbol')
          .join('\n');
    }
    return lines
        .map((line) => '• ${line.name} — الكمية ${line.qty}')
        .join('\n');
  }

  Future<void> _openLineEditor({
    required bool isPart,
    int? index,
  }) async {
    final list = isPart ? _parts : _works;
    final mode = isPart ? _partsPricingMode : _worksPricingMode;
    final existing = index == null ? null : list[index];

    final result = await showModalBottomSheet<_RepairLineDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _RepairLineEditorSheet(
        isPart: isPart,
        isEdit: index != null,
        existing: existing,
        mode: mode,
        modeLabel: _pricingModeLabel(mode),
        currencySymbol: _currencySymbol,
        parseMoney: _parseMoney,
        money: _money,
      ),
    );

    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        list.add(result);
      } else {
        list[index] = result;
      }
    });
  }

  Widget _repairLinesSection({
    required ThemeData theme,
    required String title,
    required String addLabel,
    required String emptyText,
    required IconData icon,
    required List<_RepairLineDraft> lines,
    required bool isPart,
  }) {
    final mode = isPart ? _partsPricingMode : _worksPricingMode;
    final total = _sectionTotal(isPart: isPart);
    final totalController =
        isPart ? _partsTotalController : _worksTotalController;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.lightGrey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _openLineEditor(isPart: isPart),
                icon: const Icon(Icons.add_rounded),
                label: Text(addLabel),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'طريقة التسعير',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: <Widget>[
              ChoiceChip(
                label: const Text('تفصيلي'),
                selected: mode == 'detailed',
                onSelected: (_) => setState(() {
                  if (isPart) {
                    _partsPricingMode = 'detailed';
                  } else {
                    _worksPricingMode = 'detailed';
                  }
                }),
              ),
              ChoiceChip(
                label: const Text('إجمالي فقط'),
                selected: mode == 'total',
                onSelected: (_) => setState(() {
                  if (isPart) {
                    _partsPricingMode = 'total';
                  } else {
                    _worksPricingMode = 'total';
                  }
                }),
              ),
              if (isPart)
                ChoiceChip(
                  label: const Text('كشف بدون أسعار'),
                  selected: mode == 'list',
                  onSelected: (_) => setState(() => _partsPricingMode = 'list'),
                ),
            ],
          ),
          if (mode == 'total') ...<Widget>[
            const SizedBox(height: 12),
            TextFormField(
              inputFormatters: const [YallaDigitNormalizer()],
              controller: totalController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText:
                    isPart ? 'إجمالي قيمة القطع *' : 'إجمالي أعمال الإصلاح *',
                suffixText: MoneyFormatter.symbol,
                helperText: 'يمكن إضافة البنود كوصف فقط دون تسعير كل بند.',
              ),
            ),
          ],
          if (isPart) ...<Widget>[
            const SizedBox(height: 12),
            Text('جهة توريد القطع',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                )),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              children:
                  <String>['الورشة', 'العميل', 'شركة التأمين'].map((source) {
                return ChoiceChip(
                  label: Text(source),
                  selected: _partsSupplySource == source,
                  onSelected: (_) =>
                      setState(() => _partsSupplySource = source),
                );
              }).toList(growable: false),
            ),
          ],
          const SizedBox(height: 12),
          if (lines.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.inputFill,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(emptyText,
                  style: const TextStyle(color: Colors.black54)),
            )
          else
            ...lines.asMap().entries.map((entry) {
              final index = entry.key;
              final line = entry.value;
              final priced = mode == 'detailed';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.inputFill,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(line.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Text(
                              priced
                                  ? '${line.qty} × ${_money(line.price)} $_currencySymbol'
                                  : 'الكمية ${line.qty}${mode == 'list' ? ' • بدون سعر' : ''}',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                      if (priced) ...<Widget>[
                        const SizedBox(width: 8),
                        Text('${_money(line.total)} $_currencySymbol',
                            style:
                                const TextStyle(fontWeight: FontWeight.w900)),
                      ],
                      PopupMenuButton<String>(
                        tooltip: 'خيارات',
                        onSelected: (value) {
                          if (value == 'edit') {
                            _openLineEditor(isPart: isPart, index: index);
                          } else if (value == 'delete') {
                            setState(() => lines.removeAt(index));
                          }
                        },
                        itemBuilder: (_) => const <PopupMenuEntry<String>>[
                          PopupMenuItem(value: 'edit', child: Text('تعديل')),
                          PopupMenuItem(value: 'delete', child: Text('حذف')),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  mode == 'list'
                      ? 'كشف قطع مطلوب توريدها — لا يدخل في قيمة الملف'
                      : '${lines.length} بند • ${_pricingModeLabel(mode)}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.black54),
                ),
              ),
              if (mode != 'list')
                Text('${_money(total)} $_currencySymbol',
                    style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
        ],
      ),
    );
  }

  String? _firstColumn(Set<String> columns, List<String> candidates) {
    for (final candidate in candidates) {
      if (columns.contains(candidate)) return candidate;
    }
    return null;
  }

  Future<_RepairLineTypeValues> _resolveRepairLineTypes(
    DatabaseExecutor db,
    String typeColumn,
  ) async {
    String? work;
    String? part;
    try {
      final rows = await db.rawQuery(
        'SELECT DISTINCT "$typeColumn" AS v FROM repair_lines '
        'WHERE "$typeColumn" IS NOT NULL LIMIT 50',
      );
      for (final row in rows) {
        final value = (row['v'] ?? '').toString().trim();
        final lower = value.toLowerCase();
        if (value.isEmpty) continue;
        if (part == null &&
            (lower.contains('part') ||
                value.contains('قطعة') ||
                value.contains('قطع'))) {
          part = value;
        }
        if (work == null &&
            (lower.contains('work') ||
                lower.contains('repair') ||
                lower.contains('service') ||
                lower.contains('labor') ||
                lower.contains('labour') ||
                value.contains('عمل') ||
                value.contains('أعمال') ||
                value.contains('إصلاح') ||
                value.contains('اصلاح'))) {
          work = value;
        }
      }
    } catch (_) {
      // Fallback below keeps the same canonical desktop semantics.
    }
    return _RepairLineTypeValues(
      work: work ?? 'work',
      part: part ?? 'part',
    );
  }

  Future<void> _persistRepairLinesOn(
    DatabaseExecutor txn,
    Object repairId,
  ) async {
    final hasWorksValue = _sectionTotal(isPart: false) > 0;
    final hasPartsValue = _sectionTotal(isPart: true) > 0;
    if (_works.isEmpty && _parts.isEmpty && !hasWorksValue && !hasPartsValue)
      return;
    final info = await txn.rawQuery('PRAGMA table_info(repair_lines)');
    final columns = info
        .map((row) => (row['name'] ?? '').toString())
        .where((name) => name.isNotEmpty)
        .toSet();

    final repairColumn = _firstColumn(columns, const ['repair_id', 'repairId']);
    final typeColumn =
        _firstColumn(columns, const ['type', 'line_type', 'category']);
    final nameColumn =
        _firstColumn(columns, const ['name', 'description', 'item_name']);
    final qtyColumn = _firstColumn(columns, const ['qty', 'quantity']);
    final priceColumn =
        _firstColumn(columns, const ['price', 'unit_price', 'unitPrice']);
    final totalColumn =
        _firstColumn(columns, const ['total', 'line_total', 'amount']);

    if (repairColumn == null ||
        typeColumn == null ||
        nameColumn == null ||
        qtyColumn == null ||
        priceColumn == null ||
        totalColumn == null) {
      throw StateError(
          'تعذر مطابقة جدول أعمال الإصلاح والقطع مع بنية سطح المكتب.');
    }

    final types = await _resolveRepairLineTypes(txn, typeColumn);
    var serial = 0;
    Future<void> insertLine(_RepairLineDraft line, bool isPart) async {
      serial++;
      final row = <String, Object?>{
        repairColumn: repairId,
        typeColumn: isPart ? types.part : types.work,
        nameColumn: line.name,
        qtyColumn: line.qty,
        priceColumn: line.price,
        totalColumn: line.total,
      };
      final idInfo = info.where((column) => column['name']?.toString() == 'id');
      if (idInfo.isNotEmpty) {
        final idType = (idInfo.first['type'] ?? '').toString().toUpperCase();
        final pk = idInfo.first['pk'];
        final isPk = pk == 1 || pk?.toString() == '1';
        if (isPk && !idType.contains('INT')) {
          row['id'] =
              '${repairId}_${DateTime.now().microsecondsSinceEpoch}_$serial';
        }
      }
      final now = DateTime.now().toIso8601String();
      if (columns.contains('created_at')) row['created_at'] = now;
      if (columns.contains('updated_at')) row['updated_at'] = now;
      await txn.insert('repair_lines', row);
    }

    final worksMode = _worksPricingMode;
    final partsMode = _partsPricingMode;

    for (final line in _works) {
      await insertLine(
        _RepairLineDraft(
          name: line.name,
          qty: line.qty,
          price: worksMode == 'detailed' ? line.price : 0,
        ),
        false,
      );
    }
    if (worksMode == 'total' && hasWorksValue) {
      await insertLine(
        _RepairLineDraft(
          name: 'إجمالي أعمال الإصلاح',
          qty: 1,
          price: _sectionTotal(isPart: false),
        ),
        false,
      );
    }

    for (final line in _parts) {
      await insertLine(
        _RepairLineDraft(
          name: line.name,
          qty: line.qty,
          price: partsMode == 'detailed' ? line.price : 0,
        ),
        true,
      );
    }
    if (partsMode == 'total' && hasPartsValue) {
      await insertLine(
        _RepairLineDraft(
          name: 'إجمالي قيمة القطع',
          qty: 1,
          price: _sectionTotal(isPart: true),
        ),
        true,
      );
    }

    // Value promotion and accounting happen in the same outer save transaction.
  }

  Widget _scopeStep(ThemeData theme) {
    final showWorks =
        _repairScope == 'إصلاح فقط' || _repairScope == 'إصلاح + قطع';
    final showParts =
        _repairScope == 'قطع فقط' || _repairScope == 'إصلاح + قطع';

    return _stepContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _stepIntro(
            icon: Icons.build_circle_outlined,
            title: 'ما نوع هذا الملف؟',
            subtitle:
                'حدد نطاق العمل وجهة الدفع، ثم أضف الأعمال أو القطع المطلوبة مبدئيًا.',
          ),
          const SizedBox(height: 18),
          Text('نوع الملف',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <String>[
              'إصلاح فقط',
              'قطع فقط',
              'إصلاح + قطع',
            ].map((option) {
              return ChoiceChip(
                label: Text(option),
                selected: _repairScope == option,
                onSelected: (_) => setState(() => _repairScope = option),
              );
            }).toList(growable: false),
          ),
          const SizedBox(height: 22),
          Text('جهة الدفع',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <String>[
              'العميل',
              'شركة تأمين',
              'مختلط',
            ].map((option) {
              return ChoiceChip(
                label: Text(option),
                selected: _payer == option,
                onSelected: (_) => setState(() {
                  _payer = option;
                  if (option == 'العميل') {
                    _insuranceCompanyController.clear();
                    _claimNumberController.clear();
                  }
                }),
              );
            }).toList(growable: false),
          ),
          if (showWorks) ...<Widget>[
            const SizedBox(height: 22),
            _repairLinesSection(
              theme: theme,
              title: 'كشف أعمال الإصلاح',
              addLabel: 'إضافة عمل',
              emptyText: 'لا توجد أعمال مضافة بعد.',
              icon: Icons.car_repair_outlined,
              lines: _works,
              isPart: false,
            ),
          ],
          if (showParts) ...<Widget>[
            const SizedBox(height: 16),
            _repairLinesSection(
              theme: theme,
              title: 'كشف القطع',
              addLabel: 'إضافة قطعة',
              emptyText: 'لا توجد قطع مضافة بعد.',
              icon: Icons.settings_outlined,
              lines: _parts,
              isPart: true,
            ),
          ],
          if (showWorks || showParts) ...<Widget>[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.lightGreen.withOpacity(.35),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.lightGrey),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.calculate_outlined,
                      color: AppColors.primary),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'إجمالي قيمة الملف',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    '${_money(_sectionTotal(isPart: false) + _sectionTotal(isPart: true))} $_currencySymbol',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_payer != 'العميل') ...<Widget>[
            const SizedBox(height: 22),
            _optionalSection(
              icon: Icons.shield_outlined,
              title: 'بيانات التأمين',
              subtitle: 'تظهر فقط لأن جهة الدفع تشمل شركة تأمين.',
              child: Column(
                children: <Widget>[
                  TextField(
                    inputFormatters: const [YallaDigitNormalizer()],
                    controller: _insuranceCompanyController,
                    decoration: const InputDecoration(
                      labelText: 'شركة التأمين',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    inputFormatters: const [YallaDigitNormalizer()],
                    controller: _claimNumberController,
                    decoration: const InputDecoration(
                      labelText: 'رقم المطالبة (اختياري)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _receptionStep(ThemeData theme) {
    return _stepContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _stepIntro(
            icon: Icons.car_repair_outlined,
            title: 'بيانات الاستلام',
            subtitle: 'ثلاث معلومات سريعة توثق حالة المركبة عند دخولها.',
          ),
          const SizedBox(height: 18),
          InkWell(
            onTap: _selectReceivedDate,
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'تاريخ الاستلام',
                prefixIcon: Icon(Icons.calendar_today_outlined),
                border: OutlineInputBorder(),
              ),
              child: Text(_dateLabel(_receivedDate)),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            inputFormatters: const [YallaDigitNormalizer()],
            controller: _odometerController,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'قراءة العداد *',
              suffixText: 'كم',
              prefixIcon: Icon(Icons.speed_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          Text('مستوى الوقود', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <int>[0, 25, 50, 75, 100]
                .map(
                  (value) => ChoiceChip(
                    selected: _fuelLevel == value,
                    label: Text('$value%'),
                    avatar:
                        const Icon(Icons.local_gas_station_outlined, size: 18),
                    onSelected: (_) => setState(() => _fuelLevel = value),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 18),
          TextField(
            inputFormatters: const [YallaDigitNormalizer()],
            controller: _intakeNotesController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'ملاحظات الاستلام (اختياري)',
              hintText: 'مثال: المفتاح الثاني مع العميل، أغراض في الصندوق...',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _damageStep(ThemeData theme) {
    return _stepContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _stepIntro(
            icon: Icons.gpp_maybe_outlined,
            title: 'الأضرار السابقة',
            subtitle:
                'سجل الموجود قبل بدء العمل حتى لا تختلط المسؤوليات لاحقًا.',
          ),
          const SizedBox(height: 18),
          _BinaryChoice(
            selected: _hasPreviousDamage == false,
            icon: Icons.verified_outlined,
            title: 'لا يوجد ضرر سابق',
            subtitle: 'بحسب فحص الاستلام وإفادة العميل',
            onTap: () => setState(() {
              _hasPreviousDamage = false;
              _damageController.clear();
            }),
          ),
          const SizedBox(height: 10),
          _BinaryChoice(
            selected: _hasPreviousDamage == true,
            icon: Icons.warning_amber_rounded,
            title: 'يوجد ضرر سابق',
            subtitle: 'سأصفه الآن',
            onTap: () => setState(() => _hasPreviousDamage = true),
          ),
          if (_hasPreviousDamage == true) ...<Widget>[
            const SizedBox(height: 14),
            TextField(
              inputFormatters: const [YallaDigitNormalizer()],
              controller: _damageController,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'وصف الأضرار السابقة *',
                hintText: 'مثال: خدش باب يمين، كسر سابق في الصدام الخلفي...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _documentationStep(ThemeData theme, bool phone) {
    const consentOptions = <String>[
      'بدون توثيق',
      'إقرار شفهي حضوري',
      'موافقة هاتفية',
      'موافقة عبر واتساب',
      'توقيع على الشاشة',
    ];

    return _stepContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _stepIntro(
            icon: Icons.fact_check_outlined,
            title: 'توثيق الاستلام',
            subtitle:
                'الصور وموافقة العميل اختيارية. أضف ما يفيد ملف الورشة دون تعطيل فتح الملف.',
          ),
          const SizedBox(height: 20),
          _optionalSection(
            icon: Icons.photo_camera_outlined,
            title: 'صور المركبة',
            subtitle: 'اختياري • حتى 8 صور للحالة عند الاستلام',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    FilledButton.tonalIcon(
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('التقاط صورة'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('من الصور'),
                    ),
                    Text(
                      '${_photoPaths.length}/8 • اختياري',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.black54,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                if (_photoPaths.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 112,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _photoPaths.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final path = _photoPaths[index];
                        return Stack(
                          children: <Widget>[
                            YallaStoredImage(
                              storedPath: path,
                              width: 112,
                              height: 112,
                              fit: BoxFit.cover,
                              borderRadius: BorderRadius.circular(12),
                              fallback: const SizedBox(
                                width: 112,
                                height: 112,
                                child: ColoredBox(
                                  color: Color(0x11000000),
                                  child: Icon(Icons.broken_image_outlined),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 4,
                              left: 4,
                              child: IconButton.filledTonal(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'حذف الصورة',
                                onPressed: () =>
                                    setState(() => _photoPaths.removeAt(index)),
                                icon: const Icon(Icons.close, size: 18),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          _optionalSection(
            icon: Icons.handshake_outlined,
            title: 'توثيق موافقة العميل',
            subtitle:
                'اختياري • اختر الطريقة العملية المتاحة، أو تابع دون توثيق.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: consentOptions.map((option) {
                    final selected = _consentMethod == option;
                    return ChoiceChip(
                      label: Text(option),
                      selected: selected,
                      selectedColor: AppColors.lightGreen,
                      side: BorderSide(
                        color:
                            selected ? AppColors.primary : AppColors.lightGrey,
                      ),
                      onSelected: (_) {
                        setState(() {
                          _consentMethod = option;
                          if (option != 'توقيع على الشاشة') {
                            _savedSignaturePath = null;
                            _signatureKey.currentState?.clear();
                          }
                        });
                      },
                    );
                  }).toList(growable: false),
                ),
                if (_consentMethod == 'توقيع على الشاشة') ...<Widget>[
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'التوقيع على الشاشة — اختياري',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          _signatureKey.currentState?.clear();
                          setState(() => _savedSignaturePath = null);
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('مسح'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _SignaturePad(key: _signatureKey, height: phone ? 170 : 190),
                  const SizedBox(height: 8),
                  Text(
                    _savedSignaturePath == null
                        ? 'يمكن للعميل التوقيع هنا، أو تركه فارغًا والمتابعة.'
                        : 'تم حفظ توقيع سابق لهذه العملية. يمكنك استبداله بتوقيع جديد.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.black54,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewStep(ThemeData theme) {
    final client = _client;
    final vehicle = _vehicle;
    final previousDamage = _hasPreviousDamage == true
        ? _damageController.text.trim()
        : 'لا يوجد ضرر سابق حسب إفادة العميل';
    return _stepContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _stepIntro(
            icon: Icons.task_alt,
            title: 'راجع وافتح الملف',
            subtitle:
                'لا فواتير ولا قيود محاسبية هنا؛ هذا ملف استلام أولي فقط.',
          ),
          const SizedBox(height: 18),
          _ReviewSection(
            title: 'العميل والمركبة',
            rows: <_ReviewRow>[
              _ReviewRow('العميل', client?.name ?? '—'),
              _ReviewRow('النوع', client?.type ?? '—'),
              _ReviewRow('رقم المركبة', vehicle?.number ?? '—'),
              _ReviewRow(
                'المركبة',
                <String>[vehicle?.type ?? '', vehicle?.model ?? '']
                    .where((value) => value.isNotEmpty)
                    .join(' • '),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ReviewSection(
            title: 'نطاق الملف والدفع',
            rows: <_ReviewRow>[
              _ReviewRow('نوع الملف', _repairScope),
              _ReviewRow('جهة الدفع', _payer),
              _ReviewRow('تسعير الأعمال', _pricingModeLabel(_worksPricingMode)),
              _ReviewRow('تسعير القطع', _pricingModeLabel(_partsPricingMode)),
              if (_repairScope != 'إصلاح فقط')
                _ReviewRow('توريد القطع', _partsSupplySource),
              if (_works.isNotEmpty)
                _ReviewRow(
                  'أعمال الإصلاح',
                  '${_works.length} بند • ${_pricingModeLabel(_worksPricingMode)} • ${_money(_sectionTotal(isPart: false))} $_currencySymbol\n${_linesReview(_works, isPart: false)}',
                ),
              if (_parts.isNotEmpty)
                _ReviewRow(
                  'القطع المطلوبة',
                  '${_parts.length} بند • ${_pricingModeLabel(_partsPricingMode)} • ${_partsPricingMode == 'list' ? 'بدون سعر' : '${_money(_sectionTotal(isPart: true))} $_currencySymbol'}\n${_linesReview(_parts, isPart: true)}',
                ),
              _ReviewRow(
                'إجمالي الملف',
                '${_money(_sectionTotal(isPart: false) + _sectionTotal(isPart: true))} $_currencySymbol',
              ),
              if (_payer != 'العميل' &&
                  _insuranceCompanyController.text.trim().isNotEmpty)
                _ReviewRow(
                  'شركة التأمين',
                  _insuranceCompanyController.text.trim(),
                ),
              if (_payer != 'العميل' &&
                  _claimNumberController.text.trim().isNotEmpty)
                _ReviewRow('رقم المطالبة', _claimNumberController.text.trim()),
            ],
          ),
          const SizedBox(height: 12),
          _ReviewSection(
            title: 'حالة الاستلام',
            rows: <_ReviewRow>[
              _ReviewRow('التاريخ', _dateLabel(_receivedDate)),
              _ReviewRow('العداد', '${_odometerController.text.trim()} كم'),
              _ReviewRow('الوقود', '$_fuelLevel%'),
              _ReviewRow('الأضرار السابقة', previousDamage),
              _ReviewRow(
                'الصور',
                _photoPaths.isEmpty
                    ? 'لم تُضف (اختياري)'
                    : '${_photoPaths.length} صورة',
              ),
              _ReviewRow('توثيق العميل', _consentReviewLabel()),
              if (_intakeNotesController.text.trim().isNotEmpty)
                _ReviewRow('ملاحظات', _intakeNotesController.text.trim()),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.info_outline, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'عند الحفظ يصبح الملف معتمدًا ماليًا تلقائيًا وتظهر قيمته مباشرة في القوائم والحسابات. يمكنك تعديل الأعمال والقطع والقيمة لاحقًا؛ أي فرق مالي يُسجل كتسوية محاسبية موثقة. القطع التي يوردها العميل أو شركة التأمين تبقى في الكشف ولا تدخل قيمة الملف.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepIntro({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: AppColors.lightGreen,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: AppColors.primary, size: 27),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: AppColors.textDark,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.black54,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _consentReviewLabel() {
    if (_consentMethod == 'توقيع على الشاشة') {
      return _savedSignaturePath?.isNotEmpty == true
          ? 'توقيع على الشاشة'
          : 'لم يُضف توقيع (اختياري)';
    }
    if (_consentMethod == 'بدون توثيق') {
      return 'غير موثق (اختياري)';
    }
    return _consentMethod;
  }

  Widget _optionalSection({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppColors.lightGrey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _emptyCard(String text) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.lightGrey),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.inbox_outlined, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _ClientChoice {
  const _ClientChoice(
      {required this.id, required this.name, required this.type});
  final int id;
  final String name;
  final String type;
}

class _VehicleChoice {
  const _VehicleChoice({
    required this.id,
    required this.number,
    required this.type,
    required this.model,
  });
  final int id;
  final String number;
  final String type;
  final String model;
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.step,
    required this.titles,
    required this.compact,
  });

  final int step;
  final List<String> titles;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = (step + 1) / titles.length;
    return Container(
      margin: EdgeInsets.fromLTRB(compact ? 14 : 18, 14, compact ? 14 : 18, 0),
      padding:
          EdgeInsets.fromLTRB(compact ? 14 : 18, 14, compact ? 14 : 18, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.lightGrey),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  'الخطوة ${step + 1} من ${titles.length}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                titles[step],
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AppColors.textDark,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: AppColors.lightGrey,
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(10),
          ),
          if (!compact) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              children: List<Widget>.generate(titles.length, (index) {
                final active = index <= step;
                return Expanded(
                  child: Text(
                    titles[index],
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                      color: active ? AppColors.primary : Colors.black45,
                    ),
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }
}

class _SelectionCard extends StatelessWidget {
  const _SelectionCard({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
  final bool selected;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: selected ? AppColors.lightGreen.withOpacity(.45) : Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.lightGrey,
          width: selected ? 1.8 : 1,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.lightGreen,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: AppColors.primary),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: AppColors.textDark,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: subtitle.isEmpty ? null : Text(subtitle),
        trailing: Icon(
          selected ? Icons.check_circle : Icons.radio_button_unchecked,
          color: selected ? AppColors.primary : Colors.black45,
        ),
      ),
    );
  }
}

class _BinaryChoice extends StatelessWidget {
  const _BinaryChoice({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.lightGreen.withOpacity(.45) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.lightGrey,
          width: selected ? 1.8 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? AppColors.primary : Colors.black45,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RepairLineEditorSheet extends StatefulWidget {
  const _RepairLineEditorSheet({
    required this.isPart,
    required this.isEdit,
    required this.existing,
    required this.mode,
    required this.modeLabel,
    required this.currencySymbol,
    required this.parseMoney,
    required this.money,
  });

  final bool isPart;
  final bool isEdit;
  final _RepairLineDraft? existing;
  final String mode;
  final String modeLabel;
  final String currencySymbol;
  final double Function(String) parseMoney;
  final String Function(double) money;

  @override
  State<_RepairLineEditorSheet> createState() => _RepairLineEditorSheetState();
}

class _RepairLineEditorSheetState extends State<_RepairLineEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _qtyController;
  late final TextEditingController _priceController;

  bool get _requirePrice => widget.mode == 'detailed';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _qtyController = TextEditingController(
      text: widget.existing?.qty.toString() ?? '1',
    );
    _priceController = TextEditingController(
      text: widget.existing == null || !_requirePrice
          ? ''
          : widget.existing!.price.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _qtyController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  double _previewTotal() {
    final qty = widget.parseMoney(_qtyController.text);
    final price =
        _requirePrice ? widget.parseMoney(_priceController.text) : 0.0;
    return qty * price;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        18,
        18,
        MediaQuery.viewInsetsOf(context).bottom + 18,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.lightGreen,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      widget.isPart
                          ? Icons.settings_outlined
                          : Icons.car_repair_outlined,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          widget.isEdit
                              ? (widget.isPart
                                  ? 'تعديل قطعة'
                                  : 'تعديل عمل إصلاح')
                              : (widget.isPart
                                  ? 'إضافة قطعة'
                                  : 'إضافة عمل إصلاح'),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          widget.modeLabel,
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _nameController,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText:
                      widget.isPart ? 'اسم / وصف القطعة *' : 'وصف العمل *',
                  prefixIcon: const Icon(Icons.description_outlined),
                ),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'أدخل الوصف.' : null,
              ),
              const SizedBox(height: 12),
              if (_requirePrice)
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextFormField(
                        inputFormatters: const [YallaDigitNormalizer()],
                        controller: _qtyController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.next,
                        decoration:
                            const InputDecoration(labelText: 'الكمية *'),
                        onChanged: (_) => setState(() {}),
                        validator: (value) =>
                            widget.parseMoney(value ?? '') <= 0
                                ? 'كمية غير صحيحة.'
                                : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        inputFormatters: const [YallaDigitNormalizer()],
                        controller: _priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: 'سعر الوحدة *',
                          suffixText: MoneyFormatter.symbol,
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (value) {
                          final parsed = widget.parseMoney(value ?? '');
                          return parsed < 0 || (value ?? '').trim().isEmpty
                              ? 'سعر غير صحيح.'
                              : null;
                        },
                      ),
                    ),
                  ],
                )
              else
                TextFormField(
                  inputFormatters: const [YallaDigitNormalizer()],
                  controller: _qtyController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'الكمية *',
                    helperText: 'لا يلزم سعر لهذا البند في هذا النمط.',
                  ),
                  validator: (value) => widget.parseMoney(value ?? '') <= 0
                      ? 'كمية غير صحيحة.'
                      : null,
                ),
              if (_requirePrice) ...<Widget>[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.lightGreen.withOpacity(.38),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Expanded(
                        child: Text(
                          'الإجمالي',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(
                        '${widget.money(_previewTotal())} ${widget.currencySymbol}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () {
                  if (!(_formKey.currentState?.validate() ?? false)) return;
                  final qty = widget.parseMoney(_qtyController.text);
                  final price = _requirePrice
                      ? widget.parseMoney(_priceController.text)
                      : 0.0;
                  Navigator.pop(
                    context,
                    _RepairLineDraft(
                      name: _nameController.text.trim(),
                      qty: qty,
                      price: price,
                    ),
                  );
                },
                icon: const Icon(Icons.check_rounded),
                label: Text(widget.isEdit ? 'حفظ التعديل' : 'إضافة'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RepairLineDraft {
  const _RepairLineDraft({
    required this.name,
    required this.qty,
    required this.price,
  });

  final String name;
  final double qty;
  final double price;

  double get total => qty * price;
}

class _RepairLineTypeValues {
  const _RepairLineTypeValues({required this.work, required this.part});
  final String work;
  final String part;
}

class _SignaturePad extends StatefulWidget {
  const _SignaturePad({super.key, required this.height});
  final double height;

  @override
  State<_SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<_SignaturePad> {
  final GlobalKey _boundaryKey = GlobalKey();
  final List<Offset?> _points = <Offset?>[];

  bool get hasInk => _points.any((point) => point != null);

  void clear() {
    setState(_points.clear);
  }

  Future<String?> exportPng() async {
    if (!hasInk) return null;
    await Future<void>.delayed(const Duration(milliseconds: 16));
    final boundary = _boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) return null;

    return YallaStorageService.saveSignature(
      bytes: bytes.buffer.asUint8List(),
      date: DateTime.now(),
    );
  }

  void _addPoint(Offset localPosition) {
    setState(() => _points.add(localPosition));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: RepaintBoundary(
        key: _boundaryKey,
        child: ColoredBox(
          color: Colors.white,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) => _addPoint(details.localPosition),
            onPanUpdate: (details) => _addPoint(details.localPosition),
            onPanEnd: (_) => setState(() => _points.add(null)),
            child: CustomPaint(
              painter: _SignaturePainter(_points),
              child: hasInk
                  ? const SizedBox.expand()
                  : const Center(
                      child: Text(
                        'وقّع هنا بإصبعك أو بالقلم',
                        style: TextStyle(color: Colors.black45),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter(this.points);
  final List<Offset?> points;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var index = 0; index < points.length - 1; index++) {
      final current = points[index];
      final next = points[index + 1];
      if (current != null && next != null) {
        canvas.drawLine(current, next, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}

class _ReviewRow {
  const _ReviewRow(this.label, this.value);
  final String label;
  final String value;
}

class _ReviewSection extends StatelessWidget {
  const _ReviewSection({required this.title, required this.rows});
  final String title;
  final List<_ReviewRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.lightGrey),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(title, style: theme.textTheme.titleMedium),
            const Divider(height: 24),
            ...rows.map(
              (row) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 125,
                      child: Text(
                        row.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(row.value.isEmpty ? '—' : row.value)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
