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

  static const effectiveDate = '25/09/2026';

  static const terms = LocalLegalDocument(
    id: 'terms_ps',
    title: 'شروط الاستخدام',
    version: 'terms_ps_v2',
    assetPath: 'assets/legal/terms_ps_v2.html',
    sha256: '29e41d52985a4aa48f585ec30ef149806483d4ff21661525f03f0f5c3f125502',
  );

  static const privacy = LocalLegalDocument(
    id: 'privacy_ps',
    title: 'سياسة الخصوصية',
    version: 'privacy_ps_v2',
    assetPath: 'assets/legal/privacy_ps_v2.html',
    sha256: '2c2a92f9665f466d725a16e733ea3c9142bbb113bd8e1914df9f4116fc754890',
  );

  static const deletion = LocalLegalDocument(
    id: 'deletion_ps',
    title: 'حذف الحساب والبيانات',
    version: 'deletion_ps_v2',
    assetPath: 'assets/legal/account_deletion_ps_v2.html',
    sha256: 'c052c1aafc08b0ae0ee56d76987506c2df22e279e2e2d7da85e51548d3de90b3',
  );

  static const refund = LocalLegalDocument(
    id: 'refund_ps',
    title: 'الإلغاء والاسترداد',
    version: 'refund_ps_v2',
    assetPath: 'assets/legal/refund_ps_v2.html',
    sha256: '8c6ebdc170eaf194f3c512cb807b2548c51fa9aecc545c37beb27b1f2c29c956',
  );

  static const support = LocalLegalDocument(
    id: 'support_ps',
    title: 'الدعم والشكاوى',
    version: 'support_ps_v2',
    assetPath: 'assets/legal/support_ps_v2.html',
    sha256: '4337f2538d1afcfe10aca0bdb6c7932a07f9b8c8eccee7f562d39fd19d8a3a86',
  );

  static const contact = LocalLegalDocument(
    id: 'contact_ps',
    title: 'اتصل بنا',
    version: 'contact_ps_v2',
    assetPath: 'assets/legal/contact_ps_v2.html',
    sha256: 'f760e03004ee482af7abd678c558583f8c3ec5c786de732fac61364147a151c9',
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
