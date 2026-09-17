import 'package:flutter/material.dart';

import 'package:yalla_accounts/core/services/sync/sync_state_service.dart';
import 'package:yalla_accounts/core/services/sync/unified_sync_coordinator_v3.dart';

/// Compact P04 sync-state indicator shown above the phone bottom navigation.
class YallaSyncStatusStrip extends StatelessWidget {
  const YallaSyncStatusStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<YallaSyncSnapshot>(
      valueListenable: SyncStateService.instance.listenable,
      builder: (context, snapshot, _) {
        final colors = Theme.of(context).colorScheme;
        final presentation = _presentation(snapshot, colors);

        return Semantics(
          label: 'حالة المزامنة: ${presentation.label}',
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 26),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: presentation.background,
              border: Border(
                bottom: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: .45),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  presentation.icon,
                  size: 14,
                  color: presentation.foreground,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    presentation.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                      color: presentation.foreground,
                    ),
                  ),
                ),
                if (snapshot.transportConfigured &&
                    (snapshot.phase == YallaSyncPhase.failed ||
                        snapshot.phase == YallaSyncPhase.offline)) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () async {
                      await UnifiedSyncCoordinatorV3.instance.cycle();
                      await SyncStateService.instance.refresh();
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Text(
                        'إعادة المحاولة',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: presentation.foreground,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  _SyncPresentation _presentation(
    YallaSyncSnapshot snapshot,
    ColorScheme colors,
  ) {
    switch (snapshot.phase) {
      case YallaSyncPhase.checking:
        return _SyncPresentation(
          icon: Icons.sync_rounded,
          label: 'فحص حالة الحفظ...',
          background: colors.surfaceContainerHighest,
          foreground: colors.onSurfaceVariant,
        );
      case YallaSyncPhase.syncing:
        return _SyncPresentation(
          icon: Icons.sync_rounded,
          label: snapshot.pendingCount > 0
              ? 'جارٍ المزامنة • ${snapshot.pendingCount} متبقي'
              : 'جارٍ المزامنة',
          background: colors.primaryContainer,
          foreground: colors.onPrimaryContainer,
        );
      case YallaSyncPhase.synced:
        return _SyncPresentation(
          icon: Icons.cloud_done_outlined,
          label: 'متزامن',
          background: colors.primaryContainer,
          foreground: colors.onPrimaryContainer,
        );
      case YallaSyncPhase.offline:
        return _SyncPresentation(
          icon: Icons.cloud_off_outlined,
          label: snapshot.pendingCount > 0
              ? 'بدون اتصال • محفوظ محليًا • ${snapshot.pendingCount} معلّق'
              : 'بدون اتصال • البيانات محفوظة محليًا',
          background: colors.secondaryContainer,
          foreground: colors.onSecondaryContainer,
        );
      case YallaSyncPhase.failed:
        return _SyncPresentation(
          icon: Icons.sync_problem_rounded,
          label: snapshot.pendingCount > 0
              ? 'تعذرت المزامنة • ${snapshot.pendingCount} محفوظ محليًا'
              : 'تعذرت المزامنة • البيانات محفوظة محليًا',
          background: colors.errorContainer,
          foreground: colors.onErrorContainer,
        );
      case YallaSyncPhase.pending:
        return _SyncPresentation(
          icon: Icons.cloud_upload_outlined,
          label: '${snapshot.pendingCount} بانتظار المزامنة',
          background: colors.tertiaryContainer,
          foreground: colors.onTertiaryContainer,
        );
      case YallaSyncPhase.localOnly:
        return _SyncPresentation(
          icon: snapshot.pendingCount > 0
              ? Icons.cloud_queue_rounded
              : Icons.save_outlined,
          label: snapshot.pendingCount > 0
              ? 'محفوظ محليًا • ${snapshot.pendingCount} بانتظار المزامنة'
              : 'محفوظ محليًا',
          background: colors.surfaceContainerHighest,
          foreground: colors.onSurfaceVariant,
        );
    }
  }
}

class _SyncPresentation {
  const _SyncPresentation({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
}
