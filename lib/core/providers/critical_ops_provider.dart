import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/finance/services/collection_service.dart';

class CriticalOperation {
  final String repairId;
  final String vehicleNumber;
  final String paymentStatus;
  final DateTime dueDate;

  CriticalOperation({
    required this.repairId,
    required this.vehicleNumber,
    required this.paymentStatus,
    required this.dueDate,
  });
}

/// P12: critical collection operations use canonical GL AR plus the dedicated
/// financial due date instead of an intake-date shortcut.
final criticalOpsProvider =
    FutureProvider.autoDispose<List<CriticalOperation>>((ref) async {
  final items = await CollectionService.loadOpenDues();
  return items
      .where((item) => item.daysUntilDue <= 1)
      .map((item) => CriticalOperation(
            repairId: item.repairId,
            vehicleNumber: item.vehicleLabel,
            paymentStatus: item.isOverdue ? 'متأخر' : 'يستحق قريبًا',
            dueDate: item.dueDate,
          ))
      .toList();
});
