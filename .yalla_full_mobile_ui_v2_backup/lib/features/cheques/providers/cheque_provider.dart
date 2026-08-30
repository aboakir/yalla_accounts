// -----------------------------------------------------------------------------
// 📁 lib/features/cheques/providers/cheque_provider.dart
//
// ChequeProvider — FINAL D (ENDORSEMENT-READY + CLEAN ARCH)
// -----------------------------------------------------------------------------
// • متوافق بالكامل مع ChequeService + ChequeEndorsementService
// • CRUD + Filtering
// • وظيفة endorseCheque مدمجة داخل المزود الرسمي
// • refresh تلقائي بعد كل عملية
// • بدون أي دوال ناقصة أو Imports وهمية
// -----------------------------------------------------------------------------

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_service.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_endorsement_service.dart';

// -----------------------------------------------------------------------------
// SERVICE PROVIDER
// -----------------------------------------------------------------------------
final chequeServiceProvider = Provider<ChequeService>((ref) {
  return ChequeService();
});

// -----------------------------------------------------------------------------
// FILTER MODEL
// -----------------------------------------------------------------------------
class ChequeFilter {
  final String? search;
  final ChequeStatus? status;
  final ChequeType? type;

  final DateTime? issueFrom;
  final DateTime? issueTo;

  final DateTime? dueFrom;
  final DateTime? dueTo;

  const ChequeFilter({
    this.search,
    this.status,
    this.type,
    this.issueFrom,
    this.issueTo,
    this.dueFrom,
    this.dueTo,
  });

  ChequeFilter copyWith({
    String? search,
    ChequeStatus? status,
    ChequeType? type,
    DateTime? issueFrom,
    DateTime? issueTo,
    DateTime? dueFrom,
    DateTime? dueTo,
  }) {
    return ChequeFilter(
      search: search ?? this.search,
      status: status ?? this.status,
      type: type ?? this.type,
      issueFrom: issueFrom ?? this.issueFrom,
      issueTo: issueTo ?? this.issueTo,
      dueFrom: dueFrom ?? this.dueFrom,
      dueTo: dueTo ?? this.dueTo,
    );
  }
}

// مزود الفلتر الرئيسي
final chequeFilterProvider =
    StateProvider<ChequeFilter>((ref) => const ChequeFilter());

// -----------------------------------------------------------------------------
// STATE NOTIFIER
// -----------------------------------------------------------------------------
class ChequeNotifier extends StateNotifier<List<Cheque>> {
  final ChequeService svc;
  ChequeFilter lastFilter = const ChequeFilter();

  ChequeNotifier(this.svc) : super([]) {
    loadFiltered(lastFilter);
  }

  // ---------------------------------------------------------------------------
  // LOAD FILTERED
  // ---------------------------------------------------------------------------
  Future<void> loadFiltered(ChequeFilter f) async {
    final rows = await svc.fetchFiltered(
      search: f.search,
      status: f.status,
      type: f.type,
      issueFrom: f.issueFrom,
      issueTo: f.issueTo,
      dueFrom: f.dueFrom,
      dueTo: f.dueTo,
    );

    lastFilter = f;
    state = rows;
  }

  void syncFilter(ChequeFilter f) {
    lastFilter = f;
    loadFiltered(f);
  }

  // ---------------------------------------------------------------------------
  // ADD
  // ---------------------------------------------------------------------------
  Future<void> addCheque(Cheque c) async {
    await svc.addCheque(c);
    await loadFiltered(lastFilter);
  }

  // ---------------------------------------------------------------------------
  // UPDATE
  // ---------------------------------------------------------------------------
  Future<void> updateCheque(Cheque c) async {
    await svc.updateCheque(c);
    await loadFiltered(lastFilter);
  }

  // ---------------------------------------------------------------------------
  // DELETE
  // ---------------------------------------------------------------------------
  Future<void> deleteCheque(int id) async {
    await svc.deleteCheque(id);
    await loadFiltered(lastFilter);
  }

  // ---------------------------------------------------------------------------
  // GET BY ID
  // ---------------------------------------------------------------------------
  Future<Cheque?> getById(int id) async {
    return await svc.getById(id);
  }

  // ---------------------------------------------------------------------------
  // ENDORSE CHEQUE — الوظيفة الجديدة الرسمية
  // ---------------------------------------------------------------------------
  Future<Cheque> endorseCheque({
    required Cheque cheque,
    required String supplierPid,
    required DateTime endorsementDate,
  }) async {
    final updated = await ChequeEndorsementService.endorseCheque(
      cheque: cheque,
      supplierPid: supplierPid,
      endorsementDate: endorsementDate,
    );

    await loadFiltered(lastFilter);
    return updated;
  }
}

// -----------------------------------------------------------------------------
// PROVIDER
// -----------------------------------------------------------------------------
final chequeProvider =
    StateNotifierProvider<ChequeNotifier, List<Cheque>>((ref) {
  final svc = ref.read(chequeServiceProvider);
  return ChequeNotifier(svc);
});

// -----------------------------------------------------------------------------
// AUTO SYNC — أي تغيير في الفلاتر يعطي Refresh
// -----------------------------------------------------------------------------
final chequeFilterSyncProvider = Provider<void>((ref) {
  final f = ref.watch(chequeFilterProvider);
  ref.read(chequeProvider.notifier).syncFilter(f);
});
