import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/features/vouchers/pdf/payment_voucher_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('payment voucher PDF supports Arabic Latin currency and symbols',
      () async {
    final bytes = await PaymentVoucherPdf.generate(
      voucherId: 'PV-C-JOD-001',
      date: DateTime(2026, 9, 23),
      expenseType: 'مصاريف تشغيل — Parts C',
      amount: 1234.50,
      method: 'cheque',
      partyName: 'مورد C — Bethlehem',
      notes: 'دفعة JOD — اختبار عربي English',
      glEntryId: 42,
      chequeNumber: 'C-JOD-001',
      chequeBank: 'Bank of Palestine',
      chequeBranch: 'Bethlehem — بيت لحم',
      chequePayee: 'المورد C',
      chequeCurrency: 'JOD',
      chequeStatus: 'مستحق — Due',
      chequeIssueDate: DateTime(2026, 9, 23),
      chequeDueDate: DateTime(2026, 10, 23),
    );

    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(bytes.length, greaterThan(1000));
  });
}
