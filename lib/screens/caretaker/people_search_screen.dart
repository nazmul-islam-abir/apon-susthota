/// Facebook-style "people" directory for the caretaker app.
///
/// Replaces the old patient-search screen. Lets a caretaker find
/// other users of the *opposite* role by:
///   * full name (substring)
///   * email (substring)
///   * last-4 mobile (digits)
///
/// Result rows carry avatar + role badge + masked mobile + masked
/// email + age/sex pills. A CTA button on each row:
///   * For already-linked users → "দেখুন" (opens public profile)
///   * For pending requests   → "অপেক্ষমান" (disabled, info only)
///   * Otherwise               → "সংযুক্ত হন" (opens send-request sheet)
///
/// Layout:
///   • Header (title + sub)
///   • Search field (debounced 350 ms)
///   • Recently searched chips (last 5)
///   • Result list
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/caretaker_provider.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/back_scaffold.dart';
import 'public_profile_screen.dart';

class PeopleSearchScreen extends StatefulWidget {
  const PeopleSearchScreen({super.key});

  @override
  State<PeopleSearchScreen> createState() => _PeopleSearchScreenState();
}

class _PeopleSearchScreenState extends State<PeopleSearchScreen> {
  final TextEditingController _ctrl = TextEditingController();
  Timer? _debounce;
  bool _searching = false;
  List<Map<String, dynamic>> _results = const [];
  Object? _error;
  List<String> _recent = const [];

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  /// Per-user recent-search storage key. Scope by the signed-in uid so
  /// a new account on the same device doesn't see the previous
  /// account's history (privacy bug fix).
  String get _recentKey {
    final uid = SupabaseService.currentUser?.id ?? 'anon';
    return 'people_search_recent_$uid';
  }

  Future<void> _loadRecent() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() => _recent = p.getStringList(_recentKey) ?? []);
    } catch (_) {/* ignore */}
  }

  Future<void> _saveRecent(String q) async {
    try {
      final p = await SharedPreferences.getInstance();
      final list = [q, ..._recent.where((x) => x != q)].take(5).toList();
      await p.setStringList(_recentKey, list);
      if (!mounted) return;
      setState(() => _recent = list);
    } catch (_) {/* ignore */}
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _runSearch);
  }

  Future<void> _runSearch() async {
    final q = _ctrl.text.trim();
    // Username is exactly 6 chars by SQL constraint, so we never fire
    // an RPC for shorter queries. Keeps the network quiet while the
    // user is still typing and prevents the empty-state hint from
    // flashing during partial input.
    if (q.length != 6) {
      setState(() {
        _results = const [];
        _error = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final rows = await SupabaseService.searchPeople(q);
      if (!mounted) return;
      setState(() {
        _results = rows;
        _searching = false;
      });
      unawaited(_saveRecent(q));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = e;
        _results = const [];
      });
    }
  }

  Future<void> _openSendSheet(Map<String, dynamic> person) async {
    final result = await showModalBottomSheet<_SendResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _SendRequestSheet(patient: person),
    );
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final prov = context.read<CaretakerProvider>();
    try {
      await prov.sendRequest(
        patientUserId: result.patientUserId,
        relationship: result.relationship,
        note: result.note,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '✅ ${person['full_name'] ?? 'রোগী'}–কে অনুরোধ পাঠানো হয়েছে',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );
      await _runSearch();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('অনুরোধ ব্যর্থ হয়েছে: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // The shared AppShellScaffold now sits the brand top bar (which
    // owns the status-bar inset via its own `SafeArea`) above this
    // body when `showTopBar` is true, so the body always starts
    // below the status bar. The previous `SafeArea(top: false)`
    // was a no-op on tabs where the bar was shown and unnecessary
    // everywhere else; we drop it so this screen doesn't fight the
    // shell's layout.
    return BackScaffold(
      title: 'খোঁজা',
      body: Column(
      children: [
        _Header(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            controller: _ctrl,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _runSearch(),
            onChanged: _onChanged,
            decoration: InputDecoration(
              hintText: 'ইউজারনেম (৬ অক্ষর)',
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: AppColors.violetDeep,
              ),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.violet,
                        ),
                      ),
                    )
                  : _ctrl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          color: AppColors.textDim,
                          onPressed: () {
                            _ctrl.clear();
                            _onChanged('');
                          },
                        ),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: AppColors.violetDeep,
                  width: 1.4,
                ),
              ),
            ),
          ),
        ),
        if (_recent.isNotEmpty && _results.isEmpty && !_searching)
          _RecentRow(
              recent: _recent,
              onTap: (q) {
                _ctrl.text = q;
                _ctrl.selection =
                    TextSelection.fromPosition(TextPosition(offset: q.length));
                _runSearch();
              }),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Text(
              'খোঁজা ব্যর্থ হয়েছে',
              style: const TextStyle(
                color: AppColors.rose,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        const SizedBox(height: 6),
        Expanded(child: _buildResults()),
      ],
    ),
    );
  }

  Widget _buildResults() {
    if (_ctrl.text.trim().length != 6) {
      return const _Hint();
    }
    if (_results.isEmpty && !_searching) {
      return const _NoResults();
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemBuilder: (_, i) => _PersonRow(
        person: _results[i],
        onConnect: () => _openSendSheet(_results[i]),
      ),
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemCount: _results.length,
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.violet.withValues(alpha: 0.16),
                      AppColors.cyan.withValues(alpha: 0.10),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.people_alt_rounded,
                  color: AppColors.violetDeep,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'মানুষ খুঁজুন',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppColors.text,
                        height: 1.1,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'নাম, ইউজারনেম দিয়ে — সবাইকে খুঁজুন',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  final List<String> recent;
  final ValueChanged<String> onTap;
  const _RecentRow({required this.recent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'সাম্প্রতিক খোঁজা',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textMuted,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: recent
                .map((q) => InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => onTap(q),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.history_rounded,
                              size: 14,
                              color: AppColors.textMuted,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              q,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.text,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_rounded,
              size: 56,
              color: AppColors.textDim.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 14),
            const Text(
              'ইউজারনেম দিয়ে খুঁজুন',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'সঠিক ৬ অক্ষরের ইউজারনেম লিখুন — শুধু নিখুঁত মিল দেখায়।\nগোপনীয়তা রক্ষিত থাকে।',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textDim,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_off_rounded,
              size: 56,
              color: AppColors.textDim.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 14),
            const Text(
              'কোনো মিল পাওয়া যায়নি',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'ইউজারনেম যাচাই করে আবার চেষ্টা করুন — শুধু নিখুঁত মিল দেখায়।',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textDim,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row in the people directory.
///
/// Shows avatar + name + role badge + masked mobile + masked email +
/// age/sex pill + the right CTA (active / pending / connect).
class _PersonRow extends StatelessWidget {
  final Map<String, dynamic> person;
  final VoidCallback onConnect;
  const _PersonRow({required this.person, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    final name = (person['full_name'] ?? '').toString().trim().isEmpty
        ? 'ব্যবহারকারী'
        : person['full_name'].toString();
    final rawUsername = (person['username'] ?? '').toString().trim();
    final role = (person['role'] ?? 'patient').toString();
    final isCaretaker = role == 'caretaker';
    final mobile = (person['mobile'] ?? '').toString();
    final email = (person['email'] ?? '').toString();
    final age = person['age'];
    final sex = (person['sex'] ?? '').toString();
    final isLinked = person['is_linked'] == true;
    final linkStatus = (person['link_status'] ?? '').toString();

    final ctaBg = isLinked
        ? AppColors.cyanDeep
        : linkStatus == 'pending'
            ? AppColors.amber
            : AppColors.violetDeep;
    final ctaFg = Colors.white;
    final ctaLabel = isLinked
        ? 'সক্রিয়'
        : linkStatus == 'pending'
            ? 'অপেক্ষমান'
            : 'সংযুক্ত হন';

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PublicProfileScreen(
                userId: (person['user_id'] ?? '') as String,
                person: person,
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(name: name, role: role),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.text,
                              height: 1.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _RoleBadge(role: role),
                      ],
                    ),
                    if (rawUsername.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        '@$rawUsername',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.violetDeep,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    if (mobile.isNotEmpty)
                      Text(
                        '📱 $mobile',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '✉ $email',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (age != null || sex.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (age != null)
                            _MetaPill(
                              label: 'বয়স ${age}',
                              color: AppColors.violet,
                            ),
                          if (sex.isNotEmpty)
                            _MetaPill(
                              label: sex == 'male' ? 'পুরুষ' : 'নারী',
                              color: AppColors.cyan,
                            ),
                          if (isCaretaker)
                            _MetaPill(
                              label: 'পরিচর্যাকারী',
                              color: AppColors.amber,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: isLinked ? null : onConnect,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isLinked ? ctaBg.withValues(alpha: 0.15) : ctaBg,
                      borderRadius: BorderRadius.circular(999),
                      border: isLinked
                          ? Border.all(color: ctaBg.withValues(alpha: 0.4))
                          : null,
                    ),
                    child: Text(
                      ctaLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: isLinked ? ctaBg : ctaFg,
                        height: 1.1,
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

class _Avatar extends StatelessWidget {
  final String name;
  final String role;
  const _Avatar({required this.name, required this.role});

  @override
  Widget build(BuildContext context) {
    final initials = _initials(name);
    final isCaretaker = role == 'caretaker';
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isCaretaker
              ? [AppColors.cyan, AppColors.cyanDeep]
              : [AppColors.violet, AppColors.violetDeep],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
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

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final isCaretaker = role == 'caretaker';
    final c = isCaretaker ? AppColors.amber : AppColors.cyan;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Text(
        isCaretaker ? 'পরিচর্যাকারী' : 'রোগী',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: c,
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final String label;
  final Color color;
  const _MetaPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// The internal value-type + sheet live alongside the people screen
// so we don't introduce a circular import on the legacy patient-search
// screen.
class _SendResult {
  final String patientUserId;
  final String relationship;
  final String? note;
  _SendResult(this.patientUserId, this.relationship, this.note);
}

class _SendRequestSheet extends StatefulWidget {
  final Map<String, dynamic> patient;
  const _SendRequestSheet({required this.patient});

  @override
  State<_SendRequestSheet> createState() => _SendRequestSheetState();
}

class _SendRequestSheetState extends State<_SendRequestSheet> {
  String _rel = 'পরিবার';
  final TextEditingController _noteCtrl = TextEditingController();
  bool _sending = false;

  static const List<String> _relChoices = [
    'পিতা',
    'মাতা',
    'সন্তান',
    'স্বামী/স্ত্রী',
    'ভাই/বোন',
    'পরিবার',
    'বন্ধু',
    'পরিচর্যাকারী',
    'অন্য',
  ];

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.patient['full_name'] ?? 'রোগী') as String;
    final insets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.lineStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                name.isEmpty
                    ? 'রোগীর কাছে অনুরোধ পাঠান'
                    : '$name-এর কাছে অনুরোধ',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: AppColors.text,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'সম্পর্কটি বেছে নিন এবং চাইলে একটি ছোট নোট যোগ করুন।',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _relChoices
                    .map((r) => _RelChip(
                          label: r,
                          selected: r == _rel,
                          onTap: () => setState(() => _rel = r),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _noteCtrl,
                minLines: 1,
                maxLines: 3,
                maxLength: 200,
                decoration: const InputDecoration(
                  hintText: 'ঐচ্ছিক নোট (যেমন: “আমি আপনার ছেলে”)',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.violetDeep,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _sending
                      ? null
                      : () {
                          setState(() => _sending = true);
                          Navigator.of(context).pop(
                            _SendResult(
                              widget.patient['user_id'] as String,
                              _rel,
                              _noteCtrl.text.trim().isEmpty
                                  ? null
                                  : _noteCtrl.text.trim(),
                            ),
                          );
                        },
                  child: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Text('অনুরোধ পাঠান'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RelChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _RelChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final c = selected ? AppColors.violetDeep : AppColors.surfaceHigh;
    final tc = selected ? Colors.white : AppColors.text;
    return Material(
      color: c,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: tc,
            ),
          ),
        ),
      ),
    );
  }
}
