import 'package:yalla_accounts/core/services/db_service.dart';

class SubscriptionService {
  /// إنشاء اشتراك جديد
  Future<void> createSubscription({
    required String id,
    required String planId,
    required DateTime startDate,
    required DateTime endDate,
    required String userId,
    required double price,
  }) async {
    final db = await DBService.database;

    await db.insert('subscriptions', {
      'id': id,
      'planId': planId,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'userId': userId,
      'price': price,
    });
  }

  /// جلب الاشتراك الفعال للمستخدم
  Future<Map<String, dynamic>?> getActiveSubscription(String userId) async {
    final db = await DBService.database;
    final now = DateTime.now().toIso8601String();

    final results = await db.query(
      'subscriptions',
      where: 'userId = ? AND endDate > ?',
      whereArgs: [userId, now],
      orderBy: 'endDate DESC',
      limit: 1,
    );

    return results.isNotEmpty ? results.first : null;
  }

  /// التحقق من وجود اشتراك مفعل
  Future<bool> isSubscriptionActive(String userId) async {
    final sub = await getActiveSubscription(userId);
    if (sub == null) return false;

    final endDate = DateTime.tryParse(sub['endDate'] ?? '');
    return endDate != null && endDate.isAfter(DateTime.now());
  }

  /// جلب جميع الباقات الفعالة
  Future<List<Map<String, dynamic>>> getAvailablePlans() async {
    final db = await DBService.database;
    return await db.query('plans', where: 'isActive = 1');
  }

  /// جلب باقة محددة عبر ID
  Future<Map<String, dynamic>?> getPlanById(String planId) async {
    final db = await DBService.database;
    final result = await db.query(
      'plans',
      where: 'id = ?',
      whereArgs: [planId],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  /// ✅ تفعيل اشتراك تجريبي لمدة محددة (مرة واحدة فقط)
  Future<bool> activateTrial(String userId, int durationDays) async {
    final db = await DBService.database;

    // التأكد من عدم وجود اشتراك مجاني مفعل مسبقًا
    final existingTrial = await db.query(
      'subscriptions',
      where: 'userId = ? AND planId = ?',
      whereArgs: [userId, 'trial'],
    );

    if (existingTrial.isNotEmpty) {
      return false; // لا تقم بالتفعيل مرة ثانية
    }

    final now = DateTime.now();
    final end = now.add(Duration(days: durationDays));

    await db.insert('subscriptions', {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'planId': 'trial',
      'startDate': now.toIso8601String(),
      'endDate': end.toIso8601String(),
      'userId': userId,
      'price': 0.0,
    });

    return true; // ✅ تم التفعيل بنجاح
  }
}
