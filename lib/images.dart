/// images.dart — Central image registry for the Details / Blog feature.
///
/// The Details page (and its companion Home list) load their hero + thumbnail
/// images through this single file. **You only ever need to edit the
/// `kArticleImages` map below** to point every article at a new CDN URL —
/// no other file in the app needs to change.
///
/// Each entry has:
///   • `hero`    — large card image shown at the top of the Details page
///   • `thumb`   — small square image shown in the "More Articles" rail
///   • `badge`   — optional tag printed on the featured card (Design /
///                 Health / Workout / etc.) — comes from the article, not
///                 from this file, but we keep the badge color hint here so
///                 designers can swap visuals without re-touching code.
///
/// Convention:
///   * Use a public URL (https://...) for a network-loaded image.
///   * Use `asset('assets/...')` to bundle an image with the app.
///   * Leave the string empty ('') to fall back to the built-in gradient
///     placeholder so the screen never looks broken.
///
/// Keep the keys in `kArticleImages` exactly in sync with the article IDs
/// defined in `lib/blog/blog_articles.dart` — both files share the same
/// `String id` (e.g. `'home_dashboard'`, `'meal_plan'`, …).
library;

import 'package:flutter/material.dart';

import 'theme/app_theme.dart';

class ArticleImage {
  /// Hero image URL (large 16:9 card on the Details page).
  final String hero;

  /// Thumbnail URL (small 1:1 card on the home "More Articles" rail).
  final String thumb;

  /// Optional dark gradient that sits behind the image so text stays
  /// legible even if the photo is light. Tweak the stops per article.
  final List<Color> gradient;

  const ArticleImage({
    required this.hero,
    required this.thumb,
    this.gradient = const [
      AppColors.newsOverlayStart,
      AppColors.newsOverlayEnd,
    ],
  });
}

/// 👇  EDIT THIS MAP TO UPDATE IMAGES  👇
///
/// Replace the `hero` / `thumb` URLs with whatever your CDN returns. As long
/// as the keys match the article IDs in `lib/blog/blog_articles.dart`, the
/// rest of the app will pick them up automatically — no widget changes
/// required.
const Map<String, ArticleImage> kArticleImages = {
  // ───────────────────────────────────────────────────────────────────────
  // Home & navigation
  // ───────────────────────────────────────────────────────────────────────
  'home_dashboard': ArticleImage(
    hero:
        'https://images.unsplash.com/photo-1490645935967-10de6ba17061?w=1600&q=80',
    thumb:
        'https://images.unsplash.com/photo-1490645935967-10de6ba17061?w=600&q=80',
  ),
  'role_select': ArticleImage(
    hero:
        'https://images.unsplash.com/photo-1576091160550-2173dba999ef?w=1600&q=80',
    thumb:
        'https://images.unsplash.com/photo-1576091160550-2173dba999ef?w=600&q=80',
  ),
  'onboarding': ArticleImage(
    hero:
        'https://images.unsplash.com/photo-1559757148-5c350d0d3c56?w=1600&q=80',
    thumb:
        'https://images.unsplash.com/photo-1559757148-5c350d0d3c56?w=600&q=80',
  ),

  // ───────────────────────────────────────────────────────────────────────
  // Meal & nutrition
  // ───────────────────────────────────────────────────────────────────────
  'meal_plan': ArticleImage(
    hero:
        'https://images.unsplash.com/photo-1498837167922-ddd27525d352?w=1600&q=80',
    thumb:
        'https://images.unsplash.com/photo-1498837167922-ddd27525d352?w=600&q=80',
  ),
  'meal_details': ArticleImage(
    hero:
        'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=1600&q=80',
    thumb:
        'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=600&q=80',
  ),
  'plan_editor': ArticleImage(
    hero:
        'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=1600&q=80',
    thumb:
        'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=600&q=80',
  ),
  'restricted_foods': ArticleImage(
    hero:
        'https://images.unsplash.com/photo-1551024601-bec78aea704b?w=1600&q=80',
    thumb:
        'https://images.unsplash.com/photo-1551024601-bec78aea704b?w=600&q=80',
  ),

  // ───────────────────────────────────────────────────────────────────────
  // Medicine & doctor
  // ───────────────────────────────────────────────────────────────────────
  'medicine': ArticleImage(
    hero:
        'https://images.unsplash.com/photo-1587854692152-cbe660dbde88?w=1600&q=80',
    thumb:
        'https://images.unsplash.com/photo-1587854692152-cbe660dbde88?w=600&q=80',
  ),
  'medicine_editor': ArticleImage(
    hero:
        'https://images.unsplash.com/photo-1471864190281-a93a3070b6de?w=1600&q=80',
    thumb:
        'https://images.unsplash.com/photo-1471864190281-a93a3070b6de?w=600&q=80',
  ),
  'doctor_report': ArticleImage(
    hero:
        'https://images.unsplash.com/photo-1576091160399-112ba8d25d1d?w=1600&q=80',
    thumb:
        'https://images.unsplash.com/photo-1576091160399-112ba8d25d1d?w=600&q=80',
  ),

  // ───────────────────────────────────────────────────────────────────────
  // Water, workout, AI chat
  // ───────────────────────────────────────────────────────────────────────
  'water': ArticleImage(
    hero:
        'https://images.unsplash.com/photo-1523362628745-0c100150b504?w=1600&q=80',
    thumb:
        'https://images.unsplash.com/photo-1523362628745-0c100150b504?w=600&q=80',
  ),
  'water_analytics': ArticleImage(
    hero:
        'https://images.unsplash.com/photo-1502740479091-635887520276?w=1600&q=80',
    thumb:
        'https://images.unsplash.com/photo-1502740479091-635887520276?w=600&q=80',
  ),
  'workout': ArticleImage(
    hero:
        'https://images.unsplash.com/photo-1571019613454-1cb2f99b2d8b?w=1600&q=80',
    thumb:
        'https://images.unsplash.com/photo-1571019613454-1cb2f99b2d8b?w=600&q=80',
  ),
  'workout_details': ArticleImage(
    hero:
        'https://images.unsplash.com/photo-1518611012118-696072aa579a?w=1600&q=80',
    thumb:
        'https://images.unsplash.com/photo-1518611012118-696072aa579a?w=600&q=80',
  ),
  'ai_chat': ArticleImage(
    hero:
        'https://images.unsplash.com/photo-1531746790731-6c087fecd65a?w=1600&q=80',
    thumb:
        'https://images.unsplash.com/photo-1531746790731-6c087fecd65a?w=600&q=80',
  ),

  // ───────────────────────────────────────────────────────────────────────
  // Analytics, profile, caretaker
  // ───────────────────────────────────────────────────────────────────────
  'analytics': ArticleImage(
    hero:
        'https://images.unsplash.com/photo-1551288049-bebda4e38f71?w=1600&q=80',
    thumb:
        'https://images.unsplash.com/photo-1551288049-bebda4e38f71?w=600&q=80',
  ),
  'profile': ArticleImage(
    hero:
        'https://images.unsplash.com/photo-1559839734-2b71ea197ec2?w=1600&q=80',
    thumb:
        'https://images.unsplash.com/photo-1559839734-2b71ea197ec2?w=600&q=80',
  ),
  'caretaker_shell': ArticleImage(
    hero:
        'https://images.unsplash.com/photo-1581579438747-104c53e7e7a5?w=1600&q=80',
    thumb:
        'https://images.unsplash.com/photo-1581579438747-104c53e7e7a5?w=600&q=80',
  ),
  'caretaker_today': ArticleImage(
    hero:
        'https://images.unsplash.com/photo-1573497019940-1c28c88b4f3e?w=1600&q=80',
    thumb:
        'https://images.unsplash.com/photo-1573497019940-1c28c88b4f3e?w=600&q=80',
  ),
  'patient_inbox': ArticleImage(
    hero:
        'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=1600&q=80',
    thumb:
        'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=600&q=80',
  ),
  'explore': ArticleImage(
    hero:
        'https://images.unsplash.com/photo-1469474968028-56623f02e42e?w=1600&q=80',
    thumb:
        'https://images.unsplash.com/photo-1469474968028-56623f02e42e?w=600&q=80',
  ),

  // ───────────────────────────────────────────────────────────────────────
  // Splash & auth
  // ───────────────────────────────────────────────────────────────────────
  'splash': ArticleImage(
    hero:
        'https://images.unsplash.com/photo-1505751172876-fa1923c5c528?w=1600&q=80',
    thumb:
        'https://images.unsplash.com/photo-1505751172876-fa1923c5c528?w=600&q=80',
  ),
  'auth': ArticleImage(
    hero:
        'https://images.unsplash.com/photo-1499951360447-b19be8fe80f5?w=1600&q=80',
    thumb:
        'https://images.unsplash.com/photo-1499951360447-b19be8fe80f5?w=600&q=80',
  ),
};

/// Fallback image used whenever an article ID doesn't have an entry above
/// (or its URL is empty). Keeps the UI from looking broken during dev.
ArticleImage fallbackImage(String id) {
  final entry = kArticleImages[id];
  if (entry != null) return entry;
  return const ArticleImage(
    hero: '',
    thumb: '',
  );
}
