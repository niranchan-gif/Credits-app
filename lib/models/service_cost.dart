import '../utils/date_parser.dart';

class ServiceCost {
  int? id;
  double amount;
  String? description;
  DateTime dateCreated;
  String? createdBy;
  int timestamp;
  bool isDeleted;

  ServiceCost({
    this.id,
    required this.amount,
    this.description,
    required this.dateCreated,
    this.createdBy,
    required this.timestamp,
    this.isDeleted = false,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
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

