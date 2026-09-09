import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/clients/models/client.dart';
import 'package:yalla_accounts/features/clients/services/client_service.dart';

/// مزود حالة قائمة العملاء
final clientListProvider =
    StateNotifierProvider<ClientListNotifier, List<Client>>((ref) {
  return ClientListNotifier();
});

class ClientListNotifier extends StateNotifier<List<Client>> {
  ClientListNotifier() : super(const []) {
    loadClients();
  }

  // نسخة كاملة من البيانات المحمّلة (للبحث/الفلترة محليًا)
  List<Client> _all = const [];

  // معايير اختيارية
  String? _query; // نص البحث
  String? _type; // 'أفراد' | 'شركة تأمين' | null (الكل)

  /// تحميل كل العملاء من القاعدة
  Future<void> loadClients() async {
    final clients = await ClientService.getAllClients();
    if (!mounted) return;
    _all = clients;
    _applyFilters();
  }

  /// إعادة التحميل من القاعدة
  Future<void> refresh() => loadClients();

  /// تعيين نص البحث (محليًا)
  void setQuery(String? q) {
    _query = (q == null || q.trim().isEmpty) ? null : q.trim();
    _applyFilters();
  }

  /// تعيين نوع العميل للتصفية: 'أفراد' | 'شركة تأمين' | null (الكل)
  void setTypeFilter(String? type) {
    _type = (type == null || type.trim().isEmpty || type == 'الكل')
        ? null
        : type.trim();
    _applyFilters();
  }

  /// إدراج عميل كامل
  Future<void> addClient(Client client) async {
    await ClientService.insertClient(client);
    await loadClients();
  }

  /// تحديث عميل
  Future<void> updateClient(Client client) async {
    await ClientService.updateClient(client);
    await loadClients();
  }

  /// حذف عميل
  Future<void> deleteClient(int id) async {
    await ClientService.deleteClient(id);
    await loadClients();
  }

  /// إدراج سريع بالاسم/النوع مع منع التكرار (لا يعتمد على DBHelper)
  Future<void> upsertByName(String name, String type) async {
    await ClientService.insertOrGetClientId(name, type);
    await loadClients();
  }

  // ================== داخلي ==================
  void _applyFilters() {
    List<Client> list = _all;

    if (_type != null) {
      list = list.where((c) => c.type.trim() == _type).toList();
    }

    if (_query != null) {
      final q = _query!.toLowerCase();
      list = list.where((c) {
        final n = c.name.toLowerCase();
        final ph = (c.phone).toLowerCase();
        final em = (c.email).toLowerCase();
        return n.contains(q) || ph.contains(q) || em.contains(q);
      }).toList();
    }

    state = list;
  }
}
