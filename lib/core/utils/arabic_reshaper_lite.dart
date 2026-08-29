// 📁 lib/core/utils/arabic_reshaper_lite.dart
//
// ArabicReshaperLite — تشكيل مبسط للحروف العربية (للـ PDF).
// - يختار الشكل المناسب (isolated/initial/medial/final) حسب الجيران.
// - يدعم اللام-ألف (ﻻ ﻹ ﻷ ﻵ).
// - لا يعتمد على أي حزم خارجية.
//
// ملاحظة: هذا reshaper مبسط لكنه كافٍ للفواتير/التقارير.
// لو أردت دقة لغوية كاملة استخدم مكتبة خارجية عند توفرها.

class ArabicReshaperLite {
// Zero Width Joiner (نستخدمه بحالات نادرة)

  // أحرف لا تتصل بما بعدها (Non-joining on the left)
  static const Set<int> _nonJoiners = {
    0x0627, // ا
    0x062F, // د
    0x0630, // ذ
    0x0631, // ر
    0x0632, // ز
    0x0648, // و
    0x0622, // آ
    0x0623, // أ
    0x0625, // إ
    0x0671, // ٱ
    0x0629, // ة
    0x0649, // ى
  };

  // أحرف عربية أساسية ثنائية الإتصال
  static const Set<int> _arabicLetters = {
    // ا..ي (بدون التشكيل)
    0x0621, 0x0622, 0x0623, 0x0624, 0x0625, 0x0626,
    0x0627, 0x0628, 0x0629, 0x062A, 0x062B, 0x062C, 0x062D, 0x062E,
    0x062F, 0x0630, 0x0631, 0x0632, 0x0633, 0x0634, 0x0635, 0x0636,
    0x0637, 0x0638, 0x0639, 0x063A,
    0x0641, 0x0642, 0x0643, 0x0644, 0x0645, 0x0646, 0x0647, 0x0648, 0x0649,
    0x064A,
  };

  // خريطة الأشكال (isol, init, medi, fina)
  // (أخذت مجموعة شائعة تكفي للفواتير، ويمكن توسيعها لاحقًا)
  static const Map<int, List<int>> _forms = {
    0x0628: [0xFE8F, 0xFE91, 0xFE92, 0xFE90], // ب
    0x062A: [0xFE95, 0xFE97, 0xFE98, 0xFE96], // ت
    0x062B: [0xFE99, 0xFE9B, 0xFE9C, 0xFE9A], // ث
    0x062C: [0xFE9D, 0xFE9F, 0xFEA0, 0xFE9E], // ج
    0x062D: [0xFEA1, 0xFEA3, 0xFEA4, 0xFEA2], // ح
    0x062E: [0xFEA5, 0xFEA7, 0xFEA8, 0xFEA6], // خ
    0x0633: [0xFEB1, 0xFEB3, 0xFEB4, 0xFEB2], // س
    0x0634: [0xFEB5, 0xFEB7, 0xFEB8, 0xFEB6], // ش
    0x0635: [0xFEB9, 0xFEBB, 0xFEBC, 0xFEBA], // ص
    0x0636: [0xFEBD, 0xFEBF, 0xFEC0, 0xFEBE], // ض
    0x0637: [0xFEC1, 0xFEC3, 0xFEC4, 0xFEC2], // ط
    0x0638: [0xFEC5, 0xFEC7, 0xFEC8, 0xFEC6], // ظ
    0x0639: [0xFEC9, 0xFECB, 0xFECC, 0xFECA], // ع
    0x063A: [0xFECD, 0xFECF, 0xFED0, 0xFECE], // غ
    0x0641: [0xFED1, 0xFED3, 0xFED4, 0xFED2], // ف
    0x0642: [0xFED5, 0xFED7, 0xFED8, 0xFED6], // ق
    0x0643: [0xFED9, 0xFEDB, 0xFEDC, 0xFEDA], // ك
    0x0644: [0xFEDD, 0xFEDF, 0xFEE0, 0xFEDE], // ل
    0x0645: [0xFEE1, 0xFEE3, 0xFEE4, 0xFEE2], // م
    0x0646: [0xFEE5, 0xFEE7, 0xFEE8, 0xFEE6], // ن
    0x0647: [0xFEE9, 0xFEEB, 0xFEEC, 0xFEEA], // هـ
    0x064A: [0xFEF1, 0xFEF3, 0xFEF4, 0xFEF2], // ي
    0x0629: [0xFE93, 0xFE93, 0xFE94, 0xFE94], // ة (منفصل/نهائي)
    0x0649: [0xFEEF, 0xFBE8, 0xFBE9, 0xFEF0], // ى
    0x0627: [0xFE8D, 0xFE8D, 0xFE8E, 0xFE8E], // ا
    0x0623: [0xFE83, 0xFE83, 0xFE84, 0xFE84], // أ
    0x0625: [0xFE87, 0xFE87, 0xFE88, 0xFE88], // إ
    0x0622: [0xFE81, 0xFE81, 0xFE82, 0xFE82], // آ
    0x062F: [0xFEA9, 0xFEA9, 0xFEAA, 0xFEAA], // د
    0x0630: [0xFEAB, 0xFEAB, 0xFEAC, 0xFEAC], // ذ
    0x0631: [0xFEAD, 0xFEAD, 0xFEAE, 0xFEAE], // ر
    0x0632: [0xFEAF, 0xFEAF, 0xFEB0, 0xFEB0], // ز
    0x0648: [0xFEED, 0xFEED, 0xFEEE, 0xFEEE], // و
  };

  // لام-ألف ligatures
  static const Map<String, String> _lamAlef = {
    'لا': 'ﻻ',
    'لأ': 'ﻷ',
    'لإ': 'ﻹ',
    'لآ': 'ﻵ',
  };

  static bool _isArabicLetter(int cp) => _arabicLetters.contains(cp);

  static bool _canJoinToLeft(int cp) =>
      !_nonJoiners.contains(cp) && _isArabicLetter(cp);
  static bool _canJoinToRight(int cp) => _isArabicLetter(cp);

  static String reshape(String input) {
    if (input.isEmpty) return input;

    // عالج اللام-ألف أولًا
    String s = input;
    _lamAlef.forEach((k, v) {
      s = s.replaceAll(k, v);
    });

    final codepoints = s.runes.toList();
    final out = <int>[];

    for (int i = 0; i < codepoints.length; i++) {
      final curr = codepoints[i];

      if (!_isArabicLetter(curr) || !_forms.containsKey(curr)) {
        out.add(curr);
        continue;
      }

      int? prev;
      int? next;

      // تخطَّ الحركات والزيرو-ويتذ وغيرها عند الفحص
      int j = i - 1;
      while (j >= 0) {
        final cp = codepoints[j];
        if (_isArabicLetter(cp)) {
          prev = cp;
          break;
        }
        j--;
      }
      j = i + 1;
      while (j < codepoints.length) {
        final cp = codepoints[j];
        if (_isArabicLetter(cp)) {
          next = cp;
          break;
        }
        j++;
      }

      final joinLeft = prev != null && _canJoinToLeft(prev);
      final joinRight =
          next != null && _canJoinToRight(next) && !_nonJoiners.contains(curr);

      int formIndex;
      if (joinLeft && joinRight) {
        formIndex = 2; // medial
      } else if (joinLeft && !joinRight) {
        formIndex = 3; // final
      } else if (!joinLeft && joinRight) {
        formIndex = 1; // initial
      } else {
        formIndex = 0; // isolated
      }

      out.add(_forms[curr]![formIndex]);
    }

    return String.fromCharCodes(out);
  }
}
