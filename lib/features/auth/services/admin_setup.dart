/// P1.002 legacy compatibility shim.
///
/// The historical AdminSetup opened a second SQLite database and created a
/// predictable administrator account. That path is permanently disabled.
class AdminSetup {
  static Future<void> addDefaultAdmin() {
    throw UnsupportedError(
      'Default administrator creation is disabled. '
      'Use the explicit first-owner setup flow.',
    );
  }
}
