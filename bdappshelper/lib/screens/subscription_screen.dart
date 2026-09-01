import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../widgets/gradient_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/app_button.dart';
import '../services/auth_service.dart';
import '../services/bdapps_service.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  String _status = 'pending';
  String _statusDetail = '';
  bool _loadingStatus = true;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final phone = AuthService.instance.phone;
    if (phone == null || phone.isEmpty) {
      if (!mounted) return;
      setState(() {
        _status = 'unknown';
        _statusDetail = 'No active session';
        _loadingStatus = false;
      });
      return;
    }
    try {
      final res = await BdappsService.checkSubscription(phone);
      final raw = res['subscriptionStatus']?.toString().toUpperCase().trim() ??
          '';
      if (!mounted) return;
      setState(() {
        _status = raw.isEmpty ? 'UNKNOWN' : raw;
        _statusDetail = res['statusDetail']?.toString() ?? '';
        _loadingStatus = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'ERROR';
        _statusDetail = e.toString();
        _loadingStatus = false;
      });
    }
  }

  bool get _isActive {
    return _status.isNotEmpty &&
        _status != 'UNREGISTERED' &&
        _status != 'UNKNOWN' &&
        _status != 'ERROR';
  }

  void _onContinue() {
    final msg = _statusDetail.isNotEmpty
        ? 'Current status: $_status — $_statusDetail'
        : 'Current status: $_status';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.md,
                  AppSpacing.xl,
                  140,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_ios_new_rounded),
                          color: AppColors.textPrimary,
                        ),
                        const Spacer(),
                        const Text(
                          'Subscription',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: _loadingStatus ? null : _refreshStatus,
                          icon: const Icon(Icons.refresh_rounded),
                          color: AppColors.textSecondary,
                          tooltip: 'Refresh status',
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _StatusBanner(
                      loading: _loadingStatus,
                      active: _isActive,
                      status: _status,
                      detail: _statusDetail,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const Center(
                      child: Text(
                        'Subscribe to Pro',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Center(
                      child: Text(
                        'Unlock personalised plans & insights',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    GlassCard(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      AppColors.primary,
                                      AppColors.primaryDark,
                                    ],
                                  ),
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.md),
                                ),
                                child: const Icon(
                                  Icons.bolt_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              const Expanded(
                                child: Text(
                                  'চার্জ: ২.৭৮ টাকা/দিন (ভ্যাট+এসসি+এসডি সহ)',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textPrimary,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.sm,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.secondary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              border: Border.all(
                                color:
                                    AppColors.secondary.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: const [
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 16,
                                  color: AppColors.secondary,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'শুধুমাত্র Robi ও Airtel গ্রাহকদের জন্য।',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          const Text(
                            'Pro includes',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          const _FeatureRow(label: 'Personalised diet plan'),
                          const _FeatureRow(label: 'Smart meal recommendations'),
                          const _FeatureRow(
                              label: 'Detailed progress analytics'),
                          const _FeatureRow(
                              label: 'Hilsa & seasonal Bangladeshi meals'),
                          const _FeatureRow(label: 'Ad-free experience'),
                          const _FeatureRow(label: 'Priority support'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: AppSpacing.xl,
                right: AppSpacing.xl,
                bottom: AppSpacing.xl,
                child: AppButton(
                  label: _isActive ? 'View current status' : 'Show current status',
                  icon: Icons.lock_rounded,
                  onPressed: _onContinue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.loading,
    required this.active,
    required this.status,
    required this.detail,
  });

  final bool loading;
  final bool active;
  final String status;
  final String detail;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    IconData icon;
    String headline;
    String sub;

    if (loading) {
      bg = AppColors.info.withValues(alpha: 0.12);
      fg = AppColors.info;
      icon = Icons.hourglass_top_rounded;
      headline = 'সাবস্ক্রিপশন যাচাই হচ্ছে…';
      sub = 'অপেক্ষা করুন, আপনার বর্তমান অবস্থা যাচাই করা হচ্ছে।';
    } else if (active) {
      bg = AppColors.success.withValues(alpha: 0.12);
      fg = AppColors.success;
      icon = Icons.verified_rounded;
      headline = 'সাবস্ক্রিপশন চালু আছে ✅';
      sub = detail.isNotEmpty
          ? 'অবস্থা: $status — $detail'
          : 'অবস্থা: $status। সব প্রো ফিচার ব্যবহার করুন।';
    } else if (status == 'UNREGISTERED' || status == 'UNKNOWN') {
      bg = AppColors.secondary.withValues(alpha: 0.12);
      fg = AppColors.secondaryDark;
      icon = Icons.error_outline_rounded;
      headline = 'আপনি এখনো সাবস্ক্রাইব করেননি';
      sub = detail.isNotEmpty
          ? 'অবস্থা: $status — $detail'
          : 'অবস্থা: $status। প্রো ফিচার আনলক করতে সাবস্ক্রাইব করুন।';
    } else {
      bg = AppColors.warning.withValues(alpha: 0.15);
      fg = AppColors.warning;
      icon = Icons.warning_amber_rounded;
      headline = 'অবস্থা যাচাই করা যাচ্ছে না';
      sub = detail.isNotEmpty
          ? detail
          : 'নেটওয়ার্ক সমস্যা হতে পারে। আবার চেষ্টা করুন।';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          loading
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: fg,
                  ),
                )
              : Icon(icon, color: fg, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
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

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 14),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
