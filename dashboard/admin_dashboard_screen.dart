import 'package:flutter/material.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  // بيانات تجريبية (استبدلها ببياناتك الحقيقية)
  int totalUsers = 850;
  int activeUsers = 700;
  int pendingUsers = 100;
  int rejectedUsers = 50;

  int totalRequests = 320;
  int pendingRequests = 45;
  int approvedRequests = 260;
  int rejectedRequests = 15;

  int unreadNotifications = 8;

  Widget _buildInfoCard(
      {required String title,
      required String value,
      required Color color,
      required IconData icon}) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      shadowColor: color.withOpacity(0.5),
      child: Container(
        padding: const EdgeInsets.all(20),
        width: 150,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: color),
            const SizedBox(height: 10),
            Text(value,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 6),
            Text(title,
                style: const TextStyle(fontSize: 16, color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _buildUsersStatusSummary() {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('حالة المستخدمين',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            _buildStatusRow('مفعل', activeUsers, Colors.green),
            _buildStatusRow('في الانتظار', pendingUsers, Colors.orange),
            _buildStatusRow('مرفوض', rejectedUsers, Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestsStatusSummary() {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('حالة الطلبات',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            _buildStatusRow('في الانتظار', pendingRequests, Colors.orange),
            _buildStatusRow('مقبولة', approvedRequests, Colors.green),
            _buildStatusRow('مرفوضة', rejectedRequests, Colors.red),
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
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 16)),
          const Spacer(),
          Text(count.toString(),
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildNotificationsCard() {
    return Card(
      color:
          unreadNotifications > 0 ? Colors.red.shade50 : Colors.grey.shade200,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: ListTile(
        leading: Icon(Icons.notifications,
            color: unreadNotifications > 0 ? Colors.red : Colors.grey),
        title: Text(
          unreadNotifications > 0
              ? 'لديك $unreadNotifications إشعار جديد'
              : 'لا توجد إشعارات جديدة',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: unreadNotifications > 0 ? Colors.red : Colors.grey,
          ),
        ),
        trailing: unreadNotifications > 0
            ? ElevatedButton(
                onPressed: () {
                  // TODO: افتح صفحة الإشعارات
                },
                child: const Text('عرض'),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة تحكم المدير'),
        backgroundColor: const Color(0xFF3A9D23),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // البطاقات الملخصة
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildInfoCard(
                    title: 'إجمالي المستخدمين',
                    value: totalUsers.toString(),
                    color: Colors.blue,
                    icon: Icons.people,
                  ),
                  _buildInfoCard(
                    title: 'الطلبات الكلية',
                    value: totalRequests.toString(),
                    color: Colors.deepPurple,
                    icon: Icons.list_alt,
                  ),
                  _buildInfoCard(
                    title: 'الإشعارات',
                    value: unreadNotifications.toString(),
                    color: Colors.red,
                    icon: Icons.notifications_active,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            _buildUsersStatusSummary(),

            _buildRequestsStatusSummary(),

            _buildNotificationsCard(),

            const SizedBox(height: 30),

            Center(
              child: Text(
                'مرحباً بك في لوحة تحكم المدير، يمكنك متابعة جميع المستخدمين والطلبات والإشعارات من هنا.',
                style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
