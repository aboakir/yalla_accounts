class InsuranceInvoice {
  final int? id;
  final String invoiceNumber;
  final String clientName;
  final String insuranceCompany;
  final double amount;
  final DateTime date;
  final String status; // مثل: "معلق", "مدفوع", "ملغى"

  InsuranceInvoice({
    this.id,
    required this.invoiceNumber,
    required this.clientName,
    required this.insuranceCompany,
    required this.amount,
    required this.date,
    required this.status,
  });

  factory InsuranceInvoice.fromMap(Map<String, dynamic> map) {
    return InsuranceInvoice(
      id: map['id'] as int?,
      invoiceNumber: map['invoice_number'] as String,
      clientName: map['client_name'] as String,
      insuranceCompany: map['insurance_company'] as String,
      amount: map['amount'] is int
          ? (map['amount'] as int).toDouble()
          : map['amount'] as double,
      date: DateTime.parse(map['date'] as String),
      status: map['status'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'invoice_number': invoiceNumber,
      'client_name': clientName,
      'insurance_company': insuranceCompany,
      'amount': amount,
      'date': date.toIso8601String(),
      'status': status,
    };
  }
}
