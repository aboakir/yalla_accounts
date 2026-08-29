import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/insurance_calculator_provider.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';

class DynamicInputsForm extends StatelessWidget {
  const DynamicInputsForm({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InsuranceCalculatorProvider>();
    final input = provider.input;
    final key = provider.category.key;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'بيانات المركبة',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // ------------------------------------------------------------
            // سعر المركبة (دائم)
            // ------------------------------------------------------------
            TextFormField(
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: 'سعر المركبة (${MoneyFormatter.symbol})'),
              onChanged: (v) =>
                  provider.updateVehiclePrice(double.tryParse(v) ?? 0),
            ),

            const SizedBox(height: 12),

            // ------------------------------------------------------------
            // حقول حسب الفئة (مطابقة للجداول)
            // ------------------------------------------------------------
            ..._buildFieldsForCategory(
              context: context,
              categoryKey: key,
              input: input,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFieldsForCategory({
    required BuildContext context,
    required String categoryKey,
    required dynamic input,
  }) {
    final provider = context.read<InsuranceCalculatorProvider>();

    switch (categoryKey) {
      // ============================================================
      // 1) خصوصي: شرائح محرك
      // ============================================================
      case 'private':
        return [
          _dropdown<int>(
            label: 'شريحة المحرك',
            value: input?.engineCc,
            items: const [
              _DD(1000, '0 – 1000 سي سي'),
              _DD(1500, '1001 – 1500 سي سي'),
              _DD(2000, '1501 – 2000 سي سي'),
              _DD(2001, '2000+ سي سي'),
            ],
            onChanged: (v) => provider.updateEngineCc(v),
          ),
        ];

      // ============================================================
      // 2) تجاري: نوع الإلزامي (حسب الوزن أو نوع خاص)
      // ============================================================
      case 'commercial':
        final mode = input?.fixedOption as String?; // سنستخدمها كـ "mode"
        final isWeightMode = (mode == null || mode == 'by_weight');

        return [
          _dropdown<String>(
            label: 'نوع المركبة التجارية',
            value: mode ?? 'by_weight',
            items: const [
              _DD('by_weight', 'حسب الوزن'),
              _DD('bus_small', 'باص صغير'),
              _DD('truck_semi', 'شاحنة + نصف قاطرة'),
              _DD('tractor_head', 'رأس قاطرة'),
              _DD('tractor_head_semi', 'رأس قاطرة + نصف قاطرة'),
              _DD('mixer', 'خلاطة / آليات ثقيلة'),
            ],
            onChanged: (v) => provider.updateFixedOption(v),
          ),
          if (isWeightMode) ...[
            const SizedBox(height: 12),
            _dropdown<double>(
              label: 'شريحة الوزن (بالطن)',
              value: input?.weightTon,
              items: const [
                _DD(1.0, '0 – 1 طن'),
                _DD(1.6, '1 – 1.6 طن'),
                _DD(4.0, '1.6 – 4 طن'),
                _DD(6.0, '4 – 6 طن'),
                _DD(6.1, 'أكثر من 6 طن'),
              ],
              onChanged: (v) => provider.updateWeight(v),
            ),
          ],
        ];

      // ============================================================
      // 3) تأجير: اختيار "محرك" أو "وزن"
      // ============================================================
      case 'rental':
        final rentalMode = (input?.fixedOption as String?) ?? 'by_engine';
        final byEngine = rentalMode == 'by_engine';

        return [
          _dropdown<String>(
            label: 'طريقة التسعير (تأجير)',
            value: rentalMode,
            items: const [
              _DD('by_engine', 'حسب المحرك'),
              _DD('by_weight', 'حسب الوزن'),
            ],
            onChanged: (v) => provider.updateFixedOption(v),
          ),
          const SizedBox(height: 12),
          if (byEngine)
            _dropdown<int>(
              label: 'شريحة المحرك',
              value: input?.engineCc,
              items: const [
                _DD(1000, 'حتى 1000 سي سي'),
                _DD(1500, '1001 – 1500 سي سي'),
                _DD(2000, '1501 – 2000 سي سي'),
                _DD(2001, '2000+ سي سي'),
              ],
              onChanged: (v) => provider.updateEngineCc(v),
            )
          else
            _dropdown<double>(
              label: 'شريحة الوزن (بالطن)',
              value: input?.weightTon,
              items: const [
                _DD(1.6, 'حتى 1.6 طن'),
                _DD(2.0, 'أكثر من 1.6 طن'),
                _DD(4.1, 'أكثر من 4 طن'),
              ],
              onChanged: (v) => provider.updateWeight(v),
            ),
        ];

      // ============================================================
      // 4) تاكسي سائق واحد: 3 خيارات (ليست أرقام ركاب)
      // سنحوّلها لقيم passengers عشان الخدمة الحالية تفهمها:
      // - 4–6 => passengers=6
      // - عمومي/خصوصي => passengers=7
      // - كبير => passengers=8
      // ============================================================
      case 'taxi_single':
        return [
          _dropdown<int>(
            label: 'نوع التاكسي (سائق واحد)',
            value: input?.passengers,
            items: const [
              _DD(6, '4 – 6 ركاب'),
              _DD(7, 'تاكسي عمومي أو خصوصي'),
              _DD(8, 'تاكسي كبير'),
            ],
            onChanged: (v) => provider.updatePassengers(v),
          ),
        ];

      // ============================================================
      // 5) تاكسي سائقين / أي سائق: شرائح الركاب
      // ============================================================
      case 'taxi_double':
      case 'taxi_any':
        return [
          _dropdown<int>(
            label: 'عدد الركاب',
            value: input?.passengers,
            items: const [
              _DD(6, '4 – 6 ركاب'),
              _DD(7, '7 ركاب'),
              _DD(8, '8 ركاب'),
            ],
            onChanged: (v) => provider.updatePassengers(v),
          ),
        ];

      // ============================================================
      // 6) باصات: شرائح الركاب
      // ============================================================
      case 'bus_private':
      case 'bus_public':
        return [
          _dropdown<int>(
            label: 'سعة الباص',
            value: input?.passengers,
            items: const [
              _DD(21, 'حتى 21 راكب'),
              _DD(35, 'حتى 35 راكب'),
              _DD(50, 'حتى 50 راكب'),
            ],
            onChanged: (v) => provider.updatePassengers(v),
          ),
        ];

      // ============================================================
      // 7) اتجار: لا مدخلات إضافية
      // ============================================================
      case 'trading':
        return const [
          _InfoLine('لا توجد مدخلات إضافية لهذه الفئة (فقط سعر المركبة).'),
        ];

      // ============================================================
      // 8) دراجات: شرائح محرك
      // ============================================================
      case 'motorcycle':
        return [
          _dropdown<int>(
            label: 'شريحة محرك الدراجة',
            value: input?.engineCc,
            items: const [
              _DD(50, 'لغاية 50 سي سي'),
              _DD(250, '51 – 250 سي سي'),
              _DD(251, 'أكثر من 250 سي سي'),
            ],
            onChanged: (v) => provider.updateEngineCc(v),
          ),
        ];

      // ============================================================
      // 9) مجرور: نوع (حسب الحمولة أو نوع خاص)
      // سنستخدم fixedOption كـ mode
      // ============================================================
      case 'trailer':
        final mode = (input?.fixedOption as String?) ?? 'by_load';
        final byLoad = mode == 'by_load';

        return [
          _dropdown<String>(
            label: 'نوع المجرور',
            value: mode,
            items: const [
              _DD('by_load', 'حسب الحمولة'),
              _DD('tanker', 'مجرور صهريج'),
              _DD('tipper', 'مجرور قلاب'),
              _DD('special', 'مجرور خاص'),
              _DD('agriculture', 'مجرور زراعي'),
            ],
            onChanged: (v) => provider.updateFixedOption(v),
          ),
          if (byLoad) ...[
            const SizedBox(height: 12),
            _dropdown<double>(
              label: 'شريحة الحمولة (طن)',
              value: input?.weightTon,
              items: const [
                _DD(1.0, 'لغاية 1 طن'),
                _DD(3.0, '1 – 3 طن'),
                _DD(6.0, '3 – 6 طن'),
                _DD(16.0, '6 – 16 طن'),
                _DD(16.1, 'أكثر من 16 طن'),
              ],
              onChanged: (v) => provider.updateWeight(v),
            ),
          ],
        ];

      // ============================================================
      // 10) آليات منوعة: نوع الآلية Dropdown (fixedOption)
      // ============================================================
      case 'machinery':
        // هنا لازم options جاية من category.fixedOptions عندك،
        // لكن بما إن هالملف ما بيستورد InsuranceCategory،
        // نخليها تعتمد على provider.category.fixedOptions مباشرة.
        final options = provider.category.fixedOptions;

        return [
          DropdownButtonFormField<String>(
            value: input?.fixedOption,
            decoration: InputDecoration(labelText: 'نوع الآلية'),
            items: options
                .map((o) => DropdownMenuItem<String>(
                      value: o,
                      child: Text(o),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) provider.updateFixedOption(v);
            },
          ),
        ];

      default:
        return const [
          _InfoLine('هذه الفئة غير مدعومة في واجهة الإدخال حالياً.'),
        ];
    }
  }

  // ----------------------------------------------------------------------
  // Dropdown builder
  // ----------------------------------------------------------------------

  Widget _dropdown<T>({
    required String label,
    required T? value,
    required List<_DD<T>> items,
    required ValueChanged<T> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      decoration: InputDecoration(labelText: label),
      items: items
          .map(
            (it) => DropdownMenuItem<T>(
              value: it.value,
              child: Text(it.label),
            ),
          )
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

// ----------------------------------------------------------------------
// Helpers
// ----------------------------------------------------------------------

class _DD<T> {
  final T value;
  final String label;
  const _DD(this.value, this.label);
}

class _InfoLine extends StatelessWidget {
  final String text;
  const _InfoLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, color: Colors.black54),
      ),
    );
  }
}
