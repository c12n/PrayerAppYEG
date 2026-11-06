//
//  ContentView.swift
//  AlRashid Prayer Widget
//
//  Target Membership: AlRashidWidget only.
//

import AppIntents
import CoreMotion
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import WidgetKit

/// Reports the home list's scroll offset (the content's top edge in
/// the scroll view's coordinate space) for the status-bar auto-hide.
private struct HomeScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    /// The user's Light/Dark choice from Settings (App Group, shared with
    /// the widgets). Applied with preferredColorScheme below — this is
    /// what makes the whole UI actually follow the in-app setting.
    @AppStorage(AppAppearance.modeKey, store: UserDefaults(suiteName: PrayerProvider.appGroupIdentifier))
    private var modeRaw: String = AppAppearance.Mode.system.rawValue
    /// The theme colors, observed here as well as in Settings (v1.0.9).
    /// Until now the main screen only observed the Light/Dark mode, so a
    /// color change written by Settings never re-rendered this view —
    /// the cards kept the old main color until the app was relaunched.
    /// Watching the same keys makes every change repaint instantly, and
    /// the stamp below rebuilds the timeline content with the new colors.
    @AppStorage(AppAppearance.primaryKey, store: UserDefaults(suiteName: PrayerProvider.appGroupIdentifier))
    private var primaryHex: Int = Int(AppAppearance.defaultPrimaryHex)
    @AppStorage(AppAppearance.accentKey, store: UserDefaults(suiteName: PrayerProvider.appGroupIdentifier))
    private var accentHex: Int = Int(AppAppearance.defaultAccentHex)
    @AppStorage(AppAppearance.textKey, store: UserDefaults(suiteName: PrayerProvider.appGroupIdentifier))
    private var textHex: Int = Int(AppAppearance.defaultTextHex)
    /// Language + text size (v1.1.0), observed here so a change in
    /// Settings re-renders the whole screen — including the layout
    /// direction for Arabic.
    @AppStorage(AppLanguage.storageKey, store: UserDefaults(suiteName: PrayerProvider.appGroupIdentifier))
    private var languageCode: String = AppLanguage.en.rawValue
    @AppStorage(AppTextSize.storageKey, store: UserDefaults(suiteName: PrayerProvider.appGroupIdentifier))
    private var textSizeRaw: String = AppTextSize.standard.rawValue
    @State private var showSettings = false
    /// iPhone Duo (v2.0.0): the icon rail's Qibla sheet and its
    /// Day/Tomorrow switch for the right-hand pane.
    @State private var showDuoCompass = false
    @State private var duoShowTomorrow = false
    /// Monthly calendar sheet (v2.0.0, feature 2).
    @State private var showCalendar = false
    /// StandBy nightstand (v2.0.0, feature 4).
    @State private var showStandBy = false
    /// What's New sheet (v1.8.0): shown once after an update, never
    /// on a fresh install.
    @State private var showWhatsNew = false
    /// In-app update reminder (v1.7.0): checks the version note hosted
    /// in the c12nfeather source and prompts toward TestFlight when a
    /// newer public build than the installed one is advertised.
    @StateObject private var updateChecker = UpdateChecker()
    @Environment(\.openURL) private var openURL
    /// Bumped by Settings on every change — and again when the sheet
    /// closes — to force this screen to rebuild with the new values
    /// (v1.1.1). Cross-view @AppStorage observation of the App Group
    /// suite proved unreliable on device: Settings wrote the new theme,
    /// but this screen kept the old one until the app was relaunched.
    /// A @State change in THIS view always re-renders it, and the stamp
    /// below rebuilds the timeline with colors re-read from the suite.
    @State private var appearanceGeneration = 0
    /// True once the home list is scrolled: the status bar hides so
    /// it never floats over the prayer cards mid-scroll (v1.5.1), and
    /// screenshots taken while scrolled come out clean.
    @State private var statusBarHidden = false
    private let provider = PrayerProvider.standard

    /// Changes whenever any appearance value changes.
    private var appearanceStamp: String {
        "\(modeRaw)-\(primaryHex)-\(accentHex)-\(textHex)-\(languageCode)-\(textSizeRaw)"
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let snapshot = provider.snapshot(at: context.date)
            let todaySchedule = provider.day(for: context.date)
            GeometryReader { proxy in
                // Layout routing (v2.0.0): iPad at regular width gets
                // the multi-column iPad layout; any phone-width window
                // of 600 pt or more (Pro Max / Plus landscape) gets the
                // iPhone Duo two-pane layout; everything else keeps the
                // single column. Width — never text size — decides, and
                // Dynamic Type only ever grows the panes' rows.
                if MinimalMode.enabled {
                    minimalLayout(snapshot: snapshot, today: todaySchedule, now: context.date)
                } else if UIDevice.current.userInterfaceIdiom == .pad,
                   proxy.size.width >= 700 {
                    iPadLayout(snapshot: snapshot, today: todaySchedule, now: context.date)
                } else if proxy.size.width >= 600 {
                    duoLayout(snapshot: snapshot, today: todaySchedule, now: context.date)
                } else {
                    phoneLayout(snapshot: snapshot, today: todaySchedule, now: context.date)
                }
            }
            .sheet(isPresented: $showWhatsNew) {
                WhatsNewView()
            }
            .fullScreenCover(isPresented: $showStandBy) {
                StandByView(snapshot: snapshot)
            }
        }
        .id("\(appearanceStamp)#\(appearanceGeneration)")
        .background { AppBackground() }
        .preferredColorScheme(AppAppearance.Mode(rawValue: modeRaw)?.colorScheme)
        .environment(\.layoutDirection, AppLanguage.current.isRTL ? .rightToLeft : .leftToRight)
        .environment(\.locale, AppLanguage.current.locale)
        .dynamicTypeSize(AppTextSize.current.dynamicTypeSize)
        .sheet(isPresented: $showSettings, onDismiss: { appearanceGeneration += 1 }) {
            SettingsView { appearanceGeneration += 1 }
                .environmentObject(updateChecker)
        }
        .alert(L10n.t("updateAvailable"), isPresented: $updateChecker.showAlert) {
            Button(L10n.t("updateNow")) {
                if let update = updateChecker.updateToShow,
                   let url = URL(string: update.url) {
                    openURL(url)
                }
            }
            Button(L10n.t("updateLater"), role: .cancel) {
                updateChecker.dismiss()
            }
        } message: {
            if let update = updateChecker.updateToShow {
                Text(L10n.f("updateAvailableBody", update.version))
            }
        }
        .onAppear {
            refreshWidgets()
            if !MinimalMode.enabled {
                updateChecker.checkIfNeeded()
                checkWhatsNew()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                appearanceGeneration += 1
                refreshWidgets()
                if !MinimalMode.enabled {
                    updateChecker.checkIfNeeded()
                }
            }
        }
    }

    // MARK: Layouts (v2.0.0)

    /// The original single column: portrait phones and narrow windows.
    private func phoneLayout(snapshot: PrayerSnapshot, today: PrayerDay, now: Date) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Scroll-offset sentinel for the status-bar hide.
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: HomeScrollOffsetKey.self,
                                    value: proxy.frame(in: .named("homeScroll")).minY)
                }
                .frame(height: 0)
                HeaderView(today: today, now: now) {
                    showSettings = true
                }
                NextPrayerCard(snapshot: snapshot)
                ScheduleCard(snapshot: snapshot)
                HStack(spacing: 12) {
                    DuoChip(title: L10n.t("monthlyCalendar"), detail: "") {
                        showCalendar = true
                    }
                    DuoChip(title: L10n.t("standBy"), detail: "") {
                        showStandBy = true
                    }
                }
                DailyVerseCard()
                QiblaCard()
                FooterView()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .coordinateSpace(name: "homeScroll")
        .onPreferenceChange(HomeScrollOffsetKey.self) { minY in
            statusBarHidden = minY < -24
        }
        .statusBarHidden(statusBarHidden)
        .sheet(isPresented: $showCalendar) {
            MonthlyCalendarView(snapshot: snapshot)
        }
    }

    /// iPhone Duo: two panes at 600 pt and wider (Pro Max / Plus
    /// landscape), per the approved design — a slim icon rail, the
    /// "Now" pane (next prayer, countdown, progress, verse), and the
    /// full-day schedule with the tomorrow strip and quick chips.
    /// Both panes scroll independently so large Dynamic Type sizes
    /// grow rows and scroll instead of shrinking text.

    // MARK: Minimal Mode layout (v2.0.0, workstream 10)

    /// Minimal Mode: the essentials only, at every width — next
    /// prayer + plain countdown, today's Adhan/Iqamah list, and the
    /// fasting times row on fasting days and throughout Ramadan.
    /// No verse card, no Qibla, no calendar, no tomorrow strip.
    /// Settings stays reachable from the header gear, as always.
    private func minimalLayout(snapshot: PrayerSnapshot, today: PrayerDay, now: Date) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HeaderView(today: today, now: now) {
                    showSettings = true
                }
                NextPrayerCard(snapshot: snapshot)
                if RamadanMode.isRamadan(on: now, timeZone: provider.calendar.timeZone)
                    || FastingSettings.isFastingDay(now, timeZone: provider.calendar.timeZone) {
                    FastingTimesRow(day: today)
                }
                ScheduleCard(snapshot: snapshot)
                FooterView()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
    }

    private func duoLayout(snapshot: PrayerSnapshot, today: PrayerDay, now: Date) -> some View {
        HStack(alignment: .top, spacing: 0) {
            duoRail
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DuoNowHeader(today: today, now: now)
                    NextPrayerCard(snapshot: snapshot)
                    DailyVerseCard()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .frame(width: 330)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if duoShowTomorrow {
                        DuoDayCard(
                            day: tomorrowDay(from: now),
                            title: L10n.t("tomorrowTimes"),
                            snapshot: snapshot
                        )
                    } else {
                        ScheduleCard(snapshot: snapshot)
                    }
                    DuoTomorrowStrip(now: now)
                    HStack(spacing: 12) {
                        DuoChip(title: L10n.t("qibla"),
                                detail: "\(Int(QiblaMath.bearingFromMosque.rounded()))°") {
                            showDuoCompass = true
                        }
                        DuoChip(title: L10n.t("widgetColors"),
                                detail: AppAppearance.effectiveTheme(for: .home).name) {
                            showSettings = true
                        }
                    }
                    QiblaCard()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .sheet(isPresented: $showDuoCompass) {
            QiblaCompassView()
        }
        .sheet(isPresented: $showCalendar) {
            MonthlyCalendarView(snapshot: snapshot)
        }
    }

    /// The Duo icon rail: Day / Qibla / Calendar (today⇄tomorrow) /
    /// Settings, one thumb-reach away without eating schedule width.
    private var duoRail: some View {
        VStack(spacing: 14) {
            DuoRailButton(systemImage: "sun.max.fill", label: L10n.t("today"),
                          isActive: !duoShowTomorrow) {
                duoShowTomorrow = false
            }
            DuoRailButton(systemImage: "location.north.circle.fill", label: L10n.t("qibla"),
                          isActive: false) {
                showDuoCompass = true
            }
                        DuoRailButton(systemImage: "moon.zzz.fill", label: L10n.t("standBy"),
                          isActive: false) {
                showStandBy = true
            }
DuoRailButton(systemImage: "calendar", label: L10n.t("monthlyCalendar"),
                          isActive: false) {
                showCalendar = true
            }
            Spacer()
            DuoRailButton(systemImage: "gearshape.fill", label: L10n.t("settings"),
                          isActive: false) {
                showSettings = true
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .frame(width: 60)
        .background(Color.black.opacity(0.18))
    }

    /// Proper iPad UI: a fixed left column (header, next prayer, verse)
    /// beside a scrolling two-column card grid — the iPhone column is
    /// never just stretched. All features stay reachable: Settings via
    /// the header gear, Qibla as a full card, Schedule with its own
    /// Today/Tomorrow toggle.
    private func iPadLayout(snapshot: PrayerSnapshot, today: PrayerDay, now: Date) -> some View {
        HStack(alignment: .top, spacing: 20) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HeaderView(today: today, now: now) {
                        showSettings = true
                    }
                    NextPrayerCard(snapshot: snapshot)
                    DailyVerseCard()
                    FooterView()
                }
                .padding(.vertical, 20)
            }
            .frame(width: 360)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ScheduleCard(snapshot: snapshot)
                    HStack(alignment: .top, spacing: 20) {
                        DuoTomorrowStrip(now: now)
                        DuoChip(title: L10n.t("widgetColors"),
                                detail: AppAppearance.effectiveTheme(for: .home).name) {
                            showSettings = true
                        }
                        DuoChip(title: L10n.t("monthlyCalendar"), detail: "") {
                            showCalendar = true
                        }
                        DuoChip(title: L10n.t("standBy"), detail: "") {
                            showStandBy = true
                        }
                    }
                    QiblaCard()
                }
                .padding(.vertical, 20)
                .padding(.trailing, 20)
            }
        }
        .padding(.leading, 20)
        .sheet(isPresented: $showCalendar) {
            MonthlyCalendarView(snapshot: snapshot)
        }
    }

    /// Tomorrow's PrayerDay via the provider's own calendar (DST-safe).
    private func tomorrowDay(from now: Date) -> PrayerDay {
        let start = provider.calendar.startOfDay(for: now)
        let next = provider.calendar.date(byAdding: .day, value: 1, to: start)
            ?? now.addingTimeInterval(86_400)
        return provider.day(for: next)
    }

    /// The Duo tomorrow strip: tomorrow's Fajr at a glance (plus the
    /// Khutbah time when tomorrow is Friday); tapping jumps the Duo
    /// right pane to tomorrow's full schedule.
    private func DuoTomorrowStrip(now: Date) -> some View {
        let tomorrow = tomorrowDay(from: now)
        let fajr = tomorrow.slots.first { $0.prayer == .fajr }
        return Button {
            duoShowTomorrow = true
        } label: {
            HStack(spacing: 10) {
                Text(L10n.t("tomorrow"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.onSurface)
                if let fajr {
                    Text("\(fajr.name) \(PrayerFormat.time(fajr.adhan))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.onSurfaceSecondary)
                }
                if tomorrow.isFriday {
                    Text("· \(L10n.t("jumuahBadge")) \(PrayerFormat.khutbahTime(on: tomorrow.date))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.onSurfaceSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.adaptiveGold)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .adaptiveCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }

    private func refreshWidgets() {
        provider.refreshCache()
        WidgetCenter.shared.reloadAllTimelines()
        AppServices.refresh()
    }

    /// Shows the What's New sheet once per version: a fresh install
    /// just records the current version; an update to a version with
    /// bundled notes presents the sheet and records it as seen.
    private func checkWhatsNew() {
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let key = "whatsnew.lastSeenVersion"
        let lastSeen = UserDefaults.standard.string(forKey: key)
        if lastSeen == nil {
            UserDefaults.standard.set(current, forKey: key)
        } else if lastSeen != current, WhatsNewView.entries(for: current) != nil {
            UserDefaults.standard.set(current, forKey: key)
            showWhatsNew = true
        }
    }
}


// MARK: - Fasting times row (v2.0.0)

/// Suhoor (Fajr) and Iftar (Maghrib) for a day — shown in Minimal
/// Mode on fasting days and every day in Ramadan, and wherever the
/// essentials are listed.
private struct FastingTimesRow: View {
    let day: PrayerDay

    var body: some View {
        HStack(spacing: 16) {
            Label {
                Text("\(L10n.t("suhoor")) · \(PrayerFormat.time(day.fajr))")
            } icon: {
                Image(systemName: "moon.haze.fill").foregroundStyle(AppAppearance.accent)
            }
            Spacer(minLength: 4)
            Label {
                Text("\(L10n.t("iftar")) · \(PrayerFormat.time(day.maghrib))")
            } icon: {
                Image(systemName: "sunset.fill").foregroundStyle(AppAppearance.accent)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Theme.onSurface)
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Theme.primary.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - StandBy (v2.0.0, feature 4)

/// In-app StandBy: a landscape nightstand view — the next prayer
/// huge, a live countdown, the rest of today beneath, all in the
/// app theme. The screen stays awake while it is up; tap anywhere
/// to leave. (True system StandBy is Apple's own mode for the Lock
/// Screen widgets; this is the in-app equivalent the brief asks
/// for, reached from the Duo rail, the iPad chips, or Settings.)
private struct StandByView: View {
    @Environment(\.dismiss) private var dismiss
    let snapshot: PrayerSnapshot

    var body: some View {
        let next = snapshot.next
        let palette = PartPalette(theme: AppAppearance.effectiveTheme(for: .liveActivity))
        ZStack {
            ColoredSurfaceBackground(palette: palette)
            VStack(spacing: 10) {
                Text(next.name)
                    .font(.system(size: 84, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(PrayerFormat.time(next.adhan))
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.textSecondary)
                Text(timerInterval: snapshot.date...next.adhan, countsDown: true)
                    .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(palette.accent)
                Text(snapshot.day.hijriDate)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(32)
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

// MARK: - Duo & iPad pieces (v2.0.0)

/// The Duo "Now" pane header: brand, Gregorian date, Hijri date —
/// the HeaderView content minus the settings gear (the rail has it).
private struct DuoNowHeader: View {
    let today: PrayerDay
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Image(systemName: "moon.stars.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.adaptiveGold)
                Text(MosqueInfo.name.uppercased())
                    .font(.caption.weight(.heavy))
                    .tracking(1.1)
                    .foregroundStyle(Theme.adaptiveGold)
                    .lineLimit(1)
            }
            Text(PrayerFormat.longDate(now))
                .font(.headline)
                .foregroundStyle(Theme.onSurface)
            Text(today.hijriDate)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.onSurfaceSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A full-day schedule card for an arbitrary day (the Duo right pane's
/// Tomorrow view): same rows as ScheduleCard, without its toggle.
private struct DuoDayCard: View {
    let day: PrayerDay
    let title: String
    let snapshot: PrayerSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.onSurface)
                Spacer(minLength: 8)
                Text(PrayerFormat.shortDate(day.date))
                    .font(.subheadline)
                    .foregroundStyle(Theme.onSurfaceSecondary)
            }
            HStack(spacing: 8) {
                Text(L10n.t("colPrayer")).frame(maxWidth: .infinity, alignment: .leading)
                Text(L10n.t("colAdhan")).frame(width: 86, alignment: .trailing)
                Text(L10n.t("colIqamah")).frame(width: 86, alignment: .trailing)
            }
            .font(.caption2.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(Theme.onSurfaceMuted)
            .padding(.horizontal, 12)
            VStack(spacing: 4) {
                ForEach(day.slots) { slot in
                    ScheduleRow(
                        slot: slot,
                        isNext: day.date == snapshot.day.date && snapshot.isNext(slot)
                    )
                }
            }
            if day.isFriday {
                Label(L10n.f("jumuahReplaces", PrayerFormat.khutbahTime(on: day.date)),
                      systemImage: "building.columns.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.adaptiveGold)
            }
            if RamadanMode.isRamadan(on: day.date, timeZone: PrayerProvider.standard.calendar.timeZone) {
                HStack(spacing: 10) {
                    Image(systemName: "moon.haze.fill")
                        .font(.body.weight(.semibold))
                        .frame(width: 26)
                        .foregroundStyle(Theme.adaptiveGold)
                    Text(L10n.t("taraweeh"))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.onSurface)
                    Text(L10n.t("estimate"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.onSurfaceMuted)
                    Spacer()
                    Text(PrayerFormat.time(RamadanMode.taraweehTime(for: day)))
                        .font(.body.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.onSurface)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveCard(cornerRadius: 26)
    }
}

/// One Duo quick chip (Qibla, Widget Colors): title + gold detail.
private struct DuoChip: View {
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.onSurface)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(detail)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.adaptiveGold)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.adaptiveGold)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .adaptiveCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }
}

/// One Duo rail button: icon tile, gold when active.
private struct DuoRailButton: View {
    let systemImage: String
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 40, height: 40)
                .background {
                    if isActive {
                        LinearGradient(colors: [Theme.lightGold, Theme.gold],
                                       startPoint: .top, endPoint: .bottom)
                    } else {
                        Theme.panelFill
                    }
                }
                .foregroundStyle(isActive ? Theme.primaryDeep : Theme.onSurfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Monthly calendar (v2.0.0, feature 2)

/// A full month of Adhan/Iqamah times: a day grid (Fajr + Maghrib in
/// each cell), tap a day to preview its full schedule, and share or
/// print the whole month as a text table through the share sheet.
/// On iPad/Duo widths the grid and the day preview sit side by side.
struct MonthlyCalendarView: View {
    let snapshot: PrayerSnapshot
    @Environment(\.dismiss) private var dismiss
    @State private var monthAnchor: Date = .now
    @State private var selectedDate: Date = .now
    @State private var daysByStart: [TimeInterval: PrayerDay] = [:]

    private var provider: PrayerProvider { .standard }

    private var monthDates: [Date] {
        let cal = provider.calendar
        guard let interval = cal.dateInterval(of: .month, for: monthAnchor),
              let range = cal.range(of: .day, in: .month, for: monthAnchor)
        else { return [] }
        return range.map { cal.date(byAdding: .day, value: $0 - 1, to: interval.start) ?? interval.start }
    }

    private var leadingBlanks: Int {
        let cal = provider.calendar
        guard let first = monthDates.first else { return 0 }
        return (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
    }

    private var selectedDay: PrayerDay? {
        daysByStart[provider.calendar.startOfDay(for: selectedDate).timeIntervalSince1970]
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                if proxy.size.width >= 700 {
                    HStack(alignment: .top, spacing: 20) {
                        grid
                            .frame(maxWidth: .infinity)
                        ScrollView { dayPreview }
                            .frame(width: 360)
                    }
                    .padding(20)
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            grid
                            dayPreview
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle(L10n.t("monthlyCalendar"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        shiftMonth(-1)
                    } label: { Image(systemName: "chevron.left") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        shiftMonth(1)
                    } label: { Image(systemName: "chevron.right") }
                }
                ToolbarItem(placement: .bottomBar) {
                    ShareLink(item: monthTableText) {
                        Label(L10n.t("shareMonth"), systemImage: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("done")) { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, AppLanguage.current.isRTL ? .rightToLeft : .leftToRight)
        .environment(\.locale, AppLanguage.current.locale)
        .onAppear { loadMonth() }
        .onChange(of: monthAnchor) { _, _ in loadMonth() }
    }

    private var grid: some View {
        VStack(spacing: 10) {
            Text(monthAnchor, format: .dateTime.month(.wide).year())
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear }
                ForEach(monthDates, id: \.self) { date in
                    dayCell(date)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let cal = provider.calendar
        let day = daysByStart[cal.startOfDay(for: date).timeIntervalSince1970]
        let isSelected = cal.isDate(date, inSameDayAs: selectedDate)
        let isToday = cal.isDateInToday(date)
        return Button {
            selectedDate = date
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(cal.component(.day, from: date))")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isSelected ? Theme.adaptiveGold : Theme.onSurface)
                if let day {
                    Text("\(Prayer.fajr.displayName) \(PrayerFormat.compactTime(day.fajr))")
                        .font(.caption2)
                        .foregroundStyle(Theme.onSurfaceSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("\(Prayer.maghrib.displayName) \(PrayerFormat.compactTime(day.maghrib))")
                        .font(.caption2)
                        .foregroundStyle(Theme.onSurfaceSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (isSelected ? Theme.adaptiveGold.opacity(0.22) : Theme.panelFill),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isToday ? Theme.adaptiveGold : Theme.hairline,
                                   lineWidth: isToday ? 1.5 : 0.5)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var dayPreview: some View {
        if let day = selectedDay {
            DuoDayCard(
                day: day,
                title: PrayerFormat.longDate(day.date),
                snapshot: snapshot
            )
        }
    }

    private func shiftMonth(_ delta: Int) {
        if let next = provider.calendar.date(byAdding: .month, value: delta, to: monthAnchor) {
            monthAnchor = next
        }
    }

    private func loadMonth() {
        var map: [TimeInterval: PrayerDay] = [:]
        for date in monthDates {
            let day = provider.computeDay(for: date)
            map[day.date.timeIntervalSince1970] = day
        }
        daysByStart = map
    }

    /// The whole month as a plain-text table (shared / printed).
    private var monthTableText: String {
        let title = monthAnchor.formatted(.dateTime.month(.wide).year())
        var lines = ["\(MosqueInfo.name) — \(title)", ""]
        lines.append("Date\tFajr\tSunrise\tDhuhr\tAsr\tMaghrib\tIsha")
        for date in monthDates {
            guard let day = daysByStart[provider.calendar.startOfDay(for: date).timeIntervalSince1970]
            else { continue }
            let row = [day.fajr, day.sunrise, day.dhuhr, day.asr, day.maghrib, day.isha]
                .map { PrayerFormat.compactTime($0) }
            lines.append("\(PrayerFormat.shortDate(date))\t" + row.joined(separator: "\t"))
        }
        lines.append("")
        lines.append("Iqamah: Fajr +20m · Dhuhr +10m · Asr +10m · Maghrib +5m · Isha +10m")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Header

private struct HeaderView: View {
    let today: PrayerDay
    let now: Date
    let onSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "moon.stars.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.adaptiveGold)
                    Text(L10n.t("greeting"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(MosqueInfo.name)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.primary)
                Text(today.hijriDate)
                    .font(.headline)
                    .foregroundStyle(Theme.adaptiveGold)
                Text(PrayerFormat.longDate(now))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button(action: onSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(Color(uiColor: .secondarySystemBackground), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("settings"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Next prayer card

private struct NextPrayerCard: View {
    let snapshot: PrayerSnapshot
    @ScaledMetric(relativeTo: .largeTitle) private var nameSize: CGFloat = 40
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 46

    var body: some View {
        let next = snapshot.next
        // Iqamah-first (v2.0.0): between a prayer's Adhan and its
        // Iqamah, the hero flips to that prayer and counts down to
        // the Iqamah instead of the following Adhan.
        let phase = PrayerProvider.standard.iqamahPhase(at: snapshot.date)
        let phaseIqamah = phase?.iqamah
        let caption = phase != nil
            ? L10n.t("iqamahNow")
            : (snapshot.isShowingTomorrow ? L10n.t("nextPrayerTomorrow") : L10n.t("nextPrayer"))
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(caption, systemImage: (phase ?? next).symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.adaptiveGold)
                Spacer()
                if RamadanMode.isRamadan(on: snapshot.date, timeZone: PrayerProvider.standard.calendar.timeZone),
                   (phase ?? next).prayer == .maghrib || (phase ?? next).prayer == .fajr {
                    Text(L10n.t((phase ?? next).prayer == .maghrib ? "iftar" : "suhoor"))
                        .font(.caption2.weight(.heavy))
                        .tracking(0.8)
                        .foregroundStyle(Theme.adaptiveGold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.adaptiveGold.opacity(0.25), in: Capsule())
                }
                if next.isJumuah {
                    Text(L10n.t("jumuahBadge"))
                        .font(.caption2.weight(.heavy))
                        .tracking(0.8)
                        .foregroundStyle(Theme.adaptiveGold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.adaptiveGold.opacity(0.25), in: Capsule())
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text((phase ?? next).name)
                    .font(.system(size: nameSize, weight: .bold))
                    .foregroundStyle(Theme.onSurface)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 8)
                Text(PrayerFormat.time(phaseIqamah ?? next.adhan))
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.onSurface)
                    .lineLimit(1)
            }
            if let phase, let phaseIqamah {
                Label(L10n.f("adhanWasAt", PrayerFormat.time(phase.adhan)), systemImage: "megaphone.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.onSurfaceSecondary)
                Label("\(L10n.t("nextPrayer")): \(next.name) \(L10n.t("at")) \(PrayerFormat.time(next.adhan))", systemImage: "arrow.forward.circle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.onSurfaceSecondary)
                VStack(alignment: .leading, spacing: 8) {
                    Text(timerInterval: phase.adhan...phaseIqamah, countsDown: true)
                        .font(.system(size: countdownSize, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.adaptiveGold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    GoldProgressBar(range: phase.adhan...phaseIqamah)
                    Text(L10n.f("untilIqamah", phase.name))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.onSurfaceMuted)
                    if IqamahCountdownSettings.leaveLeadMinutes > 0,
                       snapshot.date >= phaseIqamah.addingTimeInterval(-Double(IqamahCountdownSettings.leaveLeadMinutes) * 60) {
                        Label(L10n.t("timeToLeave"), systemImage: "figure.walk")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.adaptiveGold)
                    }
                }
            } else {
                if let iqamah = next.iqamah {
                    Label("\(next.iqamahLabel) \(L10n.t("at")) \(PrayerFormat.time(iqamah))", systemImage: "person.3.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.onSurfaceSecondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(timerInterval: snapshot.countdownRange, countsDown: true)
                        .font(.system(size: countdownSize, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.adaptiveGold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    GoldProgressBar(range: snapshot.progressRange)
                    Text(L10n.f("untilAdhan", next.name))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.onSurfaceMuted)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveCard(cornerRadius: 26)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    /// "Maghrib in 42 minutes" — what VoiceOver announces for the card.
    private var accessibilitySummary: String {
        if let phase = PrayerProvider.standard.iqamahPhase(at: snapshot.date),
           let iqamah = phase.iqamah {
            let minutes = max(0, Int(iqamah.timeIntervalSince(snapshot.date) / 60))
            return L10n.f("inMinutes", phase.iqamahLabel + " " + phase.name, minutes)
        }
        let minutes = max(0, Int(snapshot.next.adhan.timeIntervalSince(snapshot.date) / 60))
        return L10n.f("inMinutes", snapshot.next.name, minutes)
    }
}

// MARK: - Schedule card

private struct ScheduleCard: View {
    let snapshot: PrayerSnapshot

    /// Today/Tomorrow preview toggle (v1.5). Nil follows the snapshot
    /// (today, switching to tomorrow after Isha); tapping a segment
    /// pins the card to that day until the snapshot's day catches up.
    @State private var showTomorrow: Bool?

    private var provider: PrayerProvider { .standard }

    private var todayDay: PrayerDay { provider.day(for: snapshot.date) }

    private var displayedDay: PrayerDay {
        let wantTomorrow = showTomorrow ?? snapshot.isShowingTomorrow
        if wantTomorrow == snapshot.isShowingTomorrow { return snapshot.day }
        if wantTomorrow {
            let next = provider.calendar.date(byAdding: .day, value: 1, to: todayDay.date) ?? todayDay.date
            return provider.computeDay(for: next)
        }
        return todayDay
    }

    private var isDisplayingSnapshotDay: Bool {
        displayedDay.date == snapshot.day.date
    }

    var body: some View {
        let day = displayedDay
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(day.date == todayDay.date ? L10n.t("todayTimes") : L10n.t("tomorrowTimes"))
                    .font(.headline)
                    .foregroundStyle(Theme.onSurface)
                Spacer(minLength: 8)
                Text(PrayerFormat.shortDate(day.date))
                    .font(.subheadline)
                    .foregroundStyle(Theme.onSurfaceSecondary)
            }
            Picker("", selection: Binding(
                get: { showTomorrow ?? snapshot.isShowingTomorrow },
                set: { showTomorrow = $0 }
            )) {
                Text(L10n.t("today")).tag(false)
                Text(L10n.t("tomorrow")).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            HStack(spacing: 8) {
                Text(L10n.t("colPrayer")).frame(maxWidth: .infinity, alignment: .leading)
                Text(L10n.t("colAdhan")).frame(width: 86, alignment: .trailing)
                Text(L10n.t("colIqamah")).frame(width: 86, alignment: .trailing)
            }
            .font(.caption2.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(Theme.onSurfaceMuted)
            .padding(.horizontal, 12)
            VStack(spacing: 4) {
                ForEach(day.slots) { slot in
                    ScheduleRow(slot: slot, isNext: isDisplayingSnapshotDay && snapshot.isNext(slot))
                }
            }
            if day.isFriday {
                Label(L10n.f("jumuahReplaces", PrayerFormat.khutbahTime(on: day.date)), systemImage: "building.columns.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.adaptiveGold)
            }
            if RamadanMode.isRamadan(on: day.date, timeZone: PrayerProvider.standard.calendar.timeZone) {
                HStack(spacing: 10) {
                    Image(systemName: "moon.haze.fill")
                        .font(.body.weight(.semibold))
                        .frame(width: 26)
                        .foregroundStyle(Theme.adaptiveGold)
                    Text(L10n.t("taraweeh"))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.onSurface)
                    Text(L10n.t("estimate"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.onSurfaceMuted)
                    Spacer()
                    Text(PrayerFormat.time(RamadanMode.taraweehTime(for: day)))
                        .font(.body.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.onSurface)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveCard(cornerRadius: 26)
    }
}

private struct ScheduleRow: View {
    let slot: PrayerSlot
    let isNext: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: slot.symbolName)
                    .font(.body.weight(.semibold))
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(slot.name)
                        .font(.body.weight(isNext ? .bold : .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if slot.isJumuah {
                        Text(L10n.t("khutbahShown"))
                            .font(.caption2)
                            .foregroundStyle(Theme.onSurfaceMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(PrayerFormat.time(slot.adhan))
                .frame(width: 86, alignment: .trailing)
            Text(slot.iqamah.map { PrayerFormat.time($0) } ?? "—")
                .frame(width: 86, alignment: .trailing)
        }
        .font(.body.weight(isNext ? .bold : .regular).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .foregroundStyle(rowColor)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background {
            if isNext {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.adaptiveGold.opacity(0.2))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Theme.adaptiveGold.opacity(0.65), lineWidth: 1)
                    }
            }
        }
    }

    private var rowColor: Color {
        if isNext { return Theme.adaptiveGold }
        return slot.prayer == .sunrise ? Theme.onSurfaceMuted : Theme.onSurface
    }
}

// MARK: - Footer

private struct FooterView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(MosqueInfo.address, systemImage: "mappin.and.ellipse")
            Label(L10n.f("jumuahWeeklyAt", PrayerFormat.khutbahTime(on: .now)), systemImage: "building.columns")
            Label(L10n.t("footerPrivacy"), systemImage: "lock.shield.fill")
            Text(L10n.t("footerCalc"))
                .font(.caption)
                .padding(.top, 4)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Styling

/// Page background (v1.0.5, per the user's request): stays PURE BLACK in
/// Dark Mode and PURE WHITE in Light Mode, with only a faint wash of the
/// main theme color at the top so the page still feels like the app.
private struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            colorScheme == .dark ? Color.black : Color.white
            LinearGradient(
                colors: [Theme.primary.opacity(colorScheme == .dark ? 0.35 : 0.07), Color.clear],
                startPoint: .top, endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}

private struct ThemeButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(prominent ? Theme.primaryDeep : Theme.onPrimaryText)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(prominent
                        ? AnyShapeStyle(LinearGradient(colors: [Theme.lightGold, Theme.gold], startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(LinearGradient(colors: [Theme.primaryBright, Theme.primary, Theme.primaryDeep], startPoint: .top, endPoint: .bottom)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.adaptiveGold.opacity(prominent ? 0 : 0.6), lineWidth: 1)
            }
            .shadow(color: Theme.primaryDeep.opacity(0.25), radius: 8, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Card surface (v1.0.5): a gradient of the user's main theme color in
/// Dark Mode, a clean white card with a main-color hairline in Light
/// Mode. Text on it uses the Theme.onSurface* colors, which flip with
/// the appearance and pass a contrast guard to stay readable in both.
private struct AdaptiveCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                CardSurfaceBackground()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark
                            ? AnyShapeStyle(LinearGradient(
                                colors: [Theme.adaptiveGold.opacity(0.45), Color.white.opacity(0.08)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            : AnyShapeStyle(Theme.primary.opacity(0.25)),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: colorScheme == .dark ? Theme.primaryDeep.opacity(0.35) : Color.black.opacity(0.10),
                radius: 16, x: 0, y: 8
            )
    }
}

private extension View {
    func adaptiveCard(cornerRadius: CGFloat) -> some View {
        modifier(AdaptiveCardModifier(cornerRadius: cornerRadius))
    }
}

#Preview {
    ContentView()
}

// MARK: - Settings (v1.0.5)

/// The dedicated Settings page: appearance (System/Light/Dark), theme
/// colors (main color, accent, text — each with preset swatches and a
/// full color picker), curated themes, save-your-own themes, the app
/// icon picker, per-prayer alert toggles (including Sunrise), privacy
/// notes, and Reset to Defaults. Everything is stored in the App Group,
/// so the Home Screen widgets and the Live Activity follow along.
private struct SettingsView: View {
    /// Called on every settings change so the main screen behind the
    /// sheet rebuilds immediately (v1.1.1 — see ContentView).
    let onSettingsChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// In-app update reminder state (v1.7.0), owned by ContentView.
    @EnvironmentObject private var updateChecker: UpdateChecker

    private static var suite: UserDefaults {
        UserDefaults(suiteName: PrayerProvider.appGroupIdentifier) ?? .standard
    }

    @AppStorage(AppAppearance.modeKey, store: UserDefaults(suiteName: PrayerProvider.appGroupIdentifier))
    private var modeRaw: String = AppAppearance.Mode.system.rawValue
    @AppStorage(AppAppearance.primaryKey, store: UserDefaults(suiteName: PrayerProvider.appGroupIdentifier))
    private var primaryHex: Int = Int(AppAppearance.defaultPrimaryHex)
    @AppStorage(AppAppearance.accentKey, store: UserDefaults(suiteName: PrayerProvider.appGroupIdentifier))
    private var accentHex: Int = Int(AppAppearance.defaultAccentHex)
    @AppStorage(AppAppearance.textKey, store: UserDefaults(suiteName: PrayerProvider.appGroupIdentifier))
    private var textHex: Int = Int(AppAppearance.defaultTextHex)

    @AppStorage(AppLanguage.storageKey, store: UserDefaults(suiteName: PrayerProvider.appGroupIdentifier))
    private var languageCode: String = AppLanguage.en.rawValue
    @AppStorage(AppTextSize.storageKey, store: UserDefaults(suiteName: PrayerProvider.appGroupIdentifier))
    private var textSizeRaw: String = AppTextSize.standard.rawValue
    @AppStorage(AdhanSound.storageKey, store: UserDefaults(suiteName: PrayerProvider.appGroupIdentifier))
    private var soundRaw: String = AdhanSound.default.rawValue

    /// The master alert switches, moved here from the Home screen's
    /// Alerts card in v1.4. They live in UserDefaults.standard (the
    /// store AlertSettings reads), NOT the App Group suite.
    @AppStorage(AlertSettings.notificationsKey) private var notificationsOn = true
    @AppStorage(AlertSettings.liveActivityKey) private var liveActivityOn = true
    @AppStorage(AlertSettings.reminderKey) private var reminderOn = true
    @AppStorage(AlertSettings.reminderLeadKey) private var reminderLead = 10
    @AppStorage(AlertSettings.jumuahReminderKey) private var jumuahReminderOn = true
    @State private var notificationsDenied = false

    @AppStorage(AppAppearance.widgetColorModeKey, store: UserDefaults(suiteName: PrayerProvider.appGroupIdentifier))
    private var widgetColorModeRaw: String = AppAppearance.WidgetColorMode.match.rawValue
    /// Bumped whenever a per-part theme is picked, so the (non-observed)
    /// stored part themes re-read and the swatches repaint.
    @State private var partThemesRevision = 0

    @AppStorage(HijriOffset.storageKey, store: UserDefaults(suiteName: PrayerProvider.appGroupIdentifier))
    private var hijriOffset: Int = 0

    @AppStorage(CompassSettings.hapticsKey) private var hapticsOn = true

    @State private var savedThemes: [AppAppearance.ThemeChoice] = AppAppearance.savedThemes
    @State private var showSaveTheme = false
    @State private var showRestartPrompt = false
    @State private var newThemeName = ""
    @State private var currentIconName: String? = nil
    @State private var iconError: String? = nil
    @State private var showResetConfirm = false
    @State private var resetGeneration = 0

    var body: some View {
        NavigationStack {
            Form {
                updateSection
                languageSection
                appearanceSection
                minimalModeSection
                colorsSection
                themesSection
                widgetColorsSection
                ramadanSection
                fastingSection
                textSizeSection
                iconSection
                hijriSection
                qiblaSection
                alertsSection
                iqamahCountdownSection
                siriSection
                prayerAlertsSection
                soundSection
                prayerSoundsSection
                privacySection
                backupSection
                resetSection
                versionSection
            }
            .id(resetGeneration)
            .navigationTitle(L10n.t("settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("done")) { dismiss() }
                }
            }
            .preferredColorScheme(AppAppearance.Mode(rawValue: modeRaw)?.colorScheme)
            .environment(\.layoutDirection, AppLanguage.current.isRTL ? .rightToLeft : .leftToRight)
            .environment(\.locale, AppLanguage.current.locale)
            .dynamicTypeSize(AppTextSize.current.dynamicTypeSize)
            .onAppear { currentIconName = UIApplication.shared.alternateIconName }
            .onChange(of: modeRaw) { _, _ in settingsChanged() }
            .onChange(of: primaryHex) { _, _ in settingsChanged() }
            .onChange(of: accentHex) { _, _ in settingsChanged() }
            .onChange(of: textHex) { _, _ in settingsChanged() }
            .onChange(of: languageCode) { _, _ in settingsChanged() }
            .onChange(of: widgetColorModeRaw) { _, _ in settingsChanged() }
            .onChange(of: textSizeRaw) { _, _ in settingsChanged() }
            .onChange(of: soundRaw) { _, _ in settingsChanged() }
            .alert(L10n.t("saveThemeTitle"), isPresented: $showSaveTheme) {
                TextField(L10n.t("themeName"), text: $newThemeName)
                Button(L10n.t("save")) { saveCurrentTheme() }
                Button(L10n.t("cancel"), role: .cancel) { newThemeName = "" }
            } message: {
                Text(L10n.t("saveThemeMessage"))
            }
            .alert(L10n.t("restartRequired"), isPresented: $showRestartPrompt) {
                Button(L10n.t("later"), role: .cancel) {}
                Button(L10n.t("restart")) { restartApp() }
            } message: {
                Text(L10n.t("restartMessage"))
            }
            .confirmationDialog(
                L10n.t("resetConfirm"),
                isPresented: $showResetConfirm,
                titleVisibility: .visible
            ) {
                Button(L10n.t("reset"), role: .destructive) { resetToDefaults() }
                Button(L10n.t("cancel"), role: .cancel) {}
            }
        }
    }

    // MARK: Sections

    private var appearanceSection: some View {
        Section {
            Picker(L10n.t("appearance"), selection: $modeRaw) {
                ForEach(AppAppearance.Mode.allCases, id: \.rawValue) { mode in
                    Text(L10n.t("mode.\(mode.rawValue)")).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text(L10n.t("appearance"))
        } footer: {
            Text(L10n.t("appearanceFooter"))
        }
    }

    private var colorsSection: some View {
        Section {
            ColorSettingRow(title: L10n.t("mainColor"), caption: L10n.t("mainColorCaption"),
                            presets: AppAppearance.primaryPresets, hexValue: $primaryHex)
            ColorSettingRow(title: L10n.t("accentColor"), caption: L10n.t("accentColorCaption"),
                            presets: AppAppearance.presets, hexValue: $accentHex)
            ColorSettingRow(title: L10n.t("textColor"), caption: L10n.t("textColorCaption"),
                            presets: AppAppearance.textPresets, hexValue: $textHex)
        } header: {
            Text(L10n.t("themeColors"))
        } footer: {
            Text(L10n.t("colorsFooter"))
        }
    }

    // MARK: Minimal Mode (v2.0.0, workstream 10)

    @AppStorage(MinimalMode.key, store: UserDefaults(suiteName: PrayerProvider.appGroupIdentifier))
    private var minimalModeOn = false

    private var minimalModeSection: some View {
        Section {
            Toggle(L10n.t("minimalMode"), isOn: $minimalModeOn)
        } header: {
            Text(L10n.t("minimalMode"))
        } footer: {
            Text(L10n.t("minimalModeFooter"))
        }
        .onChange(of: minimalModeOn) { _, _ in settingsChanged() }
    }

    // MARK: Sunnah fasting (v2.0.0, workstream 9)

    @AppStorage(FastingSettings.mondayThursdayKey, store: UserDefaults(suiteName: PrayerProvider.appGroupIdentifier))
    private var fastingMonThu = false
    @AppStorage(FastingSettings.whiteDaysKey, store: UserDefaults(suiteName: PrayerProvider.appGroupIdentifier))
    private var fastingWhiteDays = false

    private var fastingSection: some View {
        Section {
            Toggle(L10n.t("fastingMonThu"), isOn: $fastingMonThu)
            Toggle(L10n.t("fastingWhiteDays"), isOn: $fastingWhiteDays)
        } header: {
            Text(L10n.t("fasting"))
        } footer: {
            Text(L10n.t("fastingFooter"))
        }
        .onChange(of: fastingMonThu) { _, _ in settingsChanged() }
        .onChange(of: fastingWhiteDays) { _, _ in settingsChanged() }
    }

    // MARK: Siri & Controls (v2.0.0, feature 7)

    @State private var siriTipVisible = true

    private var siriSection: some View {
        Section {
            SiriTipView(intent: NextPrayerIntent(), isVisible: $siriTipVisible)
            SiriTipView(intent: SilenceNextAlertIntent(), isVisible: $siriTipVisible)
        } header: {
            Text(L10n.t("siri"))
        } footer: {
            Text(L10n.t("siriFooter"))
        }
    }

    // MARK: Settings backup (v2.0.0, workstream 9)

    @State private var showBackupImporter = false
    @State private var backupMessage: String?

    /// The export file, rebuilt on each appearance of the section.
    private var backupExportURL: URL? {
        guard let data = SettingsBackup.exportData() else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AlRashidSettingsBackup.json")
        try? data.write(to: url, options: .atomic)
        return url
    }

    private var backupSection: some View {
        Section {
            if SettingsBackup.cloudAvailable {
                Button(L10n.t("backupToICloud")) {
                    backupMessage = SettingsBackup.backupToCloud()
                        ? L10n.t("backupDone") : L10n.t("actionFailed")
                }
                Button(L10n.t("restoreFromICloud")) {
                    let ok = SettingsBackup.restoreFromCloud()
                    backupMessage = ok ? L10n.t("restoreDone") : L10n.t("actionFailed")
                    if ok { settingsChanged(); resetGeneration += 1 }
                }
                if let last = SettingsBackup.lastCloudBackup {
                    Text(L10n.f("lastBackup", last.formatted(date: .abbreviated, time: .shortened)))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text(L10n.t("noBackupYet"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(L10n.t("iCloudUnavailable"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let url = backupExportURL {
                ShareLink(item: url) {
                    Label(L10n.t("exportSettings"), systemImage: "square.and.arrow.up")
                }
            }
            Button {
                showBackupImporter = true
            } label: {
                Label(L10n.t("importSettings"), systemImage: "square.and.arrow.down")
            }
            if let backupMessage {
                Text(backupMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(L10n.t("backup"))
        } footer: {
            Text(L10n.t("backupFooter"))
        }
        .fileImporter(isPresented: $showBackupImporter,
                      allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result,
                  url.startAccessingSecurityScopedResource(),
                  let data = try? Data(contentsOf: url) else {
                backupMessage = L10n.t("actionFailed")
                return
            }
            url.stopAccessingSecurityScopedResource()
            let ok = SettingsBackup.importData(data)
            backupMessage = ok ? L10n.t("restoreDone") : L10n.t("actionFailed")
            if ok { settingsChanged(); resetGeneration += 1 }
        }
    }
    // MARK: Ramadan (v2.0.0)

    @AppStorage(RamadanMode.taraweehOffsetKey, store: UserDefaults(suiteName: PrayerProvider.appGroupIdentifier))
    private var taraweehOffset = 15

    private var ramadanSection: some View {
        Section {
            Picker(L10n.t("taraweehAfterIsha"), selection: $taraweehOffset) {
                ForEach(RamadanMode.taraweehOptions, id: \.self) { minutes in
                    Text(L10n.f("taraweehOffset", minutes)).tag(minutes)
                }
            }
        } header: {
            Text(L10n.t("ramadan"))
        } footer: {
            Text(L10n.t("ramadanFooter"))
        }
        .onChange(of: taraweehOffset) { _, _ in settingsChanged() }
    }

    // MARK: Widget colors (v2.0.0)

    /// Settings → Appearance → Widget Colors: Match (default) makes
    /// every widget surface follow the app theme; Separate gives the
    /// Home widgets, Lock Screen widgets and Live Activity their own
    /// theme each, picked from the same presets (plus any saved theme).
    private var widgetColorsSection: some View {
        Section {
            Picker(L10n.t("widgetColors"), selection: $widgetColorModeRaw) {
                Text(L10n.t("widgetColorMode.match"))
                    .tag(AppAppearance.WidgetColorMode.match.rawValue)
                Text(L10n.t("widgetColorMode.separate"))
                    .tag(AppAppearance.WidgetColorMode.separate.rawValue)
            }
            .pickerStyle(.segmented)
            if widgetColorModeRaw == AppAppearance.WidgetColorMode.separate.rawValue {
                ForEach(AppAppearance.WidgetPart.allCases, id: \.rawValue) { part in
                    partThemePicker(part)
                }
            }
        } header: {
            Text(L10n.t("widgetColors"))
        } footer: {
            Text(L10n.t(widgetColorModeRaw == AppAppearance.WidgetColorMode.separate.rawValue
                        ? "widgetColorsFooterSeparate" : "widgetColorsFooterMatch"))
        }
    }

    /// One part's theme picker in Separate mode: the part's current
    /// effective theme name plus a swatch row — the preset themes and
    /// the user's saved themes, with an "App theme" reset swatch.
    private func partThemePicker(_ part: AppAppearance.WidgetPart) -> some View {
        let stored = AppAppearance.storedPartTheme(for: part)
        let effective = AppAppearance.effectiveTheme(for: part)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.t("widgetPart.\(part.rawValue)"))
                    .font(.body.weight(.semibold))
                Spacer(minLength: 8)
                Text(stored?.name ?? L10n.t("appTheme"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    partThemeSwatch(part: part, theme: nil, isActive: stored == nil)
                    ForEach(AppAppearance.presetThemes + savedThemes) { theme in
                        partThemeSwatch(
                            part: part, theme: theme,
                            isActive: stored.map { sameTheme($0, theme) } ?? false
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            // Live mini preview in the part's own colors.
            HStack(spacing: 8) {
                Image(systemName: "moon.stars.fill")
                Text(Prayer.fajr.displayName)
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(previewTime)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            .foregroundStyle(PartPalette(theme: effective).text)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                LinearGradient(
                    colors: [PartPalette(theme: effective).primaryBright,
                             PartPalette(theme: effective).primary],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .id("\(part.rawValue)-\(partThemesRevision)")
        .padding(.vertical, 2)
    }

    /// A two-tone swatch (primary disc, accent ring) for one part-theme
    /// choice; a nil theme is the "follow the app theme" reset.
    private func partThemeSwatch(
        part: AppAppearance.WidgetPart,
        theme: AppAppearance.ThemeChoice?,
        isActive: Bool
    ) -> some View {
        let primary = theme.map { Color(hex: $0.primaryHex) } ?? Theme.primary
        let accent = theme.map { Color(hex: $0.accentHex) } ?? Theme.adaptiveGold
        return Button {
            AppAppearance.setPartTheme(theme, for: part)
            partThemesRevision += 1
            settingsChanged()
        } label: {
            ZStack {
                Circle()
                    .fill(primary)
                    .frame(width: 34, height: 34)
                    .overlay { Circle().strokeBorder(accent, lineWidth: 3) }
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme?.name ?? L10n.t("appTheme"))
    }

    private func sameTheme(_ a: AppAppearance.ThemeChoice, _ b: AppAppearance.ThemeChoice) -> Bool {
        a.primaryHex == b.primaryHex && a.accentHex == b.accentHex
            && a.textHex == b.textHex && a.modeRaw == b.modeRaw
    }

    private var themesSection: some View {
        Section {
            themePreviewCard
            ForEach(AppAppearance.presetThemes) { theme in
                ThemeChoiceRow(theme: theme, isSaved: false, isActive: isActiveTheme(theme)) { apply(theme) }
            }
            if !savedThemes.isEmpty {
                ForEach(savedThemes) { theme in
                    ThemeChoiceRow(theme: theme, isSaved: true, isActive: isActiveTheme(theme)) { apply(theme) }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { deleteSavedTheme(theme) } label: {
                                Label(L10n.t("delete"), systemImage: "trash")
                            }
                        }
                }
            }
            Button {
                newThemeName = ""
                showSaveTheme = true
            } label: {
                Label(L10n.t("saveCurrentTheme"), systemImage: "bookmark.fill")
            }
        } header: {
            Text(L10n.t("themes"))
        } footer: {
            Text(L10n.t("themesFooter"))
        }
    }

    private var iconSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(Self.iconOptions) { option in
                    Button { setIcon(option) } label: {
                        VStack(spacing: 6) {
                            Image(option.previewImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 62, height: 62)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(
                                            currentIconName == option.alternateName ? Color.accentColor : Color.primary.opacity(0.15),
                                            lineWidth: currentIconName == option.alternateName ? 2.5 : 1
                                        )
                                }
                            Text(L10n.t(option.nameKey))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            if let iconError {
                Text(iconError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text(L10n.t("appIcon"))
        } footer: {
            Text(L10n.t("appIconFooter"))
        }
    }

    private var languageSection: some View {
        Section {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    languageCode = language.rawValue
                } label: {
                    HStack {
                        Text(language.nativeName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if languageCode == language.rawValue {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.adaptiveGold)
                        }
                    }
                    // The whole row is the tap target — the text, the
                    // empty space beside it, everything (v1.1.1).
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text(L10n.t("language"))
        } footer: {
            Text(L10n.t("languageFooter"))
        }
    }

    private var textSizeSection: some View {
        Section {
            Picker(L10n.t("textSize"), selection: $textSizeRaw) {
                ForEach(AppTextSize.allCases) { size in
                    Text(L10n.t(size.l10nKey)).tag(size.rawValue)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text(L10n.t("textSize"))
        } footer: {
            Text(L10n.t("textSizeFooter"))
        }
    }

    private var soundSection: some View {
        Section {
            ForEach(AdhanSound.allCases) { sound in
                Button {
                    soundRaw = sound.rawValue
                } label: {
                    HStack {
                        Text(L10n.t(sound.l10nKey))
                            .foregroundStyle(.primary)
                        Spacer()
                        if soundRaw == sound.rawValue {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.adaptiveGold)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text(L10n.t("alertSound"))
        } footer: {
            Text(L10n.t("alertSoundFooter"))
        }
    }

    /// Per-prayer sound overrides (v1.8.0): each prayer can follow
    /// the app-wide sound or take its own — including Silent.
    private var prayerSoundsSection: some View {
        Section {
            ForEach(Prayer.allCases) { prayer in
                PrayerSoundRow(prayer: prayer) {
                    AppServices.alertPreferencesChanged()
                }
            }
        } header: {
            Text(L10n.t("prayerSounds"))
        } footer: {
            Text(L10n.t("prayerSoundsFooter"))
        }
    }

    /// Master alert switches (v1.4 — moved from the Home screen's
    /// Alerts card): Adhan notifications on/off with the
    /// permission-denied warning, and the Live Activity on/off.
    /// v1.5.2: the Live Activity push-registration state shown in the
    /// Alerts section — the server handoff is verifiable on the phone
    /// instead of failing silently as it did in v1.3–1.5.1.
    private var pushStatusText: String {
        switch LiveActivityPushSync.status {
        case .registered(let date):
            return L10n.t("pushConnected") + " · "
                + date.formatted(date: .omitted, time: .shortened)
        case .pending, .failed:
            return L10n.t("pushPending")
        case .localOnly:
            return L10n.t("pushLocalOnly")
        }
    }

    /// App version, pinned to the very bottom of Settings (v1.8.0).
    /// Read live from the bundle so it can never go stale.
    private var versionSection: some View {
        Section {
            Text("\(L10n.t("version")) \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
        }
    }

    /// In-app update reminder (v1.7.0): pinned at the top of Settings
    /// while a newer public build than the installed one is advertised
    /// and the user has not dismissed that build.
    @ViewBuilder
    private var updateSection: some View {
        if let update = updateChecker.updateToShow {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.t("updateAvailable"), systemImage: "arrow.down.circle.fill")
                        .font(.headline)
                    Text(L10n.f("updateAvailableBody", update.version))
                        .font(.subheadline)
                    if let notes = update.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        Button(L10n.t("updateNow")) {
                            if let url = URL(string: update.url) {
                                openURL(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        Button(L10n.t("updateLater")) {
                            updateChecker.dismiss()
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: Iqamah-first countdown (v2.0.0)

    @AppStorage(IqamahCountdownSettings.enabledKey, store: UserDefaults(suiteName: PrayerProvider.appGroupIdentifier))
    private var iqamahFirstEnabled = true
    @AppStorage(IqamahCountdownSettings.leaveLeadKey, store: UserDefaults(suiteName: PrayerProvider.appGroupIdentifier))
    private var leaveLeadMinutes = 0

    private var iqamahCountdownSection: some View {
        Section {
            Toggle(L10n.t("iqamahFirst"), isOn: $iqamahFirstEnabled)
            if iqamahFirstEnabled {
                Picker(L10n.t("leaveNudge"), selection: $leaveLeadMinutes) {
                    Text(L10n.t("leaveOff")).tag(0)
                    ForEach([5, 10, 15, 20], id: \.self) { minutes in
                        Text(L10n.f("leaveMinutes", minutes)).tag(minutes)
                    }
                }
            }
        } header: {
            Text(L10n.t("iqamahFirst"))
        } footer: {
            Text(L10n.t("iqamahFirstFooter"))
        }
        .onChange(of: iqamahFirstEnabled) { _, _ in settingsChanged() }
        .onChange(of: leaveLeadMinutes) { _, _ in settingsChanged() }
    }

    private var alertsSection: some View {
        Section {
            Toggle(isOn: $notificationsOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("adhanNotifications"))
                    Text(L10n.t("notificationsBody"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: notificationsOn) { _, isOn in
                AppServices.notificationsToggled(on: isOn)
                refreshDeniedState()
            }

            if notificationsOn && notificationsDenied {
                Label(L10n.t("notificationsOffWarning"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.adaptiveGold)
            }

            Toggle(isOn: $liveActivityOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("liveActivity"))
                    Text(L10n.t("liveActivityBody"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: liveActivityOn) { _, isOn in
                AppServices.liveActivityToggled(on: isOn)
            }

            // v1.5.2: the Live Activity push-registration state, so a
            // broken server handoff is visible instead of silent.
            if liveActivityOn {
                HStack {
                    Text(L10n.t("pushUpdates"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(pushStatusText)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }

            Toggle(isOn: $reminderOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("reminder"))
                    Text(L10n.t("reminderBody"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: reminderOn) { _, _ in
                AppServices.alertPreferencesChanged()
            }

            if reminderOn {
                Picker(L10n.t("reminder"), selection: $reminderLead) {
                    ForEach([5, 10, 15, 20, 30], id: \.self) { minutes in
                        Text(L10n.f("minutesBefore", minutes)).tag(minutes)
                    }
                }
                .onChange(of: reminderLead) { _, _ in
                    AppServices.alertPreferencesChanged()
                }
            }

            Toggle(isOn: $jumuahReminderOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("jumuahReminder"))
                    Text(L10n.t("jumuahReminderBody"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: jumuahReminderOn) { _, _ in
                AppServices.alertPreferencesChanged()
            }
        } header: {
            Text(L10n.t("alerts"))
        }
        .task { refreshDeniedState() }
    }

    /// Hijri date adjustment (v1.5): −1/0/+1 days on the displayed
    /// Hijri date. It is part of the provider's cache signature, so
    /// the change recomputes the cached day; reload widgets to match.
    private var hijriSection: some View {
        Section {
            Picker("", selection: $hijriOffset) {
                Text("-1").tag(-1)
                Text("0").tag(0)
                Text("+1").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: hijriOffset) { _, _ in
                settingsChanged()
                PrayerProvider.standard.refreshCache()
                WidgetCenter.shared.reloadAllTimelines()
            }
        } header: {
            Text(L10n.t("hijriDate"))
        } footer: {
            Text(L10n.t("hijriOffsetFooter"))
        }
    }

    private func refreshDeniedState() {
        Task { notificationsDenied = await AdhanNotifications.authorizationDenied() }
    }

    /// Qibla compass preferences (v1.5.1): the facing haptic toggle.
    private var qiblaSection: some View {
        Section {
            Toggle(isOn: $hapticsOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("haptics"))
                    Text(L10n.t("hapticsBody"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(L10n.t("qibla"))
        }
    }

    private var prayerAlertsSection: some View {
        Section {
            ForEach(Prayer.allCases) { prayer in
                PrayerAlertRow(prayer: prayer) { settingsChanged() }
            }
        } header: {
            Text(L10n.t("prayerAlerts"))
        } footer: {
            Text(L10n.t("prayerAlertsFooter"))
        }
    }

    private var privacySection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("noDataCollected"))
                    Text(L10n.t("noDataBody"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "hand.raised.fill")
            }
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("staysOnDevice"))
                    Text(L10n.t("staysOnDeviceBody"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "lock.shield.fill")
            }
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("noExternalLinks"))
                    Text(L10n.t("noExternalLinksBody"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "eye.slash.fill")
            }
        } header: {
            Text(L10n.t("privacy"))
        }
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                Label(L10n.t("reset"), systemImage: "arrow.counterclockwise")
            }
        } footer: {
            Text(L10n.t("resetFooter"))
        }
    }

    // MARK: Actions

    private func settingsChanged() {
        onSettingsChanged()
        PrayerProvider.standard.refreshCache()
        WidgetCenter.shared.reloadAllTimelines()
        AppServices.refresh()
    }

    /// A miniature next-prayer card in the current colors. It redraws
    /// the instant a theme or color changes, so the effect of a tap is
    /// visible right here in Settings — no need to close the page and
    /// reopen the app to see the new theme.
    private var themePreviewCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("nextPrayerPreview"))
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(Theme.onPrimaryText.opacity(0.75))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Prayer.fajr.displayName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.onPrimaryText)
                Spacer()
                Text(previewTime)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.onPrimaryText)
            }
            Text("7:49:52")
                .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.adaptiveGold)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Theme.primaryBright, Theme.primary],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// A fixed clock time (today at 6:28) formatted in the current
    /// language, for the theme preview card's sample Adhan time.
    private var previewTime: String {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        comps.hour = 6
        comps.minute = 28
        return PrayerFormat.time(Calendar.current.date(from: comps) ?? .now)
    }

    /// True when the current mode + colors exactly match a theme — its
    /// row then shows a checkmark instead of the chevron.
    private func isActiveTheme(_ theme: AppAppearance.ThemeChoice) -> Bool {
        theme.modeRaw == modeRaw
            && Int(theme.primaryHex) == primaryHex
            && Int(theme.accentHex) == accentHex
            && Int(theme.textHex) == textHex
    }

    private func apply(_ theme: AppAppearance.ThemeChoice) {
        modeRaw = theme.modeRaw
        primaryHex = Int(theme.primaryHex)
        accentHex = Int(theme.accentHex)
        textHex = Int(theme.textHex)
        settingsChanged()
        // Offer a full restart so the new theme reaches every surface
        // (widgets, Live Activity) exactly the way a fresh launch
        // would apply it (v1.1.1, at Youssef's request).
        showRestartPrompt = true
    }

    /// "Restart" from the theme-applied prompt: close Settings, then
    /// terminate — iOS gives apps no relaunch API, so the app closes
    /// and the user reopens it to a fully re-themed fresh launch.
    private func restartApp() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            exit(0)
        }
    }

    private func saveCurrentTheme() {
        let name = newThemeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var theme = AppAppearance.ThemeChoice(
            id: UUID().uuidString, name: name,
            primaryHex: UInt32(primaryHex), accentHex: UInt32(accentHex),
            textHex: UInt32(textHex), modeRaw: modeRaw
        )
        theme.name = name
        savedThemes.append(theme)
        AppAppearance.savedThemes = savedThemes
        newThemeName = ""
    }

    private func deleteSavedTheme(_ theme: AppAppearance.ThemeChoice) {
        savedThemes.removeAll { $0.id == theme.id }
        AppAppearance.savedThemes = savedThemes
    }

    private func setIcon(_ option: IconOption) {
        iconError = nil
        guard UIApplication.shared.supportsAlternateIcons else {
            iconError = L10n.t("iconUnsupported")
            return
        }
        UIApplication.shared.setAlternateIconName(option.alternateName) { error in
            if let error {
                iconError = L10n.f("iconError", error.localizedDescription)
            } else {
                currentIconName = option.alternateName
            }
        }
    }

    private func resetToDefaults() {
        AppAppearance.resetToDefaults()
        IqamahCountdownSettings.reset()
        RamadanMode.reset()
        FastingSettings.reset()
        MinimalMode.reset()
        SilenceNextAlert.clear()
        PrayerAlertSettings.reset()
        PrayerSoundSettings.reset()
        UIApplication.shared.setAlternateIconName(nil)
        currentIconName = nil
        modeRaw = AppAppearance.Mode.system.rawValue
        widgetColorModeRaw = AppAppearance.WidgetColorMode.match.rawValue
        partThemesRevision += 1
        primaryHex = Int(AppAppearance.defaultPrimaryHex)
        accentHex = Int(AppAppearance.defaultAccentHex)
        textHex = Int(AppAppearance.defaultTextHex)
        resetGeneration += 1
        settingsChanged()
    }

    // MARK: Icon options

    private struct IconOption: Identifiable {
        let alternateName: String?
        let nameKey: String
        let previewImage: String
        var id: String { alternateName ?? "default" }
    }

    private static let iconOptions: [IconOption] = [
        IconOption(alternateName: nil, nameKey: "icon.classic", previewImage: "IconPreviewDefault"),
        IconOption(alternateName: "AppIconMidnight", nameKey: "icon.midnight", previewImage: "IconPreviewMidnight"),
        IconOption(alternateName: "AppIconDesert", nameKey: "icon.desert", previewImage: "IconPreviewDesert"),
        IconOption(alternateName: "AppIconRose", nameKey: "icon.rose", previewImage: "IconPreviewRose"),
        IconOption(alternateName: "AppIconRoyal", nameKey: "icon.royal", previewImage: "IconPreviewRoyal"),
    ]
}

/// One color setting: preset swatches plus the system color picker.
private struct ColorSettingRow: View {
    let title: String
    let caption: String
    let presets: [(name: String, hex: UInt32)]
    @Binding var hexValue: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.body.weight(.semibold))
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                ColorPicker(L10n.f("customColor", title), selection: colorBinding, supportsOpacity: false)
                    .labelsHidden()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(presets, id: \.hex) { preset in
                        Button {
                            hexValue = Int(preset.hex)
                        } label: {
                            Circle()
                                .fill(Color(hex: preset.hex))
                                .frame(width: 36, height: 36)
                                .overlay {
                                    Circle().strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
                                }
                                .overlay {
                                    if UInt32(hexValue) == preset.hex {
                                        Circle()
                                            .strokeBorder(Color.accentColor, lineWidth: 3)
                                            .frame(width: 44, height: 44)
                                    }
                                }
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(preset.name)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 4)
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: UInt32(hexValue)) },
            set: { hexValue = Int($0.hexValue) }
        )
    }
}

/// A theme row: preview chip in the theme's own colors + name.
private struct ThemeChoiceRow: View {
    let theme: AppAppearance.ThemeChoice
    let isSaved: Bool
    let isActive: Bool
    let onApply: () -> Void

    var body: some View {
        Button(action: onApply) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color(hex: theme.primaryHex).opacity(0.75), Color(hex: theme.primaryHex)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                    Text("Aa")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color(hex: theme.textHex))
                    Circle()
                        .fill(Color(hex: theme.accentHex))
                        .frame(width: 12, height: 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(4)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(theme.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("\(L10n.t(isSaved ? "savedTheme" : "designedTheme")) · \(L10n.t("mode.\(theme.modeRaw)"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color(hex: theme.accentHex))
                } else {
                    Image(systemName: "chevron.forward")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            // Whole-row tap target (v1.1.1): with the plain button
            // style only the chip and text were hittable, so most taps
            // on a theme row silently did nothing.
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One prayer's alert toggle, backed directly by the App Group setting.
private struct PrayerAlertRow: View {
    let prayer: Prayer
    let onToggle: () -> Void
    @AppStorage private var isOn: Bool

    init(prayer: Prayer, onToggle: @escaping () -> Void) {
        self.prayer = prayer
        self.onToggle = onToggle
        _isOn = AppStorage(
            wrappedValue: prayer != .sunrise,
            PrayerAlertSettings.key(for: prayer),
            store: UserDefaults(suiteName: PrayerProvider.appGroupIdentifier) ?? .standard
        )
    }

    var body: some View {
        // The whole row toggles — tapping the prayer's name or the
        // empty space beside it works, not just the switch (v1.1.1).
        // The switch is drawn by a non-interactive Toggle so every
        // tap lands on this button.
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                Label {
                    Text(prayer == .dhuhr ? L10n.t("dhuhrFriday") : prayer.displayName)
                } icon: {
                    Image(systemName: prayer.symbolName)
                }
                .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onChange(of: isOn) { _, _ in onToggle() }
    }
}

/// One row of the per-prayer sounds list (v1.8.0): the prayer's
/// name, and a picker — App default, or one of the sounds (Silent
/// mutes just this prayer's alert). Stored as the AdhanSound raw
/// value in the App Group; empty means App default.
private struct PrayerSoundRow: View {
    let prayer: Prayer
    let onChange: () -> Void
    @AppStorage private var stored: String

    init(prayer: Prayer, onChange: @escaping () -> Void) {
        self.prayer = prayer
        self.onChange = onChange
        _stored = AppStorage(
            wrappedValue: "",
            PrayerSoundSettings.key(for: prayer),
            store: UserDefaults(suiteName: PrayerProvider.appGroupIdentifier) ?? .standard
        )
    }

    private var selection: Binding<AdhanSound?> {
        Binding(
            get: { AdhanSound(rawValue: stored) },
            set: { stored = $0?.rawValue ?? "" }
        )
    }

    var body: some View {
        Picker(selection: selection) {
            Text(L10n.t("useAppSound")).tag(nil as AdhanSound?)
            ForEach(AdhanSound.allCases) { sound in
                Text(L10n.t(sound.l10nKey)).tag(sound as AdhanSound?)
            }
        } label: {
            Label {
                Text(prayer == .dhuhr ? L10n.t("dhuhrFriday") : prayer.displayName)
            } icon: {
                Image(systemName: prayer.symbolName)
            }
        }
        .onChange(of: stored) { _, _ in onChange() }
    }
}

// MARK: - Quran quote of the day (v1.1.1)

/// A card under the prayer times with today's verse: the Arabic text,
/// the translation in the chosen language, and the reference. The
/// verse is picked by the day, so it changes at midnight — the
/// timeline rebuild picks the new one up on its own.
private struct DailyVerseCard: View {
    var body: some View {
        let language = AppLanguage.current
        let verse = DailyVerses.verse(for: .now)
        VStack(spacing: 10) {
            HStack {
                Label(L10n.t("dailyVerse"), systemImage: "book.closed.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.onSurface)
                Spacer()
                ShareLink(item: shareText(verse, language)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.adaptiveGold)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(L10n.t("share"))
            }
            VStack(spacing: 10) {
                Text(verse.arabic)
                    .font(.title3.weight(.semibold))
                    .lineSpacing(6)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.onSurface)
                if let translation = verse.translation(for: language) {
                    Text(translation)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.onSurfaceSecondary)
                }
                Text(verse.reference(for: language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.adaptiveGold)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(L10n.t("dailyVerse")): \(verse.arabic) \(verse.translation(for: language) ?? "") \(verse.reference(for: language))"
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .adaptiveCard(cornerRadius: 26)
    }

    /// The verse as one shareable block of text (v1.5).
    private func shareText(_ verse: DailyVerse, _ language: AppLanguage) -> String {
        var lines = [verse.arabic]
        if let translation = verse.translation(for: language) {
            lines.append(translation)
        }
        lines.append("\(verse.reference(for: language)) — \(MosqueInfo.name)")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Qibla compass (v1.1.0)

/// Qibla bearing math: the initial great-circle bearing from the
/// mosque to the Kaaba, plus Edmonton's magnetic declination so the
/// phone's magnetic compass can be corrected to true north.
private enum QiblaMath {
    static let kaabaLatitude = 21.422487
    static let kaabaLongitude = 39.826206
    /// Magnetic declination at Edmonton in 2026 (degrees East), slowly
    /// decreasing; close enough for a phone compass.
    static let magneticDeclination = 12.6

    static var bearingFromMosque: Double {
        let lat1 = MosqueInfo.latitude * .pi / 180
        let lat2 = kaabaLatitude * .pi / 180
        let dLon = (kaabaLongitude - MosqueInfo.longitude) * .pi / 180
        let y = sin(dLon)
        let x = cos(lat1) * tan(lat2) - sin(lat1) * cos(dLon)
        let bearing = atan2(y, x) * 180 / .pi
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }
}

/// Live compass heading from the motion coprocessor, referenced to
/// magnetic north. No location permission is needed (or wanted — the
/// app's privacy promise), and the bearing is computed from the
/// mosque's fixed position, not the user's.
private final class QiblaHeadingManager: ObservableObject {
    @Published private(set) var heading: Double?
    private let motion = CMMotionManager()

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        motion.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: .main) { [weak self] data, _ in
            guard let yaw = data?.attitude.yaw else { return }
            // Yaw is radians counter-clockwise from magnetic north;
            // convert to a clockwise compass heading in degrees, then
            // correct magnetic -> true north.
            var degrees = -yaw * 180 / .pi + QiblaMath.magneticDeclination
            degrees = degrees.truncatingRemainder(dividingBy: 360)
            if degrees < 0 { degrees += 360 }
            self?.heading = degrees
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
    }
}

/// The rotating compass dial, shared by the Qibla card and the
/// full-screen compass (v1.5). The dial rotates against the phone's
/// heading; the gold marker is the Qibla, the fixed triangle at the
/// top is where the phone points.
private struct QiblaDial: View {
    let heading: Double?
    let bearing: Double

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle()
                    .fill(Theme.panelFill)
                    .overlay { Circle().strokeBorder(Theme.hairline, lineWidth: 1) }
                ZStack {
                    ForEach(0..<4, id: \.self) { quarter in
                        Text(L10n.t(["dir.n", "dir.e", "dir.s", "dir.w"][quarter]))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.onSurfaceSecondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .padding(.top, 10)
                            .rotationEffect(.degrees(Double(quarter) * 90))
                    }
                    // Qibla marker on the rim.
                    Text("🕋")
                        .font(.system(size: size > 200 ? 34 : 24))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 2)
                        .rotationEffect(.degrees(bearing))
                        .accessibilityHidden(true)
                }
                .rotationEffect(.degrees(-(heading ?? 0)))
                .animation(.linear(duration: 0.1), value: heading)
                // Fixed pointer at the top: where the phone is facing.
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.adaptiveGold)
                    .offset(y: -(size / 2) - 6)
            }
        }
    }
}

/// Full-screen Qibla compass (v1.5), opened by tapping the Qibla card.
private struct QiblaCompassView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = QiblaHeadingManager()
    @State private var facingQibla = false

    private var bearing: Double { QiblaMath.bearingFromMosque }

    private var offset: Double? {
        guard let heading = manager.heading else { return nil }
        var diff = (bearing - heading).truncatingRemainder(dividingBy: 360)
        if diff > 180 { diff -= 360 }
        if diff < -180 { diff += 360 }
        return diff
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                QiblaDial(heading: manager.heading, bearing: bearing)
                    .frame(width: 300, height: 300)
                VStack(spacing: 6) {
                    Text("\(Int(bearing.rounded()))°")
                        .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.adaptiveGold)
                    Text(L10n.t("fromNorth"))
                        .font(.headline)
                        .foregroundStyle(Theme.onSurface)
                    Text(L10n.t("qiblaFromMosque"))
                        .font(.subheadline)
                        .foregroundStyle(Theme.onSurfaceSecondary)
                    if let offset, abs(offset) <= 3 {
                        Label(L10n.t("facingQibla"), systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(Theme.adaptiveGold)
                            .padding(.top, 4)
                    }
                }
                Text(L10n.t("qiblaHint"))
                    .font(.caption)
                    .foregroundStyle(Theme.onSurfaceMuted)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { AppBackground() }
            .navigationTitle(L10n.t("qiblaCompass"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("done")) { dismiss() }
                }
            }
        }
        .onAppear { manager.start() }
        .onDisappear { manager.stop() }
        // The facing haptic lives ONLY here (v1.5.1): on the card it
        // fired whenever the phone drifted past the Qibla bearing,
        // even with the card scrolled off-screen. In the full-screen
        // compass the user is actively aiming, so the buzz is wanted
        // — and Settings can turn it off entirely.
        .onChange(of: offset.map { abs($0) <= 3 }) { _, isFacing in
            let facing = isFacing ?? false
            if facing && !facingQibla && CompassSettings.hapticsEnabled {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            facingQibla = facing
        }
    }
}

private struct QiblaCard: View {
    @StateObject private var manager = QiblaHeadingManager()
    @State private var showCompass = false

    private var bearing: Double { QiblaMath.bearingFromMosque }

    /// Signed smallest angle between the phone's heading and the Qibla.
    private var offset: Double? {
        guard let heading = manager.heading else { return nil }
        var diff = (bearing - heading).truncatingRemainder(dividingBy: 360)
        if diff > 180 { diff -= 360 }
        if diff < -180 { diff += 360 }
        return diff
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L10n.t("qibla"), systemImage: "location.north.circle.fill")
                .font(.headline)
                .foregroundStyle(Theme.onSurface)
            HStack(spacing: 18) {
                QiblaDial(heading: manager.heading, bearing: bearing)
                    .frame(width: 148, height: 148)
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(Int(bearing.rounded()))°")
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.adaptiveGold)
                    Text(L10n.t("fromNorth"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.onSurface)
                    Text(L10n.t("qiblaFromMosque"))
                        .font(.footnote)
                        .foregroundStyle(Theme.onSurfaceSecondary)
                    if let offset, abs(offset) <= 3 {
                        Label(L10n.t("facingQibla"), systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.adaptiveGold)
                    }
                }
            }
            Text(L10n.t("qiblaHint"))
                .font(.caption)
                .foregroundStyle(Theme.onSurfaceMuted)
            Label(L10n.t("tapForCompass"), systemImage: "arrow.up.left.and.arrow.down.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.adaptiveGold)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveCard(cornerRadius: 26)
        .contentShape(Rectangle())
        .onTapGesture { showCompass = true }
        .sheet(isPresented: $showCompass) {
            QiblaCompassView()
        }
        .onAppear { manager.start() }
        .onDisappear { manager.stop() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(L10n.t("qibla")): \(Int(bearing.rounded()))° \(L10n.t("fromNorth"))")
    }
}

// MARK: - Update checker (v1.7.0)

/// The version note hosted in the c12nfeather source
/// (alrashid-version.json). It only ever advertises a build Apple has
/// approved for the public TestFlight link, so a prompt never sends
/// anyone to an update that is not actually there for them.
struct AdvertisedVersion: Decodable {
    let version: String
    let build: Int
    let url: String
    let notes: String?
}

/// Checks the advertised version at most once per 6 hours, silently.
/// On a newer build: a one-time alert (ContentView) plus a standing
/// Settings section, until the user updates or dismisses that build.
@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var advertised: AdvertisedVersion?
    @Published var showAlert = false

    private let defaults = UserDefaults.standard
    private let lastCheckKey = "updatecheck.lastAt"
    private let dismissedKey = "updatecheck.dismissedBuild"
    private let alertedKey = "updatecheck.alertedBuild"
    private let checkInterval: TimeInterval = 6 * 3600

    private var installedBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
    }

    /// The advertised build the UI should show right now: newer than
    /// the installed build and not dismissed by the user.
    var updateToShow: AdvertisedVersion? {
        guard let advertised, advertised.build > installedBuild,
              advertised.build > defaults.integer(forKey: dismissedKey)
        else { return nil }
        return advertised
    }

    func checkIfNeeded() {
        let now = Date().timeIntervalSince1970
        guard now - defaults.double(forKey: lastCheckKey) >= checkInterval
        else { return }
        defaults.set(now, forKey: lastCheckKey)
        Task { await check() }
    }

    private func check() async {
        guard let url = URL(string: "https://c12nfeather.07051969.xyz/alrashid-version.json")
        else { return }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 8
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let note = try? JSONDecoder().decode(AdvertisedVersion.self, from: data)
        else { return }
        advertised = note.build > installedBuild ? note : nil
        if let update = updateToShow,
           update.build > defaults.integer(forKey: alertedKey) {
            defaults.set(update.build, forKey: alertedKey)
            showAlert = true
        }
    }

    /// "Later": stay quiet about this build (alert and Settings
    /// section) until a newer one is advertised.
    func dismiss() {
        if let build = advertised?.build {
            defaults.set(build, forKey: dismissedKey)
        }
        showAlert = false
    }
}

// MARK: - What's New (v1.8.0)

/// Shown once after an update: what changed in this version, in the
/// user's language. Notes are bundled per version; a version with no
/// entry never presents the sheet.
struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    static func entries(for version: String) -> [(icon: String, key: String)]? {
        switch version {
        case "2.0.0":
            return [
                ("paintpalette.fill", "wnWidgets200"),
                ("rectangle.split.2x1.fill", "wnDuo200"),
                ("ipad", "wnPad200"),
                ("moon.stars.fill", "wnRamadan200"),
                ("calendar", "wnCalendar200"),
                ("timer", "wnIqamah200"),
                ("line.3.horizontal.decrease", "wnMinimal200"),
            ]
        case "1.8.0":
            return [
                ("applewatch", "wnWatch"),
                ("speaker.wave.2.fill", "wnSounds"),
                ("icloud.fill", "wnSync"),
                ("textformat.size", "wnText"),
            ]
        default:
            return nil
        }
    }

    var body: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        NavigationStack {
            List {
                ForEach(Self.entries(for: version) ?? [], id: \.key) { entry in
                    Label {
                        Text(L10n.t(entry.key))
                    } icon: {
                        Image(systemName: entry.icon)
                            .foregroundStyle(Theme.adaptiveGold)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(L10n.t("whatsNew"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("continue")) { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, AppLanguage.current.isRTL ? .rightToLeft : .leftToRight)
        .environment(\.locale, AppLanguage.current.locale)
    }
}
