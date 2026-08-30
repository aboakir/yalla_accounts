import 'package:sqflite/sqflite.dart';

class DocumentNumberService {
  DocumentNumberService._();

  static Future<String> nextOn(
    DatabaseExecutor db, {
    required String documentType,
  }) async {
    final rows = await db.query(
      'document_sequences',
      where: 'document_type=?',
      whereArgs: [documentType],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Missing document sequence: $documentType');
    }

    final row = rows.first;
    final prefix = row['prefix']?.toString() ?? '';
    final next = (row['next_value'] as num?)?.toInt() ?? 0;
    final width = (row['pad_width'] as num?)?.toInt() ?? 4;
    if (prefix.isEmpty || next <= 0) {
      throw StateError('Invalid document sequence: $documentType');
    }

    final changed = await db.update(
      'document_sequences',
      {
        'next_value': next + 1,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'document_type=? AND next_value=?',
      whereArgs: [documentType, next],
    );
    if (changed != 1) {
      throw StateError('Document sequence conflict. Retry.');
    }

    return '$prefix-${next.toString().padLeft(width, '0')}';
  }
}
