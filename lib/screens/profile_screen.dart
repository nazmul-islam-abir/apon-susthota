import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/user_profile.dart';
import '../services/supabase_service.dart';
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
    final isFirstLoad = _profile == null && _error == null;
    if (isFirstLoad) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
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

      String? signed;
      if (p.avatarUrl != null && p.avatarUrl!.isNotEmpty) {
        final raw = await SupabaseService.getProfilePhotoUrl(p.avatarUrl);
        if (raw.isNotEmpty) {
          // Append cache-buster keyed on upload count.
          final joiner = raw.contains('?') ? '&' : '?';
          signed = '$raw${joiner}_v=${p.photoUploadCount}';
        }
      }

      if (!mounted) return;
      setState(() {
        _profile = p;
        _avatarSignedUrl = signed;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = isFirstLoad ? e.toString() : null;
          _loading = false;
        });
        if (!isFirstLoad) {
          _showSnack('প্রোফাইল আপডেট হতে সমস্যা হয়েছে');
        }
      }
    }
  }

  Future<void> _signOut() async {
    // The root widget listens to Supabase auth state changes and
    // automatically swaps HomeShell for AuthScreen once the session
    // is cleared — no manual navigation needed.
    // Wrap in try/catch so a network failure during sign-out never leaves
    // the screen in a "tapped but nothing happened" state. The root
    // navigator will still tear this screen down via the auth listener.
    try {
      await SupabaseService.signOut();
    } catch (e) {
      // Surface the error to the console; the UI swap is handled by
      // the auth state listener in main.dart regardless.
      debugPrint('signOut failed: $e');
      if (mounted) {
        _showSnack('লগআউট ব্যর্থ হয়েছে — আবার চেষ্টা করুন');
      }
    }
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
      // Notify the rest of the app (dashboard tab, top bar, etc.) so the
      // avatar caches re-fetch and the new photo appears everywhere.
      AppEvents.notifyProfileChanged();
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
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 120),
          sliver: SliverList.list(children: [
            _accountCard(email),
            const SizedBox(height: 14),
            _conditionsCard(_profile!),
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

  /// Slim conditions chip — shows the same flags the Dashboard's
  /// `_ProfileCard` does (CKD / heart disease / on insulin / anemia)
  /// so the user still sees them when navigating into the full
  /// Profile screen via the dashboard.
  Widget _conditionsCard(UserProfile p) {
    final chips = <(IconData, String)>[];
    if (p.hasCkd == true) {
      chips.add((Icons.water_drop_outlined, 'কিডনি সমস্যা'));
    }
    if (p.hasHeartDisease == true) {
      chips.add((Icons.favorite_outline, 'হৃদরোগ'));
    }
    if (p.onInsulin == true) {
      chips.add((Icons.medication_outlined, 'ইনসুলিন'));
    }
    if (p.hasAnemia == true) {
      chips.add((Icons.bloodtype_outlined, 'রক্তস্বল্পতা'));
    }
    final other = p.otherConditions?.trim() ?? '';
    if (other.isNotEmpty) {
      chips.add((Icons.note_alt_outlined, other));
    }
    if (chips.isEmpty) {
      return const SizedBox.shrink();
    }
    return RevealOnEnter(
      delay: const Duration(milliseconds: 80),
      child: MonoCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Overline('বিশেষ শারীরিক অবস্থা'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in chips)
                  AccentTag(icon: c.$1, label: c.$2),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
