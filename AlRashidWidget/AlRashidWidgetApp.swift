//
//  AlRashidWidgetApp.swift
//  AlRashid Prayer Widget
//
//  App target: AlRashidWidget (com.c12n.alrashidwidget), iOS 17.0+
//  Target Membership: AlRashidWidget only.
//  Shared files (also in this target): PrayerCalculator.swift, PrayerModels.swift
//  Capability: App Groups -> group.com.c12n.alrashidwidget
//

import ActivityKit
import BackgroundTasks
import SwiftUI
import UserNotifications
import WidgetKit

@main
struct AlRashidWidgetApp: App {
    init() {
        BackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Theme.adaptiveGold)
        }
    }
}

// MARK: - Alert settings

/// User-facing alert preferences, shared by ContentView (toggles) and
/// AppServices (scheduling). Both default ON.
enum AlertSettings {
    static let notificationsKey = "alerts.notificationsEnabled"
    static let liveActivityKey = "alerts.liveActivityEnabled"

    private static var defaults: UserDefaults { .standard }

    static var notificationsEnabled: Bool {
        get { defaults.object(forKey: notificationsKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: notificationsKey) }
    }

    static var liveActivityEnabled: Bool {
        get { defaults.object(forKey: liveActivityKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: liveActivityKey) }
    }
}

// MARK: - App services (Adhan notifications + Live Activity)

/// Owns the two alert channels added in v1.0.3:
///
/// - Local notifications at every Adhan (the five prayers; Jumu'ah on
///   Fridays), scheduled 7 days ahead (up to 42 requests — under iOS's
///   64-pending cap) and re-scheduled whenever the app becomes active, so
///   the schedule is always fresh. Since v1.0.5 each prayer's alert can
///   be turned off in Settings, and Sunrise can be turned on. v1.0.2 and
///   earlier scheduled none.
/// - A Live Activity counting down to the next prayer on the Lock Screen
///   and Dynamic Island. Since v1.0.4 it rolls over to the following prayer
///   on its own when a prayer time arrives: a BGAppRefreshTask is chained
///   to fire just after every Adhan (see BackgroundRefresh), and each
///   update also pre-stages the prayer after next on the Lock Screen.
///   There is still no push server by design, so iOS decides the exact
///   moment the background task runs — for an app used daily it lands
///   within a few minutes of the Adhan.
enum AppServices {

    /// Called on launch and on every move to the active state.
    static func refresh() {
        Task {
            if AlertSettings.notificationsEnabled {
                _ = await AdhanNotifications.requestAuthorizationIfNeeded()
                await AdhanNotifications.reschedule()
            }
            await LiveActivityController.refresh()
            BackgroundRefresh.schedule()
        }
    }

    static func notificationsToggled(on: Bool) {
        Task {
            if on {
                _ = await AdhanNotifications.requestAuthorizationIfNeeded()
                await AdhanNotifications.reschedule()
            } else {
                await AdhanNotifications.cancelAll()
            }
        }
    }

    static func liveActivityToggled(on: Bool) {
        Task { await LiveActivityController.refresh() }
    }
}

// MARK: - Adhan alert sound (v1.1.0)

/// The sound played with Adhan notifications, chosen in Settings and
/// stored in the App Group. The two tones are small synthesized files
/// bundled with the app (no downloads, per the privacy promise).
enum AdhanSound: String, CaseIterable, Sendable, Identifiable {
    case `default`, silent, chime, bell

    var id: String { rawValue }
    static let storageKey = "alerts.sound"

    static var current: AdhanSound {
        let raw = UserDefaults(suiteName: PrayerProvider.appGroupIdentifier)?
            .string(forKey: storageKey)
        return AdhanSound(rawValue: raw ?? "") ?? .default
    }

    var l10nKey: String { "sound.\(rawValue)" }

    var notificationSound: UNNotificationSound? {
        switch self {
        case .default: .default
        case .silent: nil
        case .chime: UNNotificationSound(named: UNNotificationSoundName("adhan_chime.wav"))
        case .bell: UNNotificationSound(named: UNNotificationSoundName("adhan_bell.wav"))
        }
    }
}

// MARK: - Adhan local notifications

enum AdhanNotifications {
    private static var center: UNUserNotificationCenter { .current() }
    private static let identifierPrefix = "adhan."

    /// Asks for alert permission the first time (no-op once decided).
    /// Returns true when notifications may be scheduled.
    static func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default:
            return false
        }
    }

    static func authorizationDenied() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
    }

    /// Rebuilds the pending Adhan notifications for the next 7 days.
    static func reschedule() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else { return }

        await cancelAll()

        let provider = PrayerProvider.standard
        let calendar = provider.calendar
        let now = Date.now
        let todayStart = calendar.startOfDay(for: now)

        var requests: [UNNotificationRequest] = []
        for offset in 0..<7 {
            guard let dayStart = calendar.date(byAdding: .day, value: offset, to: todayStart) else { continue }
            let day = provider.computeDay(for: dayStart)
            for slot in day.slots where slot.adhan > now && PrayerAlertSettings.isEnabled(slot.prayer) {
                let content = UNMutableNotificationContent()
                if slot.prayer == .sunrise {
                    content.title = L10n.f("mosqueTitle", slot.name, MosqueInfo.name)
                    content.body = L10n.f("sunriseBody", PrayerFormat.time(slot.adhan))
                } else if slot.isJumuah {
                    content.title = L10n.f("mosqueTitle", slot.name, MosqueInfo.name)
                    content.body = L10n.f("labelAtTime", slot.iqamahLabel, PrayerFormat.time(slot.iqamah ?? slot.adhan))
                } else {
                    content.title = L10n.f("notifTitle", slot.name, MosqueInfo.name)
                    if let iqamah = slot.iqamah {
                        content.body = L10n.f("labelAtTime", slot.iqamahLabel, PrayerFormat.time(iqamah))
                    } else {
                        content.body = L10n.f("adhanAtTime", PrayerFormat.time(slot.adhan))
                    }
                }
                content.sound = AdhanSound.current.notificationSound
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: slot.adhan)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let identifier = identifierPrefix + String(Int(slot.adhan.timeIntervalSince1970))
                requests.append(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            }
        }
        for request in requests {
            try? await center.add(request)
        }
    }

    static func cancelAll() async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

// MARK: - Live Activity

@MainActor
enum LiveActivityController {

    /// Starts, updates or ends the next-prayer Live Activity to match the
    /// current snapshot and the user's preference.
    static func refresh() {
        let activities = Activity<PrayerActivityAttributes>.activities

        guard AlertSettings.liveActivityEnabled,
              ActivityAuthorizationInfo().areActivitiesEnabled else {
            endAll(activities)
            return
        }

        let provider = PrayerProvider.standard
        let snapshot = provider.snapshot()
        let next = snapshot.next
        let following = provider.followingSlot(after: next)
        let state = PrayerActivityAttributes.ContentState(
            prayerName: next.name,
            symbolName: next.symbolName,
            adhan: next.adhan,
            iqamah: next.iqamah,
            iqamahLabel: next.iqamahLabel,
            hijri: snapshot.day.hijriDate,
            isTomorrow: snapshot.isShowingTomorrow,
            followingName: following?.name,
            followingAdhan: following?.adhan,
            followingSymbolName: following?.symbolName,
            followingIqamah: following?.iqamah,
            followingIqamahLabel: following?.iqamahLabel
        )
        // Go stale shortly after the FOLLOWING prayer's Iqamah (or Adhan),
        // so the activity stays live across the automatic rollover at this
        // prayer's Adhan instead of dimming while the background refresh
        // that swaps in the next prayer is still on its way.
        let staleBase = following?.iqamah ?? following?.adhan ?? next.iqamah ?? next.adhan
        let staleDate = staleBase.addingTimeInterval(10 * 60)
        let content = ActivityContent(state: state, staleDate: staleDate)

        if let activity = activities.first {
            Task { await activity.update(content) }
            endAll(Array(activities.dropFirst()))
        } else {
            let attributes = PrayerActivityAttributes(mosqueName: MosqueInfo.name)
            _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
        }
    }

    private static func endAll(_ activities: [Activity<PrayerActivityAttributes>]) {
        for activity in activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}

// MARK: - Background refresh (automatic Live Activity rollover)

/// Chains a BGAppRefreshTask to just after every Adhan. When it fires, the
/// Live Activity is updated to the following prayer — so the Lock Screen
/// countdown rolls from Dhuhr to Asr (and so on) without the app ever
/// being opened — the Adhan notifications are re-scheduled, and the next
/// refresh is chained. The identifier must also be listed under
/// BGTaskSchedulerPermittedIdentifiers in Info.plist, AND Info.plist must
/// declare the `fetch` background mode (UIBackgroundModes) — without it
/// every submit() fails silently and the task never runs (the v1.0.4–
/// v1.0.5 rollover bug, fixed in v1.0.6). The Lock Screen additionally
/// promotes the pre-staged following prayer at the Adhan itself via a
/// TimelineView, so the visible switch does not wait for this task.
enum BackgroundRefresh {
    static let identifier = "com.c12n.alrashidwidget.refresh"
    private static var didRegister = false

    /// Must run before the app finishes launching (called from App.init).
    static func register() {
        guard !didRegister else { return }
        didRegister = true
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    /// Asks iOS to wake the app shortly after the next Adhan. Submitting a
    /// new request with the same identifier replaces the pending one.
    static func schedule() {
        let next = PrayerProvider.standard.snapshot().next
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = next.adhan.addingTimeInterval(15)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        // Chain first: by the time this runs, the snapshot's next prayer is
        // the following one, so this schedules the refresh after ITS Adhan.
        schedule()

        // The Live Activity update goes FIRST (v1.0.6): the background
        // budget is ~30 s, and rebuilding ~40 notification requests first
        // could starve the one update the user actually sees. Notifications
        // are refreshed last, as best-effort.
        let work = Task {
            await LiveActivityController.refresh()
            WidgetCenter.shared.reloadAllTimelines()
            if AlertSettings.notificationsEnabled {
                await AdhanNotifications.reschedule()
            }
        }
        task.expirationHandler = { work.cancel() }
        Task {
            _ = await work.result
            task.setTaskCompleted(success: !work.isCancelled)
        }
    }
}
