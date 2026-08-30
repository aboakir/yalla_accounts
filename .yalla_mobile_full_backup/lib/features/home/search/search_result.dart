// 📁 lib/features/home/search/search_result.dart

import 'package:flutter/material.dart';

/// نموذج يمثل نتيجة بحث عام في التطبيق
class SearchResult {
  /// العنوان الرئيسي للنتيجة (مثلاً: "أمر إصلاح: ABC123")
  final String title;

  /// الوصف الثانوي أو التفاصيل الإضافية (مثلاً: "حالة الدفع: مسدد جزئي")
  final String subtitle;

  /// الأيقونة الممثلة لنوع النتيجة
  final IconData icon;

  /// المسار الذي يجب التنقل إليه عند اختيار هذه النتيجة
  final String route;

  const SearchResult({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.route,
  });
}
