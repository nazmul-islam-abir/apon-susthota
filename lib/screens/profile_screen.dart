import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/user_profile.dart';
import '../services/caretaker_provider.dart';
import '../services/supabase_service.dart';
import '../services/app_events.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';
import '../widgets/reminder_settings_sheet.dart';
import 'onboarding_screen.dart';
import 'auth_screen.dart';
import 'notification_screen.dart';
import 'doctor_report_screen.dart';
import 'analytics_screen.dart';
import 'caretaker/people_search_screen.dart';

/// Redesigned Profile screen — professional Bangla look.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  bool _loading = true;
  String? _error;
  String? _avatarSignedUrl;
  bool _uploadingPhoto = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SupabaseService.fetchProfile();
      if (!mounted) return;
      if (p == null) {
        setState(() { _loading = false; _profile = null; });
        return;
      }
      String? signed;
      if (p.avatarUrl != null && p.avatarUrl!.isNotEmpty) {
        final raw = await SupabaseService.getProfilePhotoUrl(p.avatarUrl);
        if (raw.isNotEmpty) {
          final joiner = raw.contains('?') ? '&' : '?';
          signed = '$raw${joiner}_v=${p.photoUploadCount}';
        }
      }
      if (!mounted) return;
      setState(() {
        _profile = p;
        _avatarSignedUrl = signed;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('লগআউট নিশ্চিত করুন', style: TextStyle(fontWeight: FontWeight.w900)),
        content: const Text('আপনি কি সত্যিই অ্যাকাউন্ট থেকে বের হয়ে যেতে চান?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('না')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.rose),
            child: const Text('হ্যাঁ, লগআউট', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    try {
      await SupabaseService.signOut();
      if (!mounted) return;
      // Navigate to AuthScreen and clear stack
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (route) => false,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.void2,
      body: SafeArea(
        child: _loading
            ? const Center(child: LoadingMark())
            : _error != null
                ? _buildError()
                : _profile == null
                    ? _onboardingNeeded()
                    : _buildBody(),
      ),
    );
  }

  Widget _buildError() => Center(child: Text('ত্রুটি: $_error'));

  Widget _buildBody() {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
      children: [
        _Header(),
        const SizedBox(height: 30),
        _ProfileInfo(
          profile: _profile!,
          avatarUrl: _avatarSignedUrl,
          uploading: _uploadingPhoto,
          onChangePhoto: _changePhoto,
        ),
        const SizedBox(height: 32),
        _HealthQuickStats(),
        const SizedBox(height: 24),
        _FamilyCircle(),
        const SizedBox(height: 24),
        _SettingsList(onEdit: _editProfile, onSignOut: _signOut),
      ],
    );
  }

  Future<void> _editProfile() async {
    if (_profile == null) return;
    final res = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => OnboardingScreen(edit: _profile)),
    );
    if (res == true) {
      AppEvents.notifyProfileChanged();
      _load();
    }
  }

  Future<void> _changePhoto() async {
    final source = await _pickPhotoSource();
    if (source == null) return;
    final picked = await _picker.pickImage(source: source, imageQuality: 80);
    if (picked == null) return;
    setState(() => _uploadingPhoto = true);
    try {
      final bytes = await picked.readAsBytes();
      await SupabaseService.uploadProfilePhoto(
        bytes: bytes,
        contentType: picked.mimeType ?? 'image/jpeg',
        originalFileName: picked.name,
      );
      AppEvents.notifyProfileChanged();
      await _load();
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<ImageSource?> _pickPhotoSource() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('গ্যালারি'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text('ক্যামেরা'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
        ],
      ),
    );
  }

  Widget _onboardingNeeded() => const Center(child: Text('অনুগ্রহ করে প্রোফাইল সম্পন্ন করুন'));
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        const Expanded(
          child: Text(
            'স্বাস্থ্য কানেক্ট',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.svcHero,
            ),
          ),
        ),
        IconButton(
          icon: Stack(
            children: [
              const Icon(Icons.notifications_none_rounded, size: 26, color: AppColors.newsInk),
              Positioned(
                right: 2,
                top: 2,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.rose,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationScreen()),
            );
          },
        ),
      ],
    );
  }
}

class _ProfileInfo extends StatelessWidget {
  final UserProfile profile;
  final String? avatarUrl;
  final bool uploading;
  final VoidCallback onChangePhoto;

  const _ProfileInfo({
    required this.profile,
    required this.avatarUrl,
    required this.uploading,
    required this.onChangePhoto,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.line, width: 1),
                borderRadius: BorderRadius.zero,
              ),
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.zero,
                ),
                clipBehavior: Clip.antiAlias,
                child: uploading
                    ? const Center(child: LoadingMark(size: 20))
                    : avatarUrl != null
                        ? Image.network(avatarUrl!, fit: BoxFit.cover)
                        : const Icon(Icons.person, size: 50, color: AppColors.textDim),
              ),
            ),
            GestureDetector(
              onTap: onChangePhoto,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: AppColors.svcHero,
                  borderRadius: BorderRadius.zero,
                ),
                child: const Icon(Icons.edit_rounded, color: Colors.white, size: 16),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          profile.fullName ?? 'ব্যবহারকারী',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.location_on_outlined, size: 14, color: AppColors.smoke),
            SizedBox(width: 4),
            Text(
              'ঢাকা, বাংলাদেশ',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.smoke,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HealthQuickStats extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'স্বাস্থ্যের সংক্ষিপ্ত তথ্য',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.ink),
            ),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AnalyticsScreen())),
              child: const Text(
                'সব দেখুন',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.svcHero),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _StatTile(
          icon: Icons.favorite_rounded,
          color: AppColors.rose,
          label: 'হৃদস্পন্দন',
          value: '72 bpm',
        ),
        const SizedBox(height: 12),
        _StatTile(
          icon: Icons.speed_rounded,
          color: AppColors.violet,
          label: 'রক্তচাপ',
          value: '120/80 mmHg',
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _StatTile({required this.icon, required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.zero,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.smoke)),
                Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.ink)),
              ],
            ),
          ),
          const Icon(Icons.trending_up_rounded, color: AppColors.lineStrong, size: 18),
        ],
      ),
    );
  }
}

class _FamilyCircle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'পরিবার ও আপনজন',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.ink),
            ),
            GestureDetector(
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const PeopleSearchScreen()));
              },
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: AppColors.svcHero, borderRadius: BorderRadius.zero),
                child: const Icon(Icons.add, color: Colors.white, size: 18),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'আপনার স্বাস্থ্যের যত্ন নিচ্ছেন যারা।',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.smoke),
        ),
        const SizedBox(height: 16),
        Consumer<CaretakerProvider>(
          builder: (context, prov, _) {
            final list = prov.activeCaretakers;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  ...list.map((c) => _FamilyMember(
                        name: c.otherFullName ?? 'সদস্য',
                        role: c.caretakerRelationship ?? 'কেয়ারটেকার',
                      )),
                  _InviteMember(),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _FamilyMember extends StatelessWidget {
  final String name;
  final String role;
  const _FamilyMember({required this.name, required this.role});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.zero),
            child: const Icon(Icons.person, color: AppColors.smoke),
          ),
          const SizedBox(height: 6),
          Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
          Text(role, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.smoke)),
        ],
      ),
    );
  }
}

class _InviteMember extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.line, style: BorderStyle.solid),
            borderRadius: BorderRadius.zero,
          ),
          child: const Icon(Icons.person_add_alt_1_outlined, color: AppColors.smoke, size: 20),
        ),
        const SizedBox(height: 6),
        const Text('আমন্ত্রণ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.smoke)),
      ],
    );
  }
}

class _SettingsList extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onSignOut;
  const _SettingsList({required this.onEdit, required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          _SettingItem(icon: Icons.person_outline_rounded, label: 'ব্যক্তিগত তথ্য', onTap: onEdit),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _SettingItem(
            icon: Icons.description_outlined,
            label: 'ডাক্তারের রিপোর্ট',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DoctorReportScreen())),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _SettingItem(
            icon: Icons.assignment_outlined,
            label: 'স্বাস্থ্য রেকর্ড',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AnalyticsScreen())),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _SettingItem(
            icon: Icons.watch_rounded,
            label: 'সংযুক্ত ডিভাইস',
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('এই ফিচারটি শীঘ্রই আসছে।'))),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _SettingItem(icon: Icons.sos_rounded, label: 'জরুরি যোগাযোগ', onTap: () => Navigator.of(context).pushNamed('/sos')),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _SettingItem(
            icon: Icons.settings_outlined,
            label: 'অ্যাপ সেটিংস',
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('অ্যাপ সেটিংস শীঘ্রই আপডেট করা হবে।'))),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _SettingItem(
            icon: Icons.notifications_active_outlined,
            label: 'বিজ্ঞপ্তি',
            onTap: () => ReminderSettingsSheet.show(context),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _SettingItem(
            icon: Icons.menu_book_outlined,
            label: 'অ্যাপ গাইড ও বিস্তারিত',
            onTap: () => Navigator.of(context).pushNamed('/details-home'),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _SettingItem(
            icon: Icons.logout_rounded,
            label: 'লগআউট',
            iconColor: AppColors.rose,
            onTap: onSignOut,
          ),
        ],
      ),
    );
  }
}

class _SettingItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;

  const _SettingItem({required this.icon, required this.label, required this.onTap, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: AppColors.svcCategoryBg, borderRadius: BorderRadius.zero),
        child: Icon(icon, color: iconColor ?? AppColors.svcHero, size: 20),
      ),
      title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.ink)),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.lineStrong),
      onTap: onTap,
    );
  }
}

