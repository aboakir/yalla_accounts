import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class Subscription {
  final int? id;
  final String userId;
  final DateTime startDate;
  final DateTime? endDate;
  final String status; // active, expired, canceled

  Subscription({
    this.id,
    required this.userId,
    required this.startDate,
    this.endDate,
    required this.status,
  });

  factory Subscription.fromMap(Map<String, dynamic> map) {
    return Subscription(
      id: map['id'] as int?,
      userId: map['userId'] as String,
      startDate: DateTime.parse(map['startDate'] as String),
      endDate: map['endDate'] != null ? DateTime.parse(map['endDate'] as String) : null,
      status: map['status'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'userId': userId,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'status': status,
    };
  }
}

class SubscriptionService {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'yalla_accounts.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE subscriptions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            userId TEXT NOT NULL,
            startDate TEXT NOT NULL,
            endDate TEXT,
            status TEXT NOT NULL
          )
        ''');
      },
    );
  }

  // إنشاء اشتراك جديد
  Future<int> createSubscription(Subscription subscription) async {
    final db = await database;
    return await db.insert('subscriptions', subscription.toMap());
  }

  // تحديث اشتراك موجود
  Future<int> updateSubscription(Subscription subscription) async {
    final db = await database;
    return await db.update(
      'subscriptions',
      subscription.toMap(),
      where: 'id = ?',
      whereArgs: [subscription.id],
    );
  }

  // حذف اشتراك
  Future<int> deleteSubscription(int id) async {
    final db = await database;
    return await db.delete(
      'subscriptions',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // جلب الاشتراك حسب userId (مفترض الاشتراك النشط)
  Future<Subscription?> getActiveSubscriptionByUserId(String userId) async {
    final db = await database;
    final result = await db.query(
      'subscriptions',
      where: 'userId = ? AND status = ?',
      whereArgs: [userId, 'active'],
      limit: 1,
    );
    if (result.isNotEmpty) {
      return Subscription.fromMap(result.first);
    }
    return null;
  }

  // جلب كل الاشتراكات
  Future<List<Subscription>> getAllSubscriptions() async {
    final db = await database;
    final result = await db.query('subscriptions', orderBy: 'startDate DESC');
    return result.map((map) => Subscription.fromMap(map)).toList();
  }

  // تحديث حالة الاشتراك (مثلاً من active إلى expired)
  Future<int> updateSubscriptionStatus(int id, String newStatus) async {
    final db = await database;
    return await db.update(
      'subscriptions',
      {'status': newStatus},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
