//
//  PrayerModels.swift
//  AlRashid Prayer Widget
//
//  SHARED FILE: Target Membership = AlRashidWidget + PrayerWidgetExtension
//
//  Models, Iqamah configuration, PrayerProvider (computation, App Group cache,
//  timeline planning), formatting helpers, theme and small shared SwiftUI components.
//
//  Both targets need the App Groups capability with: group.com.c12n.alrashidwidget
//

import Foundation
import SwiftUI

// MARK: - Mosque constants

enum MosqueInfo {
    static let name = "AlRashid Mosque"
    static let address = "13070 113 St NW, Edmonton, AB"
    static let directionsAddress = "13070 113 St NW, Edmonton, AB, Canada"
    static let latitude = 53.591189
    static let longitude = -113.515598
    static let timeZoneIdentifier = "America/Edmonton"
    static let jumuahKhutbahHour = 13
    static let jumuahKhutbahMinute = 30
    static let websiteURL = URL(string: "https://alrashidmosque.ca")!

    static var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }

    /// Apple Maps driving directions to the mosque.
    static var directionsURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.path = "/"
        components.queryItems = [
            URLQueryItem(name: "daddr", value: directionsAddress),
            URLQueryItem(name: "dirflg", value: "d")
        ]
        return components.url ?? URL(string: "https://maps.apple.com/")!
    }
}

// MARK: - Prayer

enum Prayer: String, Codable, CaseIterable, Sendable, Identifiable {
    case fajr, sunrise, dhuhr, asr, maghrib, isha

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fajr: "Fajr"
        case .sunrise: "Sunrise"
        case .dhuhr: "Dhuhr"
        case .asr: "Asr"
        case .maghrib: "Maghrib"
        case .isha: "Isha"
        }
    }

    var shortName: String {
        switch self {
        case .fajr: "FAJR"
        case .sunrise: "SUNRISE"
        case .dhuhr: "DHUHR"
        case .asr: "ASR"
        case .maghrib: "MAGHRIB"
        case .isha: "ISHA"
        }
    }

    var symbolName: String {
        switch self {
        case .fajr: "sun.haze.fill"
        case .sunrise: "sunrise.fill"
        case .dhuhr: "sun.max.fill"
        case .asr: "sun.min.fill"
        case .maghrib: "sunset.fill"
        case .isha: "moon.stars.fill"
        }
    }

    /// Sunrise is shown in the schedule but is not a prayer (no Iqamah, never "next prayer").
    var isPrayer: Bool { self != .sunrise }
}

// MARK: - Iqamah configuration

struct IqamahConfig: Codable, Sendable, Hashable {
    var fajr: Int
    var dhuhr: Int
    var asr: Int
    var maghrib: Int
    var isha: Int

    init(fajr: Int = 20, dhuhr: Int = 10, asr: Int = 10, maghrib: Int = 5, isha: Int = 10) {
        self.fajr = fajr
        self.dhuhr = dhuhr
        self.asr = asr
        self.maghrib = maghrib
        self.isha = isha
    }

    /// AlRashid defaults: Fajr +20, Dhuhr +10, Asr +10, Maghrib +5, Isha +10 minutes after Adhan.
    static let standard = IqamahConfig()

    func offsetMinutes(for prayer: Prayer) -> Int? {
        switch prayer {
        case .fajr: fajr
        case .sunrise: nil
        case .dhuhr: dhuhr
        case .asr: asr
        case .maghrib: maghrib
        case .isha: isha
        }
    }

    func iqamah(for prayer: Prayer, adhan: Date) -> Date? {
        guard let minutes = offsetMinutes(for: prayer) else { return nil }
        return adhan.addingTimeInterval(TimeInterval(minutes) * 60)
    }
}

// MARK: - Prayer slot (one row in a schedule)

struct PrayerSlot: Codable, Sendable, Hashable, Identifiable {
    let prayer: Prayer
    let adhan: Date
    let iqamah: Date?
    let isJumuah: Bool

    var id: String { "\(prayer.rawValue)-\(Int(adhan.timeIntervalSince1970))" }
    var name: String { isJumuah ? "Jumu'ah" : prayer.displayName }
    var shortName: String { isJumuah ? "JUMU'AH" : prayer.shortName }
    var iqamahLabel: String { isJumuah ? "Khutbah" : "Iqamah" }
    var symbolName: String { isJumuah ? "building.columns.fill" : prayer.symbolName }
}

// MARK: - Prayer day

struct PrayerDay: Codable, Sendable, Hashable {
    /// Start of the local (America/Edmonton) calendar day.
    let date: Date
    let fajr: Date
    let sunrise: Date
    let dhuhr: Date
    let asr: Date
    let maghrib: Date
    let isha: Date
    let fajrIqamah: Date
    let dhuhrIqamah: Date
    let asrIqamah: Date
    let maghribIqamah: Date
    let ishaIqamah: Date
    let hijriDate: String
    let isFriday: Bool
    let jumuahKhutbah: Date?

    func adhan(for prayer: Prayer) -> Date {
        switch prayer {
        case .fajr: fajr
        case .sunrise: sunrise
        case .dhuhr: dhuhr
        case .asr: asr
        case .maghrib: maghrib
        case .isha: isha
        }
    }

    func iqamah(for prayer: Prayer) -> Date? {
        switch prayer {
        case .fajr: fajrIqamah
        case .sunrise: nil
        case .dhuhr: dhuhrIqamah
        case .asr: asrIqamah
        case .maghrib: maghribIqamah
        case .isha: ishaIqamah
        }
    }

    /// All six rows. On Fridays the Dhuhr row becomes Jumu'ah with the Khutbah time
    /// in the Iqamah column.
    var slots: [PrayerSlot] {
        Prayer.allCases.map { prayer in
            let jumuah = isFriday && prayer == .dhuhr
            let second = jumuah ? (jumuahKhutbah ?? iqamah(for: prayer)) : iqamah(for: prayer)
            return PrayerSlot(prayer: prayer, adhan: adhan(for: prayer), iqamah: second, isJumuah: jumuah)
        }
    }

    /// The five prayers (no Sunrise) — used for "next prayer" logic and timeline boundaries.
    var prayerSlots: [PrayerSlot] { slots.filter { $0.prayer.isPrayer } }
}

// MARK: - Snapshot (state at an instant) & timeline plan

struct PrayerSnapshot: Sendable, Hashable {
    /// The instant this snapshot describes (becomes the widget entry date).
    let date: Date
    /// The day whose schedule is displayed (switches to tomorrow after Isha).
    let day: PrayerDay
    /// The next upcoming prayer.
    let next: PrayerSlot
    /// The previous prayer boundary — start of the progress interval.
    let previousBoundary: Date
    /// True when `day` is later than the calendar day of `date`.
    let isShowingTomorrow: Bool

    var countdownRange: ClosedRange<Date> {
        let start = min(date, next.adhan)
        return start...next.adhan
    }

    var progressRange: ClosedRange<Date> {
        let start = previousBoundary < next.adhan ? previousBoundary : next.adhan.addingTimeInterval(-3600)
        return start...next.adhan
    }

    func isNext(_ slot: PrayerSlot) -> Bool { slot.id == next.id }
}

struct PrayerTimelinePlan: Sendable {
    let snapshots: [PrayerSnapshot]
    let reloadDate: Date
}

// MARK: - Provider

struct PrayerProvider: Sendable {
    static let appGroupIdentifier = "group.com.c12n.alrashidwidget"
    static let widgetKind = "AlRashidPrayerWidget"
    static let cacheKey = "alrashid.prayerDay.cache"
    static let cacheVersion = 1
    static let standard = PrayerProvider()

    let calculator: PrayerCalculator
    let iqamahConfig: IqamahConfig
    let calendar: Calendar

    init(calculator: PrayerCalculator = .alRashid, iqamahConfig: IqamahConfig = .standard) {
        self.calculator = calculator
        self.iqamahConfig = iqamahConfig
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = calculator.timeZone
        self.calendar = localCalendar
    }

    // MARK: Computation

    /// Computes (never reads cache) the full PrayerDay for the local day containing `date`.
    func computeDay(for date: Date) -> PrayerDay {
        let start = calendar.startOfDay(for: date)
        let noon = calendar.date(byAdding: .hour, value: 12, to: start) ?? start
        let times = calculator.times(for: noon)
        let isFriday = calendar.component(.weekday, from: noon) == 6
        let khutbah: Date? = isFriday
            ? calendar.date(bySettingHour: MosqueInfo.jumuahKhutbahHour, minute: MosqueInfo.jumuahKhutbahMinute, second: 0, of: start)
            : nil

        func iqamah(_ prayer: Prayer, _ adhan: Date) -> Date {
            iqamahConfig.iqamah(for: prayer, adhan: adhan) ?? adhan
        }

        return PrayerDay(
            date: start,
            fajr: times.fajr, sunrise: times.sunrise, dhuhr: times.dhuhr,
            asr: times.asr, maghrib: times.maghrib, isha: times.isha,
            fajrIqamah: iqamah(.fajr, times.fajr),
            dhuhrIqamah: iqamah(.dhuhr, times.dhuhr),
            asrIqamah: iqamah(.asr, times.asr),
            maghribIqamah: iqamah(.maghrib, times.maghrib),
            ishaIqamah: iqamah(.isha, times.isha),
            hijriDate: Self.hijriString(for: noon, timeZone: calendar.timeZone),
            isFriday: isFriday,
            jumuahKhutbah: khutbah
        )
    }

    /// Cache-aware lookup for any day (uses the cached day when it matches).
    func day(for date: Date) -> PrayerDay {
        let start = calendar.startOfDay(for: date)
        if let cached = cachedDay(), cached.date == start { return cached }
        return computeDay(for: start)
    }

    /// Today's PrayerDay — served from the App Group cache, recomputed and re-cached when stale.
    func today(now: Date = .now) -> PrayerDay {
        let start = calendar.startOfDay(for: now)
        if let cached = cachedDay(), cached.date == start { return cached }
        let fresh = computeDay(for: start)
        storeInCache(fresh)
        return fresh
    }

    func tomorrow(now: Date = .now) -> PrayerDay {
        computeDay(for: shifted(calendar.startOfDay(for: now), byDays: 1))
    }

    /// Forces a recompute of today and writes it to the App Group cache.
    @discardableResult
    func refreshCache(now: Date = .now) -> PrayerDay {
        let fresh = computeDay(for: now)
        storeInCache(fresh)
        return fresh
    }

    // MARK: App Group cache

    private struct CachePayload: Codable {
        let version: Int
        let signature: String
        let day: PrayerDay
    }

    private var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: Self.appGroupIdentifier) ?? .standard
    }

    /// Invalidates the cache whenever calculation settings or Iqamah offsets change.
    private var cacheSignature: String {
        let c = calculator
        let parts: [String] = [
            String(c.coordinates.latitude), String(c.coordinates.longitude), String(c.coordinates.elevation),
            c.method.name, String(c.method.fajrAngle), String(c.method.ishaAngle), String(c.method.maghribMinutes),
            c.asrMethod.rawValue, c.highLatitudeRule.rawValue, c.timeZone.identifier,
            String(iqamahConfig.fajr), String(iqamahConfig.dhuhr), String(iqamahConfig.asr),
            String(iqamahConfig.maghrib), String(iqamahConfig.isha),
            String(MosqueInfo.jumuahKhutbahHour), String(MosqueInfo.jumuahKhutbahMinute)
        ]
        return parts.joined(separator: "|")
    }

    func cachedDay() -> PrayerDay? {
        guard let data = sharedDefaults.data(forKey: Self.cacheKey),
              let payload = try? JSONDecoder().decode(CachePayload.self, from: data),
              payload.version == Self.cacheVersion,
              payload.signature == cacheSignature else { return nil }
        return payload.day
    }

    func storeInCache(_ day: PrayerDay) {
        let payload = CachePayload(version: Self.cacheVersion, signature: cacheSignature, day: day)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        sharedDefaults.set(data, forKey: Self.cacheKey)
    }

    // MARK: Snapshots & timeline

    /// State at an arbitrary instant (used by the app and widget snapshots/placeholders).
    func snapshot(at date: Date = .now) -> PrayerSnapshot {
        let start = calendar.startOfDay(for: date)
        let days = (-1...2).map { offset in day(for: shifted(start, byDays: offset)) }
        return makeSnapshot(at: date, days: days)
    }

    /// One entry now, one at every prayer Adhan for today and tomorrow, plus each midnight,
    /// so "next prayer" and the countdown roll over exactly. Reloads at the end of today.
    func timelinePlan(from now: Date = .now) -> PrayerTimelinePlan {
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = shifted(todayStart, byDays: 1)
        let dayAfterStart = shifted(todayStart, byDays: 2)
        let todaySchedule = today(now: now)
        let tomorrowSchedule = computeDay(for: tomorrowStart)
        let days = [
            computeDay(for: shifted(todayStart, byDays: -1)),
            todaySchedule, tomorrowSchedule, computeDay(for: dayAfterStart)
        ]

        var boundaries: Set<Date> = [now]
        for schedule in [todaySchedule, tomorrowSchedule] {
            for slot in schedule.prayerSlots where slot.adhan > now {
                boundaries.insert(slot.adhan)
            }
        }
        if tomorrowStart > now { boundaries.insert(tomorrowStart) }
        if dayAfterStart > now { boundaries.insert(dayAfterStart) }

        let snapshots = boundaries.sorted().map { makeSnapshot(at: $0, days: days) }
        return PrayerTimelinePlan(snapshots: snapshots, reloadDate: tomorrowStart)
    }

    private func makeSnapshot(at date: Date, days: [PrayerDay]) -> PrayerSnapshot {
        let ordered = days.sorted { $0.date < $1.date }
        let candidates: [(day: PrayerDay, slot: PrayerSlot)] = ordered.flatMap { schedule in
            schedule.prayerSlots.map { (day: schedule, slot: $0) }
        }
        let dateDayStart = calendar.startOfDay(for: date)
        if let index = candidates.firstIndex(where: { $0.slot.adhan > date }) {
            let match = candidates[index]
            let previous = index > 0 ? candidates[index - 1].slot.adhan : match.slot.adhan.addingTimeInterval(-6 * 3600)
            return PrayerSnapshot(
                date: date, day: match.day, next: match.slot, previousBoundary: previous,
                isShowingTomorrow: match.day.date > dateDayStart
            )
        }
        // Defensive fallback: tomorrow's Fajr is always after `date`.
        let fallbackDay = computeDay(for: shifted(dateDayStart, byDays: 1))
        let fallbackSlot = fallbackDay.prayerSlots.first(where: { $0.adhan > date })
            ?? PrayerSlot(prayer: .fajr, adhan: max(fallbackDay.fajr, date), iqamah: fallbackDay.fajrIqamah, isJumuah: false)
        return PrayerSnapshot(date: date, day: fallbackDay, next: fallbackSlot, previousBoundary: date, isShowingTomorrow: true)
    }

    private func shifted(_ start: Date, byDays days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: start) ?? start.addingTimeInterval(TimeInterval(days) * 86_400)
    }

    // MARK: Hijri

    static func hijriString(for date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        // Via NSCalendar: the Swift Calendar.Identifier case for Umm al-Qura is not exposed in every SDK.
        formatter.calendar = (NSCalendar(calendarIdentifier: .islamicUmalqura) as Calendar?)
            ?? Calendar(identifier: .islamicCivil)
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = timeZone
        formatter.dateFormat = "d MMMM y"
        return "\(formatter.string(from: date)) AH"
    }
}

// MARK: - Formatting (always in the mosque's time zone)

enum PrayerFormat {
    static var timeZone: TimeZone { MosqueInfo.timeZone }

    /// "1:18 PM" (respects the user's 12/24-hour preference).
    static func time(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// "1:18" — no AM/PM, for tight lock-screen layouts.
    static func compactTime(_ date: Date) -> String {
        var style = Date.FormatStyle().hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// "Tuesday, October 27, 2026"
    static func longDate(_ date: Date) -> String {
        var style = Date.FormatStyle().weekday(.wide).month(.wide).day().year()
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// "Tue, Oct 27"
    static func shortDate(_ date: Date) -> String {
        var style = Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day()
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// Jumu'ah Khutbah time (1:30 PM local) formatted for the given day.
    static func khutbahTime(on day: Date) -> String {
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = timeZone
        let start = localCalendar.startOfDay(for: day)
        let khutbah = localCalendar.date(bySettingHour: MosqueInfo.jumuahKhutbahHour, minute: MosqueInfo.jumuahKhutbahMinute, second: 0, of: start) ?? start
        return time(khutbah)
    }
}

// MARK: - Theme

enum Theme {
    static let deepGreen = Color(hex: 0x0B3D2E)
    static let green = Color(hex: 0x0E5A40)
    static let gold = Color(hex: 0xD4AF37)
    static let lightGold = Color(hex: 0xF2CD5C)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

// MARK: - Shared SwiftUI components

/// Deep-green "glass" background: green gradient with soft light and gold glows.
struct GlassGreenBackground: View {
    var showsWatermark: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.green, Theme.deepGreen], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color.white.opacity(0.18), Color.clear], center: .topLeading, startRadius: 0, endRadius: 260)
            RadialGradient(colors: [Theme.gold.opacity(0.16), Color.clear], center: .bottomTrailing, startRadius: 0, endRadius: 240)
            LinearGradient(colors: [Color.white.opacity(0.07), Color.clear], startPoint: .top, endPoint: .center)
            if showsWatermark {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 120, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.05))
                    .rotationEffect(.degrees(-12))
                    .offset(x: 30, y: -20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
    }
}

/// Live, self-updating gold progress bar between two prayer boundaries.
struct GoldProgressBar: View {
    let range: ClosedRange<Date>

    var body: some View {
        ProgressView(timerInterval: range, countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
            .progressViewStyle(.linear)
            .tint(Theme.lightGold)
    }
}
