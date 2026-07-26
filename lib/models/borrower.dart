import 'package:uuid/uuid.dart';

class Borrower {
  int? id;
  String syncId;
  String borrowerCode;
  String name;
  String phone;
  String? address;
  String? notes;
  int updatedAt;
  int createdAt;
  String? lastModifiedDevice;
  bool isDeleted;
  bool isDummy;
  bool isClosed;

  // Transient fields computed at query time
  double totalBalance;
  int loanCount;
  int loanAgeDays;
  String overdueStatus;

  String get displayBorrowerCode {
    if (borrowerCode.contains('_del_')) {
      return borrowerCode.split('_del_').first;
    }
    return borrowerCode;
  }

  Borrower({
    this.id,
    String? syncId,
    required this.borrowerCode,
    required this.name,
    required this.phone,
    this.address,
    this.notes,
    this.updatedAt = 0,
    this.createdAt = 0,
    this.lastModifiedDevice,
    this.isDeleted = false,
    this.isDummy = false,
    this.isClosed = false,
    this.totalBalance = 0.0,
    this.loanCount = 0,
    this.loanAgeDays = 0,
    this.overdueStatus = 'ACTIVE',
  }) : syncId = syncId ?? const Uuid().v4();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sync_id': syncId,
      'borrower_code': borrowerCode,
      'name': name,
      'phone': phone,
      'address': address,
      'notes': notes,
      'updated_at': updatedAt,
      'created_at': createdAt,
      'last_modified_device': lastModifiedDevice,
      'is_deleted': isDeleted ? 1 : 0,
      'is_dummy': isDummy ? 1 : 0,
      'is_closed': isClosed ? 1 : 0,
    };
  }

  factory Borrower.fromMap(Map<String, dynamic> map) {
    return Borrower(
      id: map['id'],
      syncId: map['sync_id'],
      borrowerCode: map['borrower_code'] ?? '',
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      address: map['address'],
      notes: map['notes'],
      updatedAt: map['updated_at'] ?? DateTime.now().millisecondsSinceEpoch,
      createdAt: map['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
      lastModifiedDevice: map['last_modified_device'],
      isDeleted: (map['is_deleted'] ?? 0) == 1,
      isDummy: (map['is_dummy'] ?? 0) == 1,
      isClosed: (map['is_closed'] ?? 0) == 1,
    );
  }
}

