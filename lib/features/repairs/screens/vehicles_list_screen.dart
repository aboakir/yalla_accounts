import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/storage/yalla_stored_image.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/features/vehicles/models/vehicle.dart';
import 'package:yalla_accounts/features/vehicles/services/vehicle_service.dart';
import 'package:yalla_accounts/features/vehicles/widgets/vehicle_edit_dialog.dart';
import 'package:yalla_accounts/features/vehicles/widgets/vehicle_history_dialog.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class VehiclesListScreen extends StatefulWidget {
  const VehiclesListScreen({super.key});

  @override
  State<VehiclesListScreen> createState() => _VehiclesListScreenState();
}

class _VehiclesListScreenState extends State<VehiclesListScreen> {
  final TextEditingController _searchController = TextEditingController();
  final DateFormat _dateFormat = DateFormat('dd-MM-yyyy');

  List<Vehicle> _vehicles = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applySearch);
    _load();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_applySearch)
      ..dispose();
    super.dispose();
  }

  void _applySearch() {
    setState(() {});
  }

  Future<void> _load() async {
    try {
      if (mounted) {
        setState(() {
          _loading = true;
          _error = null;
        });
      }
      final vehicles = await VehicleService.getAllVehicles();
      if (!mounted) return;
      setState(() {
        _vehicles = vehicles;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  List<Vehicle> get _filtered {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _vehicles;

    return _vehicles.where((vehicle) {
      return vehicle.number.toLowerCase().contains(query) ||
          vehicle.type.toLowerCase().contains(query) ||
          vehicle.model.toLowerCase().contains(query) ||
          vehicle.clientName.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  Future<void> _addVehicle() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => const VehicleEditDialog(),
    );
    if (changed == true) await _load();
  }

  Future<void> _editVehicle(Vehicle vehicle) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => VehicleEditDialog(vehicle: vehicle),
    );
    if (changed == true) await _load();
  }

  Future<void> _showHistory(Vehicle vehicle) async {
    await showDialog<void>(
      context: context,
      builder: (_) => VehicleHistoryDialog(vehicle: vehicle),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vehicles = _filtered;
    final withHistory =
        _vehicles.where((vehicle) => vehicle.repairCount > 0).length;

    return Scaffold(
      body: AdaptiveRow(
        children: [
          if (MediaQuery.sizeOf(context).width >= 600)
            if (context.isDesktopWidth)
              const YallaSidebar(currentRoute: '/vehicles_list'),
          Expanded(
            child: SafeArea(
              child: RefreshIndicator(
                onRefresh: _load,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AdaptiveRow(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'المركبات',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                FilledButton.icon(
                                  onPressed: _addVehicle,
                                  icon: const Icon(Icons.add),
                                  label: const Text('مركبة جديدة'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            AdaptiveRow(
                              children: [
                                Expanded(
                                  child: _StatCard(
                                    title: 'إجمالي المركبات',
                                    value: _vehicles.length.toString(),
                                    icon: Icons.directions_car,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _StatCard(
                                    title: 'لها سجل إصلاح',
                                    value: withHistory.toString(),
                                    icon: Icons.history,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              inputFormatters: const [YallaDigitNormalizer()],
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText:
                                    'بحث برقم المركبة، النوع، الموديل أو العميل',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon:
                                    _searchController.text.trim().isEmpty
                                        ? null
                                        : IconButton(
                                            onPressed: _searchController.clear,
                                            icon: const Icon(Icons.close),
                                          ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_loading)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_error != null)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'تعذر تحميل المركبات\n$_error',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      )
                    else if (vehicles.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Text('لا توجد مركبات مطابقة'),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final vehicle = vehicles[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                child: ListTile(
                                  onTap: () => _showHistory(vehicle),
                                  leading: _VehicleProfileThumb(
                                    path: vehicle.profileImagePath,
                                  ),
                                  title: Text(
                                    '${vehicle.type} • ${vehicle.number}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (vehicle.model.isNotEmpty)
                                        Text('الموديل: ${vehicle.model}'),
                                      Text(
                                        vehicle.clientName.isEmpty
                                            ? 'بدون عميل مرتبط'
                                            : 'العميل: ${vehicle.clientName}',
                                      ),
                                      Text(
                                        vehicle.lastReceivedDate == null
                                            ? 'لا يوجد سجل إصلاح'
                                            : 'ملفات الإصلاح: '
                                                '${vehicle.repairCount}'
                                                ' • آخر استلام: '
                                                '${_dateFormat.format(vehicle.lastReceivedDate!)}',
                                      ),
                                    ],
                                  ),
                                  trailing: IconButton(
                                    tooltip: 'تعديل المركبة',
                                    onPressed: () => _editVehicle(vehicle),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                ),
                              );
                            },
                            childCount: vehicles.length,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VehicleProfileThumb extends StatelessWidget {
  const _VehicleProfileThumb({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    return YallaStoredImage(
      storedPath: path,
      width: 48,
      height: 48,
      cacheWidth: 180,
      borderRadius: BorderRadius.circular(14),
      fallback: CircleAvatar(
        radius: 24,
        backgroundColor: AppColors.primary.withOpacity(.12),
        child: const Icon(
          Icons.directions_car,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
