// 📁 lib/features/home/models/kpi_item.dart

class KPIItem {
  final String title;
  final num value;
  final bool highlight;

  KPIItem({
    required this.title,
    required this.value,
    this.highlight = false,
  });

  KPIItem copyWith({
    String? title,
    num? value,
    bool? highlight,
  }) {
    return KPIItem(
      title: title ?? this.title,
      value: value ?? this.value,
      highlight: highlight ?? this.highlight,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'value': value,
      'highlight': highlight ? 1 : 0,
    };
  }

  factory KPIItem.fromMap(Map<String, dynamic> map) {
    return KPIItem(
      title: map['title'] as String? ?? '',
      value: map['value'] as num? ?? 0,
      highlight: (map['highlight'] as int? ?? 0) == 1,
    );
  }
}
