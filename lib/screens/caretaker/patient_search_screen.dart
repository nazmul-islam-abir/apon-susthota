/// Search-and-connect screen. The caretaker enters a Bangladeshi
/// mobile number (11 digits, "01XXXXXXXXX") and we look up matching
/// patients via the `search_patient_by_mobile` RPC. Each result row
/// opens a sheet to confirm relationship + send the request.
///
/// Layout:
///   • search field (always-visible, large tap target)
///   • recent matches list (debounced 350ms)
///   • result row -> "অনুরোধ পাঠান" sheet
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/caretaker_link.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';

class PatientSearchScreen extends StatefulWidget {
  const PatientSearchScreen({super.key});

  @override
  State<PatientSearchScreen> createState() => _PatientSearchScreenState();
}

class _PatientSearchScreenState extends State<PatientSearchScreen> {
  final TextEditingController _ctrl = TextEditingController();
  Timer? _debounce;
  bool _searching = false;
  List<Map<String, dynamic>> _results = [];
  Object? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  /// Normalize any phone input to the last 11 digits. The RPC accepts
  /// a flexible input, but Bangladeshi mobile numbers are 11 digits
  /// starting with "01", and many users type with spaces / "+880".
  String _normalize(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 11) {
      return digits.substring(digits.length - 11);
    }
    return digits;
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _runSearch);
  }

  Future<void> _runSearch() async {
    final raw = _ctrl.text.trim();
    if (raw.length < 4) {
      setState(() {
        _results = [];
        _error = null;
      });
      return;
    }
    final query = _normalize(raw);
    // The SQL RPC requires at least 7 digits to avoid dumping every
    // patient on a stray "1". Skip the call (and clear the list) when
    // the typed number is shorter than that, instead of letting the RPC
    // silently return an empty list.
    if (query.length < 7) {
      setState(() {
        _results = [];
        _error = null;
      });
      return;
    }
    if (query.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final rows =
          await SupabaseService.searchPatientByMobile(query);
      if (!mounted) return;
      setState(() {
        _results = rows;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = e;
        _results = [];
      });
    }
  }

  Future<void> _openSendSheet(Map<String, dynamic> patient) async {
    final result = await showModalBottomSheet<_SendResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _SendRequestSheet(patient: patient),
    );
    if (result == null || !mounted) return;
    setState(() {
      _searching = true;
    });
    try {
      final CaretakerLink link =
          await SupabaseService.sendCaretakerRequest(
        patientUserId: result.patientUserId,
        relationship: result.relationship,
        note: result.note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            link.status == CaretakerLinkStatus.pending
                ? 'অনুরোধ পাঠানো হয়েছে — রোগীর অনুমতির অপেক্ষায়'
                : 'অনুরোধ পাঠানো হয়েছে',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('অনুরোধ পাঠানো যায়নি: $e')),
      );
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            _Header(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: TextField(
                controller: _ctrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]')),
                ],
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText: '01XXXXXXXXX',
                  prefixIcon: const Icon(
                    Icons.phone_android_rounded,
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
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          color: AppColors.textDim,
                          onPressed: () {
                            _ctrl.clear();
                            _onChanged('');
                          },
                        ),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Text(
                  'খোঁা ব্যর্থ হয়েছে: $_error',
                  style: const TextStyle(
                    color: AppColors.rose,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Expanded(child: _buildResults()),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_results.isEmpty) {
      return const _Hint();
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemBuilder: (_, i) => _ResultRow(
        patient: _results[i],
        onTap: () => _openSendSheet(_results[i]),
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
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.violet.withValues(alpha: 0.16),
                  AppColors.cyan.withValues(alpha: 0.10),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.search_rounded,
              color: AppColors.violetDeep,
              size: 28,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'রোগী খুঁজুন',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppColors.text,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'রোগীর পূর্ণ মোবাইল নম্বর লিখুন (যেমন 01XXXXXXXXX) — '
            'সার্ভার থেকে মিলিয়ে দেখাবে।',
            style: TextStyle(
              fontSize: 13.5,
              color: AppColors.textMuted,
              height: 1.35,
            ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 24),
      child: Column(
        children: const [
          Icon(
            Icons.person_search_rounded,
            size: 56,
            color: AppColors.textDim,
          ),
          SizedBox(height: 14),
          Text(
            'নম্বর লিখলে এখানে মিলবে',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'শুধুমাত্র যারা অ্যাকাউন্ট খুলেছেন তাদের খুঁজে পাবেন —\nগোপনীয়তা রক্ষিত থাকে।',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.textDim,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final Map<String, dynamic> patient;
  final VoidCallback onTap;
  const _ResultRow({required this.patient, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = (patient['full_name'] ?? '') as String;
    final mobile = (patient['mobile'] ?? '') as String;
    final uid = (patient['user_id'] ?? '') as String;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: uid.isEmpty ? null : onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.violet.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: AppColors.violetDeep,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'অজানা ব্যবহারকারী' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      mobile.isEmpty ? '—' : mobile,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.violetDeep,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'সংযুক্ত হন',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
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
    'অন্য',
  ];

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.patient['full_name'] ?? '') as String;
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
                name.isEmpty ? 'রোগীর কাছে অনুরোধ পাঠান' : '$name-এর কাছে অনুরোধ',
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
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.violetDeep,
                    foregroundColor: Colors.white,
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