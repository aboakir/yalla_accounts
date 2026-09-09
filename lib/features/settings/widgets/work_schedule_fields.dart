import 'package:flutter/material.dart';

class WorkScheduleFields extends StatelessWidget {
  const WorkScheduleFields(
      {super.key,
      required this.days,
      required this.hours,
      required this.breakMinutes,
      required this.onDays,
      required this.onHours,
      required this.onBreak,
      required this.overtime,
      required this.onOvertime});
  final String days;
  final double hours;
  final int breakMinutes;
  final double? overtime;
  final ValueChanged<String> onDays;
  final ValueChanged<double> onHours;
  final ValueChanged<int> onBreak;
  final ValueChanged<double> onOvertime;
  @override
  Widget build(BuildContext context) {
    final selected = days.split(',').toSet();
    const labels = {
      1: 'الاثنين',
      2: 'الثلاثاء',
      3: 'الأربعاء',
      4: 'الخميس',
      5: 'الجمعة',
      6: 'السبت',
      7: 'الأحد'
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('أيام العمل — الأيام غير المحددة عطلة أسبوعية'),
      Wrap(
          spacing: 6,
          children: labels.entries
              .map((day) => FilterChip(
                  label: Text(day.value),
                  selected: selected.contains('${day.key}'),
                  onSelected: (enabled) {
                    final next = {...selected};
                    enabled
                        ? next.add('${day.key}')
                        : next.remove('${day.key}');
                    final sorted = next.where((e) => e.isNotEmpty).toList()
                      ..sort();
                    onDays(sorted.join(','));
                  }))
              .toList()),
      TextFormField(
          initialValue: hours.toString(),
          keyboardType: TextInputType.number,
          decoration:
              const InputDecoration(labelText: 'ساعات العمل اليومية المدفوعة'),
          onChanged: (v) => onHours(double.tryParse(v) ?? 0)),
      TextFormField(
          initialValue: breakMinutes.toString(),
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              labelText: 'الاستراحة غير المدفوعة بالدقائق'),
          onChanged: (v) => onBreak(int.tryParse(v) ?? -1)),
      TextFormField(
          initialValue: (overtime ?? 1.25).toString(),
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              labelText: 'معدل الإضافي',
              helperText:
                  '0: بدون إضافي • حتى 5: معامل الساعة • أكثر من 5: مبلغ لكل ساعة (النظام الحالي)'),
          onChanged: (v) => onOvertime(double.tryParse(v) ?? -1)),
    ]);
  }
}
