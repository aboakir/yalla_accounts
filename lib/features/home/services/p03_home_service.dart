import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/features/settings/services/commercial_settings_service.dart';
import 'package:yalla_accounts/features/settings/services/workshop_settings_service.dart';

enum P03AttentionKind {
  overdueCheque,
  chequeDueToday,
  staleUnpaidRepair,
}

class P03AttentionItem {
  const P03AttentionItem({
    required this.kind,
    required this.title,
    required this.subtitle,
    this.amount,
  });

  final P03AttentionKind kind;
  final String title;
  final String subtitle;
  final double? amount;
}

class P03RecentRepair {
  const P03RecentRepair({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.date,
  });

  final String id;
  final String title;
  final String subtitle;
  final String status;
  final String date;
}

class P03HomeSnapshot {
  const P03HomeSnapshot({
    required this.workshopName,
    required this.currencySymbol,
    required this.repairsReceivedToday,
    required this.receiptsToday,
    required this.paymentsToday,
    required this.chequesDueToday,
    required this.attentionCount,
    required this.attention,
    required this.recentRepairs,
  });

  final String workshopName;
  final String currencySymbol;
  final int repairsReceivedToday;
  final double receiptsToday;
  final double paymentsToday;
  final int chequesDueToday;
  final int attentionCount;
  final List<P03AttentionItem> attention;
  final List<P03RecentRepair> recentRepairs;

  double get netCashToday => receiptsToday - paymentsToday;
}

class P03HomeService {
  P03HomeService._();

  static Future<P03HomeSnapshot> load() async {
    final db = await DBService.database;
    final today = _dateOnly(DateTime.now());

    var workshopName = 'ورشتي';
    var currencySymbol = MoneyFormatter.symbol;

    try {
      final settings = await WorkshopSettingsService.instance.getSettings();
      final configured = settings?.workshopName?.trim() ?? '';
      if (configured.isNotEmpty) workshopName = configured;
    } catch (_) {
      // Optional presentation settings must never block the Home screen.
    }

    try {
      final commercial = await CommercialSettingsService.instance.get();
      final configured = commercial.currencySymbol.trim();
      if (configured.isNotEmpty) currencySymbol = configured;
    } catch (_) {
      // Currency fallback is presentation-only; no financial value is changed.
    }

    final repairsTodayRows = await _safeRawQuery(
      db,
      '''
        SELECT COUNT(*) AS c
        FROM repairs
        WHERE DATE(receivedDate) = DATE(?)
      ''',
      [today],
    );
    final repairsReceivedToday = _intValue(repairsTodayRows, 'c');

    final receiptRows = await _safeRawQuery(
      db,
      '''
        SELECT COALESCE(SUM(amount), 0) AS total
        FROM payments
        WHERE DATE(date) = DATE(?)
          AND COALESCE(isIncome, 1) = 1
      ''',
      [today],
    );
    final receiptsToday = _doubleValue(receiptRows, 'total');

    final paymentRows = await _safeRawQuery(
      db,
      '''
        SELECT COALESCE(SUM(amount), 0) AS total
        FROM payments
        WHERE DATE(date) = DATE(?)
          AND COALESCE(isIncome, 1) = 0
      ''',
      [today],
    );
    final paymentsToday = _doubleValue(paymentRows, 'total');

    final dueTodayRows = await _safeRawQuery(
      db,
      '''
        SELECT COUNT(*) AS c
        FROM cheques
        WHERE LOWER(COALESCE(status, 'pending')) IN ('pending','deposited')
          AND DATE(COALESCE(NULLIF(due_date,''), NULLIF(date,''))) = DATE(?)
      ''',
      [today],
    );
    final chequesDueToday = _intValue(dueTodayRows, 'c');

    final overdueChequeCountRows = await _safeRawQuery(
      db,
      '''
        SELECT COUNT(*) AS c
        FROM cheques
        WHERE LOWER(COALESCE(status, 'pending')) IN ('pending','deposited')
          AND DATE(COALESCE(NULLIF(due_date,''), NULLIF(date,''))) < DATE(?)
      ''',
      [today],
    );
    final overdueChequeCount = _intValue(overdueChequeCountRows, 'c');

    final staleRepairCountRows = await _safeRawQuery(
      db,
      '''
        SELECT COUNT(*) AS c
        FROM repairs
        WHERE COALESCE(isArchived, 0) = 0
          AND COALESCE(paymentStatus, '') <> 'مسدد'
          AND DATE(receivedDate) <= DATE(?, '-7 day')
      ''',
      [today],
    );
    final staleRepairCount = _intValue(staleRepairCountRows, 'c');

    final attention = <P03AttentionItem>[];

    final overdueCheques = await _safeRawQuery(
      db,
      '''
        SELECT
          cheque_no,
          number,
          amount,
          currency,
          due_date,
          date,
          bank_name,
          bank
        FROM cheques
        WHERE LOWER(COALESCE(status, 'pending')) IN ('pending','deposited')
          AND DATE(COALESCE(NULLIF(due_date,''), NULLIF(date,''))) < DATE(?)
        ORDER BY DATE(COALESCE(NULLIF(due_date,''), NULLIF(date,''))) ASC
        LIMIT 3
      ''',
      [today],
    );
    for (final row in overdueCheques) {
      final number = _firstText(row, const ['cheque_no', 'number']);
      final due = _displayDate(_firstText(row, const ['due_date', 'date']));
      final bank = _firstText(row, const ['bank_name', 'bank']);
      attention.add(
        P03AttentionItem(
          kind: P03AttentionKind.overdueCheque,
          title: number.isEmpty ? 'شيك متأخر' : 'شيك $number متأخر',
          subtitle: [
            if (due.isNotEmpty) 'استحقاق $due',
            if (bank.isNotEmpty) bank,
          ].join(' • '),
          amount: _asDouble(row['amount']),
        ),
      );
    }

    final dueTodayCheques = await _safeRawQuery(
      db,
      '''
        SELECT
          cheque_no,
          number,
          amount,
          currency,
          due_date,
          date,
          bank_name,
          bank
        FROM cheques
        WHERE LOWER(COALESCE(status, 'pending')) IN ('pending','deposited')
          AND DATE(COALESCE(NULLIF(due_date,''), NULLIF(date,''))) = DATE(?)
        ORDER BY amount DESC
        LIMIT 2
      ''',
      [today],
    );
    for (final row in dueTodayCheques) {
      final number = _firstText(row, const ['cheque_no', 'number']);
      final bank = _firstText(row, const ['bank_name', 'bank']);
      attention.add(
        P03AttentionItem(
          kind: P03AttentionKind.chequeDueToday,
          title: number.isEmpty ? 'شيك يستحق اليوم' : 'شيك $number يستحق اليوم',
          subtitle: bank.isEmpty ? 'يحتاج متابعة اليوم' : bank,
          amount: _asDouble(row['amount']),
        ),
      );
    }

    final staleRepairs = await _safeRawQuery(
      db,
      '''
        SELECT
          id,
          vehicleType,
          vehicleModel,
          vehicleNumber,
          beneficiaryName,
          receivedDate,
          paymentStatus
        FROM repairs
        WHERE COALESCE(isArchived, 0) = 0
          AND COALESCE(paymentStatus, '') <> 'مسدد'
          AND DATE(receivedDate) <= DATE(?, '-7 day')
        ORDER BY DATE(receivedDate) ASC
        LIMIT 3
      ''',
      [today],
    );
    for (final row in staleRepairs) {
      final vehicle = _vehicleLabel(row);
      final beneficiary = _text(row['beneficiaryName']);
      final received = _displayDate(row['receivedDate']);
      attention.add(
        P03AttentionItem(
          kind: P03AttentionKind.staleUnpaidRepair,
          title: vehicle.isEmpty ? 'ملف إصلاح غير مسدد' : vehicle,
          subtitle: [
            if (beneficiary.isNotEmpty) beneficiary,
            if (received.isNotEmpty) 'منذ $received',
          ].join(' • '),
        ),
      );
    }

    final recentRows = await _safeRawQuery(
      db,
      '''
        SELECT
          id,
          vehicleType,
          vehicleModel,
          vehicleNumber,
          beneficiaryName,
          vehicleStatus,
          paymentStatus,
          receivedDate,
          updated_at,
          created_at
        FROM repairs
        ORDER BY datetime(
          COALESCE(
            NULLIF(updated_at,''),
            NULLIF(created_at,''),
            receivedDate
          )
        ) DESC
        LIMIT 5
      ''',
    );

    final recentRepairs = recentRows
        .map((row) {
          final vehicle = _vehicleLabel(row);
          final beneficiary = _text(row['beneficiaryName']);
          final status = _firstText(
            row,
            const ['vehicleStatus', 'paymentStatus'],
          );
          final date = _displayDate(
            _firstText(
              row,
              const ['updated_at', 'created_at', 'receivedDate'],
            ),
          );
          return P03RecentRepair(
            id: _text(row['id']),
            title: vehicle.isEmpty ? 'ملف إصلاح' : vehicle,
            subtitle: beneficiary.isEmpty ? 'بدون اسم مستفيد' : beneficiary,
            status: status,
            date: date,
          );
        })
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);

    return P03HomeSnapshot(
      workshopName: workshopName,
      currencySymbol: currencySymbol,
      repairsReceivedToday: repairsReceivedToday,
      receiptsToday: receiptsToday,
      paymentsToday: paymentsToday,
      chequesDueToday: chequesDueToday,
      attentionCount: overdueChequeCount + chequesDueToday + staleRepairCount,
      attention: List<P03AttentionItem>.unmodifiable(attention),
      recentRepairs: List<P03RecentRepair>.unmodifiable(recentRepairs),
    );
  }

  static Future<List<Map<String, Object?>>> _safeRawQuery(
    dynamic db,
    String sql, [
    List<Object?>? arguments,
  ]) async {
    try {
      final rows = await db.rawQuery(sql, arguments);
      return List<Map<String, Object?>>.from(rows);
    } catch (_) {
      return const <Map<String, Object?>>[];
    }
  }

  static int _intValue(List<Map<String, Object?>> rows, String key) {
    if (rows.isEmpty) return 0;
    final value = rows.first[key];
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  static double _doubleValue(List<Map<String, Object?>> rows, String key) {
    if (rows.isEmpty) return 0;
    return _asDouble(rows.first[key]);
  }

  static double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  static String _vehicleLabel(Map<String, Object?> row) {
    final type = _text(row['vehicleType']);
    final model = _text(row['vehicleModel']);
    final number = _text(row['vehicleNumber']);
    final pieces = <String>[
      if (type.isNotEmpty) type,
      if (model.isNotEmpty && model != type) model,
      if (number.isNotEmpty) number,
    ];
    return pieces.join(' • ');
  }

  static String _firstText(
    Map<String, Object?> row,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = _text(row[key]);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static String _text(Object? value) => value?.toString().trim() ?? '';

  static String _displayDate(Object? value) {
    final raw = _text(value);
    if (raw.isEmpty) return '';

    final parsed = DateTime.tryParse(raw);
    if (parsed != null) {
      final day = parsed.day.toString().padLeft(2, '0');
      final month = parsed.month.toString().padLeft(2, '0');
      return '$day-$month-${parsed.year}';
    }

    final isoDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
    if (isoDate != null) {
      return '${isoDate.group(3)}-${isoDate.group(2)}-${isoDate.group(1)}';
    }

    return raw;
  }

  static String _dateOnly(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
