/// lib/screens/details_screen.dart
///
/// "Details" page — mirrors the right phone in the reference design.
///
/// Layout (top → bottom):
///   1. Top bar: back button (left) and a circular bookmark button
///      (right) — toggles an in-memory bookmark state for demo.
///   2. Hero image (16:9) with a soft bottom shadow for depth.
///   3. Meta row: date + read-time with a hairline divider under it.
///   4. Big Bangla title (multi-line).
///   5. Body — every section from the article rendered with a
///      section heading + paragraph(s), exactly like the reference
///      paragraphs.
///   6. "আপনি যা করতে পারেন" — a checklist of canDo items, only
///      rendered when the article has them.
///   7. Sticky "Read More" CTA at the bottom (per the reference
///      button). We make it a snackbar-trigger so the demo flow is
///      obvious — replace with your real action when wiring the page
///      to the actual feature.
///
/// All copy is in Bangla; the article object already provides every
/// string. Image URLs come from `lib/images.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../blog/blog_repository.dart';
import '../models/blog_article.dart';
import '../theme/app_theme.dart';
import '../widgets/blog_image.dart'
    show HeroImage;

class DetailsScreen extends StatefulWidget {
  final ArticleWithImage data;
  const DetailsScreen({super.key, required this.data});

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  bool _bookmarked = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.data.article;
    final img = widget.data.image;

    return Scaffold(
      backgroundColor: AppColors.newsCanvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _TopBar(
              bookmarked: _bookmarked,
              onBack: () => Navigator.of(context).maybePop(),
              onBookmark: () {
                HapticFeedback.selectionClick();
                setState(() => _bookmarked = !_bookmarked);
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(
                        _bookmarked
                            ? 'বুকমার্ক করা হয়েছে'
                            : 'বুকমার্ক সরানো হয়েছে',
                      ),
                      duration: const Duration(seconds: 1),
                    ),
                  );
              },
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  _Hero(url: img.hero, gradient: img.gradient),
                  const SizedBox(height: 18),
                  _MetaRow(
                    date: a.dateLabel,
                    readTime: a.readTimeLabel,
                  ),
                  const SizedBox(height: 14),
                  _Title(text: a.titleBn),
                  const SizedBox(height: 10),
                  _Dek(text: a.dekBn),
                  const SizedBox(height: 22),
                  for (var i = 0; i < a.sections.length; i++) ...[
                    _SectionView(section: a.sections[i]),
                    if (i != a.sections.length - 1)
                      const SizedBox(height: 22),
                  ],
                  if (a.canDo.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    _CanDoList(items: a.canDo),
                  ],
                  const SizedBox(height: 110), // room for sticky CTA
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _CtaBar(
        label: a.ctaLabel ?? 'আরও পড়ুন',
        onPressed: () {
          HapticFeedback.lightImpact();
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              SnackBar(
                content: Text('"${a.titleBn}" এখনো সম্পূর্ণ হয়নি'),
                duration: const Duration(seconds: 2),
              ),
            );
        },
      ),
    );
  }
}

// ─── Top bar ─────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final bool bookmarked;
  final VoidCallback onBack;
  final VoidCallback onBookmark;
  const _TopBar({
    required this.bookmarked,
    required this.onBack,
    required this.onBookmark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back,
                color: AppColors.newsInk, size: 26),
            tooltip: 'পিছনে',
          ),
          const Spacer(),
          _CircleIconButton(
            icon: bookmarked ? Icons.bookmark : Icons.bookmark_outline,
            onPressed: onBookmark,
            tooltip: 'বুকমার্ক',
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  const _CircleIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.newsSurface,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Tooltip(
          message: tooltip ?? '',
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.newsDivider),
            ),
            child: Icon(icon, color: AppColors.newsInk, size: 22),
          ),
        ),
      ),
    );
  }
}

// ─── Hero image ──────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  final String url;
  final List<Color> gradient;
  const _Hero({required this.url, required this.gradient});

  @override
  Widget build(BuildContext context) =>
      HeroImage(url: url, gradient: gradient);
}

// ─── Meta row ────────────────────────────────────────────────────────────

class _MetaRow extends StatelessWidget {
  final String date;
  final String readTime;
  const _MetaRow({required this.date, required this.readTime});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              date,
              style: const TextStyle(
                color: AppColors.newsMuted,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.circle,
                size: 4, color: AppColors.newsMuted),
            const SizedBox(width: 6),
            Text(
              readTime,
              style: const TextStyle(
                color: AppColors.newsMuted,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(height: 1, color: AppColors.newsDivider),
      ],
    );
  }
}

// ─── Title / dek ─────────────────────────────────────────────────────────

class _Title extends StatelessWidget {
  final String text;
  const _Title({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.newsInk,
        fontSize: 26,
        fontWeight: FontWeight.w800,
        height: 1.22,
        letterSpacing: -0.4,
      ),
    );
  }
}

class _Dek extends StatelessWidget {
  final String text;
  const _Dek({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.newsMuted,
        fontSize: 15,
        fontWeight: FontWeight.w500,
        height: 1.45,
      ),
    );
  }
}

// ─── Body section ────────────────────────────────────────────────────────

class _SectionView extends StatelessWidget {
  final BlogSection section;
  const _SectionView({required this.section});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          section.heading,
          style: const TextStyle(
            color: AppColors.newsInk,
            fontSize: 19,
            fontWeight: FontWeight.w800,
            height: 1.3,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          section.body,
          style: const TextStyle(
            color: AppColors.newsMuted,
            fontSize: 16,
            height: 1.55,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ─── "What you can do" list ──────────────────────────────────────────────

class _CanDoList extends StatelessWidget {
  final List<String> items;
  const _CanDoList({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.newsSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.newsDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.tips_and_updates_outlined,
                  color: AppColors.newsInk, size: 22),
              SizedBox(width: 8),
              Text(
                'আপনি যা করতে পারেন',
                style: TextStyle(
                  color: AppColors.newsInk,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final t in items) ...[
            _CanDoRow(text: t),
            if (t != items.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _CanDoRow extends StatelessWidget {
  final String text;
  const _CanDoRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          margin: const EdgeInsets.only(top: 2),
          decoration: const BoxDecoration(
            color: AppColors.newsPill,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check,
              size: 14, color: AppColors.newsOnPill),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.newsInk,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Sticky CTA ──────────────────────────────────────────────────────────

class _CtaBar extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _CtaBar({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: AppColors.newsCanvas,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.newsPill,
            foregroundColor: AppColors.newsOnPill,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          child: Text(label),
        ),
      ),
    );
  }
}