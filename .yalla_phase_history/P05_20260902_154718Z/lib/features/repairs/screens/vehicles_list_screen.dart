// 📁 lib/features/repairs/screens/vehicles_list_screen.dart
import 'dart:io';
import 'package:yalla_accounts/core/services/db_service.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/services/repair_database_service.dart';
import 'package:yalla_accounts/features/repairs/screens/add_repair_screen.dart';
import 'package:yalla_accounts/features/repairs/screens/repair_details_screen.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class RepairThumbSmall extends StatelessWidget {
  final String repairId;
  final String? fallbackFirstPath;
  final double size;
  final double radius;

  const RepairThumbSmall({
    super.key,
    required this.repairId,
    required this.fallbackFirstPath,
    required this.size,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: DBService.getRepairThumbnailPath(repairId),
      builder: (context, snap) {
        String? path = snap.data;
        File? file;

        try {
          if (path != null && path.isNotEmpty) {
            final f = File(path);
            if (f.existsSync()) file = f;
          }
          if (file == null && fallbackFirstPath != null) {
            final f = File(fallbackFirstPath!);
            if (f.existsSync()) file = f;
          }
        } catch (_) {}

        if (file != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Image.file(
              file,
              width: size,
              height: size,
              fit: BoxFit.cover,
            ),
          );
        }

        return CircleAvatar(
          radius: radius,
          backgroundColor: AppColors.lightGrey,
          child: Icon(Icons.directions_car,
              size: radius, color: AppColors.primary),
        );
      },
    );
  }
}

class VehiclesListScreen extends StatefulWidget {
  const VehiclesListScreen({super.key});

  @override
  _VehiclesListScreenState createState() => _VehiclesListScreenState();
}

class _VehiclesListScreenState extends State<VehiclesListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DateFormat _df = DateFormat('yyyy-MM-dd');
  List<Repair> _all = [];
  String _search = '';
  DateTimeRange? _dateRange;
  String _statusFilter = 'all';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadRepairs();
  }

  Future<void> _loadRepairs() async {
    final list = await RepairDatabaseService.getAllRepairs();

    // ترتيب صحيح (الأحدث أولاً)
    list.sort((a, b) => b.receivedDate.compareTo(a.receivedDate));

    setState(() {
      _all = list;
      _loading = false;
    });
  }

  List<Repair> _filtered(String type) {
    return _all.where((r) {
      final isTypeMatch = type == 'individual'
          ? r.beneficiaryType != 'شركة تأمين'
          : r.beneficiaryType == 'شركة تأمين';
      final hay = '${r.beneficiaryName} ${r.vehicleType} ${r.vehicleNumber}'
          .toLowerCase();
      final isSearch =
          _search.isEmpty || hay.contains(_search.trim().toLowerCase());
      final inDate = _dateRange == null ||
          (_dateRange!.start.isBefore(r.receivedDate) &&
              _dateRange!.end.isAfter(r.receivedDate));
      final status = (r.paymentStatus ?? r.computedPaymentStatus).toLowerCase();
      final isStatus = _statusFilter == 'all' ||
          (_statusFilter == 'paid' && status == 'مسدد') ||
          (_statusFilter == 'unpaid' && status != 'مسدد');
      return isTypeMatch && isSearch && inDate && isStatus;
    }).toList();
  }

  void _onAddRepair() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddRepairScreen()),
    );

    if (result == true) {
      setState(() {
        _search = '';
        _statusFilter = 'all';
        _dateRange = null;
        _loading = true;
      });
      _loadRepairs();
    }
  }

  Future<void> _pickDateRange() async {
    final dr = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (dr != null) setState(() => _dateRange = dr);
  }

  Widget _buildStatsCard(String title, int count, double sum) {
    return Expanded(
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: AppColors.lightGrey,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Text('عدد: $count', style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 4),
              Text('متبقي: ${sum.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStats() {
    final ind = _filtered('individual');
    final ins = _filtered('insurance');
    double sumRemaining(List<Repair> list) =>
        list.fold(0, (s, r) => s + (r.totalFileValue - r.totalPaidAmount));
    return Padding(
      padding: const EdgeInsets.all(12),
      child: AdaptiveRow(
        children: [
          _buildStatsCard('أفراد', ind.length, sumRemaining(ind)),
          _buildStatsCard('تأمين', ins.length, sumRemaining(ins)),
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: () {/* TODO: export CSV */},
            tooltip: 'تصدير CSV',
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: () {/* TODO: export PDF */},
            tooltip: 'تصدير PDF',
          ),
        ],
      ),
    );
  }

  Widget _buildListView(List<Repair> items) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) return const Center(child: Text('لا توجد نتائج'));

    return RefreshIndicator(
      onRefresh: _loadRepairs,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final r = items[i];
          final status =
              (r.paymentStatus ?? r.computedPaymentStatus).toLowerCase();
          Color bgColor;
          if (status.contains('مسدد') && !status.contains('جزئي')) {
            bgColor = Colors.green.shade50;
          } else if (status.contains('جزئي')) {
            bgColor = Colors.yellow.shade50;
          } else {
            bgColor = Colors.red.shade50;
          }
          return Dismissible(
            key: ValueKey(r.id),
            background: Container(
              color: AppColors.primary.withOpacity(0.3),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 20),
              child: const Icon(Icons.open_in_new, color: Colors.white),
            ),
            secondaryBackground: Container(
              color: Colors.blue.shade300,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: const Icon(Icons.attach_money, color: Colors.white),
            ),
            confirmDismiss: (dir) async {
              if (dir == DismissDirection.startToEnd) {
                _openDetails(r);
                return false;
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('فتح إضافة دفعة')),
                );
                return false;
              }
            },
            child: Card(
              color: bgColor,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: RepairThumbSmall(
                  repairId: r.id,
                  fallbackFirstPath:
                      r.imagePaths.isNotEmpty ? r.imagePaths.first : null,
                  size: 52,
                  radius: 26,
                ),
                title: Text('${r.vehicleType} • ${r.vehicleNumber}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('الاسم: ${r.beneficiaryName}'),
                    Text('تاريخ استلام: ${_df.format(r.receivedDate)}'),
                  ],
                ),
                trailing: Chip(
                  label: Text(
                    status,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: bgColor.withOpacity(0.6),
                ),
                onTap: () => _openDetails(r),
              ),
            ),
          );
        },
      ),
    );
  }

  void _openDetails(Repair r) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RepairDetailsScreen(repair: r),
      ),
    ).then((_) => _loadRepairs());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AdaptiveRow(children: [
        if (MediaQuery.sizeOf(context).width >= 600)
          const YallaSidebar(currentRoute: '/vehicles_list'),
        Expanded(
          child: Column(children: [
            _buildStats(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: AdaptiveRow(children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'بحث (اسم، نوع، رقم)…',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.date_range),
                  onPressed: _pickDateRange,
                  tooltip: 'فلترة بالتاريخ',
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _statusFilter,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('الكل')),
                    DropdownMenuItem(value: 'paid', child: Text('مسدد')),
                    DropdownMenuItem(value: 'unpaid', child: Text('غير مسدد')),
                  ],
                  onChanged: (v) => setState(() => _statusFilter = v!),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('جديد'),
                  onPressed: _onAddRepair,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                ),
              ]),
            ),
            TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppColors.primary,
              tabs: const [
                Tab(text: 'أفراد'),
                Tab(text: 'تأمين'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildListView(_filtered('individual')),
                  _buildListView(_filtered('insurance')),
                ],
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
