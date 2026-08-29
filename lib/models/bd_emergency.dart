import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class BdDivision {
  final String id;
  final String nameBn;
  final String nameEn;

  const BdDivision({required this.id, required this.nameBn, required this.nameEn});

  factory BdDivision.fromJson(Map<String, dynamic> json) {
    return BdDivision(
      id: (json['id'] ?? '') as String,
      nameBn: (json['name_bn'] ?? '') as String,
      nameEn: (json['name_en'] ?? '') as String,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name_bn': nameBn, 'name_en': nameEn};
}

class BdUpazila {
  final String id;
  final String nameBn;
  final String nameEn;

  const BdUpazila({required this.id, required this.nameBn, required this.nameEn});

  factory BdUpazila.fromJson(Map<String, dynamic> json) {
    return BdUpazila(
      id: (json['id'] ?? '') as String,
      nameBn: (json['name_bn'] ?? '') as String,
      nameEn: (json['name_en'] ?? '') as String,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name_bn': nameBn, 'name_en': nameEn};
}

class BdDistrict {
  final String id;
  final String nameBn;
  final String nameEn;
  final String divisionId;
  final List<BdUpazila> upazilas;

  const BdDistrict({
    required this.id,
    required this.nameBn,
    required this.nameEn,
    required this.divisionId,
    required this.upazilas,
  });

  factory BdDistrict.fromJson(Map<String, dynamic> json) {
    final ups = (json['upazilas'] as List?) ?? const [];
    return BdDistrict(
      id: (json['id'] ?? '') as String,
      nameBn: (json['name_bn'] ?? '') as String,
      nameEn: (json['name_en'] ?? '') as String,
      divisionId: (json['division_id'] ?? '') as String,
      upazilas: ups
          .where((e) => e is Map)
          .map((e) => BdUpazila.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name_bn': nameBn,
        'name_en': nameEn,
        'division_id': divisionId,
        'upazilas': upazilas.map((u) => u.toJson()).toList(),
      };
}

class BdHotline {
  final String nameBn;
  final String nameEn;
  final String number;
  final String type;

  const BdHotline({
    required this.nameBn,
    required this.nameEn,
    required this.number,
    required this.type,
  });

  factory BdHotline.fromJson(Map<String, dynamic> json) {
    return BdHotline(
      nameBn: (json['name_bn'] ?? '') as String,
      nameEn: (json['name_en'] ?? '') as String,
      number: (json['number'] ?? '') as String,
      type: (json['type'] ?? '') as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'name_bn': nameBn,
        'name_en': nameEn,
        'number': number,
        'type': type,
      };
}

class BdHospital {
  final String nameBn;
  final String nameEn;
  final String districtId;
  final String addressBn;
  final String addressEn;
  final String phone;
  final double lat;
  final double lng;
  final String type;

  double? distanceKm;

  BdHospital({
    required this.nameBn,
    required this.nameEn,
    required this.districtId,
    required this.addressBn,
    required this.addressEn,
    required this.phone,
    required this.lat,
    required this.lng,
    required this.type,
    this.distanceKm,
  });

  factory BdHospital.fromJson(Map<String, dynamic> json) {
    return BdHospital(
      nameBn: (json['name_bn'] ?? '') as String,
      nameEn: (json['name_en'] ?? '') as String,
      districtId: (json['district_id'] ?? '') as String,
      addressBn: (json['address_bn'] ?? '') as String,
      addressEn: (json['address_en'] ?? '') as String,
      phone: (json['phone'] ?? '') as String,
      lat: ((json['lat'] ?? 0) as num).toDouble(),
      lng: ((json['lng'] ?? 0) as num).toDouble(),
      type: (json['type'] ?? '') as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'name_bn': nameBn,
        'name_en': nameEn,
        'district_id': districtId,
        'address_bn': addressBn,
        'address_en': addressEn,
        'phone': phone,
        'lat': lat,
        'lng': lng,
        'type': type,
      };
}

class BdEmergencyData {
  final List<BdDivision> divisions;
  final List<BdDistrict> districts;
  final List<BdHotline> hotlines;
  final List<BdHospital> hospitals;

  const BdEmergencyData({
    required this.divisions,
    required this.districts,
    required this.hotlines,
    required this.hospitals,
  });

  factory BdEmergencyData.empty() => const BdEmergencyData(
        divisions: [],
        districts: [],
        hotlines: [],
        hospitals: [],
      );

  static Future<BdEmergencyData> load() async {
    final raw = await rootBundle.loadString('assets/data/bd_geo.json');
    final map = json.decode(raw) as Map<String, dynamic>;
    final divs = (map['divisions'] as List? ?? [])
        .where((e) => e is Map)
        .map((e) => BdDivision.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final dists = (map['districts'] as List? ?? [])
        .where((e) => e is Map)
        .map((e) => BdDistrict.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final hots = (map['national_hotlines'] as List? ?? [])
        .where((e) => e is Map)
        .map((e) => BdHotline.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final hosps = (map['hospitals'] as List? ?? [])
        .where((e) => e is Map)
        .map((e) => BdHospital.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return BdEmergencyData(
      divisions: divs,
      districts: dists,
      hotlines: hots,
      hospitals: hosps,
    );
  }

  List<BdDistrict> districtsOf(String divisionId) =>
      districts.where((d) => d.divisionId == divisionId).toList();

  BdDistrict? districtById(String id) {
    for (final d in districts) {
      if (d.id == id) return d;
    }
    return null;
  }

  BdDivision? divisionById(String id) {
    for (final d in divisions) {
      if (d.id == id) return d;
    }
    return null;
  }

  List<BdHospital> hospitalsIn(String districtId) =>
      hospitals.where((h) => h.districtId == districtId).toList();
}
