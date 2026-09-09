/// Shared validation for every ledger writer, including legacy entry points.
abstract final class GlPostingPolicy {
  static List<Map<String, Object?>> normalize(
      List<Map<String, Object?>> lines) {
    if (lines.length < 2) {
      throw ArgumentError('A journal requires at least two lines');
    }
    var debits = 0;
    var credits = 0;
    int cents(Object? raw) {
      if (raw == null) return 0;
      if (raw is! num || !raw.isFinite || raw < 0) {
        throw ArgumentError(
            'Debit and credit must be finite non-negative numbers');
      }
      final scaled = raw.toDouble() * 100;
      if (!scaled.isFinite ||
          scaled.abs() > 9007199254740991 ||
          (scaled - scaled.round()).abs() > 0.000001) {
        throw ArgumentError('Amounts must have at most two decimal places');
      }
      return scaled.round();
    }

    final result = <Map<String, Object?>>[];
    for (final line in lines) {
      final account = int.tryParse('${line['account_id']}');
      if (account == null || account <= 0) {
        throw ArgumentError('Invalid account ID');
      }
      final debit = cents(line['debit']);
      final credit = cents(line['credit']);
      if (debit > 0 && credit > 0) {
        throw ArgumentError('A line cannot be both debit and credit');
      }
      debits += debit;
      credits += credit;
      result.add({
        ...line,
        'account_id': account,
        'debit': debit / 100,
        'credit': credit / 100
      });
    }
    if (debits == 0 || debits != credits) {
      throw StateError(
          'القيد غير متوازن أو بلا قيمة: المدين $debits، الدائن $credits (أجزاء العملة)');
    }
    return result;
  }

  static String reference(
      String source, String id, String? ref, String? number) {
    for (final value in [ref, number]) {
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return '$source:$id';
  }

  static String description(String source, String ref, String? note) {
    if (note != null && note.trim().isNotEmpty) return note.trim();
    const labels = {
      'PURCHASE': 'فاتورة مشتريات',
      'INVOICE': 'فاتورة بيع',
      'VOUCHER': 'سند صرف',
      'PAYMENT': 'سند قبض',
      'PAYMENT_OUT': 'دفعة صادرة',
      'CHEQUE_STATUS': 'حركة شيك',
      'REPAIR_VALUE_ADJ': 'تعديل قيمة إصلاح',
      'PURCHASE_PAYMENT': 'سداد مشتريات',
      'SUPPLIER_PAYMENT': 'سداد مورد'
    };
    return '${labels[source] ?? source} — $ref';
  }
}
