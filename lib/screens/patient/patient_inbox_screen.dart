/// Patient-side inbox for caretaker link requests.
///
/// Two stacked sections:
///   1. "অপেক্ষমান অনুরোধ" — pending requests waiting for the
///      patient to accept or decline. Each row has গ্রহণ / প্রত্যাখ্যান
///      actions that call `CaretakerProvider.respondTo(...)`.
///   2. "সক্রিয় পরি�র্যাকারী" — caretakers the patient has already
///      accepted. Read-only list with a "সরান" (revoke) action.
///
/// Realtime updates via the wrapping `CaretakerProvider` so accept /
/// decline / revoke actions propagate without a manual refresh.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/caretaker_link.dart';
import '../../services/app_errors.dart';
import '../../services/caretaker_provider.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/relative_time.dart';
import '../caretaker/public_profile_screen.dart';

class PatientInboxScreen extends StatelessWidget {
  const PatientInboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.void2,
      appBar: AppBar(
        backgroundColor: AppColors.void2,
        foregroundColor: AppColors.text,
        elevation: 0,
        title: const Text(
          'কেয়ারটেকার অনুরোধ',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Consumer<CaretakerProvider>(
        builder: (context, prov, _) {
          final pending = prov.pending;
          final active = prov.activeCaretakers;
          return RefreshIndicator(
            color: AppColors.cyanDeep,
            onRefresh: prov.refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (pending.isEmpty && active.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(),
                  )
                else ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    sliver: SliverToBoxAdapter(
                      child: _SectionHeader(
                        count: pending.length,
                        label: 'অপেক্ষমান অনুরোধ',
                      ),
                    ),
                  ),
                  if (pending.isEmpty)
                    const SliverToBoxAdapter(child: _NoItems())
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      sliver: SliverList.separated(
                        itemCount: pending.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _PendingRow(
                          link: pending[i],
                          onAccept: () => _respond(context, pending[i], true),
                          onDecline: () => _respond(context, pending[i], false),
                        ),
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                    sliver: SliverToBoxAdapter(
                      child: _SectionHeader(
                        count: active.length,
                        label: 'সক্রিয় পরিচর্যাকারী',
                      ),
                    ),
                  ),
                  if (active.isEmpty)
                    const SliverToBoxAdapter(child: _NoItems())
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      sliver: SliverList.separated(
                        itemCount: active.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _ActiveRow(
                          link: active[i],
                          onRevoke: () => _revoke(context, active[i]),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _respond(
    BuildContext context,
    CaretakerLink link,
    bool accept,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final id = link.id;
    // Defensive guard: the inbox RPCs now remap `link_id → id`, so this
    // branch should be unreachable. If it ever fires we WANT to know —
    // the previous silent `return` was the reason "accept/reject is
    // broken" looked undebuggable to the user.
    if (id == null) {
      debugPrint(
        '⚠️ patient_inbox: respondTo called with null link.id '
        '(link.caretakerUserId=${link.caretakerUserId}). '
        'This means the inbox RPC is missing the link_id remap.',
      );
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'ত্রুটি: লিঙ্ক আইডি পাওয়া যায়নি — অনুগ্রহ করে পেজ রিফ্রেশ করুন।',
          ),
          backgroundColor: AppColors.rose,
        ),
      );
      return;
    }
    try {
      if (!context.mounted) return;
      await context.read<CaretakerProvider>().respondTo(
            linkId: id,
            accept: accept,
          );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            accept ? 'অনুরোধ গৃহীত হয়েছে।' : 'অনুরোধ প্রত্যাখ্যাত হয়েছে।',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('ত্রুটি: ${BanglaError.toBangla(e)}'),
          backgroundColor: AppColors.rose,
        ),
      );
    }
  }

  Future<void> _revoke(BuildContext context, CaretakerLink link) async {
    final id = link.id;
    if (id == null) {
      debugPrint(
        '⚠️ patient_inbox: revoke called with null link.id '
        '(link.caretakerUserId=${link.caretakerUserId}).',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'ত্রুটি: লিঙ্ক আইডি পাওয়া যায়নি — অনুগ্রহ করে পেজ রিফ্রেশ করুন।',
          ),
          backgroundColor: AppColors.rose,
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('পরিচর্যাকারী সরান'),
        content: const Text(
          'এই পরিচর্যাকারী আর আপনার ত�্য দেখতে পাবে না।',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.rose),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('সরান'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<CaretakerProvider>().revoke(id);
      messenger.showSnackBar(
        const SnackBar(content: Text('পরিচর্যাকারী সরানো হয়েছে।')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('ত্রুটি: ${BanglaError.toBangla(e)}'),
          backgroundColor: AppColors.rose,
        ),
      );
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final int count;
  final String label;
  const _SectionHeader({required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        '$label ($count)',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: AppColors.text,
          height: 1.2,
        ),
      ),
    );
  }
}

class _NoItems extends StatelessWidget {
  const _NoItems();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Text(
        '—',
        style: TextStyle(
          fontSize: 13,
          color: AppColors.textDim.withValues(alpha: 0.7),
          height: 1.3,
        ),
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  final CaretakerLink link;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  const _PendingRow({
    required this.link,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final name = _resolveName(link);
    final rel = link.caretakerRelationship ?? 'পরিচর্যাকারী';
    final ts = link.requestedAt;
    final tsStr = ts == null
        ? ''
        : RelativeTime.format(ts);
    final age = link.otherAge;
    final sex = (link.otherSex ?? '').trim();
    final email = (link.otherEmail ?? '').trim();
    final avatarUrl = (link.otherAvatarUrl ?? '').trim();
    final initial = _initialOf(name);
    return Material(
      color: AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(14),
      // Note: we use GestureDetector with HitTestBehavior.translucent
      // (NOT InkWell) for the "tap card to open details" affordance.
      // InkWell's gesture arena handler is greedy and was stealing
      // pointer events from the inner accept/reject buttons, making
      // them un-tappable. GestureDetector with translucent behaviour
      // only fires when no descendant claims the tap first, so the
      // buttons below get the tap as intended.
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _openDetails(context),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.cyan.withValues(alpha: 0.18),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- Top: avatar + name + relationship + age/sex pills + time ----
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _PersonAvatar(
                    url: avatarUrl,
                    initial: initial,
                    size: 46,
                    bgColor: AppColors.cyan.withValues(alpha: 0.14),
                    fgColor: AppColors.cyanDeep,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name (FB-style prominent)
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w900,
                            color: AppColors.text,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 3),
                        // Relationship line ("পরিচর্যাকারী হিসেবে অনুরোধ")
                        Row(
                          children: [
                            const Icon(
                              Icons.volunteer_activism_rounded,
                              size: 13,
                              color: AppColors.cyanDeep,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                '$rel হিসেবে অনুরোধ',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        // Age / sex demographic pills (FB-style)
                        if (age != null || sex.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (age != null) _MetaPill(label: '$age বছর'),
                              if (sex.isNotEmpty) _MetaPill(label: sex),
                            ],
                          ),
                        ],
                        // Email preview (if joined by RPC)
                        if (email.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(
                                Icons.mail_outline_rounded,
                                size: 12,
                                color: AppColors.textDim,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.textDim,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        // Timestamp
                        if (tsStr.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.schedule_rounded,
                                size: 12,
                                color: AppColors.textDim,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                tsStr,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textDim,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              // ---- Request note (FB-style intro message) ----
              if (link.requestNote != null &&
                  link.requestNote!.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.cyan.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 4,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.cyanDeep,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          link.requestNote!.trim(),
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.text,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // ---- "বিস্তারিত দেখুন" hint so patients know they can tap to verify ----
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 12,
                    color: AppColors.cyanDeep.withValues(alpha: 0.85),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'বিস্তারিত দেখুন',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.cyanDeep.withValues(alpha: 0.95),
                    ),
                  ),
                ],
              ),
              // ---- Action row ----
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.text,
                        side: const BorderSide(
                          color: AppColors.lineStrong,
                        ),
                      ),
                      onPressed: onDecline,
                      child: const Text(
                        'প্রত্যাখ্যান',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.cyan,
                      ),
                      onPressed: onAccept,
                      child: const Text(
                        'গ্রহণ করুন',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Open the caretaker's full public profile in a modal bottom-sheet so
  /// the patient can see exactly who is asking (name, mobile, email,
  /// age, sex, relationship, joined date) BEFORE deciding to accept.
  Future<void> _openDetails(BuildContext context) async {
    final uid = link.caretakerUserId;
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.void2,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _PendingRequestDetailsSheet(
        userId: uid,
        fallbackName: _resolveName(link),
        fallbackEmail: (link.otherEmail ?? '').trim(),
        fallbackAge: link.otherAge,
        fallbackSex: (link.otherSex ?? '').trim(),
        fallbackRelationship: link.caretakerRelationship ?? 'পরিচর্যাকারী',
        fallbackNote: link.requestNote,
        onAccept: () {
          Navigator.of(ctx).pop();
          onAccept();
        },
        onDecline: () {
          Navigator.of(ctx).pop();
          onDecline();
        },
      ),
    ).catchError((e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('ত্রুটি: ${BanglaError.toBangla(e)}'),
          backgroundColor: AppColors.rose,
        ),
      );
    });
  }

  String _resolveName(CaretakerLink link) {
    // The inbox RPC joins the caretaker's `full_name` into the row
    // so we can show a real name instead of the generic label.
    final n = (link.otherFullName ?? '').trim();
    return n.isEmpty ? 'পরিচর্যাকারী' : n;
  }

  String _initialOf(String name) {
    final s = name.trim();
    if (s.isEmpty) return '?';
    // Bangla-friendly: use first user-perceived character so that
    // a name like "আবির" doesn't get split into "আ" + junk.
    return s.characters.first.toUpperCase();
  }
}

/// Modal bottom-sheet that shows the requesting caretaker's full public
/// profile (full name, mobile, email, age, sex, relationship, joined
/// date) so the patient can verify identity BEFORE accepting.
///
/// The bottom-sheet always calls `get_public_profile(uid)` for the most
/// up-to-date data; if that RPC fails (offline, etc.) we fall back to
/// whatever the inbox row already had joined.
class _PendingRequestDetailsSheet extends StatefulWidget {
  final String userId;
  final String fallbackName;
  final String fallbackEmail;
  final int? fallbackAge;
  final String fallbackSex;
  final String fallbackRelationship;
  final String? fallbackNote;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  const _PendingRequestDetailsSheet({
    required this.userId,
    required this.fallbackName,
    required this.fallbackEmail,
    required this.fallbackAge,
    required this.fallbackSex,
    required this.fallbackRelationship,
    required this.fallbackNote,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  State<_PendingRequestDetailsSheet> createState() =>
      _PendingRequestDetailsSheetState();
}

class _PendingRequestDetailsSheetState
    extends State<_PendingRequestDetailsSheet> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.userId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'user-not-found';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await SupabaseService.getPublicProfile(widget.userId);
      if (!mounted) return;
      setState(() {
        _data = res;
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

  String _sexBn(String raw) {
    final s = raw.trim().toLowerCase();
    if (s == 'male' || s == 'পুরুষ') return 'পুরুষ';
    if (s == 'female' || s == 'নারী' || s == 'মহিলা') return 'নারী';
    return raw.trim();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    // Prefer live RPC data, but always keep the inbox-joined data as
    // fallback so the sheet still renders something useful offline.
    final name = (d?['full_name'] ?? widget.fallbackName).toString();
    final email = (d?['email'] ?? widget.fallbackEmail).toString();
    final mobile = (d?['mobile'] ?? '').toString();
    final age = d?['age'] ?? widget.fallbackAge;
    final sexRaw = (d?['sex'] ?? widget.fallbackSex).toString();
    final sex = _sexBn(sexRaw);
    final rel = (d?['caretaker_relationship'] ?? widget.fallbackRelationship)
        .toString();
    final avatarUrl = (d?['avatar_url'] ?? '').toString();
    final createdAtStr = d?['created_at']?.toString();
    DateTime? createdAt;
    if (createdAtStr != null && createdAtStr.isNotEmpty) {
      createdAt = DateTime.tryParse(createdAtStr);
    }

    final tiles = <MapEntry<String, String>>[
      if (mobile.isNotEmpty) MapEntry('মোবাইল', mobile),
      if (email.isNotEmpty) MapEntry('ইমেইল', email),
      if (age != null) MapEntry('বয়স', '$age'),
      if (sex.isNotEmpty) MapEntry('লিঙ্গ', sex),
      if (rel.isNotEmpty) MapEntry('সম্পর্ক', rel),
      if (createdAt != null)
        MapEntry(
          'যোগদান',
          '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}',
        ),
    ];

    final viewInsets = MediaQuery.of(context).viewInsets;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: AppColors.void2,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppColors.lineStrong,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                        color: AppColors.text,
                      ),
                      const Expanded(
                        child: Text(
                          'অনুরোধকারীর তথ্য',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PublicProfileScreen(
                              userId: widget.userId,
                            ),
                          ),
                        ),
                        child: const Text(
                          'পূর্ণ প্রোফাইল',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _HeaderCard(
                    name: name,
                    rel: rel,
                    avatarUrl: avatarUrl,
                    loading: _loading,
                  ),
                  const SizedBox(height: 14),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: AppColors.cyan,
                          ),
                        ),
                      ),
                    )
                  else if (_error != null && d == null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.amber.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.amber.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.wifi_off_rounded,
                            size: 18,
                            color: AppColors.amber,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'বিস্তারিত প্রোফাইল লোড করা যায়নি — নিচে থাকা তথ্য ইনবক্স থেকে নেওয়া।',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.text,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _load,
                            child: const Text(
                              'আবার চেষ্টা',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (widget.fallbackNote != null &&
                      widget.fallbackNote!.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.cyan.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.format_quote_rounded,
                            color: AppColors.cyanDeep,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.fallbackNote!.trim(),
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.text,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  const Text(
                    'যোগাযোগের তথ্য',
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
                            padding:
                                const EdgeInsets.symmetric(vertical: 10),
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
                        if (tiles.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'পরিচর্যাকারী এখনো বিস্তারিত তথ্য দেননি।',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.cyan.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.cyan.withValues(alpha: 0.22),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 18,
                          color: AppColors.cyan,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'গোপনীয়তা রক্ষিত — মোবাইল ও ইমেইল আংশিক দেখানো হচ্ছে। সম্মতি দিলে ক্লিনিক্যাল তথ্য শেয়ার হবে।',
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
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.text,
                            side: const BorderSide(
                              color: AppColors.lineStrong,
                            ),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: widget.onDecline,
                          child: const Text(
                            'প্রত্যাখ্যান',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.cyan,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: widget.onAccept,
                          child: const Text(
                            'গ্রহণ করুন',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final String name;
  final String rel;
  final String avatarUrl;
  final bool loading;
  const _HeaderCard({
    required this.name,
    required this.rel,
    required this.avatarUrl,
    required this.loading,
  });

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

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.cyan,
            AppColors.cyan.withValues(alpha: 0.78),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.22),
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.4)),
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: avatarUrl.isEmpty
                ? Text(
                    _initials(name),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  )
                : Image.network(
                    avatarUrl,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Text(
                      _initials(name),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
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
                    fontSize: 18,
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
                  child: const Text(
                    'পরিচর্যাকারী',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (rel.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    rel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (loading) ...[
                  const SizedBox(height: 6),
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
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
}

class _ActiveRow extends StatelessWidget {
  final CaretakerLink link;
  final VoidCallback onRevoke;
  const _ActiveRow({required this.link, required this.onRevoke});

  @override
  Widget build(BuildContext context) {
    final rel = link.caretakerRelationship ?? 'পরিচর্যাকারী';
    final name = (link.otherFullName ?? '').trim();
    final ts = link.lastSeenAt ?? link.respondedAt;
    final tsStr = ts == null ? '' : RelativeTime.format(ts);
    final age = link.otherAge;
    final sex = (link.otherSex ?? '').trim();
    final avatarUrl = (link.otherAvatarUrl ?? '').trim();
    final initial = name.isEmpty ? rel.characters.first.toUpperCase() : name.characters.first.toUpperCase();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
      child: Row(
        children: [
          _PersonAvatar(
            url: avatarUrl,
            initial: initial,
            size: 42,
            bgColor: AppColors.mint.withValues(alpha: 0.14),
            fgColor: AppColors.mintDeep,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? rel : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.text,
                    height: 1.15,
                  ),
                ),
                if (name.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    rel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                // Age / sex chips for active caretakers too (consistency)
                if (age != null || sex.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (age != null) _MetaPill(label: '$age বছর'),
                      if (sex.isNotEmpty) _MetaPill(label: sex),
                    ],
                  ),
                ],
                if (tsStr.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'সংযুক্ত: $tsStr',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textDim,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.rose,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: onRevoke,
            child: const Text(
              'সরান',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.cyan.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.inbox_rounded,
                color: AppColors.cyanDeep,
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'কোনো অনুরোধ নেই',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'কেউ আপনাকে পর্যবে�্ষণ করার অনুরোধ পাঠালে এ�ানে দেখা যাবে।',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textMuted,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Round avatar with a real network image when available, otherwise
/// a coloured circle with the person's initial. Falls back to a
/// grey placeholder when both are missing.
class _PersonAvatar extends StatelessWidget {
  final String url;
  final String initial;
  final double size;
  final Color bgColor;
  final Color fgColor;
  const _PersonAvatar({
    required this.url,
    required this.initial,
    required this.size,
    required this.bgColor,
    required this.fgColor,
  });

  @override
  Widget build(BuildContext context) {
    Widget placeholder() => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
          ),
          child: Text(
            initial.isEmpty ? '?' : initial,
            style: TextStyle(
              color: fgColor,
              fontWeight: FontWeight.w900,
              fontSize: size * 0.42,
            ),
          ),
        );
    if (url.isEmpty) return placeholder();
    return ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return placeholder();
        },
        errorBuilder: (context, error, stackTrace) => placeholder(),
      ),
    );
  }
}

/// Small demographic / metadata chip (age, sex, etc.) used inside
/// inbox rows. Visual style is intentionally restrained so it never
/// competes with the primary action buttons.
class _MetaPill extends StatelessWidget {
  final String label;
  const _MetaPill({required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.line,
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10.5,
          color: AppColors.textMuted,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}
