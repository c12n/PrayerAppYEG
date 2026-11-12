# Prayer YEG for Wear OS

Standalone Wear OS companion to Prayer YEG. It computes Edmonton prayer
times entirely on the watch (no phone pairing required), using the same
solar calculator and the same mosque timetable calibration as the phone
apps.

## Features

- **Now** screen: next prayer, live countdown, its Adhan and Iqamah
  times, and the Hijri date (Umm al-Qura).
- **Today** screen: all six times with Adhan and Iqamah, next prayer
  highlighted. On Fridays the Dhuhr row becomes Jumu'ah with the
  1:30 PM Khutbah in the Iqamah column.
- **About** screen: app info and the data note.
- A Wear **Tile** (next prayer, time and countdown) and a watch-face
  **Complication** (SHORT_TEXT: next prayer name and time).
- Iqamah offsets match the phone apps: Fajr +20, Dhuhr +10, Asr +10,
  Maghrib +5, Isha +10.

## Build

Built by `.github/workflows/build-wear.yml` (Gradle 8.7, Java 17).
The workflow first runs the JVM unit tests in
`app/src/test/.../CalculatorTest.kt`, which verify the calculator
against the same reference vectors as the phone test suites, then
builds a debug-signed release APK (internal sideload build, artifact
`PrayerYEG-Wear-APK`). Not a Play release.

Package: `com.c12n.prayerappAndroid.wear` | minSdk 30 (Wear OS 3).

The prayer math lives in `PrayerCalculator.kt` (calibration constants
identical to `flutter/lib/prayer_calculator.dart`), the day/snapshot
model in `PrayerModels.kt` (including the explicit America/Edmonton
transition table the phone apps use), and the Hijri conversion in
`HijriCalendar.kt` (month table generated from the Dart source of
truth, do not hand-edit).
