/// Converts caught exceptions into safe Arabic messages for end users.
///
/// Technical details remain available to debug logging, while UI surfaces never
/// expose SQLite errors, stack traces, filesystem paths or exception class
/// names.
abstract final class UserFacingError {
  static final RegExp _prefix = RegExp(
    r'^(?:Exception|StateError|ArgumentError|DatabaseException|'
    r'FileSystemException|PathNotFoundException|FormatException|'
    r'Bad state|Invalid argument(?:s)?)'
    r'\s*:?\s*',
    caseSensitive: false,
  );

  static final RegExp _technical = RegExp(
    r'(sqlite|sql\b|databaseexception|filesystemexception|'
    r'pathnotfoundexception|stack trace|no such (?:column|table)|'
    r'pragma\b|select\s+.+\s+from\b|insert\s+into\b|'
    r'update\s+.+\s+set\b|delete\s+from\b|'
    r'package:[a-z0-9_./-]+\.dart|dart:[a-z_]+)',
    caseSensitive: false,
  );

  static final RegExp _absolutePath = RegExp(
    r'(?:[a-zA-Z]:[\\/]|/(?:Users|home|var|tmp|private|data)/)',
  );

  static final RegExp _arabic = RegExp(r'[\u0600-\u06FF]');

  static String message(
    Object error, {
    String fallback = 'تعذر تنفيذ العملية. حاول مرة أخرى.',
  }) {
    var value = error.toString().trim();
    if (value.isEmpty) return fallback;

    value = value.replaceFirst(_prefix, '').trim();

    if (value.isEmpty ||
        value.length > 220 ||
        _technical.hasMatch(value) ||
        _absolutePath.hasMatch(value)) {
      return fallback;
    }

    // The product UI is Arabic. Preserve deliberate Arabic business-rule
    // messages while converting unknown English/plugin errors to a stable
    // generic message.
    if (!_arabic.hasMatch(value)) return fallback;

    return value;
  }
}
