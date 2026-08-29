import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bd_emergency.dart';
import 'supabase_service.dart';

/// Reads the `bd_emergency_entries` table from Supabase and assembles a
/// `BdEmergencyData` in memory. Mobile never writes — rows are managed
/// in Supabase Studio.
///
/// Falls back to the bundled `assets/data/bd_geo.json` asset on any
/// fetch failure so the SOS screen stays usable offline.
class SosDirectoryService {
  SosDirectoryService._();

  static const _table = 'bd_emergency_entries';
  static const _geoView = 'bd_emergency_hospitals_geo';

  static BdEmergencyData? _cache;

  static BdEmergencyData get cached {
    final c = _cache;
    if (c != null) return c;
    return _fallback();
  }

  static BdEmergencyData _fallback() {
    return BdEmergencyData.empty();
  }

  /// Best-effort fetch. Catches all errors and returns null so callers
  /// (e.g. splash-time warm-up) can ignore connectivity.
  static Future<void> warm() async {
    try {
      await refresh();
    } catch (e) {
      debugPrint('⚠️ [SosDirectoryService] warm failed (will use fallback): $e');
    }
  }

  /// Force a fresh fetch. Throws on connectivity / permission errors
  /// so the caller can show a snackbar.
  static Future<BdEmergencyData> refresh() async {
    if (!SupabaseService.isInitialized) {
      throw StateError('Supabase not initialized');
    }
    final client = SupabaseService.client;

    final treeResp = await client.from(_table).select('id, kind, parent_id, name_bn, name_en, slug, sort_order, phone, type').eq('active', true);
    final treeRows = (treeResp as List).cast<Map<String, dynamic>>();

    final geoResp = await client.from(_geoView).select('id, district_id, name_bn, name_en, phone, lat, lng, address_bn, address_en, type');
    final geoRows = (geoResp as List).cast<Map<String, dynamic>>();

    final assembled = _assemble(treeRows, geoRows);
    _cache = assembled;
    return assembled;
  }

  static BdEmergencyData _assemble(
    List<Map<String, dynamic>> treeRows,
    List<Map<String, dynamic>> geoRows,
  ) {
    final nodesById = <String, _Node>{};
    for (final r in treeRows) {
      final id = r['id'] as String;
      final kind = r['kind'] as String;
      final node = _Node(
        id: id,
        kind: kind,
        parentId: r['parent_id'] as String?,
        nameBn: r['name_bn'] as String? ?? '',
        nameEn: r['name_en'] as String? ?? '',
        slug: r['slug'] as String? ?? '',
        sortOrder: (r['sort_order'] as int?) ?? 0,
        phone: r['phone'] as String?,
        type: r['type'] as String?,
      );
      nodesById[id] = node;
    }

    for (final n in nodesById.values) {
      if (n.parentId != null) {
        nodesById[n.parentId]?.children.add(n);
      }
    }
    for (final n in nodesById.values) {
      n.children.sort((a, b) {
        final c = a.sortOrder.compareTo(b.sortOrder);
        if (c != 0) return c;
        return a.nameEn.compareTo(b.nameEn);
      });
    }

    final divisions = <BdDivision>[];
    final districts = <BdDistrict>[];
    final hotlines = <BdHotline>[];
    final hospitalsByDistrictId = <String, List<BdHospital>>{};

    for (final n in nodesById.values) {
      switch (n.kind) {
        case 'division':
          divisions.add(BdDivision(id: n.id, nameBn: n.nameBn, nameEn: n.nameEn));
          break;
        case 'district':
          final upazilas = n.children
              .where((c) => c.kind == 'upazila')
              .map((c) => BdUpazila(id: c.id, nameBn: c.nameBn, nameEn: c.nameEn))
              .toList();
          districts.add(BdDistrict(
            id: n.id,
            nameBn: n.nameBn,
            nameEn: n.nameEn,
            divisionId: n.parentId ?? '',
            upazilas: upazilas,
          ));
          break;
        case 'hotline':
          hotlines.add(_hotlineFromNode(n));
          break;
      }
    }

    for (final r in geoRows) {
      final distId = r['district_id'] as String? ?? '';
      final h = BdHospital(
        nameBn: (r['name_bn'] ?? '') as String,
        nameEn: (r['name_en'] ?? '') as String,
        districtId: distId,
        addressBn: (r['address_bn'] ?? '') as String,
        addressEn: (r['address_en'] ?? '') as String,
        phone: (r['phone'] ?? '') as String,
        lat: ((r['lat'] ?? 0) as num).toDouble(),
        lng: ((r['lng'] ?? 0) as num).toDouble(),
        type: (r['type'] ?? '') as String,
      );
      hospitalsByDistrictId.putIfAbsent(distId, () => []).add(h);
    }
    final hospitals = hospitalsByDistrictId.values.expand((e) => e).toList();

    divisions.sort((a, b) => a.nameEn.compareTo(b.nameEn));
    districts.sort((a, b) => a.nameEn.compareTo(b.nameEn));

    return BdEmergencyData(
      divisions: divisions,
      districts: districts,
      hotlines: hotlines,
      hospitals: hospitals,
    );
  }

  static BdHotline _hotlineFromNode(_Node n) {
    return BdHotline(
      nameBn: n.nameBn,
      nameEn: n.nameEn,
      number: n.phone ?? '',
      type: n.type ?? n.slug.replaceFirst('hotline__', ''),
    );
  }
}

class _Node {
  final String id;
  final String kind;
  final String? parentId;
  final String nameBn;
  final String nameEn;
  final String slug;
  final int sortOrder;
  final String? phone;
  final String? type;
  final List<_Node> children = [];

  _Node({
    required this.id,
    required this.kind,
    required this.parentId,
    required this.nameBn,
    required this.nameEn,
    required this.slug,
    required this.sortOrder,
    this.phone,
    this.type,
  });
}
