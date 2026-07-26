import 'package:uuid/uuid.dart';
import '../utils/date_parser.dart';

class ServiceCost {
  int? id;
  String syncId;
  double amount;
  String? description;
  DateTime dateCreated;
  String? createdBy;
  int timestamp;
  bool isDeleted;

  ServiceCost({
    this.id,
    String? syncId,
    required this.amount,
    this.description,
    required this.dateCreated,
    this.createdBy,
    required this.timestamp,
    this.isDeleted = false,
  }) : syncId = syncId ?? const Uuid().v4();

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'sync_id': syncId,
      'amount': amount,
      'description': description,
      'dateCreated': dateCreated.toIso8601String(),
      'createdBy': createdBy,
      'timestamp': timestamp,
      'is_deleted': isDeleted ? 1 : 0,
    };
    if (id != null) map['id'] = id;
    return map;
  }

  factory ServiceCost.fromMap(Map<String, dynamic> map) {
    return ServiceCost(
      id: map['id'],
      syncId: map['sync_id'],
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      description: map['description'],
      dateCreated: map['dateCreated'] != null
          ? DateParser.safeParse(map['dateCreated'])
          : DateTime.now(),
      createdBy: map['createdBy'],
      timestamp: map['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
      isDeleted: (map['is_deleted'] ?? 0) == 1,
    );
  }
}

