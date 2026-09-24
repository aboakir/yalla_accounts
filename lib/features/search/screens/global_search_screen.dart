import 'package:yalla_accounts/core/utils/user_facing_error.dart';
// 📁 lib/features/search/screens/global_search_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/services/global_search_service.dart';
import 'package:yalla_accounts/core/experience/app_experience_service.dart';
import 'package:yalla_accounts/core/release/release_scope_config.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/repairs/services/repair_database_service.dart';
import 'package:yalla_accounts/features/clients/services/client_service.dart';
import 'package:yalla_accounts/features/employees/services/employee_database_service.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_service.dart';
import 'package:yalla_accounts/features/raw_materials/services/raw_material_service.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  bool _loading = false;
  bool _opening = false; // يمنع double tap
  List<SearchHit> _hits = [];
  String _q = '';

  @override
  void initState() {
    super.initState();
    AppExperienceService.load();
    // افتح الكيبورد مباشرة
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    // تفريغ النتائج لو النص فاضي
    if (v.trim().isEmpty) {
      setState(() {
        _q = '';
        _hits = [];
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _search(v);
    });
  }

  Future<void> _search(String v) async {
    final q = v.trim();
    if (q.isEmpty) {
      setState(() {
        _q = '';
        _hits = [];
        _loading = false;
      });
      return;
    }
    setState(() {
      _q = q;
      _loading = true;
    });
    try {
      final hits = await GlobalSearchService.search(q);
      final profile = AppExperienceService.current.value;
      final visibleHits = hits
          .where((hit) => profile.isSearchSourceVisible(
                hit.source,
                insurancePilotVisible: ReleaseScopeConfig.insurancePilotVisible,
              ))
          .toList();
      if (!mounted) return;
      setState(() => _hits = visibleHits);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في البحث: ${UserFacingError.message(e)}')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openHit(SearchHit h) async {
    if (_opening) return;
    _opening = true;
    FocusScope.of(context).unfocus();
    try {
      switch (h.source) {
        case 'repairs':
          final repair = await RepairDatabaseService.getRepairById(h.id);
          if (!mounted) return;
          await AppRoutes.pushNamedSafe(
            context,
            repair == null
                ? AppRoutes.repairsDashboard
                : AppRoutes.repairDetail,
            arguments: repair,
          );
          break;
        case 'clients':
          final clientId = int.tryParse(h.id);
          final client = clientId == null
              ? null
              : await ClientService.getClientById(clientId);
          if (!mounted) return;
          await AppRoutes.pushNamedSafe(
            context,
            client == null ? AppRoutes.clients : AppRoutes.clientEdit,
            arguments: client,
          );
          break;
        case 'invoices':
          await AppRoutes.pushNamedSafe(context, AppRoutes.invoiceView,
              arguments: h.id);
          break;
        case 'payments':
          await AppRoutes.pushNamedSafe(context, AppRoutes.payments,
              arguments: {'paymentId': h.id});
          break;
        case 'employees':
          final employee = await EmployeeDatabaseService.getById(h.id);
          if (!mounted) return;
          await AppRoutes.pushNamedSafe(
            context,
            employee == null ? AppRoutes.employeeList : AppRoutes.employeeEdit,
            arguments: employee,
          );
          break;
        case 'suppliers':
          await AppRoutes.pushNamedSafe(
            context,
            AppRoutes.supplierPayables,
            arguments: {'supplierId': h.id, 'supplierName': h.title},
          );
          break;
        case 'receipts':
          await AppRoutes.pushNamedSafe(context, AppRoutes.receiptVouchersList,
              arguments: {'receiptId': h.id});
          break;
        case 'cheques':
          final chequeId = int.tryParse(h.id);
          final cheque =
              chequeId == null ? null : await ChequeService().getById(chequeId);
          if (!mounted) return;
          await AppRoutes.pushNamedSafe(
            context,
            cheque == null ? AppRoutes.chequesList : AppRoutes.chequesEdit,
            arguments: cheque,
          );
          break;
        case 'purchases':
          await AppRoutes.pushNamedSafe(context, AppRoutes.purchasesList,
              arguments: {'purchaseId': h.id});
          break;
        case 'vehicles':
          await AppRoutes.pushNamedSafe(
            context,
            AppRoutes.vehiclesList,
            arguments: {'vehicleId': int.tryParse(h.id)},
          );
          break;
        case 'documents':
          await AppRoutes.pushNamedSafe(
            context,
            AppRoutes.insurancePolicyDetails,
            arguments: {'policyId': h.id},
          );
          break;
        case 'items':
          final itemId = int.tryParse(h.id);
          final item =
              itemId == null ? null : await RawMaterialService.getById(itemId);
          if (!mounted) return;
          await AppRoutes.pushNamedSafe(
            context,
            item == null ? AppRoutes.rawMaterials : AppRoutes.rawMaterialEdit,
            arguments: item,
          );
          break;
        default:
          break;
      }
    } finally {
      _opening = false;
      if (mounted) {
        _focus.requestFocus();
        _controller.selection =
            TextSelection.collapsed(offset: _controller.text.length);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('بحث شامل'),
        actions: [
          if (_q.isNotEmpty)
            IconButton(
              onPressed: () {
                _controller.clear();
                setState(() {
                  _q = '';
                  _hits = [];
                  _loading = false;
                });
              },
              icon: const Icon(Icons.clear),
              tooltip: 'مسح',
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: TextField(
              inputFormatters: const [YallaDigitNormalizer()],
              focusNode: _focus,
              controller: _controller,
              onChanged: _onChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'اكتب للبحث في الملفات، العملاء، الفواتير، الدفعات…',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: _hits.isEmpty && _q.isEmpty
                ? Center(
                    child: Text('ابدأ بالكتابة للبحث',
                        style: theme.textTheme.bodyMedium),
                  )
                : _hits.isEmpty
                    ? const Center(child: Text('لا نتائج'))
                    : ListView.separated(
                        itemCount: _hits.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final h = _hits[i];
                          return ListTile(
                            onTap: () => _openHit(h),
                            leading: _leadingIcon(h.source),
                            title: Text(
                              h.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle:
                                (h.subtitle != null && h.subtitle!.isNotEmpty)
                                    ? Text(
                                        h.subtitle!,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    : null,
                            trailing: Chip(label: Text(_label(h.source))),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  static Widget _leadingIcon(String src) {
    switch (src) {
      case 'repairs':
        return const Icon(Icons.build_circle);
      case 'clients':
        return const Icon(Icons.person);
      case 'invoices':
        return const Icon(Icons.receipt_long);
      case 'payments':
        return const Icon(Icons.attach_money);
      case 'employees':
        return const Icon(Icons.badge);
      case 'suppliers':
        return const Icon(Icons.store);
      case 'receipts':
        return const Icon(Icons.receipt_long);
      case 'cheques':
        return const Icon(Icons.payments_outlined);
      case 'purchases':
        return const Icon(Icons.shopping_cart_outlined);
      default:
        return const Icon(Icons.search);
    }
  }

  static String _label(String src) {
    switch (src) {
      case 'repairs':
        return 'إصلاحات';
      case 'clients':
        return 'عملاء';
      case 'invoices':
        return 'فواتير';
      case 'payments':
        return 'دفعات';
      case 'employees':
        return 'موظفون';
      case 'suppliers':
        return 'موردون';
      case 'receipts':
        return 'سندات قبض';
      case 'cheques':
        return 'شيكات';
      case 'purchases':
        return 'مشتريات';
      default:
        return src;
    }
  }
}
