import 'package:yalla_accounts/features/cheques/models/cheque.dart';

enum ChequeMaturityClass {
  dueToday,
  dueSoon,
  postDated,
  overdue,
  collected,
  cleared,
  returned,
  cancelled,
  endorsed,
}

class ChequeMaturityService {
  ChequeMaturityService._();

  static ChequeMaturityClass classify(
    Cheque cheque, {
    DateTime? asOf,
    int dueSoonDays = 7,
  }) {
    switch (cheque.status) {
      case ChequeStatus.collected:
        return ChequeMaturityClass.collected;
      case ChequeStatus.cleared:
        return ChequeMaturityClass.cleared;
      case ChequeStatus.returned:
        return ChequeMaturityClass.returned;
      case ChequeStatus.cancelled:
        return ChequeMaturityClass.cancelled;
      case ChequeStatus.endorsed:
        return ChequeMaturityClass.endorsed;
      default:
        break;
    }

    final today = _dateOnly(asOf ?? DateTime.now());
    final due = _dateOnly(cheque.dueDate);
    final days = due.difference(today).inDays;

    if (days < 0) return ChequeMaturityClass.overdue;
    if (days == 0) return ChequeMaturityClass.dueToday;
    if (days <= dueSoonDays) return ChequeMaturityClass.dueSoon;
    return ChequeMaturityClass.postDated;
  }

  static bool isActionableDue(
    Cheque cheque, {
    DateTime? asOf,
    int dueSoonDays = 7,
  }) {
    final value = classify(cheque, asOf: asOf, dueSoonDays: dueSoonDays);
    return value == ChequeMaturityClass.dueToday ||
        value == ChequeMaturityClass.dueSoon ||
        value == ChequeMaturityClass.overdue;
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
