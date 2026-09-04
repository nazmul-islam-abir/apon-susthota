/// `PatientDataRealtimeMixin` — caretaker-side auto-refresh.
///
/// Caretaker screens are read-only mirrors of the patient's app. When
/// the patient logs a meal, water dose, medicine, workout, or mood,
/// the linked caretaker wants to see the update without manually
/// pulling the screen down.
///
/// This mixin attaches a per-screen Supabase realtime channel filtered
/// by `patient_user_id = patientUserId`. The SQL setup in
/// `supabasesql/54_caretaker_realtime_subscription.sql` adds the data
/// tables to the `supabase_realtime` publication and grants the
/// caretaker session SELECT access only for rows linked via an active
/// `caretaker_patient_links` row. Whenever a filtered row changes, the
/// screen's [onChange] callback fires.
///
/// Usage in a caretaker screen that already knows which patient to
/// watch (most screens):
/// ```dart
/// class _MyState extends State<...> with PatientDataRealtimeMixin {
///   @override
///   void initState() {
///     super.initState();
///     _future = _load();
///     attachPatientDataRealtime(
///       widget.patient.patientUserId,
///       _refresh,
///     );
///   }
/// }
/// ```
///
/// For screens that read the selected patient from
/// `CaretakerProvider` (e.g. `caretaker_today_tab`), wrap the call in
/// `addPostFrameCallback` so `context` is ready:
///
/// ```dart
/// WidgetsBinding.instance.addPostFrameCallback((_) {
///   final pid = context
///       .read<CaretakerProvider>()
///       .selectedPatientUserId;
///   if (pid != null) attachPatientDataRealtime(pid, _refresh);
/// });
/// ```
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';

mixin PatientDataRealtimeMixin<W extends StatefulWidget> on State<W> {
  RealtimeChannel? _pdChannel;
  StreamSubscription<AuthState>? _pdAuthSub;
  VoidCallback? _pdOnChange;
  String? _pdPatientUserId;

  /// Wire up the realtime subscription. The single binding across all
  /// data tables is filtered server-side by [patientUserId], so a
  /// channel only fires for rows belonging to *that* patient. [onChange]
  /// is called regardless of which table fired.
  ///
  /// Call this from `initState` (or post-frame) with the patient
  /// user-id you want to watch. If the patient changes mid-session
  /// (rare; caretaker switches patients on a today-tab), call
  /// [switchPatientDataRealtime] instead.
  void attachPatientDataRealtime(
    String patientUserId,
    VoidCallback onChange,
  ) {
    _pdPatientUserId = patientUserId;
    _pdOnChange = onChange;
    _pdAuthSub?.cancel();
    _pdAuthSub = SupabaseService.client.auth.onAuthStateChange.listen((s) {
      final signedIn = s.event == AuthChangeEvent.signedIn;
      final signedOut = s.event == AuthChangeEvent.signedOut;
      if (signedIn) {
        _openPatientDataChannel();
      } else if (signedOut) {
        _closePatientDataChannel();
      }
    });
    if (SupabaseService.currentUser != null) {
      _openPatientDataChannel();
    }
  }

  /// Re-target the existing subscription to a different patient. Tears
  /// down the old channel and opens a new one filtered to
  /// [newPatientUserId]. Useful on today-tab when the caretaker
  /// switches the selected patient.
  void switchPatientDataRealtime(String newPatientUserId) {
    if (newPatientUserId == _pdPatientUserId) return;
    _pdPatientUserId = newPatientUserId;
    _closePatientDataChannel();
    _openPatientDataChannel();
  }

  /// Tear down the subscription. The implementing state class must
  /// call this from `dispose()` — see the usage example at the top.
  void disposePatientDataRealtime() {
    _closePatientDataChannel();
    _pdAuthSub?.cancel();
    _pdAuthSub = null;
    _pdOnChange = null;
    _pdPatientUserId = null;
  }

  void _openPatientDataChannel() {
    _closePatientDataChannel();
    final cb = _pdOnChange;
    final pid = _pdPatientUserId;
    if (cb == null || pid == null || pid.isEmpty) return;
    _pdChannel = SupabaseService.subscribeToPatientDataEvents(
      patientUserId: pid,
      onChange: () {
        if (!mounted) return;
        cb();
      },
    );
  }

  void _closePatientDataChannel() {
    final ch = _pdChannel;
    _pdChannel = null;
    if (ch != null) {
      try {
        SupabaseService.client.removeChannel(ch);
      } catch (_) {
        // Channel may already be closed by Supabase on sign-out.
      }
    }
  }
}
