import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/features/employees/models/employee.dart';
import 'package:yalla_accounts/features/employees/services/employee_service.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/services/repair_workflow_service.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';

class RepairWorkflowCard extends StatefulWidget {
  final Repair repair;
  final Future<void> Function() onChanged;
  final Future<void> Function()? onShareEstimate;

  const RepairWorkflowCard({
    super.key,
    required this.repair,
    required this.onChanged,
    this.onShareEstimate,
  });

  @override
  State<RepairWorkflowCard> createState() => _RepairWorkflowCardState();
}

class _RepairWorkflowCardState extends State<RepairWorkflowCard> {
  final _dateFormat = DateFormat('yyyy-MM-dd');
  RepairWorkflowState? _workflow;
  bool _loading = true;
  String? _responsibleName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RepairWorkflowCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repair.id != widget.repair.id) _load();
  }

  Future<void> _load() async {
    try {
      final workflow = await RepairWorkflowService.load(widget.repair.id);
      String? responsibleName;
      final responsibleId = workflow.responsibleEmployeeId?.trim() ?? '';
      if (responsibleId.isNotEmpty) {
        final employee = await EmployeeService.getEmployeeById(responsibleId);
        responsibleName = employee?.fullName;
      }
      if (!mounted) return;
      setState(() {
        _workflow = workflow;
        _responsibleName = responsibleName;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('تعذر تحميل سير العمل: $e');
    }
  }

  Future<void> _afterChange() async {
    await _load();
    await widget.onChanged();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  String _stageLabel(String stage) {
    switch (stage) {
      case P09RepairWorkflowStage.draft:
        return 'إعداد العرض';
      case P09RepairWorkflowStage.sent:
        return 'العرض مُرسل';
      case P09RepairWorkflowStage.approved:
        return 'موافقة العميل';
      case P09RepairWorkflowStage.rejected:
        return 'مرفوض';
      case P09RepairWorkflowStage.workOrder:
        return 'أمر عمل';
      case P09RepairWorkflowStage.inProgress:
        return 'قيد التنفيذ';
      case P09RepairWorkflowStage.readyForQc:
        return 'فحص أولي';
      case P09RepairWorkflowStage.qcChecked:
        return 'اجتاز الفحص الأولي';
      case P09RepairWorkflowStage.finalQc:
        return 'الجودة النهائية معتمدة';
      case P09RepairWorkflowStage.readyForDelivery:
        return 'جاهزة للتسليم';
      case P09RepairWorkflowStage.delivered:
        return 'تم التسليم';
      case P09RepairWorkflowStage.closed:
        return 'مغلق';
      default:
        return stage;
    }
  }

  IconData _stageIcon(String stage) {
    switch (stage) {
      case P09RepairWorkflowStage.sent:
        return Icons.send_outlined;
      case P09RepairWorkflowStage.approved:
        return Icons.verified_outlined;
      case P09RepairWorkflowStage.rejected:
        return Icons.cancel_outlined;
      case P09RepairWorkflowStage.workOrder:
        return Icons.assignment_outlined;
      case P09RepairWorkflowStage.inProgress:
        return Icons.handyman_outlined;
      case P09RepairWorkflowStage.readyForQc:
        return Icons.fact_check_outlined;
      case P09RepairWorkflowStage.qcChecked:
        return Icons.task_alt_outlined;
      case P09RepairWorkflowStage.finalQc:
        return Icons.verified_outlined;
      case P09RepairWorkflowStage.readyForDelivery:
        return Icons.local_shipping_outlined;
      case P09RepairWorkflowStage.delivered:
        return Icons.person_outline;
      case P09RepairWorkflowStage.closed:
        return Icons.lock_outline;
      default:
        return Icons.request_quote_outlined;
    }
  }

  Future<void> _prepareEstimate() async {
    final current = _workflow;
    if (current == null) return;
    final assessment = TextEditingController(text: current.damageAssessment);
    DateTime validUntil =
        current.quoteValidUntil ?? DateTime.now().add(const Duration(days: 14));

    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => _WorkflowDialog(
          title: 'إعداد عرض السعر',
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حفظ العرض'),
            ),
          ],
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'قيمة العرض الحالية: ${MoneyFormatter.format(widget.repair.fileValue)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: assessment,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'تقييم الأضرار والأعمال المقترحة',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_outlined),
                  label: Text('صالح حتى ${_dateFormat.format(validUntil)}'),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDate: validUntil.isBefore(DateTime.now())
                          ? DateTime.now()
                          : validUntil,
                    );
                    if (picked != null) {
                      setDialogState(() => validUntil = picked);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (submit != true) return;

    try {
      await RepairWorkflowService.prepareEstimate(
        repairId: widget.repair.id,
        damageAssessment: assessment.text,
        validUntil: validUntil,
      );
      await _afterChange();
      _message('تم إعداد عرض السعر دون إنشاء فاتورة أو قيد محاسبي');
    } catch (e) {
      _message('$e');
    } finally {
      assessment.dispose();
    }
  }

  Future<void> _markSent() async {
    try {
      await RepairWorkflowService.markEstimateSent(widget.repair.id);
      await _afterChange();
      _message('تم تسجيل إرسال عرض السعر');
    } catch (e) {
      _message('$e');
    }
  }

  Future<void> _recordCustomerResponse() async {
    final response = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'رد العميل على عرض السعر',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.pop(sheetContext, 'approve'),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('تسجيل الموافقة'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(sheetContext, 'reject'),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('تسجيل الرفض'),
              ),
            ],
          ),
        ),
      ),
    );
    if (response == 'approve') await _approve();
    if (response == 'reject') await _reject();
  }

  Future<void> _approve() async {
    const methods = [
      'إقرار حضوري',
      'هاتف',
      'WhatsApp',
      'توقيع على الشاشة',
    ];
    String method = methods.first;
    final note = TextEditingController();
    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => _WorkflowDialog(
          title: 'تسجيل موافقة العميل',
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('اعتماد الموافقة'),
            ),
          ],
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: method,
                  items: methods
                      .map((value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setDialogState(() => method = value);
                  },
                  decoration: const InputDecoration(
                    labelText: 'طريقة الموافقة',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة اختيارية',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (submit != true) {
      note.dispose();
      return;
    }
    try {
      await RepairWorkflowService.approveEstimate(
        repairId: widget.repair.id,
        method: method,
        note: note.text,
      );
      await _afterChange();
      _message('تم تسجيل الموافقة تشغيليًا فقط — بدون فاتورة أو GL');
    } catch (e) {
      _message('$e');
    } finally {
      note.dispose();
    }
  }

  Future<void> _reject() async {
    final reason = TextEditingController();
    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _WorkflowDialog(
        title: 'تسجيل رفض العرض',
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تسجيل الرفض'),
          ),
        ],
        child: TextField(
          controller: reason,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'سبب الرفض (اختياري)',
            border: OutlineInputBorder(),
          ),
        ),
      ),
    );
    if (submit != true) {
      reason.dispose();
      return;
    }
    try {
      await RepairWorkflowService.rejectEstimate(
        repairId: widget.repair.id,
        reason: reason.text,
      );
      await _afterChange();
      _message('تم تسجيل رفض العرض');
    } catch (e) {
      _message('$e');
    } finally {
      reason.dispose();
    }
  }

  Future<List<Employee>> _activeEmployees() async {
    final all = await EmployeeService.getAllEmployees();
    final active = all.where((employee) {
      final status = employee.status.trim().toLowerCase();
      return status != 'inactive' && status != 'terminated';
    }).toList();
    return active.isEmpty ? all : active;
  }

  Future<String?> _quickAddEmployee() async {
    final name = TextEditingController();
    final jobTitle = TextEditingController(text: 'فني');
    final createdId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _WorkflowDialog(
        title: 'إضافة موظف سريع',
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              final fullName = name.text.trim();
              final title = jobTitle.text.trim();
              if (fullName.isEmpty || title.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                      content: Text('أدخل اسم الموظف والمسمى الوظيفي.')),
                );
                return;
              }
              final code = 'EMP-${DateTime.now().millisecondsSinceEpoch}';
              try {
                await EmployeeService.addEmployee(
                  Employee.fromMap(<String, dynamic>{
                    'id': '',
                    'full_name': fullName,
                    'employee_code': code,
                    'job_title': title,
                    'hire_date': DateTime.now().toIso8601String(),
                    'status': 'active',
                    'contract_type': 'monthly',
                    'base_salary': 0.0,
                    'allowances': 0.0,
                    'deductions': 0.0,
                    'advances': 0.0,
                    'payment_method': 'cash',
                    'work_days_per_week': 6,
                    'hours_per_day': 8,
                  }),
                );
                final employees = await EmployeeService.getAllEmployees();
                final created = employees.where((e) => e.employeeCode == code);
                if (created.isEmpty) {
                  throw StateError('employee_not_found_after_save');
                }
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, created.first.id);
                }
              } catch (e) {
                debugPrint('Quick employee creation failed: $e');
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content:
                          Text('تعذر إضافة الموظف. لم يتم تغيير ملف الإصلاح.'),
                    ),
                  );
                }
              }
            },
            child: const Text('إضافة واختيار'),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'اسم الموظف',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: jobTitle,
              decoration: const InputDecoration(
                labelText: 'المسمى الوظيفي',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    jobTitle.dispose();
    return createdId;
  }

  Future<String?> _chooseEmployee({bool allowUnassigned = false}) async {
    final employees = await _activeEmployees();
    if (!mounted) return null;
    if (employees.isEmpty) {
      final created = await _quickAddEmployee();
      if (created != null) return created;
      return allowUnassigned ? '' : null;
    }

    String? selected = _workflow?.responsibleEmployeeId;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => _WorkflowDialog(
          title: 'المسؤول / الفني',
          actions: [
            if (allowUnassigned)
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, ''),
                child: const Text('لاحقًا'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: selected == null
                  ? null
                  : () => Navigator.pop(dialogContext, selected),
              child: const Text('اختيار'),
            ),
          ],
          child: DropdownButtonFormField<String>(
            value: employees.any((e) => e.id == selected) ? selected : null,
            items: employees
                .map((employee) => DropdownMenuItem(
                      value: employee.id,
                      child:
                          Text('${employee.fullName} — ${employee.jobTitle}'),
                    ))
                .toList(),
            onChanged: (value) => setDialogState(() => selected = value),
            decoration: const InputDecoration(
              labelText: 'اختر المسؤول عن الملف',
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ),
    );
    return result;
  }

  Future<void> _createWorkOrder() async {
    final employeeId = await _chooseEmployee(allowUnassigned: true);
    if (employeeId == null) return;
    try {
      await RepairWorkflowService.createWorkOrder(
        repairId: widget.repair.id,
        responsibleEmployeeId: employeeId,
      );
      await _afterChange();
      _message('تم إنشاء أمر العمل');
    } catch (e) {
      _message('$e');
    }
  }

  Future<void> _assignResponsible() async {
    final employeeId = await _chooseEmployee();
    if (employeeId == null || employeeId.isEmpty) return;
    try {
      await RepairWorkflowService.assignResponsible(
        repairId: widget.repair.id,
        employeeId: employeeId,
      );
      await _afterChange();
      _message('تم تعيين المسؤول عن الملف');
    } catch (e) {
      _message('$e');
    }
  }

  Future<void> _startWork() async {
    try {
      await RepairWorkflowService.startWork(widget.repair.id);
      await _afterChange();
      _message('تم بدء التنفيذ');
    } catch (e) {
      _message('$e');
    }
  }

  Future<void> _readyForQc() async {
    try {
      await RepairWorkflowService.markReadyForQc(widget.repair.id);
      await _afterChange();
      _message('تم تحويل الملف للفحص الأولي');
    } catch (e) {
      _message('$e');
    }
  }

  Future<void> _initialQc() async {
    bool work = false;
    bool finish = false;
    bool cleanliness = false;
    bool docs = false;
    final notes = TextEditingController();
    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => _WorkflowDialog(
          title: 'الفحص الأولي للجودة',
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: work && finish && cleanliness && docs
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: const Text('اعتماد الفحص'),
            ),
          ],
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  value: work,
                  onChanged: (value) =>
                      setDialogState(() => work = value ?? false),
                  title: const Text('الأعمال المطلوبة مكتملة'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  value: finish,
                  onChanged: (value) =>
                      setDialogState(() => finish = value ?? false),
                  title: const Text('التشطيب الظاهري مفحوص'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  value: cleanliness,
                  onChanged: (value) =>
                      setDialogState(() => cleanliness = value ?? false),
                  title: const Text('تنظيف أولي للمركبة'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  value: docs,
                  onChanged: (value) =>
                      setDialogState(() => docs = value ?? false),
                  title: const Text('الصور/المستندات محدثة'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notes,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات الفحص (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (submit != true) {
      notes.dispose();
      return;
    }
    try {
      await RepairWorkflowService.completeInitialQc(
        repairId: widget.repair.id,
        workComplete: work,
        finishChecked: finish,
        cleanlinessChecked: cleanliness,
        documentationChecked: docs,
        notes: notes.text,
      );
      await _afterChange();
      _message('تم اعتماد الفحص الأولي. التسليم النهائي يبقى ضمن P13.');
    } catch (e) {
      _message('$e');
    } finally {
      notes.dispose();
    }
  }

  Future<void> _finalQc() async {
    bool work = false;
    bool finish = false;
    bool cleanliness = false;
    bool docs = false;
    final notes = TextEditingController();
    final submit = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => _WorkflowDialog(
          title: 'فحص الجودة النهائي',
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(dialogContext, 'rework'),
              child: const Text('إرجاع للتنفيذ'),
            ),
            FilledButton(
              onPressed: work && finish && cleanliness && docs
                  ? () => Navigator.pop(dialogContext, 'pass')
                  : null,
              child: const Text('اعتماد الجودة النهائية'),
            ),
          ],
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  value: work,
                  onChanged: (value) =>
                      setDialogState(() => work = value ?? false),
                  title: const Text('جميع أعمال أمر العمل مكتملة'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  value: finish,
                  onChanged: (value) =>
                      setDialogState(() => finish = value ?? false),
                  title: const Text('التشطيب النهائي مطابق'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  value: cleanliness,
                  onChanged: (value) =>
                      setDialogState(() => cleanliness = value ?? false),
                  title: const Text('المركبة جاهزة ونظيفة للتسليم'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  value: docs,
                  onChanged: (value) =>
                      setDialogState(() => docs = value ?? false),
                  title: const Text('الصور والمستندات النهائية محدثة'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notes,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات الجودة النهائية (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (submit == null) {
      notes.dispose();
      return;
    }
    try {
      if (submit == 'rework') {
        if (notes.text.trim().isEmpty) {
          _message('اكتب سبب إعادة المركبة للتنفيذ في ملاحظات الجودة');
          return;
        }
        await RepairWorkflowService.returnFinalQcToWork(
          repairId: widget.repair.id,
          reason: notes.text,
        );
        await _afterChange();
        _message('أعيدت المركبة للتنفيذ بسبب موثق');
        return;
      }
      await RepairWorkflowService.completeFinalQc(
        repairId: widget.repair.id,
        workVerified: work,
        finishVerified: finish,
        cleanlinessVerified: cleanliness,
        documentationVerified: docs,
        notes: notes.text,
      );
      await _afterChange();
      _message('تم اعتماد فحص الجودة النهائي');
    } catch (e) {
      _message('$e');
    } finally {
      notes.dispose();
    }
  }

  Future<void> _markReadyForDelivery() async {
    try {
      await RepairWorkflowService.markReadyForDelivery(widget.repair.id);
      await _afterChange();
      _message('المركبة الآن جاهزة للتسليم');
    } catch (e) {
      _message('$e');
    }
  }

  Future<void> _deliver() async {
    final recipient = TextEditingController();
    final note = TextEditingController();
    const methods = <String>[
      'تأكيد الموظف + اسم المستلم',
      'توقيع ورقي',
      'توقيع إلكتروني',
      'استلام جهة / مفوض',
    ];
    String method = methods.first;
    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => _WorkflowDialog(
          title: 'تسليم المركبة',
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('تأكيد التسليم'),
            ),
          ],
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: recipient,
                  decoration: const InputDecoration(
                    labelText: 'اسم المستلم *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: method,
                  isExpanded: true,
                  items: methods
                      .map((value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setDialogState(() => method = value);
                  },
                  decoration: const InputDecoration(
                    labelText: 'إثبات التسليم',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'توقيع العميل اختياري؛ اسم المستلم + تأكيد الموظف إثبات عملي كافٍ.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة التسليم (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (submit != true) {
      recipient.dispose();
      note.dispose();
      return;
    }
    try {
      await RepairWorkflowService.recordDelivery(
        repairId: widget.repair.id,
        recipientName: recipient.text,
        proofMethod: method,
        note: note.text,
      );
      await _afterChange();
      _message(
          'تم توثيق تسليم المركبة. الذمة المالية تبقى مستقلة حتى الإغلاق.');
    } catch (e) {
      _message('$e');
    } finally {
      recipient.dispose();
      note.dispose();
    }
  }

  Future<void> _closeRepair() async {
    final note = TextEditingController();
    final remaining = widget.repair.remainingAmount;
    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _WorkflowDialog(
        title: 'إغلاق ملف الإصلاح',
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: remaining > 0.005
                ? null
                : () => Navigator.pop(dialogContext, true),
            child: const Text('إغلاق رسمي'),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
                'قيمة الملف: ${MoneyFormatter.format(widget.repair.fileValue)}'),
            Text(
                'المدفوع: ${MoneyFormatter.format(widget.repair.totalPaidAmount)}'),
            Text(
              'المتبقي: ${MoneyFormatter.format(remaining)}',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: remaining > 0.005
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'ملاحظة الإغلاق (اختياري)',
                border: OutlineInputBorder(),
              ),
            ),
            if (remaining > 0.005) ...[
              const SizedBox(height: 10),
              const Text(
                'تم تسليم المركبة، لكن الإغلاق النهائي ينتظر تسوية الذمة. لا يتم حذف أو تعديل أي قيد مالي.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ],
        ),
      ),
    );
    if (submit != true) {
      note.dispose();
      return;
    }
    try {
      await RepairWorkflowService.closeRepair(
        repairId: widget.repair.id,
        note: note.text,
      );
      await _afterChange();
      _message('تم إغلاق الملف رسميًا');
    } catch (e) {
      _message('$e');
    } finally {
      note.dispose();
    }
  }

  Future<void> _runPrimaryAction() async {
    final workflow = _workflow;
    if (workflow == null) return;
    switch (workflow.stage) {
      case P09RepairWorkflowStage.draft:
        if ((workflow.quoteNumber ?? '').trim().isEmpty) {
          await _prepareEstimate();
        } else {
          await _markSent();
        }
        break;
      case P09RepairWorkflowStage.sent:
        await _recordCustomerResponse();
        break;
      case P09RepairWorkflowStage.rejected:
        try {
          await RepairWorkflowService.reopenRejectedEstimate(widget.repair.id);
          await _afterChange();
          await _prepareEstimate();
        } catch (e) {
          _message('$e');
        }
        break;
      case P09RepairWorkflowStage.approved:
        await _createWorkOrder();
        break;
      case P09RepairWorkflowStage.workOrder:
        if ((workflow.responsibleEmployeeId ?? '').trim().isEmpty) {
          await _assignResponsible();
        } else {
          await _startWork();
        }
        break;
      case P09RepairWorkflowStage.inProgress:
        await _readyForQc();
        break;
      case P09RepairWorkflowStage.readyForQc:
        await _initialQc();
        break;
      case P09RepairWorkflowStage.qcChecked:
        await _finalQc();
        break;
      case P09RepairWorkflowStage.finalQc:
        await _markReadyForDelivery();
        break;
      case P09RepairWorkflowStage.readyForDelivery:
        await _deliver();
        break;
      case P09RepairWorkflowStage.delivered:
        await _closeRepair();
        break;
      case P09RepairWorkflowStage.closed:
        _message(
            'الملف مغلق رسميًا. إعادة الفتح تتم بسبب موثق من قائمة الملفات المغلقة.');
        break;
    }
  }

  String _primaryLabel(RepairWorkflowState workflow) {
    switch (workflow.stage) {
      case P09RepairWorkflowStage.draft:
        return (workflow.quoteNumber ?? '').trim().isEmpty
            ? 'إعداد عرض السعر'
            : 'تسجيل إرسال العرض';
      case P09RepairWorkflowStage.sent:
        return 'تسجيل رد العميل';
      case P09RepairWorkflowStage.rejected:
        return 'تعديل وإعادة إعداد العرض';
      case P09RepairWorkflowStage.approved:
        return 'إنشاء أمر العمل';
      case P09RepairWorkflowStage.workOrder:
        return (workflow.responsibleEmployeeId ?? '').trim().isEmpty
            ? 'تعيين المسؤول / الفني'
            : 'بدء التنفيذ';
      case P09RepairWorkflowStage.inProgress:
        return 'جاهز للفحص الأولي';
      case P09RepairWorkflowStage.readyForQc:
        return 'إجراء الفحص الأولي';
      case P09RepairWorkflowStage.qcChecked:
        return 'فحص الجودة النهائي';
      case P09RepairWorkflowStage.finalQc:
        return 'اعتماد الجاهزية للتسليم';
      case P09RepairWorkflowStage.readyForDelivery:
        return 'تسليم المركبة';
      case P09RepairWorkflowStage.delivered:
        return 'إغلاق الملف';
      case P09RepairWorkflowStage.closed:
        return 'الملف مغلق';
      default:
        return 'متابعة';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final workflow = _workflow;
    if (workflow == null) return const SizedBox.shrink();

    final canShare = (workflow.quoteNumber ?? '').trim().isNotEmpty &&
        widget.onShareEstimate != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                const Text(
                  'سير العمل',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                ),
                Chip(
                  avatar: Icon(_stageIcon(workflow.stage), size: 18),
                  label: Text(_stageLabel(workflow.stage)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if ((workflow.quoteNumber ?? '').trim().isNotEmpty)
                  _InfoChip(
                    icon: Icons.numbers,
                    text: workflow.quoteNumber!,
                  ),
                if (workflow.quoteValidUntil != null)
                  _InfoChip(
                    icon: Icons.event_available_outlined,
                    text:
                        'صالح حتى ${_dateFormat.format(workflow.quoteValidUntil!)}',
                  ),
                _InfoChip(
                  icon: Icons.payments_outlined,
                  text: MoneyFormatter.format(widget.repair.fileValue),
                ),
                if ((workflow.workOrderNumber ?? '').trim().isNotEmpty)
                  _InfoChip(
                    icon: Icons.assignment_outlined,
                    text: workflow.workOrderNumber!,
                  ),
                if ((_responsibleName ?? '').trim().isNotEmpty)
                  _InfoChip(
                    icon: Icons.engineering_outlined,
                    text: _responsibleName!,
                  ),
                if ((workflow.handoverRecipient ?? '').trim().isNotEmpty)
                  _InfoChip(
                    icon: Icons.person_outline,
                    text: 'المستلم: ${workflow.handoverRecipient}',
                  ),
                if (workflow.deliveredAt != null)
                  _InfoChip(
                    icon: Icons.local_shipping_outlined,
                    text: 'سُلّمت ${_dateFormat.format(workflow.deliveredAt!)}',
                  ),
                if (workflow.closedAt != null)
                  _InfoChip(
                    icon: Icons.lock_outline,
                    text: 'أُغلقت ${_dateFormat.format(workflow.closedAt!)}',
                  ),
              ],
            ),
            if (workflow.damageAssessment.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                workflow.damageAssessment.trim(),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (workflow.stage == P09RepairWorkflowStage.rejected &&
                (workflow.rejectionReason ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'سبب الرفض: ${workflow.rejectionReason}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: workflow.stage == P09RepairWorkflowStage.closed
                      ? null
                      : _runPrimaryAction,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(_primaryLabel(workflow)),
                ),
                if (canShare)
                  OutlinedButton.icon(
                    onPressed: widget.onShareEstimate,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('نسخة عرض السعر'),
                  ),
                if ((workflow.quoteNumber ?? '').trim().isNotEmpty &&
                    (workflow.stage == P09RepairWorkflowStage.draft ||
                        workflow.stage == P09RepairWorkflowStage.rejected))
                  TextButton.icon(
                    onPressed: _prepareEstimate,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('تعديل العرض'),
                  ),
                if (workflow.stage == P09RepairWorkflowStage.workOrder &&
                    (workflow.responsibleEmployeeId ?? '').trim().isNotEmpty)
                  TextButton.icon(
                    onPressed: _assignResponsible,
                    icon: const Icon(Icons.person_search_outlined),
                    label: const Text('تغيير المسؤول'),
                  ),
              ],
            ),
            if (workflow.stage == P09RepairWorkflowStage.delivered &&
                widget.repair.remainingAmount > 0.005) ...[
              const SizedBox(height: 10),
              const Text(
                '✓ المركبة مسلّمة. الإغلاق الرسمي ينتظر تسوية الذمة المالية.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
            if (workflow.stage == P09RepairWorkflowStage.closed) ...[
              const SizedBox(height: 10),
              const Text(
                '✓ الملف مغلق رسميًا ومحفوظ في المركبات المغلقة.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          Icon(icon, size: 16),
          Text(text),
        ],
      ),
    );
  }
}

class _WorkflowDialog extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget> actions;

  const _WorkflowDialog({
    required this.title,
    required this.child,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: viewport.height * 0.88,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 16),
              Flexible(child: child),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: actions,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
