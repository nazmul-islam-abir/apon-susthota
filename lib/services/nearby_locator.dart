import 'dart:async';
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import '../models/bd_emergency.dart';

class NearbyLocator {
  Future<bool> ensurePermission() async {
    final service = await Geolocator.isLocationServiceEnabled();
    if (!service) return false;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.whileInUse || perm == LocationPermission.always;
  }

  Future<Position?> currentPosition({Duration timeout = const Duration(seconds: 8)}) async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      ).timeout(timeout, onTimeout: () => throw TimeoutException('GPS timeout'));
    } catch (_) {
      return null;
    }
  }

  double haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = (math.sin(dLat / 2) * math.sin(dLat / 2)) +
        (math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2));
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  double _rad(double deg) => deg * math.pi / 180.0;

  Future<List<BdHospital>> nearest(List<BdHospital> all, {int limit = 5}) async {
    final granted = await ensurePermission();
    if (!granted) return const <BdHospital>[];

    final pos = await currentPosition();
    if (pos == null) return const <BdHospital>[];

    final annotated = all.map((h) {
      final km = haversineKm(pos.latitude, pos.longitude, h.lat, h.lng);
      h.distanceKm = km;
      return h;
    }).toList();
    annotated.sort((a, b) => (a.distanceKm ?? 0).compareTo(b.distanceKm ?? 0));
    return annotated.take(limit).toList();
  }
}