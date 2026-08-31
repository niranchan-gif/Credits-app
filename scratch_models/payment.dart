import 'package:uuid/uuid.dart';
import '../utils/date_parser.dart';

class Payment {
  int? id;
  String syncId;
  String? loanSyncId;
  int loanId;
  double amount;
  DateTime paymentDate;
  String? notes;
  int updatedAt;
  int createdAt;
  String? lastModifiedDevice;
  bool isDeleted;

  Payment({
    String? syncId,
    this.loanSyncId,
    this.id,
    required this.loanId,
    required this.amount,
    required this.paymentDate,
    this.notes,
    this.updatedAt = 0,
    this.createdAt = 0,
    this.lastModifiedDevice,
    this.isDeleted = false,
  }) : syncId = syncId ?? const Uuid().v4();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'loan_id': loanId,
      'amount': amount,
      'payment_date': paymentDate.toIso8601String(),
      'notes': notes,
      'updated_at': updatedAt,
      'created_at': createdAt,
      'last_modified_device': lastModifiedDevice,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  factory Payment.fromMap(Map<String, dynamic> map) {
    return Payment(
      id: map['id'],
      syncId: map['sync_id']?.toString() ?? '',
      loanSyncId: map['loan_sync_id']?.toString(),
      loanId: map['loan_id'],
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      paymentDate: DateParser.safeParse(map['payment_date']),
      notes: map['notes'],
      updatedAt: map['updated_at'] ?? DateTime.now().millisecondsSinceEpoch,
      createdAt: map['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
      lastModifiedDevice: map['last_modified_device'],
      isDeleted: (map['is_deleted'] ?? 0) == 1,
    );
  }
}
