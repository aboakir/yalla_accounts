// 📁 lib/features/home/widgets/smart_cards.dart
// SmartCards — بطاقات ذكية ثابتة الارتفاع بدون Overflow.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';

class SmartCards extends StatefulWidget {
  final VoidCallback? onOpenStuckRepairs;
  final VoidCallback? onOpenClientsAR;
  final VoidCallback? onOpenSuppliersAP;
  final VoidCallback? onOpenAttendance;

  const SmartCards({
    super.key,
    this.onOpenStuckRepairs,
    this.onOpenClientsAR,
    this.onOpenSuppliersAP,
    this.onOpenAttendance,
  });

  @override
  State<SmartCards> createState() => _SmartCardsState();
}

class _SmartCardsState extends State<SmartCards> {
  bool loading = true;

  int stuckRepairs = 0;
  double clientsAR = 0;
  double suppliersAP = 0;
  int absentsToday = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<bool> _hasColumn(Database db, String table, String column) async {
    final info = await db.rawQuery('PRAGMA table_info($table);');
    for (final m in info) {
      final name = (m['name'] ?? '').toString().toLowerCase();
      if (name == column.toLowerCase()) return true;
    }
    return false;
  }

  Future<void> _load() async {
    final db = await DBService.database;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    try {
      // 1) ملفات عالقة
      final hasLastAct = await _hasColumn(db, 'repairs', 'last_activity_at');
      final stuck = await db.rawQuery('''
        SELECT COUNT(*) AS c
        FROM repairs
        WHERE status NOT IN ('CLOSED','مغلق','تم التسليم')
          AND DATE(${hasLastAct ? 'last_activity_at' : 'updated_at'}) <= DATE('now','-3 day')
      ''');
      stuckRepairs = _asInt(stuck.first['c']);

      // 2) ذمم العملاء
      final hasDueGL = await _hasColumn(db, 'gl_lines', 'due_date');
      final ar = await db.rawQuery('''
        SELECT IFNULL(SUM(credit - debit), 0) AS bal
        FROM gl_lines
        WHERE party_type='CLIENT'
          AND (credit - debit) > 0
          AND DATE(${hasDueGL ? 'due_date' : 'date'})
              <= ${hasDueGL ? "DATE('now')" : "DATE('now','-7 day')"}
      ''');
      clientsAR = _asDouble(ar.first['bal']);

      // 3) ذمم الموردين
      final ap = await db.rawQuery('''
        SELECT IFNULL(SUM(debit - credit), 0) AS bal
        FROM gl_lines
        WHERE party_type='SUPPLIER'
          AND (debit - credit) > 0
          AND DATE(${hasDueGL ? 'due_date' : 'date'})
              <= ${hasDueGL ? "DATE('now')" : "DATE('now','-7 day')"}
      ''');
      suppliersAP = _asDouble(ap.first['bal']);

      // 4) غياب اليوم
      final attendance = await db.rawQuery('''
        SELECT COUNT(*) AS c
        FROM attendance
        WHERE date=? AND LOWER(status) IN ('absent','غياب','غائب','غير موجود')
      ''', [today]);
      absentsToday = _asInt(attendance.first['c']);
    } catch (_) {
      // فشل آمن
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  int _asInt(Object? v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  double _asDouble(Object? v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const _SkeletonGrid();

    final tiles = [
      _SmartTile(
        color: Colors.orange,
        icon: Icons.warning_amber_rounded,
        title: 'ملفات عالقة',
        value: '$stuckRepairs',
        caption: 'بدون حركة منذ 3 أيام',
        actionLabel: 'افتح الملفات',
        onAction: widget.onOpenStuckRepairs,
      ),
      _SmartTile(
        color: Colors.redAccent,
        icon: Icons.request_quote,
        title: 'ذمم العملاء',
        value: _fmtCurrency(clientsAR),
        caption: 'مستحقة/متأخرة',
        actionLabel: 'إدارة التحصيل',
        onAction: widget.onOpenClientsAR,
      ),
      _SmartTile(
        color: Colors.blueGrey,
        icon: Icons.account_balance_wallet,
        title: 'ذمم الموردين',
        value: _fmtCurrency(suppliersAP),
        caption: 'مستحقة/متأخرة',
        actionLabel: 'سدد الآن',
        onAction: widget.onOpenSuppliersAP,
      ),
      _SmartTile(
        color: Colors.deepPurple,
        icon: Icons.event_busy,
        title: 'غياب اليوم',
        value: '$absentsToday',
        caption: 'تقرير الحضور',
        actionLabel: 'إدارة الحضور',
        onAction: widget.onOpenAttendance,
      ),
    ];

    return LayoutBuilder(
      builder: (ctx, c) {
        final isWide = c.maxWidth >= 900;
        // ارتفاع صريح يمنع أي Overflow. زدناه قليلاً.
        final mainExtent = isWide ? 140.0 : 164.0;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: tiles.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isWide ? 4 : 1,
            mainAxisExtent: mainExtent,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          itemBuilder: (_, i) => tiles[i],
        );
      },
    );
  }

  String _fmtCurrency(double v) {
    final nf = NumberFormat('#,##0.##');
    return '${MoneyFormatter.format(v)}';
  }
}

// =============== UI Components ===============

class _SmartTile extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String value;
  final String caption;
  final String actionLabel;
  final VoidCallback? onAction;

  const _SmartTile({
    required this.color,
    required this.icon,
    required this.title,
    required this.value,
    required this.caption,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _cardDecoration(context),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.15),
                ),
                padding: const EdgeInsets.all(8),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: color),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 6), // بدل Spacer لتثبيت الارتفاع
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.chevron_right,
                  color: AppColors.primary, size: 18),
              label: const Text(
                'فتح',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.w700),
              ),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                foregroundColor: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration(BuildContext context) {
    return BoxDecoration(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.primary.withOpacity(0.08)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }
}

class _SkeletonGrid extends StatelessWidget {
  const _SkeletonGrid();

  @override
  Widget build(BuildContext context) {
    Widget box(double h) => Container(
          height: h,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
          ),
        );

    return LayoutBuilder(
      builder: (_, c) {
        final isWide = c.maxWidth >= 900;
        final mainExtent = isWide ? 140.0 : 164.0;
        return GridView.count(
          crossAxisCount: isWide ? 4 : 1,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: List.generate(4, (_) => box(mainExtent)),
        );
      },
    );
  }
}
