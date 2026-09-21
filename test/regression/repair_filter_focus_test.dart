import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/features/repairs/models/repair_list_filter.dart';
import 'package:yalla_accounts/features/repairs/widgets/repair_filter_bar.dart';

void main() {
  testWidgets('repair search keeps focus while live filtering rebuilds parent',
      (tester) async {
    var query = '';

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: StatefulBuilder(
            builder: (context, setState) => SizedBox(
              width: 1200,
              child: RepairFilterBar(
                searchQuery: query,
                onSearchChanged: (value) => setState(() => query = value),
                onPaymentStatusChanged: (_) {},
                onTypeChanged: (_) {},
                onVehicleStatusChanged: (_) {},
                onArchiveScopeChanged: (_) {},
                onReset: () => setState(() => query = ''),
                selectedArchiveScope: RepairArchiveScope.all,
              ),
            ),
          ),
        ),
      ),
    );

    final searchField = find.byType(TextFormField).first;
    await tester.tap(searchField);
    await tester.pump();

    await tester.enterText(searchField, 'ر');
    await tester.pump();
    var editable = tester.widget<EditableText>(find.byType(EditableText).first);
    expect(editable.focusNode.hasFocus, isTrue);
    expect(query, 'ر');

    await tester.enterText(searchField, 'رامي');
    await tester.pump();
    editable = tester.widget<EditableText>(find.byType(EditableText).first);
    expect(editable.focusNode.hasFocus, isTrue);
    expect(editable.controller.text, 'رامي');
    expect(query, 'رامي');
  });
}
