import '../models/blog_article.dart';
import '../services/blog_service.dart';
import 'article_image.dart';

/// Pairs a blog article with its image URL.
class ArticleWithImage {
  final BlogArticle article;
  final ArticleImage image;
  const ArticleWithImage({required this.article, required this.image});
}

/// Public accessor for the blog dataset. Reads from [BlogService]
/// (DB-backed when the network is up, bundled fallback when offline)
/// and pairs each article with its image URL.
///
/// Image priority: DB row's `hero_image_url`/`thumb_image_url` (when
/// set) → `kArticleImages[id]` → gradient placeholder.
class BlogRepository {
  BlogRepository._();

  static List<ArticleWithImage>? _wrappedCache;
  static List<BlogArticle>? _wrappedForSource;

  static ArticleWithImage _wrap(BlogArticle a) {
    final bundled = kArticleImages[a.id] ?? fallbackImage(a.id);
    final img = (a.heroImageUrl != null || a.thumbImageUrl != null)
        ? ArticleImage(
            hero: a.heroImageUrl ?? bundled.hero,
            thumb: a.thumbImageUrl ?? bundled.thumb,
            gradient: bundled.gradient,
          )
        : bundled;
    return ArticleWithImage(article: a, image: img);
  }

  static List<ArticleWithImage> _wrapAll(List<BlogArticle> source) {
    if (identical(_wrappedForSource, source) && _wrappedCache != null) {
      return _wrappedCache!;
    }
    final list = source.map(_wrap).toList(growable: false);
    _wrappedForSource = source;
    _wrappedCache = List.unmodifiable(list);
    return _wrappedCache!;
  }

  /// Every article, in display order.
  static List<ArticleWithImage> get all => _wrapAll(BlogService.cached);

  /// First article that has `is_featured = true` in the DB; falls back
  /// to the first sorted article when nothing is featured.
  static ArticleWithImage get today {
    final list = all;
    if (list.isEmpty) {
      // Should ideally never happen given the BlogService fallback, 
      // but prevents "Bad state: No element" crash if both sources are empty.
      throw StateError('No blog articles found in fallback or database.');
    }
    for (final p in list) {
      if (p.article.isFeatured) return p;
    }
    return list.first;
  }

  /// Everything except today's article — feeds the "More Articles" rail.
  static List<ArticleWithImage> get more {
    final t = today;
    return all.where((p) => p.article.id != t.article.id).toList(growable: false);
  }

  /// Lookup by article slug (matches `blog_posts.slug`).
  static ArticleWithImage? byId(String id) {
    for (final pair in all) {
      if (pair.article.id == id) return pair;
    }
    return null;
  }
}