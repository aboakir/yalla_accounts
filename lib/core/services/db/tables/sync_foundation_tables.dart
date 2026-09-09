import 'package:sqflite/sqflite.dart';

/// Stage 50: local metadata only. Never rewrites a source document or a GL row.
/// Install after the operational schemas, inside the migration transaction.
class SyncFoundationTables {
  SyncFoundationTables._();

  static const registry = 'sync_entity_registry';
  static const changes = 'sync_change_log';
  static const context = 'sync_mutation_context';
  static const candidates = 'sync_remote_candidates';
  static const conflicts = 'sync_conflicts';
  static const outboxLinks = 'sync_outbox_links';
  static const technicalTables = {
    registry,
    changes,
    context,
    candidates,
    conflicts,
    outboxLinks,
  };

  /// The registry UUID is independent of legacy integer/business identifiers.
  /// Line/allocation records are tracked too: changing a line cannot disappear
  /// behind an unchanged document header. GL is observed, never applied.
  static const documents = <String, String>{
    'clients': 'client',
    'suppliers': 'supplier',
    'vehicles': 'vehicle',
    'employees': 'employee',
    'parties': 'party',
    'accounts': 'account',
    'repairs': 'repair',
    'repair_lines': 'repair_line',
    'repair_workflow': 'repair_workflow',
    'invoices': 'invoice',
    'purchase_invoices': 'purchase_invoice',
    'purchase_invoice_lines': 'purchase_invoice_line',
    'payments': 'payment',
    'purchase_payments': 'purchase_payment',
    'receipt_headers': 'receipt',
    'receipt_allocations': 'receipt_allocation',
    'customer_credit_allocations': 'customer_credit_allocation',
    'vouchers': 'voucher',
    'cheques': 'cheque',
    'employee_advances': 'employee_advance',
    'payroll_runs': 'payroll_run',
    'payroll_payments': 'payroll_payment',
    'insurance_policies': 'insurance_policy',
    'insurance_policy_cheques': 'insurance_policy_cheque',
    'insurance_policy_installments': 'insurance_policy_installment',
    'insurance_policy_promissories': 'insurance_policy_promissory',
    'invoice_settlements': 'invoice_settlement',
    'monthly_expenses': 'monthly_expense',
    'gl_entries': 'gl_entry',
    'gl_lines': 'gl_line',
  };

  static const _moneyColumns = {
    'amount',
    'total',
    'subtotal',
    'vat',
    'vat_amount',
    'amount_total',
    'paid_total',
    'paid',
    'remaining',
    'qty',
    'quantity',
    'unit_price',
    'price',
    'debit',
    'credit',
    'currency',
    'exchange_rate',
    'total_amount',
    'allocated_amount',
    'credit_amount',
    'gross',
    'net',
    'allowances',
    'deductions',
    'advance_applied',
    'amount_paid',
    'fileValue',
    'paidAmount',
    'finalApprovedAmount',
    'workCost',
    'incomeAmount',
    'actualCost',
    'transferAmount',
    'premium',
    'commission',
    'commission_amount',
    'insurance_amount',
    'total_premium',
    'company_amount',
    'buy_price',
    'sell_price',
    'cash_amount',
    'amount_applied',
    'salaries',
    'raw_materials',
    'electricity',
    'rent',
    'other',
  };

  static const _uuid = "(lower(hex(randomblob(4))) || '-' || "
      "lower(hex(randomblob(2))) || '-4' || substr(lower(hex(randomblob(2))),2) "
      "|| '-' || substr('89ab', (random() & 3) + 1, 1) || "
      "substr(lower(hex(randomblob(2))),2) || '-' || lower(hex(randomblob(6))))";
  static const _now = "strftime('%Y-%m-%dT%H:%M:%fZ','now')";

  static Future<bool> isInstalled(DatabaseExecutor db) async =>
      (await db.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
        [registry],
      ))
          .isNotEmpty;

  static Future<void> ensure(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS $registry (
      entity_uuid TEXT PRIMARY KEY NOT NULL,
      entity_type TEXT NOT NULL,
      local_id TEXT NOT NULL,
      organization_id TEXT,
      revision INTEGER NOT NULL DEFAULT 0 CHECK(revision >= 0),
      is_voided INTEGER NOT NULL DEFAULT 0 CHECK(is_voided IN (0,1)),
      snapshot_json TEXT NOT NULL,
      financial_json TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(entity_type, local_id)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS $context (
      singleton_id INTEGER PRIMARY KEY CHECK(singleton_id=1),
      user_id TEXT
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS $changes (
      sequence INTEGER PRIMARY KEY AUTOINCREMENT,
      change_id TEXT NOT NULL UNIQUE,
      entity_uuid TEXT NOT NULL REFERENCES $registry(entity_uuid),
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      organization_id TEXT,
      device_id TEXT,
      user_id TEXT,
      occurred_at TEXT NOT NULL,
      operation TEXT NOT NULL CHECK(operation IN
        ('created','updated','voided','restored','synced')),
      revision INTEGER NOT NULL CHECK(revision >= 0),
      before_json TEXT,
      after_json TEXT,
      attribution_state TEXT NOT NULL CHECK(attribution_state IN
        ('attributed','unavailable','historical')),
      origin TEXT NOT NULL CHECK(origin IN ('local','baseline','acknowledgement')),
      idempotency_key TEXT NOT NULL UNIQUE
    )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_changes_entity '
        'ON $changes(entity_uuid, revision, sequence)');
    await db.execute('''CREATE TABLE IF NOT EXISTS $candidates (
      candidate_id TEXT PRIMARY KEY NOT NULL,
      organization_id TEXT NOT NULL,
      remote_change_id TEXT NOT NULL,
      entity_uuid TEXT NOT NULL,
      payload_sha256 TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      received_at TEXT NOT NULL,
      disposition TEXT NOT NULL CHECK(disposition IN
        ('requires_review','conflict')),
      UNIQUE(organization_id, remote_change_id)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS $conflicts (
      conflict_id TEXT PRIMARY KEY NOT NULL,
      candidate_id TEXT NOT NULL UNIQUE REFERENCES $candidates(candidate_id),
      entity_uuid TEXT NOT NULL,
      local_revision INTEGER,
      remote_base_revision INTEGER NOT NULL,
      reasons_json TEXT NOT NULL,
      local_snapshot_json TEXT,
      remote_snapshot_json TEXT NOT NULL,
      detected_at TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'open' CHECK(status='open')
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS $outboxLinks (
      outbox_id TEXT PRIMARY KEY NOT NULL,
      change_id TEXT NOT NULL REFERENCES $changes(change_id)
    )''');
    for (final table in [changes, candidates, conflicts, outboxLinks]) {
      for (final op in ['UPDATE', 'DELETE']) {
        await db.execute('''CREATE TRIGGER IF NOT EXISTS
          trg_${table}_immutable_${op.toLowerCase()} BEFORE $op ON $table
          BEGIN SELECT RAISE(ABORT,'SYNC_HISTORY_IMMUTABLE'); END''');
      }
    }
    await db.execute('''CREATE TRIGGER IF NOT EXISTS
      trg_sync_uuid_immutable BEFORE UPDATE OF entity_uuid,entity_type,local_id
      ON $registry BEGIN SELECT RAISE(ABORT,'SYNC_IDENTITY_IMMUTABLE'); END''');
    await db.execute('''CREATE TRIGGER IF NOT EXISTS
      trg_sync_identity_retained BEFORE DELETE ON $registry
      BEGIN SELECT RAISE(ABORT,'SYNC_IDENTITY_RETAINED'); END''');

    // SQLite can propagate an outer REPLACE policy into trigger statements.
    // Reject replacement explicitly; all idempotent insertions above/below use
    // NOT EXISTS, so they do not rely on a conflict policy for identity safety.
    const identities = <String, List<String>>{
      registry: ['entity_uuid'],
      changes: ['sequence', 'change_id', 'idempotency_key'],
      candidates: ['candidate_id'],
      conflicts: ['conflict_id', 'candidate_id'],
      outboxLinks: ['outbox_id'],
    };
    for (final entry in identities.entries) {
      final duplicate = entry.value.map((c) => '$c=NEW.$c').join(' OR ');
      final extra = entry.key == registry
          ? ' OR (entity_type=NEW.entity_type AND local_id=NEW.local_id)'
          : entry.key == candidates
              ? ' OR (organization_id=NEW.organization_id AND remote_change_id=NEW.remote_change_id)'
              : '';
      await db.execute('''CREATE TRIGGER IF NOT EXISTS
        trg_${entry.key}_no_replace BEFORE INSERT ON ${entry.key}
        WHEN EXISTS (SELECT 1 FROM ${entry.key} WHERE $duplicate$extra)
        BEGIN SELECT RAISE(ABORT,'SYNC_HISTORY_REPLACEMENT_FORBIDDEN'); END''');
    }

    final tables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    ))
        .map((r) => r['name'])
        .toSet();
    final org = tables.contains('organization_identity')
        ? '(SELECT organization_id FROM organization_identity WHERE singleton_id=1)'
        : 'NULL';
    final device = tables.contains('installation_identity')
        ? '(SELECT device_id FROM installation_identity WHERE singleton_id=1 '
            'AND organization_id=$org)'
        : 'NULL';

    for (final entry in documents.entries) {
      if (!tables.contains(entry.key)) continue;
      final columns = (await db.rawQuery('PRAGMA table_info(${entry.key})'))
          .map((r) => r['name'] as String)
          .toList();
      final pk = entry.key == 'receipt_headers'
          ? 'receipt_number'
          : entry.key == 'repair_workflow'
              ? 'repair_id'
              : 'id';
      if (!columns.contains(pk)) continue;
      await _track(db, entry.key, entry.value, pk, columns, org, device);
    }
    if (tables.contains('outbox_messages')) await _linkOutbox(db);
  }

  static String _json(List<String> columns, String prefix) {
    if (columns.isEmpty) return "'{}'";
    // SQLite on supported devices can limit function arguments to 127.
    // Small chunks also support wide legacy repair schemas.
    final chunks = <String>[];
    for (var i = 0; i < columns.length; i += 24) {
      final end = (i + 24).clamp(0, columns.length);
      final pairs = columns.sublist(i, end).map((c) {
        final value = '$prefix"${c.replaceAll('"', '""')}"';
        return "'${c.replaceAll("'", "''")}', CASE WHEN typeof($value)='blob' "
            "THEN hex($value) ELSE $value END";
      });
      chunks.add('json_object(${pairs.join(',')})');
    }
    // json_patch would remove null-valued keys; splice object text instead.
    if (chunks.length == 1) return chunks.single;
    return "('{' || ${chunks.map((c) => 'substr($c,2,length($c)-2)').join(" || ',' || ")} || '}')";
  }

  static String _voided(List<String> columns, String prefix) {
    final predicates = <String>[
      if (columns.contains('status'))
        "lower(COALESCE(${prefix}status,'')) IN "
            "('void','voided','cancelled','canceled','reversed','deleted')",
      for (final column in ['is_voided', 'is_deleted'])
        if (columns.contains(column)) 'COALESCE($prefix$column,0)=1',
    ];
    return predicates.isEmpty
        ? '0'
        : '(CASE WHEN ${predicates.join(' OR ')} THEN 1 ELSE 0 END)';
  }

  static Future<void> _track(DatabaseExecutor db, String table, String type,
      String pk, List<String> columns, String org, String device) async {
    final snapshot = _json(columns, '');
    final money = _json(columns.where(_moneyColumns.contains).toList(), '');
    final voided = _voided(columns, '');
    await db.execute('''INSERT OR IGNORE INTO $registry (
      entity_uuid,entity_type,local_id,organization_id,revision,is_voided,
      snapshot_json,financial_json,created_at,updated_at)
      SELECT $_uuid,'$type',CAST("$pk" AS TEXT),$org,0,$voided,
        $snapshot,$money,$_now,$_now FROM "$table"
      WHERE "$pk" IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM $registry r WHERE r.entity_type='$type'
          AND r.local_id=CAST("$table"."$pk" AS TEXT))''');
    // Baseline facts are explicitly historical, never invented creator events.
    await db.execute('''INSERT OR IGNORE INTO $changes (
      change_id,entity_uuid,entity_type,entity_id,organization_id,device_id,
      user_id,occurred_at,operation,revision,before_json,after_json,
      attribution_state,origin,idempotency_key)
      SELECT $_uuid,entity_uuid,entity_type,local_id,organization_id,NULL,NULL,
        created_at,'created',0,NULL,snapshot_json,'historical','baseline',
        'baseline:' || entity_uuid FROM $registry
      WHERE entity_type='$type' AND revision=0 AND NOT EXISTS (
        SELECT 1 FROM $changes c WHERE c.idempotency_key='baseline:' || $registry.entity_uuid)''');
    const sessionActor = '(SELECT user_id FROM $context WHERE singleton_id=1)';
    var insertActor = columns.contains('created_by')
        ? "COALESCE($sessionActor,NULLIF(TRIM(NEW.created_by),''))"
        : sessionActor;
    if (table == 'gl_lines' && columns.contains('entry_id')) {
      final entryColumns = await db.rawQuery('PRAGMA table_info(gl_entries)');
      if (entryColumns.any((c) => c['name'] == 'created_by')) {
        insertActor =
            "COALESCE($sessionActor,(SELECT NULLIF(TRIM(created_by),'') "
            "FROM gl_entries WHERE id=NEW.entry_id))";
      }
    }
    final updateActor = columns.contains('updated_by')
        ? "COALESCE($sessionActor,CASE WHEN NEW.updated_by IS NOT OLD.updated_by "
            "THEN NULLIF(TRIM(NEW.updated_by),'') END)"
        : sessionActor;
    final newSnapshot = _json(columns, 'NEW.');
    final oldSnapshot = _json(columns, 'OLD.');
    final newMoney =
        _json(columns.where(_moneyColumns.contains).toList(), 'NEW.');
    final newVoided = _voided(columns, 'NEW.');
    final oldVoided = _voided(columns, 'OLD.');
    final rowKey = "entity_type='$type' AND local_id=CAST(NEW.\"$pk\" AS TEXT)";

    // Refresh only our own triggers so later additive columns are observed.
    for (final op in ['insert', 'update', 'delete']) {
      await db.execute('DROP TRIGGER IF EXISTS trg_sync_${table}_$op');
    }
    String log(
        String operation, String before, String after, String key, String actor,
        {bool nextRevision = false}) {
      final revision = nextRevision ? '(revision+1)' : 'revision';
      return '''
      INSERT INTO $changes(change_id,entity_uuid,entity_type,entity_id,
        organization_id,device_id,user_id,occurred_at,operation,revision,
        before_json,after_json,attribution_state,origin,idempotency_key)
      SELECT $_uuid,entity_uuid,entity_type,local_id,organization_id,$device,
        $actor,$_now,$operation,$revision,$before,$after,
        CASE WHEN $org IS NOT NULL AND $device IS NOT NULL AND $actor IS NOT NULL
          THEN 'attributed' ELSE 'unavailable' END,'local',
        entity_uuid || ':' || $revision FROM $registry WHERE $key;
      ''';
    }

    // A child mutation also advances the containing document revision. Two
    // devices editing different lines must not appear to edit an unchanged
    // header. This touches only the sidecar, never the actual header row.
    String touchParent(String prefix, String actor, {bool onlyMoved = false}) {
      const parents = <String, (String, String)>{
        'repair_lines': ('repair', 'repair_id'),
        'repair_workflow': ('repair', 'repair_id'),
        'purchase_invoice_lines': ('purchase_invoice', 'invoice_id'),
        'receipt_allocations': ('receipt', 'receipt_number'),
        'insurance_policy_cheques': ('insurance_policy', 'policy_id'),
        'insurance_policy_installments': ('insurance_policy', 'policy_id'),
        'insurance_policy_promissories': ('insurance_policy', 'policy_id'),
        'gl_lines': ('gl_entry', 'entry_id'),
      };
      final parent = parents[table];
      if (parent == null || !columns.contains(parent.$2)) return '';
      final moved =
          onlyMoved ? ' AND OLD."${parent.$2}" IS NOT NEW."${parent.$2}"' : '';
      final key =
          "entity_type='${parent.$1}' AND local_id=CAST($prefix\"${parent.$2}\" AS TEXT)$moved";
      return '''UPDATE $registry SET revision=revision+1,updated_at=$_now WHERE $key;
        ${log("'updated'", 'snapshot_json', 'snapshot_json', key, actor)}''';
    }

    await db.execute('''CREATE TRIGGER trg_sync_${table}_insert
      AFTER INSERT ON "$table" WHEN NEW."$pk" IS NOT NULL BEGIN
      INSERT OR IGNORE INTO $registry(entity_uuid,entity_type,local_id,
        organization_id,revision,is_voided,snapshot_json,financial_json,
        created_at,updated_at) SELECT $_uuid,'$type',CAST(NEW."$pk" AS TEXT),
        $org,0,$newVoided,$newSnapshot,$newMoney,$_now,$_now
        WHERE NOT EXISTS (SELECT 1 FROM $registry WHERE $rowKey);
      ${log("CASE WHEN revision=0 THEN 'created' WHEN is_voided=1 AND $newVoided=0 THEN 'restored' ELSE 'updated' END", 'CASE WHEN revision=0 THEN NULL ELSE snapshot_json END', newSnapshot, rowKey, insertActor, nextRevision: true)}
      UPDATE $registry SET revision=revision+1,is_voided=$newVoided,
        snapshot_json=$newSnapshot,financial_json=$newMoney,updated_at=$_now
        WHERE $rowKey;
      ${touchParent('NEW.', insertActor)}
      END''');
    await db.execute('''CREATE TRIGGER trg_sync_${table}_update
      AFTER UPDATE ON "$table" WHEN $newSnapshot IS NOT $oldSnapshot BEGIN
      UPDATE $registry SET revision=revision+1,is_voided=$newVoided,
        snapshot_json=$newSnapshot,financial_json=$newMoney,updated_at=$_now
        WHERE $rowKey;
      ${log("CASE WHEN $oldVoided=0 AND $newVoided=1 THEN 'voided' WHEN $oldVoided=1 AND $newVoided=0 THEN 'restored' ELSE 'updated' END", oldSnapshot, newSnapshot, rowKey, updateActor)}
      ${touchParent('OLD.', updateActor)}
      ${touchParent('NEW.', updateActor, onlyMoved: true)}
      END''');
    final oldKey = "entity_type='$type' AND local_id=CAST(OLD.\"$pk\" AS TEXT)";
    await db.execute('''CREATE TRIGGER trg_sync_${table}_delete
      AFTER DELETE ON "$table" BEGIN
      UPDATE $registry SET revision=revision+1,is_voided=1,updated_at=$_now
        WHERE $oldKey;
      ${log("'voided'", oldSnapshot, 'NULL', oldKey, sessionActor)}
      ${touchParent('OLD.', sessionActor)}
      END''');
    // A legacy primary key must not move away from its permanent registry id.
    await db.execute('''CREATE TRIGGER IF NOT EXISTS trg_sync_${table}_pk_guard
      BEFORE UPDATE OF "$pk" ON "$table" WHEN NEW."$pk" IS NOT OLD."$pk"
      BEGIN SELECT RAISE(ABORT,'SYNC_DOCUMENT_ID_IMMUTABLE'); END''');
  }

  static Future<void> _linkOutbox(DatabaseExecutor db) async {
    final cols = (await db.rawQuery('PRAGMA table_info(outbox_messages)'))
        .map((r) => r['name'])
        .toSet();
    if (!cols.containsAll(['entity_type', 'entity_id', 'status', 'sent'])) {
      return;
    }
    await db.execute('''CREATE TRIGGER IF NOT EXISTS trg_sync_outbox_link
      AFTER INSERT ON outbox_messages BEGIN
      INSERT OR IGNORE INTO $outboxLinks(outbox_id,change_id)
      SELECT NEW.id,change_id FROM $changes
      WHERE entity_type=NEW.entity_type AND entity_id=NEW.entity_id
        AND origin='local' AND NOT EXISTS (
          SELECT 1 FROM $outboxLinks WHERE outbox_id=NEW.id)
        ORDER BY sequence DESC LIMIT 1;
      END''');
    await db.execute('''CREATE TRIGGER IF NOT EXISTS trg_sync_outbox_ack
      AFTER UPDATE OF sent,status ON outbox_messages
      WHEN NEW.sent=1 AND NEW.status='sent' AND OLD.sent<>1 BEGIN
      INSERT OR IGNORE INTO $changes(change_id,entity_uuid,entity_type,entity_id,
        organization_id,device_id,user_id,occurred_at,operation,revision,
        before_json,after_json,attribution_state,origin,idempotency_key)
      SELECT $_uuid,c.entity_uuid,c.entity_type,c.entity_id,c.organization_id,
        c.device_id,c.user_id,$_now,'synced',c.revision,NULL,NULL,
        c.attribution_state,'acknowledgement','ack:' || NEW.id
      FROM $outboxLinks l JOIN $changes c ON c.change_id=l.change_id
      WHERE l.outbox_id=NEW.id AND NOT EXISTS (
        SELECT 1 FROM $changes WHERE idempotency_key='ack:' || NEW.id);
      END''');
  }

  static Future<void> validate(DatabaseExecutor db) async {
    for (final table in technicalTables) {
      if ((await db.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
        [table],
      ))
          .isEmpty) {
        throw StateError('Stage 50 missing $table.');
      }
    }
    final invalid = Sqflite.firstIntValue(await db.rawQuery('''
      SELECT COUNT(*) FROM $registry WHERE length(entity_uuid)<>36
        OR substr(entity_uuid,15,1)<>'4' OR substr(entity_uuid,20,1) NOT IN ('8','9','a','b')
        OR revision<0 OR NOT json_valid(snapshot_json) OR NOT json_valid(financial_json)
    ''')) ?? 0;
    if (invalid != 0) {
      throw StateError('Stage 50 invalid stable identity metadata.');
    }
    for (final entry in documents.entries) {
      final columns = (await db.rawQuery('PRAGMA table_info(${entry.key})'))
          .map((r) => r['name'])
          .toSet();
      final pk = entry.key == 'receipt_headers'
          ? 'receipt_number'
          : entry.key == 'repair_workflow'
              ? 'repair_id'
              : 'id';
      if (!columns.contains(pk)) continue;
      final missing = Sqflite.firstIntValue(await db.rawQuery('''SELECT COUNT(*)
        FROM "${entry.key}" d LEFT JOIN $registry r
          ON r.entity_type=? AND r.local_id=CAST(d."$pk" AS TEXT)
        WHERE d."$pk" IS NOT NULL AND r.entity_uuid IS NULL''',
              [entry.value])) ??
          0;
      if (missing != 0) {
        throw StateError('Stage 50 missing identities: ${entry.key}.');
      }
      final triggerCount = Sqflite.firstIntValue(await db.rawQuery('''
        SELECT COUNT(*) FROM sqlite_master WHERE type='trigger' AND name IN (?,?,?,?)
      ''', [
            'trg_sync_${entry.key}_insert',
            'trg_sync_${entry.key}_update',
            'trg_sync_${entry.key}_delete',
            'trg_sync_${entry.key}_pk_guard'
          ])) ??
          0;
      if (triggerCount != 4) {
        throw StateError('Stage 50 missing capture triggers: ${entry.key}.');
      }
    }
  }
}
