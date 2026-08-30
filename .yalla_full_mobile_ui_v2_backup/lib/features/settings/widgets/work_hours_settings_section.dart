import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/features/settings/services/workshop_settings_service.dart';

class WorkHoursSettingsSection extends ConsumerStatefulWidget {
  const WorkHoursSettingsSection({super.key});

  @override
  ConsumerState<WorkHoursSettingsSection> createState() =>
      _WorkHoursSettingsSectionState();
}

class _WorkHoursSettingsSectionState
    extends ConsumerState<WorkHoursSettingsSection> {
  TimeOfDay? _start;
  TimeOfDay? _end;
  double _dailyHours = 8;

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadFromDatabase();
  }

  // ----------------------------------
  // تحميل الإعدادات من قاعدة البيانات
  // ----------------------------------
  Future<void> _loadFromDatabase() async {
    final ws = await WorkshopSettingsService.instance.getOrDefaults();

    setState(() {
      _start = _parseHHMM(ws.workStart);
      _end = _parseHHMM(ws.workEnd);
      _dailyHours = ws.dailyHours ?? 8;
      _loading = false;
    });
  }

  // ----------------------------------
  // حفظ الإعدادات في قاعدة البيانات
  // ----------------------------------
  Future<void> _saveToDatabase() async {
    if (_start == null || _end == null) return;

    setState(() => _saving = true);

    final current = await WorkshopSettingsService.instance.getOrDefaults();

    final updated = current.copyWith(
      workStart: _fmt(_start!),
      workEnd: _fmt(_end!),
      dailyHours: _dailyHours,
    );

    await WorkshopSettingsService.instance.saveSettings(updated);

    setState(() => _saving = false);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ إعدادات الدوام بنجاح')),
    );
  }

  // ----------------------------------
  // Helpers
  // ----------------------------------
  TimeOfDay _parseHHMM(String? hhmm) {
    if (hhmm == null || !hhmm.contains(':')) {
      return const TimeOfDay(hour: 9, minute: 0);
    }
    final p = hhmm.split(':');
    return TimeOfDay(
      hour: int.parse(p[0]),
      minute: int.parse(p[1]),
    );
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _formatDisplay(TimeOfDay? t) {
    if (t == null) return 'غير محدد';
    final now = DateTime.now();
    return DateFormat('HH:mm').format(
      DateTime(now.year, now.month, now.day, t.hour, t.minute),
    );
  }

  // ----------------------------------
  // UI
  // ----------------------------------
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'إعدادات أوقات الدوام',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // وقت البدء
            ListTile(
              title: const Text('وقت بدء الدوام'),
              subtitle: Text(_formatDisplay(_start)),
              trailing: const Icon(Icons.access_time),
              onTap: () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: _start ?? const TimeOfDay(hour: 9, minute: 0),
                );
                if (t != null) setState(() => _start = t);
              },
            ),

            // وقت الانتهاء
            ListTile(
              title: const Text('وقت انتهاء الدوام'),
              subtitle: Text(_formatDisplay(_end)),
              trailing: const Icon(Icons.access_time),
              onTap: () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: _end ?? const TimeOfDay(hour: 17, minute: 0),
                );
                if (t != null) setState(() => _end = t);
              },
            ),

            const SizedBox(height: 12),

            // عدد ساعات العمل
            DropdownButtonFormField<double>(
              decoration: const InputDecoration(
                labelText: 'عدد ساعات العمل اليومية',
                border: OutlineInputBorder(),
              ),
              value: _dailyHours,
              onChanged: (v) => setState(() => _dailyHours = v ?? 8),
              items: List.generate(10, (i) {
                final h = (6 + i).toDouble();
                return DropdownMenuItem(
                  value: h,
                  child: Text('$h ساعات'),
                );
              }),
            ),

            const SizedBox(height: 16),

            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _saveToDatabase,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: const Text('حفظ'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
