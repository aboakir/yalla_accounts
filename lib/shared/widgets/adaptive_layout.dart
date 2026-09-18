import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/design/yalla_breakpoints.dart' as design;

/// Unified adaptive layout primitives for Yallah Accounts.
///
/// Breakpoints are deliberately shared across phone, tablet and desktop so
/// feature screens do not invent their own device thresholds.
abstract final class YallaBreakpoints {
  static const double phone = design.YallaBreakpoints.tablet;
  static const double desktop = design.YallaBreakpoints.desktop;
  static const double denseRowStack = 680;
}

enum YallaWindowClass { phone, tablet, desktop }

extension YallaAdaptiveContext on BuildContext {
  double get viewportWidth => MediaQuery.sizeOf(this).width;
  bool get isPhoneWidth => viewportWidth < YallaBreakpoints.phone;
  bool get isTabletWidth =>
      viewportWidth >= YallaBreakpoints.phone &&
      viewportWidth < YallaBreakpoints.desktop;
  bool get isDesktopWidth => viewportWidth >= YallaBreakpoints.desktop;

  YallaWindowClass get windowClass {
    if (isPhoneWidth) return YallaWindowClass.phone;
    if (isTabletWidth) return YallaWindowClass.tablet;
    return YallaWindowClass.desktop;
  }

  EdgeInsets get adaptivePagePadding {
    final width = viewportWidth;
    if (width < 360) return const EdgeInsets.all(10);
    if (width < YallaBreakpoints.phone) return const EdgeInsets.all(14);
    if (width < YallaBreakpoints.desktop) return const EdgeInsets.all(18);
    return const EdgeInsets.all(24);
  }
}

/// Row-compatible widget that preserves normal desktop layout but prevents the
/// common "desktop form squeezed into a phone" failure mode.
///
/// It stacks only rows that contain two or more direct Flex children when the
/// *available* width is narrow. Compact icon/text rows remain horizontal.
class AdaptiveRow extends StatelessWidget {
  const AdaptiveRow({
    super.key,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.mainAxisSize = MainAxisSize.max,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.textDirection,
    this.verticalDirection = VerticalDirection.down,
    this.textBaseline,
    this.children = const <Widget>[],
    this.stackBelow = YallaBreakpoints.denseRowStack,
  });

  final MainAxisAlignment mainAxisAlignment;
  final MainAxisSize mainAxisSize;
  final CrossAxisAlignment crossAxisAlignment;
  final TextDirection? textDirection;
  final VerticalDirection verticalDirection;
  final TextBaseline? textBaseline;
  final List<Widget> children;
  final double stackBelow;

  int get _directFlexCount =>
      children.where((child) => child is Flexible).length;

  Widget _unwrapForColumn(Widget child) {
    if (child is Expanded) return child.child;
    if (child is Flexible) return child.child;
    if (child is Spacer) return const SizedBox(height: 12);
    if (child is SizedBox && child.width != null && child.height == null) {
      final gap = child.width!.clamp(8.0, 20.0).toDouble();
      return SizedBox(height: gap);
    }
    return child;
  }

  WrapAlignment _wrapAlignment(MainAxisAlignment value) {
    return switch (value) {
      MainAxisAlignment.start => WrapAlignment.start,
      MainAxisAlignment.end => WrapAlignment.end,
      MainAxisAlignment.center => WrapAlignment.center,
      MainAxisAlignment.spaceBetween => WrapAlignment.spaceBetween,
      MainAxisAlignment.spaceAround => WrapAlignment.spaceAround,
      MainAxisAlignment.spaceEvenly => WrapAlignment.spaceEvenly,
    };
  }

  Widget _row() => Row(
        mainAxisAlignment: mainAxisAlignment,
        mainAxisSize: mainAxisSize,
        crossAxisAlignment: crossAxisAlignment,
        textDirection: textDirection,
        verticalDirection: verticalDirection,
        textBaseline: textBaseline,
        children: children,
      );

  @override
  Widget build(BuildContext context) {
    // The majority of Yalla rows are compact icon/text/action rows. Preserve
    // their exact Row behavior and avoid adding a LayoutBuilder unnecessarily.
    if (_directFlexCount < 2 && children.length < 4) return _row();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        final shouldStack = width < stackBelow && _directFlexCount >= 2;
        if (shouldStack) {
          final stacked =
              children.map(_unwrapForColumn).toList(growable: false);
          if (verticalDirection == VerticalDirection.up) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: stacked.reversed.toList(growable: false),
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: stacked,
          );
        }

        // Dense toolbar/action rows with no flex children may also overflow on
        // very small phones. Wrap only those long rows; ordinary 2-3 child rows
        // retain exact Row semantics.
        if (width < 520 && _directFlexCount == 0 && children.length >= 4) {
          return Wrap(
            alignment: _wrapAlignment(mainAxisAlignment),
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: children
                .where((child) => child is! Spacer)
                .toList(growable: false),
          );
        }

        return _row();
      },
    );
  }
}

/// DataTable-compatible wrapper. Tables remain full desktop tables on wide
/// screens and become horizontally scrollable inside the available viewport on
/// smaller screens instead of producing RenderFlex/viewport overflow.
class AdaptiveDataTable extends StatelessWidget {
  const AdaptiveDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.dataRowMinHeight,
    this.dataRowMaxHeight,
    this.dataRowHeight,
    this.headingRowHeight,
    this.headingRowColor,
    this.headingTextStyle,
    this.dataTextStyle,
    this.columnSpacing,
  });

  final List<DataColumn> columns;
  final List<DataRow> rows;
  final double? dataRowMinHeight;
  final double? dataRowMaxHeight;
  final double? dataRowHeight;
  final double? headingRowHeight;
  final dynamic headingRowColor;
  final TextStyle? headingTextStyle;
  final TextStyle? dataTextStyle;
  final double? columnSpacing;

  Widget _table() => DataTable(
        columns: columns,
        rows: rows,
        dataRowMinHeight: dataRowMinHeight,
        dataRowMaxHeight: dataRowMaxHeight,
        dataRowHeight: dataRowHeight,
        headingRowHeight: headingRowHeight,
        headingRowColor: headingRowColor,
        headingTextStyle: headingTextStyle,
        dataTextStyle: dataTextStyle,
        columnSpacing: columnSpacing,
      );

  String _columnLabel(DataColumn column, int index) {
    final label = column.label;
    if (label is Text) {
      final value = label.data?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return 'بيان ${index + 1}';
  }

  Widget _phoneCards(BuildContext context) {
    if (rows.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8E4)),
        ),
        child: const Text(
          'لا توجد بيانات',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF66736C)),
        ),
      );
    }

    final theme = Theme.of(context);
    return Column(
      children: List.generate(rows.length, (rowIndex) {
        final row = rows[rowIndex];
        final count = row.cells.length < columns.length
            ? row.cells.length
            : columns.length;

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: row.onSelectChanged == null
                ? null
                : () => row.onSelectChanged!(true),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                children: List.generate(count, (cellIndex) {
                  final cell = row.cells[cellIndex];
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: cellIndex == count - 1 ? 0 : 10,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 92,
                          child: Text(
                            _columnLabel(columns[cellIndex], cellIndex),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF6A756F),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: cell.child),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        // Phone is a real card/list experience, never a squeezed desktop table.
        if (width < YallaBreakpoints.phone) return _phoneCards(context);

        // Tablet keeps the information-dense table, with safe horizontal scroll.
        if (width < YallaBreakpoints.desktop) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            primary: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: width),
              child: _table(),
            ),
          );
        }

        return _table();
      },
    );
  }
}

/// Dialog surface that preserves the desktop dimensions but becomes a
/// viewport-safe page-like surface on phones and compact tablets.
class AdaptiveDialogSurface extends StatelessWidget {
  const AdaptiveDialogSurface({
    super.key,
    required this.child,
    required this.desktopWidth,
    required this.desktopHeight,
    this.padding = const EdgeInsets.all(24),
  });

  final Widget child;
  final double desktopWidth;
  final double desktopHeight;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final insets = MediaQuery.viewInsetsOf(context);
    final compact = size.width < YallaBreakpoints.phone;
    final horizontalInset = compact ? 12.0 : 40.0;
    final verticalInset = compact ? 12.0 : 24.0;
    final maxWidth = (size.width - (horizontalInset * 2))
        .clamp(240.0, desktopWidth)
        .toDouble();
    final maxHeight = (size.height - insets.bottom - (verticalInset * 2))
        .clamp(280.0, desktopHeight)
        .toDouble();

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: verticalInset,
      ),
      child: SizedBox(
        width: maxWidth,
        height: maxHeight,
        child: Padding(
          padding: compact ? const EdgeInsets.all(16) : padding,
          child: child,
        ),
      ),
    );
  }
}

/// AlertDialog-compatible wrapper used throughout the product. It applies
/// phone-safe insets and enables vertical scrolling on compact viewports.
class AdaptiveAlertDialog extends StatelessWidget {
  const AdaptiveAlertDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.actionsAlignment,
    this.actionsPadding,
  });

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final MainAxisAlignment? actionsAlignment;
  final EdgeInsetsGeometry? actionsPadding;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final insets = MediaQuery.viewInsetsOf(context);
    final compact = size.width < YallaBreakpoints.phone;
    final maxContentWidth =
        compact ? (size.width - 32).clamp(240.0, 560.0).toDouble() : 640.0;
    final maxContentHeight = compact
        ? (size.height - insets.bottom - 120).clamp(220.0, 760.0).toDouble()
        : double.infinity;

    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 40,
        vertical: compact ? 12 : 24,
      ),
      scrollable: compact,
      title: title,
      content: content == null
          ? null
          : ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxContentWidth,
                maxHeight: maxContentHeight,
              ),
              child: content!,
            ),
      actions: actions,
      actionsAlignment: actionsAlignment,
      actionsPadding: actionsPadding,
    );
  }
}
