import 'package:flutter/material.dart';

import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/screens/cheque_details_screen.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_service.dart';
import 'package:yalla_accounts/features/cheques/widgets/cheque_card.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

class ChequeFilteredScreenBody extends StatefulWidget {
  const ChequeFilteredScreenBody({
    super.key,
    required this.title,
    required this.currentRoute,
    required this.emptyText,
    required this.predicate,
  });

  final String title;
  final String currentRoute;
  final String emptyText;
  final bool Function(Cheque) predicate;

  @override
  State<ChequeFilteredScreenBody> createState() =>
      _ChequeFilteredScreenBodyState();
}

class _ChequeFilteredScreenBodyState extends State<ChequeFilteredScreenBody> {
  final _service = ChequeService();
  late Future<List<Cheque>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _service.fetchFiltered().then(
          (rows) => rows.where(widget.predicate).toList(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: () => setState(_reload),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      drawer: desktop ? null : YallaSidebar(currentRoute: widget.currentRoute),
      body: AdaptiveRow(
        children: [
          if (desktop) YallaSidebar(currentRoute: widget.currentRoute),
          Expanded(
            child: FutureBuilder<List<Cheque>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                      child: Text('تعذر تحميل الشيكات: ${snap.error}'));
                }
                final rows = snap.data ?? const <Cheque>[];
                if (rows.isEmpty) {
                  return Center(child: Text(widget.emptyText));
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: rows.length,
                  itemBuilder: (_, i) => ChequeCard(
                    cheque: rows[i],
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChequeDetailsScreen(cheque: rows[i]),
                        ),
                      );
                      if (mounted) setState(_reload);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
