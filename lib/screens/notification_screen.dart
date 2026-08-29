/// lib/screens/notification_screen.dart
///
/// Notification inbox — redesigned to match the professional forest green hero aesthetic.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  late Future<List<AppNotification>> _future;

  @override
  void initState() {
    super.initState();
    _future = NotificationService.load(force: true);
  }

  Future<void> _refresh() async {
    HapticFeedback.selectionClick();
    setState(() { _future = NotificationService.load(force: true); });
    await _future;
  }

  Future<void> _markAllRead(List<AppNotification> list) async {
    HapticFeedback.lightImpact();
    final unread = list.where((n) => n.isUnread).toList();
    for (final n in unread) { await NotificationService.markRead(n.id); }
    if (!mounted) return;
    setState(() { _future = NotificationService.load(force: true); });
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
          child: FutureBuilder<List<AppNotification>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const Center(child: LoadingMark());
              if (snap.hasError) return _ErrorState(error: snap.error!, onRetry: _refresh);
              
              final list = snap.data ?? const [];

              return CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                slivers: [
                  _buildHero(context, list),
                  if (list.isEmpty)
                    const SliverFillRemaining(hasScrollBody: false, child: _EmptyState())
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
                      sliver: SliverList.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        itemBuilder: (_, i) => _NotificationCard(
                          notification: list[i],
                          onChanged: () { if (mounted) setState(() { _future = NotificationService.load(); }); },
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context, List<AppNotification> list) {
    const url = 'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/app/photo-1564352969906-8b7f46ba4b8b.avif?token=eyJraWQiOiJhZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJhcHAvcGhvdG8tMTU2NDM1Mjk2OTkwNi04YjdmNDZiYTRiOGIuYXZpZiIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODc4Njg2MjksImV4cCI6MTgxOTQwNDYyOX0.Jdl-6cqT6wHh_nv8j-7oD3zjU2KcoR4e5ohJVnZgTNs';
    final hasUnread = list.any((n) => n.isUnread);

    return SliverToBoxAdapter(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.svcHero,
          image: const DecorationImage(image: NetworkImage(url), fit: BoxFit.cover, opacity: 0.7),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: Container(color: Colors.black.withValues(alpha: 0.3))),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 20, 0),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const Expanded(
                          child: Text(
                            'বিজ্ঞপ্তি কেন্দ্র',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                          ),
                        ),
                        if (hasUnread)
                          TextButton.icon(
                            onPressed: () => _markAllRead(list),
                            icon: const Icon(Icons.done_all_rounded, size: 18, color: Colors.white),
                            label: const Text('সব পড়ুন', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                          ),
                      ],
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 40, 24, 48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('NOTIFICATIONS', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),
                      SizedBox(height: 8),
                      Text(
                        'আপনার স্বাস্থ্যের নতুন\nসংবাদ ও আপডেট',
                        style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -0.6),
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

class _NotificationCard extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onChanged;
  const _NotificationCard({required this.notification, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final unread = n.isUnread;
    final color = _colorFor(n.category);
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: unread ? AppColors.svcHero : AppColors.line, width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.zero),
                  child: Icon(_iconFor(n.category), color: color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(_categoryLabel(n.category), style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                          const SizedBox(width: 8),
                          Text(_timeAgo(n.createdAt), style: const TextStyle(color: AppColors.smoke, fontSize: 11, fontWeight: FontWeight.w700)),
                          const Spacer(),
                          if (unread) Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(n.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.ink, height: 1.2)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (n.shortMessage != null && n.shortMessage!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(n.shortMessage!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.smoke, height: 1.4)),
            ),
          if (n.imageUrl != null && n.imageUrl!.isNotEmpty)
            Container(
              height: 180,
              decoration: BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: AppColors.line))),
              child: Image.network(n.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            ),
          if (n.actionUrl != null && n.actionUrl!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: InkWell(
                onTap: () async {
                  HapticFeedback.selectionClick();
                  await NotificationService.handleAction(n);
                  onChanged();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(color: AppColors.svcHero, borderRadius: BorderRadius.zero),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(n.actionLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 16),
                    ],
                  ),
                ),
              ),
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }

  IconData _iconFor(String cat) {
    return switch (cat) {
      'greeting' => Icons.celebration_rounded,
      'update' => Icons.system_update_rounded,
      'tip' => Icons.lightbulb_rounded,
      'alert' => Icons.priority_high_rounded,
      _ => Icons.campaign_rounded,
    };
  }

  Color _colorFor(String cat) {
    return switch (cat) {
      'greeting' => Colors.amber[800]!,
      'update' => Colors.blue[800]!,
      'tip' => AppColors.svcHeroAccent,
      'alert' => AppColors.rose,
      _ => AppColors.svcHero,
    };
  }

  String _categoryLabel(String cat) {
    return switch (cat) {
      'greeting' => 'শুভেচ্ছা',
      'update' => 'আপডেট',
      'tip' => 'পরামর্শ',
      'alert' => 'সতর্কতা',
      _ => 'ঘোষণা',
    };
  }

  String _timeAgo(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'এইমাত্র';
    if (diff.inMinutes < 60) return '${diff.inMinutes} মি আগে';
    if (diff.inHours < 24) return '${diff.inHours} ঘণ্টা আগে';
    return '${diff.inDays} দিন আগে';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none_rounded, size: 64, color: AppColors.svcHero.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          const Text('কোনো বিজ্ঞপ্তি নেই', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.smoke)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.rose),
          const SizedBox(height: 16),
          const Text('বিজ্ঞপ্তি লোড করতে সমস্যা হয়েছে', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 24),
          MonoButton(label: 'আবার চেষ্টা করুন', onPressed: onRetry),
        ],
      ),
    );
  }
}
