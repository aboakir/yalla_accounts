import 'package:pdf/widgets.dart' as pw;

/// Isolates Latin identifiers/numbers from the Arabic shaping pass.
/// Each token keeps its logical spelling; Wrap handles RTL line ordering.
class ArabicPdfText {
  static pw.Widget build(String value,
      {required pw.TextStyle style, required pw.Font latin}) {
    final hasArabic = RegExp(r'[\u0600-\u06ff]').hasMatch(value);
    if (!hasArabic)
      return pw.Text(value,
          textDirection: pw.TextDirection.ltr,
          textAlign: pw.TextAlign.right,
          style: style.copyWith(font: latin));
    if (!RegExp(r'[A-Za-z0-9]').hasMatch(value)) {
      return pw.Text(value,
          textDirection: pw.TextDirection.rtl,
          textAlign: pw.TextAlign.right,
          style: style);
    }
    final tokens = <String>[];
    for (final token in value.trim().split(RegExp(r'\s+'))) {
      final latinWord = RegExp(r'^[A-Za-z0-9][A-Za-z0-9.,:/@_+()\-]*$');
      if (tokens.isNotEmpty &&
          latinWord.hasMatch(token) &&
          tokens.last.split(' ').every(latinWord.hasMatch)) {
        tokens[tokens.length - 1] = '${tokens.last} $token';
      } else {
        tokens.add(token);
      }
    }
    return pw.Directionality(
        textDirection: pw.TextDirection.rtl,
        child: pw.Wrap(
            alignment: pw.WrapAlignment.start,
            spacing: (style.fontSize ?? 10) * .25,
            runSpacing: 2,
            children: tokens.map((token) {
              final arabic = RegExp(r'[\u0600-\u06ff]').hasMatch(token);
              return pw.Text(token,
                  textDirection:
                      arabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                  style: arabic ? style : style.copyWith(font: latin));
            }).toList()));
  }
}
