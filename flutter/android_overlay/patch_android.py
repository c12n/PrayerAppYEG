#!/usr/bin/env python3
"""Patch the flutter-create generated Android scaffold for Prayer YEG:
- app label -> "Prayer YEG"
- register the four home-screen widget providers in AndroidManifest.xml
- v3.0.0: the ongoing-notification tick receiver and the nine
  activity-alias alternate launcher icons
- minSdk -> 26 (the widget providers use java.time)
- v1.5 notification engine: POST_NOTIFICATIONS, SCHEDULE_EXACT_ALARM
  and RECEIVE_BOOT_COMPLETED permissions, plus the alarm and boot
  receivers from Alerts.kt
- v1.8 settings backup: allowBackup + fullBackupContent +
  dataExtractionRules pointing at the overlay's res/xml rules, so
  the Flutter settings restore after a reinstall

Usage: patch_android.py <path-to-generated-android-dir>
"""
import base64
import pathlib
import re
import sys

PERMISSIONS = """    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
"""

RECEIVERS = """        <receiver
            android:name=".NextPrayerWidgetProvider"
            android:exported="false"
            android:label="Prayer YEG - Next Prayer">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data
                android:name="android.appwidget.provider"
                android:resource="@xml/widget_next_info" />
        </receiver>
        <receiver
            android:name=".ScheduleWidgetProvider"
            android:exported="false"
            android:label="Prayer YEG - Schedule">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data
                android:name="android.appwidget.provider"
                android:resource="@xml/widget_schedule_info" />
        </receiver>
        <receiver
            android:name=".LargeScheduleWidgetProvider"
            android:exported="false"
            android:label="Prayer YEG - Full Schedule">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data
                android:name="android.appwidget.provider"
                android:resource="@xml/widget_large_info" />
        </receiver>
        <receiver
            android:name=".ContinueListeningWidgetProvider"
            android:exported="false"
            android:label="Prayer YEG - Continue Listening">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data
                android:name="android.appwidget.provider"
                android:resource="@xml/widget_listening_info" />
        </receiver>
        <receiver
            android:name=".AdhanAlarmReceiver"
            android:exported="false">
        </receiver>
        <service
            android:name=".SilenceNextTileService"
            android:exported="true"
            android:icon="@mipmap/ic_launcher"
            android:label="Silence Next Alert"
            android:permission="android.permission.BIND_QUICK_SETTINGS_TILE">
            <intent-filter>
                <action android:name="android.service.quicksettings.action.QS_TILE" />
            </intent-filter>
        </service>
        <service
            android:name=".PrayerCarService"
            android:exported="true"
            android:label="Prayer YEG">
            <intent-filter>
                <action android:name="androidx.car.app.CarAppService" />
                <category android:name="androidx.car.app.category.POI" />
            </intent-filter>
            <meta-data
                android:name="androidx.car.app.minCarApiLevel"
                android:value="1" />
        </service>
        <receiver
            android:name=".BootReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
            </intent-filter>
        </receiver>
        <receiver
            android:name=".OngoingTickReceiver"
            android:exported="false">
        </receiver>
        <!-- Alternate launcher icons (v3.0.0): one disabled alias
             per iOS alternate icon; MainActivity switches them
             through the alrashid/icons channel. -->
        <activity-alias
            android:name=".MainActivityMidnight"
            android:enabled="false"
            android:exported="true"
            android:icon="@mipmap/ic_launcher_midnight"
            android:label="Prayer YEG"
            android:targetActivity=".MainActivity">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity-alias>
        <activity-alias
            android:name=".MainActivityDesert"
            android:enabled="false"
            android:exported="true"
            android:icon="@mipmap/ic_launcher_desert"
            android:label="Prayer YEG"
            android:targetActivity=".MainActivity">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity-alias>
        <activity-alias
            android:name=".MainActivityRose"
            android:enabled="false"
            android:exported="true"
            android:icon="@mipmap/ic_launcher_rose"
            android:label="Prayer YEG"
            android:targetActivity=".MainActivity">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity-alias>
        <activity-alias
            android:name=".MainActivityRoyal"
            android:enabled="false"
            android:exported="true"
            android:icon="@mipmap/ic_launcher_royal"
            android:label="Prayer YEG"
            android:targetActivity=".MainActivity">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity-alias>
        <activity-alias
            android:name=".MainActivityEmerald"
            android:enabled="false"
            android:exported="true"
            android:icon="@mipmap/ic_launcher_emerald"
            android:label="Prayer YEG"
            android:targetActivity=".MainActivity">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity-alias>
        <activity-alias
            android:name=".MainActivityOcean"
            android:enabled="false"
            android:exported="true"
            android:icon="@mipmap/ic_launcher_ocean"
            android:label="Prayer YEG"
            android:targetActivity=".MainActivity">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity-alias>
        <activity-alias
            android:name=".MainActivityCrimson"
            android:enabled="false"
            android:exported="true"
            android:icon="@mipmap/ic_launcher_crimson"
            android:label="Prayer YEG"
            android:targetActivity=".MainActivity">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity-alias>
        <activity-alias
            android:name=".MainActivityPlum"
            android:enabled="false"
            android:exported="true"
            android:icon="@mipmap/ic_launcher_plum"
            android:label="Prayer YEG"
            android:targetActivity=".MainActivity">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity-alias>
        <activity-alias
            android:name=".MainActivityTeal"
            android:enabled="false"
            android:exported="true"
            android:icon="@mipmap/ic_launcher_teal"
            android:label="Prayer YEG"
            android:targetActivity=".MainActivity">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity-alias>
    </application>"""


def main() -> None:
    android = pathlib.Path(sys.argv[1])

    manifest_path = android / "app/src/main/AndroidManifest.xml"
    text = manifest_path.read_text()
    text, n = re.subn(r'android:label="[^"]*"', 'android:label="Prayer YEG"', text, count=1)
    if n != 1:
        raise SystemExit("could not patch app label in AndroidManifest.xml")
    # Settings backup (v1.8.0): opt the app into Auto Backup with the
    # overlay's rules files (copied into res/xml before this runs).
    if "<application" not in text:
        raise SystemExit("no <application> tag in AndroidManifest.xml")
    text = text.replace(
        "<application",
        '<application android:allowBackup="true"'
        ' android:fullBackupContent="@xml/backup_rules"'
        ' android:dataExtractionRules="@xml/data_extraction_rules"',
        1,
    )
    if "</application>" not in text:
        raise SystemExit("no </application> in AndroidManifest.xml")
    text = text.replace("</application>", RECEIVERS, 1)
    # App Actions / shortcuts (v2.0.0): attach res/xml/shortcuts.xml
    # to MainActivity's <activity> element.
    activity_match = re.search(
        r'(<activity[^>]*android:name="\.MainActivity"[^>]*>)(.*?)(</activity>)',
        text, re.DOTALL)
    if not activity_match:
        raise SystemExit("could not find MainActivity in AndroidManifest.xml")
    text = (text[:activity_match.start()]
            + activity_match.group(1)
            + '\n            <meta-data android:name="android.app.shortcuts"'
              ' android:resource="@xml/shortcuts" />'
            + activity_match.group(2)
            + activity_match.group(3)
            + text[activity_match.end():])
    # Notification permissions go right after the <manifest ...> tag.
    match = re.search(r"<manifest\b[^>]*>", text)
    if not match:
        raise SystemExit("no <manifest> tag in AndroidManifest.xml")
    text = text[:match.end()] + "\n" + PERMISSIONS + text[match.end():]
    manifest_path.write_text(text)

    gradle_path = android / "app/build.gradle.kts"
    gradle = gradle_path.read_text()
    if "minSdk = flutter.minSdkVersion" in gradle:
        gradle = gradle.replace("minSdk = flutter.minSdkVersion", "minSdk = 26")
    elif "minSdk" not in gradle:
        raise SystemExit("no minSdk line found in build.gradle.kts")
    # v2.3.0: applicationId is com.c12n.prayerappAndroid. Only the
    # install identity changes — the namespace and the Kotlin
    # package stay com.c12n.alrashidwidget.
    gradle, n = re.subn(
        r'applicationId\s*=\s*"[^"]*"',
        'applicationId = "com.c12n.prayerappAndroid"',
        gradle, count=1)
    if n != 1:
        raise SystemExit("could not patch applicationId in build.gradle.kts")
    # v2.0.0: Android Auto (androidx.car.app) + Google sign-in for
    # the Drive settings backup (play-services-auth).
    if "androidx.car.app" not in gradle:
        deps = (
            "\ndependencies {\n"
            '    implementation("androidx.car.app:app:1.7.0")\n'
            '    implementation("com.google.android.gms:play-services-auth:21.2.0")\n'
            "}\n"
        )
        gradle = gradle.rstrip() + "\n" + deps
    gradle_path.write_text(gradle)

    # Bundled adhan sounds (v3.0.0): the WAVs live in the repo
    # base64-encoded under android_overlay/raw_b64 (the repo tooling
    # moves text only); decode them into res/raw next to keep.xml.
    overlay = android.parent / "android_overlay"
    b64_dir = overlay / "raw_b64"
    raw_dir = android / "app/src/main/res/raw"
    raw_dir.mkdir(parents=True, exist_ok=True)
    decoded = []
    if b64_dir.is_dir():
        for b64_file in sorted(b64_dir.glob("*.wav.b64")):
            target = raw_dir / b64_file.name[: -len(".b64")]
            target.write_bytes(base64.b64decode(b64_file.read_text()))
            decoded.append(target.name)

    print("patched AndroidManifest.xml (label + widget receivers + alert receivers + QS tile + CarAppService + shortcuts + notification permissions) and build.gradle.kts (minSdk 26 + car app + play-services-auth); decoded raw sounds:", ", ".join(decoded))


if __name__ == "__main__":
    main()
