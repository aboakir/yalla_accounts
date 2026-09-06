class PublicTextSanitizer {
  const PublicTextSanitizer._();

  /// Removes internal Yalla metadata markers from any user-facing text.
  /// Internal lines are implementation metadata and must never leak into
  /// PDFs, print/share output, reports, or global search results.
  static String sanitize(Object? raw) {
    final text = (raw ?? '').toString();
    if (text.isEmpty) return '';

    final lines =
        text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    return lines
        .where((line) => !line.trimLeft().startsWith('[YALLA_'))
        .map((line) => line.trimRight())
        .join('\n')
        .trim();
  }

  static bool containsInternalMarker(Object? raw) =>
      RegExp(r'\[YALLA_[A-Z0-9_]+\]', caseSensitive: false)
          .hasMatch((raw ?? '').toString());
}
