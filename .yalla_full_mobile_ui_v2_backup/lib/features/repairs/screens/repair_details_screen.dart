import 'dart:ui' as ui;
// ًں“پ lib/features/repairs/screens/repair_details_screen.dart
// - ط­ط§ظ„ط© ط§ظ„طھط£ظ…ظٹظ† + ط­ط§ظ„ط© ط§ظ„ظ…ط±ظƒط¨ط© ط¬ظ†ط¨ ط¨ط¹ط¶ ط¯ط§ط®ظ„ ط§ظ„ط¨ط·ط§ظ‚ط© ط§ظ„ظٹط³ط±ظ‰.
// - طھط­ط¯ظٹط« ط°ظƒظٹ ظ„ط£ط³ظ…ط§ط، ط§ظ„ط£ط¹ظ…ط¯ط© (ظٹظƒطھط´ظپ ط§ظ„ط¹ظ…ظˆط¯ ط§ظ„طµط­ظٹط­ ظ‚ط¨ظ„ UPDATE).
// - ط¯ظپط¹ط§طھطŒ ط§ط¹طھظ…ط§ط¯ ظ†ظ‡ط§ط¦ظٹطŒ طµظˆط±طŒ PDFطŒ GL.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:yalla_accounts/core/services/image_storage_service.dart';

import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/services/repairs_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_pdf_generator.dart';
import 'package:yalla_accounts/features/repairs/services/repair_finance_service.dart';

import 'package:yalla_accounts/features/repairs/constants/repair_status.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/finance/payments/models/payment.dart';
import 'package:yalla_accounts/features/repairs/widgets/repair_thumb.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class RepairDetailsScreen extends StatefulWidget {
  final Repair repair;
  const RepairDetailsScreen({super.key, required this.repair});

  @override
  State<RepairDetailsScreen> createState() => _RepairDetailsScreenState();
}

class _RepairDetailsScreenState extends State<RepairDetailsScreen> {
  late Repair _repair;
  bool _loading = true;
  bool _approving = false;

  List<Map<String, dynamic>> _repairWorks = [];
  List<Map<String, dynamic>> _repairParts = [];

  final _currency = NumberFormat('#,##0.00', 'ar');
  final _df = DateFormat('yyyy-MM-dd');

  int? _invoiceGlEntryId;

  final ScrollController _imagesScrollCtrl = ScrollController();

  static const List<_PayMethod> _methods = [
    _PayMethod('cash', 'ط§ظ„طµظ†ط¯ظˆظ‚ (1000)'),
    _PayMethod('bank', 'ط§ظ„ط¨ظ†ظƒ (1010)'),
  ];

  // ط®ظٹط§ط±ط§طھ ط§ظ„ظ‚ظˆط§ط¦ظ…
  static const List<String> _insuranceOptions = [
    'طھظ… طھط³ظ„ظٹظ… ط§ظ„ظپط§طھظˆط±ط©',
    'طھظ… ط§ظ„طھط³ط¯ظٹط¯ ظپظٹ ط§ظ„طھط¹ظˆظٹط¶ط§طھ',
    'طھظ… ط§ظ„طھط³ط¯ظٹط¯ ظپظٹ ط§ظ„ظ…ط§ظ„ظٹط©',
    'طھظ… ط§ظ„طµط±ظپ',
  ];

  static const List<String> _vehicleOptions = [
    'طھظ… ط§ظ„ط§ط³طھظ„ط§ظ…',
    'ظ‚ظٹط¯ ط§ظ„ط¥طµظ„ط§ط­',
    'ط¬ط§ظ‡ط²ط© ظ„ظ„طھط³ظ„ظٹظ…',
    'طھظ… ط§ظ„طھط³ظ„ظٹظ…',
  ];

  @override
  void initState() {
    super.initState();
    _repair = widget.repair;
    _loadRepairDetails();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _reloadRepair();
    });
  }

  @override
  void dispose() {
    _imagesScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRepairDetails() async {
    final svc = await RepairsService.instance();
    final loaded = await svc.getById(widget.repair.id);
    if (!mounted) return;
    final r = loaded ?? widget.repair;
    setState(() {
      _repair = r;
      _repairWorks = List<Map<String, dynamic>>.from(r.works);
      _repairParts = List<Map<String, dynamic>>.from(r.parts);
      _loading = false;
    });
    await _refreshInvoiceGl();
  }

  Future<void> _reloadRepair() async {
    final svc = await RepairsService.instance();
    final r = await svc.getById(_repair.id);
    if (!mounted) return;
    if (r != null) {
      setState(() => _repair = r);
      await _refreshInvoiceGl();
    }
  }

  // ===== ظƒط´ظپ ط§ط³ظ… ط§ظ„ط¹ظ…ظˆط¯ ط§ظ„ط­ظ‚ظٹظ‚ظٹ ظˆطھط­ط¯ظٹط«ظ‡ ط¨ط´ظƒظ„ ط¢ظ…ظ† =====
  Future<String?> _findExistingColumn(List<String> candidates) async {
    final db = await DBService.database;
    final rows = await db.rawQuery('PRAGMA table_info(repairs)');
    final cols = rows.map((r) => (r['name'] ?? '').toString()).toSet();
    for (final c in candidates) {
      if (cols.contains(c)) return c;
    }
    return null;
  }

  Future<void> _updateColumnSmart({
    required List<String> candidates,
    required String value,
    required String successMsg,
  }) async {
    try {
      final col = await _findExistingColumn(candidates);
      if (col == null) {
        throw 'ظ„ظ… ظٹظڈط¹ط«ط± ط¹ظ„ظ‰ ط¹ظ…ظˆط¯ ظ…ظ†ط§ط³ط¨ (${candidates.join(", ")}) ظپظٹ ط¬ط¯ظˆظ„ repairs';
      }
      final db = await DBService.database;
      await db.update('repairs', {col: value},
          where: 'id = ?', whereArgs: [_repair.id]);
      await _reloadRepair();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(successMsg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ظپط´ظ„ طھط­ط¯ظٹط« ط§ظ„ط­ط§ظ„ط©: $e')));
    }
  }

  // طھط­ط¯ظٹط« ط§ظ„ط­ط§ظ„ط§طھ ط¨ط§ط³طھط®ط¯ط§ظ… ط§ظ„ظƒط´ظپ ط§ظ„ط°ظƒظٹ
  Future<void> _updateInsuranceStatus(String value) async {
    await _updateColumnSmart(
      candidates: [
        'insurance_followup',
        'insurance_status',
        'insuranceStatus',
        'insurance_followup_status',
      ],
      value: value,
      successMsg: 'طھظ… طھط­ط¯ظٹط« ط­ط§ظ„ط© ط§ظ„طھط£ظ…ظٹظ†',
    );
  }

  Future<void> _updateVehicleStatus(String value) async {
    await _updateColumnSmart(
      candidates: [
        'vehicle_status',
        'vehicleStatus',
        'car_status',
        'status_vehicle',
      ],
      value: value,
      successMsg: 'طھظ… طھط­ط¯ظٹط« ط­ط§ظ„ط© ط§ظ„ظ…ط±ظƒط¨ط©',
    );
  }

  // ===== GL helpers =====
  Future<void> _refreshInvoiceGl() async {
    final invId = _repair.invoiceId;
    if (invId == null || invId.isEmpty) {
      setState(() => _invoiceGlEntryId = null);
      return;
    }
    try {
      final db = await DBService.database;
      final row = await db.rawQuery(
        '''
        SELECT id FROM gl_entries
        WHERE source = 'INVOICE' AND source_id = ?
        ORDER BY id DESC
        LIMIT 1
        ''',
        [invId],
      );
      setState(() {
        _invoiceGlEntryId =
            row.isNotEmpty ? int.tryParse('${row.first['id']}') : null;
      });
    } catch (_) {
      setState(() => _invoiceGlEntryId = null);
    }
  }

  Future<void> _postInvoiceGLIfMissing() async {
    final invId = _repair.invoiceId;
    if (invId == null || invId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('ظ„ط§ طھظˆط¬ط¯ ظپط§طھظˆط±ط© ظ„ظ‡ط°ط§ ط§ظ„ظ…ظ„ظپ.')),
      );
      return;
    }
    if (_invoiceGlEntryId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'ظ‚ظٹط¯ GL ظ…ظˆط¬ظˆط¯ ط¨ط§ظ„ظپط¹ظ„ (#$_invoiceGlEntryId).')),
      );
      return;
    }
    try {
      final id = await DBService.postInvoiceGLFromId(invId);
      await _refreshInvoiceGl();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('âœ… طھظ… طھط±ط­ظٹظ„ ظ‚ظٹط¯ ط§ظ„ظپط§طھظˆط±ط© GL (#$id)')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('â‌Œ ظپط´ظ„ طھط±ط­ظٹظ„ GL: $e')),
      );
    }
  }

  // ===== ط§ط¹طھظ…ط§ط¯ ظ†ظ‡ط§ط¦ظٹ =====
  Future<void> _confirmFinalApproval() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AdaptiveAlertDialog(
        title: const Text('ط§ط¹طھظ…ط§ط¯ ط§ظ„ط³ط¹ط± ط§ظ„ظ†ظ‡ط§ط¦ظٹ'),
        content: const Text(
            'ظ‡ظ„ طھط±ظٹط¯ ط§ط¹طھظ…ط§ط¯ ط§ظ„ط³ط¹ط± ط§ظ„ظ†ظ‡ط§ط¦ظٹ ظˆطھط³ط¬ظٹظ„ ط§ظ„ظ‚ظٹط¯ ط§ظ„ظ…ط­ط§ط³ط¨ظٹطں'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ط¥ظ„ط؛ط§ط،')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('طھط£ظƒظٹط¯')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _approving = true);
    try {
      await RepairFinanceService.approveFinalAmount(_repair);
      await _reloadRepair();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'âœ… طھظ… ط§ظ„ط§ط¹طھظ…ط§ط¯ ظˆط¥ظ†ط´ط§ط، ط§ظ„ظ‚ظٹط¯ ظˆط§ظ„ظپط§طھظˆط±ط©')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('â‌Œ ظپط´ظ„ ط§ظ„ط§ط¹طھظ…ط§ط¯: $e')),
      );
    } finally {
      if (mounted) setState(() => _approving = false);
    }
  }

  // ===== ط§ظ„ط¯ظپط¹ط§طھ =====
  Future<void> _addPayment() async {
    if (_repair.id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'ظ„ط§ ظٹظ…ظƒظ† ط¥ط¶ط§ظپط© ط¯ظپط¹ط© ظ‚ط¨ظ„ ط­ظپط¸ ظ…ظ„ظپ ط§ظ„ط¥طµظ„ط§ط­.')),
      );
      return;
    }

    final amountCtrl = TextEditingController();
    final notesCtrl =
        TextEditingController(text: 'ط¯ظپط¹ط© ط¹ظ„ظ‰ ظ…ظ„ظپ ط¥طµظ„ط§ط­');
    DateTime payDate = DateTime.now();
    _PayMethod method = _methods.first;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => AdaptiveAlertDialog(
          title: const Text('ط¥ط¶ط§ظپط© ط¯ظپط¹ط©'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText: 'ط§ظ„ظ…ط¨ظ„ط؛', hintText: '0.00'),
                  autofocus: true,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<_PayMethod>(
                  value: method,
                  items: _methods
                      .map((m) =>
                          DropdownMenuItem(value: m, child: Text(m.label)))
                      .toList(),
                  onChanged: (v) => setM(() => method = v ?? _methods.first),
                  decoration:
                      InputDecoration(labelText: 'ط·ط±ظٹظ‚ط© ط§ظ„ط¯ظپط¹'),
                ),
                const SizedBox(height: 10),
                AdaptiveRow(
                  children: [
                    const Text('ط§ظ„طھط§ط±ظٹط®: '),
                    TextButton(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          firstDate: DateTime(DateTime.now().year - 3, 1, 1),
                          lastDate: DateTime(DateTime.now().year + 1, 12, 31),
                          initialDate: payDate,
                        );
                        if (d != null) setM(() => payDate = d);
                      },
                      child: Text(_df.format(payDate)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'ظ…ظ„ط§ط­ط¸ط§طھ (ط§ط®طھظٹط§ط±ظٹ)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ط¥ظ„ط؛ط§ط،')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('ط­ظپط¸')),
          ],
        ),
      ),
    );

    if (ok != true) return;

    final raw = amountCtrl.text.trim().replaceAll(',', '');
    final amount = double.tryParse(raw) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ط£ط¯ط®ظ„ ظ…ط¨ظ„ط؛ظ‹ط§ طµط§ظ„ط­ظ‹ط§')));
      return;
    }

    final remaining = (_repair.totalFileValue) - (_repair.totalPaidAmount);
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ط§ظ„ظ…ظ„ظپ ظ…ط³ط¯ط¯ ط¨ط§ظ„ظƒط§ظ…ظ„')));
      return;
    }
    if (amount > remaining + 0.0001) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'ط§ظ„ظ…ط¨ظ„ط؛ ظٹطھط¬ط§ظˆط² ط§ظ„ظ…طھط¨ظ‚ظٹ (${_currency.format(remaining)})')),
      );
      return;
    }

    final payment = Payment(
      id: '',
      clientId: _repair.clientId,
      invoiceId: _repair.invoiceId,
      repairId: _repair.id,
      relatedRepairId: _repair.id,
      amount: double.parse(amount.toStringAsFixed(2)),
      date: payDate,
      method: method.key,
      accountName: method.key,
      status: "confirmed", // â†گ String ط¨ط¯ظ„ Enum
      notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
      attachments: null,
      glEntryId: null,

      // REQUIRED â€” ظ„ط§ط²ظ… ظ…ظˆط¬ظˆط¯ ط­ط³ط¨ ط§ظ„ظ…ظˆط¯ظٹظ„
      isIncome: true, // â†گ ظ„ط£ظ†ظ‡ط§ ط¯ظپط¹ط© ظ‚ط¨ط¶ ظ„ظ„ط¹ظ…ظٹظ„
    );

    try {
      await PaymentService.insertAndPostReceipt(
        payment: payment,
        customerName: _repair.beneficiaryName,
        method: method.key,
        descriptionOverride:
            notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
      );
// طھط­ط¯ظٹط« ط¥ط¬ظ…ط§ظ„ظٹ ط§ظ„ظ…ط¯ظپظˆط¹ط§طھ ط¯ط§ط®ظ„ repairs ط¨ط¹ط¯ ط¥ط¶ط§ظپط© ط§ظ„ط¯ظپط¹ط©
      final repSvc = await RepairsService.instance();
      await repSvc.updateTotalsFromPayments(_repair.id);

      await _reloadRepair(); // ط¥ط¹ط§ط¯ط© طھط­ظ…ظٹظ„ ط¨ط¹ط¯ طھط­ط¯ظٹط« totals

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'âœ… طھظ… طھط³ط¬ظٹظ„ ط§ظ„ط¯ظپط¹ط©: ${_currency.format(amount)}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('â‌Œ ظپط´ظ„ ط§ظ„ط­ظپط¸: $e')));
    }
  }

  // ===== ط§ظ„طµظˆط± =====
  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage();
    if (picked.isEmpty) return;

    try {
      final svc = await RepairsService.instance();

      // ظ„ط¥ط¸ظ‡ط§ط± ط£ظ† ط§ظ„ظ†ط¸ط§ظ… ظٹط¹ظ…ظ„ ظˆظ„ط§ ظٹط¹ظ„ظ‚
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('âڈ³ ط¬ط§ط±ظٹ ظ…ط¹ط§ظ„ط¬ط© ط§ظ„طµظˆط±...')),
      );

      for (final raw in picked) {
        // 1) ط¶ط؛ط· ط§ظ„طµظˆط±ط©
        final compressed =
            await ImageStorageService.compressImage(XFile(raw.path));

        // 2) ط­ظپط¸ ط§ظ„طµظˆط±ط©
        final savedPath = await ImageStorageService.saveImage(
          image: compressed,
          vehicleType: _repair.vehicleType,
          vehicleNumber: _repair.vehicleNumber,
          beneficiaryName: _repair.beneficiaryName,
          receivedDate: _repair.receivedDate,
        );

        // 3) ط¥ط¶ط§ظپط© ط§ظ„ظ…ط³ط§ط± ط¥ظ„ظ‰ DB
        await svc.addImagePath(repairId: _repair.id, path: savedPath);

        // 4) ط¥ظ†ط´ط§ط، Thumbnail ط¥ط°ط§ ظ„ظٹط³ ظ…ظˆط¬ظˆط¯ظ‹ط§
        if ((_repair.thumbnailPath ?? '').isEmpty) {
          final thumbPath =
              await ImageStorageService.generateThumbnail(savedPath);
          await svc.updateThumbnail(
            repairId: _repair.id,
            thumbPath: thumbPath,
          );
        }
      }

      await _reloadRepair();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('âœ… طھظ… ط­ظپط¸ ط§ظ„طµظˆط±')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('â‌Œ ظپط´ظ„ ط¥ط¶ط§ظپط© ط§ظ„طµظˆط±: $e')));
    }
  }

  Future<void> _deleteImage(String path) async {
    try {
      final svc = await RepairsService.instance();

      // 1) ط­ط°ظپ ظ…ظ† ط§ظ„ظ‚ط±طµ
      await ImageStorageService.deleteImage(path);

      // 2) ط­ط°ظپ ظ…ظ† DB
      await svc.removeImagePath(path: path);

      // 3) ط¥ط²ط§ظ„ط© ط§ظ„ط؛ظ„ط§ظپ ط¥ظ† ظƒط§ظ† ظ‡ظˆ ظ†ظپط³ظ‡
      if (_repair.thumbnailPath == path) {
        await svc.updateThumbnail(
          repairId: _repair.id,
          thumbPath: null,
        );
      }

      await _reloadRepair();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ًں—‘ï¸ڈ طھظ… ط­ط°ظپ ط§ظ„طµظˆط±ط©')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('â‌Œ ظپط´ظ„ ط­ط°ظپ ط§ظ„طµظˆط±ط©: $e')));
    }
  }

// ===============================
// ًں”چ ط¹ط§ط±ط¶ ط§ظ„طµظˆط± ظ…ط¹ ط¯ط¹ظ… ط§ظ„ط£ط³ظ‡ظ… + Delete + ESC
// ===============================
  void _openPreview(List<String> images, int start) {
    int current = start;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dlgCtx) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: Shortcuts(
            shortcuts: <LogicalKeySet, Intent>{
              LogicalKeySet(LogicalKeyboardKey.arrowLeft):
                  const MoveSelectionLeftIntent(),
              LogicalKeySet(LogicalKeyboardKey.arrowRight):
                  const MoveSelectionRightIntent(),
              LogicalKeySet(LogicalKeyboardKey.escape): const DismissIntent(),
              LogicalKeySet(LogicalKeyboardKey.delete):
                  const DeleteImageIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                MoveSelectionLeftIntent:
                    CallbackAction<MoveSelectionLeftIntent>(
                  onInvoke: (intent) {
                    setState(() {
                      current = (current - 1 + images.length) % images.length;
                    });
                    return null;
                  },
                ),
                MoveSelectionRightIntent:
                    CallbackAction<MoveSelectionRightIntent>(
                  onInvoke: (intent) {
                    setState(() {
                      current = (current + 1) % images.length;
                    });
                    return null;
                  },
                ),
                DismissIntent: CallbackAction<DismissIntent>(
                  onInvoke: (intent) {
                    Navigator.pop(dlgCtx);
                    return null;
                  },
                ),
                DeleteImageIntent: CallbackAction<DeleteImageIntent>(
                  onInvoke: (intent) async {
                    final ok = await showDialog<bool>(
                      context: dlgCtx,
                      builder: (_) => AdaptiveAlertDialog(
                        title: const Text('ط­ط°ظپ ط§ظ„طµظˆط±ط©'),
                        content: const Text(
                            'ظ‡ظ„ طھط±ظٹط¯ ط­ط°ظپ ظ‡ط°ظ‡ ط§ظ„طµظˆط±ط© ظ†ظ‡ط§ط¦ظٹظ‹ط§طں'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(_, false),
                            child: const Text('ط¥ظ„ط؛ط§ط،'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(_, true),
                            child: const Text('ط­ط°ظپ'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await _deleteImage(images[current]);
                      Navigator.pop(dlgCtx);
                    }
                    return null;
                  },
                ),
              },
              child: StatefulBuilder(
                builder: (ctx, setDlg) {
                  return SizedBox(
                    width: 900,
                    height: 720,
                    child: Stack(
                      children: [
                        Center(
                          child: InteractiveViewer(
                            minScale: 0.5,
                            maxScale: 5,
                            child: Image.file(
                              File(images[current]),
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),

                        // ط²ط± ط¥ط؛ظ„ط§ظ‚
                        Positioned(
                          top: 10,
                          right: 10,
                          child: IconButton(
                            icon: const Icon(Icons.close,
                                color: Colors.white, size: 30),
                            onPressed: () => Navigator.pop(dlgCtx),
                          ),
                        ),

                        // ط³ظ‡ظ… ظٹط³ط§ط±
                        if (images.length > 1)
                          Positioned(
                            left: 10,
                            top: 0,
                            bottom: 0,
                            child: IconButton(
                              iconSize: 44,
                              icon: const Icon(Icons.arrow_back_ios,
                                  color: Colors.white),
                              onPressed: () {
                                setDlg(() {
                                  current = (current - 1 + images.length) %
                                      images.length;
                                });
                              },
                            ),
                          ),

                        // ط³ظ‡ظ… ظٹظ…ظٹظ†
                        if (images.length > 1)
                          Positioned(
                            right: 10,
                            top: 0,
                            bottom: 0,
                            child: IconButton(
                              iconSize: 44,
                              icon: const Icon(Icons.arrow_forward_ios,
                                  color: Colors.white),
                              onPressed: () {
                                setDlg(() {
                                  current = (current + 1) % images.length;
                                });
                              },
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  // ===== PDF =====
  Future<void> _sharePdf() async {
    try {
      final bytes = await RepairPdfGenerator.generate(_repair);
      final tempDir = await getTemporaryDirectory();
      final path = '${tempDir.path}/repair_${_repair.id}.pdf';
      final file = File(path);
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(path)],
          text: 'ظƒط´ظپ ط¥طµظ„ط§ط­ ط§ظ„ظ…ط±ظƒط¨ط©');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('â‌Œ ظپط´ظ„ ط§ظ„ظ…ط´ط§ط±ظƒط©: $e')));
    }
  }

  Future<void> _printPdf() async {
    try {
      final bytes = await RepairPdfGenerator.generate(_repair);
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('â‌Œ ظپط´ظ„ ط§ظ„ط·ط¨ط§ط¹ط©: $e')));
    }
  }

  Map<String, dynamic> _normalizeRow(Map<String, dynamic> row) {
    final desc = row['name'] ?? row['description'] ?? row['desc'] ?? '';
    final priceRaw = row['price'] ?? row['amount'] ?? row['cost'] ?? 0;
    final price = (priceRaw is num)
        ? priceRaw.toDouble()
        : double.tryParse(priceRaw.toString()) ?? 0.0;
    return {'name': '$desc', 'price': price};
  }

  Widget _buildDataTable(String title, List<Map<String, dynamic>> data) {
    final normalized = data.map(_normalizeRow).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(2)
              },
              border: TableBorder.all(color: Colors.grey),
              children: [
                TableRow(
                  decoration: BoxDecoration(color: Colors.grey[200]),
                  children: const [
                    Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text('ط§ظ„ظˆطµظپ',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text('ط§ظ„ط³ط¹ط±',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                ),
                ...normalized.map((row) => TableRow(children: [
                      Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(row['name'] ?? '')),
                      Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                              MoneyFormatter.format(row['price'] as double))),
                    ])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ط´ط±ظٹط· ط§ظ„طµظˆط±
  Widget _buildImagesStrip() {
    if (_repair.imagePaths.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: AdaptiveRow(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ًں“· طµظˆط± ط§ظ„ظ…ط±ظƒط¨ط©',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.add_a_photo),
                onPressed: _pickImages,
                tooltip: 'ط¥ط¶ط§ظپط© طµظˆط±',
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdaptiveRow(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('ًں“· طµظˆط± ط§ظ„ظ…ط±ظƒط¨ط©',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.add_a_photo),
                  onPressed: _pickImages,
                  tooltip: 'ط¥ط¶ط§ظپط© طµظˆط±',
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 130,
              child: ScrollConfiguration(
                behavior: const ScrollBehavior().copyWith(overscroll: false),
                child: Scrollbar(
                  controller: _imagesScrollCtrl,
                  thumbVisibility: true,
                  child: ListView.separated(
                    controller: _imagesScrollCtrl,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: _repair.imagePaths.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (ctx, idx) {
                      final path = _repair.imagePaths[idx];
                      return GestureDetector(
                        onTap: () => _openPreview(_repair.imagePaths, idx),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.file(
                                File(
                                    path), // â†گ ط§ظ„طµظˆط±ط© ط§ظ„طµط­ظٹط­ط© ظˆظ„ظٹط³ ط§ظ„ظ€ thumbnail
                                key: ValueKey(path),
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: GestureDetector(
                                onTap: () async {
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (_) => AdaptiveAlertDialog(
                                      title: const Text('ط­ط°ظپ ط§ظ„طµظˆط±ط©'),
                                      content: const Text(
                                          'طھط£ظƒظٹط¯ ط­ط°ظپ ظ‡ط°ظ‡ ط§ظ„طµظˆط±ط©طں'),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(_, false),
                                            child: const Text('ط¥ظ„ط؛ط§ط،')),
                                        ElevatedButton(
                                            onPressed: () =>
                                                Navigator.pop(_, true),
                                            child: const Text('ط­ط°ظپ')),
                                      ],
                                    ),
                                  );
                                  if (ok == true) {
                                    await _deleteImage(path);
                                  }
                                },
                                child: const CircleAvatar(
                                  radius: 12,
                                  backgroundColor: Colors.black54,
                                  child: Icon(Icons.close,
                                      color: Colors.white, size: 16),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== ظ„ظˆط­ط© ط§ظ„ط­ط§ظ„ط© â€” ظ†طµظپ ط§ظ„ظ…ط³ط§ط­ط© ظ„ظƒظ„ ظ‚ط§ط¦ظ…ط©طŒ ط¬ظ†ط¨ ط¨ط¹ط¶ =====
  Widget _buildStatusPanel() {
    final currentInsurance =
        normalizeOrNull(_repair.insuranceStatus, _insuranceOptions) ??
            _repair.insuranceStatus;
    final currentVehicle =
        normalizeOrNull(_repair.vehicleStatus, _vehicleOptions) ??
            _repair.vehicleStatus;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: AdaptiveRow(
          children: [
            // ط­ط§ظ„ط© ط§ظ„طھط£ظ…ظٹظ†
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('ط­ط§ظ„ط© ط§ظ„طھط£ظ…ظٹظ†',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _insuranceOptions.contains(currentInsurance)
                        ? currentInsurance
                        : null,
                    items: _insuranceOptions
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (v) {
                      if (v != null) _updateInsuranceStatus(v);
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(width: 16),

            // ط­ط§ظ„ط© ط§ظ„ظ…ط±ظƒط¨ط©
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('ط­ط§ظ„ط© ط§ظ„ظ…ط±ظƒط¨ط©',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _vehicleOptions.contains(currentVehicle)
                        ? currentVehicle
                        : null,
                    items: _vehicleOptions
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (v) {
                      if (v != null) _updateVehicleStatus(v);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ط´ط±ظٹط· ط§ظ„ط¥ط¬ط±ط§ط،ط§طھ
  Widget _buildActionsBar() {
    final remaining = (_repair.totalFileValue) - (_repair.totalPaidAmount);
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: AdaptiveRow(
          children: [
            Expanded(
              child: Text(
                'ط§ظ„ظ…طھط¨ظ‚ظٹ: ${MoneyFormatter.format(remaining)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: 8),
            const Padding(
              padding: EdgeInsetsDirectional.only(start: 8),
              child: Text('âœ… طھظ… ط§ظ„ط§ط¹طھظ…ط§ط¯ ط§ظ„ظ…ط­ط§ط³ط¨ظٹ',
                  style: TextStyle(color: Colors.green)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneDetails({
    required String repairType,
    required String vehicleStatus,
    required String insuranceStatus,
    required bool hasInvoice,
    required String? thumb,
  }) {
    final remaining = _repair.remainingAmount;

    Widget metric(String label, String value, IconData icon) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.lightGrey),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(icon, color: AppColors.primary, size: 21),
              const SizedBox(height: 10),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: ui.TextDirection.ltr,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ),
      );
    }

    Widget infoRow(String label, String value, IconData icon) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value.isEmpty ? 'â€”' : value,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(label, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(
          _repair.vehicleNumber.isEmpty
              ? 'طھظپط§طµظٹظ„ ظ…ظ„ظپ ط§ظ„ط¥طµظ„ط§ط­'
              : _repair.vehicleNumber,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) async {
              if (value == 'share') {
                await _sharePdf();
              } else if (value == 'print') {
                await _printPdf();
              } else if (value == 'save') {
                try {
                  final file =
                      await RepairPdfGenerator.saveToFileAndOpen(_repair);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('طھظ… ط¥ظ†ط´ط§ط، PDF: ${file.path}')),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('ظپط´ظ„ ط¥ظ†ط´ط§ط، PDF: $e')),
                  );
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'share',
                child: ListTile(
                  leading: Icon(Icons.ios_share_rounded),
                  title: Text('ظ…ط´ط§ط±ظƒط© PDF'),
                ),
              ),
              PopupMenuItem(
                value: 'save',
                child: ListTile(
                  leading: Icon(Icons.picture_as_pdf_outlined),
                  title: Text('ظ…ط¹ط§ظٹظ†ط© / ط­ظپط¸ PDF'),
                ),
              ),
              PopupMenuItem(
                value: 'print',
                child: ListTile(
                  leading: Icon(Icons.print_outlined),
                  title: Text('ط·ط¨ط§ط¹ط©'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _reloadRepair,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            if (thumb != null && File(thumb).existsSync())
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.file(
                  File(thumb),
                  height: 185,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            if (thumb != null) const SizedBox(height: 12),
            Row(
              children: [
                metric(
                  'ظ‚ظٹظ…ط© ط§ظ„ظ…ظ„ظپ',
                  MoneyFormatter.format(_repair.totalFileValue),
                  Icons.receipt_long_outlined,
                ),
                const SizedBox(width: 10),
                metric(
                  'ط§ظ„ظ…ط¯ظپظˆط¹',
                  MoneyFormatter.format(_repair.totalPaidAmount),
                  Icons.payments_outlined,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                metric(
                  'ط§ظ„ظ…طھط¨ظ‚ظٹ',
                  MoneyFormatter.format(remaining),
                  Icons.account_balance_wallet_outlined,
                ),
                const SizedBox(width: 10),
                metric(
                  'ط§ظ„ط­ط§ظ„ط©',
                  vehicleStatus,
                  Icons.car_repair_outlined,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: AppColors.lightGrey),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    infoRow(
                        'ط§ظ„ظ…ط±ظƒط¨ط©',
                        '${_repair.vehicleType} ${_repair.vehicleModel}',
                        Icons.directions_car_outlined),
                    const Divider(height: 1),
                    infoRow('ط§ظ„ظ…ط³طھظپظٹط¯', _repair.beneficiaryName,
                        Icons.person_outline_rounded),
                    const Divider(height: 1),
                    infoRow('ظ†ظˆط¹ ط§ظ„ط¥طµظ„ط§ط­', repairType,
                        Icons.build_outlined),
                    const Divider(height: 1),
                    infoRow(
                        'طھط§ط±ظٹط® ط§ظ„ط§ط³طھظ„ط§ظ…',
                        _df.format(_repair.receivedDate),
                        Icons.calendar_today_outlined),
                    if (_repair.beneficiaryType == 'ط´ط±ظƒط© طھط£ظ…ظٹظ†') ...[
                      const Divider(height: 1),
                      infoRow('ط§ظ„طھط£ظ…ظٹظ†', insuranceStatus,
                          Icons.shield_outlined),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            _buildStatusPanel(),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size.fromHeight(50),
                    ),
                    onPressed: _addPayment,
                    icon: const Icon(Icons.add_card_rounded),
                    label: const Text('ط¥ط¶ط§ظپط© ط¯ظپط¹ط©'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    onPressed: _pickImages,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('ط¥ط¶ط§ظپط© طµظˆط±'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildImagesStrip(),
            const SizedBox(height: 14),
            _buildDataTable('ط£ط¹ظ…ط§ظ„ ط§ظ„ط¥طµظ„ط§ط­', _repairWorks),
            const SizedBox(height: 12),
            _buildDataTable('ط§ظ„ظ‚ط·ط¹ ط§ظ„ظ…ط·ظ„ظˆط¨ط©', _repairParts),
            const SizedBox(height: 14),
            _buildActionsBar(),
            if (hasInvoice) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pushNamed(
                  AppRoutes.invoiceView,
                  arguments: _repair.invoiceId!,
                ),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('ط¹ط±ط¶ ط§ظ„ظپط§طھظˆط±ط©'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 1000;
    final f = DateFormat('yyyy-MM-dd');
    final String? firstImg =
        _repair.imagePaths.isNotEmpty ? _repair.imagePaths.first : null;

// ط¥ط°ط§ ظƒط§ظ† ظ„ظ„ظ…ظ„ظپ طµظˆط±ط© ط؛ظ„ط§ظپ ظ…ظˆط¬ظˆط¯ط© ظپظٹ ظ‚ط§ط¹ط¯ط© ط§ظ„ط¨ظٹط§ظ†ط§طھ â†’ ط§ط³طھط®ط¯ظ…ظ‡ط§
    final String? thumb = _repair.thumbnailPath?.isNotEmpty == true
        ? _repair.thumbnailPath
        : firstImg;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final repairType =
        normalizeOrNull(_repair.repairType, kRepairTypes) ?? _repair.repairType;
    final vehicleStatus = normalizeValue(
            _repair.vehicleStatus, kVehicleStatuses,
            aliases: kVehicleStatusAliases) ??
        _repair.vehicleStatus;
    final insuranceStatus =
        normalizeOrNull(_repair.insuranceStatus, _insuranceOptions) ??
            _repair.insuranceStatus;

    final hasInvoice =
        (_repair.invoiceId != null && _repair.invoiceId!.trim().isNotEmpty);

    if (MediaQuery.sizeOf(context).width < 600) {
      return _buildPhoneDetails(
        repairType: repairType,
        vehicleStatus: vehicleStatus,
        insuranceStatus: insuranceStatus,
        hasInvoice: hasInvoice,
        thumb: thumb,
      );
    }

    return Scaffold(
      body: AdaptiveRow(
        children: [
          const YallaSidebar(currentRoute: AppRoutes.repairDetail),
          Expanded(
            child: Scaffold(
              appBar: AppBar(
                title: const Text('طھظپط§طµظٹظ„ ط¥طµظ„ط§ط­ ط§ظ„ظ…ط±ظƒط¨ط©'),
                actions: [
                  IconButton(
                    tooltip: 'ط­ظپط¸ ظ…ظ„ظپ PDF ظˆظپطھط­ظ‡',
                    icon: const Icon(Icons.picture_as_pdf),
                    onPressed: () async {
                      try {
                        final file =
                            await RepairPdfGenerator.saveToFileAndOpen(_repair);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                                'âœ… طھظ… ط§ظ„ط­ظپط¸ ظˆط§ظ„ظپطھط­:\n${file.path}')));
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('â‌Œ ظپط´ظ„ ط¥ظ†ط´ط§ط، PDF: $e')));
                      }
                    },
                  ),
                  IconButton(
                      tooltip: 'ظ…ط´ط§ط±ظƒط© PDF',
                      icon: const Icon(Icons.share),
                      onPressed: _sharePdf),
                  IconButton(
                      tooltip: 'ط·ط¨ط§ط¹ط©',
                      icon: const Icon(Icons.print),
                      onPressed: _printPdf),
                ],
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: isWide
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ط§ظ„طµظپ ط§ظ„ط¹ظ„ظˆظٹ
                          AdaptiveRow(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ط§ظ„ط¹ظ…ظˆط¯ ط§ظ„ط£ظٹط³ط±: ط§ظ„ظ…ط§ظ„ظٹط© + ظ„ظˆط­ط© ط§ظ„ط­ط§ظ„ط©
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Card(
                                      child: ListTile(
                                        leading: RepairThumb(
                                          repairId: _repair.id,
                                          fallbackFirstPath:
                                              thumb, // â†گ ط§ط³طھط¨ط¯ظ„ظ†ط§ firstImg ط¨ط§ظ„ظ€ thumbnail
                                          size: 56,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        title: const Text(
                                            'ط§ظ„ط¨ظٹط§ظ†ط§طھ ط§ظ„ظ…ط§ظ„ظٹط© ًں’°'),
                                        subtitle: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                                'ط­ط§ظ„ط© ط§ظ„ط³ط¯ط§ط¯: ${_repair.displayPaymentStatus}'),
                                            Text(
                                                'ظ‚ظٹظ…ط© ط§ظ„ظ…ظ„ظپ: ${MoneyFormatter.format(_repair.totalFileValue)}'),
                                            Text(
                                                'ط§ظ„ظ…ط¯ظپظˆط¹: ${MoneyFormatter.format(_repair.totalPaidAmount)}'),
                                            Text(
                                                'ط§ظ„ظ…طھط¨ظ‚ظٹ: ${MoneyFormatter.format(_repair.remainingAmount)}'),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    _buildStatusPanel(),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 24),
                              // ط§ظ„ط¹ظ…ظˆط¯ ط§ظ„ط£ظٹظ…ظ†: ط¨ظٹط§ظ†ط§طھ ط§ظ„ظ…ط±ظƒط¨ط© ظˆط§ظ„ظ…ط³طھظپظٹط¯ + ط§ظ„ظپط§طھظˆط±ط©/GL
                              Expanded(
                                flex: 4,
                                child: Card(
                                  child: ListTile(
                                    title: const Text(
                                        'ط¨ظٹط§ظ†ط§طھ ط§ظ„ظ…ط±ظƒط¨ط© ظˆط§ظ„ظ…ط³طھظپظٹط¯'),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('ظ†ظˆط¹: ${_repair.vehicleType}'),
                                        Text(
                                            'ط§ظ„ظ…ظˆط¯ظٹظ„: ${_repair.vehicleModel}'),
                                        Text(
                                            'ط±ظ‚ظ…: ${_repair.vehicleNumber}'),
                                        Text(
                                            'طھط§ط±ظٹط® ط§ظ„ط§ط³طھظ„ط§ظ…: ${f.format(_repair.receivedDate)}'),
                                        Text('ظ†ظˆط¹ ط§ظ„ط¹ظ…ظ„: $repairType'),
                                        Text(
                                            'ط­ط§ظ„ط© ط§ظ„ظ…ط±ظƒط¨ط©: $vehicleStatus'),
                                        const SizedBox(height: 8),
                                        Text(
                                            'ظ†ظˆط¹ ط§ظ„ظ…ط³طھظپظٹط¯: ${_repair.beneficiaryType}'),
                                        Text(
                                            'ط§ظ„ط§ط³ظ…: ${_repair.beneficiaryName}'),
                                        if (_repair.beneficiaryType ==
                                            'ط´ط±ظƒط© طھط£ظ…ظٹظ†')
                                          Text(
                                              'ظ…طھط§ط¨ط¹ط© ط§ظ„طھط£ظ…ظٹظ†: $insuranceStatus'),
                                        const SizedBox(height: 12),
                                        if (hasInvoice)
                                          if (!hasInvoice)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 12),
                                              child: OutlinedButton.icon(
                                                icon: const Icon(
                                                    Icons.playlist_add),
                                                label: const Text(
                                                    'ط¥ظ†ط´ط§ط، ظپط§طھظˆط±ط© ظˆطھط±ط­ظٹظ„ GL'),
                                                onPressed: () async {
                                                  try {
                                                    final db = await DBService
                                                        .database;

                                                    // 1) ط¥ظ†ط´ط§ط، ظپط§طھظˆط±ط© ط¬ط¯ظٹط¯ط©
                                                    final invoiceId =
                                                        await DBService
                                                            .createInvoiceForRepair(
                                                      repairId: _repair.id,
                                                      clientId:
                                                          _repair.clientId,
                                                      total: _repair
                                                          .totalFileValue,
                                                    );

                                                    // 2) طھط­ط¯ظٹط« repair â†’ invoiceId
                                                    await db.update(
                                                      'repairs',
                                                      {
                                                        'invoice_id': invoiceId,
                                                        'invoiceId': invoiceId
                                                      },
                                                      where: 'id = ?',
                                                      whereArgs: [_repair.id],
                                                    );

                                                    // 3) طھط±ط­ظٹظ„ ظ‚ظٹط¯ GL
                                                    final glId = await DBService
                                                        .postInvoiceGLFromId(
                                                            invoiceId);

                                                    // 4) ط¥ط¹ط§ط¯ط© طھط­ظ…ظٹظ„ ط§ظ„ط¨ظٹط§ظ†ط§طھ
                                                    await _reloadRepair();

                                                    if (!mounted) return;

                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                            'طھظ… ط¥ظ†ط´ط§ط، ط§ظ„ظپط§طھظˆط±ط© ظˆطھط±ط­ظٹظ„ GL (#$glId)'),
                                                      ),
                                                    );
                                                  } catch (e) {
                                                    if (!mounted) return;
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                      SnackBar(
                                                          content: Text(
                                                              'ظپط´ظ„ ط§ظ„ط¹ظ…ظ„ظٹط©: $e')),
                                                    );
                                                  }
                                                },
                                              ),
                                            ),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            ElevatedButton.icon(
                                              icon: const Icon(
                                                  Icons.receipt_long),
                                              label: const Text(
                                                  'ط¹ط±ط¶ ط§ظ„ظپط§طھظˆط±ط©'),
                                              onPressed: () {
                                                Navigator.of(context).pushNamed(
                                                  AppRoutes.invoiceView,
                                                  arguments: _repair.invoiceId!,
                                                );
                                              },
                                            ),
                                            if (_invoiceGlEntryId == null)
                                              OutlinedButton.icon(
                                                icon: const Icon(
                                                    Icons.playlist_add),
                                                label: const Text(
                                                    'طھط±ط­ظٹظ„ GL ظ„ظ„ظپط§طھظˆط±ط©'),
                                                onPressed:
                                                    _postInvoiceGLIfMissing,
                                              )
                                            else ...[
                                              ElevatedButton.icon(
                                                icon: const Icon(
                                                    Icons.account_balance),
                                                label: Text(
                                                    'ط¹ط±ط¶ ظ‚ظٹط¯ GL #$_invoiceGlEntryId'),
                                                onPressed: () {
                                                  Navigator.of(context)
                                                      .pushNamed(
                                                    AppRoutes.financeGL,
                                                    arguments: {
                                                      'entryId':
                                                          _invoiceGlEntryId
                                                    },
                                                  );
                                                },
                                              ),
                                              OutlinedButton.icon(
                                                icon: const Icon(
                                                    Icons.travel_explore),
                                                label: const Text(
                                                    'ظپطھط­ GL Browser'),
                                                onPressed: () {
                                                  Navigator.of(context)
                                                      .pushNamed(
                                                    AppRoutes.financeGL,
                                                    arguments: {
                                                      'source': 'INVOICE',
                                                      'source_id':
                                                          _repair.invoiceId
                                                    },
                                                  );
                                                },
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // ط´ط±ظٹط· ط§ظ„ط¥ط¬ط±ط§ط،ط§طھ
                          _buildActionsBar(),

                          const SizedBox(height: 16),

                          // ط´ط±ظٹط· ط§ظ„طµظˆط±
                          _buildImagesStrip(),

                          const SizedBox(height: 16),

                          // ط§ظ„ط¬ط¯ط§ظˆظ„
                          _buildDataTable(
                              'ط£ط¹ظ…ط§ظ„ ط§ظ„ط¥طµظ„ط§ط­', _repairWorks),
                          const SizedBox(height: 16),
                          _buildDataTable(
                              'ط§ظ„ظ‚ط·ط¹ ط§ظ„ظ…ط·ظ„ظˆط¨ط©', _repairParts),
                        ],
                      )
                    : const Center(
                        child: Text('ط§ظ„ط´ط§ط´ط© طµط؛ظٹط±ط© ط¬ط¯ظ‹ط§')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PayMethod {
  final String key; // 'cash' | 'bank'
  final String label;
  const _PayMethod(this.key, this.label);
}
// ===============================
// ًں”‘ Intents (Top-Level)
// ===============================

class MoveSelectionLeftIntent extends Intent {
  const MoveSelectionLeftIntent();
}

class MoveSelectionRightIntent extends Intent {
  const MoveSelectionRightIntent();
}

class DismissIntent extends Intent {
  const DismissIntent();
}

class DeleteImageIntent extends Intent {
  const DeleteImageIntent();
}
