// 📁 lib/features/settings/screens/workshop_settings_screen.dart
// WorkshopSettingsScreen — FIXED (Phones + Email Visible & Saved)

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/workshop_settings.dart';
import 'package:yalla_accounts/features/settings/services/workshop_settings_service.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'package:yalla_accounts/features/auth/screens/account_security_screen.dart';
import 'package:yalla_accounts/features/auth/screens/manage_users_screen.dart';
import 'package:yalla_accounts/features/settings/screens/security_data_screen.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class WorkshopSettingsScreen extends ConsumerStatefulWidget {
  const WorkshopSettingsScreen({super.key});

  @override
  ConsumerState<WorkshopSettingsScreen> createState() =>
      _WorkshopSettingsScreenState();
}

class _WorkshopSettingsScreenState
    extends ConsumerState<WorkshopSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _generatingCode = false;

  // ===== بيانات الورشة =====
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _phone1Ctrl = TextEditingController();
  final _phone2Ctrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  String? _logoPath;

  // ===== إعدادات الدوام =====
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 17, minute: 0);

  double _dailyHours = 8;
  int _breakMinutes = 0;
  String _weekWorkdays = "1,2,3,4,5,6";

  double? _hourlyRate;
  double? _latePenalty;
  double? _overtimeRate;
  double? _earlyLeavePenalty;

  // ===== 🔐 أسئلة الأمان =====
  final _qWorkshopNameCtrl = TextEditingController();
  final _qOwnerIdCtrl = TextEditingController();
  final _qFirstCarCtrl = TextEditingController(); // اختياري

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ================= LOAD =================
  Future<void> _load() async {
    await ref.read(userServiceProvider).ensureOwnerExists();

    final ws = await WorkshopSettingsService.instance.getOrDefaults();
    if (!mounted) return;

    setState(() {
      _nameCtrl.text = ws.workshopName ?? '';
      _addressCtrl.text = ws.address ?? '';
      _cityCtrl.text = ws.city ?? '';
      _phone1Ctrl.text = ws.phone1 ?? '';
      _phone2Ctrl.text = ws.phone2 ?? '';
      _emailCtrl.text = ws.email ?? '';
      _logoPath = ws.logoPath;

      _start = _parseHHMM(ws.workStart ?? '09:00');
      _end = _parseHHMM(ws.workEnd ?? '17:00');

      _dailyHours = ws.dailyHours ?? 8;
      _breakMinutes = ws.breakMinutes ?? 0;
      _weekWorkdays = ws.weekWorkdays ?? "1,2,3,4,5,6";

      _hourlyRate = ws.hourlyRate;
      _overtimeRate = ws.overtimeRate;
      _latePenalty = ws.latePenalty;
      _earlyLeavePenalty = ws.earlyLeavePenalty;

      _loading = false;
    });
  }

  TimeOfDay _parseHHMM(String hhmm) {
    final p = hhmm.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  // ================= LOGO =================
  Future<void> _pickLogo() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null && mounted) {
      setState(() => _logoPath = picked.path);
    }
  }

  // ================= SAVE =================
  Future<void> _save() async {
    if (_saving) return;

    setState(() => _saving = true);

    try {
      final model = WorkshopSettings(
        id: 1,
        workshopName: _nameCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        city: _cityCtrl.text.trim(),
        phone1: _phone1Ctrl.text.trim(),
        phone2: _phone2Ctrl.text.trim(),
        email: _emailCtrl.text.trim(),
        logoPath: _logoPath,
        workStart: _fmt(_start),
        workEnd: _fmt(_end),
        dailyHours: _dailyHours,
        breakMinutes: _breakMinutes,
        weekWorkdays: _weekWorkdays,
        hourlyRate: _hourlyRate,
        overtimeRate: _overtimeRate,
        latePenalty: _latePenalty,
        earlyLeavePenalty: _earlyLeavePenalty,
      );

      await WorkshopSettingsService.instance.saveSettings(model);

      final securityAnswer1 = _qWorkshopNameCtrl.text.trim();
      final securityAnswer2 = _qOwnerIdCtrl.text.trim();
      if (securityAnswer1.isNotEmpty && securityAnswer2.isNotEmpty) {
        await ref.read(userServiceProvider).setSecurityQuestions(
              question1: 'ما أول اسم لورشتك بالعربية؟',
              question2: 'ما هو رقم هوية صاحب الورشة؟',
              answer1: securityAnswer1,
              answer2: securityAnswer2,
            );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✔ تم حفظ جميع الإعدادات بنجاح')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ فشل الحفظ: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ================= RECOVERY CODE =================
  Future<void> _generateRecoveryCode() async {
    if (_generatingCode) return;

    if (_qWorkshopNameCtrl.text.trim().isEmpty ||
        _qOwnerIdCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❗ يرجى إدخال إجابات أسئلة الأمان أولًا'),
        ),
      );
      return;
    }

    setState(() => _generatingCode = true);

    final userService = ref.read(userServiceProvider);
    final owner = await userService.getOwner();

    if (owner == null) {
      setState(() => _generatingCode = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ لا يوجد مستخدم مالك (Owner) معرف في النظام'),
        ),
      );
      return;
    }

    final code = await userService.generateOwnerRecoveryCode();
    if (!mounted || code == null) {
      setState(() => _generatingCode = false);
      return;
    }

    setState(() => _generatingCode = false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AdaptiveAlertDialog(
        title: const Text('كود الطوارئ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              code,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '⚠️ هذا الكود يُعرض مرة واحدة فقط.\n'
              'احتفظ به في مكان آمن.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              Navigator.pop(context);
            },
            child: const Text('نسخ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('إعدادات الورشة')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildWorkshopInfoCard(),
            const SizedBox(height: 20),
            _buildWorkTimeCard(),
            const SizedBox(height: 20),
            _buildSecurityCard(),
            const SizedBox(height: 20),
            _buildAccountManagementCard(),
            const SizedBox(height: 25),
            ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: const Text('حفظ جميع الإعدادات'),
            ),
          ],
        ),
      ),
    );
  }

  // ================= CARDS =================
  Widget _buildLogoPreview() {
    final path = _logoPath?.trim();
    if (path == null || path.isEmpty) {
      return const Icon(Icons.image, size: 70);
    }

    final file = File(path);
    if (!file.existsSync()) {
      return const Icon(Icons.broken_image_outlined, size: 70);
    }

    return Image.file(
      file,
      width: 70,
      height: 70,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) =>
          const Icon(Icons.broken_image_outlined, size: 70),
    );
  }

  Widget _buildWorkshopInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'بيانات الورشة',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Divider(),
          AdaptiveRow(children: [
            _buildLogoPreview(),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: _pickLogo,
              child: const Text('اختيار شعار'),
            ),
          ]),
          const SizedBox(height: 12),

          TextField(
            inputFormatters: const [YallaDigitNormalizer()],
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'اسم الورشة'),
          ),
          TextField(
            inputFormatters: const [YallaDigitNormalizer()],
            controller: _addressCtrl,
            decoration: const InputDecoration(labelText: 'العنوان'),
          ),
          TextField(
            inputFormatters: const [YallaDigitNormalizer()],
            controller: _cityCtrl,
            decoration: const InputDecoration(labelText: 'المدينة'),
          ),

          const SizedBox(height: 12),

          // ✅ الهواتف + الإيميل (كانت ناقصة)
          TextField(
            inputFormatters: const [YallaDigitNormalizer()],
            controller: _phone1Ctrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'رقم الهاتف الأساسي',
              hintText: '05xxxxxxxx',
            ),
          ),
          TextField(
            inputFormatters: const [YallaDigitNormalizer()],
            controller: _phone2Ctrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'رقم هاتف إضافي / واتساب',
              hintText: '05xxxxxxxx',
            ),
          ),
          TextField(
            inputFormatters: const [YallaDigitNormalizer()],
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'البريد الإلكتروني',
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildWorkTimeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          const Text(
            'إعدادات الدوام',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          ListTile(
            title: const Text('بداية الدوام'),
            subtitle: Text(_fmt(_start)),
            onTap: () async {
              final t =
                  await showTimePicker(context: context, initialTime: _start);
              if (t != null && mounted) setState(() => _start = t);
            },
          ),
          ListTile(
            title: const Text('نهاية الدوام'),
            subtitle: Text(_fmt(_end)),
            onTap: () async {
              final t =
                  await showTimePicker(context: context, initialTime: _end);
              if (t != null && mounted) setState(() => _end = t);
            },
          ),
        ]),
      ),
    );
  }

  Widget _buildAccountManagementCard() {
    final currentUser = ref.watch(currentUserProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerRight,
              child: Text(
                'الحسابات وكلمات المرور',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.security_outlined),
              title: const Text('حسابي وأمان الحساب'),
              subtitle: const Text(
                'تغيير كلمة المرور، كود الاستعادة، والجلسات المحفوظة.',
              ),
              trailing: const Icon(Icons.chevron_left),
              onTap: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const AccountSecurityScreen(),
                  ),
                );
              },
            ),
            if (currentUser?.isOwner == true) ...[
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.manage_accounts_outlined),
                title: const Text('المستخدمون والصلاحيات'),
                subtitle: const Text(
                  'إضافة مستخدمين، الأدوار، التجميد، وإعادة تعيين كلمة المرور.',
                ),
                trailing: const Icon(Icons.chevron_left),
                onTap: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const ManageUsersScreen(),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text('الأمان وحماية البيانات'),
                subtitle: const Text(
                  'سجل التدقيق، النسخ المشفرة الأسبوعية، الاستعادة، ونقل Windows.',
                ),
                trailing: const Icon(Icons.chevron_left),
                onTap: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const SecurityDataScreen(),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityCard() {
    final canGenerate =
        _qWorkshopNameCtrl.text.isNotEmpty && _qOwnerIdCtrl.text.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'إعدادات الأمان',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Divider(),
          const Text(
            '⚠️ لا يمكن عرض أو استرجاع إجابات أسئلة الأمان بعد حفظها.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          TextField(
            inputFormatters: const [YallaDigitNormalizer()],
            controller: _qWorkshopNameCtrl,
            decoration: const InputDecoration(
              labelText: 'ما أول اسم لورشتك بالعربية؟',
            ),
          ),
          TextField(
            inputFormatters: const [YallaDigitNormalizer()],
            controller: _qOwnerIdCtrl,
            decoration: const InputDecoration(
              labelText: 'ما هو رقم هوية صاحب الورشة؟',
            ),
          ),
          TextField(
            inputFormatters: const [YallaDigitNormalizer()],
            controller: _qFirstCarCtrl,
            decoration: const InputDecoration(
              labelText: 'ما نوع أول سيارة قمت بإصلاحها؟ (اختياري)',
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed:
                canGenerate && !_generatingCode ? _generateRecoveryCode : null,
            icon: _generatingCode
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.vpn_key),
            label: const Text('توليد كود طوارئ'),
          ),
        ]),
      ),
    );
  }
}
