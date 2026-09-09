import 'package:flutter/material.dart';

/// ISO week starts Monday; preset ranges end today, not at a future date.
class FinancialPeriodFilter extends StatelessWidget {
  const FinancialPeriodFilter(
      {super.key, required this.onChanged, this.from, this.to});
  final DateTime? from, to;
  final ValueChanged<DateTimeRange> onChanged;
  static DateTimeRange preset(String key, DateTime now) {
    final day = DateTime(now.year, now.month, now.day);
    return DateTimeRange(
        start: key == 'week'
            ? DateTime(day.year, day.month, day.day - day.weekday + 1)
            : key == 'month'
                ? DateTime(day.year, day.month, 1)
                : day,
        end: day);
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'فترة التقرير',
        onSelected: (key) async {
          if (key != 'custom') {
            onChanged(preset(key, DateTime.now()));
            return;
          }
          final now = DateTime.now();
          final range = await showDateRangePicker(
              context: context,
              firstDate: DateTime(1900),
              lastDate: DateTime(now.year + 10, 12, 31),
              initialDateRange:
                  from != null && to != null && !from!.isAfter(to!)
                      ? DateTimeRange(start: from!, end: to!)
                      : null);
          if (context.mounted && range != null) onChanged(range);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'today', child: Text('اليوم')),
          PopupMenuItem(
              value: 'week', child: Text('الأسبوع الحالي (من الاثنين)')),
          PopupMenuItem(value: 'month', child: Text('الشهر الحالي')),
          PopupMenuItem(value: 'custom', child: Text('فترة مخصصة'))
        ],
        child: const Padding(
            padding: EdgeInsets.all(8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.date_range, size: 20),
              SizedBox(width: 6),
              Text('فترة التقرير')
            ])),
      );
}
