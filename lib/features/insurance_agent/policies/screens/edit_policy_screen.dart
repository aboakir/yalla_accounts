// 📁 lib/features/insurance_agent/policies/screens/edit_policy_screen.dart
//
// EditPolicyScreen — تعديل بوليصة (DB REAL + Document Type + Vehicle Price)
// ✅ بدون RTL / Directionality / TextDirection (محاذاة يمين فقط)
// ✅ يعمل على Windows Desktop
// ✅ يقبل row أو policyId ويجلب من DB
// ✅ تحديث مباشر في جدول insurance_policies
// ✅ إضافة: نوع الوثيقة (طرف ثالث/شامل) + سعر المركبة (من DB الحقيقي)
// ✅ حفظ ذكي: يتحقق من وجود الأعمدة قبل التحديث لتفادي أخطاء schema

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class EditPolicyScreen extends StatefulWidget {
  final dynamic policyId; // int أو String
  final Map<String, dynamic>? row;

  const EditPolicyScreen({
    super.key,
    this.policyId,
    this.row,
  });

  @override
  State<EditPolicyScreen> createState() => _EditPolicyScreenState();
}

class _EditPolicyScreenState extends State<EditPolicyScreen> {
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _saving = false;

  Map<String, dynamic>? _row;

  // Controllers
  final _plate = TextEditingController();
  final _insuredName = TextEditingController();
  final _insuredPhone = TextEditingController();
  final _company = TextEditingController();

  final _engineSize = TextEditingController();
  final _buyPrice = TextEditingController();
  final _sellPrice = TextEditingController();
  final _paymentMethod = TextEditingController();

  // ✅ NEW: Vehicle Price
  final _vehiclePrice = TextEditingController();

  final _notes = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;

  bool _vip = false;

  // ✅ NEW: Document Type
  static const List<String> _docTypes = ['طرف ثالث', 'شامل'];
  String? _documentType;

  // ---------------------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _plate.dispose();
    _insuredName.dispose();
    _insuredPhone.dispose();
    _company.dispose();
    _engineSize.dispose();
    _buyPrice.dispose();
    _sellPrice.dispose();
    _paymentMethod.dispose();
    _vehiclePrice.dispose();
    _notes.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  Future<void> _boot() async {
    if (widget.row != null) {
      _row = Map<String, dynamic>.from(widget.row!);
      _fillFromRow(_row!);
      setState(() => _loading = false);
      return;
    }

    if (widget.policyId == null) {
      setState(() => _loading = false);
      return;
    }

    await _loadFromDb(widget.policyId);
  }

  Future<void> _loadFromDb(dynamic policyId) async {
    setState(() => _loading = true);

    try {
      final db = await DatabaseMigration.database;

      final candidates = <String>['id', 'policy_id', 'uuid'];

      Map<String, dynamic>? found;

      for (final col in candidates) {
        try {
          final rows = await db.query(
            'insurance_policies',
            where: '$col = ?',
            whereArgs: [policyId],
            limit: 1,
          );
          if (rows.isNotEmpty) {
            found = Map<String, dynamic>.from(rows.first);
            break;
          }
        } catch (_) {}
      }

      if (!mounted) return;

      setState(() {
        _row = found;
        _loading = false;
      });

      if (found != null) _fillFromRow(found);

      if (found == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('⚠️ لم يتم العثور على البوليصة للتعديل')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ فشل تحميل البوليصة: $e')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;

    try {
      return DateTime.parse(s);
    } catch (_) {
      try {
        return DateFormat('dd/MM/yyyy', 'en_US').parseStrict(s);
      } catch (_) {
        return null;
      }
    }
  }

  String _resolveFirst(Map<String, dynamic> r, List<String> keys,
      {String fallback = ''}) {
    for (final k in keys) {
      final v = r[k];
      if (v == null) continue;
      final t = v.toString().trim();
      if (t.isNotEmpty) return t;
    }
    return fallback;
  }

  void _fillFromRow(Map<String, dynamic> r) {
    _plate.text =
        _resolveFirst(r, ['vehicle_plate', 'vehicle_number', 'plate']);
    _insuredName.text =
        _resolveFirst(r, ['insured_name', 'policy_holder_name', 'owner_name']);
    _insuredPhone.text = _resolveFirst(
      r,
      [
        'insured_phone',
        'policy_holder_phone',
        'owner_phone',
        'mobile',
        'phone',
      ],
    );
    _company.text = _resolveFirst(r, ['company_name', 'insurance_company']);

    _engineSize.text = _resolveFirst(r, ['engine_size', 'engine_cc']);
    _buyPrice.text = _resolveFirst(r, ['buy_price', 'purchase_price']);
    _sellPrice.text = _resolveFirst(r, ['sell_price', 'sale_price']);
    _paymentMethod.text = _resolveFirst(r, ['payment_method', 'payment_type']);

    // ✅ NEW: سعر المركبة (من المصدر الحقيقي)
    _vehiclePrice.text = _resolveFirst(
      r,
      [
        'car_price',
        'vehicle_price',
        'vehicle_value',
        'car_value',
        'price',
      ],
    );

    // ✅ NEW: نوع الوثيقة (من المصدر الحقيقي)
    final dt = _resolveFirst(
      r,
      [
        'document_type',
        'policy_type',
        'coverage_type',
        'doc_type',
      ],
    );
    _documentType = _docTypes.contains(dt) ? dt : null;

    _notes.text = _resolveFirst(r, ['notes', 'policy_notes']);

    _startDate = _parseDate(r['start_date']);
    _endDate = _parseDate(r['end_date']);

    _vip = (r['is_vip'] ?? r['vip'] ?? 0) == 1;

    setState(() {});
  }

  // ---------------------------------------------------------------------------
  Future<void> _pickDate({required bool isStart}) async {
    final initial =
        isStart ? (_startDate ?? DateTime.now()) : (_endDate ?? DateTime.now());
    final firstDate = DateTime(2000);
    final lastDate = DateTime(2100);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
    );

    if (picked == null) return;

    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(_startDate!)) {
          _endDate = _startDate;
        }
      } else {
        _endDate = picked;
      }
    });
  }

  // ---------------------------------------------------------------------------
  dynamic _resolveId(Map<String, dynamic> r) {
    if (r.containsKey('id')) return r['id'];
    if (r.containsKey('policy_id')) return r['policy_id'];
    if (r.containsKey('uuid')) return r['uuid'];
    return null;
  }

  // ---------------------------------------------------------------------------
  Future<Set<String>> _tableColumns(String table) async {
    final db = await DatabaseMigration.database;
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((e) => (e['name'] ?? '').toString()).toSet();
  }

  String? _pickExistingColumn(Set<String> cols, List<String> candidates) {
    for (final c in candidates) {
      if (cols.contains(c)) return c;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  Future<void> _save() async {
    if (_saving) return;

    final r = _row;
    if (r == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ لا توجد بيانات للتعديل')),
      );
      return;
    }

    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ اختر تاريخ البداية والنهاية')),
      );
      return;
    }

    final id = _resolveId(r);
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('⚠️ لا يمكن تحديد معرف البوليصة (id/uuid)')),
      );
      return;
    }

    // ✅ نوع الوثيقة إلزامي هنا لأنك طلبته كحقل مهم
    if (_documentType == null || _documentType!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ اختر نوع الوثيقة (طرف ثالث / شامل)')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final db = await DatabaseMigration.database;
      final cols = await _tableColumns('insurance_policies');

      // نحدد عمود where
      String whereCol = 'id';
      if (r.containsKey('id')) {
        whereCol = 'id';
      } else if (r.containsKey('policy_id')) {
        whereCol = 'policy_id';
      } else if (r.containsKey('uuid')) {
        whereCol = 'uuid';
      }

      // ✅ خريطة تحديث ذكية حسب الأعمدة الموجودة فعليًا
      final updateMap = <String, dynamic>{};

      void putIfExists(String colName, dynamic value) {
        if (cols.contains(colName)) updateMap[colName] = value;
      }

      // الأساسية (أسماء أعمدة شائعة)
      putIfExists('vehicle_plate', _plate.text.trim());
      putIfExists('insured_name', _insuredName.text.trim());
      putIfExists('insured_phone', _insuredPhone.text.trim());
      putIfExists('company_name', _company.text.trim());

      final iso = DateFormat('yyyy-MM-dd', 'en_US');
      putIfExists('start_date', iso.format(_startDate!));
      putIfExists('end_date', iso.format(_endDate!));

      putIfExists('is_vip', _vip ? 1 : 0);

      putIfExists('engine_size', _engineSize.text.trim());
      putIfExists('buy_price', _buyPrice.text.trim());
      putIfExists('sell_price', _sellPrice.text.trim());
      putIfExists('payment_method', _paymentMethod.text.trim());
      putIfExists('notes', _notes.text.trim());

      // ✅ NEW: سعر المركبة — نختار العمود الحقيقي الموجود
      final carPriceCol = _pickExistingColumn(cols, [
        'car_price',
        'vehicle_price',
        'vehicle_value',
        'car_value',
        'price',
      ]);
      if (carPriceCol != null) {
        updateMap[carPriceCol] = _vehiclePrice.text.trim();
      }

      // ✅ NEW: نوع الوثيقة — نختار العمود الحقيقي الموجود
      final docTypeCol = _pickExistingColumn(cols, [
        'document_type',
        'policy_type',
        'coverage_type',
        'doc_type',
      ]);
      if (docTypeCol != null) {
        updateMap[docTypeCol] = _documentType!.trim();
      }

      if (updateMap.isEmpty) {
        throw 'لا يوجد أي أعمدة مطابقة للتحديث داخل insurance_policies';
      }

      await db.update(
        'insurance_policies',
        updateMap,
        where: '$whereCol = ?',
        whereArgs: [id],
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ تم حفظ التعديلات')),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ فشل الحفظ: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------------------------------------------------------------------
  Widget _field({
    required String label,
    required TextEditingController c,
    String? hint,
    TextInputType? type,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: c,
      keyboardType: type,
      textAlign: TextAlign.right,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF7F8FA),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      validator: validator,
    );
  }

  Widget _dateBox({
    required String label,
    required DateTime? value,
    required VoidCallback onPick,
  }) {
    final text = value == null ? '—' : DateFormat('yyyy-MM-dd').format(value);
    return InkWell(
      onTap: _saving ? null : onPick,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black12),
        ),
        child: AdaptiveRow(
          children: [
            const Icon(Icons.calendar_month, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: Colors.grey.shade700, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return AdaptiveRow(
      children: [
        const Spacer(),
        Text(
          title,
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }

  // ✅ NEW: Dropdown (نوع الوثيقة)
  Widget _documentTypeField() {
    return DropdownButtonFormField<String>(
      value: _documentType,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'نوع الوثيقة',
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF7F8FA),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      items: _docTypes
          .map(
            (x) => DropdownMenuItem<String>(
              value: x,
              child: Text(x, textAlign: TextAlign.right),
            ),
          )
          .toList(),
      onChanged: _saving ? null : (v) => setState(() => _documentType = v),
      validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
    );
  }

  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text(
          'تعديل البوليصة',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'حفظ',
            onPressed: (_loading || _saving) ? null : _save,
            icon: const Icon(Icons.save, color: Colors.white),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_row == null
              ? const Center(child: Text('لا توجد بيانات'))
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Form(
                        key: _formKey,
                        child: ListView(
                          children: [
                            _sectionTitle('بيانات المركبة'),
                            const SizedBox(height: 10),
                            _field(
                              label: 'رقم المركبة',
                              c: _plate,
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'مطلوب'
                                  : null,
                            ),
                            const SizedBox(height: 12),

                            // ✅ نوع الوثيقة + سعر المركبة
                            LayoutBuilder(
                              builder: (_, c) {
                                final tight = c.maxWidth < 720;
                                final w =
                                    tight ? c.maxWidth : (c.maxWidth / 2 - 6);
                                return Wrap(
                                  alignment: WrapAlignment.end,
                                  runSpacing: 12,
                                  spacing: 12,
                                  children: [
                                    SizedBox(
                                        width: w, child: _documentTypeField()),
                                    SizedBox(
                                      width: w,
                                      child: _field(
                                        label: 'سعر المركبة',
                                        c: _vehiclePrice,
                                        type: TextInputType.number,
                                        hint: 'مثال: 50000',
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),

                            const SizedBox(height: 12),
                            _field(
                              label: 'حجم المحرك',
                              c: _engineSize,
                              type: TextInputType.text,
                            ),
                            const SizedBox(height: 18),

                            _sectionTitle('بيانات المؤمن له'),
                            const SizedBox(height: 10),
                            _field(
                              label: 'الاسم',
                              c: _insuredName,
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'مطلوب'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            _field(
                              label: 'الهاتف',
                              c: _insuredPhone,
                              type: TextInputType.phone,
                            ),
                            const SizedBox(height: 18),

                            _sectionTitle('الشركة والتواريخ'),
                            const SizedBox(height: 10),
                            _field(
                              label: 'الشركة',
                              c: _company,
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'مطلوب'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            LayoutBuilder(
                              builder: (_, c) {
                                final tight = c.maxWidth < 720;
                                return Wrap(
                                  alignment: WrapAlignment.end,
                                  runSpacing: 12,
                                  spacing: 12,
                                  children: [
                                    SizedBox(
                                      width: tight
                                          ? c.maxWidth
                                          : (c.maxWidth / 2 - 6),
                                      child: _dateBox(
                                        label: 'بداية التأمين',
                                        value: _startDate,
                                        onPick: () => _pickDate(isStart: true),
                                      ),
                                    ),
                                    SizedBox(
                                      width: tight
                                          ? c.maxWidth
                                          : (c.maxWidth / 2 - 6),
                                      child: _dateBox(
                                        label: 'نهاية التأمين',
                                        value: _endDate,
                                        onPick: () => _pickDate(isStart: false),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            SwitchListTile(
                              value: _vip,
                              onChanged: _saving
                                  ? null
                                  : (v) => setState(() => _vip = v),
                              title: const Text('VIP'),
                              subtitle: const Text('تفعيل حالة VIP للمؤمّن له'),
                              contentPadding: EdgeInsets.zero,
                            ),
                            const SizedBox(height: 18),

                            _sectionTitle('التسعير والدفع'),
                            const SizedBox(height: 10),
                            LayoutBuilder(
                              builder: (_, c) {
                                final tight = c.maxWidth < 720;
                                final w =
                                    tight ? c.maxWidth : (c.maxWidth / 2 - 6);

                                return Wrap(
                                  alignment: WrapAlignment.end,
                                  runSpacing: 12,
                                  spacing: 12,
                                  children: [
                                    SizedBox(
                                      width: w,
                                      child: _field(
                                        label: 'سعر شراء البوليصة',
                                        c: _buyPrice,
                                        type: TextInputType.number,
                                      ),
                                    ),
                                    SizedBox(
                                      width: w,
                                      child: _field(
                                        label: 'سعر بيع البوليصة',
                                        c: _sellPrice,
                                        type: TextInputType.number,
                                      ),
                                    ),
                                    SizedBox(
                                      width: tight ? c.maxWidth : c.maxWidth,
                                      child: _field(
                                        label: 'آلية الدفع',
                                        c: _paymentMethod,
                                        hint: 'نقدًا / شيكات / أقساط',
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 18),

                            _sectionTitle('ملاحظات'),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _notes,
                              textAlign: TextAlign.right,
                              minLines: 3,
                              maxLines: 6,
                              decoration: InputDecoration(
                                hintText: 'اكتب أي ملاحظة مهمة…',
                                isDense: true,
                                filled: true,
                                fillColor: const Color(0xFFF7F8FA),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),

                            AdaptiveRow(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: (_saving) ? null : _save,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    icon: _saving
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.save,
                                            color: Colors.white),
                                    label: Text(
                                      _saving ? 'جاري الحفظ…' : 'حفظ التعديلات',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _saving
                                        ? null
                                        : () => Navigator.pop(context, false),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    icon: const Icon(Icons.close),
                                    label: const Text('إلغاء'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )),
    );
  }
}
