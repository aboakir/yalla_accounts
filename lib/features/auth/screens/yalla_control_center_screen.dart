import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';
import 'package:yalla_accounts/features/auth/services/yalla_admin_auth_service.dart';
import 'package:yalla_accounts/features/home/screens/dashboard_screen.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class _ControlSection {
  const _ControlSection(this.id, this.label, this.endpoint, this.icon);

  final String id;
  final String label;
  final String endpoint;
  final IconData icon;
}

const _sections = <_ControlSection>[
  _ControlSection(
      'dashboard', 'لوحة Yalla', '/dashboard', Icons.dashboard_outlined),
  _ControlSection('onboarding', 'طلبات التسجيل', '/onboarding-requests',
      Icons.person_add_alt_1_outlined),
  _ControlSection(
      'organizations', 'المنشآت', '/organizations', Icons.business_outlined),
  _ControlSection('subscriptions', 'الاشتراكات', '/subscriptions',
      Icons.credit_card_outlined),
  _ControlSection('licenses', 'التراخيص', '/licenses', Icons.verified_outlined),
  _ControlSection('devices', 'الأجهزة', '/devices', Icons.devices_outlined),
  _ControlSection('plans', 'الخطط', '/plans', Icons.layers_outlined),
  _ControlSection('features', 'المزايا', '/features', Icons.extension_outlined),
  _ControlSection(
      'entitlements', 'الاستحقاقات', '/entitlements', Icons.tune_outlined),
  _ControlSection(
      'activations', 'التفعيلات', '/activations', Icons.key_outlined),
  _ControlSection(
      'renewals', 'التجديدات', '/renewals', Icons.autorenew_outlined),
  _ControlSection('overrides', 'التجاوزات', '/overrides',
      Icons.admin_panel_settings_outlined),
  _ControlSection('security-events', 'أحداث الأمان', '/security-events',
      Icons.shield_outlined),
  _ControlSection(
      'audit-logs', 'سجل التدقيق', '/audit-logs', Icons.fact_check_outlined),
  _ControlSection('admin-users', 'مسؤولو Yalla', '/admin-users',
      Icons.manage_accounts_outlined),
  _ControlSection('customer-preview', 'معاينة تطبيق العميل', '/dashboard',
      Icons.preview_outlined),
  _ControlSection(
      'break-glass', 'Break Glass', '/break-glass', Icons.emergency_outlined),
];

const _actionCodes = <String>[
  'ORGANIZATION.CREATE',
  'ORGANIZATION.UPDATE',
  'ORGANIZATION.ACTIVATE',
  'ORGANIZATION.SUSPEND',
  'ORGANIZATION.RESUME',
  'ORGANIZATION.COUNTRY_PACK_SET',
  'SUBSCRIPTION.ACTIVATE',
  'SUBSCRIPTION.SUSPEND',
  'SUBSCRIPTION.REACTIVATE',
  'SUBSCRIPTION.EXTEND',
  'SUBSCRIPTION.TRIAL_EXTEND',
  'SUBSCRIPTION.MARK_PAID',
  'SUBSCRIPTION.MARK_UNPAID',
  'SUBSCRIPTION.CANCEL',
  'SUBSCRIPTION.RESTORE',
  'SUBSCRIPTION.RENEW',
  'SUBSCRIPTION.CHANGE_START_DATE',
  'SUBSCRIPTION.CHANGE_EXPIRY_DATE',
  'SUBSCRIPTION.CHANGE_PLAN',
  'SUBSCRIPTION.TRIAL_CREATE',
  'SUBSCRIPTION.TRIAL_CONVERT_TO_PAID',
  'SUBSCRIPTION.GRACE_EXTEND',
  'ENTITLEMENT.MAX_USERS_SET',
  'ENTITLEMENT.MAX_DEVICES_SET',
  'ENTITLEMENT.FEATURE_ENABLE',
  'ENTITLEMENT.FEATURE_DISABLE',
  'ACTIVATION.FORCE',
  'REACTIVATION.FORCE',
  'RENEWAL.FORCE',
  'DEVICE.ACTIVATE',
  'DEVICE.DEACTIVATE',
  'DEVICE.SUSPEND',
  'DEVICE.RESUME',
  'DEVICE.REVOKE',
  'DEVICE.REPLACE_FORCE',
  'DEVICE.REVOKE_FORCE',
  'SEAT.OVERRIDE_FORCE',
  'FEATURE.OVERRIDE_FORCE',
  'EXPIRY.OVERRIDE_FORCE',
  'SUBSCRIPTION.RESTORE_FORCE',
  'LICENSE.REFRESH_FORCE',
  'LICENSE.ISSUE',
  'LICENSE.REVOKE',
  'BREAK_GLASS.TEMP_SUBSCRIPTION_OPEN',
  'BREAK_GLASS.FREE_DAYS',
  'BREAK_GLASS.TEMP_DEVICE_LIMIT',
  'BREAK_GLASS.TEMP_USER_LIMIT',
  'BREAK_GLASS.CLIENT_REACTIVATE',
  'BREAK_GLASS.TEMP_FEATURE',
  'ADMIN.USERS_MANAGE',
];

class YallaControlCenterScreen extends ConsumerStatefulWidget {
  const YallaControlCenterScreen({super.key, required this.identity});

  final YallaAdminIdentity identity;

  @override
  ConsumerState<YallaControlCenterScreen> createState() =>
      _YallaControlCenterScreenState();
}

class _YallaControlCenterScreenState
    extends ConsumerState<YallaControlCenterScreen> {
  int _selected = 0;
  bool _loading = true;
  String? _error;
  Object? _payload;

  _ControlSection get _section => _sections[_selected];

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadSelected);
  }

  Future<void> _loadSelected() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_section.id == 'customer-preview') {
        if (!mounted) {
          return;
        }
        setState(() {
          _payload = const <String, Object?>{
            'mode': 'LOCAL_CUSTOMER_DB_PREVIEW',
          };
        });
        return;
      }
      final service = ref.read(yallaAdminAuthServiceProvider);
      final payload = await service.getControlCenter(_section.endpoint);
      if (!mounted) {
        return;
      }
      setState(() => _payload = payload);
    } on YallaAdminAuthException catch (error) {
      if (!mounted) {
        return;
      }
      if (error.statusCode == 401) {
        await _logout(message: 'انتهت جلسة الإدارة. سجل الدخول مرة أخرى.');
        return;
      }
      setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'تعذر تحميل بيانات Control Center.');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _logout({String? message}) async {
    await ref.read(yallaAdminAuthServiceProvider).logout();
    if (!mounted) {
      return;
    }
    Navigator.of(context)
        .pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
    if (message != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final current = AppRoutes.navigatorKey.currentContext;
        if (current != null) {
          ScaffoldMessenger.of(current)
              .showSnackBar(SnackBar(content: Text(message)));
        }
      });
    }
  }

  Future<void> _createCustomer() async {
    final request = await showDialog<_CustomerCreateRequest>(
      context: context,
      builder: (_) => const _CreateCustomerDialog(),
    );
    if (request == null) {
      return;
    }
    try {
      final result = await ref
          .read(yallaAdminAuthServiceProvider)
          .createCustomerOrganization(
            organizationName: request.organizationName,
            ownerEmail: request.ownerEmail,
            countryCode: request.countryCode,
            planCode: request.planCode,
            maxUsers: request.maxUsers,
            maxDevices: request.maxDevices,
            trialDays: request.trialDays,
          );
      if (!mounted) {
        return;
      }
      await _showProvisioningResult(result);
      await _loadSelected();
    } on YallaAdminAuthException catch (e) {
      _snack('تعذر إنشاء الزبون: ${e.message}', error: true);
    }
  }

  Future<void> _approveOnboarding(Map<String, Object?> row) async {
    final id = row['request_id']?.toString() ?? '';
    if (id.isEmpty) {
      return;
    }
    try {
      final result = await ref
          .read(yallaAdminAuthServiceProvider)
          .approveCustomerOnboarding(id);
      if (!mounted) {
        return;
      }
      await _showProvisioningResult(result);
      await _loadSelected();
    } on YallaAdminAuthException catch (e) {
      _snack('تعذر اعتماد الطلب: ${e.message}', error: true);
    }
  }

  Future<void> _rejectOnboarding(Map<String, Object?> row) async {
    final id = row['request_id']?.toString() ?? '';
    if (id.isEmpty) {
      return;
    }
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AdaptiveAlertDialog(
        title: const Text('رفض طلب التسجيل'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'سبب الرفض'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('رفض'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.length < 3) {
      return;
    }
    try {
      await ref.read(yallaAdminAuthServiceProvider).rejectCustomerOnboarding(
            requestId: id,
            reason: reason,
          );
      await _loadSelected();
    } on YallaAdminAuthException catch (e) {
      _snack('تعذر رفض الطلب: ${e.message}', error: true);
    }
  }

  Future<void> _showProvisioningResult(Map<String, Object?> result) async {
    final activationCode = result['activation_code']?.toString() ?? '';
    final organizationId = result['organization_id']?.toString() ?? '';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AdaptiveAlertDialog(
        title: const Text('تم تجهيز الزبون'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Organization ID: $organizationId'),
              const SizedBox(height: 12),
              const Text('كود التفعيل — يظهر هنا لمرة واحدة:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SelectableText(
                activationCode.isEmpty
                    ? 'لم يصدر كود في هذا الرد.'
                    : activationCode,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.3),
              ),
              const SizedBox(height: 12),
              Text(
                result['environment']?.toString() == 'LOCAL_DEVELOPMENT_ONLY'
                    ? 'هذا كود تجريبي صادر من Local Dev Harness لتجربة دورة onboarding والمتابعة. الاسترداد الحقيقي للكود على جهاز زبون جديد سيتم من Licensing Server الإنتاجي. كلمة مرور مالك المنشأة يختارها الزبون بنفسه بعد التفعيل.'
                    : 'يرسل هذا الكود للزبون. بعد تفعيل نسخته، ينشئ الزبون حساب مالك المنشأة بنفسه من شاشة الدخول. لا يتم إنشاء كلمة مرور للزبون من Control Center.',
              ),
            ],
          ),
        ),
        actions: [
          if (activationCode.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: activationCode));
                ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('تم نسخ كود التفعيل')));
              },
              icon: const Icon(Icons.copy),
              label: const Text('نسخ الكود'),
            ),
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('تم')),
        ],
      ),
    );
  }

  Future<void> _openLocalCustomerPreview() async {
    try {
      final owner = await ref.read(userServiceProvider).getOwner();
      if (owner == null) {
        _snack('لا يوجد Owner في قاعدة العميل المحلية لفتح المعاينة.',
            error: true);
        return;
      }
      final sessions = ref.read(authSessionServiceProvider);
      await sessions.createSession(owner, keepSignedIn: false);
      ref.read(currentUserProvider.notifier).state = owner;
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => _CustomerPreviewShell(
              ownerLabel: owner.name.isEmpty ? owner.email : owner.name),
        ),
      );
      await sessions.endEphemeralPreviewSession();
      ref.read(currentUserProvider.notifier).state = null;
    } catch (e) {
      _snack('تعذر فتح معاينة العميل المحلية: $e', error: true);
    }
  }

  Future<void> _openActionDialog() async {
    if (!widget.identity.isSuperOwner) {
      _snack('هذه العملية تتطلب YALLA_SUPER_OWNER.');
      return;
    }
    final action = await showDialog<_ActionRequest>(
      context: context,
      builder: (_) => const _PrivilegedActionDialog(),
    );
    if (action == null) {
      return;
    }
    try {
      final response =
          await ref.read(yallaAdminAuthServiceProvider).submitPrivilegedAction(
                actionCode: action.actionCode,
                reason: action.reason,
                organizationId: action.organizationId,
                targetEntityType: action.targetEntityType,
                targetEntityId: action.targetEntityId,
                requestedState: action.requestedState,
                breakGlassGrantId: action.breakGlassGrantId,
              );
      _snack('تم إرسال الإجراء بنجاح: ${response['status'] ?? 'ACCEPTED'}');
      await _loadSelected();
    } on YallaAdminAuthException catch (error) {
      _snack('رفض الخادم الإجراء: ${error.message}', error: true);
    }
  }

  Future<void> _runManagedAction(
    Map<String, Object?> row,
    String actionCode,
    String actionLabel,
    String dayField,
  ) async {
    if (!widget.identity.isSuperOwner) {
      _snack('هذه العملية تتطلب YALLA_SUPER_OWNER.', error: true);
      return;
    }

    final request = await showDialog<_ManagedActionRequest>(
      context: context,
      builder: (_) => _ManagedActionDialog(
        actionLabel: actionLabel,
        dayField: dayField,
      ),
    );
    if (request == null) {
      return;
    }

    final organizationId = row['organization_id']?.toString().trim() ?? '';
    String? targetType;
    String? targetId;
    if (actionCode.startsWith('SUBSCRIPTION.')) {
      targetType = 'subscription';
      targetId = row['subscription_id']?.toString().trim();
    } else if (actionCode.startsWith('DEVICE.')) {
      targetType = 'device';
      targetId = (row['device_id'] ?? row['id'])?.toString().trim();
    } else if (actionCode.startsWith('ORGANIZATION.')) {
      targetType = 'organization';
      targetId = organizationId;
    }

    if (organizationId.isEmpty) {
      _snack('السجل لا يحتوي Organization ID صالحًا.', error: true);
      return;
    }

    final requestedState = <String, Object?>{};
    if (dayField.isNotEmpty && request.days != null) {
      requestedState[dayField] = request.days;
    }

    try {
      final response =
          await ref.read(yallaAdminAuthServiceProvider).submitPrivilegedAction(
                actionCode: actionCode,
                reason: request.reason,
                organizationId: organizationId,
                targetEntityType: targetType,
                targetEntityId: targetId,
                requestedState: requestedState,
              );
      final after = _asMap(response['after_state']);
      final status = after['status'] ?? response['status'] ?? 'APPLIED';
      final billing = after['billing_status'];
      final suffix = billing == null ? '' : ' — الدفع: $billing';
      _snack('$actionLabel: $status$suffix');
      await _loadSelected();
    } on YallaAdminAuthException catch (error) {
      _snack('تعذر تنفيذ $actionLabel: ${error.message}', error: true);
    } catch (error) {
      _snack('تعذر تنفيذ $actionLabel: $error', error: true);
    }
  }

  Future<void> _openBreakGlassDialog() async {
    if (!widget.identity.isSuperOwner) {
      _snack('Break Glass يتطلب YALLA_SUPER_OWNER.', error: true);
      return;
    }
    final request = await showDialog<_BreakGlassRequest>(
      context: context,
      builder: (_) => const _BreakGlassDialog(),
    );
    if (request == null) {
      return;
    }
    try {
      final service = ref.read(yallaAdminAuthServiceProvider);
      final reauth = await service.reauthenticateForBreakGlass(
        password: request.password,
        totpCode: request.totpCode,
      );
      final contextId = reauth['reauth_context_id']?.toString().trim() ?? '';
      if (contextId.isEmpty) {
        throw const YallaAdminAuthException(
            'الخادم لم يُصدر سياق إعادة تحقق صالحًا.');
      }
      final result = await service.openBreakGlass(
        organizationId: request.organizationId,
        reason: request.reason,
        durationMinutes: request.durationMinutes,
        reauthContextId: contextId,
      );
      _snack('تم فتح Break Glass: ${result['grant_id'] ?? 'ACTIVE'}');
      await _loadSelected();
    } on YallaAdminAuthException catch (error) {
      _snack('تعذر فتح Break Glass: ${error.message}', error: true);
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : AppColors.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final compact = width < 1050;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: Text('Yalla Control Center — ${_section.label}'),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Chip(
                  backgroundColor: Colors.white,
                  avatar: Icon(Icons.verified_user_outlined,
                      size: 18, color: AppColors.primary),
                  label: Text(widget.identity.isSuperOwner
                      ? 'YALLA_SUPER_OWNER'
                      : widget.identity.roles.join(', ')),
                ),
              ),
            ),
            IconButton(
                tooltip: 'تحديث',
                onPressed: _loading ? null : _loadSelected,
                icon: const Icon(Icons.refresh)),
            IconButton(
                tooltip: 'تسجيل الخروج',
                onPressed: _logout,
                icon: const Icon(Icons.logout)),
            const SizedBox(width: 8),
          ],
        ),
        drawer: compact ? Drawer(child: _navigation(closeDrawer: true)) : null,
        body: AdaptiveRow(
          children: [
            if (!compact)
              SizedBox(
                width: 265,
                child: Material(
                  color: Colors.white,
                  elevation: 3,
                  child: _navigation(),
                ),
              ),
            Expanded(
              child: Column(
                children: [
                  _adminBanner(),
                  _sectionToolbar(),
                  Expanded(child: _content()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _adminBanner() {
    return Container(
      width: double.infinity,
      color: AppColors.primary.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: AdaptiveRow(
        children: [
          Icon(Icons.admin_panel_settings_outlined, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${widget.identity.email} — جلسة Yalla الإدارية محمية بالخادم وMFA.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _openBreakGlassDialog,
            icon: const Icon(Icons.emergency_outlined),
            label: const Text('Break Glass'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: _openActionDialog,
            icon: const Icon(Icons.bolt_outlined),
            label: const Text('إجراء إداري'),
          ),
        ],
      ),
    );
  }

  Widget _sectionToolbar() {
    final showCreate = _section.id == 'dashboard' ||
        _section.id == 'organizations' ||
        _section.id == 'onboarding';
    if (!showCreate && _section.id != 'customer-preview') {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: AdaptiveRow(
        children: [
          if (showCreate)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: _createCustomer,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('إنشاء زبون جديد'),
            ),
          if (showCreate) const SizedBox(width: 10),
          if (_section.id == 'customer-preview')
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: _openLocalCustomerPreview,
              icon: const Icon(Icons.open_in_new),
              label: const Text('فتح تطبيق العميل المحلي'),
            ),
          const Spacer(),
          if (_section.id == 'onboarding')
            const Text(
                'طلبات الزبائن من شاشة الدخول تظهر هنا للمراجعة والاعتماد.'),
        ],
      ),
    );
  }

  Widget _navigation({bool closeDrawer = false}) {
    return SafeArea(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _sections.length,
        itemBuilder: (context, index) {
          final item = _sections[index];
          final selected = index == _selected;
          return ListTile(
            key: ValueKey(item.id),
            selected: selected,
            selectedColor: AppColors.primary,
            selectedTileColor: AppColors.primary.withValues(alpha: 0.08),
            leading:
                Icon(item.icon, color: selected ? AppColors.primary : null),
            title: Text(item.label,
                style: TextStyle(
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal)),
            onTap: () {
              setState(() => _selected = index);
              if (closeDrawer) {
                Navigator.of(context).pop();
              }
              _loadSelected();
            },
          );
        },
      ),
    );
  }

  Widget _content() {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 52, color: Colors.red.shade400),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                  onPressed: _loadSelected,
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
    }
    if (_section.id == 'dashboard') {
      return _DashboardView(payload: _payload);
    }
    if (_section.id == 'onboarding') {
      return _OnboardingView(
          payload: _payload,
          onApprove: _approveOnboarding,
          onReject: _rejectOnboarding);
    }
    if (_section.id == 'organizations') {
      return _OrganizationAdministrationView(
        payload: _payload,
        onAction: _runManagedAction,
      );
    }
    if (_section.id == 'subscriptions') {
      return _SubscriptionAdministrationView(
        payload: _payload,
        onAction: _runManagedAction,
      );
    }
    if (_section.id == 'devices') {
      return _DeviceAdministrationView(
        payload: _payload,
        onAction: _runManagedAction,
      );
    }
    if (_section.id == 'customer-preview') {
      return _CustomerPreviewInfo(onOpen: _openLocalCustomerPreview);
    }
    return _PayloadView(
        payload: _payload,
        emptyLabel:
            'لا توجد سجلات بعد. استخدم أدوات القسم أو أنشئ زبونًا جديدًا.');
  }
}

class _DashboardView extends StatelessWidget {
  const _DashboardView({required this.payload});
  final Object? payload;

  @override
  Widget build(BuildContext context) {
    final map = _asMap(payload);
    final counts = _asMap(map['counts']);
    final cards = <(String, Object?, IconData)>[
      ('المنشآت', counts['organizations'] ?? 0, Icons.business_outlined),
      (
        'طلبات التسجيل',
        counts['pending_onboarding'] ?? 0,
        Icons.person_add_alt_1_outlined
      ),
      (
        'الاشتراكات النشطة',
        counts['active_subscriptions'] ?? 0,
        Icons.credit_card_outlined
      ),
      (
        'اشتراكات مجمدة',
        counts['suspended_subscriptions'] ?? 0,
        Icons.pause_circle_outline
      ),
      ('غير مدفوعة', counts['unpaid_subscriptions'] ?? 0, Icons.money_off),
      ('الأجهزة', counts['devices'] ?? 0, Icons.devices_outlined),
      (
        'تفعيلات بانتظار الاستخدام',
        counts['pending_activations'] ?? 0,
        Icons.key_outlined
      ),
      ('أحداث الأمان', counts['security_events'] ?? 0, Icons.shield_outlined),
    ];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: cards
              .map((item) => SizedBox(
                    width: 220,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: AdaptiveRow(
                          children: [
                            CircleAvatar(
                                backgroundColor:
                                    AppColors.primary.withValues(alpha: 0.12),
                                child: Icon(item.$3, color: AppColors.primary)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(item.$1),
                                  const SizedBox(height: 4),
                                  Text('${item.$2}',
                                      style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold))
                                ])),
                          ],
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('حالة Control Center',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Text(map['message']?.toString() ?? 'الخادم متصل.'),
                const SizedBox(height: 6),
                Text('Environment: ${map['environment'] ?? '—'}'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _OnboardingView extends StatelessWidget {
  const _OnboardingView(
      {required this.payload, required this.onApprove, required this.onReject});
  final Object? payload;
  final Future<void> Function(Map<String, Object?> row) onApprove;
  final Future<void> Function(Map<String, Object?> row) onReject;

  @override
  Widget build(BuildContext context) {
    final rows = _extractRows(payload) ?? const <Map<String, Object?>>[];
    if (rows.isEmpty) {
      return const _EmptyState(
        icon: Icons.person_add_alt_1_outlined,
        title: 'لا توجد طلبات تسجيل حتى الآن',
        message:
            'يمكن للزبون إرسال طلب من شاشة الدخول، أو يمكنك إنشاء زبون مباشرة من Control Center.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final row = rows[index];
        final status = row['status']?.toString().toUpperCase() ?? '';
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AdaptiveRow(children: [
                  Expanded(
                      child: Text(
                          row['organization_name']?.toString() ?? 'طلب منشأة',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold))),
                  Chip(label: Text(status.isEmpty ? 'UNKNOWN' : status))
                ]),
                const SizedBox(height: 8),
                Text(
                    'المالك: ${row['owner_name'] ?? '—'} — ${row['owner_email'] ?? '—'}'),
                Text(
                    'الدولة: ${row['country_code'] ?? '—'}   الهاتف: ${row['phone'] ?? '—'}'),
                Text('Request ID: ${row['request_id'] ?? '—'}'),
                if (status == 'PENDING') ...[
                  const SizedBox(height: 12),
                  AdaptiveRow(children: [
                    FilledButton.icon(
                        onPressed: () => onApprove(row),
                        icon: const Icon(Icons.check),
                        label: const Text('موافقة وإصدار كود التفعيل')),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                        onPressed: () => onReject(row),
                        icon: const Icon(Icons.close),
                        label: const Text('رفض')),
                  ]),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OrganizationAdministrationView extends StatelessWidget {
  const _OrganizationAdministrationView({
    required this.payload,
    required this.onAction,
  });

  final Object? payload;
  final Future<void> Function(
    Map<String, Object?> row,
    String actionCode,
    String actionLabel,
    String dayField,
  ) onAction;

  @override
  Widget build(BuildContext context) {
    final rows = _extractRows(payload) ?? const <Map<String, Object?>>[];
    if (rows.isEmpty) {
      return const _EmptyState(
        icon: Icons.business_outlined,
        title: 'لا توجد منشآت بعد',
        message: 'أنشئ زبونًا جديدًا أو وافق على طلب تسجيل أولًا.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final row = rows[index];
        final status = row['status']?.toString().toUpperCase() ?? 'UNKNOWN';
        return _AdminRecordCard(
          title: row['name']?.toString() ?? 'Organization',
          status: status,
          fields: <String, Object?>{
            'Organization ID': row['organization_id'],
            'Owner': row['owner_email'],
            'Country': row['country_code'],
          },
          actions: <Widget>[
            if (status == 'ACTIVE')
              OutlinedButton.icon(
                onPressed: () => onAction(
                  row,
                  'ORGANIZATION.SUSPEND',
                  'تجميد المنشأة',
                  '',
                ),
                icon: const Icon(Icons.pause_circle_outline),
                label: const Text('تجميد'),
              ),
            if (status == 'SUSPENDED')
              FilledButton.icon(
                onPressed: () => onAction(
                  row,
                  'ORGANIZATION.RESUME',
                  'إعادة تفعيل المنشأة',
                  '',
                ),
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('إعادة تفعيل'),
              ),
            if (status != 'ACTIVE' && status != 'SUSPENDED')
              FilledButton.icon(
                onPressed: () => onAction(
                  row,
                  'ORGANIZATION.ACTIVATE',
                  'تفعيل المنشأة',
                  '',
                ),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('تفعيل'),
              ),
          ],
        );
      },
    );
  }
}

class _SubscriptionAdministrationView extends StatelessWidget {
  const _SubscriptionAdministrationView({
    required this.payload,
    required this.onAction,
  });

  final Object? payload;
  final Future<void> Function(
    Map<String, Object?> row,
    String actionCode,
    String actionLabel,
    String dayField,
  ) onAction;

  @override
  Widget build(BuildContext context) {
    final rows = _extractRows(payload) ?? const <Map<String, Object?>>[];
    if (rows.isEmpty) {
      return const _EmptyState(
        icon: Icons.credit_card_outlined,
        title: 'لا توجد اشتراكات بعد',
        message: 'ستظهر الاشتراكات هنا بعد إنشاء أول منشأة.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final row = rows[index];
        final status = row['status']?.toString().toUpperCase() ?? 'UNKNOWN';
        final billing =
            row['billing_status']?.toString().toUpperCase() ?? 'UNPAID';
        final remainingDays = row['remaining_days'];
        final remainingHours = row['remaining_hours'];
        final remaining = remainingDays == null
            ? 'غير محدد'
            : '$remainingDays يوم (${remainingHours ?? '—'} ساعة)';

        final actions = <Widget>[];
        if (status == 'TRIAL') {
          actions.add(
            FilledButton.icon(
              onPressed: () => onAction(
                row,
                'SUBSCRIPTION.ACTIVATE',
                'تفعيل الاشتراك',
                '',
              ),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('تفعيل'),
            ),
          );
          actions.add(
            OutlinedButton.icon(
              onPressed: () => onAction(
                row,
                'SUBSCRIPTION.TRIAL_EXTEND',
                'تمديد التجربة',
                'extension_days',
              ),
              icon: const Icon(Icons.more_time),
              label: const Text('تمديد التجربة'),
            ),
          );
        } else if (status == 'ACTIVE') {
          actions.add(
            OutlinedButton.icon(
              onPressed: () => onAction(
                row,
                'SUBSCRIPTION.SUSPEND',
                'تجميد الاشتراك',
                '',
              ),
              icon: const Icon(Icons.pause_circle_outline),
              label: const Text('تجميد'),
            ),
          );
        } else if (status == 'SUSPENDED') {
          actions.add(
            FilledButton.icon(
              onPressed: () => onAction(
                row,
                'SUBSCRIPTION.REACTIVATE',
                'إعادة تفعيل الاشتراك',
                '',
              ),
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('إعادة تفعيل'),
            ),
          );
        } else if (status == 'CANCELLED') {
          actions.add(
            FilledButton.icon(
              onPressed: () => onAction(
                row,
                'SUBSCRIPTION.RESTORE',
                'استعادة الاشتراك',
                '',
              ),
              icon: const Icon(Icons.restore),
              label: const Text('استعادة'),
            ),
          );
        }

        if (status != 'CANCELLED') {
          actions.add(
            OutlinedButton.icon(
              onPressed: () => onAction(
                row,
                'SUBSCRIPTION.EXTEND',
                'تمديد المدة',
                'extension_days',
              ),
              icon: const Icon(Icons.date_range_outlined),
              label: const Text('تمديد المدة'),
            ),
          );
          actions.add(
            OutlinedButton.icon(
              onPressed: () => onAction(
                row,
                'SUBSCRIPTION.RENEW',
                'تجديد الاشتراك',
                'renewal_days',
              ),
              icon: const Icon(Icons.autorenew_outlined),
              label: const Text('تجديد'),
            ),
          );
          actions.add(
            OutlinedButton.icon(
              onPressed: () => onAction(
                row,
                billing == 'PAID'
                    ? 'SUBSCRIPTION.MARK_UNPAID'
                    : 'SUBSCRIPTION.MARK_PAID',
                billing == 'PAID' ? 'تحديد كغير مدفوع' : 'تحديد كمدفوع',
                '',
              ),
              icon: Icon(
                billing == 'PAID' ? Icons.money_off : Icons.payments_outlined,
              ),
              label: Text(billing == 'PAID' ? 'غير مدفوع' : 'مدفوع'),
            ),
          );
        }

        return _AdminRecordCard(
          title: 'اشتراك ${row['plan_code'] ?? ''}',
          status: status,
          secondaryStatus: 'الدفع: $billing',
          fields: <String, Object?>{
            'Subscription ID': row['subscription_id'],
            'Organization ID': row['organization_id'],
            'بداية الاشتراك': row['started_at'],
            'نهاية الاشتراك': row['expires_at'],
            'المدة المتبقية': remaining,
            'MAX_USERS': row['max_users'],
            'MAX_DEVICES': row['max_devices'],
          },
          actions: actions,
        );
      },
    );
  }
}

class _DeviceAdministrationView extends StatelessWidget {
  const _DeviceAdministrationView({
    required this.payload,
    required this.onAction,
  });

  final Object? payload;
  final Future<void> Function(
    Map<String, Object?> row,
    String actionCode,
    String actionLabel,
    String dayField,
  ) onAction;

  @override
  Widget build(BuildContext context) {
    final rows = _extractRows(payload) ?? const <Map<String, Object?>>[];
    if (rows.isEmpty) {
      return const _EmptyState(
        icon: Icons.devices_outlined,
        title: 'لا توجد أجهزة مسجلة بعد',
        message:
            'عندما يسجل العميل جهازًا عبر مسار التفعيل سيظهر هنا، ويمكنك تفعيله أو تعطيله من هذه الشاشة.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final row = rows[index];
        final status = row['status']?.toString().toUpperCase() ?? 'UNKNOWN';
        return _AdminRecordCard(
          title: row['display_name']?.toString().trim().isNotEmpty == true
              ? row['display_name']!.toString()
              : 'Device ${row['device_id'] ?? ''}',
          status: status,
          fields: <String, Object?>{
            'Device ID': row['device_id'],
            'Organization ID': row['organization_id'],
            'App version': row['app_version'],
            'Activated at': row['activated_at'],
            'Last seen': row['last_seen'],
          },
          actions: <Widget>[
            if (status == 'ACTIVE')
              OutlinedButton.icon(
                onPressed: () => onAction(
                  row,
                  'DEVICE.DEACTIVATE',
                  'تعطيل الجهاز',
                  '',
                ),
                icon: const Icon(Icons.pause_circle_outline),
                label: const Text('تعطيل'),
              ),
            if (status == 'SUSPENDED')
              FilledButton.icon(
                onPressed: () => onAction(
                  row,
                  'DEVICE.ACTIVATE',
                  'تفعيل الجهاز',
                  '',
                ),
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('تفعيل'),
              ),
          ],
        );
      },
    );
  }
}

class _AdminRecordCard extends StatelessWidget {
  const _AdminRecordCard({
    required this.title,
    required this.status,
    required this.fields,
    required this.actions,
    this.secondaryStatus,
  });

  final String title;
  final String status;
  final String? secondaryStatus;
  final Map<String, Object?> fields;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdaptiveRow(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Chip(label: Text(status)),
                if (secondaryStatus != null) ...[
                  const SizedBox(width: 8),
                  Chip(label: Text(secondaryStatus!)),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 18,
              runSpacing: 10,
              children: fields.entries
                  .map(
                    (entry) => SizedBox(
                      width: 250,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.key,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(color: Colors.black54),
                          ),
                          const SizedBox(height: 3),
                          SelectableText(_display(entry.value)),
                        ],
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}

class _CustomerPreviewInfo extends StatelessWidget {
  const _CustomerPreviewInfo({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.preview_outlined,
                    size: 56, color: AppColors.primary),
                const SizedBox(height: 14),
                const Text('معاينة تطبيق العميل',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                const Text(
                  'يفتح هذا الوضع واجهة العميل الحقيقية فوق قاعدة البيانات المحلية الموجودة على جهاز التطوير، بهوية Owner محلية مؤقتة. يمكنك مراجعة الأقسام والتنقل بينها ثم العودة إلى Control Center.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  'هذا ليس دخولًا إلى بيانات عميل بعيد. الوصول إلى قاعدة عميل بعيدة يحتاج طبقة Cloud/Remote Support في SEC.017 ويظل خاضعًا للصلاحيات وBreak Glass.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('فتح تطبيق العميل المحلي')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomerPreviewShell extends StatelessWidget {
  const _CustomerPreviewShell({required this.ownerLabel});
  final String ownerLabel;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Column(
          children: [
            Material(
              color: AppColors.primary,
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  height: 52,
                  child: AdaptiveRow(
                    children: [
                      const SizedBox(width: 12),
                      const Icon(Icons.preview_outlined, color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text('وضع معاينة العميل — Owner: $ownerLabel',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold))),
                      TextButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        label: const Text('العودة إلى Control Center',
                            style: TextStyle(color: Colors.white)),
                      ),
                      const SizedBox(width: 12),
                    ],
                  ),
                ),
              ),
            ),
            const Expanded(child: DashboardScreen()),
          ],
        ),
      ),
    );
  }
}

class _PayloadView extends StatelessWidget {
  const _PayloadView(
      {required this.payload, this.emptyLabel = 'لا توجد سجلات في هذا القسم.'});
  final Object? payload;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final rows = _extractRows(payload);
    if (rows != null) {
      if (rows.isEmpty) {
        return _EmptyState(
            icon: Icons.inbox_outlined,
            title: emptyLabel,
            message: 'سيظهر المحتوى هنا بمجرد وجود بيانات على الخادم.');
      }
      return ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final row = rows[index];
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 18,
                runSpacing: 12,
                children: row.entries
                    .map((entry) => SizedBox(
                          width: 260,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(entry.key,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(color: Colors.black54)),
                              const SizedBox(height: 3),
                              SelectableText(_display(entry.value)),
                            ],
                          ),
                        ))
                    .toList(growable: false),
              ),
            ),
          );
        },
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Card(
          child: Padding(
              padding: const EdgeInsets.all(18),
              child: SelectableText(
                  const JsonEncoder.withIndent('  ').convert(payload),
                  textDirection: TextDirection.ltr))),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(
      {required this.icon, required this.title, required this.message});
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 56, color: AppColors.primary.withValues(alpha: 0.75)),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}

Map<String, Object?> _asMap(Object? value) {
  if (value is! Map) {
    return <String, Object?>{};
  }
  return value
      .map<String, Object?>((key, item) => MapEntry(key.toString(), item));
}

List<Map<String, Object?>>? _extractRows(Object? payload) {
  if (payload is List) {
    return payload
        .whereType<Map>()
        .map((row) => row.map<String, Object?>(
            (key, value) => MapEntry(key.toString(), value)))
        .toList(growable: false);
  }
  if (payload is Map) {
    final map = payload
        .map<String, Object?>((key, value) => MapEntry(key.toString(), value));
    final candidate = map['items'] ?? map['data'];
    if (candidate is List) {
      return _extractRows(candidate);
    }
    if (map.containsKey('counts')) {
      return null;
    }
    return <Map<String, Object?>>[map];
  }
  return null;
}

String _display(Object? value) {
  if (value is Map || value is List) {
    return jsonEncode(value);
  }
  return value?.toString() ?? '—';
}

class _CustomerCreateRequest {
  const _CustomerCreateRequest(
      {required this.organizationName,
      required this.ownerEmail,
      required this.countryCode,
      required this.planCode,
      required this.maxUsers,
      required this.maxDevices,
      required this.trialDays});
  final String organizationName;
  final String ownerEmail;
  final String countryCode;
  final String planCode;
  final int maxUsers;
  final int maxDevices;
  final int trialDays;
}

class _CreateCustomerDialog extends StatefulWidget {
  const _CreateCustomerDialog();
  @override
  State<_CreateCustomerDialog> createState() => _CreateCustomerDialogState();
}

class _CreateCustomerDialogState extends State<_CreateCustomerDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _country = TextEditingController(text: 'PS');
  final _plan = TextEditingController(text: 'LOCAL_PRO');
  final _users = TextEditingController(text: '5');
  final _devices = TextEditingController(text: '2');
  final _trial = TextEditingController(text: '0');

  @override
  void dispose() {
    for (final c in [
      _name,
      _email,
      _country,
      _plan,
      _users,
      _devices,
      _trial
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) {
      return;
    }
    Navigator.pop(
        context,
        _CustomerCreateRequest(
          organizationName: _name.text.trim(),
          ownerEmail: _email.text.trim(),
          countryCode: _country.text.trim(),
          planCode: _plan.text.trim(),
          maxUsers: int.tryParse(_users.text) ?? 1,
          maxDevices: int.tryParse(_devices.text) ?? 1,
          trialDays: int.tryParse(_trial.text) ?? 0,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveAlertDialog(
      title: const Text('إنشاء زبون جديد'),
      content: SizedBox(
        width: 620,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'اسم المنشأة'),
                    validator: (v) => (v?.trim().length ?? 0) < 2
                        ? 'اسم المنشأة مطلوب'
                        : null),
                TextFormField(
                    controller: _email,
                    decoration:
                        const InputDecoration(labelText: 'بريد مالك المنشأة'),
                    validator: (v) =>
                        (v?.contains('@') ?? false) ? null : 'بريد صحيح مطلوب'),
                AdaptiveRow(children: [
                  Expanded(
                      child: TextFormField(
                          controller: _country,
                          decoration:
                              const InputDecoration(labelText: 'رمز الدولة'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: TextFormField(
                          controller: _plan,
                          decoration:
                              const InputDecoration(labelText: 'Plan code')))
                ]),
                AdaptiveRow(children: [
                  Expanded(
                      child: TextFormField(
                          controller: _users,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'MAX_USERS'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: TextFormField(
                          controller: _devices,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'MAX_DEVICES'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: TextFormField(
                          controller: _trial,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Trial days')))
                ]),
                const SizedBox(height: 12),
                const Text(
                    'سيُنشأ Organization + Subscription + License/Entitlements ويصدر كود تفعيل لمرة واحدة. الزبون يختار كلمة مروره بنفسه بعد تفعيل نسخته.',
                    style: TextStyle(color: Colors.black54)),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء')),
        FilledButton(onPressed: _submit, child: const Text('إنشاء وإصدار كود'))
      ],
    );
  }
}

class _ManagedActionRequest {
  const _ManagedActionRequest({required this.reason, this.days});

  final String reason;
  final int? days;
}

class _ManagedActionDialog extends StatefulWidget {
  const _ManagedActionDialog({
    required this.actionLabel,
    required this.dayField,
  });

  final String actionLabel;
  final String dayField;

  @override
  State<_ManagedActionDialog> createState() => _ManagedActionDialogState();
}

class _ManagedActionDialogState extends State<_ManagedActionDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  late final TextEditingController _days = TextEditingController(
    text: widget.dayField == 'renewal_days' ? '365' : '14',
  );

  @override
  void dispose() {
    _reason.dispose();
    _days.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) {
      return;
    }
    Navigator.pop(
      context,
      _ManagedActionRequest(
        reason: _reason.text.trim(),
        days: widget.dayField.isEmpty ? null : int.tryParse(_days.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asksDays = widget.dayField.isNotEmpty;
    return AdaptiveAlertDialog(
      title: Text(widget.actionLabel),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _reason,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'سبب الإجراء',
                  hintText: 'مثال: دفعة مستلمة / طلب العميل / تمديد تجربة',
                ),
                validator: (value) => (value?.trim().length ?? 0) < 3
                    ? 'اكتب سببًا واضحًا للإجراء'
                    : null,
              ),
              if (asksDays) ...[
                const SizedBox(height: 10),
                TextFormField(
                  controller: _days,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: widget.dayField == 'renewal_days'
                        ? 'مدة التجديد بالأيام'
                        : 'عدد أيام التمديد',
                  ),
                  validator: (value) {
                    final days = int.tryParse(value?.trim() ?? '');
                    if (days == null || days < 1 || days > 3650) {
                      return 'أدخل رقمًا بين 1 و3650 يومًا';
                    }
                    return null;
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('تنفيذ'),
        ),
      ],
    );
  }
}

class _ActionRequest {
  const _ActionRequest({
    required this.actionCode,
    required this.reason,
    required this.requestedState,
    this.organizationId,
    this.targetEntityType,
    this.targetEntityId,
    this.breakGlassGrantId,
  });

  final String actionCode;
  final String reason;
  final Map<String, Object?> requestedState;
  final String? organizationId;
  final String? targetEntityType;
  final String? targetEntityId;
  final String? breakGlassGrantId;
}

class _PrivilegedActionDialog extends StatefulWidget {
  const _PrivilegedActionDialog();

  @override
  State<_PrivilegedActionDialog> createState() =>
      _PrivilegedActionDialogState();
}

class _PrivilegedActionDialogState extends State<_PrivilegedActionDialog> {
  final _form = GlobalKey<FormState>();
  final _organization = TextEditingController();
  final _targetType = TextEditingController();
  final _targetId = TextEditingController();
  final _reason = TextEditingController();
  final _state = TextEditingController(text: '{}');
  final _breakGlass = TextEditingController();
  String _action = _actionCodes.first;
  String? _jsonError;

  @override
  void dispose() {
    _organization.dispose();
    _targetType.dispose();
    _targetId.dispose();
    _reason.dispose();
    _state.dispose();
    _breakGlass.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) {
      return;
    }
    Map<String, Object?> requestedState;
    try {
      final decoded =
          jsonDecode(_state.text.trim().isEmpty ? '{}' : _state.text);
      if (decoded is! Map) {
        throw const FormatException();
      }
      requestedState = decoded.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
    } catch (_) {
      setState(
          () => _jsonError = 'requested_state يجب أن يكون JSON object صالحًا.');
      return;
    }

    Navigator.of(context).pop(
      _ActionRequest(
        actionCode: _action,
        reason: _reason.text.trim(),
        requestedState: requestedState,
        organizationId: _organization.text,
        targetEntityType: _targetType.text,
        targetEntityId: _targetId.text,
        breakGlassGrantId: _breakGlass.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveAlertDialog(
      title: const Text('إجراء Yalla إداري'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _action,
                  isExpanded: true,
                  items: _actionCodes
                      .map((code) =>
                          DropdownMenuItem(value: code, child: Text(code)))
                      .toList(growable: false),
                  onChanged: (value) =>
                      setState(() => _action = value ?? _action),
                  decoration: const InputDecoration(labelText: 'Action code'),
                ),
                TextFormField(
                    controller: _organization,
                    decoration: const InputDecoration(
                        labelText: 'Organization ID (عند الحاجة)')),
                TextFormField(
                    controller: _targetType,
                    decoration:
                        const InputDecoration(labelText: 'Target entity type')),
                TextFormField(
                    controller: _targetId,
                    decoration:
                        const InputDecoration(labelText: 'Target entity ID')),
                TextFormField(
                  controller: _reason,
                  decoration: const InputDecoration(labelText: 'السبب'),
                  validator: (value) => (value?.trim().length ?? 0) < 8
                      ? 'السبب يجب ألا يقل عن 8 أحرف.'
                      : null,
                ),
                TextFormField(
                  controller: _state,
                  minLines: 3,
                  maxLines: 7,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: 'Requested state (JSON)',
                    errorText: _jsonError,
                  ),
                ),
                TextFormField(
                    controller: _breakGlass,
                    decoration: const InputDecoration(
                        labelText: 'Break Glass Grant ID (للعمليات القسرية)')),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء')),
        FilledButton(onPressed: _submit, child: const Text('إرسال')),
      ],
    );
  }
}

class _BreakGlassRequest {
  const _BreakGlassRequest({
    required this.organizationId,
    required this.reason,
    required this.durationMinutes,
    required this.password,
    required this.totpCode,
  });

  final String organizationId;
  final String reason;
  final int durationMinutes;
  final String password;
  final String totpCode;
}

class _BreakGlassDialog extends StatefulWidget {
  const _BreakGlassDialog();

  @override
  State<_BreakGlassDialog> createState() => _BreakGlassDialogState();
}

class _BreakGlassDialogState extends State<_BreakGlassDialog> {
  final _form = GlobalKey<FormState>();
  final _organization = TextEditingController();
  final _reason = TextEditingController();
  final _password = TextEditingController();
  final _totp = TextEditingController();
  int _duration = 15;
  bool _obscure = true;

  @override
  void dispose() {
    _organization.dispose();
    _reason.dispose();
    _password.dispose();
    _totp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveAlertDialog(
      title: const Text('فتح Break Glass'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _organization,
                decoration: const InputDecoration(labelText: 'Organization ID'),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'مطلوب' : null,
              ),
              TextFormField(
                controller: _reason,
                decoration: const InputDecoration(labelText: 'السبب'),
                validator: (value) => (value?.trim().length ?? 0) < 15
                    ? 'السبب يجب ألا يقل عن 15 حرفًا.'
                    : null,
              ),
              DropdownButtonFormField<int>(
                initialValue: _duration,
                decoration: const InputDecoration(labelText: 'المدة'),
                items: const [5, 10, 15, 30, 45, 60]
                    .map((value) => DropdownMenuItem(
                        value: value, child: Text('$value دقيقة')))
                    .toList(growable: false),
                onChanged: (value) => setState(() => _duration = value ?? 15),
              ),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'كلمة مرور Yalla الحالية',
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility),
                  ),
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? 'مطلوب' : null,
              ),
              TextFormField(
                controller: _totp,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'رمز MFA (TOTP)'),
                validator: (value) =>
                    (value?.trim().length ?? 0) < 6 ? 'أدخل رمز MFA.' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) {
              return;
            }
            Navigator.of(context).pop(
              _BreakGlassRequest(
                organizationId: _organization.text.trim(),
                reason: _reason.text.trim(),
                durationMinutes: _duration,
                password: _password.text,
                totpCode: _totp.text.trim(),
              ),
            );
          },
          child: const Text('إعادة التحقق والفتح'),
        ),
      ],
    );
  }
}
