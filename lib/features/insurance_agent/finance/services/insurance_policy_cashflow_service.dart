import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_book_service.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_financial_service.dart';
import 'package:yalla_accounts/features/vouchers/services/voucher_payment_service.dart';

class InsurancePolicyCashflowMovement {
  const InsurancePolicyCashflowMovement({
    required this.key,
    required this.direction,
    required this.amount,
    required this.status,
    required this.activityDate,
    required this.method,
    this.receiptNumber,
    this.voucherId,
    this.chequeId,
    this.chequeNumber,
    this.chequeStatus,
    this.chequeDirection,
    this.chequeBankName,
    this.chequeDueDate,
    this.notes,
    this.reversalReason,
  });

  final String key;
  final String direction;
  final double amount;
  final String status;
  final DateTime activityDate;
  final String method;
  final int? receiptNumber;
  final String? voucherId;
  final int? chequeId;
  final String? chequeNumber;
  final String? chequeStatus;
  final String? chequeDirection;
  final String? chequeBankName;
  final DateTime? chequeDueDate;
  final String? notes;
  final String? reversalReason;

  bool get isPosted => status.toUpperCase() == 'POSTED';
  bool get canReverse =>
      isPosted &&
      ((direction == 'CUSTOMER_RECEIPT' && receiptNumber != null) ||
          (direction == 'INSURER_PAYMENT' &&
              voucherId != null &&
              voucherId!.trim().isNotEmpty));
}

class InsuranceChequeBookOption {
  const InsuranceChequeBookOption({
    required this.id,
    required this.bankAccountId,
    required this.bookNumber,
    required this.nextAvailableNumber,
    required this.lastChequeNumber,
    required this.bankAccountName,
    required this.bankAccountCode,
  });

  final String id;
  final int bankAccountId;
  final String bookNumber;
  final int nextAvailableNumber;
  final int lastChequeNumber;
  final String bankAccountName;
  final String bankAccountCode;

  String get label => '$bookNumber • $bankAccountName • #$nextAvailableNumber';
}

class InsurancePolicyCashflowSnapshot {
  const InsurancePolicyCashflowSnapshot({
    required this.policyId,
    required this.policyNumber,
    required this.insuredName,
    required this.companyName,
    required this.vehiclePlate,
    required this.balances,
    required this.movements,
  });

  final String policyId;
  final String policyNumber;
  final String insuredName;
  final String companyName;
  final String vehiclePlate;
  final InsurancePolicyBalances balances;
  final List<InsurancePolicyCashflowMovement> movements;
}

class InsurancePolicyCashflowService {
  InsurancePolicyCashflowService._();

  static double _n(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime _date(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '') ?? DateTime(1970);

  static Future<InsurancePolicyCashflowSnapshot> load(
    String policyId, {
    DatabaseExecutor? executor,
  }) async {
    final id = policyId.trim();
    if (id.isEmpty) throw ArgumentError('Insurance policy id is required.');
    final db = executor ?? await DBService.database;

    final policies = await db.rawQuery(
      '''SELECT p.id, p.policy_number, p.vehicle_plate,
                c.name AS insured_name, ic.name AS company_name
         FROM insurance_policies p
         LEFT JOIN clients c ON c.id=p.client_id
         LEFT JOIN insurance_companies ic ON ic.id=p.insurance_company_id
         WHERE p.id=?
         LIMIT 1''',
      [id],
    );
    if (policies.isEmpty) throw StateError('Insurance policy not found.');
    final policy = policies.single;

    final links = await db.rawQuery(
      '''SELECT ipp.*,
                p.method AS receipt_method,
                p.date AS receipt_date,
                p.notes AS receipt_notes,
                v.method AS voucher_method,
                v.date AS voucher_date,
                v.notes AS voucher_notes,
                ch.cheque_no AS cheque_number,
                ch.status AS cheque_status,
                ch.direction AS cheque_direction,
                ch.bank_name AS cheque_bank_name,
                ch.due_date AS cheque_due_date
         FROM insurance_policy_payments ipp
         LEFT JOIN payments p ON p.id=ipp.payment_id
         LEFT JOIN vouchers v ON v.id=ipp.voucher_id
         LEFT JOIN cheques ch ON ch.id=ipp.cheque_id
         WHERE ipp.policy_id=?
         ORDER BY ipp.created_at DESC, ipp.id DESC''',
      [id],
    );

    final grouped = <String, _MovementAccumulator>{};
    for (final row in links) {
      final direction = (row['direction'] ?? '').toString();
      final receiptNumber = row['receipt_number'] is num
          ? (row['receipt_number'] as num).toInt()
          : int.tryParse(row['receipt_number']?.toString() ?? '');
      final voucherId = row['voucher_id']?.toString();
      final key = direction == 'CUSTOMER_RECEIPT' && receiptNumber != null
          ? '$direction:$receiptNumber'
          : direction == 'INSURER_PAYMENT' &&
                  voucherId != null &&
                  voucherId.trim().isNotEmpty
              ? '$direction:$voucherId'
              : '$direction:${row['id']}';
      final method = direction == 'CUSTOMER_RECEIPT'
          ? (row['receipt_method'] ?? '').toString()
          : (row['voucher_method'] ?? '').toString();
      final activityDate = direction == 'CUSTOMER_RECEIPT'
          ? _date(row['receipt_date'] ?? row['created_at'])
          : _date(row['voucher_date'] ?? row['created_at']);
      final notes = direction == 'CUSTOMER_RECEIPT'
          ? row['receipt_notes']?.toString()
          : row['voucher_notes']?.toString();

      final accumulator = grouped.putIfAbsent(
        key,
        () => _MovementAccumulator(
          key: key,
          direction: direction,
          status: (row['status'] ?? 'POSTED').toString(),
          activityDate: activityDate,
          receiptNumber: receiptNumber,
          voucherId: voucherId,
          notes: notes,
          reversalReason: row['reversal_reason']?.toString(),
          chequeNumber: row['cheque_number']?.toString(),
          chequeStatus: row['cheque_status']?.toString(),
          chequeDirection: row['cheque_direction']?.toString(),
          chequeBankName: row['cheque_bank_name']?.toString(),
          chequeDueDate: row['cheque_due_date'] == null
              ? null
              : _date(row['cheque_due_date']),
        ),
      );
      accumulator.amount += _n(row['amount']);
      if (method.trim().isNotEmpty) accumulator.methods.add(method.trim());
      if (row['cheque_id'] is num) {
        accumulator.chequeId ??= (row['cheque_id'] as num).toInt();
      }
      final status = (row['status'] ?? '').toString();
      if (status.toUpperCase() != 'POSTED') accumulator.status = status;
      accumulator.reversalReason ??= row['reversal_reason']?.toString();
    }

    final movements = grouped.values
        .map((entry) => entry.build())
        .toList(growable: false)
      ..sort((a, b) => b.activityDate.compareTo(a.activityDate));

    return InsurancePolicyCashflowSnapshot(
      policyId: id,
      policyNumber: (policy['policy_number'] ?? id).toString(),
      insuredName: (policy['insured_name'] ?? '').toString(),
      companyName: (policy['company_name'] ?? '').toString(),
      vehiclePlate: (policy['vehicle_plate'] ?? '').toString(),
      balances: await InsuranceFinancialService.balances(id, executor: db),
      movements: movements,
    );
  }

  static Future<void> collectCustomer({
    required String operationId,
    required String policyId,
    required double amount,
    required DateTime date,
    required String method,
    String? notes,
    Map<String, dynamic>? chequeDraft,
    Database? database,
  }) async {
    final db = database ?? await DBService.database;
    final balances =
        await InsuranceFinancialService.balances(policyId, executor: db);
    if (!amount.isFinite || amount <= 0.005) {
      throw ArgumentError('Customer receipt amount must be positive.');
    }
    if (amount - balances.customerOutstanding > 0.005) {
      throw StateError('Receipt exceeds the customer outstanding balance.');
    }
    final canonicalMethod = method.trim().toUpperCase();
    final isCheque = canonicalMethod == 'CHEQUE';
    if (isCheque && chequeDraft == null) {
      throw ArgumentError('Cheque receipt requires cheque details.');
    }
    final authorization = await PaymentService.preauthorizeInsuranceReceipt(
      includesCheque: isCheque,
    );
    await InsuranceFinancialService.collectPolicy(
      operationId: operationId,
      policyId: policyId,
      date: date,
      database: db,
      authorizationToken: authorization,
      notes: notes,
      instruments: [
        ReceiptInstrumentInput(
          instrumentKey: '$operationId:1',
          method: canonicalMethod.toLowerCase(),
          amount: amount,
          chequeDraft: chequeDraft,
        ),
      ],
    );
  }

  static Future<List<InsuranceChequeBookOption>> listOpenChequeBooks({
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DBService.database;
    final rows = await ChequeBookService.list(executor: db);
    final result = <InsuranceChequeBookOption>[];
    for (final row in rows) {
      final status = (row['status'] ?? '').toString().toUpperCase();
      final next = (row['next_available_number'] as num?)?.toInt();
      final last = (row['last_cheque_number'] as num?)?.toInt();
      final bankAccountId = (row['bank_account_id'] as num?)?.toInt();
      final id = row['id']?.toString().trim() ?? '';
      if (status != 'OPEN' ||
          next == null ||
          last == null ||
          next > last ||
          bankAccountId == null ||
          bankAccountId <= 0 ||
          id.isEmpty) {
        continue;
      }
      result.add(
        InsuranceChequeBookOption(
          id: id,
          bankAccountId: bankAccountId,
          bookNumber: (row['book_number'] ?? '').toString(),
          nextAvailableNumber: next,
          lastChequeNumber: last,
          bankAccountName: (row['bank_account_name'] ?? '').toString(),
          bankAccountCode: (row['bank_account_code'] ?? '').toString(),
        ),
      );
    }
    return result;
  }

  static Future<String> _drawerName(DatabaseExecutor db) async {
    final organization = await db.rawQuery(
      '''SELECT o.display_name
         FROM organization_identity oi
         JOIN organizations o ON o.id=oi.organization_id
         WHERE oi.singleton_id=1
         LIMIT 1''',
    );
    final organizationName = organization.isEmpty
        ? ''
        : (organization.single['display_name'] ?? '').toString().trim();
    if (organizationName.isNotEmpty) return organizationName;

    try {
      final workshop = await db.query(
        'workshop_settings',
        columns: const ['workshopName'],
        where: 'id=?',
        whereArgs: const [1],
        limit: 1,
      );
      final workshopName = workshop.isEmpty
          ? ''
          : (workshop.single['workshopName'] ?? '').toString().trim();
      if (workshopName.isNotEmpty) return workshopName;
    } catch (_) {}
    return 'Yallah Accounts';
  }

  static Future<void> payInsurerByCheque({
    required String operationId,
    required String policyId,
    required double amount,
    required DateTime issueDate,
    required DateTime dueDate,
    required String chequeBookId,
    String? notes,
    Database? database,
  }) async {
    if (dueDate.isBefore(issueDate)) {
      throw ArgumentError('Cheque due date cannot be before issue date.');
    }
    final db = database ?? await DBService.database;
    final books = await listOpenChequeBooks(executor: db);
    final book = books.where((entry) => entry.id == chequeBookId).firstOrNull;
    if (book == null) {
      throw StateError('Selected cheque book is not open or is exhausted.');
    }
    final nextNumber = await ChequeBookService.nextAvailableNumber(db, book.id);
    if (nextNumber != book.nextAvailableNumber) {
      throw StateError('Cheque book sequence changed; reload before posting.');
    }
    final drawerName = await _drawerName(db);
    final bankName = book.bankAccountName.trim().isEmpty
        ? book.bankAccountCode
        : book.bankAccountName.trim();

    await payInsurer(
      operationId: operationId,
      policyId: policyId,
      amount: amount,
      date: issueDate,
      method: 'CHEQUE',
      notes: notes,
      chequeDraft: {
        'instrument_key': '$operationId:CHEQUE',
        'cheque_no': nextNumber.toString(),
        'drawer_name': drawerName,
        'bank_name': bankName,
        'issue_date': issueDate.toIso8601String(),
        'due_date': dueDate.toIso8601String(),
        'bank_account_id': book.bankAccountId,
        'cheque_book_id': book.id,
      },
      database: db,
    );
  }

  static Future<void> payInsurer({
    required String operationId,
    required String policyId,
    required double amount,
    required DateTime date,
    required String method,
    String? notes,
    Map<String, dynamic>? chequeDraft,
    Database? database,
  }) async {
    final db = database ?? await DBService.database;
    final balances =
        await InsuranceFinancialService.balances(policyId, executor: db);
    if (!amount.isFinite || amount <= 0.005) {
      throw ArgumentError('Insurance-company payment must be positive.');
    }
    if (amount - balances.insurerOutstanding > 0.005) {
      throw StateError('Payment exceeds the insurance-company balance.');
    }
    final canonicalMethod = method.trim().toUpperCase();
    if (canonicalMethod == 'CHEQUE' && chequeDraft == null) {
      throw ArgumentError('Cheque insurer payment requires cheque details.');
    }
    await InsuranceFinancialService.payInsuranceCompanyForPolicy(
      operationId: operationId,
      policyId: policyId,
      amount: amount,
      date: date,
      method: method.trim().toUpperCase(),
      notes: notes,
      chequeDraft: chequeDraft,
      database: db,
    );
  }

  static Future<void> reverseMovement({
    required InsurancePolicyCashflowMovement movement,
    required String reason,
    Database? database,
  }) async {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw ArgumentError('A reversal reason is required.');
    }
    final db = database ?? await DBService.database;
    if (!movement.isPosted) {
      throw StateError('Insurance movement is already reversed.');
    }
    if (movement.direction == 'CUSTOMER_RECEIPT' &&
        movement.receiptNumber != null) {
      await PaymentService.reverseReceipt(
        movement.receiptNumber!,
        reason: cleanReason,
        database: db,
      );
      return;
    }
    if (movement.direction == 'INSURER_PAYMENT' &&
        movement.voucherId != null &&
        movement.voucherId!.trim().isNotEmpty) {
      await VoucherPaymentService.reverseVoucher(
        movement.voucherId!,
        reason: cleanReason,
        database: db,
      );
      return;
    }
    throw StateError('This insurance movement cannot be reversed here.');
  }
}

class _MovementAccumulator {
  _MovementAccumulator({
    required this.key,
    required this.direction,
    required this.status,
    required this.activityDate,
    this.receiptNumber,
    this.voucherId,
    this.notes,
    this.reversalReason,
    this.chequeNumber,
    this.chequeStatus,
    this.chequeDirection,
    this.chequeBankName,
    this.chequeDueDate,
  });

  final String key;
  final String direction;
  double amount = 0;
  String status;
  final DateTime activityDate;
  final int? receiptNumber;
  final String? voucherId;
  int? chequeId;
  final String? notes;
  String? reversalReason;
  final String? chequeNumber;
  final String? chequeStatus;
  final String? chequeDirection;
  final String? chequeBankName;
  final DateTime? chequeDueDate;
  final Set<String> methods = <String>{};

  InsurancePolicyCashflowMovement build() => InsurancePolicyCashflowMovement(
        key: key,
        direction: direction,
        amount: amount,
        status: status,
        activityDate: activityDate,
        method: methods.isEmpty
            ? ''
            : methods.length == 1
                ? methods.first
                : 'MIXED',
        receiptNumber: receiptNumber,
        voucherId: voucherId,
        chequeId: chequeId,
        chequeNumber: chequeNumber,
        chequeStatus: chequeStatus,
        chequeDirection: chequeDirection,
        chequeBankName: chequeBankName,
        chequeDueDate: chequeDueDate,
        notes: notes,
        reversalReason: reversalReason,
      );
}
