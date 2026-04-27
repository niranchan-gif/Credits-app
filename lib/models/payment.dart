class Payment {
  int? id;
  int loanId;
  double amount;
  DateTime paymentDate;
  String? notes;

  Payment({
    this.id,
    required this.loanId,
    required this.amount,
    required this.paymentDate,
    this.notes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'loan_id': loanId,
      'amount': amount,
      'payment_date': paymentDate.toIso8601String(),
      'notes': notes,
    };
  }

  factory Payment.fromMap(Map<String, dynamic> map) {
    return Payment(
      id: map['id'],
      loanId: map['loan_id'],
      amount: (map['amount'] as num).toDouble(),
      paymentDate: DateTime.parse(map['payment_date']),
      notes: map['notes'],
    );
  }
}