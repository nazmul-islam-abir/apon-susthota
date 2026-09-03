/// Caretaker "Notice" / announcements screen.
///
/// Mirrors the visual style of the patient `NotificationScreen` (forest
/// green hero, dark ink body) but is scoped to *caretaker-side*
/// announcements (link-request updates, system-wide notices from the
/// care-team admin, etc.). For v1 the list is empty — the screen
/// exists so the home dashboard's "নোটিশ" category card navigates
/// somewhere real, matching the patient UX.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../widgets/mono_widgets.dart';

class CaretakerNoticeScreen extends StatefulWidget {
  const CaretakerNoticeScreen({super.key});

  @override
  State<CaretakerNoticeScreen> createState() => _CaretakerNoticeScreenState();
}

class _CaretakerNoticeScreenState extends State<CaretakerNoticeScreen> {
  Future<void> _refresh() async {
    HapticFeedback.selectionClick();
    // Nothing to fetch yet — we just bounce a tiny delay so the
    // pull-to-refresh gesture feels responsive (avoids the "nothing
    // happened" smell of an empty Future.microtask).
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.svcCategoryBg,
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: AppColors.svcHero,
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              _buildHero(context),
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    const url =
        'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/app/photo-1564352969906-8b7f46ba4b8b.avif?token=eyJraWQiOiJhZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJhcHAvcGhvdG8tMTU2NDM1Mjk2OTkwNi04YjdmNDZiYTRiOGIuYXZpZiIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODc4Njg2MjksImV4cCI6MTgxOTQwNDYyOX0.Jdl-6cqT6wHh_nv8j-7oD3zjU2KcoR4e5ohJVnZgTNs';

    return SliverToBoxAdapter(
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.svcHero,
          image: DecorationImage(
            image: NetworkImage(url),
            fit: BoxFit.cover,
            opacity: 0.7,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(color: Colors.black.withValues(alpha: 0.3)),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SafeArea(bottom: false, child: SizedBox(height: 8)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 18),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'নোটিশ',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                          letterSpacing: -1,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'সিস্টেম-পর্যায়ের ঘোষণা ও আপডেট',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.svcCategoryBg,
                borderRadius: BorderRadius.zero,
                border: Border.all(color: AppColors.line, width: 1.2),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.campaign_outlined,
                color: AppColors.svcHero,
                size: 44,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'এখনো কোনো নোটিশ নেই',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'গুরুত্বপূর্ণ ঘোষণা ও আপডেট\nএখানে দেখানো হবে।',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.smoke,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            const LoadingMark(size: 18),
          ],
        ),
      ),
    );
  }
}
