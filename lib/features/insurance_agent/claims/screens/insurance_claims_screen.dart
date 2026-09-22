import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:yalla_accounts/core/utils/user_facing_error.dart';
import 'package:yalla_accounts/features/insurance_agent/claims/services/insurance_claim_service.dart';
import 'package:yalla_accounts/features/insurance_agent/dashboard/services/insurance_dashboard_service.dart';

class InsuranceClaimsScreen extends StatefulWidget {
  const InsuranceClaimsScreen({super.key});

  @override
  State<InsuranceClaimsScreen> createState() => _InsuranceClaimsScreenState();
}

class _InsuranceClaimsScreenState extends State<InsuranceClaimsScreen> {
  final _search = TextEditingController();
  List<InsuranceClaimRecord> _claims = const [];
  List<InsurancePolicyOverview> _policies = const [];
  bool _busy = true;
  String? _error;

  static const _labels = <String, String>{
    'NEW': 'جديدة',
    'DOCUMENTS_REQUIRED': 'نواقص مستندات',
    'SUBMITTED': 'مقدمة للشركة',
    'ASSESSOR': 'عند المخمّن',
    'APPROVED': 'موافق عليها',
    'REPAIR': 'قيد الإصلاح',
    'SETTLED': 'تمت التسوية',
    'CLOSED': 'مغلقة',
    'REJECTED': 'مرفوضة',
  };

  static const _next = <String, List<String>>{
    'NEW': ['DOCUMENTS_REQUIRED', 'SUBMITTED', 'REJECTED'],
    'DOCUMENTS_REQUIRED': ['SUBMITTED', 'REJECTED'],
    'SUBMITTED': ['DOCUMENTS_REQUIRED', 'ASSESSOR', 'REJECTED'],
    'ASSESSOR': ['DOCUMENTS_REQUIRED', 'APPROVED', 'REJECTED'],
    'APPROVED': ['REPAIR', 'SETTLED', 'CLOSED'],
    'REPAIR': ['SETTLED', 'CLOSED'],
    'SETTLED': ['CLOSED'],
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        InsuranceClaimService.listClaims(),
        InsuranceDashboardService.policies(limit: 500),
      ]);
      if (!mounted) return;
      setState(() {
        _claims = values[0] as List<InsuranceClaimRecord>;
        _policies = values[1] as List<InsurancePolicyOverview>;
      });
    } catch (error) {
      if (mounted) setState(() => _error = UserFacingError.message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InsurancePolicyOverview? _policy(String id) {
    for (final policy in _policies) {
      if (policy.id == id) return policy;
    }
    return null;
  }

  List<InsuranceClaimRecord> get _visible {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _claims;
    return _claims.where((claim) {
      final policy = _policy(claim.policyId);
      return [
        claim.claimNumber,
        _labels[claim.status] ?? claim.status,
        policy?.number,
        policy?.insuredName,
        policy?.vehicle,
        policy?.company,
      ].whereType<String>().any((value) => value.toLowerCase().contains(query));
    }).toList(growable: false);
  }

  Future<void> _create() async {
    String? policyId;
    for (final policy in _policies) {
      if (policy.status != 'DRAFT') {
        policyId = policy.id;
        break;
      }
    }
    DateTime? lossDate;
    final notes = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AdaptiveAlertDialog(
          title: const Text('فتح مطالبة تأمين'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: policyId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'الوثيقة'),
                  items: _policies
                      .where((policy) => policy.status != 'DRAFT')
                      .map((policy) => DropdownMenuItem(
                            value: policy.id,
                            child: Text(
                              '${policy.number} — ${policy.insuredName}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (value) => setDialogState(() => policyId = value),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('تاريخ الحادث'),
                  subtitle: Text(lossDate == null
                      ? 'غير محدد'
                      : DateFormat('yyyy-MM-dd').format(lossDate!)),
                  trailing: const Icon(Icons.calendar_month_outlined),
                  onTap: () async {
                    final selected = await showDatePicker(
                      context: context,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (selected != null) {
                      setDialogState(() => lossDate = selected);
                    }
                  },
                ),
                TextField(
                  controller: notes,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'ملاحظات'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: policyId == null
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('فتح المطالبة'),
            ),
          ],
        ),
      ),
    );
    if (created != true || policyId == null) {
      notes.dispose();
      return;
    }
    try {
      await InsuranceClaimService.createClaim(
        policyId: policyId!,
        lossDate: lossDate,
        notes: notes.text,
      );
      await _load();
      _notice('تم فتح المطالبة بنجاح');
    } catch (error) {
      _notice(UserFacingError.message(error), error: true);
    } finally {
      notes.dispose();
    }
  }

  Future<void> _changeStatus(InsuranceClaimRecord claim) async {
    final allowed = _next[claim.status] ?? const <String>[];
    if (allowed.isEmpty) {
      _notice('لا توجد مرحلة تالية لهذه المطالبة');
      return;
    }
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('تغيير حالة المطالبة'),
        children: allowed
            .map((status) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, status),
                  child: Text(_labels[status] ?? status),
                ))
            .toList(),
      ),
    );
    if (selected == null) return;
    try {
      await InsuranceClaimService.transitionStatus(
        claimId: claim.id,
        status: selected,
      );
      await _load();
      _notice('تم تحديث حالة المطالبة');
    } catch (error) {
      _notice(UserFacingError.message(error), error: true);
    }
  }

  Future<void> _attach(InsuranceClaimRecord claim) async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: false,
    );
    final source = picked?.files.single.path;
    if (source == null) return;
    final type = await _textPrompt(
      title: 'نوع المستند',
      label: 'مثال: تقرير حادث، صورة، فاتورة',
    );
    if (type == null || type.trim().isEmpty) return;
    try {
      await InsuranceClaimService.attachDocumentFromPath(
        claimId: claim.id,
        documentType: type,
        sourcePath: source,
      );
      _notice('تم حفظ المستند داخل ملف المطالبة');
    } catch (error) {
      _notice(UserFacingError.message(error), error: true);
    }
  }

  Future<void> _linkWorkshop(InsuranceClaimRecord claim) async {
    final reference = await _textPrompt(
      title: 'ربط المطالبة بورشة',
      label: 'رقم أمر الإصلاح أو مرجع الورشة',
    );
    if (reference == null || reference.trim().isEmpty) return;
    try {
      await InsuranceClaimService.linkWorkshop(
        claimId: claim.id,
        workshopRef: reference,
      );
      _notice('تم ربط المطالبة بالورشة');
    } catch (error) {
      _notice(UserFacingError.message(error), error: true);
    }
  }

  Future<String?> _textPrompt({
    required String title,
    required String label,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AdaptiveAlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _details(InsuranceClaimRecord claim) async {
    try {
      final values = await Future.wait([
        InsuranceClaimService.listDocuments(claim.id),
        InsuranceClaimService.timeline(claim.id),
        InsuranceClaimService.workshopRef(claim.id),
      ]);
      if (!mounted) return;
      final documents = values[0] as List<InsuranceClaimDocumentRecord>;
      final timeline = values[1] as List<InsuranceClaimTimelineEvent>;
      final workshop = values[2] as String?;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .75,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    claim.claimNumber,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text('الحالة: ${_labels[claim.status] ?? claim.status}'),
                  Text('مرجع الورشة: ${workshop ?? 'غير مربوط'}'),
                  const Divider(height: 32),
                  Text('المستندات (${documents.length})',
                      style: Theme.of(context).textTheme.titleMedium),
                  ...documents.map((document) => ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: Text(document.documentType),
                        subtitle: Text(document.filePath),
                      )),
                  const Divider(height: 32),
                  Text('سجل الحركة (${timeline.length})',
                      style: Theme.of(context).textTheme.titleMedium),
                  ...timeline.reversed.map((event) => ListTile(
                        leading: const Icon(Icons.history),
                        title: Text(event.action),
                        subtitle: Text(DateFormat('yyyy-MM-dd HH:mm')
                            .format(event.createdAt.toLocal())),
                      )),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (error) {
      _notice(UserFacingError.message(error), error: true);
    }
  }

  void _notice(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? Colors.red.shade700 : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مطالبات التأمين'),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _busy || _policies.isEmpty ? null : _create,
          icon: const Icon(Icons.add),
          label: const Text('مطالبة جديدة'),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'بحث برقم المطالبة أو الوثيقة أو العميل',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: _busy
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _Message(
                          icon: Icons.error_outline,
                          text: _error!,
                          action: _load,
                        )
                      : visible.isEmpty
                          ? _Message(
                              icon: Icons.car_crash_outlined,
                              text: _claims.isEmpty
                                  ? 'لا توجد مطالبات مسجلة'
                                  : 'لا توجد نتائج مطابقة',
                              action: _claims.isEmpty ? _create : null,
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                              itemCount: visible.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final claim = visible[index];
                                final policy = _policy(claim.policyId);
                                return Card(
                                  child: ListTile(
                                    onTap: () => _details(claim),
                                    leading:
                                        const Icon(Icons.car_crash_outlined),
                                    title: Text(
                                      '${claim.claimNumber} — ${_labels[claim.status] ?? claim.status}',
                                    ),
                                    subtitle: Text([
                                      policy?.insuredName,
                                      policy?.vehicle,
                                      policy?.company,
                                    ].whereType<String>().join(' • ')),
                                    trailing: PopupMenuButton<String>(
                                      onSelected: (action) {
                                        if (action == 'status') {
                                          _changeStatus(claim);
                                        } else if (action == 'attach') {
                                          _attach(claim);
                                        } else if (action == 'workshop') {
                                          _linkWorkshop(claim);
                                        } else {
                                          _details(claim);
                                        }
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                            value: 'status',
                                            child: Text('تحديث الحالة')),
                                        PopupMenuItem(
                                            value: 'attach',
                                            child: Text('إضافة مستند')),
                                        PopupMenuItem(
                                            value: 'workshop',
                                            child: Text('ربط بالورشة')),
                                        PopupMenuItem(
                                            value: 'details',
                                            child: Text('السجل والتفاصيل')),
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
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    this.action,
  });
  final IconData icon;
  final String text;
  final VoidCallback? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: Colors.grey),
          const SizedBox(height: 12),
          Text(text),
          if (action != null) ...[
            const SizedBox(height: 12),
            FilledButton(onPressed: action, child: const Text('متابعة')),
          ],
        ],
      ),
    );
  }
}
