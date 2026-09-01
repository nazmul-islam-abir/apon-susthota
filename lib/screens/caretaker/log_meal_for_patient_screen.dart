/// Caretaker write flow — log a meal on the patient's behalf.
///
/// UI mirrors the patient's "LogMeal" sheet but talks to the
/// caretaker write-passthrough RPC added in
/// `45_caretaker_care_doctor.sql` (caretaker_log_meal_for_patient).
/// The server validates the caretaker has an active link to the
/// patient and impersonates the patient for the row write.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/meal_item.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/mono_widgets.dart';

class LogMealForPatientScreen extends StatefulWidget {
  final String patientUserId;
  final String? patientName;
  const LogMealForPatientScreen({
    super.key,
    required this.patientUserId,
    this.patientName,
  });

  @override
  State<LogMealForPatientScreen> createState() =>
      _LogMealForPatientScreenState();
}

class _LogMealForPatientScreenState extends State<LogMealForPatientScreen> {
  static const _slots = [
    ('breakfast', 'সকালের খাবার', Icons.wb_sunny_rounded),
    ('morning_snack', 'সকালের স্ন্যাক', Icons.cookie_rounded),
    ('lunch', 'দুপুরের খাবার', Icons.lunch_dining_rounded),
    ('evening_snack', 'বিকেলের স্ন্যাক', Icons.cookie_rounded),
    ('dinner', 'রাতের খাবার', Icons.dinner_dining_rounded),
  ];

  String _slot = 'breakfast';
  String _status = 'eaten';
  String _impact = 'good';
  String? _impactReason;

  final _foodSearchCtrl = TextEditingController();
  Timer? _debounce;
  List<MealItem> _foods = [];
  bool _searching = false;
  MealItem? _picked;
  final _customNameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _foodSearchCtrl.dispose();
    _customNameCtrl.dispose();
    _notesCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _foods = const []);
      return;
    }
    setState(() => _searching = true);
    try {
      final list = await SupabaseService.searchFoods(q, limit: 15);
      if (!mounted) return;
      setState(() {
        _foods = list;
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _searching = false);
    }
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(v));
  }

  Future<void> _save() async {
    final name = _picked?.nameBn ?? _customNameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('একটি খাবার বেছে নিন অথবা নাম লিখুন')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await SupabaseService.caretakerLogMealForPatient(
        patientUserId: widget.patientUserId,
        mealSlot: _slot,
        foodId: _picked?.id,
        foodNameBn: name,
        status: _status,
        impact: _impact,
        reason: _impactReason,
        planDay: null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$name" লগ হয়েছে')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('লগ করা যায়নি: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.patientName ?? '').trim();
    return Scaffold(
      backgroundColor: AppColors.svcCategoryBg,
      appBar: AppBar(
        backgroundColor: AppColors.svcHero,
        foregroundColor: Colors.white,
        title: Text(
          name.isEmpty
              ? 'রোগীর পক্ষে খাবার লগ'
              : '$name-এর পক্ষে খাবার লগ',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
        ),
        elevation: 0,
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 60),
        children: [
          _section('স্লট'),
          _chips(
            _slots.map((s) => (s.$2, s.$1)).toList(),
            _slot,
            (v) => setState(() => _slot = v),
          ),
          const SizedBox(height: 18),
          _section('অবস্থা'),
          _chips(
            const [
              ('খাওয়া হয়েছে', 'eaten'),
              ('বিকল্প', 'swap'),
              ('পরিকল্পনার বাইরে', 'off_plan'),
            ],
            _status,
            (v) => setState(() => _status = v),
          ),
          const SizedBox(height: 18),
          _section('প্রভাব'),
          _chips(
            const [
              ('ভালো', 'good'),
              ('মাঝারি', 'neutral'),
              ('খারাপ', 'bad'),
            ],
            _impact,
            (v) => setState(() => _impact = v),
          ),
          const SizedBox(height: 6),
          if (_status == 'off_plan')
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: MonoCard(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                child: TextField(
                  controller: _notesCtrl,
                  onChanged: (v) => _impactReason = v.trim(),
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'কারণ (ঐচ্ছিক)',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 14),
          _section('খাবার'),
          MonoCard(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: TextField(
              controller: _foodSearchCtrl,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'খাবার খুঁজুন… (যেমন: ভাত)',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
                prefixIcon: Icon(Icons.search_rounded, size: 18),
              ),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
          ),
          if (_searching)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: AppColors.svcHero,
                    strokeWidth: 2,
                  ),
                ),
              ),
            )
          else if (_foods.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final f in _foods.take(8))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _picked = f;
                            _customNameCtrl.text = f.nameBn;
                            _foodSearchCtrl.clear();
                            _foods = const [];
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceHigh,
                            borderRadius: BorderRadius.zero,
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.restaurant_rounded,
                                  size: 14, color: AppColors.svcHero),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  f.nameBn,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.ink,
                                  ),
                                ),
                              ),
                              Text(
                                '${f.kcal.toStringAsFixed(0)} কিলোক্যালরি',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.smoke,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          MonoCard(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: TextField(
              controller: _customNameCtrl,
              decoration: const InputDecoration(
                hintText: 'অথবা কাস্টম খাবারের নাম',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
          ),
          if (_picked != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded,
                      color: AppColors.mintDeep, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'নির্বাচিত: ${_picked!.nameBn}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        color: AppColors.mintDeep,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _picked = null;
                        _customNameCtrl.clear();
                      });
                    },
                    child: const Icon(Icons.close_rounded,
                        size: 14, color: AppColors.smoke),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 30),
          SizedBox(
            height: 52,
            child: MonoButton(
              label: _saving ? 'সংরক্ষণ হচ্ছে…' : 'লগ সম্পন্ন করুন',
              leading: Icons.check_rounded,
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
        child: Text(
          t,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: AppColors.smoke,
            letterSpacing: 0.5,
          ),
        ),
      );

  Widget _chips(
    List<(String, String)> items,
    String selected,
    ValueChanged<String> onSelect,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final it in items)
          GestureDetector(
            onTap: () => onSelect(it.$2),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: it.$2 == selected ? AppColors.svcHero : Colors.white,
                borderRadius: BorderRadius.zero,
                border: Border.all(
                  color: it.$2 == selected
                      ? AppColors.svcHero
                      : AppColors.line,
                  width: 1.2,
                ),
              ),
              child: Text(
                it.$1,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color:
                      it.$2 == selected ? Colors.white : AppColors.ink,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
