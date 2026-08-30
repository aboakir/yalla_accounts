// 📁 lib/features/insurance_agent/calculater/providers/insurance_calculator_provider.dart

import 'package:flutter/material.dart';

import '../models/insurance_category.dart';
import '../models/insurance_input.dart';
import '../models/insurance_breakdown.dart';
import '../services/insurance_calculator_service.dart';

class InsuranceCalculatorProvider extends ChangeNotifier {
  final InsuranceCalculatorService _service = InsuranceCalculatorService();

  InsuranceCategory _category = InsuranceCategories.all.first;
  InsuranceInput? _input;
  InsuranceBreakdown _result = InsuranceBreakdown.empty();

  // ----------------------------------------------------------------------
  // ✅ Discount (NEW)
  // ----------------------------------------------------------------------
  double _discountPercent = 0; // 0..100

  double get discountPercent => _discountPercent;

  /// يدخلها المستخدم كنص (من TextField) وتتحول لرقم آمن
  void setDiscountPercentText(String text) {
    final v = double.tryParse(text.trim()) ?? 0;
    _discountPercent = v.clamp(0, 100);
    notifyListeners();
  }

  // ----------------------------------------------------------------------
  // Getters
  // ----------------------------------------------------------------------

  InsuranceCategory get category => _category;
  InsuranceInput? get input => _input;
  InsuranceBreakdown get result => _result;

  bool get hasResult => _result.hasResult;

  // ----------------------------------------------------------------------
  // ✅ Totals & Discount Computations (NEW)
  // ----------------------------------------------------------------------

  /// إجمالي النتيجة (عدّل اسم الحقل إذا عندك مختلف)
  double get resultTotal => hasResult ? (_result.total) : 0;

  double get discountAmount =>
      hasResult ? (resultTotal * _discountPercent / 100) : 0;

  double get totalAfterDiscount =>
      hasResult ? (resultTotal - discountAmount) : 0;

  // تنسيق بسيط (بدون كسور). إذا بدك كسور: toStringAsFixed(2)
  String _fmt(num v) => v.toStringAsFixed(0);

  String get discountAmountFormatted => _fmt(discountAmount);
  String get totalAfterDiscountFormatted => _fmt(totalAfterDiscount);

  // ----------------------------------------------------------------------
  // Category
  // ----------------------------------------------------------------------

  void setCategory(InsuranceCategory category) {
    _category = category;
    _input = null;
    _result = InsuranceBreakdown.empty();

    // ✅ reset discount
    _discountPercent = 0;

    notifyListeners();
  }

  // ----------------------------------------------------------------------
  // Input updates
  // ----------------------------------------------------------------------

  void updateVehiclePrice(double value) {
    _ensureInput();
    _input = _input!.copyWith(vehiclePrice: value);
    notifyListeners();
  }

  void updateEngineCc(int value) {
    _ensureInput();
    _input = _input!.copyWith(engineCc: value);
    notifyListeners();
  }

  void updateWeight(double value) {
    _ensureInput();
    _input = _input!.copyWith(weightTon: value);
    notifyListeners();
  }

  void updatePassengers(int value) {
    _ensureInput();
    _input = _input!.copyWith(passengers: value);
    notifyListeners();
  }

  void updateFixedOption(String value) {
    _ensureInput();
    _input = _input!.copyWith(fixedOption: value);
    notifyListeners();
  }

  // ----------------------------------------------------------------------
  // Calculation
  // ----------------------------------------------------------------------

  void calculate() {
    if (_input == null || !_input!.isValid) return;

    _result = _service.calculate(_input!);

    // ✅ ملاحظة: لا نصفر الخصم هنا، لأنه منطقياً المستخدم ممكن يحسب ثم يضع خصم
    notifyListeners();
  }

  void reset() {
    _input = null;
    _result = InsuranceBreakdown.empty();

    // ✅ reset discount
    _discountPercent = 0;

    notifyListeners();
  }

  // ----------------------------------------------------------------------
  // Helpers
  // ----------------------------------------------------------------------

  void _ensureInput() {
    _input ??= InsuranceInput(
      category: _category,
      vehiclePrice: 0,
    );
  }
}
