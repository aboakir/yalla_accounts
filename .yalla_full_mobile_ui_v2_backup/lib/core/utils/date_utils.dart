import 'package:intl/intl.dart';

class DateUtilsHelper {
  static String formatDate(DateTime date, {String pattern = 'yyyy-MM-dd'}) {
    return DateFormat(pattern, 'ar').format(date);
  }

  static String formatReadable(DateTime date) {
    return DateFormat.yMMMMEEEEd('ar')
        .format(date); // مثلاً: الجمعة، 23 مايو 2025
  }

  static String formatTime(DateTime date) {
    return DateFormat.Hm('ar').format(date); // 23:10
  }

  static String timeAgo(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) return '${difference.inDays} يوم';
    if (difference.inHours > 0) return '${difference.inHours} ساعة';
    if (difference.inMinutes > 0) return '${difference.inMinutes} دقيقة';
    return 'الآن';
  }
}
