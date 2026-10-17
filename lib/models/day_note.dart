import 'package:uuid/uuid.dart';

class DayNote {
  int? id;
  String syncId;
  String date; // 'YYYY-MM-DD'
  String notes;
  int updatedAt;
  int createdAt;
  String? lastModifiedDevice;
  bool isDeleted;

  DayNote({
    this.id,
    String? syncId,
    required this.date,
    required this.notes,
    int? updatedAt,
    int? createdAt,
    this.lastModifiedDevice,
    this.isDeleted = false,
  })  : syncId = syncId ?? const Uuid().v4(),
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch,
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sync_id': syncId,
      'date': date,
      'notes': notes,
      'updated_at': updatedAt,
      'created_at': createdAt,
      'last_modified_device': lastModifiedDevice,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  factory DayNote.fromMap(Map<String, dynamic> map) {
    return DayNote(
      id: map['id'] as int?,
      syncId: map['sync_id'] as String? ?? const Uuid().v4(),
      date: map['date'] as String,
      notes: map['notes'] as String? ?? '',
      updatedAt: map['updated_at'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      createdAt: map['created_at'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      lastModifiedDevice: map['last_modified_device'] as String?,
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
    );
  }
}
