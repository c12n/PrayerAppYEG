#!/usr/bin/env python3
"""Patch the flutter-create generated Android scaffold for Al Rashid Prayer:
- app label -> "Al Rashid Prayer"
- register the three home-screen widget providers in AndroidManifest.xml
- minSdk -> 26 (the widget providers use java.time)

Usage: patch_android.py <path-to-generated-android-dir>
"""
import pathlib
import re
import sys

RECEIVERS = """        <receiver
            android:name=".NextPrayerWidgetProvider"
            android:exported="false"
            android:label="Al Rashid - Next Prayer">
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
            android:label="Al Rashid - Schedule">
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
            android:label="Al Rashid - Full Schedule">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data
                android:name="android.appwidget.provider"
                android:resource="@xml/widget_large_info" />
        </receiver>
    </application>"""


def main() -> None:
    android = pathlib.Path(sys.argv[1])

    manifest_path = android / "app/src/main/AndroidManifest.xml"
    text = manifest_path.read_text()
    text, n = re.subn(r'android:label="[^"]*"', 'android:label="Al Rashid Prayer"', text, count=1)
    if n != 1:
        raise SystemExit("could not patch app label in AndroidManifest.xml")
    if "</application>" not in text:
        raise SystemExit("no </application> in AndroidManifest.xml")
    text = text.replace("</application>", RECEIVERS, 1)
    manifest_path.write_text(text)

    gradle_path = android / "app/build.gradle.kts"
    gradle = gradle_path.read_text()
    if "minSdk = flutter.minSdkVersion" in gradle:
        gradle = gradle.replace("minSdk = flutter.minSdkVersion", "minSdk = 26")
    elif "minSdk" not in gradle:
        raise SystemExit("no minSdk line found in build.gradle.kts")
    gradle_path.write_text(gradle)

    print("patched AndroidManifest.xml (label + 3 widget receivers) and build.gradle.kts (minSdk 26)")


if __name__ == "__main__":
    main()
