/// Read-only public-profile preview screen.
///
/// Anyone in the signed-in app can open this for any user they've
/// found through the People directory. The page is intentionally
/// light on PII:
///   * Name + role + avatar + relationship (caretaker)
///   * Masked mobile + masked email
///   * Age, sex, member-since, link-state
///
/// Clinical fields (HbA1c, BP, weight, adherence, …) are NOT exposed
/// here — those live behind the active-link caretaker RPCs.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/app_errors.dart';
import '../../services/caretaker_provider.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import 'package:provider/provider.dart';

class PublicProfileScreen extends StatefulWidget {
  /// UID of the profile to display.
  final String userId;

  /// Optional pre-fetched summary to show instantly while the full
  /// profile RPC loads. Avoids a flash of empty content.
  final Map<String, dynamic>? person;
  const PublicProfileScreen({
    super.key,
    required this.userId,
    this.person,
  });

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  Object? _error;
  bool _connecting = false;

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
      final data = await SupabaseService.getPublicProfile(widget.userId);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _connect() async {
    if (_connecting) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _connecting = true);
    try {
      await context.read<CaretakerProvider>().sendRequest(
            patientUserId: widget.userId,
            relationship: 'পরিচর্যাকারী',
            note: null,
          );
      messenger.showSnackBar(
        const SnackBar(
          content: Text('✅ অনুরোধ পাঠানো হয়েছে'),
        ),
      );
      await _load();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('অনুরোধ ব্যর্থ: ${BanglaError.toBangla(e)}'),
          backgroundColor: AppColors.rose,
        ),
      );
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final pending = widget.person;
    final name = (d?['full_name'] ?? pending?['full_name'] ?? 'ব্যবহারকারী')
        .toString();
    final role = (d?['role'] ?? pending?['role'] ?? 'patient').toString();
    final isCaretaker = role == 'caretaker';
    final rel = d?['caretaker_relationship'] as String?;
    final mobile = d?['mobile'] ?? pending?['mobile'];
    final email = d?['email'] ?? pending?['email'];
    final age = d?['age'] ?? pending?['age'];
    final sex = (d?['sex'] ?? pending?['sex'] ?? '').toString();
    final isLinked = d?['is_linked'] == true || pending?['is_linked'] == true;
    final linkStatus = (d?['link_status'] ??
            pending?['link_status'] ??
            '')
        .toString();
    final isSelf = d?['is_self'] == true;
    final createdAtStr = d?['created_at']?.toString();
    DateTime? createdAt;
    if (createdAtStr != null && createdAtStr.isNotEmpty) {
      createdAt = DateTime.tryParse(createdAtStr);
    }
    return Scaffold(
      backgroundColor: AppColors.void2,
      appBar: AppBar(
        backgroundColor: AppColors.void2,
        foregroundColor: AppColors.text,
        elevation: 0,
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.violetDeep,
        onRefresh: _load,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: AppColors.violet,
                ),
              )
            : _error != null
                ? _ErrorState(message: BanglaError.toBangla(_error))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      _HeaderCard(
                        name: name,
                        role: role,
                        rel: rel,
                        isSelf: isSelf,
                      ),
                      const SizedBox(height: 16),
                      if (!isSelf && !isCaretaker) ...[
                        _ConnectCTA(
                          isLinked: isLinked,
                          linkStatus: linkStatus,
                          connecting: _connecting,
                          onConnect: _connect,
                        ),
                        const SizedBox(height: 16),
                      ],
                      _InfoGrid(
                        mobile: mobile?.toString() ?? '',
                        email: email?.toString() ?? '',
                        age: age,
                        sex: sex,
                        isCaretaker: isCaretaker,
                        rel: rel,
                        createdAt: createdAt,
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final String name;
  final String role;
  final String? rel;
  final bool isSelf;
  const _HeaderCard({
    required this.name,
    required this.role,
    required this.rel,
    required this.isSelf,
  });

  @override
  Widget build(BuildContext context) {
    final isCaretaker = role == 'caretaker';
    final accent = isCaretaker ? AppColors.amber : AppColors.violetDeep;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent,
            accent.withValues(alpha: 0.78),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
            ),
            alignment: Alignment.center,
            child: Text(
              _initials(name),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isCaretaker ? 'পরিচর্যাকারী' : 'রোগী',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (rel != null && rel!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    rel!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (isSelf) ...[
                  const SizedBox(height: 4),
                  Text(
                    'এটি আপনার প্রোফাইল',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '?';
    final parts = s.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts[0].isNotEmpty ? parts[0][0] : '') +
          (parts[1].isNotEmpty ? parts[1][0] : '');
    }
    return s.characters.first.toUpperCase();
  }
}

class _ConnectCTA extends StatelessWidget {
  final bool isLinked;
  final String linkStatus;
  final bool connecting;
  final VoidCallback onConnect;
  const _ConnectCTA({
    required this.isLinked,
    required this.linkStatus,
    required this.connecting,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    if (isLinked) {
      return _StatusBanner(
        color: AppColors.cyanDeep,
        icon: Icons.check_circle_rounded,
        label: 'সক্রিয় সংযোগ — রোগীর সারাংশ দেখতে পারবেন।',
      );
    }
    if (linkStatus == 'pending') {
      return _StatusBanner(
        color: AppColors.amber,
        icon: Icons.hourglass_top_rounded,
        label: 'অনুরোধ অপেক্ষমান — রোগী এখনো সাড়া দেননি।',
      );
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: connecting ? null : onConnect,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.violetDeep,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        icon: connecting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.person_add_alt_1_rounded),
        label: Text(
          connecting ? 'পাঠানো হচ্ছে…' : 'সংযুক্ত হন',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  const _StatusBanner({
    required this.color,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: color,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoGrid extends StatelessWidget {
  final String mobile;
  final String email;
  final Object? age;
  final String sex;
  final bool isCaretaker;
  final String? rel;
  final DateTime? createdAt;
  const _InfoGrid({
    required this.mobile,
    required this.email,
    required this.age,
    required this.sex,
    required this.isCaretaker,
    required this.rel,
    required this.createdAt,
  });

  @override
  Widget build(BuildContext context) {
    final tiles = <MapEntry<String, String>>[
      if (mobile.isNotEmpty)
        MapEntry('মোবাইল', mobile),
      if (email.isNotEmpty) MapEntry('ইমেইল', email),
      if (age != null) MapEntry('বয়স', '$age'),
      if (sex.isNotEmpty)
        MapEntry('লিঙ্গ', sex == 'male' ? 'পুরুষ' : 'নারী'),
      if (isCaretaker && rel != null && rel!.trim().isNotEmpty)
        MapEntry('সম্পর্ক', rel!),
      if (createdAt != null)
        MapEntry(
          'যোগদান',
          DateFormat('d MMM yyyy', 'bn').format(createdAt!),
        ),
    ];

    if (tiles.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'তথ্য',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: AppColors.textMuted,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            children: [
              for (var i = 0; i < tiles.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 84,
                        child: Text(
                          tiles[i].key,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          tiles[i].value,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.cyan.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: AppColors.cyan.withValues(alpha: 0.22)),
          ),
          child: const Row(
            children: [
              Icon(Icons.lock_outline_rounded,
                  size: 18, color: AppColors.cyan),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'গোপনীয়তা রক্ষিত — মোবাইল ও ইমেইল আংশিক দেখানো হচ্ছে। ক্লিনিক্যাল তথ্য দেখতে প্রথমে সংযোগ গ্রহণ হওয়া দরকার।',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.text,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.rose, size: 56),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.text,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () =>
                  Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => PublicProfileScreen(
                    userId: (ModalRoute.of(context)!.settings.arguments
                            as String?) ??
                        '',
                  ),
                ),
              ),
              label: const Text('আবার চেষ্টা করুন'),
            ),
          ],
        ),
      ),
    );
  }
}