import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/features/parties/services/party_financial_service.dart';
import 'package:yalla_accounts/features/parties/services/party_report_service.dart';
import 'package:yalla_accounts/features/parties/pdf/party_detailed_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('detailed PDF paginates long Arabic invoice tables', () async {
    final report = DetailedPartyReport(
        const PartyLedgerStatement(
            partyId: '1',
            displayName: 'جهة اختبار',
            role: 'COMBINED',
            openingBalance: 0,
            closingBalance: 100,
            lines: []),
        [
          PartyReportDocument(
              'شراء',
              {
                'id': 'P-1',
                'date': '2026-09-08',
                'subtotal': 100,
                'vat': 0,
                'amount_total': 100
              },
              List.generate(
                  160,
                  (i) => {
                        'item_name': 'قطعة اختبار رقم $i',
                        'qty': 1,
                        'unit_price': 1,
                        'total': 1,
                        'note': 'تفصيل مادة خام للورشة'
                      }),
              {})
        ],
        [],
        {});
    final bytes =
        await PartyDetailedPdf.generate(report, workshopHeader: false);
    expect(bytes.take(4), [37, 80, 68, 70]);
    expect(bytes.length, greaterThan(1000));
    expect(PartyDetailedPdf.date('2026-09-08'), '2026-09-08');
    expect(PartyDetailedPdf.date(null), 'غير مسجل');
  });
}
