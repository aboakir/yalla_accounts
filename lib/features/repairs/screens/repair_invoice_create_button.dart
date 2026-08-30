// 📁 lib/features/repairs/screens/repair_invoice_create_button.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/finance/invoices/services/invoice_service.dart';

class RepairInvoiceCreateButton extends StatefulWidget {
  final String repairId;
  final VoidCallback? onCreated;
  final bool dense;

  const RepairInvoiceCreateButton({
    super.key,
    required this.repairId,
    this.onCreated,
    this.dense = false,
  });

  @override
  State<RepairInvoiceCreateButton> createState() =>
      _RepairInvoiceCreateButtonState();
}

class _RepairInvoiceCreateButtonState extends State<RepairInvoiceCreateButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final label = _busy ? 'Creating...' : 'Create Invoice';
    final icon = const Icon(Icons.request_quote);

    return widget.dense
        ? TextButton.icon(
            onPressed: _busy ? null : _handleCreate,
            icon: icon,
            label: Text(label),
          )
        : ElevatedButton.icon(
            onPressed: _busy ? null : _handleCreate,
            icon: icon,
            label: Text(label),
          );
  }

  Future<void> _handleCreate() async {
    setState(() => _busy = true);
    try {
      final exists = await _getExistingInvoiceId(widget.repairId);
      if (exists != null) {
        if (!mounted) return;
        _snack(context, 'Invoice exists: $exists');
        setState(() => _busy = false);
        return;
      }

      final db = await DBService.database;

      final info = await _loadRepairInfo(db, widget.repairId);
      if (info == null) throw StateError('Repair not found');

      final clientId = info.clientId;
      final total = await _computeRepairTotal(db, widget.repairId, info);
      if (total <= 0) throw StateError('Total is zero');

      final invId = await InvoiceService.I.createInvoice(
        repairId: widget.repairId,
        date: DateTime.now(),
        total: _round(total),
        status: 'unpaid',
        notes:
            'Invoice repair ${widget.repairId} at ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
        clientId: clientId,
        postToGL: true,
      );

      await db.update(
        'repairs',
        {'invoiceId': invId},
        where: 'id = ?',
        whereArgs: [widget.repairId],
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      if (!mounted) return;
      _snack(context, 'Invoice created: $invId');
      widget.onCreated?.call();
    } catch (e) {
      if (!mounted) return;
      _snack(context, 'Error: $e', isErr: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _getExistingInvoiceId(String repairId) async {
    final inv = await InvoiceService.I.getByRepairId(repairId);
    return inv?['id'] as String?;
  }

  Future<_RepairInfo?> _loadRepairInfo(Database db, String repairId) async {
    final rows = await db.query(
      'repairs',
      columns: [
        'id',
        'client_id',
        'finalApprovedAmount',
        'incomeAmount',
        'workCost',
        'fileValue',
      ],
      where: 'id = ?',
      whereArgs: [repairId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final m = rows.first;

    double d(Object? v) =>
        v is num ? v.toDouble() : (double.tryParse(v?.toString() ?? '') ?? 0);

    int? i(Object? v) {
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString());
    }

    return _RepairInfo(
      id: m['id'] as String,
      clientId: i(m['client_id']),
      finalApprovedAmount: d(m['finalApprovedAmount']),
      incomeAmount: d(m['incomeAmount']),
      workCost: d(m['workCost']),
      fileValue: d(m['fileValue']),
    );
  }

  Future<double> _computeRepairTotal(
      Database db, String repairId, _RepairInfo info) async {
    final r = await db.rawQuery(
      'SELECT IFNULL(SUM(total),0) AS s FROM repair_lines WHERE repair_id=?',
      [repairId],
    );
    final s = r.first['s'];
    final lines = s is num ? s.toDouble() : (double.tryParse('$s') ?? 0);

    if (lines > 0) return lines;

    return [
      info.incomeAmount,
      info.finalApprovedAmount,
      info.workCost,
      info.fileValue,
    ].fold<double>(0, (m, v) => v > m ? v : m);
  }

  double _round(double v) => double.parse(v.toStringAsFixed(2));

  void _snack(BuildContext ctx, String msg, {bool isErr = false}) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isErr ? Colors.red : null,
      ),
    );
  }
}

class _RepairInfo {
  final String id;
  final int? clientId;
  final double finalApprovedAmount;
  final double incomeAmount;
  final double workCost;
  final double fileValue;

  _RepairInfo({
    required this.id,
    required this.clientId,
    required this.finalApprovedAmount,
    required this.incomeAmount,
    required this.workCost,
    required this.fileValue,
  });
}
