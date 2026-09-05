package com.example.diabeticsmeal

import io.flutter.embedding.android.FlutterFragmentActivity

/**
 * flutter_local_notifications 17+ requires `FlutterFragmentActivity` so
 * the `ScheduledNotificationReceiver` / `ActionBroadcastReceiver` can
 * be instantiated by the OS on Android 12+. With plain `FlutterActivity`
 * the receivers can fail to attach and scheduled (`zonedSchedule`)
 * notifications silently never post. The user reported "test works,
 * real reminders don't" — this was the root cause.
 */
class MainActivity : FlutterFragmentActivity()
