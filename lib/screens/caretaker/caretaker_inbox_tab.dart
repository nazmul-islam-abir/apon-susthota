/// Caretaker "ইনবক্স" tab — outgoing link requests the caretaker has
/// sent to patients and that are still pending a response.
///
/// Each row shows the patient full name, mobile (masked), the
/// relationship, and the sent-at timestamp. A "প্রত্যাহার" (withdraw)
/// action calls `CaretakerProvider.revoke(linkId)`. Realtime updates
/// via the wrapping `CaretakerProvider` so an accepted/declined
/// request drops out without a manual refresh.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/caretaker_link.dart';
import '../../services/app_errors.dart';
import '../../services/caretaker_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/relative_time.dart';
import 'caretaker_shell.dart' show CaretakerHeaderStrip;

class CaretakerInboxTab extends StatefulWidget {
  const CaretakerInboxTab({super.key});

  @override
  State<CaretakerInboxTab> createState() => _CaretakerInboxTabState();
}

class _CaretakerInboxTabState extends State<CaretakerInboxTab> {
  @override
  void initState() {
    super.initState();
    // Surface realtime transitions as friendly snackbars.
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeEvents());
  }

  void _consumeEvents() {
    if (!mounted) return;
    final prov = context.read<CaretakerProvider>();
    final ev = prov.consumeLastEvent();
    if (ev == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final isAccepted = ev.kind == 'accepted';
    messenger.showSnackBar(
      SnackBar(
        backgroundColor:
            isAccepted ? AppColors.cyanDeep : AppColors.amber,
        content: Text(
          isAccepted
              ? '✅ ${ev.otherName} আপনার অনুরোধ গ্রহণ করেছেন'
              : '⏳ ${ev.otherName} এখনো সাড়া দেননি',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
    // Re-arm for the next event while the tab stays mounted.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _consumeEvents());
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CaretakerProvider>(
      builder: (context, prov, _) {
        // Listen for new events whenever the provider notifies.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _consumeEvents();
        });
        final pending = prov.pending;
        return RefreshIndicator(
          color: AppColors.violetDeep,
          onRefresh: prov.refreshPending,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: CaretakerHeaderStrip(
                  profile: null,
                  patientCount: prov.activePatientCount,
                  pendingCount: pending.length,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                sliver: SliverToBoxAdapter(
                  child: _SectionHeader(count: pending.length),
                ),
              ),
              if (prov.loadingPending && pending.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: AppColors.violet,
                    ),
                  ),
                )
              else if (pending.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  sliver: SliverList.separated(
                    itemCount: pending.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _PendingRow(
                      request: pending[i],
                      onWithdraw: () => _confirmWithdraw(context, pending[i]),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmWithdraw(
    BuildContext context,
    CaretakerLink link,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('অনুরোধ প্রত্যাহার'),
        content: const Text(
          'এই রোগীর সাথে সংযোগ অনুরোধ প্রত্যাহার করতে চান?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.violet),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('প্রত্যাহার'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      if (!context.mounted) return;
      await context.read<CaretakerProvider>().revoke(link.id ?? '');
      messenger.showSnackBar(
        const SnackBar(content: Text('অনুরোধ প্রত্যাহার করা হয়েছে।')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('প্রত্যাহার ব্যর্থ: ${BanglaError.toBangla(e)}'),
          backgroundColor: AppColors.rose,
        ),
      );
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final int count;
  const _SectionHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        'পাঠানো অনুরোধ ($count)',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: AppColors.text,
          height: 1.2,
        ),
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  final CaretakerLink request;
  final VoidCallback onWithdraw;
  const _PendingRow({required this.request, required this.onWithdraw});

  @override
  Widget build(BuildContext context) {
    final rel = request.caretakerRelationship ?? 'পরিচর্যাকারী';
    final ts = request.requestedAt;
    final tsStr = ts == null
        ? ''
        : RelativeTime.format(ts);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.violet.withValues(alpha: 0.18),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.violet.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.hourglass_top_rounded,
              color: AppColors.violetDeep,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                    height: 1.2,
                  ),
                ),
                if (tsStr.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    tsStr,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ],
                if (request.requestNote != null &&
                    request.requestNote!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    request.requestNote!.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                      fontStyle: FontStyle.italic,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.violetDeep,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: onWithdraw,
            child: const Text(
              'প্রত্যাহার',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.violet.withValues(alpha: 0.16),
                  AppColors.cyan.withValues(alpha: 0.10),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.send_rounded,
              color: AppColors.violetDeep,
              size: 36,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'এখনো কোনো অনুরোধ পাঠানো হয়নি',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '“খোঁজা” ট্যাব থেকে রোগীর নাম বা মোবাইল দিয়ে অনুরোধ পাঠান।',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
