class Subscription {
  final int? id;
  final String userId;
  final DateTime startDate;
  final DateTime? endDate;
  final String status;

  const Subscription({
    this.id,
    required this.userId,
    required this.startDate,
    this.endDate,
    required this.status,
  });
}

/// Legacy per-user subscription storage is not a commercial authority.
class SubscriptionService {
  static const String serverAuthorityRequired = 'SERVER_AUTHORITY_REQUIRED';

  Never _deny() => throw StateError(serverAuthorityRequired);

  Future<int> createSubscription(Subscription subscription) async => _deny();
  Future<int> updateSubscription(Subscription subscription) async => _deny();
  Future<int> deleteSubscription(int id) async => _deny();

  Future<Subscription?> getActiveSubscriptionByUserId(String userId) async =>
      _deny();

  Future<List<Subscription>> getAllSubscriptions() async => _deny();

  Future<int> updateSubscriptionStatus(int id, String newStatus) async =>
      _deny();
}
