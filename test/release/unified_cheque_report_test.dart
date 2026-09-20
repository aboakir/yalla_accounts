import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_pdf_report_service.dart';

Cheque sample(int id, String currency, double amount, String status) =>
    Cheque.fromMap({
      'id': id,
      'uuid': 'report-$id',
      'cheque_no': 'C-$id',
      'cheque_type': 'incoming',
      'direction': 'RECEIVED',
      'status': status,
      'drawer_name': 'طرف تجريبي',
      'bank_name': 'بنك تجريبي',
      'bank_branch': '',
      'currency': currency,
      'amount': amount,
      'issue_date': '2026-09-01',
      'due_date': '2026-09-20',
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final rows = [
    sample(1, 'USD', 10, 'received'),
    sample(2, 'JOD', 20, 'returned'),
    sample(3, 'USD', 5, 'returned')
  ];
  test('report filters preserve source rows and combine currency with status',
      () {
    final filtered = ChequePdfReportService.filterRows(rows,
        currency: ' usd ', status: ChequeStatus.returned);
    expect(filtered.map((c) => c.id), [3]);
    expect(rows.length, 3);
    expect(ChequePdfReportService.filterRows(rows), hasLength(3));
  });
  test('report totals never add different currencies into one amount', () {
    expect(ChequePdfReportService.totalsByCurrency(rows),
        {'USD': 15.0, 'JOD': 20.0});
  });
  test('PDF export accepts a filtered snapshot without opening a database',
      () async {
    final bytes = await ChequePdfReportService.generate(
      ChequePdfReportKind.returned,
      rowSnapshot: [rows.last],
    );
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });
  test('PDF export handles an empty result and a multipage snapshot', () async {
    final empty = await ChequePdfReportService.generate(
        ChequePdfReportKind.incoming,
        rowSnapshot: []);
    final many = await ChequePdfReportService.generate(
        ChequePdfReportKind.incoming,
        rowSnapshot: List.generate(
            80, (i) => sample(100 + i, 'JOD', i + 0.125, 'received')));
    expect(ascii.decode(empty.take(5).toList()), '%PDF-');
    expect(ascii.decode(many.take(5).toList()), '%PDF-');
    expect(many.length, greaterThan(empty.length));
  });
}
