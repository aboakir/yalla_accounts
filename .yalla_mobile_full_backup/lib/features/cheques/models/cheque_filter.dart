// 📁 lib/features/cheques/models/cheque_filter.dart
//
// ChequeFilter — الفلتر الرسمي لقسم الشيكات (PRO MAX)
// ------------------------------------------------------------------
// • بحث
// • نوع الشيك
// • حالة الشيك
// • بنك / فرع / عملة
// • مبلغ حد أدنى / أعلى
// • تاريخ إصدار من/إلى
// • تاريخ استحقاق من/إلى
// ------------------------------------------------------------------

import 'package:yalla_accounts/features/cheques/models/cheque.dart';

class ChequeFilter {
  final String? search;

  final ChequeType? type;
  final ChequeStatus? status;

  final String? bankName;
  final String? bankBranch;
  final String? currency;

  final double? amountMin;
  final double? amountMax;

  final DateTime? issueFrom;
  final DateTime? issueTo;

  final DateTime? dueFrom;
  final DateTime? dueTo;

  const ChequeFilter({
    this.search,
    this.type,
    this.status,
    this.bankName,
    this.bankBranch,
    this.currency,
    this.amountMin,
    this.amountMax,
    this.issueFrom,
    this.issueTo,
    this.dueFrom,
    this.dueTo,
  });

  // --------------------------------------------------------------------------
  // copyWith
  // --------------------------------------------------------------------------
  ChequeFilter copyWith({
    String? search,
    ChequeType? type,
    ChequeStatus? status,
    String? bankName,
    String? bankBranch,
    String? currency,
    double? amountMin,
    double? amountMax,
    DateTime? issueFrom,
    DateTime? issueTo,
    DateTime? dueFrom,
    DateTime? dueTo,
  }) {
    return ChequeFilter(
      search: search ?? this.search,
      type: type ?? this.type,
      status: status ?? this.status,
      bankName: bankName ?? this.bankName,
      bankBranch: bankBranch ?? this.bankBranch,
      currency: currency ?? this.currency,
      amountMin: amountMin ?? this.amountMin,
      amountMax: amountMax ?? this.amountMax,
      issueFrom: issueFrom ?? this.issueFrom,
      issueTo: issueTo ?? this.issueTo,
      dueFrom: dueFrom ?? this.dueFrom,
      dueTo: dueTo ?? this.dueTo,
    );
  }

  // --------------------------------------------------------------------------
  // initial → فلتر افتراضي فارغ
  // --------------------------------------------------------------------------
  static ChequeFilter initial() => const ChequeFilter();

  // --------------------------------------------------------------------------
  // match → مطابقة الشيك مع الفلتر
  //   تستخدم داخل provider لفلترة القائمة
  // --------------------------------------------------------------------------
  bool matches(Cheque c) {
    // 1) البحث
    if (search != null && search!.isNotEmpty) {
      final q = search!.toLowerCase();
      final all = [
        c.chequeNo,
        c.drawerName,
        c.bankName,
        c.bankBranch,
        c.currency,
        c.amount.toString(),
      ].join(' ').toLowerCase();

      if (!all.contains(q)) return false;
    }

    // 2) النوع
    if (type != null && c.chequeType != type) return false;

    // 3) الحالة
    if (status != null && c.status != status) return false;

    // 4) البنك
    if (bankName != null &&
        bankName!.isNotEmpty &&
        !c.bankName.toLowerCase().contains(bankName!.toLowerCase())) {
      return false;
    }

    // 5) الفرع
    if (bankBranch != null &&
        bankBranch!.isNotEmpty &&
        !c.bankBranch.toLowerCase().contains(bankBranch!.toLowerCase())) {
      return false;
    }

    // 6) العملة
    if (currency != null &&
        currency!.isNotEmpty &&
        c.currency.toLowerCase() != currency!.toLowerCase()) {
      return false;
    }

    // 7) حد أدنى للمبلغ
    if (amountMin != null && c.amount < amountMin!) return false;

    // 8) حد أعلى للمبلغ
    if (amountMax != null && c.amount > amountMax!) return false;

    // 9) إصدار من
    if (issueFrom != null && c.issueDate.isBefore(issueFrom!)) {
      return false;
    }

    // 10) إصدار إلى
    if (issueTo != null && c.issueDate.isAfter(issueTo!)) {
      return false;
    }

    // 11) استحقاق من
    if (dueFrom != null && c.dueDate.isBefore(dueFrom!)) {
      return false;
    }

    // 12) استحقاق إلى
    if (dueTo != null && c.dueDate.isAfter(dueTo!)) {
      return false;
    }

    return true;
  }
}
