/// lib/screens/details_home_screen.dart
///
/// "Details Home" — professional discovery feed for the in-app blog.
/// Redesigned to match the professional Nexora / forest green aesthetic:
///   • Fixed technical header with back button.
///   • Search field with sharp corners (Radius 0).
///   • Featured Article card with premium editorial styling.
///   • Card-based list for "More Articles" with better hierarchy.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../blog/blog_repository.dart';
import '../services/blog_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/back_scaffold.dart';
import '../widgets/blog_image.dart';
import '../widgets/mono_widgets.dart';
import 'details_screen.dart';

class DetailsHomeScreen extends StatefulWidget {
  const DetailsHomeScreen({super.key});

  @override
  State<DetailsHomeScreen> createState() => _DetailsHomeScreenState();
}

class _DetailsHomeScreenState extends State<DetailsHomeScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  late final String _displayName;

  @override
  void initState() {
    super.initState();
    _displayName = _resolveName();
    _search.addListener(() {
      final next = _search.text.trim();
      if (next != _query) setState(() => _query = next);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = BlogRepository.today;
    final more = BlogRepository.more;
    final filtered = _query.isEmpty
        ? more
        : more.where((p) {
            final q = _query.toLowerCase();
            return p.article.titleBn.toLowerCase().contains(q) ||
                p.article.summaryBn.toLowerCase().contains(q) ||
                p.article.badge.toLowerCase().contains(q);
          }).toList(growable: false);

    return Scaffold(
      backgroundColor: AppColors.newsCanvas,
      body: BackScaffold(
        title: 'স্বাস্থ্য নিবন্ধ',
        body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: AppColors.svcHero,
          backgroundColor: Colors.white,
          onRefresh: _onRefresh,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                sliver: SliverList.list(
                  children: [
                    _GreetingHeader(name: _displayName),
                    const SizedBox(height: 24),
                    _SearchField(
                      controller: _search,
                      onClear: () => _search.clear(),
                    ),
                    const SizedBox(height: 32),
                    const _SectionHeaderRow(title: 'আজকের নিবন্ধ', sub: 'আপনার জন্য নির্বাচিত'),
                    const SizedBox(height: 16),
                    _FeaturedCard(data: today, onTap: _openArticle),
                    const SizedBox(height: 36),
                    _SectionHeaderRow(
                      title: 'আরও নিবন্ধ',
                      sub: 'অন্বেষণ করুন',
                      onAction: _query.isEmpty ? () {} : null,
                    ),
                    const SizedBox(height: 16),
                    if (filtered.isEmpty)
                      _EmptyState(query: _query)
                    else
                      ...filtered.map(
                        (p) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _ArticleCard(
                            data: p,
                            onTap: () => _openArticle(p),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  String _resolveName() {
    if (!SupabaseService.isInitialized) return 'বন্ধু';
    final meta = SupabaseService.currentUser?.userMetadata ?? const {};
    final name = (meta['full_name'] ??
            meta['name'] ??
            meta['username'] ??
            '')
        .toString()
        .trim();
    return name.isNotEmpty ? name : 'বন্ধু';
  }

  void _openArticle(ArticleWithImage pair) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailsScreen(data: pair),
      ),
    );
  }

  Future<void> _onRefresh() async {
    try {
      await BlogService.load();
      if (mounted) setState(() {});
    } catch (_) {}
  }
}

// ─── Header components ───────────────────────────────────────────────────

class _GreetingHeader extends StatelessWidget {
  final String name;
  const _GreetingHeader({required this.name});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'হ্যালো, $name,',
                style: const TextStyle(
                  color: AppColors.smoke,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'শুভ দিন!',
                style: TextStyle(
                  color: AppColors.newsInk,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.svcHero,
            borderRadius: BorderRadius.zero,
            border: Border.all(color: AppColors.svcHeroAccent, width: 2),
          ),
          alignment: Alignment.center,
          child: Text(
            name.isEmpty ? 'আ' : name.characters.first.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onClear;
  const _SearchField({required this.controller, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          const Icon(Icons.search_rounded, color: AppColors.svcHero, size: 20),
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                hintText: 'নিবন্ধ খুঁজুন...',
                hintStyle: TextStyle(color: AppColors.smoke, fontWeight: FontWeight.w600),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: onClear,
            ),
        ],
      ),
    );
  }
}

class _SectionHeaderRow extends StatelessWidget {
  final String title;
  final String sub;
  final VoidCallback? onAction;

  const _SectionHeaderRow({required this.title, required this.sub, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.newsInk, letterSpacing: -0.5)),
              Text(sub, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.smoke, letterSpacing: 0.5)),
            ],
          ),
        ),
        if (onAction != null)
          GestureDetector(
            onTap: onAction,
            child: const Text(
              'সব দেখুন →',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.svcHero),
            ),
          ),
      ],
    );
  }
}

// ─── Featured card ───────────────────────────────────────────────────────

class _FeaturedCard extends StatelessWidget {
  final ArticleWithImage data;
  final ValueChanged<ArticleWithImage> onTap;
  const _FeaturedCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = data.article;
    return InkWell(
      onTap: () => onTap(data),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: AppColors.line, width: 1.2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 8))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: BlogImage(url: data.image.hero, gradient: data.image.gradient),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: const BoxDecoration(color: AppColors.svcHero, borderRadius: BorderRadius.zero),
                    child: Text(a.badge, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    a.titleBn,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.newsInk, height: 1.2),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    a.summaryBn,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.smoke, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Icon(Icons.schedule_rounded, size: 14, color: AppColors.smoke),
                      const SizedBox(width: 6),
                      Text(a.dateLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.smoke)),
                      const Spacer(),
                      Text(a.readTimeLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.svcHero)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Article Card ────────────────────────────────────────────────────────

class _ArticleCard extends StatelessWidget {
  final ArticleWithImage data;
  final VoidCallback onTap;
  const _ArticleCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = data.article;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: AppColors.line, width: 1.2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            Container(
              width: 90, height: 90,
              decoration: const BoxDecoration(borderRadius: BorderRadius.zero),
              clipBehavior: Clip.antiAlias,
              child: BlogImage(url: data.image.thumb, gradient: data.image.gradient),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.titleBn,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.newsInk, height: 1.2),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(a.dateLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.smoke)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.newsSurfaceSoft, borderRadius: BorderRadius.zero),
                        child: Text(a.readTimeLabel, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.newsInk)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String query;
  const _EmptyState({required this.query});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            const Icon(Icons.search_off_rounded, color: AppColors.smoke, size: 40),
            const SizedBox(height: 12),
            Text('"$query" পাওয়া যায়নি', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.smoke)),
          ],
        ),
      ),
    );
  }
}
