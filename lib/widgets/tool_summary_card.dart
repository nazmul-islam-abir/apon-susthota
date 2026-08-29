/// Post-success recap card with an Undo countdown.
///
/// Replaces the [PendingActionCard] once the user taps করুন and the
/// underlying RPC returns OK. Shows a green check, the human-readable
/// description, and a 60-second window during which the user can tap
/// "ফিরিয়ে আনুন" to roll back the change.
///
/// Also auto-removes itself after a few seconds past the timeout so
/// the chat log doesn't grow unbounded.
library;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/ai_chat_service.dart';
import '../services/ai_tools/pending_actions_store.dart';
import '../theme/app_theme.dart';

class ToolSummaryCard extends StatefulWidget {
  const ToolSummaryCard({
    super.key,
    required this.callId,
    required this.description,
  });

  final String callId;
  final String description;

  @override
  State<ToolSummaryCard> createState() => _ToolSummaryCardState();
}

class _ToolSummaryCardState extends State<ToolSummaryCard> {
  bool _undoing = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return ValueListenableBuilder<Map<String, PendingAction>>(
      valueListenable: PendingActionsStore.instance.actions,
      builder: (ctx, map, _) {
        final action = map[widget.callId];
        if (action == null) return const SizedBox.shrink();

        if (action.status == PendingActionStatus.undone) {
          return _Pill(
            color: AppColors.newsMuted,
            icon: Icons.undo_rounded,
            text: l.toolUndone,
          );
        }

        if (action.status == PendingActionStatus.cancelled) {
          return _Pill(
            color: AppColors.newsMuted,
            icon: Icons.cancel_outlined,
            text: l.toolCancelled,
          );
        }

        if (action.status != PendingActionStatus.succeeded) {
          return const SizedBox.shrink();
        }

        final canUndo =
            action.auditId != null && action.undoSecondsRemaining > 0;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.newsSurface,
            border: Border.all(
              color: AppColors.svcAccentGreenBright.withValues(alpha: 0.5),
              width: 1.2,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: AppColors.svcAccentGreenBright, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.description,
                      style: const TextStyle(
                        color: AppColors.newsInk,
                        fontSize: 14,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (canUndo)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: BorderSide(
                            color: AppColors.danger.withValues(alpha: 0.5),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          minimumSize: const Size(0, 32),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: _undoing ? null : () => _undo(action),
                        icon: _undoing
                            ? const SizedBox(
                                height: 14,
                                width: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.danger,
                                ),
                              )
                            : const Icon(Icons.undo_rounded, size: 16),
                        label: Text(
                          l.toolUndoButton(action.undoSecondsRemaining),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )
                    else
                      Text(
                        l.toolUndoExpired,
                        style: TextStyle(
                          color: AppColors.newsMuted,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _undo(PendingAction action) async {
    if (action.auditId == null) return;
    setState(() => _undoing = true);
    try {
      await undoAction(action: action);
    } finally {
      if (mounted) setState(() => _undoing = false);
    }
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.color, required this.icon, required this.text});
  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
