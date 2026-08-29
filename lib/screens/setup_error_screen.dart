import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';

/// Shown instead of a blank white screen when the Supabase client can't
/// initialise — most commonly because `.env` is missing or the keys are
/// blank. The screen gives the developer a precise Bangla + English
/// remediation path so they don't have to read a Flutter crash log to
/// figure out what to do.
class SetupErrorScreen extends StatelessWidget {
  const SetupErrorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (l == null) return const Scaffold(body: Center(child: Text('Setup Error')));
    final msg = SupabaseService.initError ?? l.setupErrorUnknown;
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Overline(l.setupErrorOverline),
              const SizedBox(height: 6),
              Text(
                l.setupErrorHeadline,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.line),
                ),
                child: Text(
                  msg,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                l.setupErrorStepsTitle,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 10),
              _Step(
                n: '১',
                title: l.setupErrorStep1Title,
                body: l.setupErrorStep1Body,
              ),
              const SizedBox(height: 10),
              _Step(
                n: '২',
                title: l.setupErrorStep2Title,
                body: l.setupErrorStep2Body,
              ),
              const SizedBox(height: 10),
              _Step(
                n: '৩',
                title: l.setupErrorStep3Title,
                body: l.setupErrorStep3Body,
              ),
              const Spacer(),
              MonoButton(
                label: l.setupErrorCopyButton,
                leading: Icons.copy_rounded,
                onPressed: () async {
                  await Clipboard.setData(const ClipboardData(
                      text: 'SUPABASE_URL / SUPABASE_ANON_KEY'));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l.setupErrorCopied),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String n;
  final String title;
  final String body;
  const _Step({
    required this.n,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.cyan,
            shape: BoxShape.circle,
          ),
          child: Text(
            n,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.void1,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.smoke,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
