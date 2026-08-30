import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

/// نتيجة بحث موحّدة لواجهة البحث الشامل.
class SearchHit {
  /// مصدر البيانات: repairs | clients | invoices | payments | employees | suppliers
  final String source;

  /// المعرّف الأساسي للسجل:
  /// - repairs: id (TEXT)
  /// - clients: id (INT) لكن نعيده كنص
  /// - invoices: id (TEXT)
  /// - payments: id (TEXT)
  /// - employees: id (TEXT)
  /// - suppliers: id (TEXT)
  final String id;

  /// عنوان مختصر لعرض النتيجة
  final String title;

  /// نص إضافي (اختياري)
  final String? subtitle;

  const SearchHit({
    required this.source,
    required this.id,
    required this.title,
    this.subtitle,
  });
}

class GlobalSearchService {
  GlobalSearchService._();

  /// بحث شامل على أهم الجداول بدون أي بيانات افتراضية.
  /// - يستخدم LIKE مع %query% على أعمدة أساسية.
  /// - يرتّب النتائج بكل مجموعة حسب الأحدث (إن توفر تاريخ)، ثم يدمجها.
  /// - يعيد بحد أعلى 50 نتيجة (10 من كل مصدر تقريبًا).
  static Future<List<SearchHit>> search(String rawQuery) async {
    final q = rawQuery.trim();
    if (q.isEmpty) return <SearchHit>[];

    final db = await DBService.database;
    final like = '%$q%';

    // نطلق الاستعلامات بالتوازي
    final futures = await Future.wait<List<SearchHit>>([
      _searchRepairs(db, like),
      _searchClients(db, like),
      _searchInvoices(db, like),
      _searchPayments(db, like),
      _searchEmployees(db, like),
      _searchSuppliers(db, like),
    ]);

    // دمج + قصّ
    final hits = <SearchHit>[];
    for (final group in futures) {
      hits.addAll(group);
      if (hits.length >= 50) break;
    }
    return hits.take(50).toList();
  }

  // ---------------- Repairs ----------------
  static Future<List<SearchHit>> _searchRepairs(
      Database db, String like) async {
    // أعمدة مفيدة: invoiceNumber, vehicleModel, vehicleType, vehicleNumber,
    // beneficiaryName, notes
    final rows = await db.query(
      'repairs',
      where: '''
        (invoiceNumber LIKE ? OR vehicleModel LIKE ? OR vehicleType LIKE ?
         OR vehicleNumber LIKE ? OR beneficiaryName LIKE ? OR notes LIKE ?)
      ''',
      whereArgs: [like, like, like, like, like, like],
      orderBy: 'receivedDate DESC',
      limit: 10,
    );

    return rows.map((m) {
      final id = (m['id'] ?? '').toString();
      final inv = (m['invoiceNumber'] ?? '').toString();
      final car = (m['vehicleNumber'] ?? '').toString();
      final ben = (m['beneficiaryName'] ?? '').toString();
      final title = inv.isNotEmpty
          ? 'ملف #$inv'
          : (car.isNotEmpty ? 'مركبة $car' : 'ملف إصلاح');
      final sub = [
        if (ben.isNotEmpty) 'المستفيد: $ben',
        if (car.isNotEmpty) 'رقم المركبة: $car',
        if ((m['vehicleModel'] ?? '').toString().isNotEmpty)
          'موديل: ${m['vehicleModel']}',
        if ((m['notes'] ?? '').toString().isNotEmpty) '${m['notes']}',
      ].where((s) => s.trim().isNotEmpty).join(' — ');
      return SearchHit(
        source: 'repairs',
        id: id,
        title: title,
        subtitle: sub.isEmpty ? null : sub,
      );
    }).toList();
  }

  // ---------------- Clients ----------------
  static Future<List<SearchHit>> _searchClients(
      Database db, String like) async {
    final rows = await db.query(
      'clients',
      where: '''
        (name LIKE ? OR phone LIKE ? OR email LIKE ? OR address LIKE ? OR notes LIKE ?)
      ''',
      whereArgs: [like, like, like, like, like],
      orderBy: 'name COLLATE NOCASE ASC',
      limit: 10,
    );

    return rows.map((m) {
      final id = (m['id'] ?? '').toString();
      final name = (m['name'] ?? '').toString();
      final type = (m['type'] ?? '').toString();
      final phone = (m['phone'] ?? '').toString();
      final sub = [
        if (type.isNotEmpty) 'النوع: $type',
        if (phone.isNotEmpty) 'هاتف: $phone',
        if ((m['address'] ?? '').toString().isNotEmpty) '${m['address']}',
      ].where((s) => s.trim().isNotEmpty).join(' — ');
      return SearchHit(
        source: 'clients',
        id: id,
        title: name.isEmpty ? 'عميل' : name,
        subtitle: sub.isEmpty ? null : sub,
      );
    }).toList();
  }

  // ---------------- Invoices ----------------
  static Future<List<SearchHit>> _searchInvoices(
      Database db, String like) async {
    // نبحث في id (UUID)، notes، وربما total/paid كأرقام ضمن نص
    final rows = await db.query(
      'invoices',
      where: '(id LIKE ? OR notes LIKE ?)',
      whereArgs: [like, like],
      orderBy: 'date DESC',
      limit: 10,
    );

    return rows.map((m) {
      final id = (m['id'] ?? '').toString();
      final total = _toD(m['total']);
      final paid = _toD(m['paid']);
      final status = (m['status'] ?? '').toString();
      final title = 'فاتورة ${id.isNotEmpty ? id.substring(0, 8) : ''}';
      final sub =
          'الإجمالي: ${_fmt(total)} — المدفوع: ${_fmt(paid)} — الحالة: $status';
      return SearchHit(
        source: 'invoices',
        id: id,
        title: title,
        subtitle: sub,
      );
    }).toList();
  }

  // ---------------- Payments ----------------
  static Future<List<SearchHit>> _searchPayments(
      Database db, String like) async {
    // البحث في id, method, notes, accountName
    final rows = await db.query(
      'payments',
      where:
          '(id LIKE ? OR method LIKE ? OR notes LIKE ? OR accountName LIKE ?)',
      whereArgs: [like, like, like, like],
      orderBy: 'date DESC',
      limit: 10,
    );

    return rows.map((m) {
      final id = (m['id'] ?? '').toString();
      final amount = _toD(m['amount']);
      final method = (m['method'] ?? '').toString();
      final date = (m['date'] ?? '').toString();
      final title = 'دفعة ${_fmt(amount)}';
      final sub = [
        if (method.isNotEmpty) 'طريقة: $method',
        if (date.isNotEmpty) date,
        if ((m['notes'] ?? '').toString().isNotEmpty) '${m['notes']}',
      ].where((s) => s.trim().isNotEmpty).join(' — ');
      return SearchHit(
        source: 'payments',
        id: id,
        title: title,
        subtitle: sub.isEmpty ? null : sub,
      );
    }).toList();
  }

  // ---------------- Employees ----------------
  static Future<List<SearchHit>> _searchEmployees(
      Database db, String like) async {
    final rows = await db.query(
      'employees',
      where:
          '(full_name LIKE ? OR job_title LIKE ? OR phone LIKE ? OR email LIKE ? OR notes LIKE ?)',
      whereArgs: [like, like, like, like, like],
      orderBy: 'created_at DESC',
      limit: 10,
    );

    return rows.map((m) {
      final id = (m['id'] ?? '').toString();
      final name = (m['full_name'] ?? '').toString();
      final job = (m['job_title'] ?? '').toString();
      final sub = [
        if (job.isNotEmpty) job,
        if ((m['phone'] ?? '').toString().isNotEmpty) '${m['phone']}',
        if ((m['email'] ?? '').toString().isNotEmpty) '${m['email']}',
      ].where((s) => s.trim().isNotEmpty).join(' — ');
      return SearchHit(
        source: 'employees',
        id: id,
        title: name.isEmpty ? 'موظف' : name,
        subtitle: sub.isEmpty ? null : sub,
      );
    }).toList();
  }

  // ---------------- Suppliers ----------------
  static Future<List<SearchHit>> _searchSuppliers(
      Database db, String like) async {
    final rows = await db.query(
      'suppliers',
      where: '(name LIKE ? OR phone LIKE ? OR address LIKE ?)',
      whereArgs: [like, like, like],
      orderBy: 'name COLLATE NOCASE ASC',
      limit: 10,
    );

    return rows.map((m) {
      final id = (m['id'] ?? '').toString();
      final name = (m['name'] ?? '').toString();
      final sub = [
        if ((m['phone'] ?? '').toString().isNotEmpty) '${m['phone']}',
        if ((m['address'] ?? '').toString().isNotEmpty) '${m['address']}',
      ].where((s) => s.trim().isNotEmpty).join(' — ');
      return SearchHit(
        source: 'suppliers',
        id: id,
        title: name.isEmpty ? 'مورد' : name,
        subtitle: sub.isEmpty ? null : sub,
      );
    }).toList();
  }

  // ---------------- Utils ----------------
  static double _toD(Object? v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  static String _fmt(double v) => v.toStringAsFixed(2);
}
