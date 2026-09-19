import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

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
  final _date = DateFormat('yyyy-MM-dd');
  final _money = NumberFormat('#,##0.00', 'ar');

  @override
  void initState() {
    super.initState();
    _reload();
    _loadPermissions();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadPermissions() async {
    final report =
        await _permissions.canCurrent(PermissionKeys.chequeReportView);
    final print = await _permissions.canCurrent(PermissionKeys.chequePrint);
    if (!mounted) return;
    if (!report) {
      setState(() => _canPrint = false);
      return;
    }
    setState(() => _canPrint = print);
  }

  void _reload() {
    final q = _search.text.trim();
    if (q.isEmpty) {
      _rows = ChequePdfReportService.loadRows(_kind);
    } else {
      _rows = ChequeTraceService.search(q).then((all) async {
        final allowed = await ChequePdfReportService.loadRows(_kind);
        final ids = allowed.map((e) => e.id).toSet();
        return all.where((e) => ids.contains(e.id)).toList();
      });
    }
  }

  Future<void> _printPdf() async {
    await Printing.layoutPdf(
      name: 'Yallah_Cheques_${_kind.name}.pdf',
      onLayout: (_) => ChequePdfReportService.generate(_kind),
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);
    return Scaffold(
      appBar: AppBar(title: const Text('تقارير الشيكات')),
      drawer: desktop
          ? null
          : const YallaSidebar(currentRoute: AppRoutes.chequesReport),
      body: AdaptiveRow(
        children: [
          if (desktop)
            const YallaSidebar(currentRoute: AppRoutes.chequesReport),
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 260,
                        child: DropdownButtonFormField<ChequePdfReportKind>(
                          value: _kind,
                          isExpanded: true,
                          decoration:
                              const InputDecoration(labelText: 'نوع التقرير'),
                          items: [
                            for (final kind in ChequePdfReportKind.values)
                              DropdownMenuItem(
                                  value: kind, child: Text(_kindLabel(kind))),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _kind = v;
                              _reload();
                            });
                          },
                        ),
                      ),
                      SizedBox(
                        width: 320,
                        child: TextField(
                          controller: _search,
                          decoration: const InputDecoration(
                            labelText:
                                'رقم الشيك / الطرف / البنك / السند / الملف / الفاتورة',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onSubmitted: (_) => setState(_reload),
                        ),
                      ),
                      if (_canPrint)
                        FilledButton.icon(
                          onPressed: _printPdf,
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text('PDF'),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: FutureBuilder<List<Cheque>>(
                    future: _rows,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return Center(
                            child: Text('تعذر تحميل التقرير: ${snap.error}'));
                      }
                      final rows = snap.data ?? const <Cheque>[];
                      if (rows.isEmpty) {
                        return const Center(child: Text('لا توجد نتائج'));
                      }
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
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
                                      c.direction == ChequeDirection.received
                                          ? 'وارد'
                                          : 'صادر')),
                                  DataCell(Text(
                                      c.direction == ChequeDirection.received
                                          ? c.drawerName
                                          : (c.recipientName ?? '—'))),
                                  DataCell(Text(c.bankName)),
                                  DataCell(Text(
                                      '${_money.format(c.amount)} ${c.currency}')),
                                  DataCell(Text(_date.format(c.dueDate))),
                                  DataCell(Text(_status(c.status))),
                                  DataCell(Text(_reference(c))),
                                ]),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
