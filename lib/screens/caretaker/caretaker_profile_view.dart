/// Caretaker read-only patient profile viewer — mirrors the patient's
/// own profile screen 1:1 in structure, layout, and feel.
///
/// Nexora Redesign style: full-bleed hero image with dark overlay.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/caretaker_patient_summary.dart';
import '../../services/caretaker_data_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/caretaker_viewer_header.dart';
import 'caretaker_analytics_view.dart';
import 'caretaker_doctor_report_view.dart';

class CaretakerProfileView extends StatefulWidget {
  final CaretakerPatientSummary patient;
  const CaretakerProfileView({super.key, required this.patient});

  @override
  State<CaretakerProfileView> createState() => _CaretakerProfileViewState();
}

class _CaretakerProfileViewState extends State<CaretakerProfileView> {
  late Future<_ProfileData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ProfileData> _load() async {
    final uid = widget.patient.patientUserId;
    final results = await Future.wait([
      CaretakerDataService.getProfile(uid),
      Future.value(SupabaseService.getCaretakerClinicalSnapshot(patientUserId: uid)),
    ]);
    return _ProfileData(
      profile: (results[0] as Map?)?.cast<String, dynamic>() ?? const {},
      clinical: (results[1] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.void2,
      body: RefreshIndicator(
        color: AppColors.svcHero,
        onRefresh: _refresh,
        child: FutureBuilder<_ProfileData>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done && !snap.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.svcHero),
              );
            }
            final data = snap.data ?? _ProfileData.empty();
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                CaretakerViewerHeader(
                  patient: widget.patient,
                  screenTitle: 'রোগীর প্রোফাইল',
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _buildIdentityCard(data),
                      const SizedBox(height: 24),
                      _buildHealthQuickStats(data),
                      const SizedBox(height: 24),
                      _buildClinicalSection(data),
                      const SizedBox(height: 24),
                      _buildLifestyleSection(data),
                      const SizedBox(height: 24),
                      _buildSettingsList(),
                    ]),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildIdentityCard(_ProfileData data) {
    final p = widget.patient;
    final prof = data.profile;
    final age = _intOrNull(prof['age']);
    final sex = (prof['sex'] as String?) ?? '';
    final username = (prof['username'] as String?) ?? '';
    final city = (prof['city'] as String?) ?? '';
    final role = (prof['role'] as String?) ?? 'patient';
    final onInsulin = prof['on_insulin'] == true;
    final ckd = prof['has_ckd'] == true;
    final heart = prof['has_heart_disease'] == true;
    final anemia = prof['has_anemia'] == true;
    final rel = (p.caretakerRelationship ?? '').trim();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.line, width: 1),
              borderRadius: BorderRadius.zero,
            ),
            child: Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.zero,
              ),
              clipBehavior: Clip.hardEdge,
              alignment: Alignment.center,
              child: _avatar(p.fullName, p.avatarUrl),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            p.fullName.isEmpty ? 'রোগী' : p.fullName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
              letterSpacing: -0.3,
            ),
          ),
          if (username.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '@$username',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.smoke,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          if (age != null || sex.isNotEmpty || rel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  if (age != null) _metaPill('বয়স $age'),
                  if (sex.isNotEmpty) _metaPill(_sexBn(sex)),
                  if (rel.isNotEmpty) _metaPill(rel),
                ],
              ),
            ),
          if (city.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 14, color: AppColors.smoke),
                  const SizedBox(width: 4),
                  Text(
                    city,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.smoke,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              _statusPill(
                p.isActive ? 'সক্রিয়' : 'নিষ্ক্রিয়',
                p.isActive ? AppColors.mint : AppColors.lineStrong,
                filled: p.isActive,
              ),
              _statusPill(role == 'patient' ? 'রোগী' : role, AppColors.svcHero,
                  filled: true),
              if (onInsulin) _statusPill('ইনসুলিন', AppColors.amber),
              if (ckd) _statusPill('কিডনি সমস্যা', AppColors.violetDeep),
              if (heart) _statusPill('হৃদরোগ', AppColors.rose),
              if (anemia) _statusPill('রক্তশূন্যতা', AppColors.cyan),
            ],
          ),
        ],
      ),
    );
  }

  Widget _avatar(String name, String? url) {
    final fallback = Text(
      _initials(name),
      style: const TextStyle(
        color: AppColors.smoke,
        fontSize: 36,
        fontWeight: FontWeight.w900,
      ),
    );
    final trimmed = url?.trim();
    if (trimmed == null || trimmed.isEmpty) return fallback;
    return Image.network(
      trimmed,
      width: 96,
      height: 96,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => fallback,
      loadingBuilder: (_, child, prog) => prog == null ? child : fallback,
    );
  }

  Widget _metaPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: const BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.zero,
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
        ),
      ),
    );
  }

  Widget _statusPill(String label, Color color, {bool filled = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.zero,
        border: filled ? null : Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: filled ? Colors.white : color,
        ),
      ),
    );
  }

  Widget _buildHealthQuickStats(_ProfileData data) {
    final prof = data.profile;
    final cli = data.clinical;
    final hba1c = _asDouble(cli['hba1c_percent']) ?? _asDouble(prof['hba1c_percent']);
    final fbg = _asDouble(cli['fasting_glucose_mmol']) ??
        _asDouble(prof['fasting_glucose_mmol']);
    final sbp = _asInt(cli['systolic_bp']) ?? _asInt(prof['systolic_bp']);
    final dbp = _asInt(cli['diastolic_bp']) ?? _asInt(prof['diastolic_bp']);
    final bmi = _asDouble(cli['bmi']) ?? _asDouble(prof['bmi']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text(
              'স্বাস্থ্যের সংক্ষিপ্ত তথ্য',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
            Text(
              'লাইভ ডেটা',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.svcHero,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _statTile(
          icon: Icons.bloodtype_rounded,
          color: AppColors.cyan,
          label: 'HbA1c',
          value: hba1c == null ? '—' : '${hba1c.toStringAsFixed(1)}%',
        ),
        const SizedBox(height: 10),
        _statTile(
          icon: Icons.water_drop_rounded,
          color: AppColors.violet,
          label: 'ফাস্টিং গ্লুকোজ',
          value: fbg == null ? '—' : '${fbg.toStringAsFixed(1)} mmol/L',
        ),
        const SizedBox(height: 10),
        _statTile(
          icon: Icons.favorite_rounded,
          color: AppColors.rose,
          label: 'রক্তচাপ',
          value: (sbp == null || dbp == null)
              ? '—'
              : '$sbp / $dbp mmHg',
        ),
        const SizedBox(height: 10),
        _statTile(
          icon: Icons.monitor_weight_rounded,
          color: AppColors.amber,
          label: 'BMI',
          value: bmi == null ? '—' : bmi.toStringAsFixed(1),
        ),
      ],
    );
  }

  Widget _statTile({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.zero,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.smoke,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.trending_up_rounded,
              color: AppColors.lineStrong, size: 18),
        ],
      ),
    );
  }

  Widget _buildClinicalSection(_ProfileData data) {
    final prof = data.profile;
    final cli = data.clinical;
    final hba1c = _asDouble(cli['hba1c_percent']) ?? _asDouble(prof['hba1c_percent']);
    final fbg = _asDouble(cli['fasting_glucose_mmol']) ??
        _asDouble(prof['fasting_glucose_mmol']);
    final rbg = _asDouble(cli['random_glucose_mmol']) ??
        _asDouble(prof['random_glucose_mmol']);
    final pmg = _asDouble(cli['post_meal_glucose_mmol']) ??
        _asDouble(prof['post_meal_glucose_mmol']);
    final sbp = _asInt(cli['systolic_bp']) ?? _asInt(prof['systolic_bp']);
    final dbp = _asInt(cli['diastolic_bp']) ?? _asInt(prof['diastolic_bp']);
    final weight = _asDouble(prof['weight_kg']);
    final height = _asDouble(prof['height_cm']);
    final bmi = _asDouble(cli['bmi']) ?? _asDouble(prof['bmi']);
    final ckdStage = _asInt(cli['ckd_stage']) ?? _asInt(prof['ckd_stage']);
    final onInsulin = cli['on_insulin'] ?? prof['on_insulin'] ?? false;
    final heart = cli['has_heart_disease'] ?? prof['has_heart_disease'] ?? false;
    final anemia = cli['has_anemia'] ?? prof['has_anemia'] ?? false;
    final other = (cli['other_conditions'] ?? prof['other_conditions']) as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ক্লিনিক্যাল স্ন্যাপশট',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 12),
        _clinicalCard(
          children: [
            _clinicalRow(
              icon: Icons.bloodtype_rounded,
              color: AppColors.cyan,
              label: 'HbA1c',
              value: hba1c == null ? '—' : '${hba1c.toStringAsFixed(1)}%',
            ),
            _divider(),
            _clinicalRow(
              icon: Icons.water_drop_rounded,
              color: AppColors.violet,
              label: 'ফাস্টিং গ্লুকোজ',
              value: fbg == null ? '—' : '${fbg.toStringAsFixed(1)} mmol/L',
            ),
            _divider(),
            _clinicalRow(
              icon: Icons.science_rounded,
              color: AppColors.violetDeep,
              label: 'র‍্যান্ডম গ্লুকোজ',
              value: rbg == null ? '—' : '${rbg.toStringAsFixed(1)} mmol/L',
            ),
            _divider(),
            _clinicalRow(
              icon: Icons.restaurant_rounded,
              color: AppColors.amber,
              label: 'খাবার-পরবর্তী গ্লুকোজ',
              value: pmg == null ? '—' : '${pmg.toStringAsFixed(1)} mmol/L',
            ),
            _divider(),
            _clinicalRow(
              icon: Icons.favorite_rounded,
              color: AppColors.rose,
              label: 'রক্তচাপ',
              value: (sbp == null || dbp == null)
                  ? '—'
                  : '$sbp / $dbp mmHg',
            ),
            _divider(),
            _clinicalRow(
              icon: Icons.monitor_weight_rounded,
              color: AppColors.amber,
              label: 'ওজন / উচ্চতা',
              value: (weight == null || height == null)
                  ? '—'
                  : '${weight.toStringAsFixed(1)} কেজি • ${height.toStringAsFixed(0)} সেমি',
            ),
            _divider(),
            _clinicalRow(
              icon: Icons.calculate_rounded,
              color: AppColors.mintDeep,
              label: 'BMI',
              value: bmi == null ? '—' : bmi.toStringAsFixed(1),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (onInsulin == true) _flag('ইনসুলিন গ্রহণ করেন', AppColors.amber),
            if (ckdStage != null)
              _flag('CKD গ্রেড $ckdStage', AppColors.violetDeep),
            if (heart == true) _flag('হৃদরোগ আছে', AppColors.rose),
            if (anemia == true) _flag('রক্তশূন্যতা আছে', AppColors.cyan),
            if ((other ?? '').toString().trim().isNotEmpty)
              _flag(other!.trim(), AppColors.svcHero),
          ],
        ),
      ],
    );
  }

  Widget _clinicalCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.line),
      ),
      child: Column(children: children),
    );
  }

  Widget _divider() =>
      const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.line);

  Widget _clinicalRow({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.zero,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.smoke,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _flag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.zero,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }

  Widget _buildLifestyleSection(_ProfileData data) {
    final prof = data.profile;
    final activity = _lifestyleBn((prof['activity_level'] as String?) ?? '', _actBn);
    final mealSize = _lifestyleBn((prof['meal_size_pref'] as String?) ?? '', _mealBn);
    final foodPref = _lifestyleBn((prof['food_preference'] as String?) ?? '', _foodBn);
    final medication = (prof['medication'] as String?) ?? '';
    final linkedAt = widget.patient.linkedAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'জীবনযাত্রার তথ্য',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 12),
        _lifestyleCard(
          icon: Icons.directions_run_rounded,
          label: 'কার্যকলাপের মাত্রা',
          value: activity,
        ),
        const SizedBox(height: 8),
        _lifestyleCard(
          icon: Icons.restaurant_rounded,
          label: 'খাবারের পরিমাণ',
          value: mealSize,
        ),
        const SizedBox(height: 8),
        _lifestyleCard(
          icon: Icons.set_meal_rounded,
          label: 'খাদ্যাভ্যাস',
          value: foodPref,
        ),
        if (medication.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          _lifestyleCard(
            icon: Icons.medication_rounded,
            label: 'বর্তমান ওষুধ (বিবরণ)',
            value: medication.trim(),
          ),
        ],
        if (linkedAt != null) ...[
          const SizedBox(height: 8),
          _lifestyleCard(
            icon: Icons.link_rounded,
            label: 'সংযুক্তির তারিখ',
            value: DateFormat('d MMMM yyyy', 'bn').format(linkedAt.toLocal()),
          ),
        ],
      ],
    );
  }

  Widget _lifestyleCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.svcHero, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.smoke,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _lifestyleBn(String raw, Map<String, String> dict) {
    final key = raw.trim();
    if (key.isEmpty) return '—';
    return dict[key] ?? key;
  }

  static const _actBn = {
    'low': 'কম',
    'moderate': 'মাঝারি',
    'high': 'বেশি',
  };
  static const _mealBn = {
    'small': 'অল্প',
    'medium': 'মাঝারি',
    'large': 'বেশি',
  };
  static const _foodBn = {
    'omnivore': 'সর্বভুক',
    'vegetarian': 'নিরামিষ',
    'fish_only': 'শুধু মাছ',
    'no_beef': 'গরুর মাস ব্যতীত',
  };

  Widget _buildSettingsList() {
    final p = widget.patient;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'বিস্তারিত দেখুন',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'প্রতিটি আইটেম কেবল দেখার জন্য — কোনো এডিট নেই',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.smoke,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.zero,
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            children: [
              _settingItem(
                icon: Icons.picture_as_pdf_rounded,
                label: 'ডাক্তারের রিপোর্ট',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CaretakerDoctorReportView(patient: p),
                  ),
                ),
              ),
              const _Divider(),
              _settingItem(
                icon: Icons.insights_rounded,
                label: 'স্বাস্থ্য বিশ্লেষণ',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CaretakerAnalyticsView(patient: p),
                  ),
                ),
              ),
              const _Divider(),
              _settingItem(
                icon: Icons.sos_rounded,
                label: 'জরুরি যোগাযোগ',
                onTap: () => Navigator.of(context).pushNamed('/sos'),
              ),
              const _Divider(),
              _settingItem(
                icon: Icons.menu_book_outlined,
                label: 'অ্যাপ গাইড ও বিস্তারিত',
                onTap: () => Navigator.of(context).pushNamed('/details-home'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _settingItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          color: AppColors.svcCategoryBg,
          borderRadius: BorderRadius.zero,
        ),
        child: Icon(icon, color: AppColors.svcHero, size: 20),
      ),
      title: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: AppColors.lineStrong,
      ),
      onTap: onTap,
    );
  }

  static String _sexBn(String raw) {
    switch (raw) {
      case 'male':
        return 'পুরুষ';
      case 'female':
        return 'মহিলা';
      case 'other':
        return 'অন্যান্য';
      default:
        return raw;
    }
  }

  static String _initials(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return 'র';
    final parts = s.split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}';
    return s.characters.first.toUpperCase();
  }

  static double? _asDouble(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int? _asInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static int? _intOrNull(Object? v) => _asInt(v);
}

class _ProfileData {
  final Map<String, dynamic> profile;
  final Map<String, dynamic> clinical;
  const _ProfileData({required this.profile, required this.clinical});
  factory _ProfileData.empty() =>
      const _ProfileData(profile: {}, clinical: {});
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.line);
}
