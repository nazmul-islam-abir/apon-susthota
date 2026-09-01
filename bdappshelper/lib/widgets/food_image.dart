import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../services/api_service.dart' as api;

/// Reusable food-image widget.
///
/// - Loads via [CachedNetworkImage] (offline cache + low RAM).
/// - Falls back to a beautiful gradient + icon if the network fails,
///   so the app never looks broken while images load or fail.
/// - The [icon] is auto-picked from the food's category.
/// - Use [aspectRatio] to lock a uniform aspect (default 4:3) so every
///   card looks identical regardless of source image dimensions.
class FoodImage extends StatelessWidget {
  const FoodImage({
    super.key,
    required this.food,
    this.borderRadius,
    this.fit = BoxFit.cover,
    this.aspectRatio,
    this.size,
  });

  /// Convenience constructor: pass a food id directly.
  factory FoodImage.byId({
    Key? key,
    required String foodId,
    BorderRadius? borderRadius,
    BoxFit fit = BoxFit.cover,
    double? aspectRatio,
  }) {
    final f = _lookup(foodId);
    return FoodImage(
      key: key,
      food: f,
      borderRadius: borderRadius,
      fit: fit,
      aspectRatio: aspectRatio,
    );
  }

  final api.FoodItem? food;
  final BorderRadius? borderRadius;
  final BoxFit fit;
  final double? aspectRatio;

  /// Optional explicit pixel size. Mutually exclusive with [aspectRatio].
  final double? size;

  static api.FoodItem? _lookup(String id) => _FoodImageRegistry.find(id);

  IconData _icon() {
    final cat = (food?.category ?? '').toLowerCase();
    if (cat.contains('rice')) return Icons.rice_bowl_rounded;
    if (cat.contains('curry')) return Icons.soup_kitchen_rounded;
    if (cat.contains('fish')) return Icons.set_meal_rounded;
    if (cat.contains('meat')) return Icons.restaurant_rounded;
    if (cat.contains('fruit')) return Icons.eco_rounded;
    if (cat.contains('dairy')) return Icons.icecream_rounded;
    if (cat.contains('drink')) return Icons.local_drink_rounded;
    if (cat.contains('snack') || cat.contains('street')) {
      return Icons.bakery_dining_rounded;
    }
    return Icons.ramen_dining_rounded;
  }

  Color _tint() {
    final cat = (food?.category ?? '').toLowerCase();
    if (cat.contains('rice')) return AppColors.primary;
    if (cat.contains('curry')) return AppColors.secondary;
    if (cat.contains('fish')) return AppColors.info;
    if (cat.contains('meat')) return AppColors.primaryDark;
    if (cat.contains('fruit')) return AppColors.secondary;
    if (cat.contains('dairy')) return AppColors.accent;
    if (cat.contains('drink')) return AppColors.info;
    if (cat.contains('snack') || cat.contains('street')) {
      return AppColors.accent;
    }
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    final tint = _tint();
    final icon = _icon();
    final radius = borderRadius ?? BorderRadius.circular(AppRadius.md);

    final fallback = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tint.withValues(alpha: 0.85),
            tint.withValues(alpha: 0.55),
          ],
        ),
      ),
      child: Center(child: Icon(icon, color: Colors.white, size: 38)),
    );

    final placeholder = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tint.withValues(alpha: 0.6),
            tint.withValues(alpha: 0.3),
          ],
        ),
      ),
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      ),
    );

    final url = food == null ? null : _imageUrlFor(food!);
    final image = (url == null || url.isEmpty)
        ? fallback
        : CachedNetworkImage(
            imageUrl: url,
            fit: fit,
            // Fill the entire box; never leave empty space.
            width: double.infinity,
            height: double.infinity,
            placeholder: (_, __) => placeholder,
            errorWidget: (_, __, ___) => fallback,
          );

    Widget clipped = ClipRRect(
      borderRadius: radius,
      child: image,
    );

    // Apply sizing: explicit size > aspect ratio > unbounded.
    if (size != null) {
      clipped = SizedBox(width: size, height: size, child: clipped);
    } else if (aspectRatio != null) {
      clipped = AspectRatio(aspectRatio: aspectRatio!, child: clipped);
    }

    return clipped;
  }

  String? _imageUrlFor(api.FoodItem f) => _FoodImageRegistry.url(f.id);
}

/// Tiny bridge that exposes lookup & image URL synchronously. It is
/// populated at app start from `BdFoodLibrary.imageFor(...)`.
class _FoodImageRegistry {
  static final Map<String, api.FoodItem> _byId = {};
  static final Map<String, String> _urls = {};

  static void seed(List<api.FoodItem> items, Map<String, String> urls) {
    _byId.clear();
    _urls.clear();
    for (final f in items) {
      _byId[f.id] = f;
    }
    _urls.addAll(urls);
  }

  static api.FoodItem? find(String id) => _byId[id];
  static String? url(String id) => _urls[id];
}

/// Public helper — call once from main() to populate the registry.
void seedFoodImageRegistry(
    List<api.FoodItem> items, Map<String, String> urls) {
  _FoodImageRegistry.seed(items, urls);
}