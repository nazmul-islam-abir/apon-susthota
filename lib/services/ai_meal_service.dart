import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'groq_router.dart';

class AiMealDetails {
  final double kcal;
  final String description;
  final String portion;
  final double carbG;
  final double proteinG;
  final double fatG;

  AiMealDetails({
    required this.kcal,
    required this.description,
    required this.portion,
    required this.carbG,
    required this.proteinG,
    required this.fatG,
  });

  factory AiMealDetails.fromJson(Map<String, dynamic> json) {
    return AiMealDetails(
      kcal: double.tryParse(json['kcal']?.toString() ?? '0') ?? 0,
      carbG: double.tryParse(json['carb_g']?.toString() ?? '0') ?? 0,
      proteinG: double.tryParse(json['protein_g']?.toString() ?? '0') ?? 0,
      fatG: double.tryParse(json['fat_g']?.toString() ?? '0') ?? 0,
      description: json['description']?.toString() ?? '',
      portion: json['portion']?.toString() ?? '',
    );
  }

  String toNotesString() {
    return '$description\n\n[AI_DATA:{"kcal":$kcal,"carb":$carbG,"protein":$proteinG,"fat":$fatG}]';
  }
}

class AiMealService {
  AiMealService._();

  static Future<AiMealDetails?> getDetails({
    required String mealName,
    required String quantity,
  }) async {
    if (!GroqRouter.isConfigured) return null;

    final systemPrompt = '''
তুমি একজন অভিজ্ঞ পুষ্টিবিদ। ব্যবহারকারীর দেওয়া খাবারের নাম এবং পরিমাণ দেখে তার আনুমানিক ক্যালরি (kcal), কার্বোহাইড্রেট, প্রোটিন, ফ্যাট এবং একটি ছোট বর্ণনা (description) বাংলায় দাও।
তোমার উত্তর অবশ্যই একটি বৈধ JSON হতে হবে এবং অন্য কোনো কথা থাকা চলবে না।
JSON ফরম্যাট: {
  "kcal": "সংখ্যা", 
  "carb_g": "সংখ্যা (গ্রামে)", 
  "protein_g": "সংখ্যা (গ্রামে)", 
  "fat_g": "সংখ্যা (গ্রামে)",
  "description": "খাবারের সংক্ষিপ্ত বর্ণনা", 
  "portion": "পরিমাণ"
}

উদাহরণ:
ইনপুট: নাম="ভাত", পরিমাণ="১ কাপ"
আউটপুট: {"kcal": "২০৫", "carb_g": "৪৫", "protein_g": "৪", "fat_g": "০.৪", "description": "১ কাপ সেদ্ধ চালে প্রায় ২০৫ ক্যালরি থাকে। এটি কার্বোহাইড্রেটের প্রধান উৎস।", "portion": "১ কাপ (১৫০ গ্রাম)"}

ইনপুট: নাম="$mealName", পরিমাণ="$quantity"
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
      // Find JSON block if model wrapped it in markdown
      final jsonStart = cleaned.indexOf('{');
      final jsonEnd = cleaned.lastIndexOf('}');
      if (jsonStart == -1 || jsonEnd == -1) return null;
      
      final jsonStr = cleaned.substring(jsonStart, jsonEnd + 1);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      return AiMealDetails.fromJson(data);
    } catch (e) {
      debugPrint('⚠️ [AiMealService] Error: $e');
      return null;
    }
  }
}
