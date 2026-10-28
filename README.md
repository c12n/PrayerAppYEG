# Al Rashid Prayer Widget

Prayer time widgets for **AlRashid Mosque, Edmonton, Canada** (13070 113 St NW) — a small companion app whose main purpose is its Home Screen and Lock Screen widgets: today's Adhan and Iqamah times, the next prayer, and a live countdown, in a deep-green and gold design.

## Features

- **Medium widget** — the full day at a glance: Fajr, Sunrise, Dhuhr, Asr, Maghrib and Isha with **Adhan and Iqamah columns**, the next prayer highlighted, plus the Hijri date and a live countdown to the next prayer.
- **Small widget** — next prayer, its Adhan and Iqamah times, and a live countdown.
- **Large widget** — the full day plus the mosque address footer; on Fridays the Dhuhr row becomes **Jumu'ah** with the 1:30 PM khutbah time.
- **Lock Screen widgets** — accessory rectangular (next prayer + time + countdown) and accessory circular (next prayer + time).
- **On-device prayer calculation** — times are computed on the phone for the mosque's coordinates (53.591189, -113.515598, America/Edmonton) and **calibrated to AlRashid Mosque's published timetable** (Fajr 18.25°, Maghrib at sunset + 5 min, Asr Shafi / shadow factor 1 with a +2 min adjustment, Isha as a calibrated interval after Maghrib, plus the mosque's summer schedule conventions). Validated against the mosque's published May–December 2026 tables: every prayer lands within about a minute on average. No network connection is needed for the core times.
- **Hijri date** — computed from an embedded Umm al-Qura month table, matching the mosque's official app.
- **Iqamah times** — shown alongside Adhan using Al Rashid's usual offsets (Fajr +20 min, Dhuhr +10, Asr +10, Maghrib +5, Isha +10). Note: the mosque occasionally publishes fixed iqamah times (for example a fixed Fajr iqamah in some seasons), which can differ from the offset pattern.
- **Widget timeline** — entries are planned at every prayer boundary (plus midnight rollovers), so the "next prayer" and countdown roll over on time without opening the app.
- **Adhan notifications & Live Activity** — a notification with sound at every prayer time (7 days scheduled ahead), and a Lock Screen / Dynamic Island Live Activity counting down to the next prayer. Since v1.0.4 the Live Activity rolls over to the following prayer by itself when a prayer time arrives (a background refresh is chained to just after every Adhan — no server, everything stays on-device), and it already shows the prayer after next as a "Then: …" line.
- **Companion app** — one screen with today's times, the next-prayer countdown, and buttons for directions to the mosque and the mosque website (alrashidmosque.ca).
- Deep green (#0B3D2E / #0E5A40) and gold (#D4AF37) theme, with Dark and Tinted app-icon variants.
- **Native Light & Dark Mode (v1.0.4)** — the app, widgets and Live Activity follow the system appearance: warm white surfaces with deep-green text in Light Mode, green glass in Dark Mode, and the app icon switches to its Dark variant automatically (set the Home Screen icon appearance to Auto). Colors are kept high-contrast in both modes (deep green on white ≈ 10.9:1, white on green ≈ 7.5:1+) and text sizes were bumped up, for readers with low vision.

## Requirements

- iOS 17.0 or later, iPhone or iPad.

## Install (sideload)

1. Download `AlRashidWidget.ipa` from the latest GitHub Release.
2. Install it with your preferred sideloading tool (for example AltStore, SideStore, Sideloadly, or Xcode).
3. On the Home Screen, long-press → **+** → search **AlRashid** → add the small, medium or large widget. For the Lock Screen, long-press the Lock Screen → **Customize** → add the AlRashid widget under the clock.

The app and the widget share data through an App Group (`group.com.c12n.alrashidwidget`); with a free developer certificate the bundle IDs may be re-signed by your sideloading tool, which is fine — the App Group is declared in both targets' entitlements.

## Build from source

Requires Xcode 15+ (the GitHub Actions workflow uses the Xcode on `macos-26` runners).

```sh
xcodebuild \
  -project AlRashidWidget.xcodeproj \
  -scheme AlRashidWidget \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/AlRashidWidget.xcarchive \
  archive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM=""
```

Every push to `main` runs the **Build IPA** workflow, which archives the app unsigned (with the widget extension embedded in `PlugIns/`) and uploads `AlRashidWidget-IPA` as a build artifact.

## Project layout

- `AlRashidWidget/` — the app target (`AlRashidWidgetApp.swift`, `ContentView.swift`, assets, Info.plist, entitlements)
- `Shared/` — `PrayerCalculator.swift` (prayer-time calculator with the mosque timetable calibration) and `PrayerModels.swift` (day model, iqamah config, App Group cache, timeline planning, Umm al-Qura Hijri conversion), compiled into **both** targets
- `PrayerWidgetExtension/` — the WidgetKit extension (`PrayerWidget.swift`)
- `make_icon.py` — regenerates the app icon set (Pillow)

## Flutter edition (Android + cross-platform)

The `flutter/` directory holds a Flutter port of the same app — identical prayer calculator and mosque calibration (ported from `Shared/PrayerCalculator.swift` and validated to the minute against the iOS implementation), the same deep-green/gold design, Iqamah offsets, Umm al-Qura Hijri date, and Friday Jumu'ah handling, all computed on-device and offline.

- **Android app + home-screen widgets** — three Android widgets (next prayer with countdown; schedule; full schedule with Hijri header) powered by a Kotlin port of the same calculator (`flutter/android_overlay/`), so they stay correct without the app running. Download `AlRashidWidget.apk` from the Releases page and sideload it.
- **Responsive layouts** — phone single-column; **duo** two-pane layout at 600–1100dp (landscape phones, foldables, small tablets); wide tablet layout at 1100dp+ with today's and tomorrow's schedules side by side (iPad / Android tablets). The same Dart UI runs on iOS.

The `android/` and `ios/` platform folders are generated, not committed: run `flutter/tool/setup_platforms.sh` (Flutter 3.47.8) to assemble them from `lib/` + `android_overlay/` — the **Build APK** GitHub Actions workflow does the same, runs the calculator validation tests (`flutter/test/calculator_test.dart`), and uploads `AlRashidWidget-APK` as a build artifact.

## License

MIT — see [LICENSE](LICENSE).

Copyright (c) 2026 c12n Apps
