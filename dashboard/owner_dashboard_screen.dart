import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  int totalUsers = 1200;
  int activeUsers = 950;
  int pendingUsers = 180;
  int rejectedUsers = 70;
  double monthlyRevenue = 25500;
  int openTickets = 12;

  final List<MonthlyUsers> monthlyUsersData = [
    MonthlyUsers('يناير', 800),
    MonthlyUsers('فبراير', 900),
    MonthlyUsers('مارس', 1100),
    MonthlyUsers('أبريل', 1200),
    MonthlyUsers('مايو', 1300),
    MonthlyUsers('يونيو', 1400),
  ];

  List<BarChartGroupData> get barGroups {
    return monthlyUsersData.asMap().entries.map((entry) {
      final idx = entry.key;
      final data = entry.value;
      return BarChartGroupData(
        x: idx,
        barRods: [
          BarChartRodData(
            toY: data.count.toDouble(),
            color: Colors.green,
            width: 20,
            borderRadius: BorderRadius.circular(6),
          ),
        ],
      );
    }).toList();
  }

  Widget _buildKpiCard(String title, String value, Color color, IconData icon) {
    return Card(
      elevation: 4,
      shadowColor: color.withOpacity(0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(20),
        width: 160,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: color),
            const SizedBox(height: 10),
            Text(value,
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 6),
            Text(title,
                style: const TextStyle(fontSize: 16, color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(radius: 8, backgroundColor: color),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 16)),
          const Spacer(),
          Text(count.toString(),
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildUserStatusList() {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('حالة المستخدمين',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildStatusRow('مفعل', activeUsers, Colors.green),
            _buildStatusRow('في الانتظار', pendingUsers, Colors.orange),
            _buildStatusRow('مرفوض', rejectedUsers, Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _buildBarChart() {
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: monthlyUsersData
                .map((e) => e.count)
                .reduce((a, b) => a > b ? a : b)
                .toDouble() +
            200,
        barGroups: barGroups,
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              getTitlesWidget: (value, meta) {
                int index = value.toInt();
                if (index < 0 || index >= monthlyUsersData.length) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  axisSide: AxisSide.left, // أو AxisSide.bottom حسب المحور
                  child: Text(
                    monthlyUsersData[index].month,
                    style: const TextStyle(fontSize: 12),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 200,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return SideTitleWidget(
                  axisSide: AxisSide.left, // أو AxisSide.bottom حسب المحور
                  child: Text(value.toInt().toString()),
                );
              },
            ),
          ),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة تحكم الشركة المالكة'),
        backgroundColor: const Color(0xFF3A9D23),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildKpiCard('إجمالي المستخدمين', totalUsers.toString(),
                      Colors.blue, Icons.people),
                  _buildKpiCard(
                      'الإيرادات الشهرية',
                      '${monthlyRevenue.toStringAsFixed(0)} ₪',
                      Colors.green,
                      Icons.attach_money),
                  _buildKpiCard('التذاكر المفتوحة', openTickets.toString(),
                      Colors.orange, Icons.support_agent),
                  _buildKpiCard(
                      'النمو الشهري', '+12%', Colors.purple, Icons.show_chart),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildUserStatusList(),
            const SizedBox(height: 20),
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text('نمو المستخدمين شهريًا',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    SizedBox(height: 200, child: _buildBarChart()),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Center(
              child: Text(
                'مرحباً بكم في لوحة تحكم الشركة المالكة لتطبيق Yalla Accounts',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MonthlyUsers {
  final String month;
  final int count;

  MonthlyUsers(this.month, this.count);
}
