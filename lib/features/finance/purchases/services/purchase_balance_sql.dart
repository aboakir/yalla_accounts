/// Posted ledger lines are authoritative; invoice caches and payment logs are not.
abstract final class PurchaseBalanceSql {
  static String paid(String invoiceId, {String? excludingVoucher}) {
    final exclusion = excludingVoucher == null
        ? ''
        : "AND NOT (UPPER(e.source) = 'VOUCHER' AND e.source_id = $excludingVoucher)";
    return '''(
      WITH target(id) AS (SELECT $invoiceId)
      SELECT COALESCE(SUM(CASE WHEN UPPER(e.source) IN ('PURCHASE', 'PURCHASE_INVOICE')
        THEN l.credit-l.debit ELSE l.debit-l.credit END), 0)
      FROM gl_lines l JOIN gl_entries e ON e.id = l.entry_id
      JOIN accounts a ON a.id=l.account_id
      WHERE (
        (COALESCE(l.invoice_id, CASE WHEN UPPER(e.source)='CHEQUE_STATUS' THEN
          (SELECT pl.invoice_id FROM gl_lines pl WHERE pl.cheque_id=l.cheque_id
            AND pl.invoice_id IS NOT NULL AND UPPER(pl.party_type)='SUPPLIER' LIMIT 1)
          END) = (SELECT id FROM target)
          AND UPPER(l.party_type) = 'SUPPLIER'
          AND UPPER(e.source) IN
            ('VOUCHER', 'PURCHASE_PAYMENT', 'PURCHASE_PAY', 'SUPPLIER_PAYMENT', 'PAYMENT', 'PAYMENT_OUT', 'CHEQUE_STATUS', 'CHEQUE_ENDORSE'))
        OR (e.source_id = (SELECT id FROM target)
          AND UPPER(e.source) IN ('PURCHASE', 'PURCHASE_INVOICE')
          AND a.code IN ('1000', '1010', '1020', '1030'))
      )
        AND e.reversal_of IS NULL
        AND NOT EXISTS (SELECT 1 FROM gl_entries rev WHERE rev.reversal_of = e.id)
        $exclusion
    )''';
  }
}
