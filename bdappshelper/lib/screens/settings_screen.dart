import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../widgets/gradient_background.dart';
import '../widgets/glass_card.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/bdapps_service.dart';
import '../services/settings_prefs.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'goal_screen.dart';
import 'plan_screen.dart';
import 'diet_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _darkMode = false;
  bool _notifications = true;
  String _language = 'English';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  Future<void> _hydrate() async {
    final dark = await SettingsPrefs.getDarkMode();
    final notif = await SettingsPrefs.getNotifications();
    final lang = await SettingsPrefs.getLanguage();
    if (!mounted) return;
    setState(() {
      _darkMode = dark;
      _notifications = notif;
      _language = lang;
      _loaded = true;
    });
  }

  Future<void> _setDarkMode(bool v) async {
    setState(() => _darkMode = v);
    await SettingsPrefs.setDarkMode(v);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(v ? 'Dark mode on' : 'Dark mode off'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _setNotifications(bool v) async {
    setState(() => _notifications = v);
    await SettingsPrefs.setNotifications(v);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(v ? 'Notifications enabled' : 'Notifications muted'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pickLanguage() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PickerSheet<String>(
        title: 'Language',
        options: const [
          ('English', 'English'),
          ('Bangla', 'Bangla'),
        ],
        current: _language,
      ),
    );
    if (chosen != null) {
      setState(() => _language = chosen);
      await SettingsPrefs.setLanguage(chosen);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Language: $chosen'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _pickDiet() async {
    final p = await ApiService.ensureProfile();
    if (!mounted) return;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PickerSheet<String>(
        title: 'Diet preference',
        options: const [
          ('none', 'No preference'),
          ('vegetarian', 'Vegetarian'),
          ('vegan', 'Vegan'),
          ('halal', 'Halal'),
        ],
        current: (p.dietPref ?? 'none'),
      ),
    );
    if (chosen != null) {
      await ApiService.updateProfile({'diet_pref': chosen});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Diet preference saved: $chosen'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _pickGoal() async {
    final p = await ApiService.ensureProfile();
    if (!mounted) return;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PickerSheet<String>(
        title: 'Health goal',
        options: const [
          ('lose', 'Lose weight'),
          ('maintain', 'Maintain'),
          ('gain', 'Gain weight'),
        ],
        current: (p.goal ?? 'maintain'),
      ),
    );
    if (chosen != null) {
      await ApiService.updateProfile({'goal': chosen});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Health goal saved: $chosen'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openPersonalInfo() async {
    final p = await ApiService.ensureProfile();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditProfileScreen(initial: p)),
    );
  }

  void _openSecurity() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: const Text('Password & security'),
        content: const Text(
          'Amar Diet uses your verified BDApps phone number as the primary '
          'identity. To change your number, log out and re-verify with the '
          'new one.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _openHelp() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: const Text('Help center'),
        content: const Text(
          'Need a hand? Email support@amardiet.app and we\'ll get back to you '
          'within 24 hours.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _openPrivacy() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: const Text('Privacy'),
        content: const Text(
          'All your data — meals, water, weight, profile — is stored locally '
          'on this device using Hive. Nothing is uploaded to a server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Future<void> _onLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to access your data.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.secondary),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await AuthService.instance.signOut();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  Future<void> _confirmUnsubscribe() async {
    final phone = AuthService.instance.phone;
    if (phone == null || phone.isEmpty) {
      _snack('No active session to unsubscribe');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: const Text('Unsubscribe?'),
        content: const Text(
          'You will lose access to Amar Diet until you subscribe again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.secondary),
            child: const Text('Unsubscribe'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final res = await BdappsService.unsubscribe(phone);
    final success = (res['ok'] == true) ||
        (res['success'] == true) ||
        (res['subscriptionStatus']?.toString().toUpperCase() == 'UNREGISTERED');

    if (!mounted) return;
    Navigator.pop(context);

    if (!success) {
      _snack(
        res['statusDetail']?.toString() ??
            res['error']?.toString() ??
            'Could not unsubscribe. Try again.',
      );
      return;
    }

    await AuthService.instance.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        body: SafeArea(
          child: Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
      );
    }
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      color: AppColors.textPrimary,
                    ),
                    const Spacer(),
                    const Text(
                      'Settings',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 44),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.md,
                    AppSpacing.xl,
                    120,
                  ),
                  children: [
                    _Section(title: 'Account', items: [
                      _Item(
                        icon: Icons.person_outline_rounded,
                        label: 'Personal info',
                        trailing: 'Edit',
                        onTap: _openPersonalInfo,
                      ),
                      _Item(
                        icon: Icons.lock_outline_rounded,
                        label: 'Password & security',
                        onTap: _openSecurity,
                      ),
                      _Item(
                        icon: Icons.email_outlined,
                        label: 'Email',
                        trailing: 'Edit',
                        onTap: _openPersonalInfo,
                      ),
                    ]),
                    const SizedBox(height: AppSpacing.lg),
                    _Section(title: 'Preferences', items: [
                      _Item(
                        icon: Icons.language_rounded,
                        label: 'Language',
                        trailing: _language,
                        onTap: _pickLanguage,
                      ),
                      _Item(
                        icon: Icons.dark_mode_outlined,
                        label: 'Dark mode',
                        trailing: _Toggle(
                          value: _darkMode,
                          onChanged: _setDarkMode,
                        ),
                      ),
                      _Item(
                        icon: Icons.notifications_outlined,
                        label: 'Notifications',
                        trailing: _Toggle(
                          value: _notifications,
                          onChanged: _setNotifications,
                        ),
                      ),
                    ]),
                    const SizedBox(height: AppSpacing.lg),
                    _Section(title: 'Diet & health', items: [
                      _Item(
                        icon: Icons.restaurant_outlined,
                        label: 'Diet preferences',
                        onTap: _pickDiet,
                      ),
                      _Item(
                        icon: Icons.warning_amber_rounded,
                        label: 'Allergies',
                        onTap: () => _snack(
                            'Allergy tracking — coming in a future update.'),
                      ),
                      _Item(
                        icon: Icons.flag_outlined,
                        label: 'Health goal',
                        onTap: _pickGoal,
                      ),
                      _Item(
                        icon: Icons.calendar_today_rounded,
                        label: 'Daily plan',
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const PlanScreen(),
                            ),
                          );
                        },
                      ),
                      _Item(
                        icon: Icons.tune_rounded,
                        label: 'Set goal in detail',
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const GoalScreen(),
                            ),
                          );
                        },
                      ),
                      _Item(
                        icon: Icons.local_dining_rounded,
                        label: 'Diet presets',
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const DietScreen(),
                            ),
                          );
                        },
                      ),
                    ]),
                    const SizedBox(height: AppSpacing.lg),
                    _Section(title: 'Support', items: [
                      _Item(
                        icon: Icons.help_outline_rounded,
                        label: 'Help center',
                        onTap: _openHelp,
                      ),
                      _Item(
                        icon: Icons.privacy_tip_outlined,
                        label: 'Privacy policy',
                        onTap: _openPrivacy,
                      ),
                      _Item(
                        icon: Icons.block_rounded,
                        label: 'Unsubscribe',
                        tint: AppColors.secondary,
                        onTap: _confirmUnsubscribe,
                      ),
                      _Item(
                        icon: Icons.logout_rounded,
                        label: 'Log out',
                        tint: AppColors.secondary,
                        onTap: _onLogout,
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.items});
  final String title;
  final List<_Item> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (int i = 0; i < items.length; i++) ...[
                items[i],
                if (i != items.length - 1)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: Divider(height: 1, color: Color(0x14000000)),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.label,
    this.trailing,
    this.tint,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final dynamic trailing;
  final Color? tint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = tint ?? AppColors.primaryDark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: 14,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, color: c, size: 18),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: tint ?? AppColors.textPrimary,
                  ),
                ),
              ),
              if (trailing is Widget)
                trailing as Widget
              else if (trailing is String)
                Text(
                  trailing as String,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Switch.adaptive(
      value: value,
      activeColor: AppColors.primary,
      onChanged: onChanged,
    );
  }
}

class _PickerSheet<T> extends StatelessWidget {
  const _PickerSheet({
    required this.title,
    required this.options,
    required this.current,
  });
  final String title;
  final List<(T, String)> options;
  final T current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 30,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textHint.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final opt in options)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      onTap: () => Navigator.pop(context, opt.$1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.md,
                        ),
                        decoration: BoxDecoration(
                          color: opt.$1 == current
                              ? AppColors.primary.withValues(alpha: 0.12)
                              : AppColors.glassWhite,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                            color: opt.$1 == current
                                ? AppColors.primary
                                : AppColors.glassBorder,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                opt.$2,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            if (opt.$1 == current)
                              const Icon(
                                Icons.check_rounded,
                                color: AppColors.primary,
                                size: 20,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
