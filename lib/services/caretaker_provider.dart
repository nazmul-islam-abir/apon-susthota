/// In-memory caretaker-app state, broadcast via `provider`.
///
/// Holds:
///   * the patient list (active only)
///   * outstanding pending requests sent by the caretaker
///   * which patient (uid) is currently selected for drilldown
///   * a one-shot "last incoming event" used by the inbox to flash
///     a snackbar when a patient accepts/declines a request
///
/// Realtime subscriptions are owned here — `attachRealtime` opens the
/// postgres_changes channel and `dispose` tears it down. The provider
/// is intentionally tiny because the caretaker app is read-only:
/// every interactive screen reads from this state and triggers
/// explicit refreshes via `refresh*()` rather than optimistic writes.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/caretaker_link.dart';
import '../models/caretaker_patient_summary.dart';
import 'supabase_service.dart';

/// Listens to `public.caretaker_patient_links` mutations touching the
/// signed-in user and republishes a slim list of patient summaries.
/// Used by both shells — caretaker holds the active list, patients
/// hold the pending-inbox version (signalled by [variant]).
enum CaretakerProviderVariant { caretaker, patient }

/// One-shot event used by the UI to flash a friendly snackbar when a
/// pending request transitions (accept / decline) without the user
/// having tapped refresh.
class CaretakerLinkEvent {
  CaretakerLinkEvent({
    required this.kind,
    required this.otherName,
    required this.at,
  });
  final String kind; // 'accepted' | 'declined' | 'sent'
  final String otherName;
  final DateTime at;
}

class CaretakerProvider extends ChangeNotifier {
  /// Distinguishes the two views of the same `caretaker_patient_links`
  /// table. The variant controls which side we're showing:
  ///   * caretaker → active + pending-outgoing list
  ///   * patient   → pending-incoming inbox
  final CaretakerProviderVariant variant;

  CaretakerProvider({this.variant = CaretakerProviderVariant.caretaker}) {
    refresh();
  }

  // ----- Patient-list state (caretaker variant only) -----
  final List<CaretakerPatientSummary> _patients = [];
  List<CaretakerPatientSummary> get patients =>
      List.unmodifiable(_patients);

  bool _loadingPatients = false;
  bool get loadingPatients => _loadingPatients;

  Object? _patientError;
  Object? get patientError => _patientError;

  // ----- Pending state -----
  final List<CaretakerLink> _pending = [];
  List<CaretakerLink> get pending => List.unmodifiable(_pending);

  bool _loadingPending = false;
  bool get loadingPending => _loadingPending;

  Object? _pendingError;
  Object? get pendingError => _pendingError;

  // ----- Active caretakers (patient variant only) -----
  final List<CaretakerLink> _activeCaretakers = [];
  List<CaretakerLink> get activeCaretakers =>
      List.unmodifiable(_activeCaretakers);

  // ----- Selection -----
  String? _selectedPatientUserId;
  String? get selectedPatientUserId => _selectedPatientUserId;

  /// Resolve the currently selected patient summary, or null.
  CaretakerPatientSummary? get selectedPatient {
    final id = _selectedPatientUserId;
    if (id == null) return null;
    for (final p in _patients) {
      if (p.patientUserId == id) return p;
    }
    return null;
  }

  /// Quick membership test for the People-search result rows.
  /// Returns 'active', 'pending', or null.
  String? linkStateFor(String? otherUserId) {
    if (otherUserId == null) return null;
    for (final p in _patients) {
      if (p.patientUserId == otherUserId) return 'active';
    }
    for (final p in _pending) {
      if (p.patientUserId == otherUserId) return 'pending';
    }
    return null;
  }

  /// Most-recent realtime transition event (consumed once by the UI).
  CaretakerLinkEvent? _lastEvent;
  CaretakerLinkEvent? consumeLastEvent() {
    final e = _lastEvent;
    _lastEvent = null;
    return e;
  }

  // ----- Realtime wiring -----
  RealtimeChannel? _channel;
  StreamSubscription<AuthState>? _authSub;

  /// Public entry-point. Call from `initState` after the user signs
  /// in. Idempotent — re-calling tears down + reopens.
  void attachRealtime() {
    _authSub?.cancel();
    _authSub = SupabaseService.client.auth.onAuthStateChange.listen((s) {
      final signedIn = s.event == AuthChangeEvent.signedIn;
      final signedOut = s.event == AuthChangeEvent.signedOut;
      if (signedIn) {
        _openChannel();
        refresh();
      } else if (signedOut) {
        _closeChannel();
        _reset();
      }
    });
    if (SupabaseService.currentUser != null) {
      _openChannel();
      refresh();
    }
  }

  void _openChannel() {
    _closeChannel();
    _channel = SupabaseService.subscribeToMyLinkEvents(onChange: refresh);
  }

  void _closeChannel() {
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      try {
        SupabaseService.client.removeChannel(ch);
      } catch (_) {/* ignore */}
    }
  }

  void _reset() {
    _patients.clear();
    _pending.clear();
    _activeCaretakers.clear();
    _selectedPatientUserId = null;
    _lastEvent = null;
    notifyListeners();
  }

  /// Pull both lists from the server. Re-entrancy-safe: a refresh
  /// triggered while one is in flight is coalesced and re-issued
  /// on completion.
  Future<void> refresh() async {
    if (variant == CaretakerProviderVariant.caretaker) {
      await _refreshCaretaker();
    } else {
      await _refreshPatient();
    }
  }

  Future<void> _refreshCaretaker() async {
    final prevPendingIds = _pending.map((p) => p.id).toSet();
    final prevActiveIds = _patients.map((p) => p.patientUserId).toSet();

    await _refreshPatients();
    await _refreshPending();

    // Detect "pending moved to active" so the inbox can flash a
    // green snackbar without polling AND so the today/detail tabs
    // auto-populate with the freshly-accepted patient (otherwise the
    // caretaker has to manually re-open the patients tab and tap the
    // new row — by which point they think the system is broken).
    final newActive = _patients
        .map((p) => p.patientUserId)
        .where((id) => !prevActiveIds.contains(id))
        .toSet();
    final pendingShrunk = _pending.length < prevPendingIds.length;
    if (newActive.isNotEmpty || pendingShrunk) {
      // Either a new active link appeared, or a pending one disappeared
      // (accepted → moved out of pending). We don't always know the
      // patient name from the patient's perspective; for the caretaker
      // side the UI can call `consumeLastEvent()` and use the name of
      // any patient in the new active set.
      for (final p in _patients) {
        if (newActive.contains(p.patientUserId)) {
          _lastEvent = CaretakerLinkEvent(
            kind: 'accepted',
            otherName: p.fullName.isEmpty ? 'রোগী' : p.fullName,
            at: DateTime.now(),
          );
          // Auto-select the freshly-accepted patient so the
          // caretaker's "আজ" tab + patient detail screens
          // immediately load the patient's data (meals, medicine,
          // water, analysis, workout) without the user having to
          // manually re-open the patients tab. This is the
          // missing UX hook that previously made "patient accepted"
          // look like "nothing happened on the caretaker side".
          if (_selectedPatientUserId == null ||
              !_patients.any(
                (existing) =>
                    existing.patientUserId == _selectedPatientUserId,
              )) {
            _selectedPatientUserId = p.patientUserId;
          }
          break;
        }
      }
    }
  }

  Future<void> _refreshPatient() async {
    await _refreshPatientPending();
    await _refreshPatientActive();
  }

  Future<void> _refreshPatients() async {
    if (_loadingPatients) return;
    _loadingPatients = true;
    _patientError = null;
    notifyListeners();
    try {
      final fresh = await SupabaseService.listCaretakerPatients();
      _patients
        ..clear()
        ..addAll(fresh);
    } catch (e) {
      _patientError = e;
    } finally {
      _loadingPatients = false;
      notifyListeners();
    }
  }

  Future<void> _refreshPending() async {
    if (_loadingPending) return;
    _loadingPending = true;
    _pendingError = null;
    notifyListeners();
    try {
      final fresh = await SupabaseService.listCaretakerPendingRequests();
      _pending
        ..clear()
        ..addAll(fresh);
    } catch (e) {
      _pendingError = e;
    } finally {
      _loadingPending = false;
      notifyListeners();
    }
  }

  Future<void> _refreshPatientPending() async {
    if (_loadingPending) return;
    _loadingPending = true;
    _pendingError = null;
    notifyListeners();
    try {
      // `getInboxPendingLinks` already remaps the SQL `link_id` column
      // back to `id` and returns `List<CaretakerLink>`, so we no longer
      // need the per-row `fromSupabaseRow` step (that path silently
      // produced rows with `id == null` and made accept/reject a no-op).
      final fresh = await SupabaseService.getInboxPendingLinks();
      _pending
        ..clear()
        ..addAll(fresh);
    } catch (e) {
      _pendingError = e;
    } finally {
      _loadingPending = false;
      notifyListeners();
    }
  }

  Future<void> _refreshPatientActive() async {
    _loadingPending = true;
    notifyListeners();
    try {
      // Same remap as above — the service already returns a usable
      // `List<CaretakerLink>` with non-null `id`s, which is required
      // for the revoke RPC.
      final fresh = await SupabaseService.getInboxActiveCaretakers();
      _activeCaretakers
        ..clear()
        ..addAll(fresh);
    } catch (_) {
      // Best-effort; the patient can still see the pending inbox.
    } finally {
      _loadingPending = false;
      notifyListeners();
    }
  }

  /// Pull-to-refresh entry point for the patient list screen.
  Future<void> refreshPatients() async {
    if (variant == CaretakerProviderVariant.patient) return;
    await _refreshPatients();
  }

  /// Pull-to-refresh entry point for the pending screen / inbox.
  Future<void> refreshPending() async {
    if (variant == CaretakerProviderVariant.caretaker) {
      await _refreshPending();
    } else {
      await _refreshPatientPending();
    }
  }

  // ----- Mutations -----

  /// Caretaker sends a new link request. Returns the freshly-created
  /// row so the caller can show "অপেক্ষমান" immediately.
  Future<CaretakerLink> sendRequest({
    required String patientUserId,
    required String relationship,
    String? note,
  }) async {
    final link = await SupabaseService.sendCaretakerRequest(
      patientUserId: patientUserId,
      relationship: relationship,
      note: note,
    );
    await refresh();
    return link;
  }

  /// Patient accepts/declines. [accept] true → 'active', false →
  /// 'declined'. Server rejects any non-pending row.
  Future<void> respondTo({required String linkId, required bool accept}) async {
    await SupabaseService.respondCaretakerRequest(
      linkId: linkId,
      accept: accept,
    );
    await refresh();
  }

  /// Either side can revoke. Server authorizes based on caller's uid
  /// matching one of the two link columns.
  Future<void> revoke(String linkId) async {
    await SupabaseService.revokeCaretakerLinkAsCaretaker(linkId);
    await refresh();
  }

  /// Caretaker searches by mobile. Thin pass-through to keep UI
  /// screens free of direct service calls.
  Future<List<Map<String, dynamic>>> searchPatientByMobile(String mobile) {
    return SupabaseService.searchPatientByMobile(mobile);
  }

  /// Unified people search pass-through.
  Future<List<Map<String, dynamic>>> searchPeople(String query,
      {int limit = 25}) {
    return SupabaseService.searchPeople(query, limit: limit);
  }

  /// Public-profile pass-through.
  Future<Map<String, dynamic>?> getPublicProfile(String userId) {
    return SupabaseService.getPublicProfile(userId);
  }

  // ----- Selection -----

  void selectPatient(String? uid) {
    if (_selectedPatientUserId == uid) return;
    _selectedPatientUserId = uid;
    notifyListeners();
  }

  @override
  void dispose() {
    _closeChannel();
    _authSub?.cancel();
    super.dispose();
  }
}

/// Shorthand for screens that just want to read the provider once.
extension CaretakerProviderBuildContextX on CaretakerProvider {
  /// Convenience for the caretaker home — total active patient count.
  int get activePatientCount => _patients.length;
}