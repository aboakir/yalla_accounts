import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/models/policy_draft.dart';

class StepPolicyDates extends StatefulWidget {
  final PolicyDraft draft;

  const StepPolicyDates({
    super.key,
    required this.draft,
  });

  @override
  State<StepPolicyDates> createState() => _StepPolicyDatesState();
}

class _StepPolicyDatesState extends State<StepPolicyDates> {
  final _fmt = DateFormat('yyyy-MM-dd');

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final initial = widget.draft.startDate ?? now;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 10),
    );

    if (picked == null) return;

    setState(() {
      widget.draft.startDate = DateTime(picked.year, picked.month, picked.day);

      // لو النهاية قبل البداية: نرفع النهاية تلقائياً (سنة مثلاً) بشكل منطقي
      final end = widget.draft.endDate;
      if (end != null && end.isBefore(widget.draft.startDate!)) {
        widget.draft.endDate =
            widget.draft.startDate!.add(const Duration(days: 365));
      }
    });
  }

  Future<void> _pickEnd() async {
    final now = DateTime.now();
    final initial = widget.draft.endDate ??
        (widget.draft.startDate?.add(const Duration(days: 365)) ?? now);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: widget.draft.startDate ?? DateTime(now.year - 2),
      lastDate: DateTime(now.year + 10),
    );

    if (picked == null) return;

    setState(() {
      widget.draft.endDate = DateTime(picked.year, picked.month, picked.day);
    });
  }

  String _d(DateTime? v) => v == null ? 'غير محدد' : _fmt.format(v);

  @override
  Widget build(BuildContext context) {
    final start = widget.draft.startDate;
    final end = widget.draft.endDate;

    final invalidRange = (start != null && end != null && end.isBefore(start));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'مدة التأمين (البداية والنهاية)',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.right,
        ),
        const SizedBox(height: 16),
        _dateCard(
          title: 'تاريخ بداية التأمين',
          value: _d(start),
          onPick: _pickStart,
          icon: Icons.event_available,
        ),
        const SizedBox(height: 12),
        _dateCard(
          title: 'تاريخ انتهاء التأمين',
          value: _d(end),
          onPick: _pickEnd,
          icon: Icons.event_busy,
        ),
        if (invalidRange) ...[
          const SizedBox(height: 12),
          const Text(
            'تنبيه: تاريخ الانتهاء لا يمكن أن يكون قبل تاريخ البداية.',
            style: TextStyle(color: Colors.red),
            textAlign: TextAlign.right,
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'ملاحظة: سيتم لاحقاً إضافة تنبيه قبل الانتهاء بـ 12 يوم داخل نظام التنبيهات.',
          style: TextStyle(color: Colors.grey.shade700, height: 1.4),
          textAlign: TextAlign.right,
        ),
      ],
    );
  }

  Widget _dateCard({
    required String title,
    required String value,
    required VoidCallback onPick,
    required IconData icon,
  }) {
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    textAlign: TextAlign.right,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: TextStyle(color: Colors.grey.shade700),
                    textAlign: TextAlign.right,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_left),
          ],
        ),
      ),
    );
  }
}
