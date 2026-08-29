// 📁 lib/features/settings/screens/workshop_settings_screen.dart
//
// WorkshopSettingsScreen — تصميم A
// + Reset DB (للتطوير فقط)
// + إعدادات أمان بسيطة (سؤالين ثابتين)
// ----------------------------------------------------

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/workshop_settings.dart';
import 'package:yalla_accounts/features/settings/services/workshop_settings_service.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';
import 'data_health_screen.dart';
import 'commercial_settings_screen.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class WorkshopSettingsScreen extends StatefulWidget {
  const WorkshopSettingsScreen({super.key});

  @override
  State<WorkshopSettingsScreen> createState() => _WorkshopSettingsScreenState();
}

class _WorkshopSettingsScreenState extends State<WorkshopSettingsScreen> {
  bool _loading = true;

  // بيانات الورشة
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _phone1Ctrl = TextEditingController();
  final _phone2Ctrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  String? _logoPath;

  // الدوام
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 17, minute: 0);

  double _dailyHours = 8;
  int _breakMinutes = 0;
  String _weekWorkdays = "1,2,3,4,5,6";

  double? _hourlyRate;
  double? _latePenalty;
  double? _overtimeRate;
  double? _earlyLeavePenalty;

  // 🔐 أسئلة الأمان (ثابتة)
  final _q1Ctrl = TextEditingController(); // اسم الورشة
  final _q2Ctrl = TextEditingController(); // رقم الهوية

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ws = await WorkshopSettingsService.instance.getOrDefaults();

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

  Future<void> _pickLogo() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) setState(() => _logoPath = picked.path);
  }

  // ---------------- SAVE ----------------
  Future<void> _save() async {
    if (_q1Ctrl.text.trim().isEmpty || _q2Ctrl.text.trim().isEmpty) {
      _snack('يرجى تعبئة أسئلة الأمان');
      return;
    }

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

    await UserService().setSecurityQuestions(
      question1: 'ما أول اسم لورشتك بالعربية؟',
      question2: 'ما هو رقم هوية صاحب الورشة؟',
      answer1: _q1Ctrl.text.trim(),
      answer2: _q2Ctrl.text.trim(),
    );

    if (!mounted) return;
    _snack('✔ تم حفظ الإعدادات بنجاح');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
            const SizedBox(height: 25),
            ElevatedButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text("حفظ جميع الإعدادات"),
            ),
            const SizedBox(height: 24),
            Card(
              child: ListTile(
                leading: const Icon(Icons.public_outlined),
                title: const Text(
                  'الدولة والعملة والضريبة والترقيم',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'عملة الأساس، دقة الكسور وVAT وإعدادات المستندات',
                ),
                trailing: const Icon(Icons.chevron_left),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CommercialSettingsScreen(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.health_and_safety_outlined),
                title: const Text(
                  'صحة البيانات والمحاسبة',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'فحص قاعدة البيانات، القيود، الفواتير، السندات، الموردين والشيكات',
                ),
                trailing: const Icon(Icons.chevron_left),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DataHealthScreen(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkshopInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          const Text("بيانات الورشة",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Divider(),
          AdaptiveRow(children: [
            _logoPath != null
                ? Image.file(File(_logoPath!), width: 70, height: 70)
                : const Icon(Icons.image, size: 70),
            const SizedBox(width: 12),
            ElevatedButton(
                onPressed: _pickLogo, child: const Text("اختيار شعار")),
          ]),
          TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: "اسم الورشة")),
          TextField(
              controller: _addressCtrl,
              decoration: const InputDecoration(labelText: "العنوان")),
          TextField(
              controller: _cityCtrl,
              decoration: const InputDecoration(labelText: "المدينة")),
        ]),
      ),
    );
  }

  Widget _buildWorkTimeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          const Text("إعدادات الدوام",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ListTile(
            title: const Text("بداية الدوام"),
            subtitle: Text(_fmt(_start)),
            onTap: () async {
              final t =
                  await showTimePicker(context: context, initialTime: _start);
              if (t != null) setState(() => _start = t);
            },
          ),
          ListTile(
            title: const Text("نهاية الدوام"),
            subtitle: Text(_fmt(_end)),
            onTap: () async {
              final t =
                  await showTimePicker(context: context, initialTime: _end);
              if (t != null) setState(() => _end = t);
            },
          ),
        ]),
      ),
    );
  }

  Widget _buildSecurityCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("إعدادات الأمان",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Divider(),
          TextField(
            controller: _q1Ctrl,
            decoration:
                const InputDecoration(labelText: "ما أول اسم لورشتك بالعربية؟"),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _q2Ctrl,
            decoration:
                const InputDecoration(labelText: "ما هو رقم هوية صاحب الورشة؟"),
            keyboardType: TextInputType.number,
          ),
        ]),
      ),
    );
  }
}
