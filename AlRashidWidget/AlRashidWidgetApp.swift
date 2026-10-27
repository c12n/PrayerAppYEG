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
import SwiftUI
import UserNotifications

@main
struct AlRashidWidgetApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Theme.gold)
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
///   Fridays), scheduled 7 days ahead (35 requests — under iOS's
///   64-pending cap) and re-scheduled whenever the app becomes active, so
///   the schedule is always fresh. v1.0.2 and earlier scheduled none.
/// - A Live Activity counting down to the next prayer on the Lock Screen
///   and Dynamic Island. It refreshes whenever the app is opened or
///   foregrounded (Live Activities can only be updated by the app or a
///   push server; there is no server here by design).
enum AppServices {

    /// Called on launch and on every move to the active state.
    static func refresh() {
        Task {
            if AlertSettings.notificationsEnabled {
                _ = await AdhanNotifications.requestAuthorizationIfNeeded()
                await AdhanNotifications.reschedule()
            }
            await LiveActivityController.refresh()
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
            for slot in day.prayerSlots where slot.adhan > now {
                let content = UNMutableNotificationContent()
                content.title = slot.isJumuah ? "Jumu'ah — \(MosqueInfo.name)" : "\(slot.name) Adhan — \(MosqueInfo.name)"
                if let iqamah = slot.iqamah {
                    content.body = "\(slot.iqamahLabel) at \(PrayerFormat.time(iqamah))"
                } else {
                    content.body = "Adhan at \(PrayerFormat.time(slot.adhan))"
                }
                content.sound = .default
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
        let state = PrayerActivityAttributes.ContentState(
            prayerName: next.name,
            symbolName: next.symbolName,
            adhan: next.adhan,
            iqamah: next.iqamah,
            iqamahLabel: next.iqamahLabel,
            hijri: snapshot.day.hijriDate,
            isTomorrow: snapshot.isShowingTomorrow
        )
        // Go stale shortly after the Iqamah (or the Adhan when no Iqamah),
        // so a finished countdown does not linger as if it were live.
        let staleDate = (next.iqamah ?? next.adhan).addingTimeInterval(10 * 60)
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
