/// Caretaker write flow — create / edit / delete a custom meal-plan
/// entry on the patient's calendar.
///
/// Mirrors the patient's `plan_editor.dart` sheet but routes the
/// writes through `45_caretaker_care_doctor.sql` caretaker
/// passthrough RPCs.
library;

import 'package:flutter/material.dart';

import '../../models/meal_item.dart';
import '../../services/ai_meal_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/time_format.dart';
import '../../widgets/bd_time_picker.dart';
import '../../widgets/mono_widgets.dart';

class CaretakerMealPlanEditorScreen extends StatefulWidget {
  final String patientUserId;
  final String? patientName;
  final DateTime effectiveDate;
  final String? existingId;
  final String? existingSlot;
  final String? existingScheduledTime;
  final String? existingFoodId;
  final String? existingCustomName;
  final String? existingPortionLabel;
  final String? existingNotes;

  const CaretakerMealPlanEditorScreen({
    super.key,
    required this.patientUserId,
    this.patientName,
    required this.effectiveDate,
    this.existingId,
    this.existingSlot,
    this.existingScheduledTime,
    this.existingFoodId,
    this.existingCustomName,
    this.existingPortionLabel,
    this.existingNotes,
  });

  @override
  State<CaretakerMealPlanEditorScreen> createState() =>
      _CaretakerMealPlanEditorScreenState();
}

class _CaretakerMealPlanEditorScreenState
    extends State<CaretakerMealPlanEditorScreen> {
  static const _slots = [
    ('breakfast', 'সকালের খাবার'),
    ('morning_snack', 'সকালের স্ন্যাক'),
    ('lunch', 'দুপুরের খাবার'),
    ('evening_snack', 'বিকেলের স্ন্যাক'),
    ('dinner', 'রাতের খাবার'),
    ('tiffin', 'তিফিন'),
    ('late_night', 'রাতের দেরি'),
    ('pre_workout', 'ব্যায়াম-পূর্ব'),
    ('post_workout', 'ব্যায়াম-পরবর্তী'),
    ('other', 'অন্যান্য'),
  ];

  late String _slot;
  TimeOfDay? _scheduledTime;
  final _foodSearchCtrl = TextEditingController();
  final _customNameCtrl = TextEditingController();
  final _portionCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  MealItem? _picked;
  List<MealItem> _foodSuggestions = [];
  bool _loadingFoods = false;
  bool _saving = false;
  bool _aiLoading = false;
  bool _useFreeText = true;

  @override
  void initState() {
    super.initState();
    _slot = widget.existingSlot ?? 'breakfast';
    if (widget.existingScheduledTime != null) {
      final parts = widget.existingScheduledTime!.split(':');
      if (parts.length == 2) {
        _scheduledTime = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 8,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
    }
    _customNameCtrl.text = widget.existingCustomName ?? '';
    _portionCtrl.text = widget.existingPortionLabel ?? '';
    _notesCtrl.text = widget.existingNotes ?? '';
    if (widget.existingFoodId != null) {
      _useFreeText = false;
      // We don't have the full MealItem yet, but we'll show the name
      _customNameCtrl.text = widget.existingCustomName ?? '';
    }
  }

  Future<void> _loadFoods(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _foodSuggestions = []);
      return;
    }
    setState(() => _loadingFoods = true);
    try {
      final results = await SupabaseService.searchFoods(q, limit: 10);
      if (!mounted) return;
      setState(() => _foodSuggestions = results);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingFoods = false);
    }
  }

  Future<void> _runAiAssist() async {
    final name = _customNameCtrl.text.trim();
    final quantity = _portionCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('খাবারের নাম লিখুন')),
      );
      return;
    }

    setState(() => _aiLoading = true);
    try {
      final result = await AiMealService.getDetails(
        mealName: name,
        quantity: quantity,
      );
      if (result != null && mounted) {
        setState(() {
          if (result.portion.isNotEmpty) _portionCtrl.text = result.portion;
          if (result.description.isNotEmpty) {
            final oldNotes = _notesCtrl.text.trim();
            final aiNotes = result.toNotesString();
            _notesCtrl.text =
                oldNotes.isEmpty ? aiNotes : '$oldNotes\n\n$aiNotes';
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI তথ্য যোগ করেছে')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI তথ্য আনতে পারেনি')),
        );
      }
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  @override
  void dispose() {
    _foodSearchCtrl.dispose();
    _customNameCtrl.dispose();
    _portionCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
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
      if (widget.existingId == null) {
        await SupabaseService.caretakerCreateMealPlanEntry(
          patientUserId: widget.patientUserId,
          effectiveDate: widget.effectiveDate,
          slot: _slot,
          scheduledTime:
              _scheduledTime == null ? null : _formatTime(_scheduledTime!),
          foodId: _picked?.id,
          customFoodName: _picked == null ? name : null,
          portionLabel: _portionCtrl.text.trim().isEmpty
              ? null
              : _portionCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty
              ? null
              : _notesCtrl.text.trim(),
        );
      } else {
        await SupabaseService.caretakerUpdateMealPlanEntry(
          planId: widget.existingId!,
          effectiveDate: widget.effectiveDate,
          slot: _slot,
          scheduledTime:
              _scheduledTime == null ? null : _formatTime(_scheduledTime!),
          clearScheduledTime: _scheduledTime == null,
          foodId: _picked?.id,
          clearFoodId: _picked == null,
          customFoodName: _picked == null ? name : null,
          portionLabel: _portionCtrl.text.trim().isEmpty
              ? null
              : _portionCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty
              ? null
              : _notesCtrl.text.trim(),
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('খাবারের পরিকল্পনা সংরক্ষিত')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('সংরক্�ণ করা যায়নি: $e')),
      );
    }
  }

  Future<void> _delete() async {
    if (widget.existingId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('এই খাবার মুছে ফেলুন?'),
        content: const Text('এটি রোগীর পরিকল্পনা থেকে সরানো হবে।'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('বাতিল'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.rose),
            child: const Text('মুছে ফেলুন'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await SupabaseService.caretakerDeleteMealPlanEntry(widget.existingId!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('মুছে ফেলা হয়েছে')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('মুছে ফেলা যায়নি: $e')),
      );
    }
  }

  String _formatTime(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.patientName ?? '').trim();
    final isEdit = widget.existingId != null;
    return Scaffold(
      backgroundColor: AppColors.svcCategoryBg,
      appBar: AppBar(
        backgroundColor: AppColors.svcHero,
        foregroundColor: Colors.white,
        title: Text(
          isEdit ? 'খাবার সম্পাদনা' : 'নতুন খাবার যোগ',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
        ),
        elevation: 0,
        actions: [
          if (isEdit)
            IconButton(
              tooltip: 'মুছে ফেলুন',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _saving ? null : _delete,
            ),
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
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 60),
        children: [
          if (name.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.svcHero.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.zero,
                ),
                child: Text(
                  '$name-এর পরিকল্পনায় যোগ হচ্ছে',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.svcHero,
                  ),
                ),
              ),
            ),
          _section('স্লট'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in _slots)
                GestureDetector(
                  onTap: () => setState(() => _slot = s.$1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _slot == s.$1 ? AppColors.svcHero : Colors.white,
                      borderRadius: BorderRadius.zero,
                      border: Border.all(
                        color: _slot == s.$1
                            ? AppColors.svcHero
                            : AppColors.line,
                        width: 1.2,
                      ),
                    ),
                    child: Text(
                      s.$2,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color:
                            _slot == s.$1 ? Colors.white : AppColors.ink,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _section('সময় (ঐচ্ছিক)'),
          InkWell(
            onTap: () async {
              // Bangladesh-friendly picker.
              final t = await showBdTimePicker(
                context,
                initial: _scheduledTime ?? const TimeOfDay(hour: 8, minute: 0),
                titleBn: 'খাবারের সময়',
                accent: AppColors.svcHero,
              );
              if (t != null) setState(() => _scheduledTime = t);
            },
            child: MonoCard(
              child: Row(
                children: [
                  const Icon(Icons.access_time_rounded,
                      color: AppColors.svcHero, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _scheduledTime == null
                          ? 'কোনো নির্দিষ্ট সময় নেই'
                          : formatTime12h(_scheduledTime!),
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: _scheduledTime == null
                            ? AppColors.smoke
                            : AppColors.ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  if (_scheduledTime != null)
                    InkWell(
                      onTap: () => setState(() => _scheduledTime = null),
                      child: const Icon(Icons.close_rounded,
                          size: 14, color: AppColors.smoke),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _section('খাবার'),
          MonoCard(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _useFreeText ? 'নিজের নাম লিখুন' : 'তালিকা থেকে বাছাই',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: AppColors.svcHero,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _useFreeText = !_useFreeText;
                        if (_useFreeText) {
                          _picked = null;
                        } else {
                          _customNameCtrl.clear();
                        }
                      }),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        _useFreeText ? 'তালিকা দেখুন' : 'নাম লিখুন',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.smoke,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_useFreeText)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _customNameCtrl,
                        decoration: InputDecoration(
                          hintText: 'যেমন: ভাত ও ডাল',
                          border: const OutlineInputBorder(
                            borderRadius: BorderRadius.zero,
                            borderSide: BorderSide(color: AppColors.line),
                          ),
                          enabledBorder: const OutlineInputBorder(
                            borderRadius: BorderRadius.zero,
                            borderSide: BorderSide(color: AppColors.line),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderRadius: BorderRadius.zero,
                            borderSide: BorderSide(color: AppColors.svcHero),
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 14),
                          suffixIcon: IconButton(
                            onPressed: _aiLoading ? null : _runAiAssist,
                            icon: _aiLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.auto_awesome,
                                    color: AppColors.svcHero),
                            tooltip: 'AI সাহায্য',
                          ),
                        ),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      if (_aiLoading)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'AI তথ্য বিশ্লেষণ করছে...',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.svcHero,
                            ),
                          ),
                        ),
                    ],
                  )
                else ...[
                  TextField(
                    onChanged: _loadFoods,
                    decoration: const InputDecoration(
                      hintText: 'খাবার খুঁজুন…',
                      prefixIcon: Icon(Icons.search_rounded, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: AppColors.line),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: AppColors.line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: AppColors.svcHero),
                      ),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_loadingFoods)
                    const Center(
                        child: Padding(
                      padding: EdgeInsets.all(12),
                      child: LoadingMark(size: 20),
                    ))
                  else if (_foodSuggestions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'খাবার খুঁজতে টাইপ করুন',
                        style: TextStyle(
                          color: AppColors.smoke,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _foodSuggestions.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (_, i) {
                          final f = _foodSuggestions[i];
                          final selected = _picked?.id == f.id;
                          return ListTile(
                            onTap: () => setState(() => _picked = f),
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8),
                            tileColor:
                                selected ? AppColors.svcCategoryBg : null,
                            shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.zero),
                            leading: Icon(
                              selected
                                  ? Icons.check_circle_rounded
                                  : Icons.circle_outlined,
                              color: selected
                                  ? AppColors.svcHero
                                  : AppColors.smoke,
                              size: 18,
                            ),
                            title: Text(
                              f.nameBn,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: selected
                                    ? AppColors.svcHero
                                    : AppColors.ink,
                              ),
                            ),
                            subtitle: Text(
                              '${f.category} · ${f.kcal.toStringAsFixed(0)} kcal',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.smoke,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _section('পরিমাণ ও নোট'),
          _field(_portionCtrl, 'পরিমাণ', 'যেমন: ১ কাপ'),
          _field(_notesCtrl, 'নোট', 'ডাক্তারের নির্দেশনা ইত্যাদি', maxLines: 3),
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

  Widget _field(
    TextEditingController ctrl,
    String label,
    String hint, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MonoCard(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: TextField(
          controller: ctrl,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            labelText: label,
            labelStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: AppColors.smoke,
            ),
            floatingLabelBehavior: FloatingLabelBehavior.always,
            border: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
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
    );
  }
}
