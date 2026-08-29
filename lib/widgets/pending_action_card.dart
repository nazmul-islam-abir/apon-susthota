/// Confirmation card for an AI-proposed write action.
///
/// Rendered inline under the AI bubble while the model is asking
/// "আমি যা করতে চাই:" — gives the user three choices:
///
///   • [করুন]      → fires the underlying RPC, collapses into a
///                   [ToolSummaryCard] with an Undo countdown.
///   • [বাতিল]     → flips status to `cancelled`, removes the card.
///   • [বিস্তারিত] → expands a JSON preview of the tool args.
///
/// Reads its state from [PendingActionsStore.instance] so multiple
/// cards (across multiple tool calls in one turn) stay in sync.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/ai_chat_service.dart';
import '../services/ai_tools/pending_actions_store.dart';
import '../theme/app_theme.dart';
import 'tool_summary_card.dart';

class PendingActionCard extends StatefulWidget {
  const PendingActionCard({
    super.key,
    required this.callId,
    required this.threadId,
    required this.assistantMessageId,
  });

  /// Key into [PendingActionsStore.actions]. The widget rebuilds via
  /// [ValueListenableBuilder] so the parent's setState isn't needed.
  final String callId;
  final String? threadId;
  final String? assistantMessageId;

  @override
  State<PendingActionCard> createState() => _PendingActionCardState();
}

class _PendingActionCardState extends State<PendingActionCard> {
  bool _expanded = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, PendingAction>>(
      valueListenable: PendingActionsStore.instance.actions,
      builder: (ctx, map, _) {
        final action = map[widget.callId];
        if (action == null) return const SizedBox.shrink();

        // Once execution succeeds, swap this card for the summary +
        // Undo countdown. The summary card itself reads from the
        // same store, so the transition is invisible to the user.
        if (action.status == PendingActionStatus.succeeded) {
          return ToolSummaryCard(
            callId: widget.callId,
            description: action.description,
          );
        }
        if (action.status == PendingActionStatus.undone ||
            action.status == PendingActionStatus.cancelled) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: _buildCard(action),
        );
      },
    );
  }

  Widget _buildCard(PendingAction action) {
    final accent = action.status == PendingActionStatus.failed
        ? AppColors.danger
        : AppColors.svcAccentGreenBright;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.newsSurface,
        border: Border.all(color: accent.withValues(alpha: 0.6), width: 1.2),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_iconForStatus(action.status), color: accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'আমি যা করতে চাই:',
                  style: TextStyle(
                    color: AppColors.newsMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            action.description,
            style: const TextStyle(
              color: AppColors.newsInk,
              fontSize: 15,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 10),
            _ArgsPreview(callId: widget.callId),
          ],
          if (action.status == PendingActionStatus.failed) ...[
            const SizedBox(height: 8),
            Text(
              action.errorMessage ?? 'কিছু একটা ভুল হয়েছে — আবার চেষ্টা করুন।',
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.svcChipBg,
                    foregroundColor: AppColors.svcHeroInk,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _busy ? null : () => _confirm(),
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'করুন',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.newsInk,
                    side: const BorderSide(color: AppColors.newsDivider),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _busy ? null : () => _cancel(),
                  child: const Text(
                    'বাতিল',
                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: _expanded ? 'বন্ধ করুন' : 'বিস্তারিত দেখুন',
                onPressed: _busy ? null : () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  color: AppColors.newsMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _iconForStatus(PendingActionStatus s) {
    switch (s) {
      case PendingActionStatus.awaiting:
        return Icons.pending_actions_rounded;
      case PendingActionStatus.executing:
        return Icons.sync_rounded;
      case PendingActionStatus.failed:
        return Icons.error_outline_rounded;
      default:
        return Icons.check_circle_outline_rounded;
    }
  }

  Future<void> _confirm() async {
    final action = PendingActionsStore.instance.actions.value[widget.callId];
    if (action == null) return;

    setState(() => _busy = true);
    try {
      final result = await executeConfirmedAction(
        action: action,
        threadId: widget.threadId,
        messageId: widget.assistantMessageId,
      );
      if (!mounted) return;
      // executeConfirmedAction already updates auditId/status/errorMessage.
      // We also need inverseArgs so the Undo path has the pre-image.
      PendingActionsStore.instance.update(widget.callId, (a) {
        a.inverseArgs = result.inverseArgs;
        return a;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _cancel() {
    PendingActionsStore.instance.update(
      widget.callId,
      (a) => a..status = PendingActionStatus.cancelled,
    );
    // Keep the (cancelled) entry for a few seconds so the user sees
    // the "ফিরে গেছে" pill, then drop it.
    Future.delayed(const Duration(seconds: 4), () {
      if (PendingActionsStore.instance.actions.value.containsKey(widget.callId)) {
        PendingActionsStore.instance.remove(widget.callId);
      }
    });
  }
}

class _ArgsPreview extends StatelessWidget {
  const _ArgsPreview({required this.callId});
  final String callId;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, PendingAction>>(
      valueListenable: PendingActionsStore.instance.actions,
      builder: (ctx, map, _) {
        final action = map[callId];
        if (action == null) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.newsSurfaceSoft,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.newsDivider),
          ),
          child: Text(
            const JsonEncoder.withIndent('  ').convert({
              'tool': action.toolName,
              'args': action.toolArgs,
            }),
            style: const TextStyle(
              color: AppColors.newsInk,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        );
      },
    );
  }
}
