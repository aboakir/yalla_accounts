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
    sha256: '63e269d87e39c6a375179e3b9084c997ede81f2c8438aae7e855bb112aa170a2',
  );

  static const privacy = LocalLegalDocument(
    id: 'privacy_ps',
    title: 'سياسة الخصوصية',
    version: 'privacy_ps_v1',
    assetPath: 'assets/legal/privacy_ps_v1.html',
    sha256: 'fd4d27a032b7103682334eb9bbedbe704a1d567e96a66fee2a02c92c51ee4080',
  );

  static const deletion = LocalLegalDocument(
    id: 'deletion_ps',
    title: 'حذف الحساب والبيانات',
    version: 'deletion_ps_v1',
    assetPath: 'assets/legal/account_deletion_ps_v1.html',
    sha256: '704ac6b2c8fbfa667c6af5a39c9f77904c956dae9fac42dcff4feb35816695c8',
  );

  static const refund = LocalLegalDocument(
    id: 'refund_ps',
    title: 'الإلغاء والاسترداد',
    version: 'refund_ps_v1',
    assetPath: 'assets/legal/refund_ps_v1.html',
    sha256: '44c19a098c8a231e94c94598ea4866e0eebbd1e8f81a6c5987e6e8b0a35b5c61',
  );

  static const support = LocalLegalDocument(
    id: 'support_ps',
    title: 'الدعم والشكاوى',
    version: 'support_ps_v1',
    assetPath: 'assets/legal/support_ps_v1.html',
    sha256: 'a64ab7b0478c633711e454392318b6f71446d27c02f412e82862b30056044b06',
  );

  static const contact = LocalLegalDocument(
    id: 'contact_ps',
    title: 'اتصل بنا',
    version: 'contact_ps_v1',
    assetPath: 'assets/legal/contact_ps_v1.html',
    sha256: 'fda201c8d3fe1120fd1ab487fd57699efc21ea3ebe8dda0d6646743f43e9c828',
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
