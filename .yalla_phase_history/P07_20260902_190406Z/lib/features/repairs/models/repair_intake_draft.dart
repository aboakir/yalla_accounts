class RepairIntakeDraft {
  const RepairIntakeDraft({
    this.clientId,
    required this.clientName,
    required this.clientType,
    required this.vehicleNumber,
    required this.vehicleType,
    required this.vehicleModel,
    required this.receivedDate,
    required this.odometer,
    required this.fuelLevel,
    required this.previousDamage,
    required this.photoPaths,
    required this.customerSignaturePath,
    this.notes = '',
  });

  final int? clientId;
  final String clientName;
  final String clientType;
  final String vehicleNumber;
  final String vehicleType;
  final String vehicleModel;
  final DateTime receivedDate;
  final int odometer;
  final int fuelLevel;
  final String previousDamage;
  final List<String> photoPaths;
  final String customerSignaturePath;
  final String notes;
}
