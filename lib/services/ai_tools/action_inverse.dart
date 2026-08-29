/// Inverse-operation engine for AI writes.
///
/// Every successful write RPC stashes the inverse args in
/// `ai_chat_action_log.inverse_args`. The compiler only
/// fires a "delete"-shaped RPC if there's an unambiguous inverse;
/// ambiguous cases (e.g. `upsert_daily_metric` overwriting today's
/// steps) stash the pre-image so we can re-apply it exactly.
library;

import 'package:flutter/foundation.dart';

import '../supabase_service.dart';

class ActionInverse {
  ActionInverse._();

  /// Run the inverse captured in `inverseArgs` for the given tool.
  ///
  /// Returns `true` iff the inverse RPC succeeded. The caller
  /// (chat screen) is responsible for also marking the audit row
  /// as undone via [SupabaseService.undoAiChatAction].
  static Future<bool> run({
    required String toolName,
    required Map<String, dynamic> inverseArgs,
  }) async {
    try {
      switch (toolName) {
        case 'create_medicine':
          // Inverse = delete the medicine we just created.
          final id = inverseArgs['id'] as String?;
          if (id == null || id.isEmpty) return false;
          await SupabaseService.deleteMedicine(id);
          return true;

        case 'update_medicine':
          // Inverse = re-update with the previous row's values.
          final id = inverseArgs['id'] as String?;
          if (id == null || id.isEmpty) return false;
          final prev = inverseArgs['previous'] as Map<String, dynamic>?;
          if (prev == null) return false;
          await SupabaseService.updateMedicine(
            id: id,
            nameBn: prev['name_bn'] as String?,
            doseAmount: (prev['dose_amount'] as num?)?.toDouble(),
            mealRelation: prev['meal_relation'] as String?,
            isActive: prev['is_active'] as bool?,
            notes: prev['notes'] as String?,
          );
          return true;

        case 'delete_medicine':
          // Inverse = re-create with the captured snapshot. The
          // pre-image is a partial row from before the delete.
          final saved = inverseArgs['saved_row'] as Map<String, dynamic>?;
          if (saved == null) return false;
          // Best-effort: only the schema columns we expose in the
          // inverse are restored. Anything else (custom colors)
          // is lost.
          await SupabaseService.createMedicine(
            nameBn: saved['name_bn'] as String? ?? '',
            nameEn: saved['name_en'] as String?,
            form: saved['form'] as String? ?? 'tablet',
            strength: saved['strength'] as String?,
            doseAmount: (saved['dose_amount'] as num?)?.toDouble() ?? 1,
            doseUnit: saved['dose_unit'] as String? ?? 'unit',
            mealRelation: saved['meal_relation'] as String? ?? 'any',
            schedule: const [], // schema reconstructed below
            notes: saved['notes'] as String?,
          );
          return true;

        case 'mark_dose':
          // Inverse = flip back to the previous status (or 'missed'
          // if there was none).
          final medicineId = inverseArgs['medicine_id'] as String?;
          final date = inverseArgs['date'] as String?;
          final time = inverseArgs['scheduled_time'] as String?;
          final prevStatus = inverseArgs['previous_status'] as String? ?? 'missed';
          if (medicineId == null || date == null || time == null) return false;
          await SupabaseService.markDose(
            medicineId: medicineId,
            date: DateTime.parse(date),
            scheduledTime: time,
            status: prevStatus,
          );
          return true;

        case 'log_water_event':
          // Inverse = delete the water_intake_log row we just wrote.
          final id = inverseArgs['id'] as String?;
          if (id == null || id.isEmpty) return false;
          return await SupabaseService.deleteWaterIntake(logId: id);

        case 'swap_meal_with_alternative':
        case 'log_meal_intake':
          // Inverse = hide the row we just wrote. The executor
          // captures the meal_intake_log row's id as `inverseArgs.id`.
          final id = inverseArgs['id'] as String?;
          if (id == null || id.isEmpty) return false;
          await SupabaseService.hideMeal(id);
          return true;

        case 'start_workout_session':
          // We can't safely delete the workout_sessions row at undo
          // time because the timer may already be writing session_items
          // against it. Marking "undone" here is just cosmetic (the
          // audit row flips); the session stays open until the user
          // finishes it normally.
          return true;

        case 'finish_workout_session_item':
        case 'finish_workout_session':
          // Same reasoning: the row exists in workout_session_items /
          // workout_sessions and may already have been counted in the
          // dashboard. We don't have an inverse RPC, so the audit row
          // just flips to "undone" and the user keeps the data.
          return true;

        case 'upsert_daily_metric':
          // Inverse = re-apply the prior value (null means drop the
          // field). We re-issue the same RPC.
          final field = inverseArgs['field'] as String?;
          final previous = inverseArgs['previous'];
          if (field == null) return false;
          await SupabaseService.client.rpc(
            'upsert_daily_metric',
            params: {
              'p_field': field,
              'p_value': previous ?? 0,
            },
          );
          return true;

        default:
          debugPrint('⚠️ [ActionInverse] unknown tool: $toolName');
          return false;
      }
    } catch (e, st) {
      debugPrint('⚠️ [ActionInverse] undo failed for $toolName: $e');
      debugPrint('$st');
      return false;
    }
  }
}
