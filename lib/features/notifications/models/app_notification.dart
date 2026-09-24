enum AppNotificationPriority { normal, urgent }

enum AppNotificationStatus { newItem, unread, urgent, overdue, handled }

class AppNotification {
  const AppNotification({
    required this.key,
    required this.sourceType,
    required this.sourceId,
    required this.timestamp,
    required this.priority,
    required this.status,
    required this.message,
    required this.route,
    this.title,
    this.arguments = const <String, Object?>{},
    this.isRead = false,
  });

  final String key;
  final String sourceType;
  final String sourceId;
  final DateTime timestamp;
  final AppNotificationPriority priority;
  final AppNotificationStatus status;
  final String message;
  final String route;
  final String? title;
  final Map<String, Object?> arguments;
  final bool isRead;

  bool get isHandled => status == AppNotificationStatus.handled;
  bool get countsTowardBadge => !isRead && !isHandled;

  AppNotification copyWith({
    AppNotificationPriority? priority,
    AppNotificationStatus? status,
    bool? isRead,
  }) =>
      AppNotification(
        key: key,
        sourceType: sourceType,
        sourceId: sourceId,
        timestamp: timestamp,
        priority: priority ?? this.priority,
        status: status ?? this.status,
        message: message,
        route: route,
        title: title,
        arguments: arguments,
        isRead: isRead ?? this.isRead,
      );
}
