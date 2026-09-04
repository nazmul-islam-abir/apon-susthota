/// Shared header used by every caretaker read-only viewer.
///
/// Renders:
///   • A forest-green hero strip with the patient's name + role badge.
///   • A small amber "কেবল দেখার জন্য" (read-only) pill so the caretaker
///     never accidentally taps an action expecting it to write.
///   • A back chevron that pops the screen via [Navigator.maybePop].
///
/// The bar height is 72 dp (taller than the standard AppBar) so the
/// patient identity is unmistakable. Bangla + English both render fine.
library;

import 'package:flutter/material.dart';

import '../models/caretaker_patient_summary.dart';
import '../theme/app_theme.dart';

class CaretakerViewerHeader extends StatelessWidget {
  final CaretakerPatientSummary patient;
  final String screenTitle;
  final bool showReadOnlyBadge;
  final String? nameOverride;
  final Widget? action;

  const CaretakerViewerHeader({
    super.key,
    required this.patient,
    required this.screenTitle,
    this.showReadOnlyBadge = true,
    this.nameOverride,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final name = (nameOverride ?? patient.fullName).trim();
    final display = name.isEmpty ? 'রোগী' : name;
    final initials = _initials(display);

    return SliverToBoxAdapter(
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.svcHero,
          image: DecorationImage(
            image: NetworkImage(
              'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/app/photo-1564352969906-8b7f46ba4b8b.avif?token=eyJraWQiOiJhZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJhcHAvcGhvdG8tMTU2NDM1Mjk2OTkwNi04YjdmNDZiYTRiOGIuYXZpZiIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODc4Njg2MjksImV4cCI6MTgxOTQwNDYyOX0.Jdl-6cqT6wHh_nv8j-7oD3zjU2KcoR4e5ohJVnZgTNs',
            ),
            fit: BoxFit.cover,
            opacity: 0.7,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(color: Colors.black.withValues(alpha: 0.35)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Back chevron
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: () => Navigator.of(context).maybePop(),
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 36, minHeight: 36),
                        ),
                        const SizedBox(width: 4),
                        // Avatar (network image with initials fallback)
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.zero,
                            border:
                                Border.all(color: Colors.white24, width: 1.2),
                          ),
                          clipBehavior: Clip.hardEdge,
                          child: _avatarOrInitials(patient.avatarUrl, initials),
                        ),
                        const SizedBox(width: 12),
                        // Name + role
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                display,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                screenTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (action != null) ...[
                          action!,
                          const SizedBox(width: 8),
                        ],
                        if (showReadOnlyBadge) const _ReadOnlyBadge(),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _initials(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return 'র';
    final parts = s.split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}';
    return s.characters.first.toUpperCase();
  }

  /// Render the patient's avatar URL if it exists and parses, else fall
  /// back to initials. Keeps the same visual square + white border.
  static Widget _avatarOrInitials(String? url, String initials) {
    final trimmed = url?.trim();
    final hasAvatar = trimmed != null && trimmed.isNotEmpty;
    final fallback = Text(
      initials,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w900,
      ),
    );
    if (!hasAvatar) return fallback;
    return Image.network(
      trimmed,
      width: 44,
      height: 44,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => fallback,
      loadingBuilder: (_, child, prog) => prog == null ? child : fallback,
    );
  }
}

class _ReadOnlyBadge extends StatelessWidget {
  const _ReadOnlyBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.92),
        borderRadius: BorderRadius.zero,
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline_rounded, color: Colors.white, size: 13),
          SizedBox(width: 5),
          Text(
            'শুধু দেখুন',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
