import 'package:flutter/material.dart';
import '../services/commercial_settings_service.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class CommercialSettingsScreen extends StatefulWidget {
  const CommercialSettingsScreen({super.key});

  @override
  State<CommercialSettingsScreen> createState() =>
      _CommercialSettingsScreenState();
}

class _CommercialSettingsScreenState extends State<CommercialSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  String _country = 'PS';
  bool _inclusive = false;

  final _currencyCode = TextEditingController();
  final _symbol = TextEditingController();
  final _decimals = TextEditingController();
  final _vat = TextEditingController();
  final _taxNumber = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _currencyCode.dispose();
    _symbol.dispose();
    _decimals.dispose();
    _vat.dispose();
    _taxNumber.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await CommercialSettingsService.instance.get();
    if (!mounted) return;
    setState(() {
      _country = s.countryCode;
      _currencyCode.text = s.baseCurrencyCode;
      _symbol.text = s.currencySymbol;
      _decimals.text = s.currencyDecimals.toString();
      _vat.text = s.defaultVatRate.toString();
      _taxNumber.text = s.taxRegistrationNumber;
      _inclusive = s.pricesIncludeVat;
      _loading = false;
    });
  }

  void _applyCountry(String value) {
    CountryPreset? preset;
    for (final item in CommercialSettingsService.presets) {
      if (item.code == value) preset = item;
    }
    setState(() {
      _country = value;
      if (preset != null) {
        _currencyCode.text = preset.currencyCode;
        _symbol.text = preset.currencySymbol;
        _decimals.text = preset.decimals.toString();
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final decimals = int.tryParse(_decimals.text.trim());
    final vat = double.tryParse(_vat.text.trim());
    if (decimals == null || decimals < 0 || decimals > 4) return;
    if (vat == null || vat < 0 || vat > 100) return;

    setState(() => _saving = true);
    try {
      await CommercialSettingsService.instance.save(
        CommercialSettings(
          countryCode: _country,
          baseCurrencyCode: _currencyCode.text.trim(),
          currencySymbol: _symbol.text.trim(),
          currencyDecimals: decimals,
          defaultVatRate: vat,
          pricesIncludeVat: _inclusive,
          taxRegistrationNumber: _taxNumber.text.trim(),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ الإعدادات التجارية')),
      );
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Bad state: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الدولة والعملة والضريبة')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _country,
              decoration: const InputDecoration(labelText: 'الدولة'),
              items: CommercialSettingsService.presets
                  .map((p) => DropdownMenuItem(
                        value: p.code,
                        child: Text('${p.nameAr} (${p.code})'),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) _applyCountry(v);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              inputFormatters: const [YallaDigitNormalizer()],
              controller: _currencyCode,
              decoration: const InputDecoration(
                  labelText: 'عملة الأساس ISO (مثال JOD)'),
            ),
            TextField(
              inputFormatters: const [YallaDigitNormalizer()],
              controller: _symbol,
              decoration: const InputDecoration(labelText: 'رمز العملة'),
            ),
            TextField(
              inputFormatters: const [YallaDigitNormalizer()],
              controller: _decimals,
              decoration:
                  const InputDecoration(labelText: 'عدد الكسور العشرية'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              inputFormatters: const [YallaDigitNormalizer()],
              controller: _vat,
              decoration: const InputDecoration(
                labelText: 'VAT الافتراضي %',
                helperText:
                    'يُدخل يدويًا وفق وضع المنشأة؛ تغيير الإعداد لا يعيد حساب التاريخ.',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            SwitchListTile(
              value: _inclusive,
              onChanged: (v) => setState(() => _inclusive = v),
              title: const Text('الأسعار تشمل VAT'),
            ),
            TextField(
              inputFormatters: const [YallaDigitNormalizer()],
              controller: _taxNumber,
              decoration:
                  const InputDecoration(labelText: 'رقم التسجيل الضريبي / VAT'),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ'),
            ),
            const SizedBox(height: 16),
            const Text(
              'عملة الأساس قابلة للتغيير فقط قبل وجود أي حركة مالية. '
              'بعد بدء العمل تُقفل لحماية التاريخ من خلط عملات مختلفة. '
              'تغيير VAT يؤثر على الإعدادات المستقبلية فقط ولا يعيد حساب الماضي.',
            ),
          ],
        ),
      ),
    );
  }
}
