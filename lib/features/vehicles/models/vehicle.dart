class Vehicle {
  const Vehicle({
    this.id,
    required this.number,
    required this.type,
    required this.model,
    this.clientId,
    this.ownerPartyUuid,
    this.clientName = '',
    this.notes = '',
    this.createdAt,
    this.updatedAt,
    this.repairCount = 0,
    this.lastReceivedDate,
    this.profileImagePath,
    this.isActive = true,
  });

  final int? id;
  final String number;
  final String type;
  final String model;
  final int? clientId;
  final String? ownerPartyUuid;
  final String clientName;
  final String notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int repairCount;
  final DateTime? lastReceivedDate;
  final String? profileImagePath;
  final bool isActive;

  factory Vehicle.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(Object? value) {
      if (value == null) return null;
      return DateTime.tryParse(value.toString());
    }

    int? parseInt(Object? value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString());
    }

    return Vehicle(
      id: parseInt(map['id']),
      number: (map['number'] ?? '').toString(),
      type: (map['type'] ?? '').toString(),
      model: (map['model'] ?? '').toString(),
      clientId: parseInt(map['client_id']),
      ownerPartyUuid: map['owner_party_uuid']?.toString(),
      clientName: (map['client_name'] ?? '').toString(),
      notes: (map['notes'] ?? '').toString(),
      createdAt: parseDate(map['created_at']),
      updatedAt: parseDate(map['updated_at']),
      repairCount: parseInt(map['repair_count']) ?? 0,
      lastReceivedDate: parseDate(map['last_received_date']),
      profileImagePath: map['profile_image_path']?.toString(),
      isActive: map['is_active'] == null || map['is_active'] == 1,
    );
  }

  Vehicle copyWith({
    int? id,
    String? number,
    String? type,
    String? model,
    int? clientId,
    String? ownerPartyUuid,
    String? clientName,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? repairCount,
    DateTime? lastReceivedDate,
    String? profileImagePath,
    bool? isActive,
  }) {
    return Vehicle(
      id: id ?? this.id,
      number: number ?? this.number,
      type: type ?? this.type,
      model: model ?? this.model,
      clientId: clientId ?? this.clientId,
      ownerPartyUuid: ownerPartyUuid ?? this.ownerPartyUuid,
      clientName: clientName ?? this.clientName,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      repairCount: repairCount ?? this.repairCount,
      lastReceivedDate: lastReceivedDate ?? this.lastReceivedDate,
      profileImagePath: profileImagePath ?? this.profileImagePath,
      isActive: isActive ?? this.isActive,
    );
  }
}
