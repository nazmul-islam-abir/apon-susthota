/// Map common Supabase / Dart errors to short Bangla messages.
///
/// Most auth + realtime errors fall into one of ~12 buckets. The
/// rest get a generic "সংযোগ ব্যর্থ" line. Centralising the mapping
/// here means a future i18n pass only has to swap one file.

library;

class BanglaError {
  BanglaError._();

  /// Returns a short Bangla message suitable for a snackbar or
  /// inline form error.
  static String toBangla(Object? error) {
    final raw = _stringify(error).toLowerCase();

    if (raw.isEmpty) return 'কিছু ভুল হয়েছে। আবার চেষ্টা করুন।';

    // Auth
    if (raw.contains('invalid_credentials') ||
        raw.contains('invalid_grant') ||
        raw.contains('invalid login')) {
      return 'ইমেইল বা পাসওয়ার্ড ভুল আছে।';
    }
    if (raw.contains('email_exists') ||
        raw.contains('user_already_exists') ||
        raw.contains('already registered')) {
      return 'এই ইমেইল দিয়ে আগেই অ্যাকাউন্ট আছে — লগইন করুন।';
    }
    if (raw.contains('weak_password') ||
        raw.contains('password should be') ||
        raw.contains('at least 6')) {
      return 'পাসওয়ার্ড কমপক্ষে ৬ অক্ষরের হতে হবে।';
    }
    if (raw.contains('user_not_found') ||
        raw.contains('email not confirmed')) {
      return 'অ্যাকাউন্ট পাওয়া যায়নি অথবা ইমেইল এখনো নিশ্চিত হয়নি।';
    }
    if (raw.contains('rate_limit') ||
        raw.contains('too many requests') ||
        raw.contains('email rate limit')) {
      return 'অনেক চেষ্টা হয়েছে — কয়েক মিনিট পর আবার চেষ্টা করুন।';
    }

    // Network
    if (raw.contains('failed host lookup') ||
        raw.contains('socketexception') ||
        raw.contains('network is unreachable') ||
        raw.contains('no address associated') ||
        raw.contains('connection refused') ||
        raw.contains('connection failed') ||
        raw.contains('timed out') ||
        raw.contains('timeout')) {
      return 'ইন্টারনেট সংযোগ নেই বা ধীর। ওয়াই-ফাই/মোবাইল ডেটা দেখুন।';
    }

    // Supabase config
    if (raw.contains('your-project-ref') ||
        raw.contains('invalid url') ||
        raw.contains('supabaseurl') ||
        raw.contains('not initialized') ||
        raw.contains('notauthenticated')) {
      return 'Supabase কনফিগারেশন সঠিক নয়। .env ফাইলে URL ও Key যাচাই করুন।';
    }

    // RLS / permission
    if (raw.contains('row-level security') ||
        raw.contains('permission denied') ||
        raw.contains('not authorized') ||
        raw.contains('policy')) {
      return 'এই কাজের অনুমতি আপনার নেই।';
    }

    // Validation
    if (raw.contains('check constraint') ||
        raw.contains('invalid input syntax')) {
      return 'প্রবেশ করা তথ্য সঠিক নয় — যাচাই করে আবার দিন।';
    }

    if (raw.contains('not found')) {
      return 'তথ্য পাওয়া যায়নি।';
    }

    // Last-resort: return the raw text but trimmed for snackbar friendliness.
    return _stringify(error);
  }

  static String _stringify(Object? e) {
    if (e == null) return '';
    try {
      return e.toString();
    } catch (_) {
      return 'unknown';
    }
  }
}
