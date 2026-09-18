// 📁 lib/features/home/widgets/today_timeline.dart
//
// TodayTimeline — خط زمني لعمليات اليوم
// --------------------------------------
// يعتمد على DBService كمصدر وحيد للحقيقة.
// يعرض آخر العمليات (إصلاحات، قبض/صرف، حضور) مرتبة زمنياً من الأحدث للأقدم.
// لا بيانات وهمية، فقط نتائج حقيقية من الجداول.
//
// يستخدم داخل الصفحة الرئيسية لتوفير "نظرة اليوم".

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class TodayTimeline extends StatefulWidget {
  const TodayTimeline({super.key});

  @override
  State<TodayTimeline> createState() => _TodayTimelineState();
}

class _TodayTimelineState extends State<TodayTimeline> {
  List<_TimelineEvent> events = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    final db = await DBService.database;
    final now = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final List<_TimelineEvent> list = [];

    // إصلاحات اليوم
    final repairs = await db.rawQuery('''
      SELECT id, vehicle_type AS info, status, updated_at
      FROM repairs
      WHERE DATE(updated_at)=?
      ORDER BY updated_at DESC
      LIMIT 10
    ''', [now]);

    for (final r in repairs) {
      list.add(_TimelineEvent(
        time: r['updated_at']?.toString() ?? '',
        title: 'تحديث إصلاح مركبة',
        subtitle: '${r['info'] ?? 'مركبة'} - ${r['status'] ?? ''}',
        color: AppColors.primary,
        icon: Icons.directions_car,
      ));
    }

    // حركات GL اليوم (قبض / صرف)
    final gl = await db.rawQuery('''
      SELECT ref, note, SUM(debit) AS d, SUM(credit) AS c, date
      FROM gl_lines
      WHERE date=?
      GROUP BY ref, note
      ORDER BY date DESC
      LIMIT 10
    ''', [now]);

    for (final g in gl) {
      final d = (g['d'] ?? 0) as num;
      final c = (g['c'] ?? 0) as num;
      final isInflow = d > c;
      list.add(_TimelineEvent(
        time: g['date']?.toString() ?? '',
        title: isInflow ? 'عملية قبض' : 'عملية صرف',
        subtitle: g['note']?.toString() ?? '',
        color: isInflow ? AppColors.primary : Colors.redAccent,
        icon: isInflow ? Icons.arrow_downward : Icons.arrow_upward,
      ));
    }

    // حضور الموظفين اليوم
    final attendance = await db.rawQuery('''
      SELECT employeeId, status, date
      FROM attendance
      WHERE date=?
      ORDER BY date DESC
      LIMIT 10
    ''', [now]);

    for (final a in attendance) {
      list.add(_TimelineEvent(
        time: a['date']?.toString() ?? '',
        title: 'سجل حضور موظف',
        subtitle: '${a['employeeId'] ?? ''} - ${a['status'] ?? ''}',
        color: Colors.orangeAccent,
        icon: Icons.people_alt,
      ));
    }

    list.sort((a, b) => b.time.compareTo(a.time));

    if (mounted) {
      setState(() {
        events = list;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (events.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد عمليات اليوم بعد',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🕒 نشاط اليوم',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 10),
            ...events.map((e) => _buildEvent(e)),
          ],
        ),
      ),
    );
  }

  Widget _buildEvent(_TimelineEvent e) {
    final time = e.time.length >= 16 ? e.time.substring(11, 16) : e.time;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: AdaptiveRow(
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: e.color.withOpacity(0.2),
            ),
            padding: const EdgeInsets.all(6),
            child: Icon(e.icon, color: e.color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  e.subtitle,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            time,
            style: const TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _TimelineEvent {
  final String time;
  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;

  _TimelineEvent({
    required this.time,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
  });
}
