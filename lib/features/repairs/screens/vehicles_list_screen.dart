// 📁 lib/features/repairs/screens/vehicles_list_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/widgets/mobile/yalla_mobile_bottom_nav.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/screens/add_repair_screen.dart';
import 'package:yalla_accounts/features/repairs/screens/repair_details_screen.dart';
import 'package:yalla_accounts/features/repairs/services/repair_database_service.dart';
import 'package:yalla_accounts/features/repairs/widgets/repair_thumb.dart';

class VehiclesListScreen extends StatefulWidget {
  const VehiclesListScreen({super.key});

  @override
  State<VehiclesListScreen> createState() => _VehiclesListScreenState();
}

class _VehiclesListScreenState extends State<VehiclesListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final DateFormat _df = DateFormat('yyyy-MM-dd');
  List<Repair> _all = [];
  String _search = '';
  DateTimeRange? _dateRange;
  String _statusFilter = 'all';
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadRepairs();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRepairs() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }

    try {
      final list = await RepairDatabaseService.getAllRepairs();
      list.sort((a, b) => b.receivedDate.compareTo(a.receivedDate));
      if (!mounted) return;
      setState(() {
        _all = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  List<Repair> _filtered(String type) {
    return _all.where((r) {
      final isTypeMatch = type == 'individual'
          ? r.beneficiaryType != 'شركة تأمين'
          : r.beneficiaryType == 'شركة تأمين';

      final query = _search.trim().toLowerCase();
      final haystack =
          '${r.beneficiaryName} ${r.vehicleType} ${r.vehicleNumber}'
              .toLowerCase();
      final matchesSearch = query.isEmpty || haystack.contains(query);

      final inDate = _dateRange == null ||
          (!r.receivedDate.isBefore(_dateRange!.start) &&
              !r.receivedDate.isAfter(
                _dateRange!.end.add(const Duration(days: 1)),
              ));

      final status = (r.paymentStatus ?? r.computedPaymentStatus).toLowerCase();
      final matchesStatus = _statusFilter == 'all' ||
          (_statusFilter == 'paid' && status == 'مسدد') ||
          (_statusFilter == 'unpaid' && status != 'مسدد');

      return isTypeMatch && matchesSearch && inDate && matchesStatus;
    }).toList();
  }

  double _remaining(Repair repair) =>
      (repair.totalFileValue - repair.totalPaidAmount)
          .clamp(0.0, double.infinity);

  Future<void> _onAddRepair() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddRepairScreen()),
    );
    if (result == true) {
      if (!mounted) return;
      setState(() {
        _search = '';
        _statusFilter = 'all';
        _dateRange = null;
      });
      await _loadRepairs();
    }
  }

  Future<void> _pickDateRange() async {
    final dr = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (dr != null && mounted) setState(() => _dateRange = dr);
  }

  void _openDetails(Repair repair) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RepairDetailsScreen(repair: repair),
      ),
    ).then((_) => _loadRepairs());
  }

  Widget _statCard(String title, int count, double remaining) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black12),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              '$count',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 22,
              ),
            ),
            Text(
              'متبقي ${remaining.toStringAsFixed(0)} ₪',
              style: const TextStyle(color: Colors.black54, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _stats() {
    final individual = _filtered('individual');
    final insurance = _filtered('insurance');
    final individualRemaining =
        individual.fold<double>(0, (sum, item) => sum + _remaining(item));
    final insuranceRemaining =
        insurance.fold<double>(0, (sum, item) => sum + _remaining(item));

    return Row(
      children: [
        _statCard('أفراد', individual.length, individualRemaining),
        const SizedBox(width: 10),
        _statCard('تأمين', insurance.length, insuranceRemaining),
      ],
    );
  }

  Widget _filters(bool phone) {
    final search = TextField(
      textAlign: TextAlign.right,
      decoration: InputDecoration(
        hintText: 'بحث بالاسم أو المركبة أو الرقم...',
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      onChanged: (value) => setState(() => _search = value),
    );

    final status = DropdownButtonFormField<String>(
      value: _statusFilter,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'حالة السداد',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      items: const [
        DropdownMenuItem(value: 'all', child: Text('الكل')),
        DropdownMenuItem(value: 'paid', child: Text('مسدد')),
        DropdownMenuItem(value: 'unpaid', child: Text('غير مسدد')),
      ],
      onChanged: (value) {
        if (value != null) setState(() => _statusFilter = value);
      },
    );

    final dateButton = OutlinedButton.icon(
      onPressed: _pickDateRange,
      icon: const Icon(Icons.date_range_outlined),
      label: Text(_dateRange == null ? 'التاريخ' : 'إلغاء التاريخ'),
    );

    if (phone) {
      return Column(
        children: [
          search,
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: status),
              const SizedBox(width: 10),
              dateButton,
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(flex: 3, child: search),
        const SizedBox(width: 12),
        SizedBox(width: 220, child: status),
        const SizedBox(width: 12),
        dateButton,
      ],
    );
  }

  Widget _empty(String text) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 100),
        Icon(
          Icons.directions_car_filled_outlined,
          size: 52,
          color: Colors.grey.shade400,
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            text,
            style: const TextStyle(color: Colors.black54),
          ),
        ),
      ],
    );
  }

  Widget _list(List<Repair> items) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null) {
      return _empty('تعذر تحميل المركبات. اسحب للأسفل للمحاولة مجددًا.');
    }

    if (items.isEmpty) return _empty('لا توجد مركبات مطابقة');

    return RefreshIndicator(
      onRefresh: _loadRepairs,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 24),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final repair = items[index];
          final status = (repair.paymentStatus ?? repair.computedPaymentStatus);
          final remaining = _remaining(repair);

          return Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _openDetails(repair),
              child: Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.black12),
                ),
                child: Row(
                  children: [
                    RepairThumb(
                      repairId: repair.id,
                      fallbackFirstPath: repair.imagePaths.isNotEmpty
                          ? repair.imagePaths.first
                          : null,
                      fallbackPaths: repair.imagePaths,
                      size: 62,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${repair.vehicleType} • ${repair.vehicleNumber}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            repair.beneficiaryName,
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.black54),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                '${remaining.toStringAsFixed(0)} ₪ متبقي',
                                style: TextStyle(
                                  color: remaining > 0
                                      ? Colors.red.shade700
                                      : Colors.green.shade700,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _df.format(repair.receivedDate),
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              status,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _content(bool phone) {
    return Container(
      color: const Color(0xFFF7F8FA),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              phone ? 14 : 20,
              14,
              phone ? 14 : 20,
              0,
            ),
            child: Column(
              children: [
                _stats(),
                const SizedBox(height: 12),
                _filters(phone),
                const SizedBox(height: 12),
                TabBar(
                  controller: _tabController,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: Colors.black54,
                  indicatorColor: AppColors.primary,
                  tabs: const [
                    Tab(text: 'أفراد'),
                    Tab(text: 'تأمين'),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: phone ? 14 : 20),
              child: TabBarView(
                controller: _tabController,
                children: [
                  _list(_filtered('individual')),
                  _list(_filtered('insurance')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width < 600;

    if (phone) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        drawer: Drawer(
          width: MediaQuery.sizeOf(context).width,
          shape: const RoundedRectangleBorder(),
          child: const SafeArea(
            child: YallaSidebar(currentRoute: AppRoutes.vehiclesList),
          ),
        ),
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          centerTitle: true,
          title: const Text(
            'قائمة المركبات',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loading ? null : _loadRepairs,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _content(true),
        floatingActionButton: FloatingActionButton(
          onPressed: _onAddRepair,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          child: const Icon(Icons.add),
        ),
        bottomNavigationBar: Builder(
          builder: (navContext) => YallaMobileBottomNav(
            currentRoute: AppRoutes.vehiclesList,
            onMore: () => Scaffold.of(navContext).openDrawer(),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('قائمة المركبات'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loading ? null : _loadRepairs,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Row(
        children: [
          const SizedBox(
            width: 260,
            child: YallaSidebar(currentRoute: AppRoutes.vehiclesList),
          ),
          Expanded(child: _content(false)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _onAddRepair,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }
}
