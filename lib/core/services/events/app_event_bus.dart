// 📁 lib/core/services/events/app_event_bus.dart
//
// Event Bus بسيط (broadcast) لأحداث الدومين داخل التطبيق.
// - AppEvent: صنف أساس لكل الأحداث.
// - RepairCreated: يُطلق عند إنشاء ملف إصلاح جديد.
// - PaymentRecorded: يُطلق عند تسجيل دفعة على فاتورة/ملف.
// - AppEventBus.emit(...) لبث حدث، و AppEventBus.stream للاستماع.
//
// ملاحظة: خفيف بدون تبعيات خارجية، مناسب لـ Riverpod/Bloc أو أي طبقة استماع.

import 'dart:async';

// ===== Base Event =====
abstract class AppEvent {
  const AppEvent();
}

// ===== Events =====

/// يُطلق بعد إنشاء Repair في قاعدة البيانات.
/// استخدمه لخدمات مثل: إنشاء الفاتورة تلقائياً… إلخ.
class RepairCreated extends AppEvent {
  final String repairId;
  const RepairCreated({required this.repairId});
}

/// يُطلق بعد تسجيل دفعة (اختياري للاستخدام التحليلي/تحديث واجهات).
class PaymentRecorded extends AppEvent {
  final String invoiceId;
  final double amount;
  const PaymentRecorded({required this.invoiceId, required this.amount});
}

// ===== Event Bus =====
class AppEventBus {
  static final StreamController<AppEvent> _controller =
      StreamController<AppEvent>.broadcast();

  /// بثّ حدث
  static void emit(AppEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  /// تيار الأحداث (broadcast)
  static Stream<AppEvent> get stream => _controller.stream;

  /// إغلاق (نادِها عند إطفاء التطبيق إن أردت)
  static Future<void> dispose() async {
    await _controller.close();
  }
}
