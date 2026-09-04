import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'groq_router.dart';

class AiMedicineDetails {
  final String strength;
  final String form;
  final String doseAmount;
  final String doseUnit;
  final String mealRelation;
  final String notes;

  AiMedicineDetails({
    required this.strength,
    required this.form,
    required this.doseAmount,
    required this.doseUnit,
    required this.mealRelation,
    required this.notes,
  });

  factory AiMedicineDetails.fromJson(Map<String, dynamic> json) {
    return AiMedicineDetails(
      strength: json['strength']?.toString() ?? '',
      form: json['form']?.toString() ?? 'tablet',
      doseAmount: json['dose_amount']?.toString() ?? '1',
      doseUnit: json['dose_unit']?.toString() ?? '',
      mealRelation: json['meal_relation']?.toString() ?? 'with_food',
      notes: json['notes']?.toString() ?? '',
    );
  }
}

class AiMedicineService {
  AiMedicineService._();

  static Future<AiMedicineDetails?> getDetails({
    required String medicineName,
  }) async {
    if (!GroqRouter.isConfigured) return null;

    final systemPrompt = '''
তুমি একজন অভিজ্ঞ ফার্মাসিস্ট। ব্যবহারকারীর দেওয়া ওষুধের নাম দেখে তার সাধারণ স্ট্রেংথ (strength), ফর্ম (form), ডোজ এবং কখন খেতে হয় (meal_relation) সে বিষয়ে তথ্য দাও।
তোমার উত্তর অবশ্যই একটি বৈধ JSON হতে হবে এবং অন্য কোনো কথা থাকা চলবে না।

JSON ফরম্যাট: {
  "strength": "যেমন: ৫০০ মি.গ্রা.",
  "form": "tablet | capsule | syrup | injection | insulin",
  "dose_amount": "ইংরেজি সংখ্যা মাত্র (যেমন: 1, 0.5, 2)",
  "dose_unit": "যেমন: টি, চামচ, ইউনিট",
  "meal_relation": "before_food | with_food | after_food",
  "notes": "সংক্ষিপ্ত বর্ণনা ও সতর্কতা বাংলায়"
}

গুরুত্বপূর্ণ: 'dose_amount' অবশ্যই শুধু সংখ্যা হতে হবে (1, 2 ইত্যাদি), কোনো লেখা থাকা চলবে না।

ইনপুট: নাম="$medicineName"
আউটপুট:
''';

    try {
      final result = await GroqRouter.instance.send(
        messages: [
          const GroqMessage('system', 'তুমি শুধুমাত্র JSON রিটার্ন করবে। কোনো ভূমিকা বা বাড়তি কথা বলবে না।'),
          GroqMessage('user', systemPrompt),
        ],
      );

      final cleaned = result.text.trim();
      final jsonStart = cleaned.indexOf('{');
      final jsonEnd = cleaned.lastIndexOf('}');
      if (jsonStart == -1 || jsonEnd == -1) return null;
      
      final jsonStr = cleaned.substring(jsonStart, jsonEnd + 1);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      return AiMedicineDetails.fromJson(data);
    } catch (e) {
      debugPrint('⚠️ [AiMedicineService] Error: $e');
      return null;
    }
  }
}
