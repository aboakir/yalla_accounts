import 'package:yalla_accounts/features/repairs/constants/repair_status.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';

enum RepairArchiveScope {
  active,
  archived,
  all,
}

extension RepairArchiveScopeUi on RepairArchiveScope {
  String get label {
    switch (this) {
      case RepairArchiveScope.active:
        return 'النشطة';
      case RepairArchiveScope.archived:
        return 'الأرشيف';
      case RepairArchiveScope.all:
        return 'الكل';
    }
  }
}

class RepairListFilter {
  const RepairListFilter({
    this.search = '',
    this.paymentStatus = 'الكل',
    this.beneficiaryType = 'الكل',
    this.vehicleStatus = 'الكل',
    this.archiveScope = RepairArchiveScope.all,
    this.from,
    this.to,
  });

  final String search;
  final String paymentStatus;
  final String beneficiaryType;
  final String vehicleStatus;
  final RepairArchiveScope archiveScope;
  final DateTime? from;
  final DateTime? to;

  bool matches(Repair repair) {
    final query = search.trim().toLowerCase();

    final matchesSearch = query.isEmpty ||
        <String>[
          repair.id,
          repair.invoiceNumber,
          repair.vehicleNumber,
          repair.vehicleType,
          repair.vehicleModel,
          repair.beneficiaryName,
          repair.beneficiaryType,
        ].any((value) => value.toLowerCase().contains(query));

    final normalizedPayment = normalizeOrNull(
      repair.paymentStatus,
      kPaymentStatuses,
    );

    final normalizedVehicle = normalizeValue(
          repair.vehicleStatus,
          kVehicleStatuses,
          aliases: kVehicleStatusAliases,
        ) ??
        repair.vehicleStatus;

    final matchesPayment =
        paymentStatus == 'الكل' || normalizedPayment == paymentStatus;

    final matchesBeneficiary = beneficiaryType == 'الكل' ||
        repair.beneficiaryType.trim() == beneficiaryType;

    final matchesVehicle =
        vehicleStatus == 'الكل' || normalizedVehicle == vehicleStatus;

    final matchesArchive = switch (archiveScope) {
      RepairArchiveScope.active => !repair.isArchived,
      RepairArchiveScope.archived => repair.isArchived,
      RepairArchiveScope.all => true,
    };

    final matchesDate = _matchesDate(repair.receivedDate);

    return matchesSearch &&
        matchesPayment &&
        matchesBeneficiary &&
        matchesVehicle &&
        matchesArchive &&
        matchesDate;
  }

  bool _matchesDate(DateTime date) {
    if (from != null && date.isBefore(from!)) return false;
    if (to != null && date.isAfter(to!)) return false;
    return true;
  }
}
