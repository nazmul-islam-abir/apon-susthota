/// Static catalogue of every tool the AI is allowed to call.
///
/// Each tool maps 1:1 to an existing Supabase RPC exposed by
/// `SupabaseService`. [writeMutating] tools require a confirmation
/// card in the UI before they fire; [readOnly] tools execute
/// immediately and their result is fed back to the model as a
/// `tool` message.
///
/// Schemas follow OpenAI's `tools[].function` shape, which Groq
/// accepts byte-for-byte. [toGroqToolsJson] serialises the list to
/// the JSON the router forwards to Groq.
library;

import 'dart:convert';

class AiTool {
  const AiTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.writeMutating,
    required this.appEvent,
  });

  /// Function name — matches the RPC `create_*`/`get_*`/etc.
  final String name;

  /// Bangla one-liner shown on the confirmation card and prepended
  /// to the model so it knows what this tool does. Keep it short and
  /// concrete ("একটি ওষুধ যোগ করুন", not "manage medicines").
  final String description;

  /// JSON-schema-ish object describing the function's parameters.
  /// Used verbatim in the `tools` array sent to Groq.
  final Map<String, dynamic> parameters;

  /// True ⇒ requires a করুন/বাতিল confirmation card before the
  /// executor will dispatch the RPC. Reads are false.
  final bool writeMutating;

  /// Which [AppEvents.notifyXxxChanged] to bump after a successful
  /// write, so the domain screen re-fetches without a manual reload.
  /// One of: `medicine`, `meal`, `workout`, `water`, `profile`.
  /// `null` for read-only tools.
  final String? appEvent;
}

class AiToolRegistry {
  AiToolRegistry._();

  // ── READ TOOLS ────────────────────────────────────────────────

  static const _readMedicines = AiTool(
    name: 'list_medicines',
    description: 'ব্যবহারকারীর সব সক্রিয় ওষুধের তালিকা দেখায় (নাম, ডোজ, সময়সূচী)।',
    parameters: {
      'type': 'object',
      'properties': <String, dynamic>{},
      'additionalProperties': false,
    },
    writeMutating: false,
    appEvent: null,
  );

  static const _readDoses = AiTool(
    name: 'get_medicine_doses',
    description: 'আজকের ওষুধের ডোজ টাইমলাইন দেখায় (কোনোটা নেওয়া হয়েছে কোনোটা বাকি)।',
    parameters: {
      'type': 'object',
      'properties': {
        'date': {
          'type': 'string',
          'format': 'date',
          'description': 'YYYY-MM-DD, ডিফল্ট আজ।',
        },
      },
    },
    writeMutating: false,
    appEvent: null,
  );

  static const _readAdherence = AiTool(
    name: 'get_medicine_adherence',
    description: 'গত ৭ দিনের ওষুধের অ্যাডহেরেন্স সামারি দেখায়।',
    parameters: {
      'type': 'object',
      'properties': {
        'days': {'type': 'integer', 'minimum': 1, 'maximum': 90},
      },
    },
    writeMutating: false,
    appEvent: null,
  );

  static const _readMealPlan = AiTool(
    name: 'get_user_meal_plan_for_date',
    description: 'নির্দিষ্ট দিনের মিল প্ল্যান দেখায় (সকাল/দুপুর/বিকেল/রাত)।',
    parameters: {
      'type': 'object',
      'properties': {
        'date': {'type': 'string', 'format': 'date'},
      },
      'required': ['date'],
    },
    writeMutating: false,
    appEvent: null,
  );

  static const _readWorkout = AiTool(
    name: 'get_today_workout',
    description: 'আজকের ব্যায়াম অ্যাসাইনমেন্ট ও পূর্ববর্তী অবস্থা দেখায়।',
    parameters: {
      'type': 'object',
      'properties': <String, dynamic>{},
    },
    writeMutating: false,
    appEvent: null,
  );

  static const _readWater = AiTool(
    name: 'get_water_analytics',
    description: 'গত ৭ দিনের পানির সামারি দেখায়।',
    parameters: {
      'type': 'object',
      'properties': {'days': {'type': 'integer', 'minimum': 1, 'maximum': 30}},
    },
    writeMutating: false,
    appEvent: null,
  );

  // ── WRITE TOOLS ───────────────────────────────────────────────

  static const _createMedicine = AiTool(
    name: 'create_medicine',
    description: 'নতুন ওষুধ যোগ করে — নাম, ফর্ম, শক্তি, ডোজ, সময়সূচী।',
    parameters: {
      'type': 'object',
      'properties': {
        'name_bn': {
          'type': 'string',
          'description': 'বাংলায় ওষুধের নাম (যেমন "মেটফরমিন")।',
        },
        'name_en': {
          'type': 'string',
          'description': 'ইংরেজি / জেনেরিক নাম (ঐচ্ছিক)।',
        },
        'form': {
          'type': 'string',
          'enum': [
            'tablet',
            'capsule',
            'drop',
            'syrup',
            'injection',
            'inhaler',
            'cream',
            'other',
          ],
        },
        'strength': {'type': 'string', 'description': 'যেমন "500 mg" বা "5 mg/ml"।'},
        'dose_amount': {'type': 'number', 'description': 'প্রতি ডোজের সংখ্যা, যেমন 1 বা 0.5।'},
        'dose_unit': {'type': 'string', 'description': 'unit / mg / ml / ইত্যাদি।'},
        'meal_relation': {
          'type': 'string',
          'enum': ['before_food', 'with_food', 'after_food', 'empty_stomach', 'any'],
        },
        'schedule': {
          'type': 'array',
          'description': 'ডোজের সময়ের তালিকা, প্রতিটি {"time":"HH:mm"}।',
          'items': {
            'type': 'object',
            'properties': {
              'time': {
                'type': 'string',
                'pattern': r'^[0-2][0-9]:[0-5][0-9]$',
              },
            },
            'required': ['time'],
          },
        },
        'notes': {
          'type': 'string',
          'description': 'ডাক্তারের নির্দেশ / সাইড ইফেক্ট।',
        },
      },
      'required': ['name_bn', 'form', 'schedule'],
    },
    writeMutating: true,
    appEvent: 'medicine',
  );

  static const _updateMedicine = AiTool(
    name: 'update_medicine',
    description: 'বিদ্যমান ওষুধের এক বা একাধিক ফিল্ড পরিবর্তন করে।',
    parameters: {
      'type': 'object',
      'properties': {
        'id': {'type': 'string', 'format': 'uuid'},
        'name_bn': {'type': 'string'},
        'dose_amount': {'type': 'number'},
        'meal_relation': {'type': 'string'},
        'schedule': {'type': 'array', 'items': {'type': 'object'}},
        'is_active': {'type': 'boolean'},
        'notes': {'type': 'string'},
      },
      'required': ['id'],
    },
    writeMutating: true,
    appEvent: 'medicine',
  );

  static const _deleteMedicine = AiTool(
    name: 'delete_medicine',
    description: 'ওষুধ মুছে ফেলে (ক্যাসকেডে সব ডোজ লগও মুছে যায়)।',
    parameters: {
      'type': 'object',
      'properties': {'id': {'type': 'string', 'format': 'uuid'}},
      'required': ['id'],
    },
    writeMutating: true,
    appEvent: 'medicine',
  );

  static const _markDose = AiTool(
    name: 'mark_dose',
    description: 'নির্দিষ্ট সময়ের ওষুধ নেওয়া / স্কিপ / মিস হিসেবে চিহ্নিত করে।',
    parameters: {
      'type': 'object',
      'properties': {
        'medicine_id': {'type': 'string', 'format': 'uuid'},
        'date': {'type': 'string', 'format': 'date'},
        'scheduled_time': {
          'type': 'string',
          'pattern': r'^[0-2][0-9]:[0-5][0-9]$',
        },
        'status': {
          'type': 'string',
          'enum': ['taken', 'skipped', 'missed'],
        },
        'note': {'type': 'string'},
      },
      'required': ['medicine_id', 'scheduled_time'],
    },
    writeMutating: true,
    appEvent: 'medicine',
  );

  static const _swapMeal = AiTool(
    name: 'swap_meal_with_alternative',
    description: 'একটি মিল স্লটে বিকল্প খাবার লগ করে (প্ল্যানের খাবার বদলে অন্য কিছু '
        'খেলে)।',
    parameters: {
      'type': 'object',
      'properties': {
        'slot': {
          'type': 'string',
          'enum': ['morning', 'noon', 'afternoon', 'night'],
          'description': 'কোন স্লটে বদলাচ্ছো (সকাল/দুপুর/বিকেল/রাত)।',
        },
        'food_name_bn': {
          'type': 'string',
          'description': 'যে খাবারটা খেয়েছো/খাবে (বাংলায়)।',
        },
        'alternative_food_id': {
          'type': 'string',
          'format': 'uuid',
          'description': 'ঐচ্ছিক: foods টেবিলের আইডি থাকলে ম্যাক্রো সঠিক হবে।',
        },
        'reason': {'type': 'string', 'description': 'কেন বদলাচ্ছো (ঐচ্ছিক)।'},
      },
      'required': ['slot', 'food_name_bn'],
    },
    writeMutating: true,
    appEvent: 'meal',
  );

  static const _logMeal = AiTool(
    name: 'log_meal_intake',
    description: 'একটি মিল খাওয়া / স্কিপ / অফ-প্ল্যান হিসেবে লগ করে। '
        'প্ল্যানের বাইরে কিছু খেলেও (যেমন "মুরি মাখা ১ প্লেট") এটি দিয়ে লগ করো।',
    parameters: {
      'type': 'object',
      'properties': {
        'slot': {
          'type': 'string',
          'enum': ['morning', 'noon', 'afternoon', 'night'],
          'description': 'কোন স্লটে খেয়েছো (সকাল/দুপুর/বিকেল/রাত)।',
        },
        'food_name_bn': {
          'type': 'string',
          'description': 'যে খাবারটা খেয়েছো (বাংলায়)।',
        },
        'food_id': {
          'type': 'string',
          'format': 'uuid',
          'description': 'ঐচ্ছিক: foods টেবিলের আইডি থাকলে ম্যাক্রো সঠিক হবে।',
        },
        'state': {
          'type': 'string',
          'enum': ['eaten', 'skipped', 'off_plan'],
          'description': 'eaten=প্ল্যানমতো খেয়েছো, skipped=স্কিপ, '
              'off_plan=প্ল্যানের বাইরে কিছু খেয়েছো।',
        },
        'impact': {
          'type': 'string',
          'enum': ['good', 'neutral', 'bad'],
          'description': 'ডায়াবেটিক-ক্লাস: good=ভালো, neutral=মোটামুটি, bad=খারাপ।',
        },
        'reason': {'type': 'string', 'description': 'স্কিপ/অফ-প্ল্যান হলে কারণ (ঐচ্ছিক)।'},
        'notes': {'type': 'string', 'description': 'বাড়তি নোট (ঐচ্ছিক)।'},
      },
      'required': ['slot', 'food_name_bn', 'state'],
    },
    writeMutating: true,
    appEvent: 'meal',
  );

  static const _startWorkout = AiTool(
    name: 'start_workout_session',
    description: 'আজকের ব্যায়াম সেশন শুরু করে (ইতোমধ্যে চললে আগেরটা ফেরত দেয়)।',
    parameters: {
      'type': 'object',
      'properties': {
        'day_index': {'type': 'integer', 'minimum': 1, 'maximum': 7},
      },
    },
    writeMutating: true,
    appEvent: 'workout',
  );

  static const _finishWorkoutItem = AiTool(
    name: 'finish_workout_session_item',
    description: 'একটি ব্যায়াম আইটেম "সম্পন্ন" হিসেবে চিহ্নিত করে।',
    parameters: {
      'type': 'object',
      'properties': {
        'session_id': {'type': 'string', 'format': 'uuid'},
        'workout_id': {'type': 'string', 'format': 'uuid'},
        'duration_seconds': {'type': 'integer', 'minimum': 0},
        'completed': {'type': 'boolean'},
      },
      'required': ['duration_seconds', 'completed'],
    },
    writeMutating: true,
    appEvent: 'workout',
  );

  static const _finishWorkout = AiTool(
    name: 'finish_workout_session',
    description: 'পুরো ব্যায়াম সেশন শেষ করে এবং টোটাল রোল আপ করে।',
    parameters: {
      'type': 'object',
      'properties': {'session_id': {'type': 'string', 'format': 'uuid'}},
      'required': ['session_id'],
    },
    writeMutating: true,
    appEvent: 'workout',
  );

  static const _logWater = AiTool(
    name: 'log_water_event',
    description: 'পানির একটি গ্লাস (লিটারে) লগ করে।',
    parameters: {
      'type': 'object',
      'properties': {
        'liters': {
          'type': 'number',
          'minimum': 0.05,
          'maximum': 4.0,
          'description': 'যেমন 0.25 (এক গ্লাস) বা 0.5।',
        },
      },
      'required': ['liters'],
    },
    writeMutating: true,
    appEvent: 'water',
  );

  static const _upsertMetric = AiTool(
    name: 'upsert_daily_metric',
    description: 'আজকের দৈনিক মেট্রিক (পানি / হার্ট-রেট / স্টেপস) যোগ বা আপডেট করে। '
        'একটি call-এ একটি ফিল্ড — একাধিক ফিল্ড দরকার হলে আলাদা call করো।',
    parameters: {
      'type': 'object',
      'properties': {
        'field': {
          'type': 'string',
          'enum': ['water_liters', 'heart_rate_bpm', 'steps'],
          'description': 'কোন ফিল্ড সেট করবে।',
        },
        'value': {
          'type': 'number',
          'description': 'water_liters: 0–20, heart_rate_bpm: 0–230, '
              'steps: 0–200000।',
        },
      },
      'required': ['field', 'value'],
    },
    writeMutating: true,
    appEvent: 'profile',
  );

  /// The full list — what the model sees.
  static const List<AiTool> all = [
    _readMedicines,
    _readDoses,
    _readAdherence,
    _readMealPlan,
    _readWorkout,
    _readWater,
    _createMedicine,
    _updateMedicine,
    _deleteMedicine,
    _markDose,
    _swapMeal,
    _logMeal,
    _startWorkout,
    _finishWorkoutItem,
    _finishWorkout,
    _logWater,
    _upsertMetric,
  ];

  /// Partition for the orchestrator.
  static List<AiTool> get readOnly =>
      all.where((t) => !t.writeMutating).toList(growable: false);
  static List<AiTool> get writeMutating =>
      all.where((t) => t.writeMutating).toList(growable: false);

  /// Lookup by name; null when the model hallucinates a tool name.
  static AiTool? byName(String name) {
    for (final t in all) {
      if (t.name == name) return t;
    }
    return null;
  }

  /// JSON for the Groq request body. Omits the `appEvent` field
  /// (internal-only) and the `writeMutating` flag (gated
  /// server-side by confirmation, not by prompt).
  static List<Map<String, dynamic>> toGroqToolsJson() {
    return all
        .map((t) => {
              'type': 'function',
              'function': {
                'name': t.name,
                'description': t.description,
                'parameters': t.parameters,
              },
            })
        .toList(growable: false);
  }

  /// Pretty JSON for debugging / the "বিস্তারিত দেখুন" disclosure.
  static String prettyArgs(AiTool tool, Map<String, dynamic> args) {
    const enc = JsonEncoder.withIndent('  ');
    return enc.convert({
      'tool': tool.name,
      'args': args,
      'mutating': tool.writeMutating,
    });
  }
}
