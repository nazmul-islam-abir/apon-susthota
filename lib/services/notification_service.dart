import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import 'supabase_service.dart';

/// Wire-format row returned by the `list_active_notifications` RPC.
///
/// Mirrors the columns the SQL function returns (see
/// `supabasesql/39_notifications.sql`). The `readAt`, `dismissedAt`,
/// `deliveredAt` timestamps are joined from
/// `notification_deliveries` so the UI can render read/unread state
/// without a second round-trip.
@immutable
class AppNotification {
  final String id;
  final String title;
  final String? shortMessage;
  final String? longMessage;
  final String? imageUrl;
  final String? actionUrl;
  final String actionLabel;
  final String category; // announcement|greeting|update|tip|alert
  final int priority;
  final DateTime startsAt;
  final DateTime? expiresAt;
  final String? targetVersion;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime? readAt;
  final DateTime? dismissedAt;
  final DateTime? deliveredAt;

  const AppNotification({
    required this.id,
    required this.title,
    required this.shortMessage,
    required this.longMessage,
    required this.imageUrl,
    required this.actionUrl,
    required this.actionLabel,
    required this.category,
    required this.priority,
    required this.startsAt,
    required this.expiresAt,
    required this.targetVersion,
    required this.tags,
    required this.createdAt,
    required this.readAt,
    required this.dismissedAt,
    required this.deliveredAt,
  });

  bool get isUnread => readAt == null && dismissedAt == null;

  bool get isUpdate => category == 'update';
  bool get isGreeting => category == 'greeting';
  bool get isAlert => category == 'alert';
  bool get isTip => category == 'tip';

  factory AppNotification.fromJson(Map<String, dynamic> j) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString());
    }

    return AppNotification(
      id: j['id']?.toString() ?? '',
      title: (j['title'] ?? '').toString(),
      shortMessage: j['short_message']?.toString(),
      longMessage: j['long_message']?.toString(),
      imageUrl: j['image_url']?.toString(),
      actionUrl: j['action_url']?.toString(),
      actionLabel: (j['action_label'] ?? 'Open').toString(),
      category: (j['category'] ?? 'announcement').toString(),
      priority: (j['priority'] is num)
          ? (j['priority'] as num).toInt()
          : int.tryParse('${j['priority']}') ?? 3,
      startsAt: parseDate(j['starts_at']) ?? DateTime.now(),
      expiresAt: parseDate(j['expires_at']),
      targetVersion: j['target_version']?.toString(),
      tags: (j['tags'] is List)
          ? (j['tags'] as List).map((e) => e.toString()).toList()
          : const [],
      createdAt: parseDate(j['created_at']) ?? DateTime.now(),
      readAt: parseDate(j['read_at']),
      dismissedAt: parseDate(j['dismissed_at']),
      deliveredAt: parseDate(j['delivered_at']),
    );
  }
}

/// Service that talks to the notifications tables in Supabase.
///
/// Mirrors the style of `BlogService`: static methods, in-memory cache
/// for the unread badge, lazy re-fetch. Callers can also invoke the
/// raw RPC names directly if they want to bypass the cache.
class NotificationService {
  NotificationService._();

  static const Duration _cacheTtl = Duration(seconds: 30);

  static List<AppNotification> _cache = const [];
  static DateTime? _cachedAt;
  static int _cachedUnread = 0;

  /// Drop the in-memory cache (e.g. after the user signs out, or after
  /// the bell icon page writes a read/dismiss).
  static void invalidateCache() {
    _cache = const [];
    _cachedAt = null;
    _cachedUnread = 0;
  }

  /// Fetch the active notifications for the current user. Returns the
  /// cached list when fresh; otherwise hits Supabase.
  static Future<List<AppNotification>> load({bool force = false}) async {
    if (!force &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < _cacheTtl &&
        _cache.isNotEmpty == false /* allow empty list cache */) {
      return _cache;
    }
    if (!force && _cachedAt != null && _cache.isNotEmpty) {
      final age = DateTime.now().difference(_cachedAt!);
      if (age < _cacheTtl) return _cache;
    }

    final rows = await SupabaseService.fetchActiveNotifications();
    final list = rows
        .whereType<Map<String, dynamic>>()
        .map(AppNotification.fromJson)
        .toList(growable: false);
    _cache = List.unmodifiable(list);
    _cachedAt = DateTime.now();
    _cachedUnread = list.where((n) => n.isUnread).length;
    return _cache;
  }

  /// Quick read of the cached unread count. Returns 0 if we have
  /// never fetched. Call [refreshUnread] if you need an authoritative
  /// number from the server.
  static int get cachedUnread => _cachedUnread;

  /// Force a server-side recount of unread notifications.
  static Future<int> refreshUnread() async {
    final n = await SupabaseService.unreadNotificationCount();
    _cachedUnread = n;
    return n;
  }

  /// Mark a notification as read. Updates the local cache so the
  /// unread badge drops immediately.
  static Future<void> markRead(String id) async {
    await SupabaseService.markNotificationRead(id);
    _cache = _cache
        .map((n) => n.id == id && n.readAt == null
            ? AppNotification(
                id: n.id,
                title: n.title,
                shortMessage: n.shortMessage,
                longMessage: n.longMessage,
                imageUrl: n.imageUrl,
                actionUrl: n.actionUrl,
                actionLabel: n.actionLabel,
                category: n.category,
                priority: n.priority,
                startsAt: n.startsAt,
                expiresAt: n.expiresAt,
                targetVersion: n.targetVersion,
                tags: n.tags,
                createdAt: n.createdAt,
                readAt: DateTime.now(),
                dismissedAt: n.dismissedAt,
                deliveredAt: n.deliveredAt,
              )
            : n)
        .toList(growable: false);
    _cachedUnread =
        _cache.where((n) => n.isUnread).length;
  }

  /// Dismiss a notification. The server hides it on subsequent loads.
  static Future<void> dismiss(String id) async {
    await SupabaseService.markNotificationDismissed(id);
    _cache = _cache.where((n) => n.id != id).toList(growable: false);
    _cachedUnread =
        _cache.where((n) => n.isUnread).length;
  }

  /// Tap handler used by the notification page. Decides between:
  ///   1. Internal deep link (`/dashboard`, `/blog/xyz`) — push named
  ///      route via the supplied navigator key.
  ///   2. External http(s) URL — open with the system browser.
  ///   3. Null URL — no-op (just mark as read).
  ///
  /// Returns true if it handled the action, false otherwise.
  static Future<bool> handleAction(
    AppNotification n, {
    GlobalKey<NavigatorState>? navigatorKey,
  }) async {
    await markRead(n.id);
    final url = n.actionUrl;
    if (url == null || url.isEmpty) return false;

    // Internal deep link — starts with a slash and is not an http(s).
    final isInternal = url.startsWith('/');
    if (isInternal) {
      final nav = navigatorKey?.currentState;
      if (nav != null) {
        nav.pushNamedAndRemoveUntil(url, (route) => route.isFirst);
        return true;
      }
      return false;
    }

    // External URL — validate and launch.
    final uri = Uri.tryParse(url);
    if (uri == null) {
      debugPrint('⚠️ [NotificationService] bad URL: $url');
      return false;
    }
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    }
    debugPrint('⚠️ [NotificationService] cannot launch: $uri');
    return false;
  }
}