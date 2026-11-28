# Notifications

SafeSpend sends reminders **from the phone itself** (local notifications). They arrive when the app is closed and need no server, no Firebase Cloud Messaging and no n8n.

| Notification | When |
| --- | --- |
| Daily reminder | Every day at the time you choose (default 9 pm). Skipped on a day you have already logged spending; on the same day it says how much you spent. |
| Bills and expected income | `remind days` before the due date (set on each bill), and on the due date, at the "due-date reminder" time (default 9 am). Repeating bills are planned for their next dates too. |
| Debts and loans | 3 days before, on the due date, then once a day for 3 days while overdue. |
| Budget alerts | Shown immediately when a category reaches 90% of its limit, and when it goes over. Each is shown once per budget. The first time a budget is seen, existing levels are recorded silently so old data does not trigger a burst of alerts. |

Everything is recalculated a moment after any change (paying a bill, editing a date, changing a setting) and when the app returns to the front, so a paid bill never leaves a stale reminder. At most 60 reminders are scheduled at a time (iOS allows 64); opening the app refills the list. Tapping a notification opens the matching tab (Voice, Bills, Debts or Dashboard).

Where the code is: `lib/notifications/` (`reminder_planner.dart` decides what to send and is unit-tested; `notification_service.dart` talks to the phone; `notification_coordinator.dart` keeps them in step with the data) and `lib/widgets/notification_settings_card.dart` (Settings → Reminders and alerts).

Web, Windows and Linux builds do not send reminders (the Settings card says so); due items still show in the Bills tab.

## One-time Android setup

The `android/` folder is created by `flutter create`, so these edits are made once in your copy. The package needs the permissions, two receivers and Java desugaring.

1. `android/app/src/main/AndroidManifest.xml`: put these **above** `<application ...>`:

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.VIBRATE"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
```

and these **inside** `<application ...>`, next to the existing `<activity>`:

```xml
<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
    <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED"/>
        <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
        <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
        <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
    </intent-filter>
</receiver>
```

2. `android/app/build.gradle.kts` (newer projects) — inside `android { compileOptions { ... } }` set desugaring, and add the dependency:

```kotlin
android {
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
}
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

If your file is `build.gradle` (Groovy): `coreLibraryDesugaringEnabled true` inside `compileOptions`, and `coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'` in `dependencies`.

3. `flutter pub get`, then stop the app completely and run it again (a hot reload is not enough after native changes). If the build asks for a higher `compileSdk`, set `compileSdk = 35` (or `flutter.compileSdkVersion` on a recent Flutter).

iOS needs no edits: the permission prompt appears on first use.

## How to test

1. Run the app on an Android phone or emulator (Android 13+ shows an "Allow notifications" prompt the first time you open the app; tap Allow).
2. **Settings → Reminders and alerts → Send a test now.** A notification should appear immediately. If not, the permission is off or the setup above is incomplete.
3. **Test in 15 seconds**, then lock the screen or close the app. It should arrive on its own. If it arrives a few minutes late, tap "Allow" on the "exact alarms" row.
4. **Daily reminder:** set its time to 2 minutes from now, wait.
5. **Bills:** add a bill due tomorrow with "remind 1 day" (or due today at a time after the due-date hour; set that hour to 2 minutes from now). The Settings card shows "N reminders scheduled. Next: …".
6. **Budget alert:** with a budget set, add expenses until a category passes 90%, then 100%. Alerts appear once each. (The sample data in Settings cannot trigger alerts the first time a budget is seen; add one more expense afterwards.)
7. Tap a notification: the app opens on the matching tab.

If nothing arrives on some phones (Xiaomi, Oppo, Huawei, Samsung power saving), turn off battery optimization for SafeSpend and allow "autostart"; these makers block scheduled alarms for apps that are not exempted.
