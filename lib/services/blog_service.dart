import 'package:flutter/foundation.dart';

import '../blog/blog_articles.dart';
import '../models/blog_article.dart';
import 'supabase_service.dart';

/// In-memory cache of blog posts fetched from Supabase with bundled
/// offline fallback.
///
/// Sorted once on `warm()` / `load()`. The Details Home rebuilds on
/// every search keystroke, so the cache must be a cheap read.
class BlogService {
  BlogService._();

  static List<BlogArticle>? _sortedCache;

  /// DB-backed sorted list when warm succeeded; bundled `kBlogArticles`
  /// otherwise (first paint, offline, fetch error).
  static List<BlogArticle> get cached => _sortedCache ?? kBlogArticles;

  /// Fire-and-forget warm-up. Errors are swallowed so the app stays
  /// usable offline — the fallback list renders until `load()` succeeds.
  static Future<void> warm() async {
    try {
      await _refresh();
    } catch (e) {
      debugPrint('⚠️ [BlogService] warm failed (will use fallback): $e');
    }
  }

  /// Explicit re-fetch for the Details Home pull-to-refresh. Returns
  /// the post count that ended up in the cache. Throws so the caller
  /// can show a snackbar.
  static Future<int> load() async {
    await _refresh();
    return _sortedCache!.length;
  }

  static Future<void> _refresh() async {
    if (!SupabaseService.isInitialized) {
      throw StateError('Supabase not initialized');
    }
    final rows = await SupabaseService.fetchBlogPosts();
    final list = rows.map((r) => r.toArticle()).toList(growable: false);
    list.sort((a, b) {
      if (a.isFeatured != b.isFeatured) return a.isFeatured ? -1 : 1;
      if (a.sortOrder != b.sortOrder) return a.sortOrder.compareTo(b.sortOrder);
      final ac = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bc = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return bc.compareTo(ac);
    });
    _sortedCache = List.unmodifiable(list);
  }
}
