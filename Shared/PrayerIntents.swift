import AppIntents
import Foundation
import UserNotifications

// MARK: - App Intents (v2.0.0, feature 7 — iOS leg)
//
// Siri / Shortcuts / Spotlight voice actions, compiled into BOTH the
// app and the widget extension (the iOS 18 Control Center control in
// PrayerWidget.swift runs SilenceNextAlertIntent from the extension).
// Everything reads the same on-device PrayerProvider the app uses —
// no network, no account. Android's equivalent lives in the Flutter
// app (App Actions shortcuts.xml + Quick Settings tile); Bixby
// consumes the same Android deep links (a standalone Bixby capsule
// needs Samsung's developer program — out of scope, see build log).

/// The prayers a user can ask about by name.
enum PrayerChoice: String, AppEnum {
    case fajr, sunrise, dhuhr, asr, maghrib, isha

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Prayer"
    }

    static var caseDisplayRepresentations: [PrayerChoice: DisplayRepresentation] {
        [
            .fajr: "Fajr",
            .sunrise: "Sunrise",
            .dhuhr: "Dhuhr",
            .asr: "Asr",
            .maghrib: "Maghrib",
            .isha: "Isha",
        ]
    }

    var prayer: Prayer {
        switch self {
        case .fajr: .fajr
        case .sunrise: .sunrise
        case .dhuhr: .dhuhr
        case .asr: .asr
        case .maghrib: .maghrib
        case .isha: .isha
        }
    }
}

/// "When is the next prayer?" — answered inline by Siri.
struct NextPrayerIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Prayer"
    static var description = IntentDescription(
        "Find out which prayer is next at Al Rashid Mosque and when it is.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let provider = PrayerProvider.standard
        let snapshot = provider.snapshot()
        let next = snapshot.next
        let when = PrayerFormat.time(next.adhan)
        let day = snapshot.isShowingTomorrow ? "tomorrow" : "today"
        return .result(dialog: "\(next.name) is next, \(day) at \(when) at Al Rashid Mosque.")
    }
}

/// "When is Maghrib?" — today's time for one named prayer.
struct PrayerTimeIntent: AppIntent {
    static var title: LocalizedStringResource = "Prayer Time"
    static var description = IntentDescription(
        "Find out today's time for a specific prayer at Al Rashid Mosque.")

    @Parameter(title: "Prayer")
    var prayer: PrayerChoice

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let provider = PrayerProvider.standard
        let day = provider.computeDay(for: Date.now)
        let time = day.adhan(for: prayer.prayer)
        let name = prayer.prayer.displayName
        return .result(dialog: "\(name) is at \(PrayerFormat.time(time)) today at Al Rashid Mosque.")
    }
}

/// Silence the next Adhan alert — the action behind the Control
/// Center / Lock Screen control and the Siri shortcut. Sets the
/// one-shot flag in the App Group; the app's scheduler drops exactly
/// that one alert on its next rebuild (which runs on every app
/// activation). Only that alert is skipped — reminders and every
/// later alert are untouched.
struct SilenceNextAlertIntent: AppIntent {
    static var title: LocalizedStringResource = "Silence Next Alert"
    static var description = IntentDescription(
        "Silence only the next Adhan alert. Everything after it still plays.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let provider = PrayerProvider.standard
        let next = provider.snapshot().next
        SilenceNextAlert.silence(adhan: next.adhan)
        // Build 34: also cancel the already-scheduled notification
        // right now. The scheduler's identifiers are deterministic
        // ("adhan." + the Adhan epoch, AdhanNotifications), so this
        // works even if the app is never opened before the prayer —
        // previously the suite flag alone was only honoured on the
        // app's next schedule rebuild. The flag stays set as well, so
        // a later rebuild cannot re-add the alert.
        let identifier = "adhan.\(Int(next.adhan.timeIntervalSince1970))"
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier])
        return .result(dialog: "The \(next.name) alert at \(PrayerFormat.time(next.adhan)) will be silent. Later alerts are unchanged.")
    }
}

/// Donated shortcuts so the phrases work without setup.
struct PrayerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextPrayerIntent(),
            phrases: [
                "When is the next prayer with \(.applicationName)",
                "Next prayer with \(.applicationName)",
            ],
            shortTitle: "Next Prayer",
            systemImageName: "clock")
        AppShortcut(
            intent: PrayerTimeIntent(),
            phrases: [
                "When is \(\.$prayer) with \(.applicationName)",
            ],
            shortTitle: "Prayer Time",
            systemImageName: "sun.max")
        AppShortcut(
            intent: SilenceNextAlertIntent(),
            phrases: [
                "Silence the next alert with \(.applicationName)",
            ],
            shortTitle: "Silence Next Alert",
            systemImageName: "bell.slash")
    }
}
