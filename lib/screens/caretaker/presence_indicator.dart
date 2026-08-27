/// Realtime presence chip — a small animated dot that indicates the
/// caretaker has this patient's data open *right now* in the last
/// 5 minutes. Drives off the `last_seen_at` column already updated by
/// `get_caretaker_today_overview`; no extra realtime plumbing needed.
///
/// Usage: drop a `PresenceIndicator(lastSeenAt: patient.lastSeenAt)`
/// into a card. Returns SizedBox.shrink() when the patient hasn't
/// been opened in the last 5 minutes so the UI doesn't fill with
/// dead chips.
library;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class PresenceIndicator extends StatelessWidget {
  /// Timestamp the caretaker last opened the patient. UTC.
  final DateTime? lastSeenAt;

  /// How long the chip stays green after the lastSeenAt timestamp.
  final Duration freshnessWindow;
  const PresenceIndicator({
    super.key,
    required this.lastSeenAt,
    this.freshnessWindow = const Duration(minutes: 5),
  });

  @override
  Widget build(BuildContext context) {
    final ts = lastSeenAt?.toLocal();
    if (ts == null) return const SizedBox.shrink();
    final age = DateTime.now().difference(ts);
    if (age.isNegative || age > freshnessWindow) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.cyan.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.cyanDeep,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'এইমাত্র দেখছেন',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              color: AppColors.cyanDeep,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}