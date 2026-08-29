import 'package:flutter_riverpod/flutter_riverpod.dart';

// نموذج بيانات إحصائيات مبسط (يمكن تطويره لاحقًا)
class DashboardStats {
  final int totalUsers;
  final int activeUsers;
  final int pendingUsers;
  final int rejectedUsers;
  final double monthlyRevenue;
  final int openTickets;
  final int closedTickets;

  DashboardStats({
    required this.totalUsers,
    required this.activeUsers,
    required this.pendingUsers,
    required this.rejectedUsers,
    required this.monthlyRevenue,
    required this.openTickets,
    required this.closedTickets,
  });
}

// مزود بيانات إحصائيات الداشبورد (Riverpod StateNotifier أو StateProvider)
// هنا مثال باستخدام StateProvider مع بيانات افتراضية
final dashboardStatsProvider = StateProvider<DashboardStats>((ref) {
  return DashboardStats(
    totalUsers: 1200,
    activeUsers: 950,
    pendingUsers: 180,
    rejectedUsers: 70,
    monthlyRevenue: 25500.0,
    openTickets: 12,
    closedTickets: 130,
  );
});
