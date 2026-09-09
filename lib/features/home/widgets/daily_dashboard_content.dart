import 'dart:async';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/storage/yalla_stored_image.dart';
import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/design/yalla_design_tokens.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import '../services/daily_dashboard_service.dart';

class DailyDashboardContent extends StatelessWidget {
  const DailyDashboardContent(
      {super.key,
      required this.data,
      required this.period,
      required this.onPeriod,
      required this.onOpen,
      required this.onEntry});
  final DailyDashboardData data;
  final DashboardPeriod period;
  final ValueChanged<DashboardPeriod> onPeriod;
  final void Function(String route, String? repairId) onOpen;
  final VoidCallback onEntry;

  @override
  Widget build(BuildContext context) {
    final steps = DailyDashboardService.recommendations(data, period);
    final alerts = [
      ...data.issues,
      ...steps.where(
          (s) => s.priority >= 75 && !data.issues.any((i) => i.id == s.id))
    ].take(3).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _card(child: LayoutBuilder(builder: (context, box) {
        final metrics = [
          _amount(
              'صافي اليوم',
              data.money(data.today.receipts - data.today.payments),
              'المقبوضات − المدفوعات',
              YallaColors.brand),
          _amount('جاهز للتحصيل', data.money(data.readyAmount),
              'متبقي الملفات الجاهزة', YallaColors.brandDark),
        ];
        final summary = box.maxWidth < 300 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.4
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [metrics[0], const Divider(height: 28), metrics[1]])
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: metrics[0]),
                const SizedBox(width: 16),
                Expanded(child: metrics[1])
              ]);
        return Column(children: [
          summary,
          const Divider(height: 20),
          Wrap(spacing: 20, runSpacing: 4, children: [
            Text('قبض ${data.money(data.today.receipts)}',
                style: const TextStyle(
                    fontSize: 12, color: YallaColors.brandDark)),
            Text('صرف ${data.money(data.today.payments)}',
                style:
                    const TextStyle(fontSize: 12, color: YallaColors.danger)),
          ])
        ]);
      })),
      const SizedBox(height: 18),
      BestStepCard(
          steps: steps, period: period, onPeriod: onPeriod, onOpen: onOpen),
      _heading('مراحل إصلاح السيارات'),
      if (data.cars.isEmpty)
        const Text('لا توجد سيارات قيد العمل.',
            style: TextStyle(color: YallaColors.textMuted))
      else
        SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final stage in data.cars.map((c) => c.stage).toSet())
                Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ActionChip(
                        avatar:
                            const Icon(Icons.directions_car_outlined, size: 18),
                        label: Text(
                            '$stage · ${data.cars.where((c) => c.stage == stage).length}'),
                        onPressed: () => _showCars(context, stage))),
            ])),
      _heading('إجراءات سريعة'),
      LayoutBuilder(builder: (context, box) {
        final columns = box.maxWidth < 330 ? 2 : 3;
        final items = <(String, IconData, Color, String)>[
          (
            'ملف إصلاح',
            Icons.car_repair,
            YallaColors.brand,
            AppRoutes.repairsAdd
          ),
          (
            'سند قبض',
            Icons.south_west,
            YallaColors.brandDark,
            AppRoutes.receiptVoucher
          ),
          (
            'سند صرف',
            Icons.north_east,
            YallaColors.danger,
            AppRoutes.paymentVoucher
          ),
          (
            'مشتريات',
            Icons.shopping_bag_outlined,
            YallaColors.warning,
            AppRoutes.purchaseCreate
          ),
          (
            'حاسبة التأمين',
            Icons.calculate_outlined,
            YallaColors.info,
            AppRoutes.insuranceAgentCalculator
          ),
          (
            'عميل / مورد',
            Icons.people_outline,
            YallaColors.textMuted,
            AppRoutes.clients
          ),
        ];
        return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items
                .map((item) => SizedBox(
                    width: (box.maxWidth - 8 * (columns - 1)) / columns,
                    child: Material(
                        color: item.$3.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(YallaRadii.control),
                        child: InkWell(
                            borderRadius:
                                BorderRadius.circular(YallaRadii.control),
                            onTap: () => item.$1 == 'عميل / مورد'
                                ? _party(context)
                                : onOpen(item.$4, null),
                            child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 10),
                                child: Column(children: [
                                  Icon(item.$2, color: item.$3),
                                  const SizedBox(height: 4),
                                  Text(item.$1,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: item.$3,
                                          fontWeight: FontWeight.w700)),
                                ]))))))
                .toList());
      }),
      Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Row(children: [
            const Expanded(
                child: Text('آخر ملفات الإصلاح',
                    style:
                        TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
            TextButton(
                onPressed: () => onOpen(AppRoutes.repairs, null),
                child: const Text('عرض الكل')),
          ])),
      _card(
          child: data.recentFiles.isEmpty
              ? const Text('ستظهر ملفات الإصلاح هنا بعد إضافتها.',
                  style: TextStyle(color: YallaColors.textMuted))
              : Column(children: [
                  for (final file in data.recentFiles) ...[
                    if (file != data.recentFiles.first)
                      const Divider(height: 1),
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _RepairThumbnail(id: '${file['id']}'),
                        title: Text(
                            [
                              file['vehicleType'],
                              file['vehicleModel'],
                              file['vehicleNumber']
                            ]
                                .where((v) => v != null && '$v'.isNotEmpty)
                                .join(' • '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                            [
                              file['beneficiaryName'],
                              file['vehicleStatus'],
                              file['receivedDate']
                            ]
                                .where((v) => v != null && '$v'.isNotEmpty)
                                .join(' • '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: () =>
                            onOpen(AppRoutes.repairs, '${file['id']}')),
                  ]
                ])),
      if (alerts.isNotEmpty) ...[
        _heading('يحتاج انتباهك'),
        _card(
            child: Column(children: [
          for (final s in alerts)
            ListTile(
                contentPadding: EdgeInsets.zero,
                leading:
                    const Icon(Icons.info_outline, color: YallaColors.warning),
                title: Text(s.title),
                subtitle: Text(s.reason,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => onOpen(s.route, s.repairId))
        ])),
      ],
      _heading('حركة اليوم المالية', subtitle: 'حركات اليوم من دفتر الأستاذ'),
      _card(
          child: Column(children: [
        _line('المقبوضات', data.money(data.today.receipts),
            YallaColors.brandDark),
        const Divider(height: 24),
        _line('المدفوعات', data.money(data.today.payments), YallaColors.danger),
        const Divider(height: 24),
        _line('الصندوق الآن', data.money(data.today.cashBalance),
            YallaColors.text),
        const Divider(height: 24),
        _line(
            'البنك الآن', data.money(data.today.bankBalance), YallaColors.text),
      ])),
      _heading('آخر حركة موثقة'),
      _card(
          child: data.lastEntry == null
              ? const Text('لا توجد حركة مالية موثقة بعد.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                      Text('${data.lastEntry!['note'] ?? 'حركة مالية'}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(
                          'المرجع: ${data.lastEntry!['ref'] ?? data.lastEntry!['source_number'] ?? data.lastEntry!['id']}'),
                      Text(
                          '${data.lastEntry!['created_at'] ?? data.lastEntry!['date']}',
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.right),
                      Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: TextButton.icon(
                              onPressed: onEntry,
                              icon: const Icon(Icons.receipt_long_outlined),
                              label: const Text('عرض القيد والمستند'))),
                    ])),
    ]);
  }

  void _party(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => Directionality(
          textDirection: TextDirection.rtl,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final item in [
              ('عميل', AppRoutes.clientAdd),
              ('مورد', AppRoutes.supplierAdd)
            ])
              ListTile(
                  title: Text('إضافة ${item.$1}'),
                  leading: const Icon(Icons.person_add_outlined),
                  onTap: () {
                    Navigator.pop(sheet);
                    onOpen(item.$2, null);
                  }),
          ])));
  void _showCars(BuildContext context, String stage) => showModalBottomSheet<
          void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => Directionality(
          textDirection: TextDirection.rtl,
          child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .6,
              child: Column(children: [
                Text(stage,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                Expanded(
                    child: ListView(children: [
                  for (final car in data.cars.where((c) => c.stage == stage))
                    ListTile(
                        leading: FutureBuilder<String?>(
                            future: DBService.getRepairThumbnailPath(car.id),
                            builder: (context, snapshot) => YallaStoredImage(
                                storedPath: snapshot.data,
                                width: 40,
                                height: 40,
                                fallback: const Icon(
                                    Icons.directions_car_filled_rounded))),
                        title: Text(car.name.isEmpty ? 'ملف إصلاح' : car.name),
                        subtitle: Text('المتبقي ${data.money(car.remaining)}'),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: () {
                          Navigator.pop(sheet);
                          onOpen(AppRoutes.repairs, car.id);
                        }),
                ]))
              ]))));
  static Widget _card({required Widget child}) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: YallaColors.surface,
          borderRadius: BorderRadius.circular(YallaRadii.card),
          border: Border.all(color: YallaColors.border)),
      child: child);
  static Widget _heading(String title, {String? subtitle}) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        if (subtitle != null)
          Text(subtitle,
              style:
                  const TextStyle(color: YallaColors.textMuted, fontSize: 12))
      ]));
  static Widget _amount(
          String title, String amount, String note, Color color) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(amount,
            textDirection: TextDirection.ltr,
            style: TextStyle(
                fontSize: 24, color: color, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(note,
            style: const TextStyle(fontSize: 11, color: YallaColors.textMuted)),
      ]);
  static Widget _line(String label, String amount, Color color) =>
      Row(children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 8),
        Flexible(
            child: Text(amount,
                textDirection: TextDirection.ltr,
                style: TextStyle(color: color, fontWeight: FontWeight.w700)))
      ]);
}

class BestStepCard extends StatefulWidget {
  const BestStepCard(
      {super.key,
      required this.steps,
      required this.period,
      required this.onPeriod,
      required this.onOpen});
  final List<DashboardStep> steps;
  final DashboardPeriod period;
  final ValueChanged<DashboardPeriod> onPeriod;
  final void Function(String, String?) onOpen;
  @override
  State<BestStepCard> createState() => _BestStepCardState();
}

class _BestStepCardState extends State<BestStepCard>
    with WidgetsBindingObserver {
  Timer? _timer;
  int _index = 0;
  bool _active = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restart();
  }

  void _restart() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted &&
          _active &&
          (ModalRoute.of(context)?.isCurrent ?? true) &&
          !MediaQuery.of(context).disableAnimations &&
          !MediaQuery.of(context).accessibleNavigation) {
        setState(() => _index = (_index + 1) % widget.steps.length);
      }
    });
  }

  @override
  void didUpdateWidget(covariant BestStepCard old) {
    super.didUpdateWidget(old);
    if (old.period != widget.period) {
      _index = 0;
      _restart();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _go(int index) {
    setState(
        () => _index = (index + widget.steps.length) % widget.steps.length);
    _restart();
  }

  Future<void> _details(DashboardStep step) async {
    _active = false;
    await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheet) => Directionality(
            textDirection: TextDirection.rtl,
            child: SingleChildScrollView(
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(step.title,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          Text(step.reason),
                          const SizedBox(height: 12),
                          Text(step.impact,
                              style: const TextStyle(
                                  color: YallaColors.brandDark)),
                          const SizedBox(height: 16),
                          FilledButton(
                              onPressed: () {
                                Navigator.pop(sheet);
                                widget.onOpen(step.route, step.repairId);
                              },
                              child: Text(step.action)),
                        ])))));
    if (mounted) {
      _active = true;
      _restart();
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_index];
    return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: YallaColors.successSurface,
            borderRadius: BorderRadius.circular(YallaRadii.card),
            border: Border.all(color: YallaColors.brand.withValues(alpha: .4))),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Row(children: [
            Icon(Icons.bolt_rounded, color: YallaColors.brand),
            SizedBox(width: 6),
            Expanded(
                child: Text('أفضل خطوة',
                    style:
                        TextStyle(fontWeight: FontWeight.w900, fontSize: 18)))
          ]),
          const SizedBox(height: 4),
          Wrap(
              spacing: 8,
              runSpacing: 4,
              children: DashboardPeriod.values
                  .map((p) => ChoiceChip(
                      label: Text(p.label),
                      selected: widget.period == p,
                      onSelected: (_) => widget.onPeriod(p)))
                  .toList()),
          const SizedBox(height: 6),
          GestureDetector(
              onTap: () => _details(step),
              onHorizontalDragEnd: (details) =>
                  _go(_index + ((details.primaryVelocity ?? 0) > 0 ? 1 : -1)),
              child: AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.topCenter,
                  child: Column(
                      key: ValueKey(step.id),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(step.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                height: 1.3)),
                        const SizedBox(height: 8),
                        Text(step.reason,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                height: 1.6, color: YallaColors.text)),
                        const SizedBox(height: 4),
                        Row(children: [
                          Expanded(
                              child: Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: FilledButton(
                                      onPressed: () => widget.onOpen(
                                          step.route, step.repairId),
                                      child: Text(step.action)))),
                          for (var i = 0; i < widget.steps.length; i++)
                            Semantics(
                                label:
                                    'الخطوة ${i + 1} من ${widget.steps.length}',
                                selected: i == _index,
                                button: true,
                                child: InkWell(
                                    onTap: () => _go(i),
                                    child: SizedBox(
                                        width: 48,
                                        height: 48,
                                        child: Center(
                                            child: Container(
                                                width: i == _index ? 18 : 6,
                                                height: 6,
                                                decoration: BoxDecoration(
                                                    color: i == _index
                                                        ? YallaColors.brand
                                                        : YallaColors.border,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4))))))),
                        ]),
                      ]))),
        ]));
  }
}

class _RepairThumbnail extends StatefulWidget {
  const _RepairThumbnail({required this.id});
  final String id;
  @override
  State<_RepairThumbnail> createState() => _RepairThumbnailState();
}

class _RepairThumbnailState extends State<_RepairThumbnail> {
  late Future<String?> _path;
  @override
  void initState() {
    super.initState();
    _path = DBService.getRepairThumbnailPath(widget.id);
  }

  @override
  void didUpdateWidget(covariant _RepairThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _path = DBService.getRepairThumbnailPath(widget.id);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
      future: _path,
      builder: (context, snapshot) => YallaStoredImage(
          storedPath: snapshot.data,
          width: 48,
          height: 48,
          borderRadius: BorderRadius.circular(12),
          fallback:
              const Icon(Icons.directions_car, color: YallaColors.brand)));
}
