import '../utils/date_parser.dart';

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
  int updatedAt;
  int createdAt;
  String? lastModifiedDevice;
  bool isDeleted;

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
    this.updatedAt = 0,
    this.createdAt = 0,
    this.lastModifiedDevice,
    this.isDeleted = false,
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
      'updated_at': updatedAt,
      'created_at': createdAt,
      'last_modified_device': lastModifiedDevice,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  factory Loan.fromMap(Map<String, dynamic> map) {
    return Loan(
      id: map['id'],
      borrowerId: map['borrower_id'],
      loanAmount: (map['loan_amount'] as num?)?.toDouble() ?? 0.0,
      interestAmount: (map['interest_amount'] as num?)?.toDouble() ?? 0.0,
      loanDate: DateParser.safeParse(map['loan_date']),
      installmentDays: map['installment_days'],
      endDate: map['end_date'] != null ? DateParser.safeParse(map['end_date']) : null,
      status: map['status'] ?? 'active',
      notes: map['notes'],
      updatedAt: map['updated_at'] ?? DateTime.now().millisecondsSinceEpoch,
      createdAt: map['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
      lastModifiedDevice: map['last_modified_device'],
      isDeleted: (map['is_deleted'] ?? 0) == 1,
    );
  }

  double calculateInterest() => interestAmount;
  double totalDue() => loanAmount + interestAmount;
}

