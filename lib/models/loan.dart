class Loan {
  int? id;
  int borrowerId;
  double loanAmount;
  double interestAmount;
  DateTime loanDate;
  int? installmentDays;
  DateTime? endDate;
  String status; // 'active', 'cleared'
  String? notes;

  Loan({
    this.id,
    required this.borrowerId,
    required this.loanAmount,
    required this.interestAmount,
    required this.loanDate,
    this.installmentDays,
    this.endDate,
    this.status = 'active',
    this.notes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'borrower_id': borrowerId,
      'loan_amount': loanAmount,
      'interest_amount': interestAmount,
      'loan_date': loanDate.toIso8601String(),
      'installment_days': installmentDays,
      'end_date': endDate?.toIso8601String(),
      'status': status,
      'notes': notes,
    };
  }

  factory Loan.fromMap(Map<String, dynamic> map) {
    return Loan(
      id: map['id'],
      borrowerId: map['borrower_id'],
      loanAmount: (map['loan_amount'] as num).toDouble(),
      interestAmount: (map['interest_amount'] as num).toDouble(),
      loanDate: DateTime.parse(map['loan_date']),
      installmentDays: map['installment_days'],
      endDate: map['end_date'] != null ? DateTime.parse(map['end_date']) : null,
      status: map['status'] ?? 'active',
      notes: map['notes'],
    );
  }

  double calculateInterest() => interestAmount;
  double totalDue() => loanAmount + interestAmount;
}
