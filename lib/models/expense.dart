import 'package:uuid/uuid.dart';
import '../utils/date_parser.dart';

class Expense {
  int? id;
  String syncId;
  double amount;
  DateTime expenseDate;
  String category;
  String? notes;
  int updatedAt;
  int createdAt;
  String? lastModifiedDevice;
  bool isDeleted;

  Expense({
    this.id,
    String? syncId,
    required this.amount,
    required this.expenseDate,
    required this.category,
    this.notes,
    this.updatedAt = 0,
    this.createdAt = 0,
    this.lastModifiedDevice,
    this.isDeleted = false,
  }) : syncId = syncId ?? const Uuid().v4();

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'sync_id': syncId,
      'amount': amount,
      'expense_date': expenseDate.toIso8601String(),
      'category': category,
      'notes': notes,
      'updated_at': updatedAt,
      'created_at': createdAt,
      'last_modified_device': lastModifiedDevice,
      'is_deleted': isDeleted ? 1 : 0,
    };
    if (id != null) map['id'] = id;
    return map;
  }

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'],
      syncId: map['sync_id'],
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      expenseDate: DateParser.safeParse(map['expense_date']),
      category: map['category'] ?? 'General',
      notes: map['notes'],
      updatedAt: map['updated_at'] ?? DateTime.now().millisecondsSinceEpoch,
      createdAt: map['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
      lastModifiedDevice: map['last_modified_device'],
      isDeleted: (map['is_deleted'] ?? 0) == 1,
    );
  }
}

