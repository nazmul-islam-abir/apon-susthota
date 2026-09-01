/// Caretaker "ইনবক্স" tab — professional link request management (Nexora Redesign).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/caretaker_link.dart';
import '../../services/app_errors.dart';
import '../../services/caretaker_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/relative_time.dart';
import '../../widgets/mono_widgets.dart';

class CaretakerInboxTab extends StatefulWidget {
  const CaretakerInboxTab({super.key});

  @override
  State<CaretakerInboxTab> createState() => _CaretakerInboxTabState();
}

class _CaretakerInboxTabState extends State<CaretakerInboxTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeEvents());
  }

  void _consumeEvents() {
    if (!mounted) return;
    final prov = context.read<CaretakerProvider>();
    final ev = prov.consumeLastEvent();
    if (ev == null) return;
    final isAccepted = ev.kind == 'accepted';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isAccepted ? AppColors.svcHero : AppColors.amber,
        content: Text(isAccepted ? '✅ ${ev.otherName} আপনার অনুরোধ গ্রহণ করেছেন' : '⏳ ${ev.otherName} এখনো সাড়া দেননি', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeEvents());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.svcCategoryBg,
      body: Consumer<CaretakerProvider>(
        builder: (context, prov, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _consumeEvents());
          final pending = prov.pending;
          return RefreshIndicator(
            color: AppColors.svcHero,
            onRefresh: prov.refreshPending,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              slivers: [
                _buildHero(prov),
                const SliverToBoxAdapter(child: SizedBox(height: 22)),
                SliverToBoxAdapter(child: _buildSectionTitle('পাঠানো অনুরোধ', 'অপেক্ষমাণ')),
                if (prov.loadingPending && pending.isEmpty)
                  const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: AppColors.svcHero)))
                else if (pending.isEmpty)
                  const SliverFillRemaining(hasScrollBody: false, child: _EmptyState())
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 140),
                    sliver: SliverList.separated(
                      itemCount: pending.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _PendingRow(request: pending[i], onWithdraw: () => _confirmWithdraw(context, pending[i])),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHero(CaretakerProvider prov) {
    const url = 'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/app/photo-1564352969906-8b7f46ba4b8b.avif?token=eyJraWQiOiJhZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJhcHAvcGhvdG8tMTU2NDM1Mjk2OTkwNi04YjdmNDZiYTRiOGIuYXZpZiIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODc4Njg2MjksImV4cCI6MTgxOTQwNDYyOX0.Jdl-6cqT6wHh_nv8j-7oD3zjU2KcoR4e5ohJVnZgTNs';
    return SliverToBoxAdapter(
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.svcHero,
          image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover, opacity: 0.7),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: Container(color: Colors.black.withValues(alpha: 0.35))),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SafeArea(bottom: false, child: SizedBox(height: 20)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('আপনার ইনবক্স', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -1)),
                      const SizedBox(height: 8),
                      Text(
                        'মোট ${prov.pending.length}টি পেন্ডিং অনুরোধ',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, fontWeight: FontWeight.w800),
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

  Widget _buildSectionTitle(String title, String sub) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.newsInk, letterSpacing: -0.3)),
          Text(sub, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.newsMuted.withValues(alpha: 0.8))),
        ],
      ),
    );
  }

  Future<void> _confirmWithdraw(BuildContext context, CaretakerLink link) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('অনুরোধ প্রত্যাহার?', style: TextStyle(fontWeight: FontWeight.w900)),
        content: const Text('এই রোগীর সাথে সংযোগ অনুরোধ বাতিল করতে চান?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('না')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), style: TextButton.styleFrom(foregroundColor: AppColors.rose), child: const Text('হ্যাঁ, প্রত্যাহার করুন', style: TextStyle(fontWeight: FontWeight.w900))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await context.read<CaretakerProvider>().revoke(link.id ?? '');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(BanglaError.toBangla(e)), backgroundColor: AppColors.rose));
    }
  }
}

class _PendingRow extends StatelessWidget {
  final CaretakerLink request;
  final VoidCallback onWithdraw;
  const _PendingRow({required this.request, required this.onWithdraw});

  @override
  Widget build(BuildContext context) {
    final rel = request.caretakerRelationship ?? 'পরিচর্যাকারী';
    final tsStr = request.requestedAt == null ? '' : RelativeTime.format(request.requestedAt!);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line, width: 1.2)),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: AppColors.svcCategoryBg, borderRadius: BorderRadius.zero),
            child: const Icon(Icons.hourglass_top_rounded, color: AppColors.svcHero, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rel, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.ink)),
                if (tsStr.isNotEmpty) Text(tsStr, style: const TextStyle(fontSize: 12, color: AppColors.smoke, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          MonoButton(
            label: 'প্রত্যাহার',
            onPressed: onWithdraw,
            color: AppColors.rose,
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.send_rounded, color: AppColors.lineStrong, size: 64),
        const SizedBox(height: 16),
        const Text('এখনো কোনো অনুরোধ পাঠানো হয়নি', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.ink)),
        const SizedBox(height: 8),
        const Text('“খোঁজা” ট্যাব থেকে অনুরোধ পাঠান।', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.smoke)),
      ],
    );
  }
}
