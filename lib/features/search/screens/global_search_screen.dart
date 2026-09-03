// 📁 lib/features/search/screens/global_search_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/services/global_search_service.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/repairs/services/repair_database_service.dart';

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
      if (!mounted) return;
      setState(() => _hits = hits);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في البحث: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openHit(SearchHit h) async {
    if (_opening) return;
    _opening = true;
    // اقفل الكيبورد
    FocusScope.of(context).unfocus();

    try {
      switch (h.source) {
        case 'repairs':
          final r = await RepairDatabaseService.getRepairById(h.id);
          if (!mounted) return;
          if (r != null) {
            Navigator.pushNamed(context, AppRoutes.repairDetail, arguments: r);
          } else {
            Navigator.pushNamed(context, AppRoutes.repairsDashboard);
          }
          break;

        case 'clients':
          if (!mounted) return;
          Navigator.pushNamed(context, AppRoutes.clients);
          break;

        case 'invoices':
          if (!mounted) return;
          Navigator.pushNamed(context, AppRoutes.financeDashboard);
          break;

        case 'payments':
          if (!mounted) return;
          Navigator.pushNamed(context, AppRoutes.payments);
          break;

        case 'employees':
          if (!mounted) return;
          Navigator.pushNamed(context, AppRoutes.employeeList);
          break;

        case 'suppliers':
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('قريبًا: شاشة الموردين')),
          );
          break;

        default:
          break;
      }
    } finally {
      // سماح بفتح عنصر جديد بعد الانتقال
      _opening = false;
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
      default:
        return src;
    }
  }
}
