library;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../services/app_events.dart';
import '../../services/supabase_service.dart';
import '../../services/caretaker_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/mono_widgets.dart';
import '../../widgets/account_actions.dart';
import '../../widgets/reminder_settings_sheet.dart';
import '../notification_screen.dart';

/// Caretaker's own profile screen — redesigned to match the patient's
/// profile screen look (Nexora style).
class CaretakerDoctorProfileScreen extends StatefulWidget {
  const CaretakerDoctorProfileScreen({super.key});

  @override
  State<CaretakerDoctorProfileScreen> createState() =>
      _CaretakerDoctorProfileScreenState();
}

class _CaretakerDoctorProfileScreenState
    extends State<CaretakerDoctorProfileScreen> {
  Map<String, dynamic>? _data;
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
      final data = await SupabaseService.getMyDoctorProfile();
      if (!mounted) return;
      
      final rawAvatar = data['avatar_url'] as String?;
      String? signed;
      if (rawAvatar != null && rawAvatar.isNotEmpty) {
        signed = await SupabaseService.getProfilePhotoUrl(rawAvatar);
        if (signed.isNotEmpty) {
          final joiner = signed.contains('?') ? '&' : '?';
          signed = '$signed${joiner}_v=${data['photo_upload_count'] ?? 0}';
        }
      }
      
      if (!mounted) return;
      setState(() {
        _data = data;
        _avatarSignedUrl = signed;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _signOut() => AccountActions.confirmLogout(context);
  Future<void> _unsubscribe() => AccountActions.runUnsubscribe(context);
  Future<void> _deleteAccount() => AccountActions.runDeleteAccount(context);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.void2,
      body: SafeArea(
        child: _loading
            ? const Center(child: LoadingMark())
            : _error != null
                ? Center(child: Text('ত্রুটি: $_error'))
                : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final name = (_data?['full_name'] as String?) ?? 'পরিচর্যাকারী';
    final username = (_data?['username'] as String?) ?? '';
    final specialty = (_data?['doctor_specialty'] as String?) ?? 'বিশেষজ্ঞতা নেই';

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
      children: [
        _Header(),
        const SizedBox(height: 30),
        _ProfileInfo(
          name: name,
          username: username,
          specialty: specialty,
          avatarUrl: _avatarSignedUrl,
          uploading: _uploadingPhoto,
          onChangePhoto: _changePhoto,
        ),
        const SizedBox(height: 32),
        _ProfessionalStats(data: _data!),
        const SizedBox(height: 24),
        _PatientsCircle(),
        const SizedBox(height: 24),
        _SettingsList(
          onEdit: _editProfile,
          onSignOut: _signOut,
          onUnsubscribe: _unsubscribe,
          onDeleteAccount: _deleteAccount,
        ),
      ],
    );
  }

  Future<void> _editProfile() async {
    final res = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _CaretakerEditForm(initialData: _data!)),
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
            'পরিচর্যাকারী প্রোফাইল',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.svcHero,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.notifications_none_rounded, size: 26, color: AppColors.newsInk),
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
  final String name;
  final String username;
  final String specialty;
  final String? avatarUrl;
  final bool uploading;
  final VoidCallback onChangePhoto;

  const _ProfileInfo({
    required this.name,
    required this.username,
    required this.specialty,
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
          name,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: AppColors.ink,
          ),
        ),
        if (username.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '@$username',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.smoke,
                letterSpacing: 0.4,
              ),
            ),
          ),
        const SizedBox(height: 4),
        Text(
          specialty,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.smoke,
          ),
        ),
      ],
    );
  }
}

class _ProfessionalStats extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ProfessionalStats({required this.data});

  @override
  Widget build(BuildContext context) {
    final exp = data['doctor_years_experience']?.toString() ?? '0';
    final clinic = (data['doctor_clinic_name'] as String?) ?? 'তথ্য নেই';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'পেশাদার তথ্য',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.ink),
        ),
        const SizedBox(height: 14),
        _StatTile(
          icon: Icons.timeline_rounded,
          color: AppColors.svcHero,
          label: 'অভিজ্ঞতা',
          value: '$exp বছর',
        ),
        const SizedBox(height: 12),
        _StatTile(
          icon: Icons.local_hospital_rounded,
          color: AppColors.violet,
          label: 'ক্লিনিক / হাসপাতাল',
          value: clinic,
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
                Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.ink)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PatientsCircle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'সংযুক্ত রোগী',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.ink),
        ),
        const SizedBox(height: 4),
        const Text(
          'যাদের স্বাস্থ্যের আপনি যত্ন নিচ্ছেন।',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.smoke),
        ),
        const SizedBox(height: 16),
        Consumer<CaretakerProvider>(
          builder: (context, prov, _) {
            final list = prov.patients;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  ...list.map((p) => _PatientMember(
                        name: p.fullName.isEmpty ? 'রোগী' : p.fullName,
                      )),
                  if (list.isEmpty)
                    const Text('কোনো সংযুক্ত রোগী নেই', style: TextStyle(color: AppColors.smoke, fontSize: 13)),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _PatientMember extends StatelessWidget {
  final String name;
  const _PatientMember({required this.name});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.zero),
            child: const Icon(Icons.person, color: AppColors.smoke),
          ),
          const SizedBox(height: 6),
          Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _SettingsList extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onSignOut;
  final VoidCallback onUnsubscribe;
  final VoidCallback onDeleteAccount;
  const _SettingsList({
    required this.onEdit,
    required this.onSignOut,
    required this.onUnsubscribe,
    required this.onDeleteAccount,
  });

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
          _SettingItem(icon: Icons.person_outline_rounded, label: 'ব্যক্তিগত তথ্য ও প্রোফাইল', onTap: onEdit),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _SettingItem(
            icon: Icons.notifications_active_outlined,
            label: 'বিজ্ঞপ্তি',
            onTap: () => ReminderSettingsSheet.show(context),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _SettingItem(icon: Icons.sos_rounded, label: 'জরুরি যোগাযোগ', onTap: () => Navigator.of(context).pushNamed('/sos')),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _SettingItem(
            icon: Icons.menu_book_outlined,
            label: 'অ্যাপ গাইড ও বিস্তারিত',
            onTap: () => Navigator.of(context).pushNamed('/details-home'),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _SettingItem(
            icon: Icons.block_rounded,
            label: 'সাবস্ক্রিপশন বাতিল করুন',
            iconColor: AppColors.amber,
            onTap: onUnsubscribe,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _SettingItem(
            icon: Icons.delete_forever_rounded,
            label: 'অ্যাকাউন্ট মুছুন',
            iconColor: AppColors.rose,
            onTap: onDeleteAccount,
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
        decoration: const BoxDecoration(color: AppColors.svcCategoryBg, borderRadius: BorderRadius.zero),
        child: Icon(icon, color: iconColor ?? AppColors.svcHero, size: 20),
      ),
      title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.ink)),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.lineStrong),
      onTap: onTap,
    );
  }
}

/// The edit form screen, pushed when tapping "ব্যক্তিগত তথ্য".
class _CaretakerEditForm extends StatefulWidget {
  final Map<String, dynamic> initialData;
  const _CaretakerEditForm({required this.initialData});

  @override
  State<_CaretakerEditForm> createState() => _CaretakerEditFormState();
}

class _CaretakerEditFormState extends State<_CaretakerEditForm> {
  final _fullName = TextEditingController();
  final _username = TextEditingController();
  final _bio = TextEditingController();
  final _specialty = TextEditingController();
  final _license = TextEditingController();
  final _clinic = TextEditingController();
  final _years = TextEditingController();
  final _qualifications = TextEditingController();
  final _languages = TextEditingController();
  final _availability = TextEditingController();
  final _credentials = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.initialData;
    _fullName.text = (d['full_name'] as String?) ?? '';
    _username.text = (d['username'] as String?) ?? '';
    _bio.text = (d['doctor_bio'] as String?) ?? '';
    _specialty.text = (d['doctor_specialty'] as String?) ?? '';
    _license.text = (d['doctor_license_number'] as String?) ?? '';
    _clinic.text = (d['doctor_clinic_name'] as String?) ?? '';
    final y = d['doctor_years_experience'];
    _years.text = (y is num) ? y.toInt().toString() : (y is String ? y : '');
    _qualifications.text = (d['doctor_qualifications'] as String?) ?? '';
    _languages.text = (d['doctor_languages'] as String?) ?? '';
    _availability.text = (d['doctor_availability'] as String?) ?? '';
    _credentials.text = (d['doctor_credentials'] as String?) ?? '';
  }

  @override
  void dispose() {
    _fullName.dispose();
    _username.dispose();
    _bio.dispose();
    _specialty.dispose();
    _license.dispose();
    _clinic.dispose();
    _years.dispose();
    _qualifications.dispose();
    _languages.dispose();
    _availability.dispose();
    _credentials.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final years = int.tryParse(_years.text.trim());
      await SupabaseService.updateMyDoctorProfile(
        fullName: _fullName.text.trim(),
        username: _username.text.trim(),
        bio: _bio.text.trim(),
        specialty: _specialty.text.trim(),
        licenseNumber: _license.text.trim(),
        clinicName: _clinic.text.trim(),
        yearsExperience: years,
        qualifications: _qualifications.text.trim(),
        languages: _languages.text.trim(),
        availability: _availability.text.trim(),
        credentials: _credentials.text.trim(),
        profileCompleted: true,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ত্রুটি: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.svcHero,
        foregroundColor: Colors.white,
        title: const Text('তথ্য এডিট করুন', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          if (_saving)
            const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
          else
            TextButton(onPressed: _save, child: const Text('সংরক্ষণ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildSection('মৌলিক তথ্য'),
          _field(_fullName, 'পূর্ণ নাম', 'আপনার নাম লিখুন', Icons.person_rounded),
          _field(_username, 'ইউজারনেম', '৬ অক্ষরের ইউজারনেম', Icons.alternate_email_rounded),
          const SizedBox(height: 20),
          _buildSection('পেশাগত তথ্য'),
          _field(_specialty, 'বিশেষজ্ঞতা', 'যেমন: ডায়াবেটিস', Icons.medical_services_rounded),
          _field(_clinic, 'ক্লিনিক / হাসপাতাল', 'যেখানে প্র্যাকটিস করেন', Icons.local_hospital_rounded),
          _field(_years, 'অভিজ্ঞতা (বছর)', 'যেমন: ৫', Icons.timeline_rounded, keyboardType: TextInputType.number),
          _field(_license, 'লাইসেন্স নম্বর', 'বিএমডিসি নম্বর', Icons.badge_rounded),
          const SizedBox(height: 20),
          _buildSection('বিস্তারিত তথ্য'),
          _field(_qualifications, 'যোগ্যতা', 'যেমন: এমবিবিএস, এমডি', Icons.school_rounded, maxLines: 2),
          _field(_languages, 'ভাষা', 'যেমন: বাংলা, ইংরেজি', Icons.translate_rounded),
          _field(_availability, 'প্র্যাকটিসের সময়', 'যেমন: রবি-বৃহঃ সন্ধ্যা ৬টা-৯টা', Icons.schedule_rounded),
          const SizedBox(height: 20),
          _buildSection('অতিরিক্ত'),
          _field(_bio, 'নিজের সম্পর্কে', 'সংক্ষেপে বর্ণনা করুন', Icons.edit_note_rounded, maxLines: 4),
          _field(_credentials, 'প্রমাণপত্র / অন্যান্য', 'পুরস্কার বা বিশেষ অর্জন', Icons.verified_rounded, maxLines: 2),
        ],
      ),
    );
  }

  Widget _buildSection(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.svcHero)),
    );
  }

  Widget _field(TextEditingController ctrl, String label, String hint, IconData icon, {int maxLines = 1, TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, size: 14, color: AppColors.svcHero), const SizedBox(width: 6), Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800))]),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            maxLines: maxLines,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              hintText: hint,
              fillColor: AppColors.chalk,
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: AppColors.line)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}
