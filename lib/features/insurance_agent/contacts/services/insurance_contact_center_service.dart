import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';

class InsuranceContactActivity {
  const InsuranceContactActivity({
    required this.id,
    required this.partyId,
    required this.contactAt,
    required this.channel,
    required this.result,
    required this.notes,
    required this.nextFollowUpAt,
    required this.createdBy,
  });

  final String id;
  final String partyId;
  final DateTime contactAt;
  final String channel;
  final String? result;
  final String? notes;
  final DateTime? nextFollowUpAt;
  final String? createdBy;
}

class InsuranceFollowUpTask {
  const InsuranceFollowUpTask({
    required this.id,
    required this.partyId,
    required this.policyId,
    required this.taskType,
    required this.dueAt,
    required this.status,
    required this.assignedTo,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String? partyId;
  final String? policyId;
  final String taskType;
  final DateTime? dueAt;
  final String status;
  final String? assignedTo;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class InsuranceContactCenterService {
  InsuranceContactCenterService._();

  static String? _clean(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static DateTime _parseDate(Object? value) =>
      DateTime.tryParse((value ?? '').toString()) ?? DateTime(1970);

  static DateTime? _parseOptionalDate(Object? value) {
    final text = _clean(value);
    return text == null ? null : DateTime.tryParse(text);
  }

  static String _contactId(String operationId) =>
      'CONTACT:${operationId.trim()}';

  static String _taskId(String contactId) => 'FOLLOWUP:$contactId';

  static InsuranceContactActivity _contactFromRow(
    Map<String, Object?> row,
  ) =>
      InsuranceContactActivity(
        id: row['id'].toString(),
        partyId: row['party_id'].toString(),
        contactAt: _parseDate(row['contact_at']),
        channel: row['channel'].toString(),
        result: _clean(row['result']),
        notes: _clean(row['notes']),
        nextFollowUpAt: _parseOptionalDate(row['next_follow_up_at']),
        createdBy: _clean(row['created_by']),
      );

  static InsuranceFollowUpTask _taskFromRow(Map<String, Object?> row) =>
      InsuranceFollowUpTask(
        id: row['id'].toString(),
        partyId: _clean(row['party_id']),
        policyId: _clean(row['policy_id']),
        taskType: row['task_type'].toString(),
        dueAt: _parseOptionalDate(row['due_at']),
        status: row['status'].toString(),
        assignedTo: _clean(row['assigned_to']),
        notes: _clean(row['notes']),
        createdAt: _parseDate(row['created_at']),
        updatedAt: _parseDate(row['updated_at']),
      );

  static Future<DatabaseExecutor> _db(DatabaseExecutor? executor) async =>
      executor ?? await DBService.database;

  static Future<void> _requireActiveParty(
    DatabaseExecutor db,
    String partyId,
  ) async {
    final rows = await db.query(
      'parties',
      columns: const ['id'],
      where: 'id=? AND is_active=1',
      whereArgs: [partyId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Active Party identity is required.');
  }

  static Future<InsuranceContactActivity> recordContact({
    required String operationId,
    required String partyId,
    required String channel,
    DateTime? contactAt,
    String? result,
    String? notes,
    DateTime? nextFollowUpAt,
    String? createdBy,
    String? assignedTo,
    Database? database,
  }) async {
    final cleanOperation = operationId.trim();
    final cleanParty = partyId.trim();
    final cleanChannel = channel.trim().toUpperCase();
    if (cleanOperation.isEmpty || cleanParty.isEmpty || cleanChannel.isEmpty) {
      throw ArgumentError(
          'Operation, Party, and contact channel are required.');
    }
    final db = database ?? await DBService.database;
    final id = _contactId(cleanOperation);
    final requestedResult = _clean(result);
    final requestedNotes = _clean(notes);
    final requestedBy = _clean(createdBy);
    final requestedAssignee = _clean(assignedTo);

    return SyncFoundationService.transaction(db, (txn) async {
      await _requireActiveParty(txn, cleanParty);
      final existing = await txn.query(
        'insurance_contacts',
        where: 'id=?',
        whereArgs: [id],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final row = existing.single;
        final same = row['party_id'].toString() == cleanParty &&
            row['channel'].toString().toUpperCase() == cleanChannel &&
            _clean(row['result']) == requestedResult &&
            _clean(row['notes']) == requestedNotes &&
            _clean(row['created_by']) == requestedBy &&
            (contactAt == null || _parseDate(row['contact_at']) == contactAt) &&
            (nextFollowUpAt == null ||
                _parseOptionalDate(row['next_follow_up_at']) == nextFollowUpAt);
        if (!same) {
          throw StateError(
            'Contact operation already exists with different material fields.',
          );
        }
        return _contactFromRow(row);
      }

      final effectiveAt = contactAt ?? DateTime.now();
      final now = DateTime.now().toIso8601String();
      final row = <String, Object?>{
        'id': id,
        'party_id': cleanParty,
        'contact_at': effectiveAt.toIso8601String(),
        'channel': cleanChannel,
        'result': requestedResult,
        'notes': requestedNotes,
        'next_follow_up_at': nextFollowUpAt?.toIso8601String(),
        'created_by': requestedBy,
        'created_at': now,
      };
      await txn.insert(
        'insurance_contacts',
        row,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      await txn.update(
        'insurance_prospects',
        {
          'last_contact_at': effectiveAt.toIso8601String(),
          'next_contact_at': nextFollowUpAt?.toIso8601String(),
          'contact_result': requestedResult,
          'updated_at': now,
        },
        where: 'party_id=? AND status<>?',
        whereArgs: [cleanParty, 'ARCHIVED'],
      );

      if (nextFollowUpAt != null) {
        final taskId = _taskId(id);
        await txn.insert(
          'insurance_tasks',
          {
            'id': taskId,
            'party_id': cleanParty,
            'policy_id': null,
            'task_type': 'CONTACT_FOLLOW_UP',
            'due_at': nextFollowUpAt.toIso8601String(),
            'status': 'OPEN',
            'assigned_to': requestedAssignee ?? requestedBy,
            'notes': requestedNotes,
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }

      return _contactFromRow(row);
    });
  }

  static Future<List<InsuranceContactActivity>> listTimeline(
    String partyId, {
    DatabaseExecutor? executor,
  }) async {
    final cleanParty = partyId.trim();
    if (cleanParty.isEmpty) throw ArgumentError('Party is required.');
    final db = await _db(executor);
    final rows = await db.query(
      'insurance_contacts',
      where: 'party_id=?',
      whereArgs: [cleanParty],
      orderBy: 'datetime(contact_at) DESC, created_at DESC, id DESC',
    );
    return rows.map(_contactFromRow).toList(growable: false);
  }

  static Future<List<InsuranceFollowUpTask>> listTasks({
    DateTime? through,
    String? assignedTo,
    String? partyId,
    bool includeCompleted = false,
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final clauses = <String>[];
    final args = <Object?>[];
    if (!includeCompleted) {
      clauses.add("UPPER(status) IN ('OPEN','IN_PROGRESS')");
    }
    if (through != null) {
      clauses.add('due_at IS NOT NULL AND datetime(due_at)<=datetime(?)');
      args.add(through.toIso8601String());
    }
    final cleanAssignee = _clean(assignedTo);
    if (cleanAssignee != null) {
      clauses.add('assigned_to=?');
      args.add(cleanAssignee);
    }
    final cleanParty = _clean(partyId);
    if (cleanParty != null) {
      clauses.add('party_id=?');
      args.add(cleanParty);
    }
    final rows = await db.query(
      'insurance_tasks',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy:
          'CASE WHEN due_at IS NULL THEN 1 ELSE 0 END, datetime(due_at) ASC, created_at ASC',
    );
    return rows.map(_taskFromRow).toList(growable: false);
  }

  static Future<InsuranceFollowUpTask> completeTask(
    String taskId, {
    DateTime? completedAt,
    Database? database,
  }) async {
    final cleanId = taskId.trim();
    if (cleanId.isEmpty) throw ArgumentError('Task id is required.');
    final db = database ?? await DBService.database;
    return SyncFoundationService.transaction(db, (txn) async {
      final rows = await txn.query(
        'insurance_tasks',
        where: 'id=?',
        whereArgs: [cleanId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Insurance follow-up task not found.');
      final current = _taskFromRow(rows.single);
      final status = current.status.toUpperCase();
      if (status == 'DONE') return current;
      if (status == 'CANCELLED') {
        throw StateError('Cancelled follow-up task cannot be completed.');
      }
      final updatedAt = (completedAt ?? DateTime.now()).toIso8601String();
      await txn.update(
        'insurance_tasks',
        {'status': 'DONE', 'updated_at': updatedAt},
        where: 'id=?',
        whereArgs: [cleanId],
      );
      final refreshed = await txn.query(
        'insurance_tasks',
        where: 'id=?',
        whereArgs: [cleanId],
        limit: 1,
      );
      return _taskFromRow(refreshed.single);
    });
  }
}
