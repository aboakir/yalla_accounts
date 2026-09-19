import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/clients/models/client.dart';
import 'package:yalla_accounts/features/finance/models/monthly_expense.dart';
import 'package:yalla_accounts/features/finance/payments/models/payment.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/settings/models/workshop_settings.dart';
import 'package:yalla_accounts/features/vehicles/models/vehicle.dart';

Repair _repair({
  PaymentType paymentType = PaymentType.cash,
  double fileValue = 1000,
  double paidAmount = 250,
  String? paymentStatus,
  bool isArchived = false,
  String status = RepairStatusText.approved,
  List<CheckDetail>? checkDetails,
  List<Installment>? installmentSchedule,
}) {
  return Repair(
    id: 'R-1',
    invoiceNumber: 'INV-1',
    vehicleModel: 'Corolla',
    vehicleType: 'Sedan',
    vehicleNumber: '12-345-67',
    receivedDate: DateTime.utc(2026, 9, 1, 10),
    beneficiaryType: 'CUSTOMER',
    beneficiaryName: 'Ahmad',
    clientId: 7,
    insuranceStatus: 'NONE',
    repairType: 'BODY_PAINT',
    vehicleStatus: 'IN_PROGRESS',
    status: status,
    quoteNumber: 'Q-1',
    quoteValidUntil: DateTime.utc(2026, 9, 30),
    approvedAt: DateTime.utc(2026, 9, 2),
    approvedBy: 'owner',
    insuranceFollowUpStatus: 'NONE',
    parts: const [
      {'qty': 2, 'price': 100},
      {'total': 75},
      {'qty': 0, 'unit_price': 25},
    ],
    works: const [
      {'quantity': 2, 'unitPrice': 60},
      {'total': 80},
    ],
    fileValue: fileValue,
    paymentType: paymentType,
    paidAmount: paidAmount,
    paymentStatus: paymentStatus,
    checkDetails: checkDetails,
    installmentSchedule: installmentSchedule,
    notes: 'note',
    imagePaths: const ['a.jpg', 'b.jpg'],
    thumbnailPath: 'thumb.jpg',
    thumbnailUpdatedAt: DateTime.utc(2026, 9, 2, 12),
    transferFromAccount: '1000',
    transferToAccount: '1010',
    transferCompany: 'Bank',
    transferDate: DateTime.utc(2026, 9, 3),
    transferAmount: 300,
    transferImagePath: 'transfer.jpg',
    isArchived: isArchived,
    actualCost: 500,
    workCost: 200,
    incomeAmount: 900,
    isLedgerEnabled: true,
    isLedgerSynced: true,
    finalApprovedAmount: 1000,
    invoiceId: 'I-1',
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 3),
  );
}

Cheque _cheque({
  ChequeType type = ChequeType.incoming,
  ChequeStatus status = ChequeStatus.pending,
}) {
  return Cheque(
    id: 4,
    uuid: 'C-UUID',
    chequeNo: 'CHK-100',
    chequeType: type,
    status: status,
    drawerName: 'Drawer',
    bankName: 'Bank',
    bankBranch: 'Bethlehem',
    amount: 1200.5,
    currency: 'ILS',
    issueDate: DateTime.utc(2026, 9, 1),
    dueDate: DateTime.utc(2026, 10, 1),
    sourceType: 'PAYMENT',
    sourceId: 'P-1',
    supplierPid: '12',
    clientId: 7,
    recipientType: 'SUPPLIER',
    recipientId: '12',
    recipientName: 'Supplier',
    glEntryId: 99,
    notes: 'note',
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 2),
    originChequeId: 'C-OLD',
    isEndorsed: 1,
    endorsedAt: '2026-09-03T00:00:00.000Z',
    lastEndorserName: 'Endorser',
    linkedPaymentIds: const ['P-1', 'P-2'],
    linkedRepairIds: const ['R-1'],
    autoReturnDate: DateTime.utc(2026, 11, 1),
    returnReason: 'reason',
    isLegacyIncomplete: 1,
  );
}

void main() {
  group('Group3A Repair model business coverage', () {
    test('numeric/date/detail helpers normalize valid and invalid input', () {
      expect(tryDouble(null), isNull);
      expect(tryDouble(2), 2.0);
      expect(tryDouble(2.5), 2.5);
      expect(tryDouble('3.75'), 3.75);
      expect(tryDouble('bad'), isNull);

      final check = CheckDetail.fromMap({
        'amount': '125.50',
        'issue_date': '2026-09-01',
        'due_date': '2026-10-01',
        'receiver': 'workshop',
        'from': 'client',
        'note': 'n',
        'checkNumber': '44',
        'bankName': 'B',
        'checkOwner': 'O',
        'drawer': 'D',
      });
      expect(check.amount, 125.5);
      expect(check.validateDates(), isTrue);
      expect(check.toMap()['checkNumber'], '44');

      final badCheck = CheckDetail(
        amount: 1,
        issueDate: 'not-date',
        dueDate: 'also-bad',
      );
      expect(badCheck.validateDates(), isFalse);

      final installment = Installment.fromMap({
        'amount': 80,
        'due_date': '2026-12-01',
        'paid': 'true',
        'receiver': 'r',
        'from': 'f',
        'note': 'n',
      });
      expect(installment.amount, 80);
      expect(installment.paid, isTrue);
      expect(installment.validateDueDate(), isTrue);
      expect(installment.toMap()['paid'], isTrue);

      expect(
        Installment(amount: 1, dueDate: 'bad').validateDueDate(),
        isFalse,
      );
      expect(Installment.fromMap({'amount': 'bad', 'dueDate': ''}).amount, 0);
      expect(CheckDetail.fromMap({'amount': 'bad'}).amount, 0);
    });

    test('repair round-trip preserves canonical finance and links', () {
      final source = _repair(
        checkDetails: [
          CheckDetail(
            amount: 100,
            issueDate: '2026-09-01',
            dueDate: '2026-10-01',
          ),
        ],
        installmentSchedule: [
          Installment(amount: 50, dueDate: '2026-11-01'),
        ],
      );

      expect(source.totalPartsPrice, 300);
      expect(source.totalWorksPrice, 200);
      expect(source.totalFileValue, 1000);
      expect(source.totalPaidAmount, 250);
      expect(source.remainingAmount, 750);
      expect(source.customerCredit, 0);
      expect(source.isFinanciallySettled, isFalse);
      expect(source.isClosed, isFalse);
      expect(source.computedPaymentStatus, 'مسدد جزئي');
      expect(source.displayPaymentStatus, 'مسدد جزئي');
      expect(source.customerName, 'Ahmad');
      expect(source.paymentMethodText, 'نقداً');
      expect(source.paymentMethod, 'صندوق');
      expect(source.remaining, 750);
      expect(source.validate(), isTrue);

      final map = source.toMap();
      expect(map['invoice_id'], 'I-1');
      expect(map['thumbnail_path'], 'thumb.jpg');
      expect(map['isLedgerEnabled'], 1);
      expect(map['paymentType'], 'cash');

      final changed = source.copyWith(
        id: 'R-2',
        invoiceNumber: 'INV-2',
        vehicleModel: 'Camry',
        vehicleType: 'SUV',
        vehicleNumber: '88',
        receivedDate: DateTime.utc(2026, 9, 4),
        beneficiaryType: 'INSURANCE',
        beneficiaryName: 'Insurer',
        clientId: 8,
        insuranceStatus: 'OPEN',
        repairType: 'PAINT',
        vehicleStatus: 'DONE',
        status: RepairStatusText.closed,
        quoteNumber: 'Q-2',
        quoteValidUntil: DateTime.utc(2026, 10, 1),
        approvedAt: DateTime.utc(2026, 9, 5),
        approvedBy: 'admin',
        insuranceFollowUpStatus: 'DONE',
        parts: const [
          {'total': 10},
        ],
        works: const [
          {'total': 20},
        ],
        fileValue: 30,
        paymentType: PaymentType.check,
        paidAmount: 30,
        paymentStatus: 'custom',
        checkDetails: const [],
        installmentSchedule: const [],
        notes: 'changed',
        imagePaths: const ['c.jpg'],
        thumbnailPath: 'new.jpg',
        thumbnailUpdatedAt: DateTime.utc(2026, 9, 5),
        transferFromAccount: 'A',
        transferToAccount: 'B',
        transferCompany: 'C',
        transferDate: DateTime.utc(2026, 9, 6),
        transferAmount: 30,
        transferImagePath: 'x.jpg',
        isArchived: true,
        actualCost: 10,
        workCost: 5,
        incomeAmount: 30,
        isLedgerEnabled: false,
        isLedgerSynced: false,
        finalApprovedAmount: 30,
        invoiceId: 'I-2',
        createdAt: DateTime.utc(2026, 9, 4),
        updatedAt: DateTime.utc(2026, 9, 6),
      );

      expect(changed.id, 'R-2');
      expect(changed.isClosed, isTrue);
      expect(changed.isFinanciallySettled, isTrue);
      expect(changed.displayPaymentStatus, 'custom');
      expect(changed.paymentMethodText, 'شيك');
      expect(changed.paymentMethod, 'بنك');
    });

    test('fromMap accepts legacy/snake case and safely rejects malformed data',
        () {
      final parsed = Repair.fromMap({
        'id': 77,
        'invoice_number': 'INV-77',
        'vehicle_model': 'Elantra',
        'vehicle_type': 'Sedan',
        'vehicle_number': 991,
        'received_date': 1700000000,
        'beneficiary_type': 'CUSTOMER',
        'beneficiary_name': 'Customer',
        'client_id': '9',
        'insurance_status': 'NONE',
        'repair_type': 'BODY',
        'repair_status': 'ACTIVE',
        'status': 'QUOTE',
        'quote_number': 'Q-77',
        'quote_valid_until': '2026-12-01T00:00:00.000Z',
        'approved_at': 1700000000000,
        'approved_by': 'owner',
        'insurance_followup': 'WAITING',
        'parts': '[{"qty":2,"price":50}]',
        'works': [
          {'quantity': 2, 'unit_price': 25},
        ],
        'file_value': '150',
        'payment_type': 'check',
        'total_paid_amount': '50',
        'payment_status': 'partial',
        'checkDetails':
            '[{"amount":"20","issue_date":"2026-09-01","due_date":"2026-10-01"}]',
        'installmentSchedule':
            '[{"amount":"30","due_date":"2026-11-01","paid":1}]',
        'notes': 123,
        'imagePaths': '["a","b"]',
        'thumbnail_path': 't.jpg',
        'thumbnail_updated_at': '2026-09-02T00:00:00.000Z',
        'transferFromAccount': '1000',
        'transferToAccount': '1010',
        'transferCompany': 'Bank',
        'transfer_date': '2026-09-03T00:00:00.000Z',
        'transferAmount': '40',
        'transferImagePath': 'tr.jpg',
        'isArchived': 1,
        'actualCost': '80',
        'workCost': 10,
        'incomeAmount': '150',
        'isLedgerEnabled': true,
        'isLedgerSynced': 1,
        'finalApprovedAmount': '150',
        'invoice_id': 'I-77',
        'created_at': '2026-09-01T00:00:00.000Z',
        'updated_at': 1700000000,
      });

      expect(parsed.id, '77');
      expect(parsed.clientId, 9);
      expect(parsed.paymentType, PaymentType.check);
      expect(parsed.parts, hasLength(1));
      expect(parsed.works, hasLength(1));
      expect(parsed.checkDetails, hasLength(1));
      expect(parsed.installmentSchedule, hasLength(1));
      expect(parsed.imagePaths, ['a', 'b']);
      expect(parsed.fileValue, 150);
      expect(parsed.paidAmount, 50);
      expect(parsed.invoiceId, 'I-77');

      final malformed = Repair.fromMap({
        'id': null,
        'invoiceNumber': '',
        'vehicleModel': '',
        'vehicleType': '',
        'vehicleNumber': '',
        'receivedDate': 'not-a-date',
        'beneficiaryType': '',
        'beneficiaryName': '',
        'insuranceStatus': '',
        'repairType': '',
        'vehicleStatus': '',
        'status': '',
        'parts': 'not-json',
        'works': {'bad': true},
        'total_file_value': '77',
        'paymentType': 'unknown-type',
        'paidAmount': 'bad',
        'checkDetails': 'bad-json',
        'installmentSchedule': 'bad-json',
        'imagePaths': 'bad-json',
        'isArchived': false,
        'isLedgerEnabled': false,
        'isLedgerSynced': false,
      });

      expect(malformed.receivedDate, DateTime.fromMillisecondsSinceEpoch(0));
      expect(malformed.status, RepairStatusText.invoiced);
      expect(malformed.parts, isEmpty);
      expect(malformed.works, isEmpty);
      expect(malformed.imagePaths, isEmpty);
      expect(malformed.checkDetails, isNull);
      expect(malformed.installmentSchedule, isNull);
      expect(malformed.fileValue, 77);
      expect(malformed.paymentType, PaymentType.cash);
      expect(malformed.paidAmount, 0);
      expect(malformed.validate(), isFalse);
    });

    test('all payment methods and settlement branches are explicit', () {
      final zero = _repair(fileValue: 0, paidAmount: 0);
      expect(zero.computedPaymentStatus, 'مسدد');

      final unpaid = _repair(fileValue: 100, paidAmount: 0);
      expect(unpaid.computedPaymentStatus, 'غير مسدد');

      final paid = _repair(fileValue: 100, paidAmount: 100);
      expect(paid.computedPaymentStatus, 'مسدد');

      final credit = _repair(fileValue: 100, paidAmount: 125);
      expect(credit.remainingAmount, 0);
      expect(credit.customerCredit, 25);

      for (final type in PaymentType.values) {
        final repair = _repair(paymentType: type);
        expect(repair.paymentMethodText, isNotEmpty);
        expect(repair.paymentMethod, isNotEmpty);
      }

      final invalidCheck = _repair(
        checkDetails: [
          CheckDetail(amount: 1, issueDate: 'bad', dueDate: 'bad'),
        ],
      );
      expect(invalidCheck.validate(), isFalse);

      final invalidInstallment = _repair(
        installmentSchedule: [
          Installment(amount: 1, dueDate: 'bad'),
        ],
      );
      expect(invalidInstallment.validate(), isFalse);
    });
  });

  group('Group3A Cheque model coverage', () {
    test('full cheque map/copy contracts preserve commercial metadata', () {
      final cheque = _cheque();
      final map = cheque.toMap();

      expect(map['cheque_no'], 'CHK-100');
      expect(map['number'], 'CHK-100');
      expect(map['bank'], 'Bank');
      expect(map['supplier_id'], 12);
      expect(map['payment_id'], 'P-1');
      expect(map['linked_payment_ids'], contains('P-1'));
      expect(map['is_legacy_incomplete'], 1);

      final changed = cheque.copyWith(
        id: 5,
        uuid: 'NEW',
        chequeNo: 'NEW-NO',
        chequeType: ChequeType.outgoing,
        status: ChequeStatus.delivered,
        drawerName: 'D2',
        bankName: 'B2',
        bankBranch: 'R2',
        amount: 99,
        currency: 'USD',
        issueDate: DateTime.utc(2026, 1, 1),
        dueDate: DateTime.utc(2026, 2, 1),
        sourceType: 'OTHER',
        sourceId: 'S2',
        supplierPid: '13',
        clientId: 8,
        recipientType: 'OTHER',
        recipientId: 'R2',
        recipientName: 'Recipient',
        glEntryId: 100,
        notes: 'changed',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 2),
        originChequeId: 'O2',
        isEndorsed: 0,
        endorsedAt: 'date',
        lastEndorserName: 'E2',
        linkedRepairIds: const ['R2'],
        linkedPaymentIds: const ['P2'],
        autoReturnDate: DateTime.utc(2026, 3, 1),
        returnReason: 'rr',
        isLegacyIncomplete: 0,
      );

      expect(changed.id, 5);
      expect(changed.chequeType, ChequeType.outgoing);
      expect(changed.status, ChequeStatus.delivered);
      expect(changed.amount, 99);
    });

    test('fromMap parses every type/status and malformed legacy JSON safely',
        () {
      const types = {
        'incoming': ChequeType.incoming,
        'outgoing': ChequeType.outgoing,
        'collection': ChequeType.collection,
        'unexpected': ChequeType.outgoing,
      };

      const statuses = {
        'pending': ChequeStatus.pending,
        'collected': ChequeStatus.collected,
        'returned': ChequeStatus.returned,
        'cancelled': ChequeStatus.cancelled,
        'delivered': ChequeStatus.delivered,
        'deposited': ChequeStatus.deposited,
        'received': ChequeStatus.received,
        'held': ChequeStatus.held,
        'endorsed': ChequeStatus.endorsed,
        'issued': ChequeStatus.issued,
        'presented': ChequeStatus.presented,
        'due': ChequeStatus.presented,
        'cleared': ChequeStatus.cleared,
        'unexpected': ChequeStatus.received,
      };

      for (final type in types.entries) {
        final parsed = Cheque.fromMap({
          'id': 1,
          'uuid': 'U',
          'cheque_no': 'N',
          'cheque_type': type.key,
          'status': 'pending',
          'drawer_name': 'D',
          'bank_name': 'B',
          'bank_branch': 'BR',
          'amount': '12.5',
          'currency': 'ILS',
          'issue_date': '2026-09-01',
          'due_date': '2026-10-01',
          'linked_repair_ids': '["R1"]',
          'linked_payment_ids': '["P1"]',
          'created_at': '2026-09-01',
          'updated_at': '2026-09-02',
          'auto_return_date': '2026-11-01T00:00:00.000',
        });
        expect(parsed.chequeType, type.value);
        expect(parsed.linkedRepairIds, ['R1']);
        expect(parsed.linkedPaymentIds, ['P1']);
      }

      for (final status in statuses.entries) {
        final parsed = Cheque.fromMap({
          'uuid': 'U',
          'number': 'N',
          'cheque_type': 'incoming',
          'status': status.key,
          'drawer_name': 'D',
          'bank': 'B',
          'bank_branch': 'BR',
          'amount': 'bad',
          'date': 'bad',
          'currency': 'ILS',
          'created_at': 'bad',
          'updated_at': 'bad',
          'linked_repair_ids': 'not-json',
          'linked_payment_ids': 'not-json',
          'origin_cheque_id': '',
          'is_endorsed': 'bad',
          'is_legacy_incomplete': 'bad',
        });
        expect(parsed.status, status.value);
        expect(parsed.amount, 0);
        expect(parsed.issueDate, DateTime(1970));
        expect(parsed.dueDate, DateTime(1970));
        expect(parsed.linkedRepairIds, isEmpty);
        expect(parsed.linkedPaymentIds, isEmpty);
        expect(parsed.originChequeId, isNull);
        expect(parsed.isEndorsed, 0);
        expect(parsed.isLegacyIncomplete, 0);
      }
    });
  });

  group('Group3A Payment/Client/Expense model coverage', () {
    test('payment fromMap/toMap/copyWith handles nulls, strings and epochs',
        () {
      final p = Payment.fromMap({
        'id': 7,
        'receipt_number': '22',
        'reversal_of_payment_id': 'P-OLD',
        'client_id': '3',
        'repair_id': 9,
        'invoice_id': 'I1',
        'relatedRepairId': 'R2',
        'amount': '44.5',
        'date': 1700000000000,
        'method': 'cash',
        'accountName': 'Cash',
        'status': 'confirmed',
        'notes': 55,
        'attachments': 'a.pdf',
        'gl_entry_id': '90',
        'cheque_id': '4',
        'isIncome': 1,
      });

      expect(p.id, '7');
      expect(p.receiptNumber, 22);
      expect(p.amount, 44.5);
      expect(p.isIncome, isTrue);
      expect(p.toMap()['isIncome'], 1);

      final changed = p.copyWith(
        id: 'P2',
        receiptNumber: 23,
        reversalOfPaymentId: 'X',
        clientId: 4,
        repairId: 'R4',
        invoiceId: 'I4',
        relatedRepairId: 'R5',
        amount: 50,
        date: DateTime.utc(2026, 9, 6),
        method: 'bank',
        accountName: 'Bank',
        status: 'pending',
        notes: 'n',
        attachments: 'b',
        glEntryId: 91,
        chequeId: 5,
        isIncome: false,
      );
      expect(changed.id, 'P2');
      expect(changed.isIncome, isFalse);

      final defaults = Payment.fromMap({
        'amount': 'bad',
        'date': 'bad',
        'isIncome': 0,
      });
      expect(defaults.id, '');
      expect(defaults.amount, 0);
      expect(defaults.date, DateTime(1970));
      expect(defaults.method, '');
      expect(defaults.status, '');
      expect(defaults.isIncome, isFalse);

      final nullDate = Payment.fromMap({'date': null, 'amount': null});
      expect(nullDate.date, DateTime(1970));
      expect(nullDate.amount, 0);
    });

    test('client normalization, mapping, equality and insurance helpers work',
        () {
      final insurance = Client.fromMap({
        'id': '5',
        'name': '  شركة الأمان للتأمين  ',
        'type': 'شركة تأمين',
        'phone': 123,
        'email': 'a@b.c',
        'address': 'Bethlehem',
        'notes': 'n',
      });

      expect(insurance.id, 5);
      expect(insurance.isInsurance, isTrue);
      expect(insurance.isIndividual, isFalse);
      expect(insurance.displayTypeAr, 'شركة تأمين');
      expect(insurance.normalizedName, 'الأمان لل');
      expect(insurance.toMap()['id'], 5);
      expect(insurance.toString(), contains('شركة الأمان'));

      final clone = insurance.copyWith();
      expect(clone, insurance);
      expect(clone.hashCode, insurance.hashCode);

      final individual = insurance.copyWith(
        id: 6,
        name: 'Ali',
        type: 'أفراد',
        phone: '9',
        email: '',
        address: '',
        notes: '',
      );
      expect(individual.isIndividual, isTrue);
      expect(individual.displayTypeAr, 'أفراد');
      expect(individual == insurance, isFalse);

      final noId = Client.fromMap({
        'id': 'bad',
        'name': null,
        'type': null,
      });
      expect(noId.id, isNull);
      expect(noId.toMap().containsKey('id'), isFalse);
    });

    test('monthly expense totals and maps numeric values', () {
      final expense = MonthlyExpense.fromMap({
        'id': 1,
        'month': '2026-09',
        'salaries': 1000,
        'raw_materials': 200.5,
        'electricity': 50,
        'rent': 300,
        'other': 25,
      });

      expect(expense.total, 1575.5);
      expect(expense.toMap()['raw_materials'], 200.5);

      final noId = MonthlyExpense(
        month: '2026-10',
        salaries: 0,
        rawMaterials: 0,
        electricity: 0,
        rent: 0,
        other: 0,
      );
      expect(noId.total, 0);
      expect(noId.toMap()['id'], isNull);
    });
  });

  group('Group3A Vehicle and WorkshopSettings model coverage', () {
    test('vehicle parses numeric identifiers/dates and supports copyWith', () {
      final v = Vehicle.fromMap({
        'id': '3',
        'number': 123,
        'type': 'Sedan',
        'model': 'Civic',
        'client_id': 7.9,
        'client_name': 'Client',
        'notes': 'n',
        'created_at': '2026-09-01T00:00:00.000',
        'updated_at': '2026-09-02T00:00:00.000',
        'repair_count': '4',
        'last_received_date': '2026-09-03T00:00:00.000',
        'profile_image_path': 'car.jpg',
      });

      expect(v.id, 3);
      expect(v.clientId, 7);
      expect(v.repairCount, 4);
      expect(v.profileImagePath, 'car.jpg');

      final changed = v.copyWith(
        id: 4,
        number: 'N2',
        type: 'SUV',
        model: 'M2',
        clientId: 8,
        clientName: 'C2',
        notes: 'N',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 2),
        repairCount: 5,
        lastReceivedDate: DateTime.utc(2026, 1, 3),
        profileImagePath: 'new.jpg',
      );
      expect(changed.id, 4);
      expect(changed.repairCount, 5);

      final empty = Vehicle.fromMap({
        'id': null,
        'number': null,
        'type': null,
        'model': null,
        'created_at': 'bad',
        'repair_count': null,
      });
      expect(empty.id, isNull);
      expect(empty.createdAt, isNull);
      expect(empty.repairCount, 0);
    });

    test('workshop settings round-trip numeric strings and defaults', () {
      final settings = WorkshopSettings.fromMap({
        'id': '1',
        'workshopName': 'Yalla',
        'address': 'A',
        'city': 'Bethlehem',
        'phone1': '1',
        'phone2': '2',
        'email': 'e',
        'logoPath': 'l',
        'workStart': '08:30',
        'workEnd': '17:30',
        'dailyHours': '8.5',
        'breakMinutes': 30.0,
        'weekWorkdays': '1,2,3,4,5,6',
        'hourlyRate': '20',
        'overtimeRate': 30,
        'latePenalty': '5',
        'earlyLeavePenalty': 6,
      });

      expect(settings.id, 1);
      expect(settings.dailyHours, 8.5);
      expect(settings.breakMinutes, 30);
      expect(settings.hourlyRate, 20);
      expect(settings.toMap()['city'], 'Bethlehem');

      final changed = settings.copyWith(
        id: 2,
        workshopName: 'New',
        address: 'B',
        city: 'Ramallah',
        phone1: '3',
        phone2: '4',
        email: 'x',
        logoPath: 'logo',
        workStart: '09:00',
        workEnd: '18:00',
        dailyHours: 9,
        breakMinutes: 15,
        weekWorkdays: '1,2,3,4,5',
        hourlyRate: 21,
        overtimeRate: 31,
        latePenalty: 7,
        earlyLeavePenalty: 8,
      );
      expect(changed.id, 2);
      expect(changed.workshopName, 'New');

      final defaults = WorkshopSettings.defaults();
      expect(defaults.id, 1);
      expect(defaults.workStart, '09:00');
      expect(defaults.workEnd, '17:00');
      expect(defaults.dailyHours, 8);
      expect(defaults.breakMinutes, 0);

      final nulls = WorkshopSettings.fromMap({});
      expect(nulls.id, isNull);
      expect(nulls.dailyHours, isNull);
      expect(nulls.breakMinutes, isNull);
    });
  });
}
