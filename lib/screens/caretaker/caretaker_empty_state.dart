/// First-run empty state for newly-signed-up caretakers.
///
/// The "রোগী" tab is normally a list of linked patients, but if
/// nobody has been added yet, this state explains how to start —
/// searching by name, email or mobile in the "খোঁজা" tab (or the
/// directory floating action button).
///
/// Renders three quick "how it works" cards and a primary CTA that
/// jumps to tab 3 (search).
library;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class CaretakerEmptyState extends StatelessWidget {
  final ValueChanged<int> onSwitchTab;
  const CaretakerEmptyState({super.key, required this.onSwitchTab});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Hero "कोई patient नहीं" icon.
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.violet.withValues(alpha: 0.16),
                    AppColors.cyan.withValues(alpha: 0.10),
                  ],
                ),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.people_alt_rounded,
                color: AppColors.violetDeep,
                size: 44,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'চলুন শুরু করা যাক',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.text,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'প্রথম রোগী যোগ করতে নিচের তিনটি সহজ ধাপ অনুসরণ করুন — '
              'নাম, ইমেইল বা মোবাইল নম্বর দিয়েই খুঁজে পাবেন।',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            const _Step(
              step: '১',
              title: '“খোঁজা” ট্যাবে যান',
              body:
                  'নিচের “খোঁজা” আইকনে ট্যাপ করুন — বা এই পর্দার “রোগী খুঁজুন” বোতাম।',
            ),
            const SizedBox(height: 10),
            const _Step(
              step: '২',
              title: 'নাম বা মোবাইল দিয়ে খুঁজুন',
              body:
                  'রোগীর নাম, ইমেইল বা মোবাইল নম্বর — যেকোনোটি লিখে খুঁজুন। মিল পেলে ট্যাপ করুন।',
            ),
            const SizedBox(height: 10),
            const _Step(
              step: '৩',
              title: 'সম্পর্ক বেছে অনুরোধ পাঠান',
              body:
                  'পিতা, মাতা, সন্তান — আপনার সম্পর্কটি বাছাই করে “অনুরোধ পাঠান”। রোগী গ্রহণ করলেই আপনি তার দিনের সারাংশ দেখতে পাবেন।',
            ),
            const SizedBox(height: 26),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.violetDeep,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
              ),
              onPressed: () => onSwitchTab(3),
              icon: const Icon(Icons.search_rounded),
              label: const Text(
                'রোগী খুঁজুন',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '“খোঁজা” ট্যাবে গিয়ে শুরু করুন',
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.textDim.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String step;
  final String title;
  final String body;
  const _Step({
    required this.step,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.violet.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              step,
              style: const TextStyle(
                color: AppColors.violetDeep,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
