import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/features/insurance_agent/quotes/screens/insurance_quotes_screen.dart';
import 'package:yalla_accounts/features/insurance_agent/quotes/services/insurance_quote_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  InsuranceQuoteSummary draftQuote() => InsuranceQuoteSummary(
        id: 'quote-draft',
        quoteNumber: 'Q-001',
        partyName: 'Draft Customer',
        status: 'DRAFT',
        requestedAt: DateTime(2026, 9, 22),
        itemCount: 2,
      );

  InsuranceQuoteSummary acceptedQuote() => InsuranceQuoteSummary(
        id: 'quote-accepted',
        quoteNumber: 'Q-002',
        partyName: 'Accepted Customer',
        status: 'ACCEPTED',
        requestedAt: DateTime(2026, 9, 22),
        itemCount: 1,
        acceptedItemId: 'item-a',
      );

  List<InsuranceQuoteItemRecord> items() => const [
        InsuranceQuoteItemRecord(
          id: 'item-a',
          companyId: 1,
          companyName: 'Company A',
          productId: 'product-a',
          productName: 'Comprehensive',
          status: 'OFFERED',
          purchasePrice: 2000,
          salePrice: 2400,
          finalPrice: 2400,
          discount: 0,
          commissionRate: 10,
        ),
        InsuranceQuoteItemRecord(
          id: 'item-b',
          companyId: 2,
          companyName: 'Company B',
          status: 'OFFERED',
          purchasePrice: 2050,
          salePrice: 2450,
          finalPrice: 2450,
          discount: 0,
          commissionRate: 8,
        ),
      ];

  testWidgets('quote center lists offers and accepts a selected company offer',
      (tester) async {
    String? acceptedQuoteId;
    String? acceptedItemId;

    await tester.pumpWidget(
      MaterialApp(
        home: InsuranceQuotesScreen(
          loader: () async => [draftQuote()],
          itemLoader: (_) async => items(),
          acceptor: (quoteId, itemId) async {
            acceptedQuoteId = quoteId;
            acceptedItemId = itemId;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('insuranceQuotesScreen')), findsOneWidget);
    expect(find.byKey(const Key('quoteCard-quote-draft')), findsOneWidget);

    await tester.tap(find.byKey(const Key('quoteCard-quote-draft')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quoteItem-item-a')), findsOneWidget);
    expect(find.byKey(const Key('quoteItem-item-b')), findsOneWidget);

    await tester.tap(find.byKey(const Key('acceptQuoteItem-item-a')));
    await tester.pumpAndSettle();
    expect(acceptedQuoteId, 'quote-draft');
    expect(acceptedItemId, 'item-a');
  });

  testWidgets('accepted quote can issue a policy through injected issuer',
      (tester) async {
    String? issuedQuoteId;
    String? policyNumber;
    DateTime? startDate;
    DateTime? endDate;

    await tester.pumpWidget(
      MaterialApp(
        home: InsuranceQuotesScreen(
          loader: () async => [acceptedQuote()],
          itemLoader: (_) async => [items().first],
          issuer: (quoteId, number, start, end) async {
            issuedQuoteId = quoteId;
            policyNumber = number;
            startDate = start;
            endDate = end;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('issueQuote-quote-accepted')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('quotePolicyNumber')),
      'POL-ISSUED-001',
    );
    await tester.tap(find.byKey(const Key('confirmQuoteIssue')));
    await tester.pumpAndSettle();

    expect(issuedQuoteId, 'quote-accepted');
    expect(policyNumber, 'POL-ISSUED-001');
    expect(startDate, isNotNull);
    expect(endDate, isNotNull);
    expect(endDate!.isBefore(startDate!), isFalse);
  });
}
