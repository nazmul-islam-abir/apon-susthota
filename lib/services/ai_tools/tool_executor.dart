/// Dispatch layer between AI tool calls and the existing Supabase
/// RPCs. The executor is called twice per tool — once with
/// `dryRun: true` to build the human-readable description, then
/// again with `dryRun: false` after the user confirms.
///
/// Successful writes emit an audit row via
/// [SupabaseService.logAiChatAction] and bump the matching
/// [AppEvents] topic so the domain screen re-fetches.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/medicine.dart';
import '../app_events.dart';
import '../supabase_service.dart';
import 'groq_tool_call.dart';
import 'tool_registry.dart';

class ToolExecution {
  ToolExecution({
    required this.toolName,
    required this.description,
    required this.requiresConfirmation,
    required this.toolArgs,
    required this.inverseArgs,
    this.auditId,
    this.toolResult,
    this.errorMessage,
  });

  final String toolName;
  final String description;
  final bool requiresConfirmation;
  final Map<String, dynamic> toolArgs;
  final Map<String, dynamic> inverseArgs;

  /// Set when the executor actually wrote to Supabase. Undo reads
  /// the audit row to find the inverse.
  final String? auditId;

  /// Data returned by a read tool — serialised as the
  /// `tool` message we send back to the model.
  final Object? toolResult;

  /// Non-null when the RPC threw.
  final String? errorMessage;

  bool get ok => errorMessage == null;

  /// JSON for the `tool` message we send back to the model. Falls
  /// back to a serialised error if the RPC threw.
  String toToolMessageJson() {
    if (!ok) {
      return jsonEncode({'ok': false, 'error': errorMessage});
    }
    if (toolResult == null) {
      return jsonEncode({'ok': true});
    }
    try {
      return jsonEncode(toolResult);
    } catch (_) {
      return jsonEncode({'ok': true, 'serialised': toolResult.toString()});
    }
  }
}

class AiToolExecutor {
  AiToolExecutor._();

  /// Build a human-readable Bangla description for a tool call
  /// WITHOUT executing it. Used by the confirmation card.
  static Future<String> describe({
    required AiTool tool,
    required Map<String, dynamic> args,
  }) async {
    switch (tool.name) {
      case 'create_medicine':
        final name = args['name_bn'] as String? ?? 'নামহীন ওষুধ';
        final dose = args['dose_amount'];
        final unit = args['dose_unit'] ?? 'unit';
        final times = _formatTimes(args['schedule']);
        return '$name যোগ করব ($dose $unit, $times)';

      case 'update_medicine':
        final fields = <String>[];
        if (args.containsKey('dose_amount')) {
          fields.add('ডোজ → ${args['dose_amount']}');
        }
        if (args.containsKey('meal_relation')) {
          fields.add('সময়-সম্পর্ক → ${args['meal_relation']}');
        }
        if (args.containsKey('schedule')) {
          fields.add('সময়সূচী → ${_formatTimes(args['schedule'])}');
        }
        if (args.containsKey('notes')) fields.add('নোট → ${args['notes']}');
        if (args.containsKey('is_active')) {
          fields.add(args['is_active'] == false ? 'নিষ্ক্রিয়' : 'সক্রিয়');
        }
        return 'ওষুধ আপডেট করব (${fields.join(", ")})';

      case 'delete_medicine':
        return 'ওষুধ মুছে ফেলব';

      case 'mark_dose':
        final status = args['status'] as String? ?? 'taken';
        final time = args['scheduled_time'] as String? ?? '?';
        final bn = {'taken': 'নিয়েছি', 'skipped': 'স্কিপ', 'missed': 'মিস'};
        return '$time-এর ডোজ "${bn[status] ?? status}" হিসেবে চিহ্নিত করব';

      case 'swap_meal_with_alternative':
        final slot = args['slot'] as String? ?? '?';
        final name = args['food_name_bn'] as String? ?? 'বিকল্প খাবার';
        return '$slot স্লটে "$name" বসাব';

      case 'log_meal_intake':
        final slot = args['slot'] as String? ?? '?';
        final name = args['food_name_bn'] as String? ?? 'খাবার';
        final state = args['state'] as String? ?? 'eaten';
        final bn = {'eaten': 'খেয়েছো', 'skipped': 'স্কিপ', 'off_plan': 'অফ-প্ল্যান'};
        return '$slot স্লটে "$name" "${bn[state] ?? state}" হিসেবে লগ করব';

      case 'start_workout_session':
        return 'আজকের ব্যায়াম সেশন শুরু করব';

      case 'finish_workout_session_item':
        return 'ব্যায়াম আইটেম সম্পন্ন হিসেবে চিহ্নিত করব';

      case 'finish_workout_session':
        return 'ব্যায়াম সেশন শেষ করব';

      case 'log_water_event':
        final l = args['liters'] as num?;
        return 'পানি লগ করব (${l?.toStringAsFixed(2) ?? '?'} L)';

      case 'upsert_daily_metric':
        final field = args['field'] as String? ?? 'metric';
        final value = args['value'];
        final bn = {
          'water_liters': '$value L পানি',
          'heart_rate_bpm': 'হার্ট-রেট $value bpm',
          'steps': '$value স্টেপস',
        };
        return 'আজকের ${bn[field] ?? '$field = $value'} আপডেট করব';

      default:
        return tool.description;
    }
  }

  /// Execute the tool call. Returns a [ToolExecution] with the
  /// audit id (when the RPC ran) or the error message.
  static Future<ToolExecution> execute({
    required AiTool tool,
    required GroqToolCall call,
    required Map<String, dynamic> args,
    String? messageId,
    String? threadId,
  }) async {
    // Normalise numeric types — Groq sometimes sends ints as
    // doubles, sometimes as strings. Coerce here so downstream RPCs
    // don't trip on a String in a `numeric` parameter.
    final normalised = _coerceNumbers(args);

    try {
      switch (tool.name) {
        case 'list_medicines':
          final list = await SupabaseService.listMedicines();
          return ToolExecution(
            toolName: tool.name,
            description: 'ওষুধের তালিকা দেখাচ্ছি',
            requiresConfirmation: false,
            toolArgs: normalised,
            inverseArgs: const {},
            toolResult: list
                .map((m) => {
                      'id': m.id,
                      'name_bn': m.nameBn,
                      'name_en': m.nameEn,
                      'form': m.form,
                      'strength': m.strength,
                      'dose_amount': m.doseAmount,
                      'dose_unit': m.doseUnit,
                      'meal_relation': m.mealRelation,
                      'is_active': m.isActive,
                      'notes': m.notes,
                    })
                .toList(growable: false),
          );

        case 'get_medicine_doses':
          final dateStr = normalised['date'] as String?;
          final d = dateStr != null
              ? DateTime.tryParse(dateStr) ?? DateTime.now()
              : DateTime.now();
          final doses = await SupabaseService.getMedicineDosesForDate(d);
          return ToolExecution(
            toolName: tool.name,
            description: tool.description,
            requiresConfirmation: false,
            toolArgs: normalised,
            inverseArgs: const {},
            toolResult: doses
                .map((d) => {
                      'medicine_id': d.medicineId,
                      'name': d.nameBn,
                      'time': d.scheduledTime,
                      'status': d.status,
                    })
                .toList(growable: false),
          );

        case 'get_medicine_adherence':
          final days = (normalised['days'] as num?)?.toInt() ?? 7;
          final adh = await SupabaseService.getMedicineAdherence(days: days);
          return ToolExecution(
            toolName: tool.name,
            description: tool.description,
            requiresConfirmation: false,
            toolArgs: normalised,
            inverseArgs: const {},
            toolResult: {
              'total_doses': adh.totalDoses,
              'taken': adh.taken,
              'skipped': adh.skipped,
              'missed': adh.missed,
              'taken_pct': adh.takenPct,
              'current_streak_days': adh.currentStreakDays,
              'window_days': adh.windowDays,
            },
          );

        case 'get_user_meal_plan_for_date':
          final dateStr = normalised['date'] as String?;
          final d = dateStr != null
              ? DateTime.tryParse(dateStr) ?? DateTime.now()
              : DateTime.now();
          final plan = await SupabaseService.getUserDayPlan(d);
          return ToolExecution(
            toolName: tool.name,
            description: tool.description,
            requiresConfirmation: false,
            toolArgs: normalised,
            inverseArgs: const {},
            toolResult: plan
                .map((p) => {
                      'id': p.id,
                      'slot': p.slot,
                      'scheduled_time': p.scheduledTime,
                      'food_id': p.foodId,
                      'custom_food_name': p.customFoodName,
                      'portion_label': p.portionLabel,
                      'notes': p.notes,
                    })
                .toList(growable: false),
          );

        case 'get_today_workout':
          final day = await SupabaseService.getTodayWorkout();
          return ToolExecution(
            toolName: tool.name,
            description: tool.description,
            requiresConfirmation: false,
            toolArgs: normalised,
            inverseArgs: const {},
            // Wrap the workout descriptor in a single-key map. The
            // runtime shape is implementation-defined; the model
            // can ask follow-ups against this blob if needed.
            toolResult: {'workout': day.toString()},
          );

        case 'get_water_analytics':
          final days = (normalised['days'] as num?)?.toInt() ?? 7;
          final w = await SupabaseService.getWaterAnalytics(days: days);
          return ToolExecution(
            toolName: tool.name,
            description: tool.description,
            requiresConfirmation: false,
            toolArgs: normalised,
            inverseArgs: const {},
            toolResult: {'days': days, 'summary': w.toString()},
          );

        // ── WRITE TOOLS ────────────────────────────────────────

        case 'create_medicine':
          final id = await SupabaseService.createMedicine(
            nameBn: normalised['name_bn'] as String? ?? '',
            nameEn: normalised['name_en'] as String?,
            form: normalised['form'] as String? ?? 'tablet',
            strength: normalised['strength'] as String?,
            doseAmount: (normalised['dose_amount'] as num?)?.toDouble() ?? 1,
            doseUnit: normalised['dose_unit'] as String? ?? 'unit',
            mealRelation: normalised['meal_relation'] as String? ?? 'any',
            schedule: _slotsFromArgs(normalised['schedule']),
            notes: normalised['notes'] as String?,
          );
          AppEvents.notifyMedicineChanged();
          return await _auditSuccess(
            tool: tool,
            args: normalised,
            description: await describe(tool: tool, args: normalised),
            inverseArgs: {'id': id},
            messageId: messageId,
            threadId: threadId,
          );

        case 'update_medicine':
          final id = normalised['id'] as String;
          final previous = await _fetchMedicineRow(id);
          await SupabaseService.updateMedicine(
            id: id,
            nameBn: normalised['name_bn'] as String?,
            doseAmount: (normalised['dose_amount'] as num?)?.toDouble(),
            mealRelation: normalised['meal_relation'] as String?,
            schedule: normalised.containsKey('schedule')
                ? _slotsFromArgs(normalised['schedule'])
                : null,
            isActive: normalised['is_active'] as bool?,
            notes: normalised['notes'] as String?,
          );
          AppEvents.notifyMedicineChanged();
          return await _auditSuccess(
            tool: tool,
            args: normalised,
            description: await describe(tool: tool, args: normalised),
            inverseArgs: {'id': id, 'previous': previous ?? const {}},
            messageId: messageId,
            threadId: threadId,
          );

        case 'delete_medicine':
          final id = normalised['id'] as String;
          final savedRow = await _fetchMedicineRow(id);
          await SupabaseService.deleteMedicine(id);
          AppEvents.notifyMedicineChanged();
          return await _auditSuccess(
            tool: tool,
            args: normalised,
            description: await describe(tool: tool, args: normalised),
            inverseArgs: {'id': id, 'saved_row': savedRow ?? const {}},
            messageId: messageId,
            threadId: threadId,
          );

        case 'mark_dose':
          final medicineId = normalised['medicine_id'] as String;
          final time = normalised['scheduled_time'] as String;
          final status = normalised['status'] as String? ?? 'taken';
          final dateStr = normalised['date'] as String?;
          final date = dateStr != null
              ? DateTime.parse(dateStr)
              : DateTime.now();
          final previous = await _fetchDoseStatus(
            medicineId: medicineId,
            date: date,
            scheduledTime: time,
          );
          await SupabaseService.markDose(
            medicineId: medicineId,
            date: date,
            scheduledTime: time,
            status: status,
            note: normalised['note'] as String?,
          );
          AppEvents.notifyMedicineChanged();
          return await _auditSuccess(
            tool: tool,
            args: normalised,
            description: await describe(tool: tool, args: normalised),
            inverseArgs: {
              'medicine_id': medicineId,
              'date': _dateOnly(date),
              'scheduled_time': time,
              'previous_status': previous ?? 'missed',
            },
            messageId: messageId,
            threadId: threadId,
          );

        case 'log_water_event':
          final liters = (normalised['liters'] as num).toDouble();
          final row = await SupabaseService.logWaterEvent(liters);
          AppEvents.notifyWaterChanged();
          final logId = row?['id']?.toString();
          return await _auditSuccess(
            tool: tool,
            args: normalised,
            description: await describe(tool: tool, args: normalised),
            inverseArgs: {'id': logId ?? ''},
            messageId: messageId,
            threadId: threadId,
          );

        case 'swap_meal_with_alternative':
          // Re-use record_meal_intake with status='swap'. We let the
          // user log anything they ate as a swap; if `alternative_food_id`
          // is provided we forward it so the macros resolve, otherwise
          // we just stash the Bangla label.
          final foodId = normalised['alternative_food_id'] as String?;
          final id = await SupabaseService.logMeal(
            mealSlot: normalised['slot'] as String? ?? 'morning',
            foodId: foodId,
            foodNameBn: normalised['food_name_bn'] as String? ?? '',
            status: 'swap',
            impact: 'neutral',
            reason: normalised['reason'] as String?,
          );
          AppEvents.notifyMealLogged();
          return await _auditSuccess(
            tool: tool,
            args: normalised,
            description: await describe(tool: tool, args: normalised),
            inverseArgs: {'id': id, 'kind': 'meal_intake'},
            messageId: messageId,
            threadId: threadId,
          );

        case 'log_meal_intake':
          // Map the model-facing enum (`onable_plan` is the swap case)
          // onto the `record_meal_intake` enum (`eaten` / `swap` /
          // `off_plan`).
          final modelState =
              (normalised['state'] as String? ?? 'eaten').toLowerCase();
          final rpcStatus = switch (modelState) {
            'skipped' => 'skipped',
            'off_plan' => 'off_plan',
            _ => 'eaten',
          };
          // Sensible default impact if the model forgets — `off_plan`
          // defaults to `neutral` so the dashboard doesn't punish the
          // user for eating "muri makha" without flagging it.
          final rpcImpact =
              normalised['impact'] as String? ??
                  (modelState == 'off_plan' ? 'neutral' : 'good');
          final id = await SupabaseService.logMeal(
            mealSlot: normalised['slot'] as String? ?? 'morning',
            foodId: normalised['food_id'] as String?,
            foodNameBn: normalised['food_name_bn'] as String? ?? '',
            status: rpcStatus,
            impact: rpcImpact,
            reason: normalised['reason'] as String?,
            notes: normalised['notes'] as String?,
          );
          AppEvents.notifyMealLogged();
          return await _auditSuccess(
            tool: tool,
            args: normalised,
            description: await describe(tool: tool, args: normalised),
            inverseArgs: {'id': id, 'kind': 'meal_intake'},
            messageId: messageId,
            threadId: threadId,
          );

        case 'start_workout_session':
          final dayIndex = (normalised['day_index'] as num?)?.toInt() ?? 1;
          final sessionId =
              await SupabaseService.startWorkoutSession(dayIndex: dayIndex);
          AppEvents.notifyWorkoutChanged();
          return await _auditSuccess(
            tool: tool,
            args: normalised,
            description: await describe(tool: tool, args: normalised),
            inverseArgs: {'session_id': sessionId},
            messageId: messageId,
            threadId: threadId,
          );

        case 'finish_workout_session_item':
          await SupabaseService.finishWorkoutSessionItem(
            sessionId: normalised['session_id'] as String?,
            workoutId: normalised['workout_id'] as String?,
            durationSeconds:
                (normalised['duration_seconds'] as num?)?.toInt() ?? 0,
            completed: normalised['completed'] as bool? ?? true,
          );
          AppEvents.notifyWorkoutChanged();
          return await _auditSuccess(
            tool: tool,
            args: normalised,
            description: await describe(tool: tool, args: normalised),
            inverseArgs: const {'kind': 'workout_item'},
            messageId: messageId,
            threadId: threadId,
          );

        case 'finish_workout_session':
          final sessionId = normalised['session_id'] as String;
          await SupabaseService.finishWorkoutSession(sessionId: sessionId);
          AppEvents.notifyWorkoutChanged();
          return await _auditSuccess(
            tool: tool,
            args: normalised,
            description: await describe(tool: tool, args: normalised),
            inverseArgs: {'session_id': sessionId, 'kind': 'workout_session'},
            messageId: messageId,
            threadId: threadId,
          );

        case 'upsert_daily_metric':
          final field = normalised['field'] as String;
          final value = (normalised['value'] as num).toDouble();
          final row = await SupabaseService.client.rpc(
            'upsert_daily_metric',
            params: {'p_field': field, 'p_value': value},
          );
          AppEvents.notifyProfileChanged();
          return await _auditSuccess(
            tool: tool,
            args: normalised,
            description: await describe(tool: tool, args: normalised),
            inverseArgs: {
              'field': field,
              'previous': (row is Map && row[field] != null)
                  ? row[field]
                  : null,
              'kind': 'daily_metric',
            },
            messageId: messageId,
            threadId: threadId,
          );

        default:
          return ToolExecution(
            toolName: tool.name,
            description: 'অজানা টুল: ${tool.name}',
            requiresConfirmation: tool.writeMutating,
            toolArgs: normalised,
            inverseArgs: const {},
            errorMessage: 'unknown_tool',
          );
      }
    } catch (e, st) {
      debugPrint('⚠️ [AiToolExecutor] ${tool.name} failed: $e');
      debugPrint('$st');
      return ToolExecution(
        toolName: tool.name,
        description: await describe(tool: tool, args: normalised),
        requiresConfirmation: tool.writeMutating,
        toolArgs: normalised,
        inverseArgs: const {},
        errorMessage: e.toString(),
      );
    }
  }

  // ── Internal helpers ──────────────────────────────────────────

  static Future<ToolExecution> _auditSuccess({
    required AiTool tool,
    required Map<String, dynamic> args,
    required String description,
    required Map<String, dynamic> inverseArgs,
    String? messageId,
    String? threadId,
  }) async {
    final auditId = await SupabaseService.logAiChatAction(
      toolName: tool.name,
      toolArgs: args,
      inverseArgs: inverseArgs,
      description: description,
      messageId: messageId,
      threadId: threadId,
    );
    return ToolExecution(
      toolName: tool.name,
      description: description,
      requiresConfirmation: tool.writeMutating,
      toolArgs: args,
      inverseArgs: inverseArgs,
      auditId: auditId,
      errorMessage: null,
    );
  }

  static String _formatTimes(dynamic raw) {
    if (raw is! List) return '?';
    final times = <String>[];
    for (final entry in raw) {
      if (entry is Map && entry['time'] is String) {
        times.add(entry['time'] as String);
      }
    }
    return times.isEmpty ? '?' : times.join(', ');
  }

  static List<MedicineScheduleSlot> _slotsFromArgs(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) {
          final t = m['time']?.toString() ?? '';
          if (t.isEmpty) return null;
          // Default to morning bucket; the server's
          // `classify_time_bucket` will overwrite this when it
          // re-derives it from `time`.
          return MedicineScheduleSlot(time: t, bucket: TimeBucket.morning);
        })
        .whereType<MedicineScheduleSlot>()
        .toList(growable: false);
  }

  /// Coerce stringified numerics and fix-up common schema typos
  /// before they reach Postgres.
  static Map<String, dynamic> _coerceNumbers(Map<String, dynamic> args) {
    final out = <String, dynamic>{};
    args.forEach((k, v) {
      if (v is String) {
        final asNum = num.tryParse(v);
        if (asNum != null && (v.contains('.') || k.endsWith('_amount') ||
            k == 'liters' || k == 'weight_kg' || k == 'steps' ||
            k == 'systolic_mmhg' || k == 'diastolic_mmhg' ||
            k == 'duration_seconds' || k == 'day_index' || k == 'days')) {
          out[k] = asNum;
          return;
        }
      }
      out[k] = v;
    });
    return out;
  }

  static Future<Map<String, dynamic>?> _fetchMedicineRow(String id) async {
    try {
      final list = await SupabaseService.listMedicines();
      for (final m in list) {
        if (m.id == id) {
          return {
            'id': m.id,
            'name_bn': m.nameBn,
            'name_en': m.nameEn,
            'form': m.form,
            'strength': m.strength,
            'dose_amount': m.doseAmount,
            'dose_unit': m.doseUnit,
            'meal_relation': m.mealRelation,
            'is_active': m.isActive,
            'notes': m.notes,
          };
        }
      }
    } catch (e) {
      debugPrint('⚠️ [AiToolExecutor] fetchMedicineRow failed: $e');
    }
    return null;
  }

  static Future<String?> _fetchDoseStatus({
    required String medicineId,
    required DateTime date,
    required String scheduledTime,
  }) async {
    try {
      final doses = await SupabaseService.getMedicineDosesForDate(date);
      for (final d in doses) {
        if (d.medicineId == medicineId &&
            d.scheduledTime == scheduledTime) {
          return d.status;
        }
      }
    } catch (e) {
      debugPrint('⚠️ [AiToolExecutor] fetchDoseStatus failed: $e');
    }
    return null;
  }

  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}