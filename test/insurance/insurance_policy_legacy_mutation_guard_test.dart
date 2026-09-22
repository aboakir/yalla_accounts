import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/screens/edit_policy_screen.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/utils/policy_legacy_mutation_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  group('canonical policy legacy-mutation guard', () {
    test('recognizes canonical and partial posting evidence', () {
      expect(
        PolicyLegacyMutationGuard.hasCanonicalPostingEvidence({
          'posting_status': 'DRAFT',
        }),
        isFalse,
      );
      expect(
        PolicyLegacyMutationGuard.hasCanonicalPostingEvidence({
          'operation_id': 'POLICY:1',
          'posting_status': 'DRAFT',
        }),
        isTrue,
      );
      expect(
        PolicyLegacyMutationGuard.hasCanonicalPostingEvidence({
          'posting_status': 'PENDING',
        }),
        isTrue,
      );
      expect(
        PolicyLegacyMutationGuard.hasCanonicalPostingEvidence({
          'posting_status': 'POSTED',
        }),
        isTrue,
      );
      expect(
        PolicyLegacyMutationGuard.hasCanonicalPostingEvidence({
          'gl_entry_id': 42,
          'posting_status': 'DRAFT',
        }),
        isTrue,
      );
    });

    test('fresh DB check blocks stale row before update or hard delete',
        () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('''
        CREATE TABLE insurance_policies(
          id TEXT PRIMARY KEY,
          operation_id TEXT,
          gl_entry_id INTEGER,
          posting_status TEXT NOT NULL DEFAULT 'DRAFT',
          notes TEXT
        )
      ''');
      await db.insert('insurance_policies', {
        'id': 'posted-policy',
        'operation_id': 'POST-OP-1',
        'gl_entry_id': 77,
        'posting_status': 'POSTED',
        'notes': 'canonical snapshot',
      });

      final staleLegacyRow = <String, dynamic>{
        'id': 'posted-policy',
        'posting_status': 'DRAFT',
      };

      await expectLater(
        db.transaction((txn) async {
          final current = await PolicyLegacyMutationGuard.requireUnposted(
            txn,
            staleLegacyRow,
          );
          final locator = PolicyLegacyMutationGuard.locator(current)!;
          return txn.delete(
            'insurance_policies',
            where: '${locator.column}=?',
            whereArgs: [locator.value],
          );
        }),
        throwsA(isA<PolicyLegacyMutationBlocked>()),
      );

      expect(
        await db.query(
          'insurance_policies',
          where: 'id=?',
          whereArgs: ['posted-policy'],
        ),
        hasLength(1),
      );

      await expectLater(
        db.transaction((txn) async {
          final current = await PolicyLegacyMutationGuard.requireUnposted(
            txn,
            staleLegacyRow,
          );
          final locator = PolicyLegacyMutationGuard.locator(current)!;
          return txn.update(
            'insurance_policies',
            {'notes': 'legacy overwrite'},
            where: '${locator.column}=?',
            whereArgs: [locator.value],
          );
        }),
        throwsA(isA<PolicyLegacyMutationBlocked>()),
      );

      final unchanged = await db.query(
        'insurance_policies',
        where: 'id=?',
        whereArgs: ['posted-policy'],
      );
      expect(unchanged.single['notes'], 'canonical snapshot');
    });

    test('fresh DB check preserves legacy unposted mutation behavior',
        () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('''
        CREATE TABLE insurance_policies(
          id TEXT PRIMARY KEY,
          operation_id TEXT,
          gl_entry_id INTEGER,
          posting_status TEXT NOT NULL DEFAULT 'DRAFT'
        )
      ''');
      await db.insert('insurance_policies', {
        'id': 'legacy-draft',
        'posting_status': 'DRAFT',
      });

      final current = await PolicyLegacyMutationGuard.requireUnposted(
        db,
        {'id': 'legacy-draft'},
      );

      expect(current['id'], 'legacy-draft');
      expect(
        PolicyLegacyMutationGuard.hasCanonicalPostingEvidence(current),
        isFalse,
      );
    });

    testWidgets('posted policy edit screen is visibly read-only',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: EditPolicyScreen(
            row: _policyRow(
              operationId: 'POST-OP-UI',
              postingStatus: 'POSTED',
              glEntryId: 88,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('canonical-policy-mutation-warning')),
        findsOneWidget,
      );
      expect(
        find.text(PolicyLegacyMutationGuard.blockedMessage),
        findsOneWidget,
      );

      final appBarSave = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) =>
              widget is IconButton &&
              widget.tooltip == 'التعديل المباشر غير متاح',
        ),
      );
      expect(appBarSave.onPressed, isNull);

      final firstField = tester.widget<TextFormField>(
        find.byType(TextFormField).first,
      );
      expect(firstField.enabled, isFalse);

      await tester.scrollUntilVisible(
        find.text('حفظ التعديلات'),
        500,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final saveButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'حفظ التعديلات'),
      );
      expect(saveButton.onPressed, isNull);
    });

    testWidgets('legacy draft edit screen remains editable', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: EditPolicyScreen(
            row: _policyRow(postingStatus: 'DRAFT'),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('canonical-policy-mutation-warning')),
        findsNothing,
      );

      final appBarSave = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'حفظ',
        ),
      );
      expect(appBarSave.onPressed, isNotNull);

      final firstField = tester.widget<TextFormField>(
        find.byType(TextFormField).first,
      );
      expect(firstField.enabled, isTrue);

      await tester.scrollUntilVisible(
        find.text('حفظ التعديلات'),
        500,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final saveButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'حفظ التعديلات'),
      );
      expect(saveButton.onPressed, isNotNull);
    });
  });
}

Map<String, dynamic> _policyRow({
  String? operationId,
  required String postingStatus,
  int? glEntryId,
}) {
  return {
    'id': 'policy-ui',
    'vehicle_plate': '12-345-67',
    'insured_name': 'عميل تجريبي',
    'insured_phone': '0599000000',
    'company_name': 'شركة التأمين',
    'document_type': 'شامل',
    'start_date': '2026-09-01',
    'end_date': '2027-08-31',
    'operation_id': operationId,
    'posting_status': postingStatus,
    'gl_entry_id': glEntryId,
  };
}
