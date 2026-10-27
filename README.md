# AlRashid Prayer Widget

Prayer time widgets for **AlRashid Mosque, Edmonton, Canada** (13070 113 St NW) — a small companion app whose main purpose is its Home Screen and Lock Screen widgets: today's Adhan and Iqamah times, the next prayer, and a live countdown, in a deep-green and gold design.

## Features

- **Medium widget** — the full day at a glance: Fajr, Sunrise, Dhuhr, Asr, Maghrib and Isha with **Adhan and Iqamah columns**, the next prayer highlighted, plus the Hijri date and a live countdown to the next prayer.
- **Small widget** — next prayer, its Adhan and Iqamah times, and a live countdown.
- **Large widget** — the full day plus the mosque address footer; on Fridays the Dhuhr row becomes **Jumu'ah** with the 1:30 PM khutbah time.
- **Lock Screen widgets** — accessory rectangular (next prayer + time + countdown) and accessory circular (next prayer + time).
- **On-device prayer calculation** — times are computed on the phone for the mosque's coordinates (53.591189, -113.515598, America/Edmonton) using the **ISNA method** (Fajr 15°, Isha 15°, Asr Shafi / shadow factor 1) with an angle-based high-latitude rule. No network connection is needed for the core times.
- **Iqamah times** — shown alongside Adhan using Al Rashid's usual offsets (Fajr +20 min, Dhuhr +10, Asr +10, Maghrib +5, Isha +10). Note: the mosque occasionally publishes fixed iqamah times (for example a fixed Fajr iqamah in some seasons), which can differ from the offset pattern.
- **Widget timeline** — entries are planned at every prayer boundary (plus midnight rollovers), so the "next prayer" and countdown roll over on time without opening the app.
- **Companion app** — one screen with today's times, the next-prayer countdown, and buttons for directions to the mosque and the mosque website (alrashidmosque.ca).
- Deep green (#0B3D2E / #0E5A40) and gold (#D4AF37) theme, with Dark and Tinted app-icon variants.

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
- `Shared/` — `PrayerCalculator.swift` (ISNA prayer-time calculator) and `PrayerModels.swift` (day model, iqamah config, App Group cache, timeline planning), compiled into **both** targets
- `PrayerWidgetExtension/` — the WidgetKit extension (`PrayerWidget.swift`)
- `make_icon.py` — regenerates the app icon set (Pillow)

## License

MIT — see [LICENSE](LICENSE).

Copyright (c) 2026 c12n Apps
