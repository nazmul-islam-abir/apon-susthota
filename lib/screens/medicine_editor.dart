import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/medicine.dart';
import '../services/ai_medicine_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../utils/time_format.dart';
import '../widgets/bd_time_picker.dart';
import '../widgets/mono_widgets.dart';

/// Result returned from [MedicineEditorSheet.show].
class MedicineEditResult {
  /// Either `nameBn`/`form`/etc. or `delete: true` to remove the row.
  final String nameBn;
  final String? nameEn;
  final String form;
  final String? strength;
  final double doseAmount;
  final String doseUnit;
  final String mealRelation;
  final List<MedicineScheduleSlot> schedule;
  final DateTime startDate;
  final DateTime? endDate;
  final String? notes;
  final bool clearNotes;
  final bool clearEndDate;
  final bool delete;

  MedicineEditResult({
    required this.nameBn,
    this.nameEn,
    required this.form,
    this.strength,
    required this.doseAmount,
    required this.doseUnit,
    required this.mealRelation,
    required this.schedule,
    required this.startDate,
    this.endDate,
    this.notes,
    this.clearNotes = false,
    this.clearEndDate = false,
    this.delete = false,
  });
}

/// Senior-friendly bottom-sheet editor for one medicine row.
///
/// Reuses the same editorial chrome as `plan_editor.dart` — large
/// tap targets, clear Bangla labels, soft "select one from this
/// group" chips instead of dropdowns.
class MedicineEditorSheet extends StatefulWidget {
  /// Existing medicine, or null when creating a new one.
  final Medicine? existing;
  const MedicineEditorSheet({super.key, this.existing});

  /// Show the sheet and resolve with the user's edits (or null
  /// if they tapped away without saving).
  static Future<MedicineEditResult?> show(
    BuildContext context, {
    Medicine? existing,
  }) {
    return showModalBottomSheet<MedicineEditResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      builder: (_) => MedicineEditorSheet(existing: existing),
    );
  }

  @override
  State<MedicineEditorSheet> createState() => _MedicineEditorSheetState();
}

class _MedicineEditorSheetState extends State<MedicineEditorSheet> {
  final _nameCtrl = TextEditingController();
  final _nameEnCtrl = TextEditingController();
  final _strengthCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _unitCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  late String _form;
  late String _mealRelation;
  late List<MedicineScheduleSlot> _schedule;
  late DateTime _startDate;
  DateTime? _endDate;
  bool _aiLoading = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.nameBn;
      _nameEnCtrl.text = e.nameEn ?? '';
      _form = e.form;
      _strengthCtrl.text = e.strength ?? '';
      _amountCtrl.text = e.doseAmount == e.doseAmount.toInt()
          ? e.doseAmount.toInt().toString()
          : e.doseAmount.toString();
      _unitCtrl.text = e.doseUnit == 'unit' ? '' : e.doseUnit;
      _mealRelation = e.mealRelation;
      _schedule = List.of(e.schedule);
      _startDate = e.startDate;
      _endDate = e.endDate;
      _notesCtrl.text = e.notes ?? '';
    } else {
      _form = 'tablet';
      _mealRelation = 'with_food';
      _schedule = const [];
      _startDate = DateTime.now();
      _amountCtrl.text = '1';
      _unitCtrl.text = '';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nameEnCtrl.dispose();
    _strengthCtrl.dispose();
    _amountCtrl.dispose();
    _unitCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double? _parseAmount(String text) {
    var s = text.trim();
    if (s.isEmpty) return null;
    const bnDigits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
    const enDigits = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    for (int i = 0; i < 10; i++) {
      s = s.replaceAll(bnDigits[i], enDigits[i]);
    }
    return double.tryParse(s.replaceAll(',', '.'));
  }

  bool get _canSave {
    if (_nameCtrl.text.trim().isEmpty) return false;
    final amt = _parseAmount(_amountCtrl.text);
    if (amt == null || amt <= 0) return false;
    return true;
  }

  Future<void> _pickTime({int? indexToReplace}) async {
    TimeOfDay initial = const TimeOfDay(hour: 8, minute: 0);
    if (indexToReplace != null && indexToReplace < _schedule.length) {
      // Parse from the stored 24-hour HH:mm string. We always store
      // 24-hour on the server, so re-hydrating the picker needs to
      // interpret the stored value as 24-hour (which [parseHhMm] does).
      initial = parseHhMm(_schedule[indexToReplace].time) ??
          const TimeOfDay(hour: 8, minute: 0);
    }
    // Use the Bangladesh-friendly picker: explicit AM/PM toggle,
    // never Bangla-numeral dial, never overflow on small phones.
    final picked = await showBdTimePicker(
      context,
      initial: initial,
      titleBn: 'ওষুধ খাওয়ার সময়',
      accent: AppColors.cyan,
    );
    if (picked == null) return;
    final slot = MedicineScheduleSlot.fromTime(picked.hour, picked.minute);
    setState(() {
      if (indexToReplace == null) {
        _schedule = [..._schedule, slot]..sort((a, b) => a.time.compareTo(b.time));
      } else {
        final next = List<MedicineScheduleSlot>.from(_schedule);
        next[indexToReplace] = slot;
        next.sort((a, b) => a.time.compareTo(b.time));
        _schedule = next;
      }
    });
  }

  void _removeSlot(int i) {
    setState(() => _schedule = List.of(_schedule)..removeAt(i));
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startDate : (_endDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035, 12, 31),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.ink,
            onPrimary: AppColors.paper,
            surface: AppColors.paper,
            onSurface: AppColors.ink,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  String _formatDate(DateTime d) => DateFormat('d MMM, yyyy', 'bn').format(d);

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('ওষুধ মুছবেন?'),
        content: const Text('এই ওষুধটি এবং এর সব ডোজ রেকর্ড মুছে যাবে।'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('বাতিল'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('মুছুন'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    Navigator.pop(
      context,
      MedicineEditResult(
        nameBn: _nameCtrl.text.trim(),
        form: _form,
        doseAmount: 1,
        doseUnit: _unitCtrl.text.trim().isEmpty ? 'unit' : _unitCtrl.text.trim(),
        mealRelation: _mealRelation,
        schedule: _schedule,
        startDate: _startDate,
        delete: true,
      ),
    );
  }

  void _save() {
    if (!_canSave) return;
    Navigator.pop(
      context,
      MedicineEditResult(
        nameBn: _nameCtrl.text.trim(),
        nameEn: _nameEnCtrl.text.trim().isEmpty ? null : _nameEnCtrl.text.trim(),
        form: _form,
        strength: _strengthCtrl.text.trim().isEmpty ? null : _strengthCtrl.text.trim(),
        doseAmount: _parseAmount(_amountCtrl.text) ?? 1,
        doseUnit: _unitCtrl.text.trim().isEmpty ? 'unit' : _unitCtrl.text.trim(),
        mealRelation: _mealRelation,
        schedule: _schedule,
        startDate: _startDate,
        endDate: _endDate,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        clearEndDate: _endDate == null,
        clearNotes: _notesCtrl.text.trim().isEmpty,
      ),
    );
  }

  Future<void> _runAiAssist() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ওষুধের নাম লিখুন')),
      );
      return;
    }

    setState(() => _aiLoading = true);
    try {
      final result = await AiMedicineService.getDetails(medicineName: name);
      if (result != null && mounted) {
        setState(() {
          if (result.strength.isNotEmpty) _strengthCtrl.text = result.strength;
          if (result.form.isNotEmpty) _form = result.form;
          if (result.doseAmount.isNotEmpty) _amountCtrl.text = result.doseAmount;
          if (result.doseUnit.isNotEmpty) _unitCtrl.text = result.doseUnit;
          if (result.mealRelation.isNotEmpty) _mealRelation = result.mealRelation;
          if (result.notes.isNotEmpty) {
            final oldNotes = _notesCtrl.text.trim();
            _notesCtrl.text =
                oldNotes.isEmpty ? result.notes : '$oldNotes\n\n${result.notes}';
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI ওষুধের তথ্য যোগ করেছে')),
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
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.paper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.94),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.graphite,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Overline(
                      widget.existing == null
                          ? 'নতুন ওষুধ যোগ করুন'
                          : 'ওষুধ সম্পাদনা',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'দৈনিক ওষুধের তালিকা',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 22),
                    _buildNameRow(),
                    const SizedBox(height: 16),
                    _buildFormPicker(),
                    const SizedBox(height: 16),
                    _buildStrengthRow(),
                    const SizedBox(height: 16),
                    _buildDoseRow(),
                    const SizedBox(height: 16),
                    _buildMealRelationPicker(),
                    const SizedBox(height: 22),
                    _buildScheduleEditor(),
                    const SizedBox(height: 22),
                    _buildDateRow(),
                    const SizedBox(height: 16),
                    _buildNotesRow(),
                    const SizedBox(height: 28),
                    _buildButtons(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Field builders ────────────────────────────────────────────────

  Widget _buildNameRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Overline('ওষুধের নাম'),
        const SizedBox(height: 8),
        TextField(
          controller: _nameCtrl,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
          decoration: InputDecoration(
            hintText: 'যেমন: মেটফরমিন',
            prefixIcon: const Icon(Icons.medication_outlined),
            suffixIcon: IconButton(
              onPressed: _aiLoading ? null : _runAiAssist,
              icon: _aiLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome, color: AppColors.svcHero),
              tooltip: 'AI সাহায্য',
            ),
          ),
        ),
        if (_aiLoading)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'AI ওষুধের তথ্য খুঁজছে...',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.svcHero,
              ),
            ),
          ),
        const SizedBox(height: 8),
        TextField(
          controller: _nameEnCtrl,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: AppColors.smoke,
          ),
          decoration: const InputDecoration(
            hintText: 'ইংরেজি নাম (ঐচ্ছিক)',
            prefixIcon: Icon(Icons.translate_outlined),
          ),
        ),
      ],
    );
  }

  Widget _buildFormPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Overline('আকার / ফর্ম'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in kMedicineForms)
              Pressable(
                onTap: () => setState(() => _form = f),
                borderRadius: BorderRadius.circular(28),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: _form == f ? AppGradients.aurora : null,
                    color: _form == f ? null : AppColors.chalk,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                        color: _form == f ? Colors.transparent : AppColors.graphite),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        medicineFormIcon(f),
                        size: 16,
                        color: _form == f ? AppColors.paper : AppColors.ink,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        medicineFormBn(f),
                        style: TextStyle(
                          color: _form == f ? AppColors.paper : AppColors.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildStrengthRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Overline('ক্ষমতা / স্ট্রেংথ (ঐচ্ছিক)'),
        const SizedBox(height: 8),
        TextField(
          controller: _strengthCtrl,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
          decoration: const InputDecoration(
            hintText: 'যেমন: ৫০০ মি.গ্রা., ৫ মি.গ্রা./মি.লি.',
            prefixIcon: Icon(Icons.science_outlined),
          ),
        ),
      ],
    );
  }

  Widget _buildDoseRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Overline('একবারে কতটুকু'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
                decoration: const InputDecoration(
                  hintText: 'পরিমাণ',
                  prefixIcon: Icon(Icons.numbers_outlined),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: TextField(
                controller: _unitCtrl,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
                decoration: InputDecoration(
                  hintText: 'একক (খালি রাখলে ${
                      medicineFormBn(_form)} ধরা হবে)',
                  prefixIcon: const Icon(Icons.scale_outlined),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMealRelationPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Overline('কখন নেবেন'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in kMealRelations)
              Pressable(
                onTap: () => setState(() => _mealRelation = r),
                borderRadius: BorderRadius.circular(28),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: _mealRelation == r ? AppGradients.aurora : null,
                    color: _mealRelation == r ? null : AppColors.chalk,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                        color: _mealRelation == r ? Colors.transparent : AppColors.graphite),
                  ),
                  child: Text(
                    mealRelationBn(r),
                    style: TextStyle(
                      color: _mealRelation == r ? AppColors.paper : AppColors.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildScheduleEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Overline('সময়সূচী (দিনে কতবার)'),
            const Spacer(),
            Pressable(
              onTap: () => _pickTime(),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: AppGradients.aurora,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, color: AppColors.paper, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'সময় যোগ',
                      style: TextStyle(
                        color: AppColors.paper,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_schedule.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.chalk,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.graphite),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.smoke, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'একটি সময় যোগ করুন — যেমন সকাল ৮টা, রাত ৯টা',
                    style: TextStyle(
                      color: AppColors.smoke,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Column(
            children: [
              for (int i = 0; i < _schedule.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildSlotRow(i),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildSlotRow(int i) {
    final slot = _schedule[i];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.chalk,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.graphite),
      ),
      child: Row(
        children: [
          Icon(slot.bucket.icon, color: AppColors.ink, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Show wall-clock time in 12-hour AM/PM so Bangladesh
                // users see "8:00 AM" instead of "08:00".
                Text(
                  formatTime12hFromString(slot.time),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  slot.bucket.labelBn,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.smoke,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
          Pressable(
            onTap: () => _pickTime(indexToReplace: i),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.paper,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.graphite),
              ),
              child: const Icon(Icons.edit_outlined, size: 18, color: AppColors.ink),
            ),
          ),
          const SizedBox(width: 8),
          Pressable(
            onTap: () => _removeSlot(i),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.paper,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.graphite),
              ),
              child: const Icon(Icons.close, size: 18, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Overline('কোর্সের সময়কাল'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildDateChip(
                label: 'শুরু',
                date: _startDate,
                onTap: () => _pickDate(isStart: true),
                clearable: false,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDateChip(
                label: 'শেষ (ঐচ্ছিক)',
                date: _endDate,
                onTap: () => _pickDate(isStart: false),
                clearable: true,
                onClear: () => setState(() => _endDate = null),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDateChip({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
    required bool clearable,
    VoidCallback? onClear,
  }) {
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          gradient: date != null ? AppGradients.aurora : null,
          color: date != null ? null : AppColors.chalk,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: date != null ? Colors.transparent : AppColors.graphite,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 18,
              color: date != null ? AppColors.paper : AppColors.ink,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: date != null ? AppColors.paper : AppColors.smoke,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    date != null ? _formatDate(date) : 'তারিখ বাছাই',
                    style: TextStyle(
                      color: date != null ? AppColors.paper : AppColors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (clearable && date != null && onClear != null)
              GestureDetector(
                onTap: onClear,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 18, color: AppColors.paper),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Overline('নোট (ঐচ্ছিক)'),
        const SizedBox(height: 8),
        TextField(
          controller: _notesCtrl,
          maxLines: 3,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: AppColors.ink,
          ),
          decoration: const InputDecoration(
            hintText: 'ডাক্তারের নির্দেশনা, পার্শ্ব-প্রতিক্রিয়া, রিফিলের তারিখ...',
            prefixIcon: Padding(
              padding: EdgeInsets.only(bottom: 48),
              child: Icon(Icons.notes_outlined),
            ),
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }

  Widget _buildButtons() {
    return Row(
      children: [
        if (widget.existing != null)
          Expanded(
            child: MonoButton(
              label: 'মুছে ফেলুন',
              leading: Icons.delete_outline,
              variant: MonoButtonVariant.outline,
              onPressed: _confirmDelete,
            ),
          ),
        if (widget.existing != null) const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: MonoButton(
            label: 'সংরক্ষণ',
            leading: Icons.check,
            onPressed: _canSave ? _save : null,
          ),
        ),
      ],
    );
  }
}

/// Helper used by the screen after the editor closes. Saves the
/// editor result to Supabase and notifies listeners.
///
/// `null` result → user cancelled. `MedicineEditResult.delete`
/// → delete the existing row.
Future<bool> applyMedicineEdit({
  MedicineEditResult? result,
  Medicine? existing,
}) async {
  if (result == null) return false;
  try {
    if (result.delete && existing != null) {
      await SupabaseService.deleteMedicine(existing.id);
      return true;
    }
    if (existing == null) {
      await SupabaseService.createMedicine(
        nameBn: result.nameBn,
        nameEn: result.nameEn,
        form: result.form,
        strength: result.strength,
        doseAmount: result.doseAmount,
        doseUnit: result.doseUnit,
        mealRelation: result.mealRelation,
        schedule: result.schedule,
        startDate: result.startDate,
        endDate: result.endDate,
        notes: result.notes,
      );
    } else {
      await SupabaseService.updateMedicine(
        id: existing.id,
        nameBn: result.nameBn,
        nameEn: result.nameEn,
        form: result.form,
        strength: result.strength,
        clearStrength: result.strength == null,
        doseAmount: result.doseAmount,
        doseUnit: result.doseUnit,
        mealRelation: result.mealRelation,
        schedule: result.schedule,
        startDate: result.startDate,
        endDate: result.endDate,
        clearEndDate: result.clearEndDate,
        notes: result.notes,
        clearNotes: result.clearNotes,
      );
    }
    return true;
  } catch (e) {
    debugPrint('applyMedicineEdit failed: $e');
    return false;
  }
}