import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../models/bd_emergency.dart';
import '../services/nearby_locator.dart';
import '../services/sos_directory_service.dart';
import '../theme/app_theme.dart';

class SosDirectoryScreen extends StatefulWidget {
  const SosDirectoryScreen({super.key});

  @override
  State<SosDirectoryScreen> createState() => _SosDirectoryScreenState();
}

class _SosDirectoryScreenState extends State<SosDirectoryScreen> {
  BdEmergencyData? _data;
  bool _loading = true;
  String? _error;
  bool _usingFallback = false;
  bool _locationLoading = false;

  final NearbyLocator _locator = NearbyLocator();
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  BdDivision? _division;
  BdDistrict? _district;
  BdUpazila? _upazila;

  bool get _hasDistance {
    final d = _data;
    if (d == null) return false;
    return d.hospitals.any((h) => h.distanceKm != null);
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await SosDirectoryService.refresh();
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
        _usingFallback = false;
      });
      _tryAutoSort();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _data = SosDirectoryService.cached;
        _loading = false;
        _usingFallback = true;
      });
      _tryAutoSort();
    }
  }

  Future<void> _tryAutoSort() async {
    final data = _data;
    if (data == null || data.hospitals.isEmpty) return;
    final ok = await _locator.ensurePermission();
    if (!ok || !mounted) return;
    final pos = await _locator.currentPosition();
    if (pos == null || !mounted) return;
    for (final h in data.hospitals) {
      h.distanceKm = _locator.haversineKm(pos.latitude, pos.longitude, h.lat, h.lng);
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _requestLocationAndSort() async {
    if (_locationLoading) return;
    final data = _data;
    if (data == null || data.hospitals.isEmpty) return;
    final l = AppLocalizations.of(context)!;
    setState(() => _locationLoading = true);
    try {
      final ok = await _locator.ensurePermission();
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l.sosNoPermission),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      final pos = await _locator.currentPosition();
      if (pos == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l.sosNoGps),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      for (final h in data.hospitals) {
        h.distanceKm = _locator.haversineKm(pos.latitude, pos.longitude, h.lat, h.lng);
      }
      if (!mounted) return;
      setState(() {});
    } finally {
      if (mounted) setState(() => _locationLoading = false);
    }
  }

  Future<void> _callNumber(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _copyNumber(String phone) async {
    await Clipboard.setData(ClipboardData(text: phone));
    if (!mounted) return;
    final l = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(l.sosCopied),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _clearFilters() {
    setState(() {
      _division = null;
      _district = null;
      _upazila = null;
    });
  }

  List<BdHospital> _filtered(BdEmergencyData data) {
    Iterable<BdHospital> list = data.hospitals;
    if (_upazila != null && _district != null) {
      list = list.where((h) => h.districtId == _district!.id);
    } else if (_district != null) {
      list = list.where((h) => h.districtId == _district!.id);
    } else if (_division != null) {
      final distIds = data
          .districtsOf(_division!.id)
          .map((d) => d.id)
          .toSet();
      list = list.where((h) => distIds.contains(h.districtId));
    }
    final q = _query;
    if (q.isNotEmpty) {
      list = list.where((h) =>
          h.nameBn.toLowerCase().contains(q) ||
          h.nameEn.toLowerCase().contains(q) ||
          h.phone.toLowerCase().contains(q) ||
          h.addressEn.toLowerCase().contains(q) ||
          h.addressBn.toLowerCase().contains(q));
    }
    final out = list.toList();
    final hasDist = out.any((h) => h.distanceKm != null);
    if (hasDist) {
      out.sort((a, b) {
        final ad = a.distanceKm ?? double.infinity;
        final bd = b.distanceKm ?? double.infinity;
        final c = ad.compareTo(bd);
        if (c != 0) return c;
        return a.nameEn.compareTo(b.nameEn);
      });
    } else {
      out.sort((a, b) => a.nameEn.compareTo(b.nameEn));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(l.sosTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.ink, letterSpacing: -0.3)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _locationLoading
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.svcHero),
                    ),
                  )
                : IconButton(
                    tooltip: l.sosNearestCta,
                    onPressed: _requestLocationAndSort,
                    icon: Icon(
                      Icons.my_location_rounded,
                      size: 20,
                      color: _hasDistance ? AppColors.svcHero : AppColors.smoke,
                    ),
                  ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_usingFallback)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  color: AppColors.rose.withValues(alpha: 0.08),
                  child: Row(
                    children: const [
                      Icon(Icons.cloud_off_rounded, size: 14, color: AppColors.rose),
                      SizedBox(width: 6),
                      Text('অফলাইন — ক্যাশড ডেটা দেখাচ্ছে', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.rose)),
                    ],
                  ),
                ),
              const Divider(height: 1, color: AppColors.line),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.svcHero))
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.rose)))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.svcHero,
                  child: _buildBody(l),
                ),
    );
  }

  Widget _buildBody(AppLocalizations l) {
    final data = _data;
    if (data == null) return const SizedBox.shrink();
    final hospitals = _filtered(data);

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 80),
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      children: [
        _searchField(l),
        if (data.hotlines.isNotEmpty) _hotlinesSection(l, data),
        _nearestCta(l),
        _filterChips(l, data),
        const SizedBox(height: 8),
        _resultHeader(l, hospitals.length),
        const SizedBox(height: 6),
        ...hospitals.map((h) => _hospitalRow(l, h)),
        if (hospitals.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 40),
            child: Center(
              child: Text(
                'কোনো হাসপাতাল পাওয়া যায়নি',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.smoke),
              ),
            ),
          ),
      ],
    );
  }

  Widget _searchField(AppLocalizations l) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line, width: 1.2)),
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Icon(Icons.search_rounded, size: 20, color: AppColors.smoke),
            ),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'হাসপাতাল / নম্বর / ঠিকানা খুঁজুন',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
            ),
            if (_query.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.smoke),
                onPressed: () => _searchCtrl.clear(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _hotlinesSection(AppLocalizations l, BdEmergencyData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
          child: Text(l.sosHotlinesTitle, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.newsInk, letterSpacing: -0.2)),
        ),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: data.hotlines.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _hotlineCard(l, data.hotlines[i]),
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _hotlineCard(AppLocalizations l, BdHotline h) {
    return Container(
      width: 200,
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line, width: 1.2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(h.nameBn, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: AppColors.ink, height: 1.2)),
          const Spacer(),
          Row(
            children: [
              Expanded(child: Text(h.number, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.svcHero, letterSpacing: -0.3))),
              InkWell(
                onTap: () => _callNumber(h.number),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: AppColors.svcHero, borderRadius: BorderRadius.zero),
                  child: const Icon(Icons.phone_in_talk_rounded, color: Colors.white, size: 17),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _nearestCta(AppLocalizations l) {
    final hasDist = _hasDistance;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: InkWell(
        onTap: _requestLocationAndSort,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: hasDist ? AppColors.svcHero : Colors.white,
            borderRadius: BorderRadius.zero,
            border: Border.all(color: hasDist ? AppColors.svcHero : AppColors.line, width: 1.2),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: hasDist ? Colors.white : AppColors.svcHero,
                  borderRadius: BorderRadius.zero,
                ),
                child: Icon(
                  Icons.my_location_rounded,
                  size: 18,
                  color: hasDist ? AppColors.svcHero : Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l.sosNearestCta,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: hasDist ? Colors.white : AppColors.ink,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasDist ? 'আমার অবস্থান অনুযায়ী সাজানো' : 'আমার অবস্থান ব্যবহার করুন',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: hasDist ? Colors.white.withValues(alpha: 0.85) : AppColors.smoke,
                      ),
                    ),
                  ],
                ),
              ),
              if (_locationLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.svcHero,
                  ),
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: hasDist ? Colors.white : AppColors.smoke,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChips(AppLocalizations l, BdEmergencyData data) {
    final districts = _division == null ? const <BdDistrict>[] : data.districtsOf(_division!.id);
    final upazilas = _district == null ? const <BdUpazila>[] : _district!.upazilas;
    final hasAny = _division != null || _district != null || _upazila != null;

    Widget chip(String label, bool active, VoidCallback? onTap) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: active ? AppColors.svcHero : Colors.white,
              borderRadius: BorderRadius.zero,
              border: Border.all(color: active ? AppColors.svcHero : AppColors.line, width: 1.2),
            ),
            child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: active ? Colors.white : AppColors.ink)),
          ),
        ),
      );
    }

    Widget row(String label, List<Widget> children) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
              child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.smoke, letterSpacing: 0.5)),
            ),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: children,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: AppColors.surfaceHigh, border: const Border(top: BorderSide(color: AppColors.line), bottom: BorderSide(color: AppColors.line))),
      child: Column(
        children: [
          if (hasAny)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Align(
                alignment: Alignment.centerRight,
                child: InkWell(
                  onTap: _clearFilters,
                  child: Text('ফিল্টার মুছুন', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.rose)),
                ),
              ),
            ),
          row(
            l.sosPickDivision,
            [
              chip('সব', _division == null, () => setState(() { _division = null; _district = null; _upazila = null; })),
              ...data.divisions.map((d) => chip(d.nameBn, _division?.id == d.id, () => setState(() { _division = d; _district = null; _upazila = null; }))),
            ],
          ),
          if (_division != null)
            row(
              l.sosPickDistrict,
              [
                chip('সব', _district == null, () => setState(() { _district = null; _upazila = null; })),
                ...districts.map((d) => chip(d.nameBn, _district?.id == d.id, () => setState(() { _district = d; _upazila = null; }))),
              ],
            ),
          if (_district != null)
            row(
              l.sosPickUpazila,
              [
                chip('সব', _upazila == null, () => setState(() => _upazila = null)),
                ...upazilas.map((u) => chip(u.nameBn, _upazila?.id == u.id, () => setState(() => _upazila = u))),
              ],
            ),
        ],
      ),
    );
  }

  Widget _resultHeader(AppLocalizations l, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: Row(
        children: [
          Container(width: 4, height: 14, decoration: const BoxDecoration(color: AppColors.svcHero)),
          const SizedBox(width: 8),
          Text(l.sosAllHospitals, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: AppColors.newsInk, letterSpacing: 0.3)),
          const SizedBox(width: 6),
          Text('($count)', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.smoke)),
        ],
      ),
    );
  }

  Widget _hospitalRow(AppLocalizations l, BdHospital h) {
    final distKm = h.distanceKm;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line, width: 1)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(h.nameBn, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.ink, letterSpacing: -0.2)),
                      const SizedBox(height: 2),
                      Text(h.nameEn, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.smoke)),
                    ],
                  ),
                ),
                if (distKm != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.svcCategoryBg, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line, width: 0.8)),
                    child: Text('${distKm.toStringAsFixed(1)} km', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.svcHero)),
                  ),
              ],
            ),
            if (h.addressEn.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(h.addressEn, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.smoke)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(h.phone, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.ink, letterSpacing: -0.3)),
                ),
                InkWell(
                  onTap: () => _copyNumber(h.phone),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line, width: 1)),
                    child: const Icon(Icons.copy_rounded, size: 18, color: AppColors.smoke),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _callNumber(h.phone),
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(color: AppColors.svcHero, borderRadius: BorderRadius.zero),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.phone_in_talk_rounded, color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text('কল', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

