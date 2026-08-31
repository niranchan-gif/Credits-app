import 'package:uuid/uuid.dart';
import '../utils/date_parser.dart';

class Payment {
  int? id;
  String syncId;
  int loanId;
  String? loanSyncId;
  double amount;
  DateTime paymentDate;
  String? notes;
  int updatedAt;
  int createdAt;
  String? lastModifiedDevice;
  bool isDeleted;

  Payment({
    this.id,
    String? syncId,
    required this.loanId,
    this.loanSyncId,
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
      'sync_id': syncId,
      'loan_sync_id': loanSyncId,
      'id': id,
      'sync_id': syncId,
      'loan_id': loanId,
      'loan_sync_id': loanSyncId,
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
      syncId: map['sync_id'],
      loanId: map['loan_id'],
      loanSyncId: map['loan_sync_id'],
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
