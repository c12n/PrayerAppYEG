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
import UIKit
import UserNotifications
import WidgetKit

@main
struct AlRashidWidgetApp: App {
    init() {
        BackgroundRefresh.register()
        // v1.5.2: token observers attach at process launch, not only on
        // scene activation — a process woken in the background (by the
        // refresh task or a token rotation) is observed too.
        LiveActivityPushSync.startObserving()
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
    static let reminderKey = "alerts.reminderEnabled"
    static let reminderLeadKey = "alerts.reminderLeadMinutes"
    static let jumuahReminderKey = "alerts.jumuahReminderEnabled"

    private static var defaults: UserDefaults { .standard }

    static var notificationsEnabled: Bool {
        get { defaults.object(forKey: notificationsKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: notificationsKey) }
    }

    static var liveActivityEnabled: Bool {
        get { defaults.object(forKey: liveActivityKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: liveActivityKey) }
    }

    /// Pre-prayer reminder (v1.5): a gentle heads-up before each Adhan.
    static var reminderEnabled: Bool {
        get { defaults.object(forKey: reminderKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: reminderKey) }
    }

    /// How many minutes before the Adhan the reminder fires.
    static var reminderLeadMinutes: Int {
        get {
            let stored = defaults.integer(forKey: reminderLeadKey)
            return [5, 10, 15, 20, 30].contains(stored) ? stored : 10
        }
        set { defaults.set(newValue, forKey: reminderLeadKey) }
    }

    /// Friday reminder one hour before the Khutbah (v1.5).
    static var jumuahReminderEnabled: Bool {
        get { defaults.object(forKey: jumuahReminderKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: jumuahReminderKey) }
    }
}

// MARK: - Compass settings

/// Qibla compass preferences (v1.5.1): the facing haptic, which
/// fires only in the full-screen compass and can be turned off.
enum CompassSettings {
    static let hapticsKey = "compass.hapticsEnabled"

    static var hapticsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: hapticsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: hapticsKey) }
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
///   Since v1.3 the homelab push server (see LiveActivityPushSync) also
///   updates the activity via APNs at each Adhan; the background task
///   and the stale-date flip remain as fallbacks, since iOS decides the
///   exact moment the background task runs.
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

    /// Reminder / Jumu'ah preferences changed in Settings (v1.5):
    /// rebuild the pending schedule when notifications are on.
    static func alertPreferencesChanged() {
        Task {
            if AlertSettings.notificationsEnabled {
                await AdhanNotifications.reschedule()
            }
        }
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

    private static let reminderPrefix = "reminder."
    private static let jumuahPrefix = "jumuah."
    /// iOS refuses more than 64 pending requests per app; with Adhan
    /// alerts plus the v1.5 reminders the 7-day window can exceed
    /// that, so the earliest requests win and the rest are dropped —
    /// the schedule rebuilds on every app activation anyway.
    private static let maxPendingRequests = 60

    /// Rebuilds the pending Adhan notifications for the next 7 days,
    /// including the v1.5 pre-prayer reminders and Jumu'ah reminder.
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

        func makeRequest(identifier: String, content: UNMutableNotificationContent, fireDate: Date) -> UNNotificationRequest {
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        }

        let lead = AlertSettings.reminderLeadMinutes
        var scheduled: [(fireDate: Date, request: UNNotificationRequest)] = []
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
                let identifier = identifierPrefix + String(Int(slot.adhan.timeIntervalSince1970))
                scheduled.append((slot.adhan, makeRequest(identifier: identifier, content: content, fireDate: slot.adhan)))

                // Pre-prayer reminder (v1.5): the five prayers only —
                // Sunrise has no reminder, and the Jumu'ah slot is
                // covered by its own Khutbah reminder below.
                if AlertSettings.reminderEnabled, slot.prayer.isPrayer, !slot.isJumuah {
                    let fire = slot.adhan.addingTimeInterval(-Double(lead) * 60)
                    if fire > now {
                        let reminderContent = UNMutableNotificationContent()
                        reminderContent.title = L10n.f("mosqueTitle", slot.name, MosqueInfo.name)
                        reminderContent.body = L10n.f("inMinutes", slot.name, lead)
                        reminderContent.sound = .default
                        let reminderID = reminderPrefix + String(Int(slot.adhan.timeIntervalSince1970))
                        scheduled.append((fire, makeRequest(identifier: reminderID, content: reminderContent, fireDate: fire)))
                    }
                }
            }

            // Jumu'ah reminder (v1.5): one hour before the Khutbah.
            if day.isFriday, AlertSettings.jumuahReminderEnabled, let khutbah = day.jumuahKhutbah {
                let fire = khutbah.addingTimeInterval(-3600)
                if fire > now {
                    let jumuahContent = UNMutableNotificationContent()
                    jumuahContent.title = L10n.f("mosqueTitle", Prayer.jumuahName(in: AppLanguage.current), MosqueInfo.name)
                    jumuahContent.body = L10n.f("jumuahReminderNotif", PrayerFormat.time(khutbah))
                    jumuahContent.sound = .default
                    let jumuahID = jumuahPrefix + String(Int(khutbah.timeIntervalSince1970))
                    scheduled.append((fire, makeRequest(identifier: jumuahID, content: jumuahContent, fireDate: fire)))
                }
            }
        }
        for entry in scheduled.sorted(by: { $0.fireDate < $1.fireDate }).prefix(maxPendingRequests) {
            try? await center.add(entry.request)
        }
    }

    static func cancelAll() async {
        let pending = await center.pendingNotificationRequests()
        let prefixes = [identifierPrefix, reminderPrefix, jumuahPrefix]
        let identifiers = pending.map(\.identifier).filter { id in prefixes.contains { id.hasPrefix($0) } }
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
            LiveActivityPushSync.unregister()
            return
        }

        let provider = PrayerProvider.standard
        let snapshot = provider.snapshot()
        let next = snapshot.next
        let state = makeContentState(provider: provider, snapshot: snapshot, stagedAt: .now)
        // THE switch (v1.1.2): staleDate is the next prayer's Adhan.
        // When it passes, the system re-renders the activity with
        // isStale = true, and the views show the pre-staged FOLLOWING
        // prayer instead. Every refresh re-stages the set and moves the
        // stale date to the new next Adhan. Since v1.3 the server push
        // is the primary rollover; the stale flip is the fallback.
        let content = ActivityContent(state: state, staleDate: next.adhan, relevanceScore: 100)

        // v1.5.2: reuse the running activity WHATEVER its push state.
        // The v1.3–1.5.1 filter demanded pushToken != nil — but the
        // token arrives asynchronously after the request, so an
        // activation landing before it (onAppear and scenePhase both
        // refresh at every launch) ended a healthy just-started
        // activity and requested a new one, killing its token observer
        // before the first token could ever be registered. The server
        // consequently saw ZERO registrations and no push ever rolled
        // the activity over. An activity is now replaced only when it
        // nears the system's ~8 h Live Activity lifetime cap.
        let live = activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
        if let activity = live.first, !LiveActivityPushSync.activityExpired(activity) {
            Task { await activity.update(content) }
            endAll(activities.filter { $0.id != activity.id })
            LiveActivityPushSync.observe(activity)
        } else {
            endAll(activities)
            requestNew(content: content)
        }
    }

    /// Starts a fresh activity, push-capable when the installed copy's
    /// signing allows it. v1.5.2: a failed push-type request is
    /// RECORDED (Settings → Alerts shows it) instead of silently
    /// falling back — the silent fallback is what hid the broken
    /// server handoff through v1.3–1.5.1.
    private static func requestNew(
        content: ActivityContent<PrayerActivityAttributes.ContentState>
    ) {
        let attributes = PrayerActivityAttributes(mosqueName: MosqueInfo.name)
        do {
            let activity = try Activity.request(
                attributes: attributes, content: content, pushType: .token)
            LiveActivityPushSync.noteActivityRequested(id: activity.id, pushCapable: true)
            LiveActivityPushSync.observe(activity)
        } catch {
            LiveActivityPushSync.noteActivityRequested(
                id: "", pushCapable: false, requestError: error.localizedDescription)
            // Local-only fallback (v1.3.1): the Lock Screen countdown
            // still appears; the stale-date flip covers the switch.
            if let activity = try? Activity.request(
                attributes: attributes, content: content, pushType: .none) {
                LiveActivityPushSync.observe(activity)
            }
        }
    }

    /// Builds the ContentState for a snapshot: the snapshot's next prayer
    /// plus the two after it, pre-staged so the stale-date flip and the
    /// server push both have the following prayers ready. Shared by the
    /// on-device refresh and the push schedule builder.
    static func makeContentState(
        provider: PrayerProvider,
        snapshot: PrayerSnapshot,
        stagedAt: Date
    ) -> PrayerActivityAttributes.ContentState {
        let next = snapshot.next
        let following = provider.followingSlot(after: next)
        let third = following.flatMap { provider.followingSlot(after: $0) }
        return PrayerActivityAttributes.ContentState(
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
            followingIqamahLabel: following?.iqamahLabel,
            thirdName: third?.name,
            thirdAdhan: third?.adhan,
            thirdSymbolName: third?.symbolName,
            thirdIqamah: third?.iqamah,
            thirdIqamahLabel: third?.iqamahLabel,
            stagedAt: stagedAt
        )
    }

    private static func endAll(_ activities: [Activity<PrayerActivityAttributes>]) {
        for activity in activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}

// MARK: - Live Activity server push sync (v1.3)

/// Registers the running activity's APNs push token with the homelab
/// push server (activity.07051969.xyz, on Youssef's ZimaOS box) together
/// with a rolling 14-day schedule of precomputed ContentStates — one per
/// upcoming prayer boundary. At each boundary the server sends an
/// ActivityKit update push, so the Lock Screen rolls to the next prayer
/// even when neither the app nor its background refresh has run. The
/// on-device stale-date flip stays in place as the fallback, and the
/// core prayer times are still computed entirely on-device: the only
/// data sent is the activity's push token and the upcoming prayer names
/// and times the activity already displays.
@MainActor
enum LiveActivityPushSync {
    private static let serverBase = URL(string: "https://activity.07051969.xyz")!
    private static let registrationToken = "bf51e419eebfd2d74c19a44b0178a9ed8c65cbc7b1ca1fd1"
    private static let installationIdKey = "pushsync.installationId"

    // v1.5.2: registration state is PERSISTED (v1.3–1.5.1 kept it in
    // memory only, so a lost first POST was invisible and the dedupe
    // could suppress the retry) and is surfaced in Settings → Alerts,
    // so a broken handoff is diagnosable on the phone itself.
    private static let activityIdKey = "pushsync.activityId"
    private static let activitySinceKey = "pushsync.activitySince"
    private static let pushCapableKey = "pushsync.pushCapable"
    private static let requestErrorKey = "pushsync.requestError"
    private static let lastAttemptKey = "pushsync.lastAttemptAt"
    private static let lastHTTPKey = "pushsync.lastHTTPStatus"
    private static let lastErrorKey = "pushsync.lastError"
    private static let registeredAtKey = "pushsync.registeredAt"
    private static let syncedHashKey = "pushsync.syncedHash"

    private nonisolated static var defaults: UserDefaults { .standard }
    private static var tokenTasks: [String: Task<Void, Never>] = [:]
    private static var didStartObserving = false

    static var installationId: String {
        if let existing = UserDefaults.standard.string(forKey: installationIdKey) {
            return existing
        }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: installationIdKey)
        return fresh
    }

    /// v1.5.2: attaches token observers at process launch (called from
    /// App.init), for the activities that already exist and for every
    /// activity the system reports from then on — including processes
    /// woken in the background, which the v1.3 flow never observed.
    nonisolated static func startObserving() {
        Task { @MainActor in
            guard !didStartObserving else { return }
            didStartObserving = true
            for activity in Activity<PrayerActivityAttributes>.activities {
                observe(activity)
            }
            Task {
                for await activity in Activity<PrayerActivityAttributes>.activityUpdates {
                    observe(activity)
                }
            }
        }
    }

    /// Watches the activity's push token (it can rotate at any time) and
    /// registers every new token with the server. Safe to call repeatedly:
    /// one observer task per activity, and an immediate sync whenever a
    /// token is already available.
    static func observe(_ activity: Activity<PrayerActivityAttributes>) {
        if let token = activity.pushToken {
            Task { await sync(activity: activity, tokenHex: hex(token)) }
        }
        guard tokenTasks[activity.id] == nil else { return }
        tokenTasks[activity.id] = Task {
            for await tokenData in activity.pushTokenUpdates {
                await sync(activity: activity, tokenHex: hex(tokenData))
            }
        }
    }

    /// Records which activity the controller most recently requested,
    /// and whether it is push-capable, for the renewal check and the
    /// Settings diagnostics.
    static func noteActivityRequested(id: String, pushCapable: Bool, requestError: String? = nil) {
        defaults.set(id, forKey: activityIdKey)
        defaults.set(Date.now.timeIntervalSince1970, forKey: activitySinceKey)
        defaults.set(pushCapable, forKey: pushCapableKey)
        if let requestError {
            defaults.set(requestError, forKey: requestErrorKey)
        } else {
            defaults.removeObject(forKey: requestErrorKey)
        }
    }

    /// True when the tracked activity is old enough that the system's
    /// ~8-hour Live Activity lifetime could end it mid-day; refresh()
    /// renews it (end + fresh request) after 6 hours. An activity this
    /// build did not request gets its clock started at first sight.
    static func activityExpired(_ activity: Activity<PrayerActivityAttributes>) -> Bool {
        if defaults.string(forKey: activityIdKey) != activity.id {
            defaults.set(activity.id, forKey: activityIdKey)
            defaults.set(Date.now.timeIntervalSince1970, forKey: activitySinceKey)
            return false
        }
        let since = defaults.double(forKey: activitySinceKey)
        guard since > 0 else { return false }
        return Date.now.timeIntervalSince1970 - since > 6 * 3600
    }

    /// Removes this install's registration (Live Activity turned off, or
    /// every activity ended): the server drops the token and schedule.
    static func unregister() {
        for task in tokenTasks.values { task.cancel() }
        tokenTasks.removeAll()
        for key in [activityIdKey, activitySinceKey, pushCapableKey, requestErrorKey,
                    lastAttemptKey, lastHTTPKey, lastErrorKey, registeredAtKey, syncedHashKey] {
            defaults.removeObject(forKey: key)
        }
        let url = serverBase.appendingPathComponent("v1/register/\(installationId)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(registrationToken)", forHTTPHeaderField: "Authorization")
        Task { _ = try? await URLSession.shared.data(for: request) }
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// v1.5.2: the POST now runs inside a background-task assertion with
    /// retries (a request suspended mid-flight as the app backgrounded
    /// was lost silently in v1.3), and EVERY outcome is recorded. The
    /// dedupe skip requires a previous SUCCESS with the same hash.
    private static func sync(activity: Activity<PrayerActivityAttributes>, tokenHex: String) async {
        let events = buildSchedule()
        guard !events.isEmpty else { return }
        let first = (events.first?["eventTime"] as? Int) ?? 0
        let last = (events.last?["eventTime"] as? Int) ?? 0
        let hash = "\(tokenHex)|\(events.count)|\(first)|\(last)"
        if hash == defaults.string(forKey: syncedHashKey),
           defaults.double(forKey: registeredAtKey) > Date.now.timeIntervalSince1970 - 6 * 3600 {
            return  // this exact token + schedule already reached the server
        }
        let body: [String: Any] = [
            "installationId": installationId,
            "activityId": activity.id,
            "pushToken": tokenHex,
            "events": events,
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return }
        var request = URLRequest(url: serverBase.appendingPathComponent("v1/register"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(registrationToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload

        for attempt in 0..<3 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: attempt == 1 ? 2_000_000_000 : 5_000_000_000)
            }
            defaults.set(Date.now.timeIntervalSince1970, forKey: lastAttemptKey)
            let backgroundTask = UIApplication.shared.beginBackgroundTask(
                withName: "LiveActivityPushSync") { }
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                defaults.set(status, forKey: lastHTTPKey)
                if (200..<300).contains(status) {
                    defaults.set(hash, forKey: syncedHashKey)
                    defaults.set(Date.now.timeIntervalSince1970, forKey: registeredAtKey)
                    defaults.removeObject(forKey: lastErrorKey)
                    if backgroundTask != .invalid {
                        UIApplication.shared.endBackgroundTask(backgroundTask)
                    }
                    return
                }
                defaults.set("HTTP \(status)", forKey: lastErrorKey)
            } catch {
                defaults.set(error.localizedDescription, forKey: lastErrorKey)
            }
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
        }
    }

    // MARK: Diagnostics (Settings → Alerts)

    enum PushStatus {
        case registered(Date)
        case pending
        case failed(String)
        case localOnly(String?)
    }

    /// The registration state for the Settings row. Persisted in
    /// UserDefaults by the sync engine above; safe to read anywhere.
    nonisolated static var status: PushStatus {
        let d = UserDefaults.standard
        if d.object(forKey: pushCapableKey) != nil, !d.bool(forKey: pushCapableKey) {
            return .localOnly(d.string(forKey: requestErrorKey))
        }
        let registeredAt = d.double(forKey: registeredAtKey)
        if registeredAt > 0 {
            return .registered(Date(timeIntervalSince1970: registeredAt))
        }
        if let error = d.string(forKey: lastErrorKey) {
            return .failed(error)
        }
        return .pending
    }

    /// One event per prayer boundary in the next 14 days. Each event's
    /// ContentState is the state that becomes current at that boundary
    /// (snapshot taken 1 s after it), encoded exactly as ActivityKit
    /// will decode it from the push payload — the JSONEncoder default
    /// representation, passed through the server untouched.
    private static func buildSchedule() -> [[String: Any]] {
        let provider = PrayerProvider.standard
        let calendar = provider.calendar
        let now = Date.now
        let todayStart = calendar.startOfDay(for: now)
        var boundaries: [Date] = []
        for offset in 0...14 {
            guard let dayStart = calendar.date(byAdding: .day, value: offset, to: todayStart) else { continue }
            let day = provider.computeDay(for: dayStart)
            boundaries.append(contentsOf: day.prayerSlots.map(\.adhan).filter { $0 > now })
        }
        boundaries.sort()
        let encoder = JSONEncoder()
        var events: [[String: Any]] = []
        for boundary in boundaries.prefix(70) {
            let stagedAt = boundary.addingTimeInterval(1)
            let snapshot = provider.snapshot(at: stagedAt)
            let state = LiveActivityController.makeContentState(
                provider: provider, snapshot: snapshot, stagedAt: stagedAt)
            guard let data = try? encoder.encode(state),
                  let object = try? JSONSerialization.jsonObject(with: data) else { continue }
            events.append([
                "eventTime": Int(boundary.timeIntervalSince1970),
                "staleDate": Int(state.adhan.timeIntervalSince1970),
                "contentState": object,
            ])
        }
        return events
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
/// v1.0.5 rollover bug, fixed in v1.0.6). Since v1.1.2 the visible
/// switch does NOT depend on this task's timing: the activity's
/// staleDate is set to the next Adhan, and when it passes the system
/// re-renders the activity as stale and the views promote the
/// pre-staged following prayer (see LiveActivityController). This
/// task remains as the backstop that re-stages fresh prayers,
/// reloads the widgets and rebuilds the notifications whenever iOS
/// does choose to run it — BGAppRefreshTask timing is the system's
/// call (earliestBeginDate is a floor, not a promise), and on some
/// phones it lands far later than the requested 15 s after the Adhan.
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
