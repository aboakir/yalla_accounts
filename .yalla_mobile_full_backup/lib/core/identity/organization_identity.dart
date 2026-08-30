class OrganizationIdentity {
  const OrganizationIdentity({
    required this.organizationId,
    required this.status,
    required this.createdAt,
    required this.displayName,
    required this.countryCode,
  });

  final String organizationId;
  final String status;
  final DateTime createdAt;
  final String? displayName;
  final String? countryCode;

  bool get isActive => status == 'active';
}
