// ============================================================================
// 📁 lib/features/repairs/screens/edit_repair_screen.dart
// 🔥 النسخة النهائية — متوافقة مع نظام شركات التأمين
// 🔥 كاملة — جاهزة للاستبدال — بدون حذف ولا نقص
// 🔥 DB v38 — دعم محاسبي كامل + تحديثات ذكية للحقول
// ============================================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import 'package:printing/printing.dart';
import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/image_storage_service.dart';
import 'package:yalla_accounts/core/storage/yalla_stored_image.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/services/repairs_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_pdf_generator.dart';
import 'package:yalla_accounts/features/repairs/services/edit_repair_service.dart';

import 'package:yalla_accounts/features/repairs/constants/repair_status.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

// ============================================================================
//                                WIDGET
// ============================================================================
class EditRepairScreen extends StatefulWidget {
  final Repair repair;

  const EditRepairScreen({super.key, required this.repair});

  @override
  State<EditRepairScreen> createState() => _EditRepairScreenState();
}

// ============================================================================
//                        STATE & CONTROLLERS
// ============================================================================
class _EditRepairScreenState extends State<EditRepairScreen> {
  late TextEditingController _modelCtrl;
  late TextEditingController _typeCtrl;
  late TextEditingController _numberCtrl;
  late TextEditingController _beneficiaryCtrl;
  late TextEditingController _notesCtrl;
  late TextEditingController _paidCtrl;
  late TextEditingController _fileValueCtrl;

  late DateTime _receivedDate;

  String _beneficiaryType = 'شركة تأمين';
  String _repairType = 'بودي ودهان';
  String _vehicleStatus = 'بانتظار الإصلاح';
  String _paymentStatus = 'غير مسدد';
  String _insuranceFollowUp = '';
  String _partsSupplySource = 'الورشة';

  List<Map<String, dynamic>> _parts = [];
  List<Map<String, dynamic>> _works = [];
  List<String> _imagePaths = [];

  bool _isLoading = false;
  double _originalFileValue = 0.0;

  // ============================================================================
  //                             SMART COLUMN ENGINE
  // ============================================================================

  Future<Database> _getDatabase() async {
    final dbPath = await getDatabasesPath();
    final full = p.join(dbPath, 'yalla_accounts.db');
    return openDatabase(full);
  }

  Future<String?> _findExistingColumn(List<String> candidates) async {
    try {
      final db = await _getDatabase();
      final tableInfo = await db.rawQuery("PRAGMA table_info(repairs)");

      final names =
          tableInfo.map((row) => row['name'].toString().toLowerCase()).toList();

      for (final c in candidates) {
        if (names.contains(c.toLowerCase())) return c;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _updateSmart({
    required List<String> candidates,
    required String value,
  }) async {
    final col = await _findExistingColumn(candidates);
    if (col == null) return;

    final db = await _getDatabase();
    await db.update(
      'repairs',
      {col: value},
      where: 'id = ?',
      whereArgs: [widget.repair.id],
    );
  }

  Future<void> _smartInit() async {
    await _loadSmartValue(
      candidates: [
        'insurance_followup',
        'insurance_status',
        'insuranceFollowUpStatus',
      ],
      setter: (v) => _insuranceFollowUp = v,
    );

    await _loadSmartValue(
      candidates: ['vehicle_status', 'vehicleStatus', 'repair_status'],
      setter: (v) => _vehicleStatus = v,
    );

    await _loadSmartValue(
      candidates: ['repair_type', 'repairType'],
      setter: (v) => _repairType = v,
    );

    await _loadSmartValue(
      candidates: ['payment_status', 'paymentStatus'],
      setter: (v) => _paymentStatus = v,
    );
  }

  Future<void> _loadSmartValue({
    required List<String> candidates,
    required void Function(String v) setter,
  }) async {
    final col = await _findExistingColumn(candidates);
    if (col == null) return;

    final db = await _getDatabase();
    final res = await db.query(
      'repairs',
      columns: [col],
      where: 'id = ?',
      whereArgs: [widget.repair.id],
      limit: 1,
    );

    if (res.isNotEmpty && res.first[col] != null) {
      setter(res.first[col].toString());
      setState(() {});
    }
  }

  // ============================================================================
  //                               INIT
  // ============================================================================
  @override
  void initState() {
    super.initState();
    _initializeFromRepair();
    _smartInit();
  }

  void _initializeFromRepair() {
    final r = widget.repair;

    _modelCtrl = TextEditingController(text: r.vehicleModel);
    _typeCtrl = TextEditingController(text: r.vehicleType);
    _numberCtrl = TextEditingController(text: r.vehicleNumber);
    _beneficiaryCtrl = TextEditingController(text: r.beneficiaryName);
    _notesCtrl = TextEditingController(text: r.notes);
    _paidCtrl =
        TextEditingController(text: MoneyFormatter.number(r.paidAmount));
    _fileValueCtrl = TextEditingController();

    _receivedDate = r.receivedDate;
    _beneficiaryType = 'شركة تأمين';
    _repairType = r.repairType;
    _vehicleStatus = r.vehicleStatus;
    _originalFileValue = r.fileValue;

    _paymentStatus = (r.paymentStatus?.isNotEmpty ?? false)
        ? r.paymentStatus!
        : r.computedPaymentStatus;

    final noteText = r.notes ?? '';
    if (noteText.contains('[YALLA_PARTS_SUPPLY] العميل')) {
      _partsSupplySource = 'العميل';
    } else if (noteText.contains('[YALLA_PARTS_SUPPLY] شركة التأمين')) {
      _partsSupplySource = 'شركة التأمين';
    } else {
      _partsSupplySource = 'الورشة';
    }

    _parts = r.parts.map((p) {
      return {
        ...p,
        'total': _safeTotal(p),
      };
    }).toList();

    _works = r.works.map((w) {
      return {
        ...w,
        'total': _safeTotal(w),
      };
    }).toList();
    _imagePaths = List.from(r.imagePaths);

    _insuranceFollowUp = r.insuranceFollowUpStatus ?? '';
    _recalculateFileValue();
  }

  // ============================================================================
  //                           COMPUTED VALUES
  // ============================================================================
  double _safeTotal(Map<String, dynamic> item) {
    final qty = (item['qty'] as num?)?.toDouble() ?? 1.0;
    final price = (item['price'] as num?)?.toDouble() ?? 0.0;
    return qty * price;
  }

  double get _partsCost => _partsSupplySource == 'الورشة'
      ? _parts.fold<double>(
          0.0,
          (sum, item) => sum + ((item['total'] as num?)?.toDouble() ?? 0.0),
        )
      : 0.0;

  double get _worksCost => _works.fold<double>(
        0.0,
        (sum, item) => sum + ((item['total'] as num?)?.toDouble() ?? 0.0),
      );

  double get _paidAmount => double.tryParse(_paidCtrl.text.trim()) ?? 0.0;

  double get _fileValue => _partsCost + _worksCost;

  double get _valueDiff => _fileValue - _originalFileValue;

  // ============================================================================
  //                              IMAGES
  // ============================================================================
  Future<void> _pickImage(bool fromCamera) async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 70,
    );
    if (x == null) return;

    final savedPath = await ImageStorageService.saveImage(
      image: x,
      vehicleType: _typeCtrl.text.trim(),
      vehicleNumber: _numberCtrl.text.trim(),
      beneficiaryName: _beneficiaryCtrl.text.trim(),
      receivedDate: _receivedDate,
    );

    setState(() => _imagePaths.add(savedPath));
  }

  Future<void> _persistImages(String id) async {
    final svc = await RepairsService.instance();
    final existing = await svc.listImagePaths(id);

    for (final p in _imagePaths) {
      if (!existing.contains(p)) {
        await svc.addImagePath(repairId: id, path: p);
      }
    }
  }

  Future<void> _deleteImage(String path) async {
    try {
      await ImageStorageService.deleteImage(path);
    } catch (_) {}

    try {
      final svc = await RepairsService.instance();
      await svc.removeImagePath(path: path);
    } catch (_) {}

    setState(() => _imagePaths.remove(path));
  }

  void _recalculateFileValue() {
    setState(() {
      _fileValueCtrl.text = MoneyFormatter.number(_fileValue);
    });
  }

  // ============================================================================
  //                               SAVE
  // ============================================================================
  String _notesWithPartsSupplyMarker() {
    final lines = _notesCtrl.text
        .split('\n')
        .where((line) => !line.trim().startsWith('[YALLA_PARTS_SUPPLY]'))
        .toList(growable: true);
    lines.insert(0, '[YALLA_PARTS_SUPPLY] $_partsSupplySource');
    return lines.join('\n').trim();
  }

  Repair _buildUpdatedRepair() {
    final b = widget.repair;

    return b.copyWith(
      vehicleModel: _modelCtrl.text.trim(),
      vehicleType: _typeCtrl.text.trim(),
      vehicleNumber: _numberCtrl.text.trim(),
      beneficiaryName: _beneficiaryCtrl.text.trim(),
      repairType: _repairType,
      vehicleStatus: _vehicleStatus,
      parts: _parts,
      works: _works,
      fileValue: _fileValue,
      paidAmount: _paidAmount,
      paymentStatus: _paymentStatus,
      insuranceFollowUpStatus:
          _insuranceFollowUp.isEmpty ? null : _insuranceFollowUp,
      notes: _notesWithPartsSupplyMarker(),
      updatedAt: DateTime.now(),
      imagePaths: _imagePaths,
      finalApprovedAmount: _fileValue,
      incomeAmount: _fileValue,
      workCost: _worksCost,
      isLedgerEnabled: true,
    );
  }

  Future<void> _saveWithAccounting() async {
    setState(() => _isLoading = true);
    try {
      final updated = _buildUpdatedRepair();

      final result = await EditRepairService.editRepairWithAccounting(
        repairId: widget.repair.id,
        updatedRepair: updated,
        newParts: _parts,
        newWorks: _works,
        notes: updated.notes ?? '',
        editedBy: 'system',
      );

      await _persistImages(widget.repair.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم الحفظ — الفرق: ${result.difference}')),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ============================================================================
  //                             UI HELPERS
  // ============================================================================

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );

  Widget _card(String title, Widget child) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _listSection(
    String title,
    List<Map<String, dynamic>> list,
    bool isPart,
  ) {
    return _card(
      title,
      Column(
        children: [
          if (isPart) ...<Widget>[
            const Align(
              alignment: Alignment.centerRight,
              child: Text(
                'جهة توريد القطع',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: <String>['الورشة', 'العميل', 'شركة التأمين']
                  .map(
                    (source) => ChoiceChip(
                      label: Text(source),
                      selected: _partsSupplySource == source,
                      onSelected: (_) {
                        setState(() => _partsSupplySource = source);
                        _recalculateFileValue();
                      },
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 6),
            Text(
              _partsSupplySource == 'الورشة'
                  ? 'قيمة القطع تدخل في قيمة الملف.'
                  : 'القطع تبقى في الكشف ولا تدخل في قيمة الملف المحاسبية.',
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
            const Divider(height: 24),
          ],
          ...list.asMap().entries.map(
                (e) => ListTile(
                  title: Text(e.value['name']),
                  subtitle: Text(
                    '${e.value['qty']} × ${e.value['price']} = ${e.value['total']}',
                  ),

                  // زر تعديل + زر حذف
                  trailing: AdaptiveRow(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // زر التعديل
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () {
                          _editItem(e.key, list, isPart);
                        },
                      ),

                      // زر الحذف
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          setState(() {
                            list.removeAt(e.key);
                          });
                          _recalculateFileValue();
                        },
                      ),
                    ],
                  ),
                ),
              ),

          // زر إضافة (كما هو)
          ElevatedButton.icon(
            onPressed: () => _addItem(isPart: isPart),
            icon: const Icon(Icons.add),
            label: Text(isPart ? 'إضافة قطعة' : 'إضافة عمل'),
          ),
        ],
      ),
    );
  }

  void _addItem({required bool isPart}) {
    final name = TextEditingController();
    final qty = TextEditingController(text: "1");
    final price = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AdaptiveAlertDialog(
        title: Text(isPart ? 'إضافة قطعة' : 'إضافة عمل'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: _dec('الاسم'),
              inputFormatters: const [YallaDigitNormalizer()],
            ),
            TextField(
              controller: qty,
              decoration: _dec('الكمية'),
              inputFormatters: const [YallaDigitNormalizer()],
            ),
            TextField(
              controller: price,
              decoration: _dec('السعر'),
              inputFormatters: const [YallaDigitNormalizer()],
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('إضافة'),
            onPressed: () {
              final q = double.tryParse(qty.text) ?? 1;
              final p = double.tryParse(price.text) ?? 0;

              if (name.text.trim().isNotEmpty && q > 0 && p >= 0) {
                setState(() {
                  (isPart ? _parts : _works).add({
                    'name': name.text.trim(),
                    'qty': q,
                    'price': p,
                    'total': q * p,
                  });

                  // تحديث قيمة الملف مباشرة
                  _fileValueCtrl.text =
                      MoneyFormatter.number(_partsCost + _worksCost);
                });
              }
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  // ============================================================================
  //                                 BUILD
  // ============================================================================

  Widget _phoneSection(String title, IconData icon, Widget child) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.lightGrey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 21),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildPhoneEdit(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(
          _numberCtrl.text.trim().isEmpty
              ? 'تعديل ملف الإصلاح'
              : 'تعديل ${_numberCtrl.text.trim()}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'الكاميرا',
            onPressed: _isLoading ? null : () => _pickImage(true),
            icon: const Icon(Icons.photo_camera_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'gallery') {
                await _pickImage(false);
              } else if (value == 'pdf') {
                final pdf =
                    await RepairPdfGenerator.generate(_buildUpdatedRepair());
                await Printing.layoutPdf(onLayout: (_) => pdf);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'gallery',
                  child: ListTile(
                      leading: Icon(Icons.photo_library_outlined),
                      title: Text('إضافة من المعرض'))),
              PopupMenuItem(
                  value: 'pdf',
                  child: ListTile(
                      leading: Icon(Icons.picture_as_pdf_outlined),
                      title: Text('معاينة PDF'))),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 110),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${_typeCtrl.text} ${_modelCtrl.text}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'قيمة الملف ${MoneyFormatter.format(_fileValue)}  •  الفرق ${MoneyFormatter.format(_valueDiff)}',
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(
                            color: Colors.white70, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                _phoneSection(
                  'المركبة',
                  Icons.directions_car_outlined,
                  Column(children: [
                    TextField(
                        inputFormatters: const [YallaDigitNormalizer()],
                        controller: _typeCtrl,
                        decoration: _dec('نوع المركبة')),
                    const SizedBox(height: 10),
                    TextField(
                        inputFormatters: const [YallaDigitNormalizer()],
                        controller: _modelCtrl,
                        decoration: _dec('الموديل')),
                    const SizedBox(height: 10),
                    TextField(
                        inputFormatters: const [YallaDigitNormalizer()],
                        controller: _numberCtrl,
                        decoration: _dec('رقم المركبة')),
                  ]),
                ),
                _phoneSection(
                  'الحالة والعمل',
                  Icons.car_repair_outlined,
                  Column(children: [
                    DropdownButtonFormField<String>(
                      value: normalizeOrNull(_repairType, kRepairTypes),
                      isExpanded: true,
                      decoration: _dec('نوع العمل'),
                      items: kRepairTypes
                          .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) async {
                        if (v == null) return;
                        setState(() => _repairType = v);
                        await _updateSmart(
                            candidates: ['repair_type', 'repairType'],
                            value: v);
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: normalizeOrNull(_vehicleStatus, kVehicleStatuses),
                      isExpanded: true,
                      decoration: _dec('حالة المركبة'),
                      items: kVehicleStatuses
                          .map((e) => DropdownMenuItem(
                                value: e,
                                enabled: !kWorkflowVehicleStatuses.contains(e),
                                child: Text(e),
                              ))
                          .toList(),
                      onChanged:
                          kWorkflowVehicleStatuses.contains(_vehicleStatus)
                              ? null
                              : (v) async {
                                  if (v == null ||
                                      kWorkflowVehicleStatuses.contains(v)) {
                                    return;
                                  }
                                  setState(() => _vehicleStatus = v);
                                  await _updateSmart(candidates: [
                                    'vehicle_status',
                                    'repair_status'
                                  ], value: v);
                                },
                    ),
                  ]),
                ),
                _phoneSection(
                  'التأمين',
                  Icons.shield_outlined,
                  Column(children: [
                    TextField(
                        inputFormatters: const [YallaDigitNormalizer()],
                        controller: _beneficiaryCtrl,
                        decoration: _dec('اسم شركة التأمين / المستفيد')),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: normalizeOrNull(
                          _insuranceFollowUp, kInsuranceFollowups),
                      isExpanded: true,
                      decoration: _dec('متابعة التأمين'),
                      items: kInsuranceFollowups
                          .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) async {
                        if (v == null) return;
                        setState(() => _insuranceFollowUp = v);
                        await _updateSmart(
                          candidates: [
                            'insurance_followup',
                            'insuranceFollowUpStatus',
                            'insurance_status'
                          ],
                          value: v,
                        );
                      },
                    ),
                  ]),
                ),
                _listSection('قطع الغيار', _parts, true),
                _listSection('أعمال الإصلاح', _works, false),
                _phoneSection(
                  'المالية',
                  Icons.account_balance_wallet_outlined,
                  Column(children: [
                    TextField(
                      inputFormatters: const [YallaDigitNormalizer()],
                      controller: _fileValueCtrl,
                      readOnly: true,
                      decoration: _dec('قيمة الملف المحسوبة'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      inputFormatters: const [YallaDigitNormalizer()],
                      controller: _paidCtrl,
                      readOnly: true,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: _dec('المبلغ المدفوع'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: normalizeOrNull(_paymentStatus, kPaymentStatuses),
                      isExpanded: true,
                      decoration: _dec('حالة الدفع'),
                      items: kPaymentStatuses
                          .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      // حالة الدفع مشتقة من الدفعات الفعلية وليست إدخالًا يدويًا.
                      onChanged: null,
                    ),
                  ]),
                ),
                _phoneSection(
                  'الصور',
                  Icons.photo_library_outlined,
                  Column(
                    children: [
                      if (_imagePaths.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('لا توجد صور مضافة',
                              style: TextStyle(color: Colors.black54)),
                        ),
                      if (_imagePaths.isNotEmpty)
                        SizedBox(
                          height: 112,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _imagePaths.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (_, i) {
                              final path = _imagePaths[i];
                              return Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: YallaStoredImage(
                                        storedPath: path,
                                        width: 120,
                                        height: 105,
                                        fit: BoxFit.cover),
                                  ),
                                  PositionedDirectional(
                                    top: 4,
                                    end: 4,
                                    child: InkWell(
                                      onTap: () => _deleteImage(path),
                                      child: const CircleAvatar(
                                        radius: 12,
                                        backgroundColor: Colors.black54,
                                        child: Icon(Icons.close,
                                            color: Colors.white, size: 15),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickImage(true),
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('الكاميرا'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickImage(false),
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('المعرض'),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
                _phoneSection(
                  'ملاحظات',
                  Icons.notes_outlined,
                  TextField(
                      inputFormatters: const [YallaDigitNormalizer()],
                      controller: _notesCtrl,
                      minLines: 3,
                      maxLines: 6,
                      decoration: _dec('ملاحظات الملف')),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.lightGrey)),
          ),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: _isLoading ? null : _saveWithAccounting,
            icon: const Icon(Icons.check_rounded),
            label: const Text('حفظ التعديلات',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 600) return _buildPhoneEdit(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('تعديل ملف إصلاح'),
        backgroundColor: AppColors.primary,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: () async {
              final pdf =
                  await RepairPdfGenerator.generate(_buildUpdatedRepair());
              await Printing.layoutPdf(onLayout: (_) => pdf);
            },
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _isLoading ? null : _saveWithAccounting,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _card(
                    'بيانات المركبة',
                    Column(
                      children: [
                        TextField(
                            inputFormatters: const [YallaDigitNormalizer()],
                            controller: _typeCtrl,
                            decoration: _dec('نوع المركبة')),
                        const SizedBox(height: 12),
                        TextField(
                            inputFormatters: const [YallaDigitNormalizer()],
                            controller: _modelCtrl,
                            decoration: _dec('موديل المركبة')),
                        const SizedBox(height: 12),
                        TextField(
                            inputFormatters: const [YallaDigitNormalizer()],
                            controller: _numberCtrl,
                            decoration: _dec('رقم المركبة')),
                      ],
                    ),
                  ),
                  _card(
                    'بيانات شركات التأمين',
                    Column(
                      children: [
                        TextField(
                          inputFormatters: const [YallaDigitNormalizer()],
                          controller: _beneficiaryCtrl,
                          decoration: _dec('اسم شركة التأمين'),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: normalizeOrNull(
                              _insuranceFollowUp, kInsuranceFollowups),
                          decoration: _dec('المتابعة'),
                          items: kInsuranceFollowups
                              .map((e) =>
                                  DropdownMenuItem(value: e, child: Text(e)))
                              .toList(),
                          onChanged: (v) async {
                            if (v != null) {
                              setState(() => _insuranceFollowUp = v);
                              await _updateSmart(
                                candidates: [
                                  'insurance_followup',
                                  'insuranceFollowUpStatus',
                                  'insurance_status'
                                ],
                                value: v,
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  _card(
                    'نوع العمل وحالة المركبة',
                    Column(children: [
                      DropdownButtonFormField<String>(
                        value: normalizeOrNull(_repairType, kRepairTypes),
                        items: kRepairTypes
                            .map((e) =>
                                DropdownMenuItem(value: e, child: Text(e)))
                            .toList(),
                        onChanged: (v) async {
                          if (v != null) {
                            setState(() => _repairType = v);
                            await _updateSmart(
                                candidates: ['repair_type', 'repairType'],
                                value: v);
                          }
                        },
                        decoration: _dec('نوع العمل'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value:
                            normalizeOrNull(_vehicleStatus, kVehicleStatuses),
                        items: kVehicleStatuses
                            .map((e) => DropdownMenuItem(
                                  value: e,
                                  enabled:
                                      !kWorkflowVehicleStatuses.contains(e),
                                  child: Text(e),
                                ))
                            .toList(),
                        onChanged:
                            kWorkflowVehicleStatuses.contains(_vehicleStatus)
                                ? null
                                : (v) async {
                                    if (v == null ||
                                        kWorkflowVehicleStatuses.contains(v)) {
                                      return;
                                    }
                                    setState(() => _vehicleStatus = v);
                                    await _updateSmart(candidates: [
                                      'vehicle_status',
                                      'repair_status'
                                    ], value: v);
                                  },
                        decoration: _dec('حالة المركبة'),
                      ),
                    ]),
                  ),
                  _listSection('كشف القطع', _parts, true),
                  _listSection('كشف الأعمال', _works, false),
                  _card(
                    'المالية',
                    Column(
                      children: [
                        TextField(
                          inputFormatters: const [YallaDigitNormalizer()],
                          controller: _fileValueCtrl,
                          readOnly: true,
                          decoration: _dec('قيمة الملف'),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value:
                              normalizeOrNull(_paymentStatus, kPaymentStatuses),
                          items: kPaymentStatuses
                              .map((e) =>
                                  DropdownMenuItem(value: e, child: Text(e)))
                              .toList(),
                          decoration: _dec('حالة الدفع'),
                          onChanged: null,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          inputFormatters: const [YallaDigitNormalizer()],
                          controller: _paidCtrl,
                          readOnly: true,
                          decoration: _dec('المبلغ المدفوع'),
                        ),
                      ],
                    ),
                  ),
                  _card(
                    'ملاحظات',
                    TextField(
                      inputFormatters: const [YallaDigitNormalizer()],
                      controller: _notesCtrl,
                      maxLines: 3,
                      decoration: _dec('ملاحظات'),
                    ),
                  ),
                  _card(
                    'الصور',
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final path in _imagePaths)
                          Stack(
                            children: [
                              YallaStoredImage(
                                storedPath: path,
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              Positioned(
                                right: 4,
                                top: 4,
                                child: GestureDetector(
                                  onTap: () => _deleteImage(path),
                                  child: const CircleAvatar(
                                    radius: 12,
                                    backgroundColor: Colors.black54,
                                    child: Icon(Icons.close,
                                        color: Colors.white, size: 14),
                                  ),
                                ),
                              )
                            ],
                          ),
                        _imgBtn(
                            Icons.camera_alt, 'كاميرا', () => _pickImage(true)),
                        _imgBtn(Icons.photo, 'معرض', () => _pickImage(false)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _imgBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 26, color: Colors.grey.shade700),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: Colors.grey.shade700)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _modelCtrl.dispose();
    _typeCtrl.dispose();
    _numberCtrl.dispose();
    _beneficiaryCtrl.dispose();
    _notesCtrl.dispose();
    _paidCtrl.dispose();
    _fileValueCtrl.dispose();
    super.dispose();
  }

  void _editItem(int index, List<Map<String, dynamic>> list, bool isPart) {
    final item = list[index];

    final name = TextEditingController(text: item['name']?.toString() ?? '');
    final qty = TextEditingController(text: item['qty']?.toString() ?? '1');
    final price = TextEditingController(text: item['price']?.toString() ?? '0');

    showDialog(
      context: context,
      builder: (_) => AdaptiveAlertDialog(
        title: Text(isPart ? 'تعديل قطعة' : 'تعديل عمل'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: _dec('الاسم'),
              inputFormatters: const [YallaDigitNormalizer()],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: qty,
              decoration: _dec('الكمية'),
              inputFormatters: const [YallaDigitNormalizer()],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: price,
              decoration: _dec('السعر'),
              inputFormatters: const [YallaDigitNormalizer()],
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('حفظ'),
            onPressed: () {
              final q = double.tryParse(qty.text) ?? 1;
              final p = double.tryParse(price.text) ?? 0;

              if (name.text.trim().isEmpty || q <= 0 || p < 0) return;
              setState(() {
                list[index] = {
                  'name': name.text.trim(),
                  'qty': q,
                  'price': p,
                  'total': q * p,
                };
              });

              _recalculateFileValue();
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}
