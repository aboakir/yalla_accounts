/// A person account, distinct from a workshop user and financial account.
class IdentityAccount {
  const IdentityAccount(
      {required this.id,
      required this.displayName,
      required this.createdAt,
      this.email});
  final String id;
  final String displayName;
  final String? email;
  final DateTime createdAt;

  factory IdentityAccount.fromMap(Map<String, Object?> row) => IdentityAccount(
        id: row['id'] as String,
        displayName: row['display_name'] as String,
        email: row['email'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String),
      );
}
