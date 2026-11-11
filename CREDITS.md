# Credits and Attribution | Prayer YEG

This file records where everything used in Prayer YEG came from: the texts, the voices, the data, the schedules, the libraries, and the design references. Every entry names the evidence it is based on, in this repository. Anything whose origin could not be traced from this repository is listed openly at the end, under "Origins not documented", rather than guessed.

## This app

- Prayer YEG, designed and developed by c12n Apps. Copyright (c) 2026 c12n Apps. Released under the MIT License (see LICENSE). Earlier builds were published under the names Al Rashid Prayer and Edmonton Prayer Times.
- The app itself is original work by c12n Apps, including: the on-device prayer time calculator and its mosque timetable calibration, the widget suite and Live Activity system, the Quran player engine and its interfaces, Minimal Mode, the iPhone Duo and iPad layouts, the settings backup format, and the Android edition. Evidence: the source code in this repository (AlRashidWidget/, Shared/, PrayerWidgetExtension/, flutter/).
- App icon artwork: original artwork drawn for this app by c12n Apps, generated programmatically with make_icon.py using Pillow (the Python imaging library, imported as PIL). Evidence: make_icon.py header and imports.
- No third-party fonts are bundled; the apps use the system fonts and SF Symbols of the platforms they run on.

## Quran text and translation

- Arabic Quran text (Uthmani script): bundled in AlRashidWidget/Quran/quran_text.json and shown in the Quran lyrics view. Evidence: file header comment in AlRashidWidget/Quran/QuranLyrics.swift describes the text as "Arabic (Uthmani)". The digital source the text file was taken from is not named in this repository; see "Origins not documented".
- English translation of the Quran (full text): Saheeh International. Evidence: AlRashidWidget/Quran/QuranLyrics.swift header comment names the Saheeh International English translation as the translation bundled in quran_text.json.
- Verse of the day (Daily Verse): short Quran quotations embedded in Shared/PrayerModels.swift, with English and French renderings the code describes as public-domain-style. Evidence: the DailyVerse doc comment in Shared/PrayerModels.swift. No external translator is named there; see "Origins not documented".

## Audio

- Arabic Quran recitation (streaming and downloads): audio files are served by the Islamic Network CDN (cdn.islamic.network). Evidence: the "audioBase" URL in AlRashidWidget/Quran/surahs.json ("https://cdn.islamic.network/quran/audio-surah/128"), loaded by AlRashidWidget/Quran/QuranModels.swift.
- Arabic reciters, as named in the bundled surah catalogue (surahs.json): Mishary Rashid Alafasy, Abdul Basit Abdul Samad, Abdullah Basfar, and Aziz Alili. Evidence: the "reciters" list in surahs.json, with per-surah durations for each reciter.
- English Quran narration: narrated by Ibrahim Walk, audio hosted by QuranicAudio (download.quranicaudio.com). Evidence: the stream URL "https://download.quranicaudio.com/quran/ibrahim_walk/%03d.mp3" and the "QuranicAudio" doc comment in AlRashidWidget/Quran/QuranModels.swift.
- Adhan alert sound, mosque recording (adhan_alrashid.wav): the adhan sound from Al Rashid Mosque's own mobile app, an app developed by MadinaAPPS. Evidence: code comments in AlRashidWidget/AlRashidWidgetApp.swift and flutter/lib/app_settings.dart describe it as "the single adhan from the mosque's MadinaAPPS app". The muezzin who performs this recording is not named in this repository; see "Origins not documented".
- Adhan alert sound, classic recording (adhan_classic.wav): a bundled adhan recording offered as the "Classic" sound option. Its original recording source and muezzin are not documented in this repository; see "Origins not documented".

## Prayer data and schedules

- Prayer timetable and Iqamah schedule: the published prayer timetable of Al Rashid Mosque, Edmonton, Canada (alrashidmosque.ca). The calculator's "AlRashid Mosque" method profile is fitted to that published timetable, including its Iqamah offsets. Evidence: the Method profile and calibration comments in Shared/PrayerCalculator.swift, the settings footer string in Shared/PrayerModels.swift ("Prayer time data is publicly accessible from the Al Rashid Mosque website"), and the FAQ in README.md. The timetable data itself is publicly published by the mosque; this app is not affiliated with or endorsed by the mosque.
- Prayer time calculation: the standard solar algorithm (Julian day, solar declination, equation of time, hour angles), implemented in this project. Evidence: header comment in Shared/PrayerCalculator.swift ("Self-contained, offline prayer-time calculator using the standard solar algorithm"). No third-party calculation library is used.
- Hijri dates: the Umm al-Qura calendar, using its official month table and the algorithm credited in the code to van Gent. Evidence: header comment in flutter/lib/hijri_calendar.dart ("Umm al-Qura Hijri conversion using the official month table (van Gent's algorithm)"), ported from the iOS implementation in Shared/PrayerModels.swift.
- Qibla direction: the initial great-circle bearing from the mosque coordinates to the Kaaba (21.422487, 39.826206), computed on device. Evidence: the Qibla compass comment and code in flutter/lib/main.dart and the matching iOS implementation. No external data source is used.

## Religious texts

- Daily Hadith (30 entries): each entry is labelled in the code with the collection it comes from. Evidence: the source labels on the DailyHadith entries in Shared/PrayerModels.swift.
  - Sahih al-Bukhari, compiled by Imam al-Bukhari | 2 entries labelled "Bukhari" and 16 labelled "Bukhari & Muslim".
  - Sahih Muslim, compiled by Imam Muslim | 6 entries labelled "Muslim" and the 16 joint entries above.
  - Jami' at-Tirmidhi, compiled by Imam at-Tirmidhi | 6 entries labelled "Tirmidhi".
- The 99 Names of Allah: the list of names, transliterations, and English, French, and Arabic meanings is embedded in the app code. Evidence: Shared/PrayerModels.swift (NamesOfAllah) and flutter/lib/names_of_allah.dart. No external source for this list is named in this repository; see "Origins not documented".

## Design references

Features below were implemented in this project with another app as the visual and behavioural reference, as recorded in code comments. The implementations are this project's own code; the reference is credited so the design origin is on the record.

- Spotify (Spotify AB): the Now Playing screen layout, the lyrics card placement, and the scroll-collapsing tab bar behaviour were modelled on Spotify's app. Evidence: header comments in AlRashidWidget/Quran/NowPlayingView.swift ("Now Playing in the Spotify layout", "the spot Spotify puts its lyrics card"), AlRashidWidget/ContentView.swift ("the Spotify-style behaviour"), and PrayerWidgetExtension/PrayerWidget.swift ("Spotify-style small card") for the Continue Listening widget.
- Apple Music (Apple Inc.): an Apple Music style Now Playing layout was also implemented in an earlier build and removed in build 39, leaving the Spotify style as the only one. Evidence: comments in AlRashidWidget/Quran/QuranPlayer.swift and NowPlayingView.swift.

## Software and libraries

- Apple platforms and frameworks (Apple Inc.): Swift, SwiftUI, WidgetKit, ActivityKit, App Intents, AVFoundation, MediaPlayer, UserNotifications, and SF Symbols, on iOS and watchOS. Evidence: framework imports across the Swift sources and the "Built With" section of README.md.
- Flutter and Dart (Google): the Android edition is a Flutter app. Evidence: flutter/pubspec.yaml and README.md.
- Flutter packages from pub.dev, as declared in flutter/pubspec.yaml: timezone, intl, and shared_preferences. Evidence: the dependencies block in flutter/pubspec.yaml. This repository does not include a lockfile naming their publishers, so no publisher names are asserted here.
- AndroidX Car App library (androidx.car.app:app:1.7.0) and Google Play services Auth (com.google.android.gms:play-services-auth:21.2.0), both by Google: used by the Android Auto screen and Drive backup sign-in. Evidence: the dependency lines added by flutter/android_overlay/patch_android.py.
- Android platform APIs: the native Android overlay (widgets, alerts, Quick Settings tile, car service) is written against the Android SDK in Kotlin. Evidence: imports in flutter/android_overlay/kotlin/.
- Pillow (PIL): used to draw the app icon set. Evidence: make_icon.py imports.
- GitHub Actions used by this repository's build workflows: actions/checkout, actions/setup-java, and actions/upload-artifact (by GitHub), and subosito/flutter-action (by subosito). Evidence: the "uses:" lines in .github/workflows/build-apk.yml, build-ipa.yml, and testflight.yml.

## Origins not documented

The following are used in the app, but this repository does not document where they originally came from. They are listed here so the gap is on the record, not hidden:

- The digital source of the bundled Arabic Quran text file (quran_text.json), beyond its Uthmani script.
- The muezzin (performer) of the mosque adhan recording (adhan_alrashid.wav).
- The original recording source and muezzin of the classic adhan recording (adhan_classic.wav).
- The original translator of the Daily Verse English and French renderings.
- The external source, if any, of the embedded 99 Names list and its meanings.

If you are a creator named in this file, or you hold rights in anything listed above, please open an issue in this repository so the record can be corrected or completed.
