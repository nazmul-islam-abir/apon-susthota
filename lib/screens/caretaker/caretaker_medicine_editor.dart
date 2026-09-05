/// Caretaker write flow — create / edit / delete a medicine on the
/// patient's catalogue. Wraps the patient's `MedicineEditorSheet`
/// so the UI is identical, but routes the writes through the
/// caretaker passthrough RPCs in `45_caretaker_care_doctor.sql`.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/medicine.dart';
import '../../services/ai_medicine_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/time_format.dart';
import '../../widgets/bd_time_picker.dart';
import '../../widgets/mono_widgets.dart';

class CaretakerMedicineEditorScreen extends StatefulWidget {
  final String patientUserId;
  final String? patientName;
  final Medicine? existing;
  const CaretakerMedicineEditorScreen({
    super.key,
    required this.patientUserId,
    this.patientName,
    this.existing,
  });

  @override
  State<CaretakerMedicineEditorScreen> createState() =>
      _CaretakerMedicineEditorScreenState();
}

class _CaretakerMedicineEditorScreenState
    extends State<CaretakerMedicineEditorScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _nameEnCtrl;
  late TextEditingController _strengthCtrl;
  late TextEditingController _doseAmountCtrl;
  late TextEditingController _notesCtrl;
  late String _form;
  late String _mealRelation;
  late List<TimeOfDay> _schedule;
  late DateTime _startDate;
  DateTime? _endDate;
  bool _saving = false;
  bool _aiLoading = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.nameBn ?? '');
    _nameEnCtrl = TextEditingController(text: e?.nameEn ?? '');
    _strengthCtrl = TextEditingController(text: e?.strength ?? '');
    _doseAmountCtrl = TextEditingController(
      text: e == null ? '১' : (e.doseAmount == e.doseAmount.toInt()
          ? '${e.doseAmount.toInt()}'
          : e.doseAmount.toString()),
    );
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _form = e?.form ?? 'tablet';
    _mealRelation = e?.mealRelation ?? 'any';
    _schedule = (e?.schedule ?? const [])
        .map((s) {
          final parts = s.time.split(':');
          if (parts.length != 2) return const TimeOfDay(hour: 8, minute: 0);
          final h = int.tryParse(parts[0]) ?? 8;
          final m = int.tryParse(parts[1]) ?? 0;
          return TimeOfDay(hour: h, minute: m);
        })
        .toList();
    if (_schedule.isEmpty) {
      _schedule.add(const TimeOfDay(hour: 8, minute: 0));
    }
    _startDate = e?.startDate ?? DateTime.now();
    _endDate = e?.endDate;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nameEnCtrl.dispose();
    _strengthCtrl.dispose();
    _doseAmountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final res = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.svcHero),
        ),
        child: child!,
      ),
    );
    if (res != null) setState(() => _startDate = res);
  }

  Future<void> _pickEndDate() async {
    final res = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate.add(const Duration(days: 30)),
      firstDate: _startDate,
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.svcHero),
        ),
        child: child!,
      ),
    );
    if (res != null) setState(() => _endDate = res);
  }

  Future<void> _addSlot() async {
    // Bangladesh-friendly picker (explicit AM/PM, no 24-hour dial,
    // no overflow on small phones).
    final res = await showBdTimePicker(
      context,
      initial: const TimeOfDay(hour: 12, minute: 0),
      titleBn: 'ওষুধ খাওয়ার সময়',
      accent: AppColors.svcHero,
    );
    if (res != null) {
      setState(() => _schedule.add(res));
    }
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
          if (result.doseAmount.isNotEmpty) _doseAmountCtrl.text = result.doseAmount;
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

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ওষুধের নাম আবশ্যক')),
      );
      return;
    }
    final dose = _parseAmount(_doseAmountCtrl.text) ?? 1;
    setState(() => _saving = true);
    try {
      if (widget.existing == null) {
        await SupabaseService.caretakerCreateMedicineForPatient(
          patientUserId: widget.patientUserId,
          nameBn: _nameCtrl.text.trim(),
          nameEn: _nameEnCtrl.text.trim().isEmpty
              ? null
              : _nameEnCtrl.text.trim(),
          form: _form,
          strength: _strengthCtrl.text.trim().isEmpty
              ? null
              : _strengthCtrl.text.trim(),
          doseAmount: dose,
          mealRelation: _mealRelation,
          schedule: _schedule
              .map((t) => {'time': _formatTime(t)})
              .toList(),
          startDate: _startDate,
          endDate: _endDate,
          notes: _notesCtrl.text.trim().isEmpty
              ? null
              : _notesCtrl.text.trim(),
        );
      } else {
        await SupabaseService.caretakerUpdateMedicine(
          medicineId: widget.existing!.id,
          nameBn: _nameCtrl.text.trim(),
          nameEn: _nameEnCtrl.text.trim().isEmpty
              ? null
              : _nameEnCtrl.text.trim(),
          form: _form,
          strength: _strengthCtrl.text.trim().isEmpty
              ? null
              : _strengthCtrl.text.trim(),
          doseAmount: dose,
          mealRelation: _mealRelation,
          schedule: _schedule
              .map((t) => {'time': _formatTime(t)})
              .toList(),
          startDate: _startDate,
          endDate: _endDate,
          clearEndDate: _endDate == null,
          notes: _notesCtrl.text.trim().isEmpty
              ? null
              : _notesCtrl.text.trim(),
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ওষুধ সংরক্ষিত হয়েছে')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('সংরক্ষণ করা যায়নি: $e')),
      );
    }
  }

  Future<void> _delete() async {
    if (widget.existing == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ওষুধ মুছে ফেলুন?'),
        content: Text('${widget.existing!.nameBn} আর দেখা যাবে না।'),
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
      await SupabaseService.caretakerDeleteMedicine(widget.existing!.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ওষুধ মুছে ফেলা হয়েছে')),
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

  Widget _buildMedicineNameField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MonoCard(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                hintText: 'যেমন: মেটফরমিন',
                labelText: 'বাংলা নাম (আবশ্যক)',
                labelStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: AppColors.smoke,
                ),
                floatingLabelBehavior: FloatingLabelBehavior.always,
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
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
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            if (_aiLoading)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'AI ওষুধের তথ্য খুঁজছে...',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.svcHero,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.patientName ?? '').trim();
    final title = widget.existing == null ? 'নতুন ওষুধ যোগ' : 'ওষুধ সম্পাদনা';
    return Scaffold(
      backgroundColor: AppColors.svcCategoryBg,
      appBar: AppBar(
        backgroundColor: AppColors.svcHero,
        foregroundColor: Colors.white,
        title: Text(
          name.isEmpty ? title : '$title ($name)',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        elevation: 0,
        actions: [
          if (widget.existing != null)
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
          _section('ওষুধের নাম'),
          _buildMedicineNameField(),
          _field(_nameEnCtrl, 'ইংরেজি নাম (ঐচ্ছিক)', 'যেমন: Metformin'),
          const SizedBox(height: 16),
          _section('ধরন ও মাত্রা'),
          _chipRow(kMedicineForms.map((f) => (medicineFormBn(f), f)).toList(),
              _form, (v) => setState(() => _form = v)),
          const SizedBox(height: 8),
          _field(_strengthCtrl, 'স্ট্রেংথ', 'যেমন: ৫০০ মিগ্রা'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _field(_doseAmountCtrl, 'মাত্রা', '১', keyboardType: TextInputType.number)),
              const SizedBox(width: 8),
              Expanded(child: _labelHint('খাবারের সাথে সম্পর্ক')),
            ],
          ),
          const SizedBox(height: 6),
          _chipRow(kMealRelations.map((r) => (mealRelationBn(r), r)).toList(),
              _mealRelation, (v) => setState(() => _mealRelation = v)),
          const SizedBox(height: 18),
          _section('সময়সূচি'),
          for (var i = 0; i < _schedule.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final t = await showBdTimePicker(
                          context,
                          initial: _schedule[i],
                          titleBn: 'ওষুধ খাওয়ার সময়',
                          accent: AppColors.svcHero,
                        );
                        if (t != null) {
                          setState(() => _schedule[i] = t);
                        }
                      },
                      child: MonoCard(
                        child: Row(
                          children: [
                            const Icon(Icons.access_time_rounded,
                                size: 16, color: AppColors.svcHero),
                            const SizedBox(width: 8),
                            // Display in 12-hour AM/PM; storage stays 24h.
                            Text(
                              formatTime12h(_schedule[i]),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: AppColors.ink,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_schedule.length > 1)
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: AppColors.rose, size: 18),
                      onPressed: () {
                        setState(() => _schedule.removeAt(i));
                      },
                    ),
                ],
              ),
            ),
          OutlinedButton.icon(
            onPressed: _addSlot,
            icon: const Icon(Icons.add_rounded),
            label: const Text('আরেকটি সময় যোগ করুন'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.svcHero,
              side: const BorderSide(color: AppColors.svcHero, width: 1.2),
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 18),
          _section('সময়কাল'),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _pickStartDate,
                  child: MonoCard(
                    child: Row(
                      children: [
                        const Icon(Icons.event_rounded,
                            size: 16, color: AppColors.svcHero),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('শুরু',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.smoke)),
                              Text(
                                DateFormat('d MMM, y', 'bn').format(_startDate),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: _pickEndDate,
                  child: MonoCard(
                    child: Row(
                      children: [
                        const Icon(Icons.event_busy_rounded,
                            size: 16, color: AppColors.svcHero),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('শেষ',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.smoke)),
                              Text(
                                _endDate == null
                                    ? 'চলমান'
                                    : DateFormat('d MMM, y', 'bn')
                                        .format(_endDate!),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_endDate != null)
                          InkWell(
                            onTap: () => setState(() => _endDate = null),
                            child: const Icon(Icons.close_rounded,
                                size: 14, color: AppColors.smoke),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _section('নোট'),
          _field(_notesCtrl, 'অতিরিক্ত নোট', 'ডাক্তারের নির্দেশনা ইত্যাদি',
              maxLines: 3),
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

  Widget _labelHint(String t) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text(
          t,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AppColors.smoke,
          ),
        ),
      );

  Widget _field(
    TextEditingController ctrl,
    String label,
    String hint, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MonoCard(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: TextField(
          controller: ctrl,
          maxLines: maxLines,
          keyboardType: keyboardType,
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

  Widget _chipRow(
    List<(String, String)> items,
    String selected,
    ValueChanged<String> onSelect,
  ) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final it in items)
          GestureDetector(
            onTap: () => onSelect(it.$2),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  color: it.$2 == selected ? Colors.white : AppColors.ink,
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _formatTime(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
