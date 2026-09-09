import 'package:flutter/material.dart';
import 'package:yalla_accounts/features/auth/services/owner_data_export_service.dart';

class OwnerDataExportScreen extends StatefulWidget {
  const OwnerDataExportScreen({super.key});
  @override
  State<OwnerDataExportScreen> createState() => _OwnerDataExportScreenState();
}

class _OwnerDataExportScreenState extends State<OwnerDataExportScreen> {
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _backupPassword = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _message;

  Future<void> _export() async {
    if (_busy) return;
    if (_name.text.trim().isEmpty ||
        _password.text.isEmpty ||
        _backupPassword.text.length < 10 ||
        _backupPassword.text != _confirm.text) {
      setState(() => _message =
          'أدخل بيانات المالك وكلمة حماية من 10 أحرف على الأقل، وأكدها.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final shared = await OwnerDataExportService().export(
          username: _name.text,
          password: _password.text,
          backupPassword: _backupPassword.text);
      if (!mounted) return;
      setState(() => _message = shared
          ? 'تم إنشاء النسخة وتسليمها للمشاركة.'
          : 'حُفظت النسخة محليًا، ولم تكتمل مشاركتها.');
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'تعذر التصدير. تحقق من بيانات المالك ومساحة الجهاز ثم أعد المحاولة.');
      }
    } finally {
      if (mounted) {
        _password.clear();
        _backupPassword.clear();
        _confirm.clear();
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    _backupPassword.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
              appBar: AppBar(title: const Text('تصدير بيانات الورشة')),
              body: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    const Text(
                        'يمكن للمالك حفظ نسخة مشفرة من بياناته حتى عند تعذّر التفعيل. احتفظ بكلمة حماية النسخة لاستعادتها.'),
                    const SizedBox(height: 16),
                    TextField(
                        controller: _name,
                        enabled: !_busy,
                        decoration: const InputDecoration(
                            labelText: 'اسم المستخدم للمالك')),
                    const SizedBox(height: 12),
                    TextField(
                        controller: _password,
                        enabled: !_busy,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: const InputDecoration(
                            labelText: 'كلمة مرور المالك')),
                    const SizedBox(height: 12),
                    TextField(
                        controller: _backupPassword,
                        enabled: !_busy,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: const InputDecoration(
                            labelText: 'كلمة حماية النسخة')),
                    const SizedBox(height: 12),
                    TextField(
                        controller: _confirm,
                        enabled: !_busy,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: const InputDecoration(
                            labelText: 'تأكيد كلمة حماية النسخة')),
                    const SizedBox(height: 20),
                    if (_message != null) Text(_message!),
                    const SizedBox(height: 12),
                    FilledButton(
                        onPressed: _busy ? null : _export,
                        child: Text(_busy
                            ? 'جارٍ إنشاء النسخة…'
                            : 'إنشاء النسخة ومشاركتها')),
                  ]))),
        ),
      );
}
