/// Caretaker own-profile editor (doctor-style).
///
/// Lets the signed-in caretaker fill in / update:
///   • Bio (free-text "about me")
///   • Specialty (e.g. "Diabetologist")
///   • License number
///   • Clinic name
///   • Years of experience
///   • Qualifications (free-text)
///   • Languages spoken
///   • Availability hours
///   • Credentials / extra notes
///
/// The fields are stored on `user_profiles` under the `doctor_*`
/// columns added in `45_caretaker_care_doctor.sql`. Only caretakers
/// can write them (server enforces role='caretaker').
///
/// Patient profiles are unaffected — these columns are never read
/// for a patient.
library;

import 'package:flutter/material.dart';

import '../../services/app_events.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/mono_widgets.dart';

class CaretakerDoctorProfileScreen extends StatefulWidget {
  const CaretakerDoctorProfileScreen({super.key});

  @override
  State<CaretakerDoctorProfileScreen> createState() =>
      _CaretakerDoctorProfileScreenState();
}

class _CaretakerDoctorProfileScreenState
    extends State<CaretakerDoctorProfileScreen> {
  final _bio = TextEditingController();
  final _specialty = TextEditingController();
  final _license = TextEditingController();
  final _clinic = TextEditingController();
  final _years = TextEditingController();
  final _qualifications = TextEditingController();
  final _languages = TextEditingController();
  final _availability = TextEditingController();
  final _credentials = TextEditingController();

  String? _fullName;
  String? _avatarUrl;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await SupabaseService.getMyDoctorProfile();
      if (!mounted) return;
      _bio.text = (data['doctor_bio'] as String?) ?? '';
      _specialty.text = (data['doctor_specialty'] as String?) ?? '';
      _license.text = (data['doctor_license_number'] as String?) ?? '';
      _clinic.text = (data['doctor_clinic_name'] as String?) ?? '';
      final y = data['doctor_years_experience'];
      _years.text =
          (y is num) ? y.toInt().toString() : (y is String ? y : '');
      _qualifications.text = (data['doctor_qualifications'] as String?) ?? '';
      _languages.text = (data['doctor_languages'] as String?) ?? '';
      _availability.text = (data['doctor_availability'] as String?) ?? '';
      _credentials.text = (data['doctor_credentials'] as String?) ?? '';
      _fullName = data['full_name'] as String?;
      _avatarUrl = data['avatar_url'] as String?;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final years = int.tryParse(_years.text.trim());
      await SupabaseService.updateMyDoctorProfile(
        bio: _bio.text.trim(),
        specialty: _specialty.text.trim(),
        licenseNumber: _license.text.trim(),
        clinicName: _clinic.text.trim(),
        yearsExperience: years,
        qualifications: _qualifications.text.trim(),
        languages: _languages.text.trim(),
        availability: _availability.text.trim(),
        credentials: _credentials.text.trim(),
      );
      AppEvents.notifyProfileChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('প্রোফাইল আপডেট হয়েছে'),
          duration: Duration(seconds: 2),
        ),
      );
      setState(() => _saving = false);
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('সংরক্ষণ করা যায়নি: $e')),
      );
    }
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    final name = (_fullName ?? '').trim();
    return Scaffold(
      backgroundColor: AppColors.svcCategoryBg,
      appBar: AppBar(
        backgroundColor: AppColors.svcHero,
        foregroundColor: Colors.white,
        title: const Text(
          'ডাক্তার প্রোফাইল',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'সংরক্ষণ',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.svcHero))
          : _error != null
              ? Center(child: Text('ত্রুটি: $_error'))
              : ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 60),
                  children: [
                    _IdentityCard(name: name, avatarUrl: _avatarUrl),
                    const SizedBox(height: 22),
                    _SectionHeader('পরিচিতি', 'নাম, বিশেষজ্ঞতা ও ক্লিনিক'),
                    const SizedBox(height: 10),
                    _Field(
                      controller: _specialty,
                      label: 'বিশেষজ্ঞতা',
                      hint: 'যেমন: ডায়াবেটিস, মেডিসিন',
                      icon: Icons.medical_services_rounded,
                    ),
                    _Field(
                      controller: _license,
                      label: 'লাইসেন্স নম্বর',
                      hint: 'বিএমডিসি নিবন্ধন নম্বর',
                      icon: Icons.badge_rounded,
                    ),
                    _Field(
                      controller: _clinic,
                      label: 'ক্লিনিক / হাসপাতালের নাম',
                      hint: 'যেখানে প্র্যাকটিস করেন',
                      icon: Icons.local_hospital_rounded,
                    ),
                    _Field(
                      controller: _years,
                      label: 'অভিজ্ঞতা (বছর)',
                      hint: 'যেমন: ৫',
                      icon: Icons.timeline_rounded,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 22),
                    _SectionHeader('বিস্তারিত', 'যোগ্যতা, ভাষা ও সময়সূচি'),
                    const SizedBox(height: 10),
                    _Field(
                      controller: _qualifications,
                      label: 'যোগ্যতা',
                      hint: 'যেমন: এমবিবিএস, এমডি (এন্ডোক্রাইনোলজি)',
                      icon: Icons.school_rounded,
                      maxLines: 3,
                    ),
                    _Field(
                      controller: _languages,
                      label: 'ভাষা',
                      hint: 'যেমন: বাংলা, English, हिंदी',
                      icon: Icons.translate_rounded,
                    ),
                    _Field(
                      controller: _availability,
                      label: 'প্র্যাকটিসের সময়',
                      hint: 'যেমন: রবি-বৃহঃ সন্ধ্যা ৬টা-৯টা',
                      icon: Icons.schedule_rounded,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 22),
                    _SectionHeader('প্রোফাইল', 'বায়ো ও প্রমাণপত্র'),
                    const SizedBox(height: 10),
                    _Field(
                      controller: _bio,
                      label: 'নিজের সম্পর্কে',
                      hint: 'রোগীরা আপনাকে যেভাবে চিনুক — সংক্ষেপে',
                      icon: Icons.edit_note_rounded,
                      maxLines: 5,
                    ),
                    _Field(
                      controller: _credentials,
                      label: 'প্রমাণপত্র / অন্যান্য',
                      hint: 'বিশেষ সদস্যপদ, পুরস্কার ইত্যাদি',
                      icon: Icons.verified_rounded,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 30),
                    Center(
                      child: Text(
                        'এই তথ্য শুধু আপনার সংযুক্ত রোগীরা দেখবেন।',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.smoke,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String sub;
  const _SectionHeader(this.title, this.sub);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: AppColors.newsInk,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: AppColors.smoke,
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final int maxLines;
  final TextInputType? keyboardType;
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              children: [
                Icon(icon, size: 14, color: AppColors.svcHero),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: AppColors.newsInk,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          MonoCard(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: TextField(
              controller: controller,
              maxLines: maxLines,
              minLines: 1,
              keyboardType: keyboardType,
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                hintStyle: const TextStyle(
                  color: AppColors.lineStrong,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IdentityCard extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  const _IdentityCard({required this.name, this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl?.trim();
    final hasAvatar = url != null && url.isNotEmpty;
    final display = name.isEmpty ? 'পরিচর্যাকারী' : name;
    final initials = _initials(display);

    return MonoCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.svcHero,
              borderRadius: BorderRadius.zero,
            ),
            clipBehavior: Clip.hardEdge,
            child: hasAvatar
                ? Image.network(
                    url,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _initialsText(initials),
                    loadingBuilder: (_, child, p) =>
                        p == null ? child : _initialsText(initials),
                  )
                : _initialsText(initials),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  display,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'পরিচর্যাকারী',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.smoke,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.svcHero.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.zero,
                  ),
                  child: const Text(
                    'প্রোফাইল এডিটর',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: AppColors.svcHero,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _initialsText(String initials) => Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w900,
        ),
      );

  String _initials(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return 'প';
    final parts = s.split(RegExp(r'\s+'));
    if (parts.length >= 2) return (parts[0][0]) + (parts[1][0]);
    return s.characters.first.toUpperCase();
  }
}
