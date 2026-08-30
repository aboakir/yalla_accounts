import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/settings/providers/workshop_settings_provider.dart';

class SidebarHeader extends ConsumerStatefulWidget {
  final bool isCollapsed;
  final VoidCallback onToggle;
  final bool showToggle;

  const SidebarHeader({
    super.key,
    required this.isCollapsed,
    required this.onToggle,
    this.showToggle = true,
  });

  @override
  ConsumerState<SidebarHeader> createState() => _SidebarHeaderState();
}

class _SidebarHeaderState extends ConsumerState<SidebarHeader> {
  String _appVersion = "1.0.0";

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() => _appVersion = info.version);
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(workshopSettingsProvider);

    String workshopName = "ورشة";
    String? logoPath;

    settingsAsync.when(
      data: (s) {
        workshopName = s.workshopName?.trim().isNotEmpty == true
            ? s.workshopName!
            : "ورشة";
        logoPath = s.logoPath;
      },
      loading: () {},
      error: (_, __) {},
    );

    return Container(
      padding: const EdgeInsets.only(top: 0, bottom: 5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // زر الطيّ — Desktop only. Mobile/tablet drawers stay expanded.
          if (widget.showToggle)
            Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                onTap: widget.onToggle,
                borderRadius: BorderRadius.circular(8),
                child: Ink(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: AnimatedRotation(
                      turns: widget.isCollapsed ? 0 : 0.5,
                      duration: const Duration(milliseconds: 160),
                      child: const Icon(
                        Icons.arrow_back_ios_new,
                        color: Colors.white,
                        size: 17,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          if (!widget.isCollapsed) ...[
            const SizedBox(height: 4),

            // الشعار — يتأقلم داخل مربع ثابت بدون فراغ
            _buildCompactLogo(logoPath),

            const SizedBox(height: 6),

            // اسم الورشة
            Text(
              workshopName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.primary,
                fontWeight: FontWeight.normal,
              ),
              overflow: TextOverflow.fade,
              maxLines: 1,
              softWrap: false,
            ),

            const SizedBox(height: 4),

            // رقم الإصدار
            Text(
              "v$_appVersion",
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[700],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ===============================
  // LOGO ADAPTIVE BOX (no empty space)
  // ===============================

  Widget _buildCompactLogo(String? logoPath) {
    const double boxSize = 70;

    return Container(
      width: boxSize,
      height: boxSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      clipBehavior: Clip.hardEdge,
      child: _loadLogoImage(logoPath),
    );
  }

  Widget _logoFallback() {
    return const Icon(Icons.store, size: 40, color: AppColors.primary);
  }

  Widget _loadLogoImage(String? logoPath) {
    final path = logoPath?.trim();
    if (path == null || path.isEmpty) return _logoFallback();

    // Assets المعروفة فقط تُحمّل من Flutter bundle.
    if (path.startsWith('assets/')) {
      return Image.asset(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _logoFallback(),
      );
    }

    // أي مسار اختاره المستخدم يُعامل كملف محلي فقط.
    // إذا نُقل/حُذف الملف لا نحاول تحويل مسار Windows إلى Asset.
    final file = File(path);
    if (!file.existsSync()) return _logoFallback();

    return Image.file(
      file,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _logoFallback(),
    );
  }
}
