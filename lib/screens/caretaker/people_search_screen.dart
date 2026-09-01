/// People Search screen — high-fidelity technical discovery for caregivers (Nexora Redesign).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/caretaker_provider.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/mono_widgets.dart';
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

  String get _recentKey {
    final uid = SupabaseService.currentUser?.id ?? 'anon';
    return 'people_search_recent_$uid';
  }

  Future<void> _loadRecent() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() => _recent = p.getStringList(_recentKey) ?? []);
    } catch (_) {}
  }

  Future<void> _saveRecent(String q) async {
    try {
      final p = await SharedPreferences.getInstance();
      final list = [q, ..._recent.where((x) => x != q)].take(5).toList();
      await p.setStringList(_recentKey, list);
      if (!mounted) return;
      setState(() => _recent = list);
    } catch (_) {}
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _runSearch);
  }

  Future<void> _runSearch() async {
    final q = _ctrl.text.trim();
    if (q.length != 6) {
      setState(() { _results = const []; _error = null; });
      return;
    }
    setState(() { _searching = true; _error = null; });
    try {
      final rows = await SupabaseService.searchPeople(q);
      if (!mounted) return;
      setState(() { _results = rows; _searching = false; });
      unawaited(_saveRecent(q));
    } catch (e) {
      if (mounted) setState(() { _searching = false; _error = e; _results = const []; });
    }
  }

  Future<void> _openSendSheet(Map<String, dynamic> person) async {
    final result = await showModalBottomSheet<_SendResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (_) => _SendRequestSheet(patient: person),
    );
    if (result == null || !mounted) return;
    try {
      await context.read<CaretakerProvider>().sendRequest(
        patientUserId: result.patientUserId,
        relationship: result.relationship,
        note: result.note,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ ${person['full_name'] ?? 'রোগী'}–কে অনুরোধ পাঠানো হয়েছে')));
        await _runSearch();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('অনুরোধ ব্যর্থ: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.svcCategoryBg,
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        slivers: [
          _buildHero(),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildSearchField(),
            ),
          ),
          if (_recent.isNotEmpty && _results.isEmpty && !_searching)
            SliverToBoxAdapter(child: _RecentRow(recent: _recent, onTap: (q) { _ctrl.text = q; _runSearch(); })),
          
          if (_error != null)
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(20), child: Text('খোঁজা ব্যর্থ হয়েছে: $_error', style: const TextStyle(color: AppColors.rose)))),

          SliverToBoxAdapter(child: _buildResultsSection()),
        ],
      ),
    );
  }

  Widget _buildHero() {
    const url = 'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/app/photo-1564352969906-8b7f46ba4b8b.avif?token=eyJraWQiOiJhZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJhcHAvcGhvdG8tMTU2NDM1Mjk2OTkwNi04YjdmNDZiYTRiOGIuYXZpZiIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODc4Njg2MjksImV4cCI6MTgxOTQwNDYyOX0.Jdl-6cqT6wHh_nv8j-7oD3zjU2KcoR4e5ohJVnZgTNs';
    return SliverToBoxAdapter(
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.svcHero,
          image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover, opacity: 0.7),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: Container(color: Colors.black.withValues(alpha: 0.35))),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SafeArea(bottom: false, child: SizedBox(height: 20)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('মানুষ খুঁজুন', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -1)),
                      SizedBox(height: 8),
                      Text('ইউজারনেম দিয়ে রোগীদের সাথে সংযুক্ত হন', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line, width: 1.5)),
      child: Row(
        children: [
          const SizedBox(width: 16),
          const Icon(Icons.search_rounded, color: AppColors.svcHero, size: 20),
          Expanded(
            child: TextField(
              controller: _ctrl,
              onChanged: _onChanged,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(hintText: '৬ অক্ষরের ইউজারনেম', hintStyle: TextStyle(color: AppColors.smoke), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16)),
            ),
          ),
          if (_searching)
            const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.svcHero)))
          else if (_ctrl.text.isNotEmpty)
            IconButton(icon: const Icon(Icons.close_rounded), onPressed: () { _ctrl.clear(); _onChanged(''); }),
        ],
      ),
    );
  }

  Widget _buildResultsSection() {
    if (_ctrl.text.trim().length != 6) return const _Hint();
    if (_results.isEmpty && !_searching) return const _NoResults();
    
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 140),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _PersonRow(person: _results[i], onConnect: () => _openSendSheet(_results[i])),
    );
  }
}

class _PersonRow extends StatelessWidget {
  final Map<String, dynamic> person;
  final VoidCallback onConnect;
  const _PersonRow({required this.person, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    final name = (person['full_name'] ?? 'ব্যবহারকারী').toString();
    final username = person['username'].toString();
    final isLinked = person['is_linked'] == true;
    final linkStatus = (person['link_status'] ?? '').toString();

    final ctaLabel = isLinked ? 'সক্রিয়' : (linkStatus == 'pending' ? 'অপেক্ষমান' : 'সংযুক্ত হন');
    final ctaColor = isLinked ? AppColors.svcHero : (linkStatus == 'pending' ? AppColors.amber : AppColors.svcHero);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.line, width: 1.2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _Avatar(name: name, size: 60),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.ink, height: 1.1)),
                    const SizedBox(height: 4),
                    Text('@$username', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.svcHero)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: MonoButton(
              label: ctaLabel,
              onPressed: (isLinked || linkStatus == 'pending') ? null : onConnect,
              color: ctaColor,
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final double size;
  const _Avatar({required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: AppColors.svcCategoryBg,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
        style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.w900, color: AppColors.svcHero),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 32),
      child: Column(
        children: [
          const Icon(Icons.search_rounded, size: 48, color: AppColors.lineStrong),
          const SizedBox(height: 16),
          const Text('সঠিক ৬ অক্ষরের ইউজারনেম লিখুন', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.smoke)),
        ],
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 64),
      child: Center(child: Text('কোনো মিল পাওয়া যায়নি', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.smoke))),
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
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('সাম্প্রতিক খোঁজা', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.smoke, letterSpacing: 0.5)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: recent.map((q) => GestureDetector(
              onTap: () => onTap(q),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line)),
                child: Text(q, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.ink)),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }
}

class _SendResult {
  final String patientUserId, relationship;
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
  final _noteCtrl = TextEditingController();

  static const _choices = ['পিতা', 'মাতা', 'সন্তান', 'স্বামী/স্ত্রী', 'ভাই/বোন', 'পরিবার', 'বন্ধু', 'পরিচর্যাকারী', 'অন্য'];

  @override
  Widget build(BuildContext context) {
    final name = widget.patient['full_name'] ?? 'রোগী';
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$name-এর সাথে সংযোগ', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.ink)),
            const SizedBox(height: 20),
            const Text('আপনার সম্পর্ক বাছাই করুন:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.smoke)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _choices.map((c) => GestureDetector(
                onTap: () => setState(() => _rel = c),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(color: _rel == c ? AppColors.svcHero : Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: _rel == c ? AppColors.svcHero : AppColors.line)),
                  child: Text(c, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: _rel == c ? Colors.white : AppColors.ink)),
                ),
              )).toList(),
            ),
            const SizedBox(height: 24),
            TextField(controller: _noteCtrl, decoration: const InputDecoration(hintText: 'ঐচ্ছিক বার্তা...', border: OutlineInputBorder(borderRadius: BorderRadius.zero))),
            const SizedBox(height: 24),
            SizedBox(width: double.infinity, child: MonoButton(label: 'অনুরোধ পাঠান', onPressed: () => Navigator.pop(context, _SendResult(widget.patient['user_id'], _rel, _noteCtrl.text)))),
          ],
        ),
      ),
    );
  }
}
