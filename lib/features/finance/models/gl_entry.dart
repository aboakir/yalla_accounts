// 📁 lib/features/finance/gl/models/gl_models.dart
//
// نماذج GL متوافقة مع v29a:
// - GLEntry: يمثّل رأس القيد (gl_entries)
// - GLLine : يمثّل سطر القيد  (gl_lines)
// ملاحظات:
// • التاريخ في الرأس فقط (ISO8601).
// • السطر يستخدم account_id (INT) وليس account_code.
// • party_type ∈ {CLIENT, SUPPLIER, EMPLOYEE} أو null.
// • party_id نصّي دائمًا عندك في v29a.
// • invoice_id / repair_id نصية اختيارية للربط.
//
// جاهز للاستعمال مع DBService.postEntryGL(lines: entry.linesToMaps())

import 'package:intl/intl.dart';

class GLEntry {
  final int? id; // gl_entries.id (قد يكون null قبل الإدراج)
  final DateTime date; // تاريخ القيد
  final String source; // مثل: 'PURCHASE', 'PURCHASE_PAY', 'SUPPLIER_PAYMENT'
  final String sourceId; // مفتاح idempotency
  final String? ref; // مرجع يظهر للمستخدم
  final String? note; // ملاحظة
  final List<GLLine> lines; // سطور القيد

  const GLEntry({
    this.id,
    required this.date,
    required this.source,
    required this.sourceId,
    this.ref,
    this.note,
    required this.lines,
  });

  // خريطة الرأس (بدون السطور) — تطابق أعمدة gl_entries
  Map<String, Object?> toHeadMap() {
    return {
      'date': date.toIso8601String(),
      'source': source,
      'source_id': sourceId,
      'ref': ref,
      'note': note,
    };
  }

  // سطور القيد كخرائط — جاهزة للإرسال لـ DBService.postEntryGL(...)
  List<Map<String, Object?>> linesToMaps() {
    return lines.map((e) => e.toMap()).toList();
  }

  // هل القيد متوازن؟
  bool get isBalanced {
    final d = lines.fold<double>(0.0, (s, l) => s + l.debit);
    final c = lines.fold<double>(0.0, (s, l) => s + l.credit);
    // سماحية صغيرة للفلوت
    return (d - c).abs() < 0.0001;
  }

  // تحويل من Map (صف gl_entries)
  factory GLEntry.fromMap(Map<String, Object?> m, {List<GLLine>? lines}) {
    DateTime pDate(Object? v) {
      final s = (v ?? '').toString();
      // يدعم 'yyyy-MM-dd' أو ISO8601
      final tryIso = DateTime.tryParse(s);
      if (tryIso != null) return tryIso;
      return DateFormat('yyyy-MM-dd').parse(s);
    }

    return GLEntry(
      id: _asInt(m['id']),
      date: pDate(m['date']),
      source: (m['source'] ?? '').toString(),
      sourceId: (m['source_id'] ?? '').toString(),
      ref: _asStrOrNull(m['ref']),
      note: _asStrOrNull(m['note']),
      lines: lines ?? const [],
    );
  }

  GLEntry copyWith({
    int? id,
    DateTime? date,
    String? source,
    String? sourceId,
    String? ref,
    String? note,
    List<GLLine>? lines,
  }) {
    return GLEntry(
      id: id ?? this.id,
      date: date ?? this.date,
      source: source ?? this.source,
      sourceId: sourceId ?? this.sourceId,
      ref: ref ?? this.ref,
      note: note ?? this.note,
      lines: lines ?? this.lines,
    );
  }
}

class GLLine {
  final int accountId; // accounts.id
  final double debit; // ≥ 0
  final double credit; // ≥ 0
  final String? partyType; // 'CLIENT' | 'SUPPLIER' | 'EMPLOYEE' | null
  final String? partyId; // نصّي دائمًا في v29a
  final String? invoiceId; // ربط اختياري
  final String? repairId; // ربط اختياري

  const GLLine({
    required this.accountId,
    this.debit = 0.0,
    this.credit = 0.0,
    this.partyType,
    this.partyId,
    this.invoiceId,
    this.repairId,
  });

  Map<String, Object?> toMap() {
    return {
      'account_id': accountId,
      'debit': _round(debit),
      'credit': _round(credit),
      'party_type': partyType,
      'party_id': partyId,
      'invoice_id': invoiceId,
      'repair_id': repairId,
    };
  }

  factory GLLine.fromMap(Map<String, Object?> m) {
    return GLLine(
      accountId: _asInt(m['account_id']) ?? 0,
      debit: _asDouble(m['debit']),
      credit: _asDouble(m['credit']),
      partyType: _asStrOrNull(m['party_type']),
      partyId: _asStrOrNull(m['party_id']),
      invoiceId: _asStrOrNull(m['invoice_id']),
      repairId: _asStrOrNull(m['repair_id']),
    );
  }

  GLLine copyWith({
    int? accountId,
    double? debit,
    double? credit,
    String? partyType,
    String? partyId,
    String? invoiceId,
    String? repairId,
  }) {
    return GLLine(
      accountId: accountId ?? this.accountId,
      debit: debit ?? this.debit,
      credit: credit ?? this.credit,
      partyType: partyType ?? this.partyType,
      partyId: partyId ?? this.partyId,
      invoiceId: invoiceId ?? this.invoiceId,
      repairId: repairId ?? this.repairId,
    );
  }
}

// ===== Helpers دقيقة لتحويل الأنواع =====

int? _asInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  return int.tryParse(v.toString());
}

double _asDouble(Object? v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}

String? _asStrOrNull(Object? v) {
  final s = (v ?? '').toString().trim();
  return s.isEmpty ? null : s;
}

double _round(num v) => double.parse(v.toStringAsFixed(2));
