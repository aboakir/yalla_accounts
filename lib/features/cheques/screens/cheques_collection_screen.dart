import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/utils/user_facing_error.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/features/auth/services/permission_service.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_deposit_service.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

class ChequesCollectionScreen extends StatefulWidget {
  const ChequesCollectionScreen({super.key});

  @override
  State<ChequesCollectionScreen> createState() =>
      _ChequesCollectionScreenState();
}

class _ChequesCollectionScreenState extends State<ChequesCollectionScreen>
    with SingleTickerProviderStateMixin {
  final _service = ChequeService();
  final _permissions = PermissionService();
  final _money = NumberFormat('#,##0.00', 'ar');
  final _date = DateFormat('yyyy-MM-dd');
  final _selected = <int>{};
  late TabController _tabs;
  late Future<List<Cheque>> _available;
  late Future<List<Cheque>> _deposited;
  bool _canDeposit = false;
  bool _canCollect = false;
  bool _canReturn = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _reload();
    _loadPermissions();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadPermissions() async {
    final values = await Future.wait([
      _permissions.canCurrent(PermissionKeys.chequeDeposit),
      _permissions.canCurrent(PermissionKeys.chequeCollect),
      _permissions.canCurrent(PermissionKeys.chequeReturn),
    ]);
    if (!mounted) return;
    setState(() {
      _canDeposit = values[0];
      _canCollect = values[1];
      _canReturn = values[2];
    });
  }

  void _reload() {
    _available = _loadAvailable();
    _deposited = _service.fetchFiltered(status: ChequeStatus.deposited);
  }

  Future<List<Cheque>> _loadAvailable() async {
    final received =
        await _service.fetchFiltered(status: ChequeStatus.received);
    final held = await _service.fetchFiltered(status: ChequeStatus.held);
    final rows = [...received, ...held];
    rows.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return rows;
  }

  Future<void> _deposit(List<Cheque> rows) async {
    if (_selected.isEmpty) return;
    final db = await DBService.database;
    final banks = await db.query(
      'accounts',
      columns: const ['id', 'code', 'name'],
      where: "code='1010' OR code LIKE '1010.%'",
      orderBy: 'code',
    );
    if (!mounted) return;
    if (banks.isEmpty) {
      _snack('لا يوجد حساب بنكي متاح للإيداع.');
      return;
    }
    int bankId = (banks.first['id'] as num).toInt();
    DateTime date = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AdaptiveAlertDialog(
          title: Text('إيداع ${_selected.length} شيك للتحصيل'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: bankId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'الحساب البنكي'),
                  items: [
                    for (final bank in banks)
                      DropdownMenuItem(
                        value: (bank['id'] as num).toInt(),
                        child: Text('${bank['code']} — ${bank['name']}'),
                      ),
                  ],
                  onChanged: (v) => setD(() => bankId = v ?? bankId),
                ),
                const SizedBox(height: 12),
                ListTile(
                  title: const Text('تاريخ الإيداع'),
                  subtitle: Text(_date.format(date)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setD(() => date = picked);
                  },
                ),
                Text(
                  'الإجمالي: ${_money.format(rows.where((c) => _selected.contains(c.id)).fold<double>(0, (s, c) => s + c.amount))}',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إيداع'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await ChequeDepositService.depositBatch(
        bankAccountId: bankId,
        chequeIds: _selected.toList(),
        depositDate: date,
      );
      if (!mounted) return;
      setState(() {
        _selected.clear();
        _reload();
        _tabs.index = 1;
      });
    } catch (e) {
      _snack('تعذر الإيداع: ${UserFacingError.message(e)}');
    }
  }

  Future<void> _transition(Cheque cheque, ChequeStatus status) async {
    if (cheque.id == null) return;
    String? reason;
    if (status == ChequeStatus.returned) {
      final controller = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AdaptiveAlertDialog(
          title: const Text('إرجاع الشيك'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'سبب الإرجاع'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تأكيد'),
            ),
          ],
        ),
      );
      if (ok != true) {
        controller.dispose();
        return;
      }
      reason = controller.text.trim();
      controller.dispose();
      if (reason.isEmpty) {
        _snack('سبب الإرجاع مطلوب.');
        return;
      }
    }
    try {
      await _service.transitionStatus(
        chequeId: cheque.id!,
        status: status,
        reason: reason,
      );
      if (!mounted) return;
      setState(_reload);
    } catch (e) {
      _snack('تعذر تحديث الشيك: ${UserFacingError.message(e)}');
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('إيداع وتحصيل الشيكات'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'جاهزة للإيداع'),
            Tab(text: 'مودعة قيد التحصيل'),
          ],
        ),
      ),
      drawer: desktop
          ? null
          : const YallaSidebar(currentRoute: AppRoutes.chequesCollection),
      body: AdaptiveRow(
        children: [
          if (desktop)
            const YallaSidebar(currentRoute: AppRoutes.chequesCollection),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _availableTab(),
                _depositedTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _availableTab() {
    return FutureBuilder<List<Cheque>>(
      future: _available,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snap.data ?? const <Cheque>[];
        if (rows.isEmpty) {
          return const Center(child: Text('لا توجد شيكات جاهزة للإيداع'));
        }
        return Column(
          children: [
            if (_canDeposit)
              Padding(
                padding: const EdgeInsets.all(10),
                child: FilledButton.icon(
                  onPressed: _selected.isEmpty ? null : () => _deposit(rows),
                  icon: const Icon(Icons.account_balance),
                  label: Text('إيداع المحدد (${_selected.length})'),
                ),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final c = rows[i];
                  final id = c.id!;
                  return CheckboxListTile(
                    value: _selected.contains(id),
                    onChanged: _canDeposit
                        ? (value) => setState(() {
                              value == true
                                  ? _selected.add(id)
                                  : _selected.remove(id);
                            })
                        : null,
                    title: Text(
                        'شيك ${c.chequeNo} — ${_money.format(c.amount)} ${c.currency}'),
                    subtitle: Text(
                        '${c.drawerName} • ${c.bankName} • استحقاق ${_date.format(c.dueDate)}'),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _depositedTab() {
    return FutureBuilder<List<Cheque>>(
      future: _deposited,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snap.data ?? const <Cheque>[];
        if (rows.isEmpty) {
          return const Center(child: Text('لا توجد شيكات مودعة قيد التحصيل'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final c = rows[i];
            return Card(
              child: ListTile(
                title: Text(
                    'شيك ${c.chequeNo} — ${_money.format(c.amount)} ${c.currency}'),
                subtitle: Text(
                    '${c.bankName} • إيداع ${c.depositedAt == null ? '—' : _date.format(c.depositedAt!)}'),
                trailing: Wrap(
                  spacing: 6,
                  children: [
                    if (_canCollect)
                      FilledButton.tonal(
                        onPressed: () => _transition(c, ChequeStatus.collected),
                        child: const Text('تأكيد التحصيل'),
                      ),
                    if (_canReturn)
                      OutlinedButton(
                        onPressed: () => _transition(c, ChequeStatus.returned),
                        child: const Text('راجع'),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
