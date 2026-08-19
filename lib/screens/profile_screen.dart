import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/user_profile.dart';
import '../services/supabase_service.dart';
import '../services/classification_engine.dart';
import '../services/impact_engine.dart' show ImpactEngine;
import '../services/app_events.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';
import 'onboarding_screen.dart';

/// Profile screen — clinical details, edit, and sign-out.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  Classification? _cls;
  bool _loading = true;
  String? _error;

  /// Cached, signed URL for the current avatar. Kept here so the avatar
  /// tile can render the photo without waiting on a fresh signature
  /// each rebuild.
  String? _avatarSignedUrl;

  /// True while an upload/picker roundtrip is in flight — used to
  /// show a small spinner overlay on the avatar.
  bool _uploadingPhoto = false;

  final ImagePicker _picker = ImagePicker();

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
      // Hard timeout — if Supabase hangs (network down, RLS infinite
      // wait, etc.) we still want to drop out of the spinner instead of
      // leaving the user staring at it forever.
      final p = await SupabaseService.fetchProfile()
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (p == null) {
        setState(() {
          _loading = false;
          _profile = null;
        });
        return;
      }
      final signed = (p.avatarUrl != null && p.avatarUrl!.isNotEmpty)
          ? await SupabaseService.getProfilePhotoUrl(p.avatarUrl)
          : null;
      if (!mounted) return;
      setState(() {
        _profile = p;
        _cls = ClassificationEngine.classify(p);
        _avatarSignedUrl = signed;
        _loading = false;
      });
    } catch (e) {
      // Always drop the spinner even when fetchProfile throws —
      // otherwise the screen stays stuck on the loading indicator.
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    // The root widget listens to Supabase auth state changes and
    // automatically swaps HomeShell for AuthScreen once the session
    // is cleared — no manual navigation needed.
    await SupabaseService.signOut();
  }

  Future<void> _editProfile() async {
    final p = _profile;
    if (p == null) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => OnboardingScreen(edit: p)),
    );
    if (result == true) {
      AppEvents.notifyProfileChanged();
      await _load();
    }
  }

  /// Opens the photo picker, uploads the chosen image to the
  /// `profile` bucket, and refreshes the screen. Honours the 2-upload
  /// cap by checking [_profile] before opening the picker AND by
  /// letting the server-side RPC reject the upload if the client
  /// counter is stale.
  Future<void> _changePhoto() async {
    final p = _profile;
    if (p == null) return;
    final remaining =
        SupabaseService.maxProfilePhotoUploads - p.photoUploadCount;
    if (remaining <= 0) {
      _showSnack(
        'ছবি আপলোডের সীমা শেষ (সর্বোচ্চ ${SupabaseService.maxProfilePhotoUploads}টি)।',
      );
      return;
    }

    final source = await _pickPhotoSource();
    if (source == null) return;

    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 82,
      maxWidth: 1024,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    setState(() => _uploadingPhoto = true);
    try {
      final newUrl = await SupabaseService.uploadProfilePhoto(
        bytes: bytes,
        contentType: picked.mimeType ?? 'image/jpeg',
        originalFileName: picked.name,
      );
      if (!mounted) return;
      setState(() => _avatarSignedUrl = newUrl);
      _showSnack('প্রোফাইল ছবি আপলোড হয়েছে');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showSnack('ছবি আপলোড ব্যর্থ: $e');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  /// Bottom-sheet picker: gallery / camera / cancel.
  Future<ImageSource?> _pickPhotoSource() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        Widget tile(IconData icon, String label, ImageSource src) {
          return InkWell(
            onTap: () => Navigator.pop(ctx, src),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Icon(icon, color: AppColors.ink, size: 26),
                  const SizedBox(width: 14),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              tile(Icons.photo_library_outlined, 'গ্যালারি থেকে বেছে নিন',
                  ImageSource.gallery),
              tile(Icons.camera_alt_outlined, 'ক্যামেরা দিয়ে তুলুন',
                  ImageSource.camera),
              const SizedBox(height: 6),
              const Divider(height: 1),
              tile(Icons.close, 'বাতিল', ImageSource.camera /* unused */),
            ],
          ),
        );
      },
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 16)),
        behavior: SnackBarBehavior.floating,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final user = SupabaseService.currentUser;
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(child: LoadingMark(size: 36))
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('ত্রুটি: $_error',
                          style: Theme.of(context).textTheme.bodyLarge),
                    ),
                  )
                : _profile == null
                    ? _onboardingNeeded()
                    : _buildContent(user?.email ?? ''),
      ),
    );
  }

  Widget _onboardingNeeded() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.chalk,
                borderRadius: BorderRadius.circular(44),
                border: Border.all(color: AppColors.graphite),
              ),
              child: const Icon(Icons.assignment_outlined,
                  size: 38, color: AppColors.ink),
            ),
            const SizedBox(height: 20),
            const Text(
              'আপনার স্বাস্থ্য তথ্য দেওয়া হয়নি',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'ব্যক্তিগতকৃত পরিকল্পনা পেতে প্রোফাইল পূরণ করুন',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 16, color: AppColors.smoke, height: 1.4),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: MonoButton(
                label: 'প্রোফাইল পূরণ করুন',
                leading: Icons.add,
                onPressed: () async {
                  final res = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                  );
                  if (res == true) {
                    AppEvents.notifyProfileChanged();
                    await _load();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(String email) {
    final p = _profile!;
    final cls = _cls!;
    final bmi = p.bmi;
    final bmiLabel = bmi < 18.5
        ? 'কম ওজন'
        : bmi < 23
            ? 'স্বাভাবিক'
            : bmi < 25
                ? 'সামান্য বেশি'
                : 'বেশি';

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 120),
          sliver: SliverList.list(children: [
            _accountCard(email),
            const SizedBox(height: 14),
            _vitalsCard(p, bmi, bmiLabel),
            const SizedBox(height: 14),
            _classificationCard(cls),
            const SizedBox(height: 14),
            _conditionsCard(p),
            const SizedBox(height: 20),
            MonoButton(
              label: 'তথ্য আপডেট করুন',
              leading: Icons.edit_outlined,
              onPressed: _editProfile,
            ),
            const SizedBox(height: 10),
            MonoButton(
              label: 'লগ আউট',
              leading: Icons.logout,
              variant: MonoButtonVariant.outline,
              onPressed: _signOut,
            ),
          ]),
        ),
      ],
    );
  }

  /// Full-bleed monogram fallback for the gradient block — keeps the
  /// aurora gradient + MonoPattern decoration and overlays a big
  /// monogram so the card still has presence before the user uploads.
  Widget _monogramBackground(String monogram) {
    return Container(
      decoration: BoxDecoration(gradient: AppGradients.aurora),
      child: MonoPattern(
        kind: MonoPatternKind.arcs,
        color: AppColors.paper,
        opacity: 0.10,
        spacing: 18,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Align(
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                monogram,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 88,
                  fontWeight: FontWeight.w800,
                  color: AppColors.paper,
                  letterSpacing: -3,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _accountCard(String email) {
    final p = _profile!;
    final name = (p.fullName != null && p.fullName!.isNotEmpty)
        ? p.fullName!
        : (email.isEmpty ? 'ব্যবহারকারী' : email);
    final mobile = (p.mobile != null && p.mobile!.isNotEmpty) ? p.mobile! : '—';
    final monogram = name.characters.first.toUpperCase();
    final remainingUploads =
        SupabaseService.maxProfilePhotoUploads - p.photoUploadCount;

    return RevealOnEnter(
      child: SplitHeroCard(
        blockGradient: AppGradients.aurora,
        // The SplitHeroCard still owns the aurora gradient behind the
        // photo, but we drain it (the photo covers the whole block
        // when one is uploaded). No Padding here — it would leave a
        // mint border around the photo.
        blockContent: InkWell(
          onTap: _changePhoto,
          child: Stack(
            children: [
              // Background: either the uploaded photo filling the
              // whole mint area, or the gradient + MonoPattern + big
              // monogram fallback. Either way the tag, caption and
              // camera badge sit on top.
              Positioned.fill(
                child: _avatarSignedUrl != null && _avatarSignedUrl!.isNotEmpty
                    ? Image.network(
                        _avatarSignedUrl!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) =>
                            _monogramBackground(monogram),
                        loadingBuilder: (ctx, child, prog) {
                          if (prog == null) return child;
                          return _monogramBackground(monogram);
                        },
                      )
                    : _monogramBackground(monogram),
              ),
              // Subtle dark gradient on the bottom so the caption
              // remains readable when a real photo is in place.
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.22),
                        ],
                        stops: const [0.50, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              // Upload spinner overlay.
              if (_uploadingPhoto)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.45),
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: AppColors.void1,
                      ),
                    ),
                  ),
                ),
              // Foreground: tag on top, caption at bottom.
              Positioned(
                top: 12,
                left: 12,
                child: AccentTag(
                  label: remainingUploads > 0 ? 'সক্রিয়' : 'ছবি আপলোড শেষ',
                  icon: remainingUploads > 0 ? Icons.bolt : Icons.lock_outline,
                ),
              ),
              Positioned(
                left: 14,
                bottom: 14,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'আমার\nডায়েট',
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.paper.withValues(alpha: 0.92),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
              // Camera badge — bottom-right.
              Positioned(
                right: 10,
                bottom: 10,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.void1,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: AppColors.cyan, width: 1.5),
                  ),
                  child: const Icon(
                    Icons.camera_alt,
                    size: 15,
                    color: AppColors.cyanDeep,
                  ),
                ),
              ),
            ],
          ),
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
                letterSpacing: -0.2,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 14),
            _rowLight('ইমেইল', email.isEmpty ? '—' : email),
            const SizedBox(height: 8),
            _rowLight('মোবাইল', mobile),
          ],
        ),
      ),
    );
  }

  Widget _rowLight(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.smoke,
              letterSpacing: 0.4,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
            textAlign: TextAlign.right,
            softWrap: true,
          ),
        ),
      ],
    );
  }

  Widget _vitalsCard(UserProfile p, double bmi, String bmiLabel) {
    return RevealOnEnter(
      delay: const Duration(milliseconds: 80),
      child: MonoCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Overline('শারীরিক তথ্য',
                padding: EdgeInsets.only(top: 0, bottom: 14)),
            Row(
              children: [
                Expanded(child: _statTile('বয়স', '${p.age}', 'বছর')),
                const SizedBox(width: 10),
                Expanded(
                  child: _statTile(
                    'লিঙ্গ',
                    p.sex == 'male'
                        ? 'পুরুষ'
                        : p.sex == 'female'
                            ? 'মহিলা'
                            : 'অন্যান্য',
                    '',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                    child: _statTile(
                        'ওজন', p.weightKg.toStringAsFixed(1), 'কেজি')),
                const SizedBox(width: 10),
                Expanded(
                    child: _statTile(
                        'উচ্চতা', p.heightCm.toStringAsFixed(0), 'সেমি')),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.chalk,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.graphite),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'BMI',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.smoke,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            bmi.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                              height: 1,
                              letterSpacing: -0.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          bmiLabel,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.smoke,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (p.systolicBp != null && p.diastolicBp != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'রক্তচাপ',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.smoke,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${p.systolicBp}/${p.diastolicBp}',
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                                height: 1,
                                letterSpacing: -0.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'mmHg',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.smoke,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (p.hba1cPercent != null ||
                p.fastingGlucoseMmol != null ||
                p.postMealGlucoseMmol != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.chalk,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.graphite),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'গ্লুকোজ',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.smoke,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (p.hba1cPercent != null)
                        _miniRow(
                            'HbA1c', '${p.hba1cPercent!.toStringAsFixed(1)}%'),
                      if (p.fastingGlucoseMmol != null)
                        _miniRow('ফাস্টিং',
                            '${p.fastingGlucoseMmol!.toStringAsFixed(1)} mmol/L'),
                      if (p.postMealGlucoseMmol != null)
                        _miniRow('খাবার পরে',
                            '${p.postMealGlucoseMmol!.toStringAsFixed(1)} mmol/L'),
                    ],
                  ),
                ),
              ),
            if (p.medication != null && p.medication!.isNotEmpty) ...[
              const SizedBox(height: 10),
              _miniRow('ওষুধ', p.medication!),
            ],
            const SizedBox(height: 10),
            _miniRow(
              'পরিশ্রম',
              p.activityLevel == 'low'
                  ? 'কম'
                  : p.activityLevel == 'moderate'
                      ? 'মাঝারি'
                      : 'বেশি',
            ),
          ],
        ),
      ),
    );
  }

  Widget _statTile(String label, String value, String unit) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.chalk,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.graphite),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.smoke,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  letterSpacing: -0.4,
                  height: 1.1,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    unit,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.smoke,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.smoke,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _classificationCard(Classification cls) {
    final glucoseLabel = {
          'good': 'ভালো',
          'moderate': 'মাঝারি',
          'poor': 'খারাপ',
          'unknown': 'অজানা',
        }[cls.glucoseTier] ??
        cls.glucoseTier;

    return RevealOnEnter(
      delay: const Duration(milliseconds: 160),
      child: MonoCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Overline('বর্তমান ক্লাসিফিকেশন',
                padding: EdgeInsets.only(top: 0, bottom: 14)),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'গ্লুকোজ',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.smoke,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        glucoseLabel,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'এক বেলায় কার্ব',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.smoke,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            cls.maxCarbPerMeal.toInt().toString(),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              'গ্রাম',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.smoke.withValues(alpha: 0.9),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.chalk,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.graphite),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _miniRow('অনুমোদিত GI',
                      cls.allowedGi.map(ImpactEngine.giLabel).join(', ')),
                  if (cls.restrictionFlags.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _miniRow('বিধিনিষেধ', cls.restrictionFlags.join(', ')),
                  ],
                ],
              ),
            ),
            if (cls.warnings.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: AppGradients.aurora,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.cyan.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: AppColors.paper,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.priority_high,
                              size: 14, color: AppColors.ink),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'গুরুত্বপূর্ণ তথ্য',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.paper,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    for (final w in cls.warnings)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '• $w',
                          style: const TextStyle(
                            color: AppColors.paper,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _conditionsCard(UserProfile p) {
    final chips = <String>[];
    if (p.onInsulin) chips.add('ইনসুলিন');
    if (p.hasCkd) chips.add('কিডনি রোগ (CKD)');
    if (p.hasHeartDisease) chips.add('হৃদরোগ');
    if (p.hasAnemia) chips.add('রক্তস্বল্পতা');
    if (p.otherConditions != null && p.otherConditions!.isNotEmpty) {
      chips.add(p.otherConditions!);
    }
    if (chips.isEmpty) chips.add('কোনো বিশেষ শারীরিক অবস্থা নেই');

    return RevealOnEnter(
      delay: const Duration(milliseconds: 220),
      child: MonoCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Overline('শারীরিক অবস্থা',
                padding: EdgeInsets.only(top: 0, bottom: 14)),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (int i = 0; i < chips.length; i++)
                  MonoBadge(
                    text: chips[i],
                    icon: chips[i] == 'কোনো বিশেষ শারীরিক অবস্থা নেই'
                        ? Icons.check
                        : Icons.fiber_manual_record,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
