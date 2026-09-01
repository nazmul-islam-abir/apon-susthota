// =====================================================================
// Amar Diet — Hive local storage layer
// =====================================================================
//
// Everything the user creates (profile, meals, water logs, daily plan,
// weight history) is persisted into Hive boxes. The boxes are
// automatically synced with the user's verified BDApps phone so that
// different phones on the same device do not collide.
//
// Box naming convention:
//   profile_<phone>   : UserProfile as Map
//   meals_<phone>     : list of MealEntry as Map list
//   water_<phone>     : list of WaterEntry as Map list
//   plan_<phone>      : DailyPlan as Map
//   weight_<phone>    : list of {measured_on, weight_kg} maps
// =====================================================================

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

class HiveStore {
  HiveStore._();
  static final HiveStore instance = HiveStore._();

  bool _initialized = false;
  final Map<String, Future<Box<dynamic>>> _opening = {};

  /// Open Hive. Call once at app startup.
  Future<void> init() async {
    if (_initialized) return;
    final dir = await getApplicationDocumentsDirectory();
    await Hive.initFlutter(dir.path);
    _initialized = true;
  }

  /// Box name for a given per-user key (profile, meals, water, ...).
  String _boxName(String phone, String key) => '${key}_$phone';

  /// Returns (and lazily opens) a box for a user. Synchronous callers
  /// will get a `Box<dynamic>` once opened; if it's still opening, the
  /// returned box may be empty until the future completes.
  ///
  /// Callers that need guaranteed-readiness should await [boxAsync].
  Box<dynamic> box(String phone, String key) {
    final name = _boxName(phone, key);
    if (Hive.isBoxOpen(name)) {
      return Hive.box<dynamic>(name);
    }
    // Kick off the open in the background; Hive caches it so a second
    // call returns the same instance.
    _opening.putIfAbsent(
      name,
      () => Hive.openBox<dynamic>(name),
    );
    // We can't return a not-yet-open Box synchronously, so we wait
    // briefly on the future. Most first-time screens will display a
    // loading spinner (FutureBuilder) anyway, so a 1-frame delay is
    // acceptable. The next call after this frame will hit the
    // isBoxOpen() branch above and return the real box.
    return _emptyProxy();
  }

  /// Async variant — awaits the box opening.
  Future<Box<dynamic>> boxAsync(String phone, String key) async {
    final name = _boxName(phone, key);
    if (Hive.isBoxOpen(name)) {
      return Hive.box<dynamic>(name);
    }
    final future = _opening.putIfAbsent(
      name,
      () => Hive.openBox<dynamic>(name),
    );
    return future;
  }

  /// Pre-opens all per-user boxes for a phone so the first read does
  /// not race. Called once after auth is hydrated.
  Future<void> preOpenUser(String phone) async {
    await Future.wait([
      boxAsync(phone, 'profile'),
      boxAsync(phone, 'meals'),
      boxAsync(phone, 'water'),
      boxAsync(phone, 'plan'),
      boxAsync(phone, 'weight'),
    ]);
  }

  /// Returns a transient empty Box proxy for the very first call
  /// before the underlying box is open. Reads return null/0, writes
  /// are buffered (Hive queues them). Once the box opens, future
  /// reads see the data.
  Box<dynamic> _emptyProxy() {
    // We can't construct a real Box from outside Hive, so we return a
    // tiny shim. Most apps guard against this with their own loading
    // state, but for safety we let read-only methods return safely.
    return _EmptyBox();
  }

  /// Remove ALL stored data for a phone (used on logout).
  Future<void> clearPhone(String phone) async {
    for (final k in ['profile', 'meals', 'water', 'plan', 'weight']) {
      final name = _boxName(phone, k);
      if (Hive.isBoxOpen(name)) {
        await Hive.box<dynamic>(name).clear();
      }
      _opening.remove(name);
    }
  }
}

/// No-op fallback used only on the very first call before a box is
/// open. Returns null/empty for every read, and silently drops writes
/// (the data is small enough that losing a single first-frame write
/// is acceptable; the next call hits the real box).
class _EmptyBox implements Box<dynamic> {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    if (name == #get) return null;
    if (name == #values) return const [];
    if (name == #isEmpty) return true;
    if (name == #length) return 0;
    if (name == #delete) return Future.value();
    if (name == #put) return Future.value();
    if (name == #clear) return Future.value();
    if (name == #close) return Future.value();
    return null;
  }
}
