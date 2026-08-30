import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/features/clients/providers/client_list_provider.dart';
import 'client_edit_screen.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

/// سلوك سكرول محسّن للويندوز
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
      thickness: 10,
      radius: const Radius.circular(8),
      child: child,
    );
  }
}

class ClientListScreen extends ConsumerWidget {
  const ClientListScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    await ref.read(clientListProvider.notifier).loadClients();
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref, {
    required int? id,
    required String name,
  }) async {
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("رقم العميل غير صالح")),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AdaptiveAlertDialog(
          title: const Text("تأكيد الحذف"),
          content: Text("هل تريد حذف \"$name\"؟"),
          actions: [
            TextButton(
              child: const Text("إلغاء"),
              onPressed: () => Navigator.pop(context, false),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text("حذف"),
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      await ref.read(clientListProvider.notifier).deleteClient(id);
      await _refresh(ref);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clients = ref.watch(clientListProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: ScrollConfiguration(
        behavior: const DesktopScrollBehavior(),
        child: Scaffold(
          appBar: AppBar(
            title: const Text("إدارة العملاء"),
          ),

          floatingActionButton: FloatingActionButton(
            child: const Icon(Icons.add),
            onPressed: () async {
              final ok = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ClientEditScreen()),
              );
              if (ok == true) await _refresh(ref);
            },
          ),

          // -----------------------------------------------------------------
          // BODY — الحل النهائي الحقيقي للسكرول
          // -----------------------------------------------------------------
          body: RefreshIndicator(
            onRefresh: () => _refresh(ref),
            child: CustomScrollView(
              slivers: [
                // =====================
                // لو ما في بيانات
                // =====================
                if (clients.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        "لا يوجد عملاء",
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ),

                // =====================
                // لو في بيانات
                // =====================
                if (clients.isNotEmpty)
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final c = clients[i];

                        return Column(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.person),
                              title: Text(
                                c.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                c.phone.isNotEmpty
                                    ? "هاتف: ${c.phone}"
                                    : (c.email.isNotEmpty
                                        ? "بريد: ${c.email}"
                                        : ""),
                              ),
                              trailing: AdaptiveRow(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit,
                                        color: Colors.blue),
                                    onPressed: () async {
                                      final ok = await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              ClientEditScreen(client: c),
                                        ),
                                      );
                                      if (ok == true) await _refresh(ref);
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.red),
                                    onPressed: () => _confirmDelete(
                                      context,
                                      ref,
                                      id: c.id,
                                      name: c.name,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 0),
                          ],
                        );
                      },
                      childCount: clients.length,
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
