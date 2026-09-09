import 'gl_posting_policy.dart';
import 'package:sqflite/sqflite.dart';

import 'current_user_context.dart';
import 'db/tables/accounting_tables.dart';

/// P1.006 — single production gateway for immutable General Ledger mutations.
class PostingEngine {
  PostingEngine._();

  static const int currentPostingVersion = 1;

  static void _validateIdentity(String source, String sourceId) {
    if (source.trim().isEmpty) {
      throw ArgumentError.value(source, 'source', 'Posting source is required');
    }
    if (sourceId.trim().isEmpty) {
      throw ArgumentError.value(
        sourceId,
        'sourceId',
        'Posting sourceId is required',
      );
    }
  }

  static void _validateLines(List<Map<String, Object?>> lines) {
    GlPostingPolicy.normalize(lines);
  }

  static Future<String?> _resolveActor(String? explicit) async {
    final value = explicit?.trim();
    if (value != null && value.isNotEmpty) return value;
    final actor = await CurrentUserContext.userId();
    if (actor == null || actor.isEmpty) {
      throw StateError('Authenticated posting user required');
    }
    return actor;
  }

  static Future<int> postEntry({
    required DateTime date,
    String? ref,
    required String source,
    required String sourceId,
    String? sourceNumber,
    String? createdBy,
    String? note,
    required List<Map<String, Object?>> lines,
  }) async {
    _validateIdentity(source, sourceId);
    _validateLines(lines);

    return AccountingTables.postEntryGL(
      date: date,
      ref: ref,
      source: source,
      sourceId: sourceId,
      sourceNumber: sourceNumber,
      postingVersion: currentPostingVersion,
      createdBy: await _resolveActor(createdBy),
      note: note,
      lines: lines,
    );
  }

  static Future<int> postEntryOn({
    required DatabaseExecutor ex,
    required DateTime date,
    String? ref,
    required String source,
    required String sourceId,
    String? sourceNumber,
    String? createdBy,
    String? note,
    required List<Map<String, Object?>> lines,
  }) async {
    _validateIdentity(source, sourceId);
    _validateLines(lines);

    return AccountingTables.postEntryGLOn(
      ex: ex,
      date: date,
      ref: ref,
      source: source,
      sourceId: sourceId,
      sourceNumber: sourceNumber,
      postingVersion: currentPostingVersion,
      createdBy: await _resolveActor(createdBy),
      note: note,
      lines: lines,
    );
  }

  static Future<int> postInvoice({
    required String invoiceId,
    required DateTime date,
    required int clientId,
    required double total,
    double vatAmount = 0.0,
    String? repairId,
    String? ref,
    String? sourceNumber,
    String? createdBy,
    String? note,
  }) async {
    if (invoiceId.trim().isEmpty) {
      throw ArgumentError('invoiceId is required');
    }

    return AccountingTables.postInvoiceGL(
      invoiceId: invoiceId,
      date: date,
      clientId: clientId,
      total: total,
      vatAmount: vatAmount,
      repairId: repairId,
      ref: ref,
      sourceNumber: sourceNumber,
      postingVersion: currentPostingVersion,
      createdBy: await _resolveActor(createdBy),
      note: note,
    );
  }

  static Future<int> postInvoiceOn({
    required DatabaseExecutor txn,
    required String invoiceId,
    required DateTime date,
    required int clientId,
    required double total,
    double vatAmount = 0.0,
    String? repairId,
    String? ref,
    String? sourceNumber,
    String? createdBy,
    String? note,
  }) async {
    if (invoiceId.trim().isEmpty) {
      throw ArgumentError('invoiceId is required');
    }

    return AccountingTables.postInvoiceGLOnTransaction(
      txn: txn,
      invoiceId: invoiceId,
      date: date,
      clientId: clientId,
      total: total,
      vatAmount: vatAmount,
      repairId: repairId,
      ref: ref,
      sourceNumber: sourceNumber,
      postingVersion: currentPostingVersion,
      createdBy: await _resolveActor(createdBy),
      note: note,
    );
  }

  static Future<int> postInvoiceFromId(
    String invoiceId, {
    String? createdBy,
  }) async {
    if (invoiceId.trim().isEmpty) {
      throw ArgumentError('invoiceId is required');
    }

    return AccountingTables.postInvoiceGLFromId(
      invoiceId,
      createdBy: await _resolveActor(createdBy),
    );
  }

  static Future<int> postEmployeeAdvance({
    required String employeeId,
    required DateTime date,
    required double amount,
    required bool viaBank,
    String? ref,
    String? sourceNumber,
    String? createdBy,
    String? note,
  }) async {
    if (employeeId.trim().isEmpty) {
      throw ArgumentError('employeeId is required');
    }

    return AccountingTables.postEmployeeAdvanceGL(
      employeeId: employeeId,
      date: date,
      amount: amount,
      viaBank: viaBank,
      ref: ref,
      sourceNumber: sourceNumber,
      postingVersion: currentPostingVersion,
      createdBy: await _resolveActor(createdBy),
      note: note,
    );
  }

  static Future<int> reverseEntry(
    int entryId, {
    String? createdBy,
    String? note,
  }) async {
    if (entryId <= 0) {
      throw ArgumentError('entryId must be positive');
    }

    return AccountingTables.reverseEntryGL(
      entryId,
      createdBy: await _resolveActor(createdBy),
      note: note,
    );
  }

  static Future<int> reverseEntryOn(
    DatabaseExecutor ex,
    int entryId, {
    String? createdBy,
    String? note,
  }) async {
    if (entryId <= 0) {
      throw ArgumentError('entryId must be positive');
    }

    return AccountingTables.reverseEntryGLOn(
      ex,
      entryId,
      createdBy: await _resolveActor(createdBy),
      note: note,
    );
  }
}
