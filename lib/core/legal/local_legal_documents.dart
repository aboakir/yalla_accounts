import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LocalLegalDocument {
  const LocalLegalDocument({
    required this.id,
    required this.title,
    required this.version,
    required this.assetPath,
    required this.sha256,
  });

  final String id;
  final String title;
  final String version;
  final String assetPath;
  final String sha256;
}

class LocalLegalDocuments {
  const LocalLegalDocuments._();

  static const effectiveDate = '18/09/2026';

  static const terms = LocalLegalDocument(
    id: 'terms_ps',
    title: 'شروط الاستخدام',
    version: 'terms_ps_v1',
    assetPath: 'assets/legal/terms_ps_v1.html',
    sha256: 'e27f079b68546ce1c428e3368910d3e911a01a04d4944cc2a0a35efd3ec70c58',
  );

  static const privacy = LocalLegalDocument(
    id: 'privacy_ps',
    title: 'سياسة الخصوصية',
    version: 'privacy_ps_v1',
    assetPath: 'assets/legal/privacy_ps_v1.html',
    sha256: '97e602c2dc38fb4e78d465c193cd53f473ed955fd94441da40ccf918461b02b5',
  );

  static const deletion = LocalLegalDocument(
    id: 'deletion_ps',
    title: 'حذف الحساب والبيانات',
    version: 'deletion_ps_v1',
    assetPath: 'assets/legal/account_deletion_ps_v1.html',
    sha256: '35846e89cbcebdf782bd08a176baeceed58175a45dc1dbc75050b846d215f16a',
  );

  static const refund = LocalLegalDocument(
    id: 'refund_ps',
    title: 'الإلغاء والاسترداد',
    version: 'refund_ps_v1',
    assetPath: 'assets/legal/refund_ps_v1.html',
    sha256: 'd1e99ce368d53314409458c6f8bacf8fea2b1df62f184ad417abba251f1b446e',
  );

  static const support = LocalLegalDocument(
    id: 'support_ps',
    title: 'الدعم والشكاوى',
    version: 'support_ps_v1',
    assetPath: 'assets/legal/support_ps_v1.html',
    sha256: '9e322daa206711c1d6341399045f41d4a8726409ae1add80d0b5a7248a18bc65',
  );

  static const contact = LocalLegalDocument(
    id: 'contact_ps',
    title: 'اتصل بنا',
    version: 'contact_ps_v1',
    assetPath: 'assets/legal/contact_ps_v1.html',
    sha256: '131ba72b11c20ca094609c774094c7fd64bd4b31fc42145333ba5ad3791e081c',
  );

  static const all = <LocalLegalDocument>[
    terms,
    privacy,
    deletion,
    refund,
    support,
    contact,
  ];
}

class LocalLegalDocumentScreen extends StatelessWidget {
  const LocalLegalDocumentScreen({super.key, required this.document});

  final LocalLegalDocument document;

  String _plainText(String html) {
    var body = html;
    final bodyMatch = RegExp(
      r'<body[^>]*>([\s\S]*?)<\/body>',
      caseSensitive: false,
    ).firstMatch(html);
    if (bodyMatch != null) body = bodyMatch.group(1)!;

    body = body
        .replaceAll(RegExp(r'<\s*br\s*\/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<\s*\/\s*p\s*>', caseSensitive: false), '\n\n')
        .replaceAll(
            RegExp(r'<\s*\/\s*h[1-6]\s*>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<\s*li[^>]*>', caseSensitive: false), '• ')
        .replaceAll(RegExp(r'<\s*\/\s*li\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\n[ \t]+'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return body.trim();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(document.title)),
        body: FutureBuilder<String>(
          future: rootBundle.loadString(document.assetPath),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || snapshot.data == null) {
              return const Center(
                child: Text('تعذر فتح الوثيقة القانونية المحلية.'),
              );
            }
            final text = _plainText(snapshot.data!);
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  '${document.title} — ${document.version}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text('تاريخ السريان: ${LocalLegalDocuments.effectiveDate}'),
                const Divider(height: 28),
                SelectableText(
                  text,
                  style: const TextStyle(fontSize: 16, height: 1.8),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
