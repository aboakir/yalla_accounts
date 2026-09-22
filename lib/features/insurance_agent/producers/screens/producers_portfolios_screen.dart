import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/utils/user_facing_error.dart';
import 'package:yalla_accounts/features/insurance_agent/dashboard/services/insurance_dashboard_service.dart';

class ProducersPortfoliosScreen extends StatefulWidget {
  const ProducersPortfoliosScreen({super.key});

  @override
  State<ProducersPortfoliosScreen> createState() =>
      _ProducersPortfoliosScreenState();
}

class _ProducersPortfoliosScreenState extends State<ProducersPortfoliosScreen> {
  List<InsuranceProducerPortfolio> _items = const [];
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final items = await InsuranceDashboardService.producerPortfolios();
      if (mounted) setState(() => _items = items);
    } catch (error) {
      if (mounted) setState(() => _error = UserFacingError.message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('محافظ المنتجين'),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _busy
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : _items.isEmpty
                    ? const Center(
                        child: Text('لا توجد عمولات مرتبطة بمنتجين حتى الآن'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return Card(
                            child: ListTile(
                              leading: const CircleAvatar(
                                  child: Icon(Icons.badge_outlined)),
                              title: Text(item.name),
                              subtitle: Text(
                                  '${item.policyCount} وثيقة • مبيعات ${MoneyFormatter.format(item.sales)}'),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text('العمولة'),
                                  Text(
                                    MoneyFormatter.format(item.commission),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
