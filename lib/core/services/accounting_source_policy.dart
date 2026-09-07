/// Stage 1 — canonical identity policy for accounting source documents.
///
/// Historical aliases are accepted for read/idempotency compatibility, while
/// every new posting is written using one canonical source name.
class AccountingSourcePolicy {
  AccountingSourcePolicy._();

  static String canonical(String source) {
    final value = source.trim().toUpperCase();
    switch (value) {
      case 'PURCHASE_INVOICE':
        return 'PURCHASE';
      case 'PURCHASE_INVOICE_REV':
        return 'PURCHASE_REV';
      default:
        return value;
    }
  }

  static List<String> aliasesFor(String source) {
    switch (canonical(source)) {
      case 'PURCHASE':
        return const ['PURCHASE', 'PURCHASE_INVOICE'];
      case 'PURCHASE_REV':
        return const ['PURCHASE_REV', 'PURCHASE_INVOICE_REV'];
      default:
        return <String>[canonical(source)];
    }
  }

  /// SQL expression used by integrity checks to collapse historical aliases.
  static String sqlCanonicalExpression([String column = 'source']) {
    return "CASE "
        "WHEN UPPER(TRIM($column))='PURCHASE_INVOICE' THEN 'PURCHASE' "
        "WHEN UPPER(TRIM($column))='PURCHASE_INVOICE_REV' THEN 'PURCHASE_REV' "
        "ELSE UPPER(TRIM($column)) END";
  }
}
