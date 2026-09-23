import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yalla_accounts/core/platform/yalla_path_provider.dart';
import 'package:yalla_accounts/core/utils/user_facing_error.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:yalla_accounts/core/pdf/yalla_pdf_print_service.dart';

import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/features/auth/services/permission_service.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_pdf_report_service.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_trace_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

class ChequesReportScreen extends StatefulWidget {
  const ChequesReportScreen({super.key});

  @override
  State<ChequesReportScreen> createState() => _ChequesReportScreenState();
}

class _ChequesReportScreenState extends State<ChequesReportScreen> {
  final _search = TextEditingController();
  final _permissions = PermissionService();
  ChequePdfReportKind _kind = ChequePdfReportKind.incoming;
  late Future<List<Cheque>> _rows;
  bool _canPrint = false;
  bool _canView = false;
  bool _permissionsLoaded = false;
  bool _busyExport = false;
  bool _showAdvancedFilters = false;
  final _currency = TextEditingController();
  ChequeStatus? _statusFilter;
  final _date = DateFormat('yyyy-MM-dd');
  final _money = NumberFormat('#,##0.00', 'ar');

  @override
  void initState() {
    super.initState();
    _rows = Future.value(const <Cheque>[]);
    _loadPermissions();
  }

  @override
  void dispose() {
    _search.dispose();
    _currency.dispose();
    super.dispose();
  }

  Future<void> _loadPermissions() async {
    try {
      final report =
          await _permissions.canCurrent(PermissionKeys.chequeReportView);
      final print = await _permissions.canCurrent(PermissionKeys.chequePrint);
      if (!mounted) return;
      setState(() {
        _permissionsLoaded = true;
        _canView = report;
        _canPrint = report && print;
        if (report) _reload();
      });
    } catch (_) {
      if (mounted) setState(() => _permissionsLoaded = true);
    }
  }

  void _reload() {
    final q = _search.text.trim();
    final kind = _kind;
    final currency = _currency.text;
    final status = _statusFilter;
    _rows = (() async {
      final allowed = await ChequePdfReportService.loadRows(kind);
      final ids = q.isEmpty
          ? null
          : (await ChequeTraceService.search(q)).map((c) => c.id).toSet();
      return ChequePdfReportService.filterRows(
        allowed.where((c) => ids == null || ids.contains(c.id)),
        currency: currency,
        status: status,
      );
    })();
  }

  Future<void> _printPdf() async {
    if (_busyExport) return;
    final kind = _kind;
    final snapshot = _rows;
    setState(() => _busyExport = true);
    try {
      final canView =
          await _permissions.canCurrent(PermissionKeys.chequeReportView);
      final canPrint =
          await _permissions.canCurrent(PermissionKeys.chequePrint);
      if (!canView || !canPrint) {
        throw StateError('لا تملك صلاحية تصدير التقرير.');
      }
      final rows = await snapshot;
      final pdf =
          await ChequePdfReportService.buildDocument(kind, rowSnapshot: rows);
      final bytes = await pdf.save();
      final directory = await getDownloadsDirectory();
      if (directory == null) throw StateError('تعذر تجهيز مجلد التصدير.');
      final filename =
          'cheques_report_${kind.name}_${DateTime.now().microsecondsSinceEpoch}.pdf';
      await File(p.join(directory.path, filename))
          .writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      if (Platform.isIOS || Platform.isAndroid) {
        await Printing.sharePdf(bytes: bytes, filename: filename);
      } else {
        await YallaPdfPrintService.layoutPdf(name: filename, onLayout: (_) async => bytes);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(UserFacingError.message(e))));
      }
    } finally {
      if (mounted) setState(() => _busyExport = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);
    return Scaffold(
      appBar: AppBar(title: const Text('تقارير الشيكات')),
      drawer: desktop
          ? null
          : const YallaSidebar(currentRoute: AppRoutes.chequesReport),
      body: AdaptiveRow(children: [
        if (desktop) const YallaSidebar(currentRoute: AppRoutes.chequesReport),
        Expanded(
          child: !_permissionsLoaded
              ? const Center(child: CircularProgressIndicator())
              : !_canView
                  ? const Center(
                      child: Text('لا تملك صلاحية عرض تقارير الشيكات.'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _filters(),
                          const SizedBox(height: 12),
                          FutureBuilder<List<Cheque>>(
                              future: _rows,
                              builder: (context, snap) {
                                if (snap.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Center(
                                      child: CircularProgressIndicator());
                                }
                                if (snap.hasError) {
                                  return Text(
                                      UserFacingError.message(snap.error!));
                                }
                                final rows = snap.data ?? const <Cheque>[];
                                if (rows.isEmpty) {
                                  return const Padding(
                                      padding: EdgeInsets.all(24),
                                      child: Text('لا توجد نتائج'));
                                }
                                return _reportTable(rows);
                              }),
                        ],
                      )),
        ),
      ]),
    );
  }

  Widget _filters() => LayoutBuilder(builder: (context, constraints) {
        final phone = context.isPhoneWidth;
        final width =
            phone || constraints.maxWidth < 300 ? constraints.maxWidth : 260.0;
        return Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                  width: width,
                  child: DropdownButtonFormField<ChequePdfReportKind>(
                    value: _kind,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'نوع التقرير'),
                    items: [
                      for (final kind in ChequePdfReportKind.values)
                        DropdownMenuItem(
                            value: kind, child: Text(_kindLabel(kind)))
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _kind = value;
                          _reload();
                        });
                      }
                    },
                  )),
              if (context.isPhoneWidth) ...[
                OutlinedButton.icon(
                  onPressed: () => setState(
                      () => _showAdvancedFilters = !_showAdvancedFilters),
                  icon: Icon(
                      _showAdvancedFilters ? Icons.expand_less : Icons.tune),
                  label: const Text('فلاتر متقدمة'),
                ),
              ],
              if (!phone || _showAdvancedFilters) ...[
                SizedBox(
                    width: width,
                    child: TextField(
                      controller: _search,
                      decoration: InputDecoration(
                          labelText: 'رقم الشيك / الطرف / البنك / المرجع',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: IconButton(
                              icon: const Icon(Icons.search),
                              onPressed: () => setState(_reload))),
                      onSubmitted: (_) => setState(_reload),
                    )),
                SizedBox(
                    width: width,
                    child: TextField(
                      controller: _currency,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                          labelText: 'رمز العملة — فارغ لعرض الكل'),
                      onSubmitted: (_) => setState(_reload),
                    )),
                SizedBox(
                    width: width,
                    child: DropdownButtonFormField<ChequeStatus>(
                      value: _statusFilter,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'الحالة'),
                      items: [
                        const DropdownMenuItem<ChequeStatus>(
                            value: null, child: Text('كل الحالات')),
                        for (final status in ChequeStatus.values)
                          DropdownMenuItem(
                              value: status, child: Text(_status(status)))
                      ],
                      onChanged: (value) => setState(() {
                        _statusFilter = value;
                        _reload();
                      }),
                    )),
                TextButton(
                    onPressed: () => setState(() {
                          _search.clear();
                          _currency.clear();
                          _statusFilter = null;
                          _reload();
                        }),
                    child: const Text('مسح الفلاتر')),
              ],
              if (_canPrint)
                FilledButton.icon(
                  onPressed: _busyExport ? null : _printPdf,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: Text(_busyExport ? 'جاري التجهيز' : 'PDF'),
                ),
            ]);
      });

  Widget _reportTable(List<Cheque> rows) {
    final table = AdaptiveDataTable(
      columns: const [
        DataColumn(label: Text('رقم الشيك')),
        DataColumn(label: Text('الاتجاه')),
        DataColumn(label: Text('الساحب/المستفيد')),
        DataColumn(label: Text('البنك')),
        DataColumn(label: Text('القيمة')),
        DataColumn(label: Text('الاستحقاق')),
        DataColumn(label: Text('الحالة')),
        DataColumn(label: Text('المرجع')),
      ],
      rows: [
        for (final c in rows)
          DataRow(cells: [
            DataCell(Text(c.chequeNo)),
            DataCell(Text(
                c.direction == ChequeDirection.received ? 'وارد' : 'صادر')),
            DataCell(Text(c.direction == ChequeDirection.received
                ? c.drawerName
                : (c.recipientName ?? '—'))),
            DataCell(Text(c.bankName)),
            DataCell(Text('${_money.format(c.amount)} ${c.currency}')),
            DataCell(Text(_date.format(c.dueDate))),
            DataCell(Text(_status(c.status))),
            DataCell(Text(_reference(c))),
          ]),
      ],
    );
    if (context.isPhoneWidth) return table;
    return SingleChildScrollView(
        scrollDirection: Axis.horizontal, child: table);
  }

  String _reference(Cheque c) {
    if (c.receiptVoucherId != null) return 'RC-${c.receiptVoucherId}';
    if ((c.paymentVoucherId ?? '').trim().isNotEmpty) {
      return c.paymentVoucherId!;
    }
    return '${c.sourceType ?? ''}/${c.sourceId ?? ''}';
  }

  String _kindLabel(ChequePdfReportKind kind) {
    switch (kind) {
      case ChequePdfReportKind.incoming:
        return 'الشيكات الواردة';
      case ChequePdfReportKind.outgoing:
        return 'الشيكات الصادرة';
      case ChequePdfReportKind.due:
        return 'الاستحقاق';
      case ChequePdfReportKind.deposited:
        return 'الإيداعات';
      case ChequePdfReportKind.returned:
        return 'المرتجعات';
    }
  }

  String _status(ChequeStatus status) {
    switch (status) {
      case ChequeStatus.pending:
        return 'قديم/معلّق';
      case ChequeStatus.received:
        return 'مستلم';
      case ChequeStatus.held:
        return 'محتفظ به';
      case ChequeStatus.deposited:
        return 'مودع';
      case ChequeStatus.collected:
        return 'محصل';
      case ChequeStatus.endorsed:
        return 'مظهر';
      case ChequeStatus.issued:
        return 'صادر';
      case ChequeStatus.delivered:
        return 'مسلّم';
      case ChequeStatus.presented:
        return 'مقدم/مستحق';
      case ChequeStatus.cleared:
        return 'مصروف';
      case ChequeStatus.returned:
        return 'راجع';
      case ChequeStatus.cancelled:
        return 'ملغى';
    }
  }
}
