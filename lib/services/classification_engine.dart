import '../models/user_profile.dart';
import 'diet_recommender.dart';
import 'impact_engine.dart' show Classification;

/// Backward-compatible wrapper around the new guidelines-locked
/// [DietRecommender.classify]. New code should call `DietRecommender.classify`
/// directly to access the full DietClassification shape (CKD grade, daily
/// macro targets, allowed tags, Bengali recommendations, etc.).
///
/// Thresholds come from:
///   - ADA 2024 Standards of Medical Care in Diabetes
///   - WHO SEAR Asian BMI cutoffs (2004)
///   - ACC/AHA 2017 Hypertension Guidelines
///   - KDIGO 2024 CKD Guideline
///   - AHA 2024 Heart Disease & Stroke
///   - DASH 2024 Eating Plan
///   - ICMR 2024 Dietary Guidelines for Indians
///
/// A clinical reviewer (dietician / nephrologist / cardiologist) must
/// sign off on any threshold change before production.
class ClassificationEngine {
  static Classification classify(UserProfile p) {
    return DietRecommender.toLegacy(DietRecommender.classify(p));
  }
}
