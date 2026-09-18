// 📁 lib/features/home/search/global_search_delegate.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';

/// Delegate لعملية البحث متعدد النطاقات
class GlobalSearchDelegate extends SearchDelegate<void> {
  /// النطاقات المتاحة
  final List<String> scopes;

  GlobalSearchDelegate({required this.scopes})
      : super(
          searchFieldLabel: 'بحث في النظام...',
          textInputAction: TextInputAction.search,
        );

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        if (query.isEmpty) {
          return const Center(child: Text('أدخل مصطلحًا للبحث'));
        }
        // يجمع النتائج من كل نطاق
        return FutureBuilder<List<SearchResult>>(
          future: SearchServices.searchAll(query, scopes),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return const Center(child: Text('خطأ: \${snapshot.error}'));
            }
            final results = snapshot.data ?? [];
            if (results.isEmpty) {
              return const Center(child: Text('لا توجد نتائج'));
            }
            return ListView.builder(
              itemCount: results.length,
              itemBuilder: (context, index) {
                final item = results[index];
                return ListTile(
                  leading: item.icon != null ? Icon(item.icon) : null,
                  title: Text(item.title),
                  subtitle: Text(item.subtitle ?? ''),
                  onTap: () {
                    close(context, null);
                    AppRoutes.pushNamedSafe(context, item.route);
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.isEmpty) {
      return Container();
    }
    return FutureBuilder<List<SearchResult>>(
      future: SearchServices.searchAll(query, scopes),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final suggestions = snapshot.data!;
        return ListView.builder(
          itemCount: suggestions.length,
          itemBuilder: (context, index) {
            final item = suggestions[index];
            return ListTile(
              title: Text(item.title),
              onTap: () {
                query = item.title;
                showResults(context);
              },
            );
          },
        );
      },
    );
  }
}

mixin SearchServices {
  static searchAll(String query, List<String> scopes) {}
}

/// نموذج نتيجة البحث
class SearchResult {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final String route;

  SearchResult({
    required this.title,
    this.subtitle,
    this.icon,
    required this.route,
  });
}
