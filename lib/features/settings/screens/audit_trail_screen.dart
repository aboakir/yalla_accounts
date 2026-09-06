import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/features/auth/services/audit_trail_service.dart';
import 'package:yalla_accounts/features/auth/services/permission_service.dart';

class AuditTrailScreen extends StatefulWidget {
  const AuditTrailScreen({super.key});

  @override
  State<AuditTrailScreen> createState() => _AuditTrailScreenState();
}

class _AuditTrailScreenState extends State<AuditTrailScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, Object?>> _rows = const [];
  final _action = TextEditingController();
  final _entityId = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _action.dispose();
    _entityId.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final allowed =
          await PermissionService().canCurrent(PermissionKeys.auditView);
      if (!allowed) throw StateError('ليس لديك صلاحية عرض سجل التدقيق.');
      final rows = await AuditTrailService.query(
        actionContains: _action.text,
        entityId: _entityId.text,
        limit: 500,
      );
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _pretty(Object? raw) {
    final value = raw?.toString();
    if (value == null || value.isEmpty) return '';
    try {
      final decoded = jsonDecode(value);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سجل التدقيق')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 240,
                  child: TextField(
                    controller: _action,
                    decoration: const InputDecoration(
                      labelText: 'نوع العملية',
                      hintText: 'REPAIR / RECEIPT / BACKUP...',
                      prefixIcon: Icon(Icons.filter_alt_outlined),
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: TextField(
                    controller: _entityId,
                    decoration: const InputDecoration(
                      labelText: 'معرّف السجل',
                      hintText: 'Repair ID / Receipt No...',
                      prefixIcon: Icon(Icons.tag),
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.search),
                  label: const Text('بحث'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _rows.isEmpty
                        ? const Center(child: Text('لا توجد أحداث مطابقة.'))
                        : ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: _rows.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final row = _rows[index];
                              final at = DateTime.tryParse(
                                      row['created_at']?.toString() ?? '')
                                  ?.toLocal();
                              final title =
                                  '${row['action'] ?? ''} — ${row['entity_type'] ?? ''}';
                              final subtitle = [
                                if ((row['entity_id']?.toString() ?? '')
                                    .isNotEmpty)
                                  'ID: ${row['entity_id']}',
                                'المستخدم: ${row['actor_user_id'] ?? 'SYSTEM'} (${row['actor_role'] ?? '—'})',
                                if (at != null)
                                  DateFormat('yyyy-MM-dd HH:mm:ss').format(at),
                                if ((row['reason']?.toString() ?? '')
                                    .isNotEmpty)
                                  'السبب: ${row['reason']}',
                              ].join('\n');
                              return Card(
                                child: ExpansionTile(
                                  leading:
                                      const Icon(Icons.fact_check_outlined),
                                  title: Text(title),
                                  subtitle: Text(subtitle),
                                  childrenPadding:
                                      const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                  children: [
                                    if ((row['before_json']?.toString() ?? '')
                                        .isNotEmpty)
                                      _CodeBlock(
                                          title: 'قبل',
                                          text: _pretty(row['before_json'])),
                                    if ((row['after_json']?.toString() ?? '')
                                        .isNotEmpty)
                                      _CodeBlock(
                                          title: 'بعد',
                                          text: _pretty(row['after_json'])),
                                    if ((row['metadata_json']?.toString() ?? '')
                                        .isNotEmpty)
                                      _CodeBlock(
                                          title: 'بيانات إضافية',
                                          text: _pretty(row['metadata_json'])),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.title, required this.text});
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(text),
            ),
          ],
        ),
      ),
    );
  }
}
