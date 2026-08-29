/// Blog article model used by the Details page and its Home rail.
///
/// A single article describes one screen/feature of the app, written in
/// Bangla, with:
///   • a short 1-line summary (shown on cards)
///   • a 2-line dek (shown under the title on the details page)
///   • a category tag ("Design", "Health", "Workout", …)
///   • the date / read-time, formatted the way the reference does
///   • an opening paragraph that hooks the reader
///   • a list of body sections (heading + body) — exactly the layout
///     the reference screenshot shows
///   • a "what you can do" checklist at the end
///   • the `cta` text printed on the bottom "Read More" button
///
/// Keeping the model in its own file lets us regenerate the article
/// dataset (next file) without dragging widget code with it.
library;

import 'package:flutter/foundation.dart';

/// One sub-section inside an article body.
@immutable
class BlogSection {
  final String heading;
  final String body;

  const BlogSection({required this.heading, required this.body});
}

/// The full article — a Bangla explainer for one screen of the app.
@immutable
class BlogArticle {
  /// Stable slug, also the key in `kArticleImages`. Matches the
  /// `blog_posts.slug` column in Supabase.
  final String id;

  /// English-friendly label (used in dev / logs only — UI is Bangla).
  final String titleEn;

  /// Bangla headline shown at the top of the Details page.
  final String titleBn;

  /// Short Bangla summary used on the Home list cards.
  final String summaryBn;

  /// Slightly longer 2-line dek used right under the title on Details.
  final String dekBn;

  /// Category chip on the featured card. e.g. "Design", "Health", "Workout".
  final String badge;

  /// Date string in the same format the reference uses ("October 4, 2021").
  final String dateLabel;

  /// "3 min read" style label.
  final String readTimeLabel;

  /// Long-form body of the article — list of sections.
  final List<BlogSection> sections;

  /// Optional bullet list of "what the user can do here", printed near the
  /// bottom of the article.
  final List<String> canDo;

  /// "Read More" / "আরও পড়ুন" button text. Defaults to "আরও পড়ুন" if null.
  final String? ctaLabel;

  /// When true, the article appears in the "আজকের নিবন্ধ" slot on Home.
  /// Populated from `blog_posts.is_featured`; the bundled fallback
  /// defaults to false so all articles stay eligible but the first one
  /// wins via sort-order fallback.
  final bool isFeatured;

  /// Soft-delete flag. Populated from `blog_posts.is_active`; bundled
  /// fallback defaults to true so every offline post is visible.
  final bool isActive;

  /// Manual ordering inside the list. Smaller numbers appear earlier;
  /// ties are broken by `createdAt`. Bundled fallback defaults to 0 so
  /// articles keep their source-file order.
  final int sortOrder;

  /// Server-side creation timestamp. Null for bundled fallback rows;
  /// the repository breaks ties between rows with the same sortOrder
  /// using this so newer DB posts float up when they're missing a
  /// manual sort_order value.
  final DateTime? createdAt;

  /// Optional server-side hero / thumb image URL. When non-null the
  /// repository prefers this over the bundled `kArticleImages` entry —
  /// lets you change a post's image from the Supabase Table Editor
  /// without shipping a new app build.
  final String? heroImageUrl;
  final String? thumbImageUrl;

  const BlogArticle({
    required this.id,
    required this.titleEn,
    required this.titleBn,
    required this.summaryBn,
    required this.dekBn,
    required this.badge,
    required this.dateLabel,
    required this.readTimeLabel,
    required this.sections,
    this.canDo = const [],
    this.ctaLabel,
    this.isFeatured = false,
    this.isActive = true,
    this.sortOrder = 0,
    this.createdAt,
    this.heroImageUrl,
    this.thumbImageUrl,
  });
}
