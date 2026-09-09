// 📁 lib/core/data/sidebar_items.dart
//
// Sidebar Items — نسخة محدثة
// ✅ أبقينا كل الأقسام كما هي.
// ✅ قسم المالية الآن يحتوي فقط على شاشتين جاهزتين:
//    1) "القيود اليومية" → AppRoutes.journalEntries
//    2) "قائمة الدخل"   → AppRoutes.incomeStatement
// ⛔ لا توجد عناصر مالية أخرى لتجنب مراجع غير موجودة.

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/models/menu_item.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';

/// بيانات قائمة الشريط الجانبي
final List<MenuItem> sidebarItems = [
  // لوحة التحكم
  const MenuItem(
    title: 'لوحة التحكم',
    route: AppRoutes.dashboard,
    icon: Icons.dashboard,
  ),

  // المركبات
  const MenuItem(
    title: 'المركبات',
    route: null,
    icon: Icons.directions_car,
    children: [
      MenuItem(
        title: 'إدخال مركبة جديدة',
        route: AppRoutes.repairsAdd,
        icon: Icons.add_circle_outline,
      ),
      MenuItem(
        title: 'ملفات الإصلاح',
        route: AppRoutes.repairsList,
        icon: Icons.folder_copy_outlined,
      ),
      MenuItem(
        title: 'قائمة المركبات',
        route: AppRoutes.vehiclesList,
        icon: Icons.list_alt,
      ),
      MenuItem(
        title: 'ذمم المركبات',
        route: AppRoutes.debts,
        icon: Icons.account_balance_wallet,
      ),
    ],
  ),

  // شؤون الموظفين
  const MenuItem(
    title: 'شؤون الموظفين',
    route: null,
    icon: Icons.people_alt,
    children: [
      MenuItem(
        title: 'قائمة الموظفين',
        route: AppRoutes.employeeList,
        icon: Icons.list_alt,
      ),
      MenuItem(
        title: 'إضافة موظف',
        route: AppRoutes.employeeAdd,
        icon: Icons.person_add,
      ),
      MenuItem(
        title: 'إدارة الرواتب',
        route: AppRoutes.employeeSalaries,
        icon: Icons.attach_money,
      ),
      MenuItem(
        title: 'تسجيل الحضور والانصراف',
        route: AppRoutes.employeeAttendance,
        icon: Icons.access_time,
      ),
    ],
  ),

  // المشتريات
  const MenuItem(
    title: 'المشتريات',
    route: null,
    icon: Icons.shopping_cart,
    children: [
      MenuItem(
        title: 'قطع الغيار',
        route: AppRoutes.purchaseTools,
        icon: Icons.precision_manufacturing,
      ),
      MenuItem(
        title: 'مواد الدهان',
        route: AppRoutes.purchasePaint,
        icon: Icons.format_paint,
      ),
      MenuItem(
        title: 'مشتريات أخرى',
        route: AppRoutes.purchaseOther,
        icon: Icons.more_horiz,
      ),
      MenuItem(
        title: 'مدفوعات الشراء',
        route: AppRoutes.purchasePayments,
        icon: Icons.payment,
      ),
    ],
  ),

  // العملاء والموردون
  const MenuItem(
    title: 'العملاء والموردون',
    route: null,
    icon: Icons.group,
    children: [
      MenuItem(
        title: 'الجهات وكشف الحساب الشامل',
        route: '/parties',
        icon: Icons.contact_page,
      ),
      MenuItem(
        title: 'قائمة العملاء',
        route: AppRoutes.clients,
        icon: Icons.people,
      ),
      MenuItem(
        title: 'إضافة عميل',
        route: AppRoutes.clientAdd,
        icon: Icons.person_add,
      ),
      MenuItem(
        title: 'ذمم العملاء',
        route: AppRoutes.clientArrears,
        icon: Icons.request_page,
      ),
      MenuItem(
        title: 'قائمة الموردين',
        route: AppRoutes.suppliers,
        icon: Icons.local_shipping,
      ),
      MenuItem(
        title: 'إضافة مورد',
        route: AppRoutes.supplierAdd,
        icon: Icons.person_add_alt,
      ),
      MenuItem(
        title: 'ذمم الموردين',
        route: AppRoutes.supplierPayables,
        icon: Icons.account_balance,
      ),
    ],
  ),

  // المالية — فقط الشاشتين الجاهزتين
  const MenuItem(
    title: 'المالية',
    route: null,
    icon: Icons.account_balance,
    children: [
      MenuItem(
        title: 'القيود اليومية',
        route: AppRoutes.journalEntries,
        icon: Icons.list_alt,
      ),
      MenuItem(
        title: 'قائمة الدخل',
        route: AppRoutes.incomeStatement,
        icon: Icons.bar_chart,
      ),
    ],
  ),

  // الإعدادات
  const MenuItem(
    title: 'الإعدادات',
    route: null,
    icon: Icons.settings,
    children: [
      MenuItem(
        title: 'إعدادات الورشة',
        route: AppRoutes.settingsWorkshop,
        icon: Icons.store,
      ),
      MenuItem(
        title: 'إعدادات المستخدم',
        route: AppRoutes.settingsUser,
        icon: Icons.person,
      ),
      MenuItem(
        title: 'إعدادات الواجهة',
        route: AppRoutes.settingsUI,
        icon: Icons.color_lens,
      ),
      MenuItem(
        title: 'الدعم والمساعدة',
        route: AppRoutes.settingsSupport,
        icon: Icons.support_agent,
      ),
    ],
  ),
];
