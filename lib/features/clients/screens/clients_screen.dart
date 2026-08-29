import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/clients/models/client.dart';
import 'package:yalla_accounts/features/clients/services/client_service.dart';
import 'package:yalla_accounts/features/clients/widgets/add_client_dialog.dart';
import 'package:yalla_accounts/features/clients/widgets/edit_client_dialog.dart';
import 'package:yalla_accounts/features/clients/widgets/client_details_dialog.dart';

/// سلوك Scroll خاص بالويندوز (سكرول ناعم + دعم الماوس)
class DesktopScrollBehavior extends ScrollBehavior {
  const DesktopScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();

  @override
  Widget buildScrollbar(
      BuildContext context, Widget child, ScrollableDetails details) {
    return Scrollbar(
      controller: details.controller,
      thumbVisibility: true,
      radius: const Radius.circular(12),
      child: child,
    );
  }
}

class ClientsScreen extends ConsumerStatefulWidget {
  const ClientsScreen({super.key});

  @override
  ConsumerState<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends ConsumerState<ClientsScreen> {
  List<Client> _clients = [];
  bool _isLoading = true;

  static const List<String> _filterOptions = ['الكل', 'أفراد', 'شركة تأمين'];
  String _filterType = 'الكل';

  final TextEditingController _searchCtrl = TextEditingController();

  // ================================
  // lifecycle
  // ================================
  @override
  void initState() {
    super.initState();
    _standardizeFilter();
    _loadClients();
    _searchCtrl.addListener(_onSearchInput);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchInput() => setState(() {});

  // ================================
  // Load Data
  // ================================
  Future<void> _loadClients() async {
    try {
      setState(() => _isLoading = true);
      final result = await ClientService.getAllClients();
      setState(() {
        _clients = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("خطأ أثناء تحميل العملاء: $e")),
      );
    }
  }

  // ================================
  // Normalization Helpers
  // ================================
  String _norm(String v) => v.trim().toLowerCase();

  String _normalizeType(String t) {
    final s = _norm(t);
    if (s.contains("insurance") || s.contains("تأمين")) return "شركة تأمين";
    return "أفراد";
  }

  void _standardizeFilter() {
    if (!_filterOptions.contains(_filterType)) _filterType = "الكل";
  }

  bool _matchFilter(String type) {
    if (_filterType == "الكل") return true;
    return _normalizeType(type) == _filterType;
  }

  // ================================
  // Filtering + Searching
  // ================================
  List<Client> get _filtered {
    Iterable<Client> list = _clients.where((c) => _matchFilter(c.type));

    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((c) {
        return c.name.toLowerCase().contains(q) ||
            c.phone.toLowerCase().contains(q) ||
            c.email.toLowerCase().contains(q) ||
            c.address.toLowerCase().contains(q) ||
            c.notes.toLowerCase().contains(q);
      });
    }

    return list.toList();
  }

  // ================================
  // Actions
  // ================================
  Future<void> _addClient() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const AddClientDialog(),
    );
    if (ok == true) _loadClients();
  }

  Future<void> _editClient(Client c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => EditClientDialog(client: c),
    );
    if (ok == true) _loadClients();
  }

  Future<void> _deleteClient(Client c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("تأكيد الحذف"),
        content: Text("هل تريد حذف '${c.name}'؟"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("إلغاء"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("حذف"),
          ),
        ],
      ),
    );

    if (ok == true && c.id != null) {
      await ClientService.deleteClient(c.id!);
      _loadClients();
    }
  }

  Future<void> _openDetails(Client c) async {
    final r = await showDialog<String>(
      context: context,
      builder: (_) => ClientDetailsDialog(client: c),
    );

    if (r == "edit") _editClient(c);
    if (r == "delete") _deleteClient(c);
  }

  // ================================
  // UI
  // ================================
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ScrollConfiguration(
        behavior: const DesktopScrollBehavior(),
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: AppColors.primary,
            title: const Text("إدارة العملاء"),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: _addClient,
              )
            ],
          ),

          // BODY =======================================================
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadClients,
                  child: CustomScrollView(
                    slivers: [
                      // ========== شريط البحث والفلترة ==========
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: _searchCtrl,
                                  decoration: InputDecoration(
                                    hintText:
                                        "بحث بالاسم / الهاتف / البريد / العنوان / الملاحظات",
                                    prefixIcon: const Icon(Icons.search),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _filterType,
                                  items: _filterOptions
                                      .map((e) => DropdownMenuItem(
                                            value: e,
                                            child: Text(e),
                                          ))
                                      .toList(),
                                  onChanged: (v) =>
                                      setState(() => _filterType = v!),
                                  decoration: const InputDecoration(
                                    labelText: "النوع",
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ========== العداد ==========
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          child: Row(
                            children: [
                              Text(
                                "الإجمالي: ${_filtered.length}",
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              if (_filterType != "الكل")
                                Text("النوع: $_filterType"),
                            ],
                          ),
                        ),
                      ),

                      const SliverToBoxAdapter(
                          child: Divider(height: 0, thickness: 1)),

                      // ========== القائمة ==========
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final c = _filtered[i];
                            final isInsurance =
                                _normalizeType(c.type) == "شركة تأمين";

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                onTap: () => _openDetails(c),
                                leading: Icon(
                                  isInsurance ? Icons.business : Icons.person,
                                  color: AppColors.primary,
                                ),
                                title: Text(
                                  c.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  _normalizeType(c.type),
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.black54),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: "عرض",
                                      icon: const Icon(Icons.visibility,
                                          color: Colors.teal),
                                      onPressed: () => _openDetails(c),
                                    ),
                                    IconButton(
                                      tooltip: "تعديل",
                                      icon: const Icon(Icons.edit,
                                          color: Colors.orange),
                                      onPressed: () => _editClient(c),
                                    ),
                                    IconButton(
                                      tooltip: "حذف",
                                      icon: const Icon(Icons.delete,
                                          color: Colors.red),
                                      onPressed: () => _deleteClient(c),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          childCount: _filtered.length,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
