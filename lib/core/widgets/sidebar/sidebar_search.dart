// SidebarSearch — بحث حي + اختصارات (Ctrl+K للتركيز، Esc لمسح) + Debounce
// SidebarSearch — Live search + shortcuts (Ctrl+K to focus, Esc to clear) + Debounce
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class SidebarSearch extends StatefulWidget {
  final String initialQuery;
  final String hintText; // ← صار فعّال
  final ValueChanged<String> onChanged;
  final Color fillColor; // لون الخلفية
  final bool autofocus; // للتركيز التلقائي اختياري
  final Duration debounce; // مدة التهدئة

  const SidebarSearch({
    super.key,
    required this.initialQuery,
    required this.onChanged,
    this.hintText = 'بحث...',
    this.fillColor = const Color(0xFFF0F0F0),
    this.autofocus = false,
    this.debounce = const Duration(milliseconds: 180),
  });

  @override
  State<SidebarSearch> createState() => _SidebarSearchState();
}

class _SidebarSearchState extends State<SidebarSearch> {
  late final TextEditingController _ctrl;
  final FocusNode _focusNode = FocusNode();
  Timer? _debouncer;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialQuery);
  }

  @override
  void dispose() {
    _debouncer?.cancel();
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _emit(String v) {
    _debouncer?.cancel();
    _debouncer = Timer(widget.debounce, () => widget.onChanged(v));
    setState(() {}); // لتحديث suffixIcon
  }

  void _clear() {
    _ctrl.clear();
    widget.onChanged('');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
          _focusNode.requestFocus();
          _ctrl.selection =
              TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
        },
        const SingleActivator(LogicalKeyboardKey.escape): _clear,
      },
      child: Focus(
        canRequestFocus: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            inputFormatters: const [YallaDigitNormalizer()],
            controller: _ctrl,
            focusNode: _focusNode,
            autofocus: widget.autofocus,
            textDirection: TextDirection.rtl,
            onChanged: _emit,
            decoration: InputDecoration(
              hintText: widget.hintText,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _ctrl.text.isNotEmpty
                  ? IconButton(
                      tooltip: 'مسح',
                      icon: const Icon(Icons.clear),
                      onPressed: _clear,
                    )
                  : null,
              filled: true,
              fillColor: widget.fillColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            ),
          ),
        ),
      ),
    );
  }
}
