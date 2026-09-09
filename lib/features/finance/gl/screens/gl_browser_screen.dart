// 📁 lib/features/finance/gl/screens/gl_browser_screen.dart
//
// GLBrowserScreen — مستعرض قيود GL (LTR، بدون Sidebar).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class GLBrowserScreen extends StatefulWidget {
  const GLBrowserScreen({super.key});

  @override
  State<GLBrowserScreen> createState() => _GLBrowserScreenState();
}

class _GLBrowserScreenState extends State<GLBrowserScreen> {
  final _df = DateFormat('yyyy-MM-dd');
  final _money = NumberFormat('#,##0.00');

  // فلاتر عامة
  DateTime? _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime? _to = DateTime.now();
  String?
      _source; // INVOICE, PAYMENT, EMP_ADV, SALARY-APPROVAL, SALARY-PAY, PURCHASE
  int? _accountId; // فلتر حساب (اختياري)
  String _query = '';

  bool _loading = true;

  // نتائج entries (بدون السطور)
  List<Map<String, Object?>> _entries = const [];

  // كاش سطور كل قيد
  final Map<int, List<Map<String, Object?>>> _linesCache = {};
  final Set<int> _expanded = {};

  // قائمة حسابات للاختيار
  List<_Account> _accounts = [];

  // focus entryId
  int? _focusEntryId;

  // تحكم البحث النصي
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map) {
        if (args['entryId'] != null) {
          final v = args['entryId'];
          _focusEntryId = v is int ? v : int.tryParse('$v');
        }
        if (args['accountId'] != null) {
          _accountId = (args['accountId'] is int)
              ? args['accountId'] as int
              : int.tryParse('${args['accountId']}');
        }
        if (args['from'] is String) _from = DateTime.tryParse(args['from']);
        if (args['to'] is String) _to = DateTime.tryParse(args['to']);
        if (args['query'] is String) {
          _query = args['query'];
          _searchCtrl.text = _query;
        }
      }
      await _loadAccounts();
      await _load();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    final db = await DBService.database;
    final rows = await db
        .rawQuery('SELECT id, code, name FROM accounts ORDER BY code ASC');
    setState(() {
      _accounts = rows
          .map((m) => _Account(
                id: _asInt(m['id']) ?? 0,
                code: (m['code'] ?? '').toString(),
                name: (m['name'] ?? '').toString(),
              ))
          .toList();
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final db = await DBService.database;

      // فلترة entries فقط (date/source)
      final where = <String>[];
      final args = <Object?>[];
      if (_from != null) {
        where.add('date >= ?');
        args.add(_from!.toIso8601String());
      }
      if (_to != null) {
        final end = DateTime(_to!.year, _to!.month, _to!.day + 1);
        where.add('date < ?');
        args.add(end.toIso8601String());
      }
      if (_source != null && _source!.trim().isNotEmpty) {
        where.add('source = ?');
        args.add(_source!.trim());
      }

      final rows = await db.query(
        'gl_entries',
        columns: ['id', 'date', 'ref', 'source', 'source_id', 'note'],
        where: where.isNotEmpty ? where.join(' AND ') : null,
        whereArgs: args,
        orderBy: 'date DESC, id DESC',
        limit: 500,
      );

      setState(() {
        _entries = rows;
        _loading = false;
        _linesCache.clear();
      });

      if (_focusEntryId != null &&
          rows.any((e) => _asInt(e['id']) == _focusEntryId)) {
        _expanded.add(_focusEntryId!);
        await _ensureLines(_focusEntryId!);
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _ensureLines(int entryId) async {
    final db = await DBService.database;

    final where = <String>['l.entry_id = ?'];
    final args = <Object?>[entryId];

    if (_accountId != null) {
      where.add('l.account_id = ?');
      args.add(_accountId!);
    }
    if (_query.trim().isNotEmpty) {
      final s = '%${_query.trim()}%';
      where.add(
          '(e.ref LIKE ? OR e.note LIKE ? OR e.source LIKE ? OR a.code LIKE ? OR a.name LIKE ?)');
      args.addAll([s, s, s, s, s]);
    }

    final lines = await db.rawQuery('''
      SELECT
        l.id,
        l.entry_id,
        l.account_id,
        l.debit,
        l.credit,
        l.party_type,
        l.party_id,
        a.code AS account_code,
        a.name AS account_name
      FROM gl_lines l
      JOIN accounts a ON a.id = l.account_id
      JOIN gl_entries e ON e.id = l.entry_id
      WHERE ${where.join(' AND ')}
      ORDER BY l.id ASC
    ''', args);

    _linesCache[entryId] = lines;
    if (mounted) setState(() {});
  }

  Future<void> _pickFrom() async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(DateTime.now().year - 5, 1, 1),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
      initialDate: _from ?? DateTime.now(),
    );
    if (d != null) setState(() => _from = d);
  }

  Future<void> _pickTo() async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(DateTime.now().year - 5, 1, 1),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
      initialDate: _to ?? DateTime.now(),
    );
    if (d != null) setState(() => _to = d);
  }

  Future<void> _reverse(int entryId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AdaptiveAlertDialog(
        title: const Text('Reverse GL'),
        content: Text('عكس القيد #$entryId ؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reverse')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await DBService.reverseEntryGL(entryId,
          note: 'Reverse from GLBrowserScreen');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Reversed')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  void _resetFilters() {
    setState(() {
      _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
      _to = DateTime.now();
      _source = null;
      _accountId = null;
      _query = '';
      _searchCtrl.text = '';
      _linesCache.clear();
      _expanded.clear();
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('GL Browser'),
        actions: [
          IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(isWide),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _entries.isEmpty
                    ? const Center(child: Text('No entries'))
                    : _buildList(isWide),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(bool isWide) {
    final fromStr = _from != null ? _df.format(_from!) : '—';
    final toStr = _to != null ? _df.format(_to!) : '—';

    final sources = const <String>[
      'INVOICE',
      'PAYMENT',
      'EMP_ADV',
      'SALARY-APPROVAL',
      'SALARY-PAY',
      'PURCHASE',
    ];

    // نتفادى Dropdown مع عناصر value=null: نستخدم قيم sentinels
    final String sourceValue = _source ?? ''; // '' = All
    final int accountValue = _accountId ?? -1; // -1 = All

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // بحث نصي
          SizedBox(
            width: isWide ? 340 : 260,
            child: TextField(
              inputFormatters: const [YallaDigitNormalizer()],
              controller: _searchCtrl,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'بحث في ref/note/source واسم/كود الحساب…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) {
                _query = v;
                _linesCache.clear();
                setState(() {});
              },
              onSubmitted: (_) {
                _linesCache.clear();
                setState(() {});
              },
            ),
          ),
          // من / إلى
          AdaptiveRow(mainAxisSize: MainAxisSize.min, children: [
            const Text('From: '),
            TextButton(onPressed: _pickFrom, child: Text(fromStr)),
          ]),
          AdaptiveRow(mainAxisSize: MainAxisSize.min, children: [
            const Text('To: '),
            TextButton(onPressed: _pickTo, child: Text(toStr)),
          ]),
          // المصدر
          DropdownButton<String>(
            value: sourceValue,
            hint: const Text('Source'),
            items: <DropdownMenuItem<String>>[
              const DropdownMenuItem<String>(value: '', child: Text('All')),
              ...sources.map(
                  (s) => DropdownMenuItem<String>(value: s, child: Text(s))),
            ],
            onChanged: (v) =>
                setState(() => _source = (v == null || v.isEmpty) ? null : v),
          ),
          // الحساب
          SizedBox(
              width: MediaQuery.sizeOf(context).width < 430
                  ? MediaQuery.sizeOf(context).width - 56
                  : 360,
              child: DropdownButton<int>(
                isExpanded: true,
                value: accountValue,
                hint: const Text('All accounts'),
                items: <DropdownMenuItem<int>>[
                  const DropdownMenuItem<int>(
                      value: -1, child: Text('All accounts')),
                  ..._accounts.map(
                    (a) => DropdownMenuItem<int>(
                        value: a.id, child: Text('${a.code} — ${a.name}')),
                  ),
                ],
                onChanged: (v) {
                  setState(
                      () => _accountId = (v == null || v == -1) ? null : v);
                  _linesCache.clear();
                },
              )),
          // تطبيق/تصفير
          ElevatedButton.icon(
              icon: const Icon(Icons.search),
              label: const Text('Apply'),
              onPressed: _load),
          TextButton(onPressed: _resetFilters, child: const Text('Reset')),
        ],
      ),
    );
  }

  Widget _buildList(bool isWide) {
    return ListView.separated(
      itemCount: _entries.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final e = _entries[i];
        final id = _asInt(e['id']) ?? 0;
        final dateStr = _safeDate(e['date']);
        final ref = '${e['ref'] ?? ''}';
        final source = '${e['source'] ?? ''}';
        final sourceId = '${e['source_id'] ?? ''}';
        final note = '${e['note'] ?? ''}';
        final expanded = _expanded.contains(id);

        return Column(
          children: [
            ListTile(
              dense: isWide,
              leading: CircleAvatar(child: Text('$id')),
              title: Text('$source  •  $sourceId'),
              subtitle: Text(
                  '$dateStr   —   ${note.isEmpty ? (ref.isEmpty ? '—' : ref) : note}'),
              trailing: Wrap(
                spacing: 6,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy ID'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: '$id'));
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied')));
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('Reverse'),
                    onPressed: () => _reverse(id),
                  ),
                  IconButton(
                    tooltip: expanded ? 'Collapse' : 'Expand',
                    icon:
                        Icon(expanded ? Icons.expand_less : Icons.expand_more),
                    onPressed: () async {
                      setState(() {
                        if (expanded) {
                          _expanded.remove(id);
                        } else {
                          _expanded.add(id);
                        }
                      });
                      if (!expanded) await _ensureLines(id);
                    },
                  ),
                ],
              ),
            ),
            if (expanded) _buildLines(entryId: id, isWide: isWide),
          ],
        );
      },
    );
  }

  Widget _buildLines({required int entryId, required bool isWide}) {
    final lines = _linesCache[entryId];
    if (lines == null) {
      _ensureLines(entryId);
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Center(
            child: Padding(
                padding: EdgeInsets.all(8.0),
                child: CircularProgressIndicator())),
      );
    }
    if (lines.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text('No lines'),
      );
    }

    double sD = 0, sC = 0;
    for (final m in lines) {
      final d = _num(m['debit']);
      final c = _num(m['credit']);
      sD += d;
      sC += c;
    }
    final bal = (sD - sC).abs() < 0.005;

    if (isWide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: AdaptiveDataTable(
                headingTextStyle: const TextStyle(fontWeight: FontWeight.bold),
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('Account Code')),
                  DataColumn(label: Text('Account Name')),
                  DataColumn(label: Text('Debit')),
                  DataColumn(label: Text('Credit')),
                  DataColumn(label: Text('Party')),
                ],
                rows: lines.map((m) {
                  final id = m['id'];
                  final code = '${m['account_code'] ?? ''}';
                  final name = '${m['account_name'] ?? ''}';
                  final d = _num(m['debit']);
                  final c = _num(m['credit']);
                  final partyType = (m['party_type'] ?? '').toString();
                  final partyId = (m['party_id'] ?? '').toString();
                  final party = partyType.isEmpty ? '' : '$partyType:$partyId';
                  return DataRow(cells: [
                    DataCell(Text('$id')),
                    DataCell(Text(code)),
                    DataCell(Text(name)),
                    DataCell(Text(_money.format(d))),
                    DataCell(Text(_money.format(c))),
                    DataCell(Text(party)),
                  ]);
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: AdaptiveRow(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Chip(
                    label: Text(
                      bal ? 'Balanced' : 'Not balanced',
                      style: TextStyle(
                          color: bal ? Colors.green[900] : Colors.red[900],
                          fontWeight: FontWeight.w700),
                    ),
                    backgroundColor: bal ? Colors.green[50] : Colors.red[50],
                    side: BorderSide(
                        color: bal ? Colors.green[200]! : Colors.red[200]!),
                  ),
                  const SizedBox(width: 12),
                  Text(
                      'Σ Debit: ${_money.format(sD)}    Σ Credit: ${_money.format(sC)}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Mobile
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          ...lines.map((m) {
            final code = '${m['account_code'] ?? ''}';
            final name = '${m['account_name'] ?? ''}';
            final d = _num(m['debit']);
            final c = _num(m['credit']);
            final partyType = (m['party_type'] ?? '').toString();
            final partyId = (m['party_id'] ?? '').toString();
            final party = partyType.isEmpty ? '' : '$partyType:$partyId';
            return ListTile(
              dense: true,
              title: Text('$code — $name'),
              subtitle: Text(
                  'D: ${_money.format(d)}   •   C: ${_money.format(c)}\n$party'),
              contentPadding: EdgeInsets.zero,
            );
          }),
          const SizedBox(height: 6),
          AdaptiveRow(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Chip(
                label: Text(
                  bal ? 'Balanced' : 'Not balanced',
                  style: TextStyle(
                      color: bal ? Colors.green[900] : Colors.red[900],
                      fontWeight: FontWeight.w700),
                ),
                backgroundColor: bal ? Colors.green[50] : Colors.red[50],
                side: BorderSide(
                    color: bal ? Colors.green[200]! : Colors.red[200]!),
              ),
              const SizedBox(width: 12),
              Text('Σ D: ${_money.format(sD)} / Σ C: ${_money.format(sC)}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────── Utils ───────────
  String _safeDate(Object? iso) {
    if (iso is String) {
      final d = DateTime.tryParse(iso);
      if (d != null) return _df.format(d);
      return iso;
    }
    return '';
  }

  int? _asInt(Object? v) {
    if (v is int) return v;
    return int.tryParse('$v');
  }

  double _num(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0.0;
  }
}

class _Account {
  final int id;
  final String code;
  final String name;
  _Account({required this.id, required this.code, required this.name});
}
