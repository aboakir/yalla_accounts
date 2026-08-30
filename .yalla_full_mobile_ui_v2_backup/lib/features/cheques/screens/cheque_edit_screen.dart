// -----------------------------------------------------------------------------
// 📁 lib/features/cheques/screens/cheque_edit_screen.dart
//
// ChequeEditScreen — النسخة النهائية (System-B Ready)
// -----------------------------------------------------------------------------
// • تحميل الشيك من provider.
// • تمرير editCheque إلى ChequeAddScreen.
// • embedded = true لمنع Scaffold داخل Scaffold.
// • معالجة الأخطاء + SnackBar.
// • خالية من أي بيانات وهمية.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cheque.dart';
import '../providers/cheque_provider.dart';
import 'cheque_add_screen.dart';

class ChequeEditScreen extends ConsumerStatefulWidget {
  final int chequeId;

  const ChequeEditScreen({
    super.key,
    required this.chequeId,
  });

  @override
  ConsumerState<ChequeEditScreen> createState() => _ChequeEditScreenState();
}

class _ChequeEditScreenState extends ConsumerState<ChequeEditScreen> {
  bool _loading = true;
  Cheque? _cheque;

  @override
  void initState() {
    super.initState();
    _loadCheque();
  }

  Future<void> _loadCheque() async {
    try {
      final c =
          await ref.read(chequeProvider.notifier).getById(widget.chequeId);

      if (!mounted) return;

      if (c == null) {
        _showError('الشيك غير موجود في السجل');
        Navigator.of(context).pop();
        return;
      }

      setState(() {
        _cheque = c;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      _showError('فشل تحميل الشيك: $e');
      Navigator.of(context).pop();
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // -----------------------------------------------------------------------
    // نقطة الحسم: embedded = true
    // يمنع Scaffold داخل Scaffold
    // يحل مشكلة FlutterViewId
    // -----------------------------------------------------------------------
    return ChequeAddScreen(
      editCheque: _cheque!,
      embedded: true,
    );
  }
}
