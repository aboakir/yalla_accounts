// 📁 lib/core/providers/timeline_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// نموذج حدث زمني (Timeline Event)
class TimelineEvent {
  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final String status;

  TimelineEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.status,
  });
}

/// نموذج لبيانات الملخص الزمني يحتوي قائمة بالأحداث
class TimelineStats {
  final List<TimelineEvent> events;

  TimelineStats({
    required this.events,
  });
}

/// Provider لجلب بيانات الملخص الزمني من الخدمة
final timelineProvider = FutureProvider<TimelineStats>((ref) async {
  final service = TimelineService();
  final raw = await service.getTimelineStats();
  return TimelineStats(
    events: raw
        .map((e) => TimelineEvent(
              id: e.id,
              title: e.title,
              start: e.start,
              end: e.end,
              status: e.status,
            ))
        .toList(),
  );
});

TimelineService() {
}
