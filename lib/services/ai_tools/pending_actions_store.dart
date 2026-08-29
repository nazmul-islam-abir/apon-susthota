/// In-process pub/sub for AI-proposed write actions awaiting user
/// confirmation. The chat screen renders a card per pending action
/// and mutates the entry on করুন / বাতিল / Undo.
///
/// One store per app instance — same singleton pattern as
/// [AppEvents]. The map is keyed by the `id` Groq assigned the
/// tool call (e.g. "call_xyz123"), so a single chat turn can hold
/// several pending actions simultaneously.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'groq_tool_call.dart';

enum PendingActionStatus { awaiting, executing, succeeded, failed, undone, cancelled }

class PendingAction {
  PendingAction({
    required this.call,
    required this.toolName,
    required this.toolArgs,
    required this.description,
    required this.createdAt,
    this.auditId,
    this.status = PendingActionStatus.awaiting,
    this.errorMessage,
  });

  /// Original `GroqToolCall` so the UI can reference its server id.
  final GroqToolCall call;

  final String toolName;
  final Map<String, dynamic> toolArgs;

  /// Bangla summary line shown to the user ("মেটফরমিন ৫০০ mg যোগ …").
  final String description;

  final DateTime createdAt;

  /// `null` until the executor returns the audit row id. Once set,
  /// the summary card can offer Undo.
  String? auditId;

  /// Captured by the executor at write time. Used by [ActionInverse]
  /// to roll the change back when the user taps Undo.
  Map<String, dynamic> inverseArgs = const {};

  PendingActionStatus status;
  String? errorMessage;

  /// Seconds remaining before the undo window closes. The store
  /// ticks the UI every second via [_UndoTicker].
  int undoSecondsRemaining = 60;

  Map<String, dynamic> toJson() => {
        'tool': toolName,
        'args': toolArgs,
        'description': description,
        'status': status.name,
        'audit_id': auditId,
      };
}

class PendingActionsStore {
  PendingActionsStore._();
  static final PendingActionsStore instance = PendingActionsStore._();

  /// The single source of truth — every screen reads from here.
  final ValueNotifier<Map<String, PendingAction>> actions =
      ValueNotifier<Map<String, PendingAction>>(<String, PendingAction>{});

  Timer? _ticker;

  void add(PendingAction action) {
    final next = Map<String, PendingAction>.from(actions.value);
    next[action.call.id] = action;
    actions.value = next;
    _ensureTicker();
  }

  void update(String callId, PendingAction Function(PendingAction) edit) {
    final current = actions.value[callId];
    if (current == null) return;
    final next = Map<String, PendingAction>.from(actions.value);
    next[callId] = edit(current);
    actions.value = next;
  }

  void remove(String callId) {
    if (!actions.value.containsKey(callId)) return;
    final next = Map<String, PendingAction>.from(actions.value);
    next.remove(callId);
    actions.value = next;
    _maybeStopTicker();
  }

  void clear() {
    actions.value = const <String, PendingAction>{};
    _maybeStopTicker();
  }

  void _ensureTicker() {
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      final map = actions.value;
      var touched = false;
      final next = <String, PendingAction>{};
      map.forEach((id, a) {
        if (a.status == PendingActionStatus.succeeded &&
            a.auditId != null &&
            a.undoSecondsRemaining > 0) {
          a.undoSecondsRemaining -= 1;
          if (a.undoSecondsRemaining <= 0) {
            // Window expired — flip status but keep in the map so
            // the summary card can show "Undo (closed)".
            a.status = PendingActionStatus.cancelled;
          }
          touched = true;
        }
        next[id] = a;
      });
      if (touched) {
        actions.value = Map<String, PendingAction>.from(next);
      }
    });
  }

  void _maybeStopTicker() {
    final hasLive = actions.value.values.any(
      (a) =>
          a.status == PendingActionStatus.succeeded &&
          a.auditId != null &&
          a.undoSecondsRemaining > 0,
    );
    if (!hasLive) {
      _ticker?.cancel();
      _ticker = null;
    }
  }
}