import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../services/app_events.dart';
import '../../services/bdapps/bdapps_session_service.dart';
import '../../services/supabase_service.dart';
import '../../services/caretaker_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/mono_widgets.dart';
import '../../widgets/account_actions.dart';
import '../../widgets/reminder_settings_sheet.dart';
import '../notification_screen.dart';

/// Caretaker's own profile screen — designed for the "relatives"
/// caretaking flow: son/daughter/spouse/etc. of a diabetic parent.
///
/// The form asks for the relationship to the patient, a contact phone,
/// an optional address, and an optional free-text note. The old
/// doctor-style columns (specialty, license, clinic, years of
/// experience, languages, credentials) have been re-purposed as
/// relatives info by SQL migration 56 — see
/// `supabasesql/56_caretaker_relatives_rename.sql`.
class CaretakerProfileScreen extends StatefulWidget {
  const CaretakerProfileScreen({super.key});

  @override
  State<CaretakerProfileScreen> createState() => _CaretakerProfileScreenState();
}

class _CaretakerProfileScreenState extends State<CaretakerProfileScreen> {
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
      final data = await SupabaseService.getMyCaretakerProfile();
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
    final relationship = (_data?['caretaker_specialty'] as String?) ?? '';

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
      children: [
        _Header(),
        const SizedBox(height: 30),
        _ProfileInfo(
          name: name,
          username: username,
          relationship: relationship,
          avatarUrl: _avatarSignedUrl,
          uploading: _uploadingPhoto,
          onChangePhoto: _changePhoto,
        ),
        const SizedBox(height: 32),
        _RelativesInfo(data: _data!),
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
  final String relationship;
  final String? avatarUrl;
  final bool uploading;
  final VoidCallback onChangePhoto;

  const _ProfileInfo({
    required this.name,
    required this.username,
    required this.relationship,
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
        if (relationship.isNotEmpty)
          Text(
            relationship,
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

class _RelativesInfo extends StatelessWidget {
  final Map<String, dynamic> data;
  const _RelativesInfo({required this.data});

  @override
  Widget build(BuildContext context) {
    final phone = (data['caretaker_contact_phone'] as String?) ?? '';
    final address = (data['caretaker_address'] as String?) ?? '';
    final availability = (data['caretaker_availability'] as String?) ?? '';

    final hasAny =
        phone.isNotEmpty || address.isNotEmpty || availability.isNotEmpty;
    if (!hasAny) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'যোগাযোগের তথ্য',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.ink),
        ),
        const SizedBox(height: 14),
        if (phone.isNotEmpty)
          _InfoTile(
            icon: Icons.phone_in_talk_rounded,
            color: AppColors.svcHero,
            label: 'যোগাযোগ নম্বর',
            value: phone,
          ),
        if (phone.isNotEmpty && (address.isNotEmpty || availability.isNotEmpty))
          const SizedBox(height: 12),
        if (address.isNotEmpty)
          _InfoTile(
            icon: Icons.location_on_outlined,
            color: AppColors.violet,
            label: 'ঠিকানা',
            value: address,
          ),
        if (address.isNotEmpty && availability.isNotEmpty)
          const SizedBox(height: 12),
        if (availability.isNotEmpty)
          _InfoTile(
            icon: Icons.schedule_rounded,
            color: AppColors.cyan,
            label: 'যোগাযোগের সময়',
            value: availability,
          ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _InfoTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

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
  final _relationship = TextEditingController();
  final _contactPhone = TextEditingController();
  final _address = TextEditingController();
  final _note = TextEditingController();
  final _availability = TextEditingController();

  bool _saving = false;

  static const List<String> _relationshipOptions = [
    'ছেলে',
    'মেয়ে',
    'স্বামী',
    'স্ত্রী',
    'ভাই',
    'বোন',
    'নাতি',
    'নাতনি',
    'চাচা',
    'চাচি',
    'মামা',
    'মামি',
    'খুড়া',
    'খুড়ি',
  ];

  @override
  void initState() {
    super.initState();
    final d = widget.initialData;
    _fullName.text = (d['full_name'] as String?) ?? '';
    _username.text = (d['username'] as String?) ?? '';
    _relationship.text = (d['caretaker_specialty'] as String?) ?? '';
    _contactPhone.text = (d['caretaker_contact_phone'] as String?) ?? '';
    _address.text = (d['caretaker_address'] as String?) ?? '';
    _note.text = (d['caretaker_note'] as String?) ?? '';
    _availability.text = (d['caretaker_availability'] as String?) ?? '';
  }

  @override
  void dispose() {
    _fullName.dispose();
    _username.dispose();
    _relationship.dispose();
    _contactPhone.dispose();
    _address.dispose();
    _note.dispose();
    _availability.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final fullName = _fullName.text.trim();
    final username = _username.text.trim();
    final relationship = _relationship.text.trim();
    if (fullName.isEmpty || username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('নাম ও ইউজারনেম আবশ্যক।')),
      );
      return;
    }
    // Server enforces username length = 6 via the `uniq_user_profiles_username`
    // partial index + check constraints. Mirror that here so the user gets a
    // friendly message instead of a raw DB error if they paste a longer value
    // bypassing the field's maxLength.
    if (username.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ইউজারনেম অবশ্যই ৬ অক্ষরের হতে হবে।')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await SupabaseService.updateMyCaretakerProfile(
        fullName: fullName,
        username: username,
        relationship: relationship,
        contactPhone: _contactPhone.text.trim(),
        address: _address.text.trim(),
        note: _note.text.trim(),
        availability: _availability.text.trim(),
        profileCompleted: true,
      );

      // Belt + suspenders: the mirror inside updateMyCaretakerProfile
      // already calls markProfileCompleted for BDApps caretakers. We
      // call it again here unconditionally so non-BDApps caretakers
      // and offline-failure paths still hit the local SharedPreferences
      // cache — guaranteeing the post-login dialog never appears again.
      await BdappsSessionService.instance.markProfileCompleted(value: true);

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
          _field(_fullName, 'নিজের নাম', 'আপনার নাম লিখুন', Icons.person_rounded),
          _field(_username, 'ইউজারনেম (শুধু ৬ অক্ষর)', 'যেমন: nazmul', Icons.alternate_email_rounded, maxLength: 6),
          const SizedBox(height: 20),
          _buildSection('পরিবারের সম্পর্ক'),
          _relationshipDropdown(),
          _field(_contactPhone, 'যোগাযোগ নম্বর', 'যেমন: ০১৭xxxxxxxx', Icons.phone_in_talk_rounded,
              keyboardType: TextInputType.phone),
          const SizedBox(height: 20),
          _buildSection('ঠিকানা ও নোট'),
          _field(_address, 'ঠিকানা', 'বর্তমান ঠিকানা (ঐচ্ছিক)', Icons.location_on_outlined, maxLines: 2),
          _field(_note, 'নোট', 'রোগীর যত্নে আপনার ভূমিকা বা অন্য কিছু (ঐচ্ছিক)', Icons.edit_note_rounded, maxLines: 3),
          _field(_availability, 'যোগাযোগের সময়', 'কখন ফোনে পাওয়া যাবে (ঐচ্ছিক)', Icons.schedule_rounded),
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

  Widget _relationshipDropdown() {
    final current = _relationship.text.trim();
    final value = _relationshipOptions.contains(current) ? current : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.family_restroom, size: 14, color: AppColors.svcHero),
            SizedBox(width: 6),
            Text('পরিবারের সম্পর্ক', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: value,
            isExpanded: true,
            decoration: InputDecoration(
              hintText: 'সম্পর্ক বাছাই করুন',
              fillColor: AppColors.chalk,
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: AppColors.line)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            items: _relationshipOptions
                .map((r) => DropdownMenuItem<String>(value: r, child: Text(r)))
                .toList(),
            onChanged: (v) => setState(() => _relationship.text = v ?? ''),
            validator: (v) => v == null || v.isEmpty ? 'সম্পর্ক বাছাই করুন' : null,
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, String hint, IconData icon, {int maxLines = 1, TextInputType? keyboardType, int? maxLength}) {
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
            maxLength: maxLength,
            decoration: InputDecoration(
              hintText: hint,
              fillColor: AppColors.chalk,
              filled: true,
              counterText: '',
              border: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: AppColors.line)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}