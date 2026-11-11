//
//  AlRashidWidgetApp.swift
//  AlRashid Prayer Widget
//
//  App target: AlRashidWidget (com.c12n.prayerapp), iOS 17.0+
//  Target Membership: AlRashidWidget only.
//  Shared files (also in this target): PrayerCalculator.swift, PrayerModels.swift
//  Capability: App Groups -> group.com.c12n.prayerapp
//

import ActivityKit
import AppIntents
import BackgroundTasks
import SwiftUI
import UIKit
import UserNotifications
import WidgetKit

/// Live appearance state (v2.2.0-alpha, rebuilt build 39): the
/// in-app Light/Dark/System choice lives in the App Group suite and
/// is written by Settings' @AppStorage. Cross-instance @AppStorage
/// observation proved unreliable (the app kept the launch
/// appearance until relaunched), so the App observes UserDefaults
/// changes directly and publishes mode, language and Minimal Mode
/// for the root. The mode itself is applied to the scene by
/// AppearanceController below; this observer never writes an
/// appearance itself.
final class AppearanceModeObserver: ObservableObject {
    @Published private(set) var mode: AppAppearance.Mode
    /// The in-app language, observed the same way as the mode
    /// (build 37). Views that used to read AppLanguage.current at
    /// render time kept the Arabic session's layoutDirection traits
    /// after switching back to English or French, so the App root
    /// publishes the direction from this observer.
    @Published private(set) var language: AppLanguage
    /// Minimal Mode, likewise published (build 37): the layout
    /// router read MinimalMode.enabled statically, so toggling the
    /// mode in Settings never re-ran the router and the tab shell
    /// (or the minimal layout) only changed on the next launch.
    @Published private(set) var minimalMode: Bool
    private var token: NSObjectProtocol?

    init() {
        mode = AppAppearance.mode
        language = AppLanguage.current
        minimalMode = MinimalMode.enabled
        token = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let current = AppAppearance.mode
            if current != self.mode { self.mode = current }
            let currentLanguage = AppLanguage.current
            if currentLanguage != self.language { self.language = currentLanguage }
            let currentMinimal = MinimalMode.enabled
            if currentMinimal != self.minimalMode { self.minimalMode = currentMinimal }
            // Build 39 (Claude consult): the mode is handed to the
            // ONE appearance writer. Nothing else in the app sets an
            // override or a preferred color scheme any more.
            AppearanceController.applyCurrent()
        }
    }
}

/// THE single appearance writer (build 39, rebuilt on the
/// architecture Claude Opus prescribed after builds 34 to 38 all
/// failed on device). The stored System / Light / Dark choice is
/// turned into a trait override on the window SCENE, and that is
/// the ONLY appearance write in the app:
///
/// - No `.preferredColorScheme` anywhere (it was a second writer
///   racing the window overrides; whichever wrote last won, which
///   is how the app ended up in mixed states).
/// - No `.id(flipToken)` tree rebuilds: a rebuild creates a fresh
///   hosting controller whose first pass runs before it is in the
///   hierarchy, so it reads pre-flip traits.
/// - No nested UIHostingController wrapper and no
///   traitCollectionDidChange hook (deprecated since iOS 17;
///   trait updates are top-down, so nested controllers can be
///   acting on the previous pass).
/// - In System mode the scene override is REMOVED, not pinned to
///   `.unspecified`, so the scene falls through to the device's
///   own appearance and follows Control Center flips live through
///   the normal trait system. Every color in the app is a dynamic
///   color (a UIColor trait-provider closure) or an
///   @Environment(\.colorScheme) read inside a view, so once the
///   traits move, the surfaces re-resolve at draw time with no
///   poking from here.
/// - Explicit Light / Dark also clear any legacy per-window
///   override left by builds 34 to 38, so nothing stale survives.
///
/// The stored key has dots ("appearance.mode"), so UserDefaults
/// KVO cannot observe it by property name; the observer above
/// watches didChangeNotification (which demonstrably fires for
/// in-app writes, since explicit Light/Dark always applied
/// instantly) and calls applyCurrent(). The root also calls it
/// once in onAppear for the initial apply at launch. (Build 41
/// removed the scene-activation re-apply; see AppDelegate.)
@MainActor
enum AppearanceController {
    static func applyCurrent() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            // Scene-level override: the trait source for every
            // window, sheet and alert in the scene. Build 41
            // (second Claude consult): System REMOVES the trait
            // override with remove(_:) instead of assigning
            // .unspecified (the WWDC23 pattern; assigning is not
            // documented to remove anything), and the per-window
            // override loop is gone entirely: the scene override
            // is authoritative, window overrides only duplicate it,
            // and nothing in this build writes them any more.
            switch AppAppearance.mode {
            case .system:
                windowScene.traitOverrides.remove(UITraitUserInterfaceStyle.self)
            case .light:
                windowScene.traitOverrides.userInterfaceStyle = .light
            case .dark:
                windowScene.traitOverrides.userInterfaceStyle = .dark
            }
        }
    }
}

/// Supplies the app's supported orientations, which the Qibla
/// screens narrow to portrait only (build 31).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?)
        -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }

    // Build 41 (second Claude consult): no didBecomeActive
    // appearance re-apply. A scene trait override persists until
    // changed, and in System mode there is no override at all, so
    // UIKit follows Control Center flips live on its own; the old
    // re-assert on every activation only raced the system's own
    // trait pass. The single writer runs on mode changes (the
    // defaults observer) and once at root onAppear.

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Re-register the Siri / Shortcuts phrases on every launch so
        // they survive updates and the build-34 bundle rebrand without
        // waiting for iOS to re-index the app on its own schedule.
        PrayerShortcuts.updateAppShortcutParameters()
        return true
    }
}

/// Runtime orientation lock: the app normally allows every
/// orientation its Info.plist declares; while a Qibla screen is
/// showing, the mask narrows to portrait and the scene is rotated
/// back if it was in landscape.
enum OrientationLock {
    static var mask: UIInterfaceOrientationMask = defaultMask

    static var defaultMask: UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
    }

    static func setPortraitOnly(_ locked: Bool) {
        mask = locked ? .portrait : defaultMask
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.windows.first?.rootViewController
        else { return }
        root.setNeedsUpdateOfSupportedInterfaceOrientations()
        if locked {
            scene.requestGeometryUpdate(
                .iOS(interfaceOrientations: .portrait)) { _ in }
        }
    }
}

@main
struct AlRashidWidgetApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appearanceObserver = AppearanceModeObserver()
    /// Quran player (v2.1.0-private): one engine + one download
    /// store for the whole app, injected for ContentView's mini
    /// player overlay and the Quran cover. The player's init
    /// restores the last session (paused — never autoplays).
    @StateObject private var quranPlayer = QuranPlayer()
    @StateObject private var quranDownloads = QuranDownloads()
    @StateObject private var quranBookmarks = QuranBookmarks()

    init() {
        BackgroundRefresh.register()
        // v1.5.2: token observers attach at process launch, not only on
        // scene activation — a process woken in the background (by the
        // refresh task or a token rotation) is observed too.
        LiveActivityPushSync.startObserving()
        // v1.8.0: restore/mirror the user's settings via iCloud KVS.
        SettingsSync.start()
    }

    var body: some Scene {
        WindowGroup {
            rootContent
        }
    }

    /// The SwiftUI root (build 39): a plain WindowGroup root. The
    /// old AppearanceWatchRoot hosting-controller wrapper is gone,
    /// and with it the preferredColorScheme + flip-token rebuilds:
    /// appearance is owned by AppearanceController at the scene
    /// level, and views follow it through their own traits.
    /// Layout direction and locale still come from the observer
    /// (build 37) so Arabic's right-to-left and a switch back
    /// apply live to the whole tree, including its UIKit-backed
    /// controls.
    private var rootContent: some View {
        ContentView()
            .environmentObject(quranPlayer)
            .environmentObject(quranDownloads)
            .environmentObject(quranBookmarks)
            .environmentObject(appearanceObserver)
            .environment(\.layoutDirection,
                         appearanceObserver.language.isRTL ? .rightToLeft : .leftToRight)
            .environment(\.locale, appearanceObserver.language.locale)
            .tint(Theme.adaptiveGold)
            .onAppear { AppearanceController.applyCurrent() }
    }
}

// MARK: - Alert settings

/// User-facing alert preferences, shared by ContentView (toggles) and
/// AppServices (scheduling). Notifications and reminders default ON;
/// the Live Activity defaults OFF (build 34) — on a first install or
/// an update the app asks once, with a Lock Screen preview, whether
/// to turn it on (LiveActivityPromptView in ContentView).
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
        get { defaults.object(forKey: liveActivityKey) as? Bool ?? false }
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
        SettingsSync.pushLocal()
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
/// stored in the App Group. Build 35 replaced every earlier bundled
/// sound (the chime, bell and the three 2.2.0 recordings) with the
/// single adhan from the mosque's MadinaAPPS app, at the user's
/// direction: the picker is now Default / Silent / Al Rashid Adhan.
/// A stored value naming a removed sound resolves to the Al Rashid
/// Adhan, so an existing selection is replaced rather than lost.
enum AdhanSound: String, CaseIterable, Sendable, Identifiable {
    case `default`, silent, alrashid, classic

    var id: String { rawValue }
    static let storageKey = "alerts.sound"

    /// The sound every install and update lands on until the user
    /// picks another (build 37, Youssef's order): the Al Rashid
    /// adhan from the mosque's own app. No stored value resolves
    /// here, and a stored value naming a sound that no longer
    /// exists (chime/bell/makkah/fajr were removed in build 35)
    /// resolves here too rather than to the system default.
    static var current: AdhanSound {
        let raw = UserDefaults(suiteName: PrayerProvider.appGroupIdentifier)?
            .string(forKey: storageKey)
        guard let raw, !raw.isEmpty else { return .alrashid }
        return AdhanSound(rawValue: raw) ?? .alrashid
    }

    var l10nKey: String { "sound.\(rawValue)" }

    var notificationSound: UNNotificationSound? {
        switch self {
        case .default: .default
        case .silent: nil
        case .alrashid: UNNotificationSound(named: UNNotificationSoundName("adhan_alrashid.wav"))
        case .classic: UNNotificationSound(named: UNNotificationSoundName("adhan_classic.wav"))
        }
    }
}

// MARK: - Per-prayer alert sounds (v1.8.0)

/// Optional per-prayer override of the app-wide Adhan sound, stored
/// in the App Group next to the per-prayer on/off switches. No stored
/// value means "follow the app-wide sound" — so existing users hear
/// no change until they set an override. Setting one to Silent mutes
/// just that prayer's alert.
enum PrayerSoundSettings {
    static func key(for prayer: Prayer) -> String { "alerts.sound.prayer.\(prayer.rawValue)" }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: PrayerProvider.appGroupIdentifier) ?? .standard
    }

    static func override(for prayer: Prayer) -> AdhanSound? {
        guard let raw = sharedDefaults.string(forKey: key(for: prayer)) else { return nil }
        return AdhanSound(rawValue: raw)
    }

    static func effectiveSound(for prayer: Prayer) -> AdhanSound {
        override(for: prayer) ?? AdhanSound.current
    }

    static func reset() {
        for prayer in Prayer.allCases {
            sharedDefaults.removeObject(forKey: key(for: prayer))
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
    private static let fastingPrefix = "fasting."
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
                content.sound = PrayerSoundSettings.effectiveSound(for: slot.prayer).notificationSound
                let identifier = identifierPrefix + String(Int(slot.adhan.timeIntervalSince1970))
                // Silence-next (v2.0.0): the one-shot flag from Siri /
                // the Control Center control drops exactly this one
                // Adhan alert; its reminder and all later alerts are
                // unaffected.
                if SilenceNextAlert.pendingEpoch != Int(slot.adhan.timeIntervalSince1970) {
                    scheduled.append((slot.adhan, makeRequest(identifier: identifier, content: content, fireDate: slot.adhan)))
                }

                // Pre-prayer reminder (v1.5): the five prayers only —
                // Sunrise has no reminder, and the Jumu'ah slot is
                // covered by its own Khutbah reminder below.
                if AlertSettings.reminderEnabled, !MinimalMode.enabled, slot.prayer.isPrayer, !slot.isJumuah {
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
            if day.isFriday, AlertSettings.jumuahReminderEnabled, !MinimalMode.enabled, let khutbah = day.jumuahKhutbah {
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
        // Sunnah fasting reminders (v2.0.0): one reminder at 20:00
        // the evening before each selected fasting day in the
        // window, carrying that day's Suhoor (Fajr) and Iftar
        // (Maghrib). Shares the same 60-request budget — the sort +
        // cap below keeps the earliest, so core Adhan alerts (all
        // earlier than a 20:00 reminder for a later day, and rebuilt
        // on every activation) are not displaced in practice.
        if FastingSettings.anyEnabled {
            for offset in 0..<7 {
                guard let dayStart = calendar.date(byAdding: .day, value: offset, to: todayStart) else { continue }
                guard FastingSettings.isFastingDay(dayStart, timeZone: calendar.timeZone) else { continue }
                let day = provider.computeDay(for: dayStart)
                guard let fire = calendar.date(bySettingHour: 20, minute: 0, second: 0,
                                               of: dayStart.addingTimeInterval(-86_400)),
                      fire > now else { continue }
                let fastingContent = UNMutableNotificationContent()
                fastingContent.title = L10n.f("mosqueTitle", L10n.t("fastingDay"), MosqueInfo.name)
                fastingContent.body = L10n.f("fastingReminderBody",
                                             PrayerFormat.time(day.fajr),
                                             PrayerFormat.time(day.maghrib))
                fastingContent.sound = .default
                let fastingID = fastingPrefix + String(Int(dayStart.timeIntervalSince1970))
                scheduled.append((fire, makeRequest(identifier: fastingID, content: fastingContent, fireDate: fire)))
            }
        }
        for entry in scheduled.sorted(by: { $0.fireDate < $1.fireDate }).prefix(maxPendingRequests) {
            try? await center.add(entry.request)
        }
    }

    static func cancelAll() async {
        let pending = await center.pendingNotificationRequests()
        let prefixes = [identifierPrefix, reminderPrefix, jumuahPrefix, fastingPrefix]
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
        // v2.0.0: with Iqamah-first on, the stale flip waits for the
        // Iqamah, so the activity counts down to it after the Adhan
        // instead of promoting the following prayer immediately.
        let staleDate = (IqamahCountdownSettings.enabled ? next.iqamah : nil) ?? next.adhan
        let content = ActivityContent(state: state, staleDate: staleDate, relevanceScore: 100)

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
        if let activity = live.first, !LiveActivityPushSync.activityExpired(activity),
           !LiveActivityPushSync.needsPushRetry(activity) {
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
    nonisolated private static let pushCapableKey = "pushsync.pushCapable"
    nonisolated private static let requestErrorKey = "pushsync.requestError"
    private static let lastAttemptKey = "pushsync.lastAttemptAt"
    private static let lastHTTPKey = "pushsync.lastHTTPStatus"
    nonisolated private static let lastErrorKey = "pushsync.lastError"
    nonisolated private static let registeredAtKey = "pushsync.registeredAt"
    private static let syncedHashKey = "pushsync.syncedHash"
    private static let buildKey = "pushsync.appBuild"
    // v1.6.0: push-to-start token state (see syncPushToStartToken).
    private static let ptsTokenKey = "pushsync.ptsToken"
    private static let ptsSyncedKey = "pushsync.ptsSyncedToken"
    private static let ptsRegisteredAtKey = "pushsync.ptsRegisteredAt"

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
                    // v1.6.0: an activity this build did not request was
                    // started by the server (push-to-start resurrection
                    // while the app wasn't running). It replaces whatever
                    // came before: end the older activities so the Lock
                    // Screen never stacks a frozen duplicate next to the
                    // live one.
                    if activity.id != defaults.string(forKey: activityIdKey) {
                        for other in Activity<PrayerActivityAttributes>.activities
                        where other.id != activity.id {
                            await other.end(nil, dismissalPolicy: .immediate)
                        }
                    }
                }
            }
            // v1.6.0: the push-to-start token lets the server begin a
            // fresh activity at a prayer boundary when the standing one
            // has died at the system lifetime cap (the 2026-11-02
            // Maghrib failure: update pushes returned 410 ExpiredToken
            // and nothing on the phone could resurrect it). Stream
            // every token the system issues to the server.
            if #available(iOS 17.2, *) {
                Task {
                    for await tokenData in Activity<PrayerActivityAttributes>.pushToStartTokenUpdates {
                        await syncPushToStartToken(hex: hex(tokenData))
                    }
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
        defaults.set(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
                     forKey: buildKey)
        if let requestError {
            defaults.set(requestError, forKey: requestErrorKey)
        } else {
            defaults.removeObject(forKey: requestErrorKey)
        }
    }

    /// v1.5.3: true when the standing activity is this app's own
    /// tokenless fallback (its push-type request failed) AND it was
    /// requested by an OLDER build. A newer build — e.g. one whose
    /// signing gained the push entitlement — retries the push-type
    /// request once instead of reusing the local-only activity
    /// forever. Retries are naturally once-per-build: the new request
    /// re-stamps the build number whether it succeeds or fails.
    static func needsPushRetry(_ activity: Activity<PrayerActivityAttributes>) -> Bool {
        guard activity.pushToken == nil else { return false }
        guard defaults.string(forKey: activityIdKey) == activity.id else { return false }
        guard defaults.object(forKey: pushCapableKey) != nil,
              !defaults.bool(forKey: pushCapableKey) else { return false }
        let recordedBuild = defaults.string(forKey: buildKey) ?? ""
        let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return recordedBuild != currentBuild
    }

    /// True when the tracked activity is old enough that the system's
    /// ~8-hour Live Activity lifetime could end it mid-day; refresh()
    /// renews it (end + fresh request) after 4 hours. The threshold
    /// dropped from 6 h in v1.6.0: the 2026-11-02 Maghrib miss showed a
    /// 6 h margin is too thin when the app may not run again before the
    /// cap — and the primary fix now lives server-side anyway (the
    /// server push-to-starts a fresh activity when one crosses ~6.5 h
    /// at a boundary), so this in-app renewal is the backup, not the
    /// mechanism. An activity this build did not request gets its
    /// clock started at first sight.
    static func activityExpired(_ activity: Activity<PrayerActivityAttributes>) -> Bool {
        if defaults.string(forKey: activityIdKey) != activity.id {
            defaults.set(activity.id, forKey: activityIdKey)
            defaults.set(Date.now.timeIntervalSince1970, forKey: activitySinceKey)
            return false
        }
        let since = defaults.double(forKey: activitySinceKey)
        guard since > 0 else { return false }
        return Date.now.timeIntervalSince1970 - since > 4 * 3600
    }

    /// Removes this install's registration (Live Activity turned off, or
    /// every activity ended): the server drops the token and schedule.
    static func unregister() {
        for task in tokenTasks.values { task.cancel() }
        tokenTasks.removeAll()
        for key in [activityIdKey, activitySinceKey, pushCapableKey, requestErrorKey,
                    lastAttemptKey, lastHTTPKey, lastErrorKey, registeredAtKey, syncedHashKey,
                    buildKey, ptsTokenKey, ptsSyncedKey, ptsRegisteredAtKey] {
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

    /// v1.6.0: streams the push-to-start token to the server. The token
    /// is scoped to the activity attributes type, reusable across
    /// starts, and rotates on system events, so every new value must
    /// replace the server's copy. Deliberately separate from the
    /// activity sync: the token has to reach the server even when no
    /// activity is currently registered (e.g. right after install, or
    /// after the standing activity died at the lifetime cap) — that is
    /// exactly when the server needs it.
    private static func syncPushToStartToken(hex tokenHex: String) async {
        defaults.set(tokenHex, forKey: ptsTokenKey)
        guard tokenHex != defaults.string(forKey: ptsSyncedKey) else { return }
        let body: [String: Any] = [
            "installationId": installationId,
            "pushToStartToken": tokenHex,
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return }
        var request = URLRequest(url: serverBase.appendingPathComponent("v1/push-to-start"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(registrationToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload
        for attempt in 0..<3 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: attempt == 1 ? 2_000_000_000 : 5_000_000_000)
            }
            let backgroundTask = UIApplication.shared.beginBackgroundTask(
                withName: "LiveActivityPushToStartSync") { }
            var ok = false
            if let (_, response) = try? await URLSession.shared.data(for: request),
               let status = (response as? HTTPURLResponse)?.statusCode,
               (200..<300).contains(status) {
                ok = true
            }
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
            if ok {
                defaults.set(tokenHex, forKey: ptsSyncedKey)
                defaults.set(Date.now.timeIntervalSince1970, forKey: ptsRegisteredAtKey)
                return
            }
        }
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
        var body: [String: Any] = [
            "installationId": installationId,
            "activityId": activity.id,
            "pushToken": tokenHex,
            "events": events,
        ]
        // v1.6.0: the server does the lifetime-cap math itself (update
        // vs. end + push-to-start a fresh activity at a boundary), so
        // it needs the activity's birth time — and, when known, the
        // push-to-start token. The dedicated token endpoint is the
        // primary path; including it here keeps the server's copy
        // fresh on every activity sync too.
        if defaults.string(forKey: activityIdKey) == activity.id {
            let since = defaults.double(forKey: activitySinceKey)
            if since > 0 { body["activityStartedAt"] = Int(since) }
        } else {
            body["activityStartedAt"] = Int(Date.now.timeIntervalSince1970)
        }
        if let pts = defaults.string(forKey: ptsTokenKey), !pts.isEmpty {
            body["pushToStartToken"] = pts
        }
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
                "staleDate": Int(((IqamahCountdownSettings.enabled ? state.iqamah : nil) ?? state.adhan).timeIntervalSince1970),
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
    static let identifier = "com.c12n.prayerapp.refresh"
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

// MARK: - iCloud settings sync (v1.8.0)

/// Mirrors the user's settings to iCloud Key-Value Storage so a
/// reinstall — or a move between TestFlight and a sideload — brings
/// them back on first launch. Only preference keys are mirrored,
/// never tokens or device state. Where the ubiquity entitlement is
/// not in the signing profile (some sideload routes), the store
/// simply never syncs and everything keeps working locally.
enum SettingsSync {
    private static var cloud: NSUbiquitousKeyValueStore { .default }
    private static var applying = false

    private static var suite: UserDefaults {
        UserDefaults(suiteName: PrayerProvider.appGroupIdentifier) ?? .standard
    }

    /// (key, inAppGroupSuite) pairs mirrored to iCloud. Values ride
    /// as the plist types UserDefaults already stores.
    private static var mirroredKeys: [(key: String, suite: Bool)] {
        var keys: [(String, Bool)] = [
            (AppAppearance.modeKey, true),
            (AppAppearance.primaryKey, true),
            (AppAppearance.accentKey, true),
            (AppAppearance.textKey, true),
            (AppAppearance.iconKey, true),
            (AppAppearance.savedThemesKey, true),
            (AppAppearance.widgetColorModeKey, true),
            (IqamahCountdownSettings.enabledKey, true),
            (IqamahCountdownSettings.leaveLeadKey, true),
            (RamadanMode.taraweehOffsetKey, true),
            (FastingSettings.mondayThursdayKey, true),
            (FastingSettings.whiteDaysKey, true),
            (MinimalMode.key, true),
            (AppAppearance.partThemeKey(.home), true),
            (AppAppearance.partThemeKey(.lock), true),
            (AppAppearance.partThemeKey(.liveActivity), true),
            (HijriOffset.storageKey, true),
            (AppLanguage.storageKey, true),
            (AppTextSize.storageKey, true),
            (AdhanSound.storageKey, true),
            (AlertSettings.notificationsKey, false),
            (AlertSettings.liveActivityKey, false),
            (AlertSettings.reminderKey, false),
            (AlertSettings.reminderLeadKey, false),
            (AlertSettings.jumuahReminderKey, false),
            (CompassSettings.hapticsKey, false),
        ]
        for prayer in Prayer.allCases {
            keys.append((PrayerAlertSettings.key(for: prayer), true))
            keys.append((PrayerSoundSettings.key(for: prayer), true))
        }
        return keys
    }

    static func start() {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud, queue: .main
        ) { notification in
            let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            if reason == NSUbiquitousKeyValueStoreServerChange
                || reason == NSUbiquitousKeyValueStoreInitialSyncChange {
                applyFromCloud()
            }
        }
        cloud.synchronize()
        // A cloud snapshot with no local language set means this is
        // a fresh install on a known iCloud account: restore first.
        if UserDefaults.standard.string(forKey: "whatsnew.lastSeenVersion") == nil,
           !cloud.dictionaryRepresentation.isEmpty {
            applyFromCloud()
        }
        pushLocal()
    }

    /// Local → iCloud, for every mirrored key present locally.
    static func pushLocal() {
        guard !applying else { return }
        for entry in mirroredKeys {
            let store = entry.suite ? suite : UserDefaults.standard
            if let value = store.object(forKey: entry.key),
               !valuesEqual(value, cloud.object(forKey: entry.key)) {
                cloud.set(value, forKey: entry.key)
            }
        }
        cloud.synchronize()
    }

    /// iCloud → local, then refresh whatever depends on settings.
    private static func applyFromCloud() {
        applying = true
        var changed = false
        for entry in mirroredKeys {
            guard let value = cloud.object(forKey: entry.key) else { continue }
            let store = entry.suite ? suite : UserDefaults.standard
            if !valuesEqual(value, store.object(forKey: entry.key)) {
                store.set(value, forKey: entry.key)
                changed = true
            }
        }
        applying = false
        if changed {
            PrayerProvider.standard.refreshCache()
            WidgetCenter.shared.reloadAllTimelines()
            AppServices.refresh()
        }
    }

    private static func valuesEqual(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x as NSObject, y as NSObject): return x == y
        default: return false
        }
    }
}

// MARK: - Settings backup file (v2.0.0, workstream 9)

/// Export / import of the full settings as one JSON file, shared
/// with the Android app (same canonical keys; the Android side
/// translates its two divergent key spellings). Contains NO secrets:
/// themes, per-part widget colors, sounds and per-prayer mutes,
/// reminders, fasting toggles, Minimal Mode, Hijri offset, language
/// and text size. The Live Activity push tokens and installation ids
/// are deliberately NOT settings and never enter this file.
enum SettingsBackup {
    static let formatVersion = 1

    /// (key, inAppGroupSuite) — the same split the stores use.
    private static var keys: [(key: String, suite: Bool)] {
        var list: [(String, Bool)] = [
            (AppAppearance.modeKey, true),
            (AppAppearance.primaryKey, true),
            (AppAppearance.accentKey, true),
            (AppAppearance.textKey, true),
            (AppAppearance.iconKey, true),
            (AppAppearance.savedThemesKey, true),
            (AppAppearance.widgetColorModeKey, true),
            (AppAppearance.partThemeKey(.home), true),
            (AppAppearance.partThemeKey(.lock), true),
            (AppAppearance.partThemeKey(.liveActivity), true),
            (IqamahCountdownSettings.enabledKey, true),
            (IqamahCountdownSettings.leaveLeadKey, true),
            (RamadanMode.taraweehOffsetKey, true),
            (FastingSettings.mondayThursdayKey, true),
            (FastingSettings.whiteDaysKey, true),
            (MinimalMode.key, true),
            (HijriOffset.storageKey, true),
            (AppLanguage.storageKey, true),
            (AppTextSize.storageKey, true),
            (AdhanSound.storageKey, true),
            (AlertSettings.notificationsKey, false),
            (AlertSettings.liveActivityKey, false),
            (AlertSettings.reminderKey, false),
            (AlertSettings.reminderLeadKey, false),
            (AlertSettings.jumuahReminderKey, false),
            (CompassSettings.hapticsKey, false),
        ]
        for prayer in Prayer.allCases {
            list.append((PrayerAlertSettings.key(for: prayer), true))
            list.append((PrayerSoundSettings.key(for: prayer), true))
        }
        return list
    }

    private static func store(suite: Bool) -> UserDefaults {
        suite ? (UserDefaults(suiteName: PrayerProvider.appGroupIdentifier) ?? .standard) : .standard
    }

    /// The backup document as JSON data (pretty, sorted keys).
    static func exportData() -> Data? {
        var values: [String: Any] = [:]
        for entry in keys {
            if let value = store(suite: entry.suite).object(forKey: entry.key) {
                values[entry.key] = value
            }
        }
        let document: [String: Any] = [
            "app": "AlRashidPrayer",
            "kind": "settings-backup",
            "version": formatVersion,
            "values": values,
        ]
        return try? JSONSerialization.data(withJSONObject: document,
                                           options: [.prettyPrinted, .sortedKeys])
    }

    /// Applies a backup document. Returns false for anything that is
    /// not an Al Rashid settings backup. Unknown keys are ignored, so
    /// an Android-made file (no Lock / Live Activity parts) imports
    /// cleanly and vice versa.
    static func importData(_ data: Data) -> Bool {
        guard let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              document["kind"] as? String == "settings-backup",
              let values = document["values"] as? [String: Any] else { return false }
        let known = Dictionary(uniqueKeysWithValues: keys.map { ($0.key, $0.suite) })
        for (key, value) in values {
            guard let suite = known[key] else { continue }
            store(suite: suite).set(value, forKey: key)
        }
        SettingsSync.pushLocal()
        return true
    }
}

// MARK: - iCloud Documents backup (v2.0.0, workstream 9 amendment)

/// The same backup JSON as a document in the app's iCloud container
/// — the explicit Back Up / Restore counterpart to the silent KVS
/// sync (KVS carries the small live keys; this is the full document
/// the user can trigger and restore from in Settings → Backup).
/// Degrades gracefully: with no iCloud account or no container the
/// methods return false and Settings shows the file route instead.
extension SettingsBackup {
    static let cloudFileName = "AlRashidSettingsBackup.json"
    static let lastCloudBackupKey = "backup.lastCloudAt"

    static var cloudAvailable: Bool { cloudURL != nil }

    private static var cloudURL: URL? {
        guard let container = FileManager.default
            .url(forUbiquityContainerIdentifier: nil) else { return nil }
        return container
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(cloudFileName)
    }

    static var lastCloudBackup: Date? {
        let stored = UserDefaults.standard.double(forKey: lastCloudBackupKey)
        return stored > 0 ? Date(timeIntervalSince1970: stored) : nil
    }

    /// Writes the current backup JSON to iCloud Documents.
    static func backupToCloud() -> Bool {
        guard let url = cloudURL, let data = exportData() else { return false }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            UserDefaults.standard.set(Date.now.timeIntervalSince1970,
                                      forKey: lastCloudBackupKey)
            return true
        } catch {
            return false
        }
    }

    /// Reads the iCloud backup (downloading it first if needed) and
    /// applies it through the same importer as the file route.
    static func restoreFromCloud() -> Bool {
        guard let url = cloudURL else { return false }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        guard let data = try? Data(contentsOf: url) else { return false }
        return importData(data)
    }
}
