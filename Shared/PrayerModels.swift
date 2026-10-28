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

import ActivityKit
import Foundation
import SwiftUI
import UIKit

// MARK: - Mosque constants

enum MosqueInfo {
    static let name = "Al Rashid Mosque"
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

    /// The first prayer slot whose Adhan falls strictly after `slot`'s Adhan
    /// (looking into the following day when needed). Used to pre-stage the
    /// prayer after the next one in the Live Activity, so its name and time
    /// are already on the Lock Screen when the current countdown ends.
    func followingSlot(after slot: PrayerSlot) -> PrayerSlot? {
        let start = calendar.startOfDay(for: slot.adhan)
        let days = (0...1).map { computeDay(for: shifted(start, byDays: $0)) }
        return days.flatMap { $0.prayerSlots }
            .sorted { $0.adhan < $1.adhan }
            .first { $0.adhan > slot.adhan }
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
        // The system Umm al-Qura calendar is not reliably available in
        // every SDK / runtime this project ships on (it silently falls
        // back to the tabular civil calendar, which runs a day behind),
        // so the conversion uses an embedded Umm al-Qura month table.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let hijri = UmmAlQuraCalendar.hijri(year: year, month: month, day: day) else {
            return ""
        }
        return "\(hijri.day) \(UmmAlQuraCalendar.monthNames[hijri.month - 1]) \(hijri.year) AH"
    }
}

// MARK: - Umm al-Qura Hijri conversion

/// Gregorian -> Hijri conversion using the official Umm al-Qura month
/// table (van Gent's algorithm): `monthStarts` holds the Modified
/// Julian Day of the first day of each Hijri month, lunations
/// 16260...18000 (about 1356-1500 AH). Validated against reference
/// Umm al-Qura conversions for dates across 2024-2030.
enum UmmAlQuraCalendar {
    static let monthNames = [
        "Muharram", "Safar", "Rabi I", "Rabi II", "Jumada I", "Jumada II",
        "Rajab", "Shaban", "Ramadan", "Shawwal", "Dhul Qadah", "Dhul Hijjah"
    ]

    static let monthStarts: [Int] = [
        28607, 28636, 28665, 28695, 28724, 28754, 28783, 28813, 28843, 28872, 28901, 28931,
        28960, 28990, 29019, 29049, 29078, 29108, 29137, 29167, 29196, 29226, 29255, 29285,
        29315, 29345, 29375, 29404, 29434, 29463, 29492, 29522, 29551, 29580, 29610, 29640,
        29669, 29699, 29729, 29759, 29788, 29818, 29847, 29876, 29906, 29935, 29964, 29994,
        30023, 30053, 30082, 30112, 30141, 30171, 30200, 30230, 30259, 30289, 30318, 30348,
        30378, 30408, 30437, 30467, 30496, 30526, 30555, 30585, 30614, 30644, 30673, 30703,
        30732, 30762, 30791, 30821, 30850, 30880, 30909, 30939, 30968, 30998, 31027, 31057,
        31086, 31116, 31145, 31175, 31204, 31234, 31263, 31293, 31322, 31352, 31381, 31411,
        31441, 31471, 31500, 31530, 31559, 31589, 31618, 31648, 31676, 31706, 31736, 31766,
        31795, 31825, 31854, 31884, 31913, 31943, 31972, 32002, 32031, 32061, 32090, 32120,
        32150, 32180, 32209, 32239, 32268, 32298, 32327, 32357, 32386, 32416, 32445, 32475,
        32504, 32534, 32563, 32593, 32622, 32652, 32681, 32711, 32740, 32770, 32799, 32829,
        32858, 32888, 32917, 32947, 32976, 33006, 33035, 33065, 33094, 33124, 33153, 33183,
        33213, 33243, 33272, 33302, 33331, 33361, 33390, 33420, 33450, 33479, 33509, 33539,
        33568, 33598, 33627, 33657, 33686, 33716, 33745, 33775, 33804, 33834, 33863, 33893,
        33922, 33952, 33981, 34011, 34040, 34069, 34099, 34128, 34158, 34187, 34217, 34247,
        34277, 34306, 34336, 34365, 34395, 34424, 34454, 34483, 34512, 34542, 34571, 34601,
        34631, 34660, 34690, 34719, 34749, 34778, 34808, 34837, 34867, 34896, 34926, 34955,
        34985, 35015, 35044, 35074, 35103, 35133, 35162, 35192, 35222, 35251, 35280, 35310,
        35340, 35370, 35399, 35429, 35458, 35488, 35517, 35547, 35576, 35605, 35635, 35665,
        35694, 35723, 35753, 35782, 35811, 35841, 35871, 35901, 35930, 35960, 35989, 36019,
        36048, 36078, 36107, 36136, 36166, 36195, 36225, 36254, 36284, 36314, 36343, 36373,
        36403, 36433, 36462, 36492, 36521, 36551, 36580, 36610, 36639, 36669, 36698, 36728,
        36757, 36786, 36816, 36845, 36875, 36904, 36934, 36963, 36993, 37022, 37052, 37081,
        37111, 37141, 37170, 37200, 37229, 37259, 37288, 37318, 37347, 37377, 37406, 37436,
        37465, 37495, 37524, 37554, 37584, 37613, 37643, 37672, 37701, 37731, 37760, 37790,
        37819, 37849, 37878, 37908, 37938, 37967, 37997, 38027, 38056, 38085, 38115, 38144,
        38174, 38203, 38233, 38262, 38292, 38322, 38351, 38381, 38410, 38440, 38469, 38499,
        38528, 38558, 38587, 38617, 38646, 38676, 38705, 38735, 38764, 38794, 38823, 38853,
        38882, 38912, 38941, 38971, 39001, 39030, 39059, 39089, 39118, 39148, 39178, 39208,
        39237, 39267, 39297, 39326, 39355, 39385, 39414, 39444, 39473, 39503, 39532, 39562,
        39592, 39621, 39650, 39680, 39709, 39739, 39768, 39798, 39827, 39857, 39886, 39916,
        39946, 39975, 40005, 40035, 40064, 40094, 40123, 40153, 40182, 40212, 40241, 40271,
        40300, 40330, 40359, 40389, 40418, 40448, 40477, 40507, 40536, 40566, 40595, 40625,
        40655, 40685, 40714, 40744, 40773, 40803, 40832, 40862, 40892, 40921, 40951, 40980,
        41009, 41039, 41068, 41098, 41127, 41157, 41186, 41216, 41245, 41275, 41304, 41334,
        41364, 41393, 41422, 41452, 41481, 41511, 41540, 41570, 41599, 41629, 41658, 41688,
        41718, 41748, 41777, 41807, 41836, 41865, 41894, 41924, 41953, 41983, 42012, 42042,
        42072, 42102, 42131, 42161, 42190, 42220, 42249, 42279, 42308, 42337, 42367, 42397,
        42426, 42456, 42485, 42515, 42545, 42574, 42604, 42633, 42662, 42692, 42721, 42751,
        42780, 42810, 42839, 42869, 42899, 42929, 42958, 42988, 43017, 43046, 43076, 43105,
        43135, 43164, 43194, 43223, 43253, 43283, 43312, 43342, 43371, 43401, 43430, 43460,
        43489, 43519, 43548, 43578, 43607, 43637, 43666, 43696, 43726, 43755, 43785, 43814,
        43844, 43873, 43903, 43932, 43962, 43991, 44021, 44050, 44080, 44109, 44139, 44169,
        44198, 44228, 44258, 44287, 44317, 44346, 44375, 44405, 44434, 44464, 44493, 44523,
        44553, 44582, 44612, 44641, 44671, 44700, 44730, 44759, 44788, 44818, 44847, 44877,
        44906, 44936, 44966, 44996, 45025, 45055, 45084, 45114, 45143, 45172, 45202, 45231,
        45261, 45290, 45320, 45350, 45380, 45409, 45439, 45468, 45498, 45527, 45556, 45586,
        45615, 45644, 45674, 45704, 45733, 45763, 45793, 45823, 45852, 45882, 45911, 45940,
        45970, 45999, 46028, 46058, 46088, 46117, 46147, 46177, 46206, 46236, 46265, 46295,
        46324, 46354, 46383, 46413, 46442, 46472, 46501, 46531, 46560, 46590, 46620, 46649,
        46679, 46708, 46738, 46767, 46797, 46826, 46856, 46885, 46915, 46944, 46974, 47003,
        47033, 47063, 47092, 47122, 47151, 47181, 47210, 47240, 47269, 47298, 47328, 47357,
        47387, 47417, 47446, 47476, 47506, 47535, 47565, 47594, 47624, 47653, 47682, 47712,
        47741, 47771, 47800, 47830, 47860, 47890, 47919, 47949, 47978, 48008, 48037, 48066,
        48096, 48125, 48155, 48184, 48214, 48244, 48273, 48303, 48333, 48362, 48392, 48421,
        48450, 48480, 48509, 48538, 48568, 48598, 48627, 48657, 48687, 48717, 48746, 48776,
        48805, 48834, 48864, 48893, 48922, 48952, 48982, 49011, 49041, 49071, 49100, 49130,
        49160, 49189, 49218, 49248, 49277, 49306, 49336, 49365, 49395, 49425, 49455, 49484,
        49514, 49543, 49573, 49602, 49632, 49661, 49690, 49720, 49749, 49779, 49809, 49838,
        49868, 49898, 49927, 49957, 49986, 50016, 50045, 50075, 50104, 50133, 50163, 50192,
        50222, 50252, 50281, 50311, 50340, 50370, 50400, 50429, 50459, 50488, 50518, 50547,
        50576, 50606, 50635, 50665, 50694, 50724, 50754, 50784, 50813, 50843, 50872, 50902,
        50931, 50960, 50990, 51019, 51049, 51078, 51108, 51138, 51167, 51197, 51227, 51256,
        51286, 51315, 51345, 51374, 51403, 51433, 51462, 51492, 51522, 51552, 51582, 51611,
        51641, 51670, 51699, 51729, 51758, 51787, 51816, 51846, 51876, 51906, 51936, 51965,
        51995, 52025, 52054, 52083, 52113, 52142, 52171, 52200, 52230, 52260, 52290, 52319,
        52349, 52379, 52408, 52438, 52467, 52497, 52526, 52555, 52585, 52614, 52644, 52673,
        52703, 52733, 52762, 52792, 52822, 52851, 52881, 52910, 52939, 52969, 52998, 53028,
        53057, 53087, 53116, 53146, 53176, 53205, 53235, 53264, 53294, 53324, 53353, 53383,
        53412, 53441, 53471, 53500, 53530, 53559, 53589, 53619, 53648, 53678, 53708, 53737,
        53767, 53796, 53825, 53855, 53884, 53913, 53943, 53973, 54003, 54032, 54062, 54092,
        54121, 54151, 54180, 54209, 54239, 54268, 54297, 54327, 54357, 54387, 54416, 54446,
        54476, 54505, 54535, 54564, 54593, 54623, 54652, 54681, 54711, 54741, 54770, 54800,
        54830, 54859, 54889, 54919, 54948, 54977, 55007, 55036, 55066, 55095, 55125, 55154,
        55184, 55213, 55243, 55273, 55302, 55332, 55361, 55391, 55420, 55450, 55479, 55508,
        55538, 55567, 55597, 55627, 55657, 55686, 55716, 55745, 55775, 55804, 55834, 55863,
        55892, 55922, 55951, 55981, 56011, 56040, 56070, 56100, 56129, 56159, 56188, 56218,
        56247, 56276, 56306, 56335, 56365, 56394, 56424, 56454, 56483, 56513, 56543, 56572,
        56601, 56631, 56660, 56690, 56719, 56749, 56778, 56808, 56837, 56867, 56897, 56926,
        56956, 56985, 57015, 57044, 57074, 57103, 57133, 57162, 57192, 57221, 57251, 57280,
        57310, 57340, 57369, 57399, 57429, 57458, 57487, 57517, 57546, 57576, 57605, 57634,
        57664, 57694, 57723, 57753, 57783, 57813, 57842, 57871, 57901, 57930, 57959, 57989,
        58018, 58048, 58077, 58107, 58137, 58167, 58196, 58226, 58255, 58285, 58314, 58343,
        58373, 58402, 58432, 58461, 58491, 58521, 58551, 58580, 58610, 58639, 58669, 58698,
        58727, 58757, 58786, 58816, 58845, 58875, 58905, 58934, 58964, 58994, 59023, 59053,
        59082, 59111, 59141, 59170, 59200, 59229, 59259, 59288, 59318, 59348, 59377, 59407,
        59436, 59466, 59495, 59525, 59554, 59584, 59613, 59643, 59672, 59702, 59731, 59761,
        59791, 59820, 59850, 59879, 59909, 59939, 59968, 59997, 60027, 60056, 60086, 60115,
        60145, 60174, 60204, 60234, 60264, 60293, 60323, 60352, 60381, 60411, 60440, 60469,
        60499, 60528, 60558, 60588, 60618, 60648, 60677, 60707, 60736, 60765, 60795, 60824,
        60853, 60883, 60912, 60942, 60972, 61002, 61031, 61061, 61090, 61120, 61149, 61179,
        61208, 61237, 61267, 61296, 61326, 61356, 61385, 61415, 61445, 61474, 61504, 61533,
        61563, 61592, 61621, 61651, 61680, 61710, 61739, 61769, 61799, 61828, 61858, 61888,
        61917, 61947, 61976, 62006, 62035, 62064, 62094, 62123, 62153, 62182, 62212, 62242,
        62271, 62301, 62331, 62360, 62390, 62419, 62448, 62478, 62507, 62537, 62566, 62596,
        62625, 62655, 62685, 62715, 62744, 62774, 62803, 62832, 62862, 62891, 62921, 62950,
        62980, 63009, 63039, 63069, 63099, 63128, 63157, 63187, 63216, 63246, 63275, 63305,
        63334, 63363, 63393, 63423, 63453, 63482, 63512, 63541, 63571, 63600, 63630, 63659,
        63689, 63718, 63747, 63777, 63807, 63836, 63866, 63895, 63925, 63955, 63984, 64014,
        64043, 64073, 64102, 64131, 64161, 64190, 64220, 64249, 64279, 64309, 64339, 64368,
        64398, 64427, 64457, 64486, 64515, 64545, 64574, 64603, 64633, 64663, 64692, 64722,
        64752, 64782, 64811, 64841, 64870, 64899, 64929, 64958, 64987, 65017, 65047, 65076,
        65106, 65136, 65166, 65195, 65225, 65254, 65283, 65313, 65342, 65371, 65401, 65431,
        65460, 65490, 65520, 65549, 65579, 65608, 65638, 65667, 65697, 65726, 65755, 65785,
        65815, 65844, 65874, 65903, 65933, 65963, 65992, 66022, 66051, 66081, 66110, 66140,
        66169, 66199, 66228, 66258, 66287, 66317, 66346, 66376, 66405, 66435, 66465, 66494,
        66524, 66553, 66583, 66612, 66641, 66671, 66700, 66730, 66760, 66789, 66819, 66849,
        66878, 66908, 66937, 66967, 66996, 67025, 67055, 67084, 67114, 67143, 67173, 67203,
        67233, 67262, 67292, 67321, 67351, 67380, 67409, 67439, 67468, 67497, 67527, 67557,
        67587, 67617, 67646, 67676, 67705, 67735, 67764, 67793, 67823, 67852, 67882, 67911,
        67941, 67971, 68000, 68030, 68060, 68089, 68119, 68148, 68177, 68207, 68236, 68266,
        68295, 68325, 68354, 68384, 68414, 68443, 68473, 68502, 68532, 68561, 68591, 68620,
        68650, 68679, 68708, 68738, 68768, 68797, 68827, 68857, 68886, 68916, 68946, 68975,
        69004, 69034, 69063, 69092, 69122, 69152, 69181, 69211, 69240, 69270, 69300, 69330,
        69359, 69388, 69418, 69447, 69476, 69506, 69535, 69565, 69595, 69624, 69654, 69684,
        69713, 69743, 69772, 69802, 69831, 69861, 69890, 69919, 69949, 69978, 70008, 70038,
        70067, 70097, 70126, 70156, 70186, 70215, 70245, 70274, 70303, 70333, 70362, 70392,
        70421, 70451, 70481, 70510, 70540, 70570, 70599, 70629, 70658, 70687, 70717, 70746,
        70776, 70805, 70835, 70864, 70894, 70924, 70954, 70983, 71013, 71042, 71071, 71101,
        71130, 71159, 71189, 71218, 71248, 71278, 71308, 71337, 71367, 71397, 71426, 71455,
        71485, 71514, 71543, 71573, 71602, 71632, 71662, 71691, 71721, 71751, 71781, 71810,
        71839, 71869, 71898, 71927, 71957, 71986, 72016, 72046, 72075, 72105, 72135, 72164,
        72194, 72223, 72253, 72282, 72311, 72341, 72370, 72400, 72429, 72459, 72489, 72518,
        72548, 72577, 72607, 72637, 72666, 72695, 72725, 72754, 72784, 72813, 72843, 72872,
        72902, 72931, 72961, 72991, 73020, 73050, 73080, 73109, 73139, 73168, 73197, 73227,
        73256, 73286, 73315, 73345, 73375, 73404, 73434, 73464, 73493, 73523, 73552, 73581,
        73611, 73640, 73669, 73699, 73729, 73758, 73788, 73818, 73848, 73877, 73907, 73936,
        73965, 73995, 74024, 74053, 74083, 74113, 74142, 74172, 74202, 74231, 74261, 74291,
        74320, 74349, 74379, 74408, 74437, 74467, 74497, 74526, 74556, 74586, 74615, 74645,
        74675, 74704, 74733, 74763, 74792, 74822, 74851, 74881, 74910, 74940, 74969, 74999,
        75029, 75058, 75088, 75117, 75147, 75176, 75206, 75235, 75264, 75294, 75323, 75353,
        75383, 75412, 75442, 75472, 75501, 75531, 75560, 75590, 75619, 75648, 75678, 75707,
        75737, 75766, 75796, 75826, 75856, 75885, 75915, 75944, 75974, 76003, 76032, 76062,
        76091, 76121, 76150, 76180, 76210, 76239, 76269, 76299, 76328, 76358, 76387, 76416,
        76446, 76475, 76505, 76534, 76564, 76593, 76623, 76653, 76682, 76712, 76741, 76771,
        76801, 76830, 76859, 76889, 76918, 76948, 76977, 77007, 77036, 77066, 77096, 77125,
        77155, 77185, 77214, 77243, 77273, 77302, 77332, 77361, 77390, 77420, 77450, 77479,
        77509, 77539, 77569, 77598, 77627, 77657, 77686, 77715, 77745, 77774, 77804, 77833,
        77863, 77893, 77923, 77952, 77982, 78011, 78041, 78070, 78099, 78129, 78158, 78188,
        78217, 78247, 78277, 78307, 78336, 78366, 78395, 78425, 78454, 78483, 78513, 78542,
        78572, 78601, 78631, 78661, 78690, 78720, 78750, 78779, 78808, 78838, 78867, 78897,
        78926, 78956, 78985, 79015, 79044, 79074, 79104, 79133, 79163, 79192, 79222, 79251,
        79281, 79310, 79340, 79369, 79399, 79428, 79458, 79487, 79517, 79546, 79576, 79606,
        79635, 79665, 79695, 79724, 79753, 79783, 79812, 79841, 79871, 79900, 79930, 79960,
        79990,
    ]

    static func hijri(year: Int, month: Int, day: Int) -> (year: Int, month: Int, day: Int)? {
        var y = year
        var m = month
        if m < 3 {
            y -= 1
            m += 12
        }
        let a = y / 100
        let gregorianCorrection = a - a / 4 - 2
        let cjdn = Int(floor(365.25 * Double(y + 4716)))
            + Int(floor(30.6001 * Double(m + 1)))
            + day - gregorianCorrection - 1524
        let mcjdn = cjdn - 2_400_000
        guard let index = monthStarts.firstIndex(where: { $0 > mcjdn }), index > 0 else {
            return nil
        }
        let lunation = index + 16260
        let ii = (lunation - 1) / 12
        let hijriYear = ii + 1
        let hijriMonth = lunation - 12 * ii
        let hijriDay = mcjdn - monthStarts[index - 1] + 1
        return (hijriYear, hijriMonth, hijriDay)
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

    // MARK: Adaptive (Light/Dark) surface colors — v1.0.4
    //
    // Native Light & Dark Mode: surfaces are warm white in Light Mode and
    // deep green in Dark Mode, and every text color below is chosen to stay
    // high-contrast in BOTH appearances for low-vision readers:
    // deep green #0B3D2E on white is ~10.9:1, white on the green gradient
    // is ~7.5:1 or better, and the adaptive gold is ~5.9:1 on white and
    // ~9:1 on deep green. Nothing readable is drawn in pale gold or in
    // white/green below ~0.7 opacity.

    private static func themed(dark: UIColor, light: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    private static var deepGreenUI: UIColor { UIColor(red: 0.043, green: 0.239, blue: 0.180, alpha: 1) }

    /// The user's chosen accent color (Appearance settings, v1.0.5),
    /// auto-adjusted per appearance so it stays readable: brightened for
    /// dark surfaces, deepened for light ones (the HSB adjustment keeps
    /// the hue, so gold stays gold). Defaults to the signature gold.
    static var adaptiveGold: Color {
        Color(uiColor: UIColor { traits in
            let base = AppAppearance.accentUIColor
            return traits.userInterfaceStyle == .dark
                ? base.adjustedForDarkSurface()
                : base.adjustedForLightSurface()
        })
    }

    // MARK: Theme colors (user-pickable, v1.0.5)
    //
    // The Settings page lets the user recolor the app: the MAIN color
    // replaces the signature green on the app cards and buttons, the
    // TEXT color is the main text color on those colored surfaces, and
    // the ACCENT (adaptiveGold above) drives countdowns and highlights.
    // All three are stored in the App Group, so the Home Screen widgets
    // and the Live Activity follow the same theme. Text colors pass a
    // contrast guard (see AppAppearance.resolvedTextUIColor) so a picked
    // color can never become unreadable for low-vision users.

    /// The user's main color (default: the signature deep green).
    static var primary: Color { Color(uiColor: AppAppearance.primaryUIColor) }

    /// Main color lightened — top of the card gradient.
    static var primaryBright: Color {
        Color(uiColor: AppAppearance.primaryUIColor.lightened(by: 0.16))
    }

    /// Main color darkened — bottom of the card gradient, text on gold.
    static var primaryDeep: Color {
        Color(uiColor: AppAppearance.primaryUIColor.darkened(by: 0.30))
    }

    /// Text drawn on main-color surfaces (cards in Dark Mode, buttons in
    /// both modes): the picked text color, contrast-guarded.
    static var onPrimaryText: Color {
        Color(uiColor: AppAppearance.resolvedTextUIColor(forDarkSurface: true))
    }

    /// Primary text on adaptive surfaces.
    static var onSurface: Color {
        themed(
            dark: AppAppearance.resolvedTextUIColor(forDarkSurface: true),
            light: AppAppearance.resolvedTextUIColor(forDarkSurface: false)
        )
    }

    /// Secondary text on adaptive surfaces.
    static var onSurfaceSecondary: Color {
        themed(
            dark: AppAppearance.resolvedTextUIColor(forDarkSurface: true).withAlphaComponent(0.85),
            light: AppAppearance.resolvedTextUIColor(forDarkSurface: false).withAlphaComponent(0.84)
        )
    }

    /// Muted text on adaptive surfaces (captions, column headers).
    static var onSurfaceMuted: Color {
        themed(
            dark: AppAppearance.resolvedTextUIColor(forDarkSurface: true).withAlphaComponent(0.72),
            light: AppAppearance.resolvedTextUIColor(forDarkSurface: false).withAlphaComponent(0.74)
        )
    }

    /// Translucent panel fill on adaptive surfaces.
    static var panelFill: Color {
        themed(
            dark: UIColor.white.withAlphaComponent(0.09),
            light: AppAppearance.primaryUIColor.withAlphaComponent(0.06)
        )
    }

    /// Hairline borders and dividers on adaptive surfaces.
    static var hairline: Color {
        themed(
            dark: UIColor.white.withAlphaComponent(0.16),
            light: AppAppearance.primaryUIColor.withAlphaComponent(0.22)
        )
    }

    /// Live Activity background tint (matches AdaptiveSurfaceBackground:
    /// pure black in Dark Mode, pure white in Light Mode — v1.0.5). An
    /// explicit Light/Dark choice in Settings wins over the system.
    static var activityTint: Color {
        switch AppAppearance.mode {
        case .light: return .white
        case .dark: return .black
        case .system: return themed(dark: .black, light: .white)
        }
    }
}

// MARK: - Appearance settings (shared app + widgets, v1.0.5)

/// User appearance choices, stored in the App Group so the app, the Home
/// Screen widgets and the Live Activity all follow the same settings:
/// - Mode: System (follow iOS), Light, or Dark — the app applies it with
///   preferredColorScheme; widgets resolve it against the system scheme.
/// - Main color: replaces the signature green on cards and buttons.
/// - Accent: countdowns, highlights, progress bar.
/// - Text color: the main text color on colored surfaces (contrast-guarded).
/// - Saved themes: the user's own named combinations of the above.
/// Colors are stored as sRGB hex ints.
enum AppAppearance {
    static let modeKey = "appearance.mode"
    static let accentKey = "appearance.accentHex"
    static let primaryKey = "appearance.primaryHex"
    static let textKey = "appearance.textHex"
    static let iconKey = "appearance.iconName"
    static let savedThemesKey = "appearance.savedThemes"

    static let defaultAccentHex: UInt32 = 0xD4AF37
    static let defaultPrimaryHex: UInt32 = 0x0B3D2E
    static let defaultTextHex: UInt32 = 0xFFFFFF

    enum Mode: String, CaseIterable {
        case system, light, dark

        var label: String {
            switch self {
            case .system: "System"
            case .light: "Light"
            case .dark: "Dark"
            }
        }

        /// nil = follow the system (no override).
        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: PrayerProvider.appGroupIdentifier) ?? .standard
    }

    static var mode: Mode {
        get { Mode(rawValue: sharedDefaults.string(forKey: modeKey) ?? "") ?? .system }
        set { sharedDefaults.set(newValue.rawValue, forKey: modeKey) }
    }

    private static func hex(forKey key: String, default defaultHex: UInt32) -> UInt32 {
        (sharedDefaults.object(forKey: key) as? NSNumber)?.uint32Value ?? defaultHex
    }

    private static func setHex(_ value: UInt32, forKey key: String) {
        sharedDefaults.set(NSNumber(value: value), forKey: key)
    }

    static func uiColor(forHex hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1
        )
    }

    static var accentHex: UInt32 {
        get { hex(forKey: accentKey, default: defaultAccentHex) }
        set { setHex(newValue, forKey: accentKey) }
    }

    static var accentUIColor: UIColor { uiColor(forHex: accentHex) }
    static var accent: Color { Color(uiColor: accentUIColor) }

    static var primaryHex: UInt32 {
        get { hex(forKey: primaryKey, default: defaultPrimaryHex) }
        set { setHex(newValue, forKey: primaryKey) }
    }

    static var primaryUIColor: UIColor { uiColor(forHex: primaryHex) }

    static var textHex: UInt32 {
        get { hex(forKey: textKey, default: defaultTextHex) }
        set { setHex(newValue, forKey: textKey) }
    }

    static var textUIColor: UIColor { uiColor(forHex: textHex) }

    /// The picked text color made safe for its surface. On dark (main
    /// color) surfaces the default is plain white; on light (white)
    /// surfaces the default is the deepened main color. A picked color
    /// is blended toward white (dark surfaces) or black (light surfaces)
    /// until it reaches ~4.5:1 contrast with its background, so text can
    /// never end up unreadable for low-vision users.
    static func resolvedTextUIColor(forDarkSurface dark: Bool) -> UIColor {
        let picked = textUIColor
        if dark {
            if sharedDefaults.object(forKey: textKey) == nil { return .white }
            return picked.ensuringContrast(against: primaryUIColor, minimum: 4.5, blendToward: .white)
        }
        if sharedDefaults.object(forKey: textKey) == nil {
            return primaryUIColor.darkened(by: 0.15)
        }
        // A near-white pick on a white surface would vanish: use the
        // deepened main color instead of an unreadable light gray.
        if picked.relativeLuminance > 0.75 { return primaryUIColor.darkened(by: 0.15) }
        return picked.ensuringContrast(against: .white, minimum: 4.5, blendToward: .black)
    }

    /// The color scheme surfaces should render in: the stored mode wins,
    /// System defers to the ambient (system) scheme.
    static func resolvedColorScheme(system: ColorScheme) -> ColorScheme {
        mode.colorScheme ?? system
    }

    // MARK: Pickers' preset swatches

    /// Accent presets (name, sRGB hex).
    static let presets: [(name: String, hex: UInt32)] = [
        ("Gold", 0xD4AF37),
        ("Emerald", 0x10B981),
        ("Teal", 0x14B8A6),
        ("Sky", 0x38BDF8),
        ("Blue", 0x3B82F6),
        ("Violet", 0x8B5CF6),
        ("Rose", 0xF43F5E),
        ("Orange", 0xF97316),
    ]

    /// Main-color presets: deep, saturated colors that carry white text.
    static let primaryPresets: [(name: String, hex: UInt32)] = [
        ("Mosque Green", 0x0B3D2E),
        ("Midnight", 0x0F2440),
        ("Ocean", 0x083344),
        ("Royal", 0x2E1065),
        ("Rosewood", 0x571233),
        ("Bronze", 0x6B4420),
        ("Forest", 0x14532D),
        ("Charcoal", 0x171717),
    ]

    /// Text-color presets.
    static let textPresets: [(name: String, hex: UInt32)] = [
        ("White", 0xFFFFFF),
        ("Warm White", 0xFFF8E7),
        ("Soft Gold", 0xF2CD5C),
        ("Deep Green", 0x0B3D2E),
        ("Black", 0x111111),
    ]

    // MARK: Themes

    /// A complete, apply-in-one-tap look: main + accent + text + mode.
    struct ThemeChoice: Codable, Identifiable, Hashable {
        var id: String
        var name: String
        var primaryHex: UInt32
        var accentHex: UInt32
        var textHex: UInt32
        var modeRaw: String

        var mode: Mode { Mode(rawValue: modeRaw) ?? .system }
    }

    /// Curated theme pairs, designed to work as sets (deep main color,
    /// a bright harmonious accent, near-white text with full contrast).
    static let presetThemes: [ThemeChoice] = [
        ThemeChoice(id: "preset-mosque", name: "Mosque Green & Gold",
                    primaryHex: 0x0B3D2E, accentHex: 0xD4AF37, textHex: 0xFFFFFF, modeRaw: "system"),
        ThemeChoice(id: "preset-midnight", name: "Midnight Oasis",
                    primaryHex: 0x0F2440, accentHex: 0x7DD3FC, textHex: 0xF0F9FF, modeRaw: "dark"),
        ThemeChoice(id: "preset-ocean", name: "Ocean Depths",
                    primaryHex: 0x083344, accentHex: 0x67E8F9, textHex: 0xECFEFF, modeRaw: "dark"),
        ThemeChoice(id: "preset-royal", name: "Royal Amethyst",
                    primaryHex: 0x2E1065, accentHex: 0xC4B5FD, textHex: 0xF5F3FF, modeRaw: "dark"),
        ThemeChoice(id: "preset-rose", name: "Rose Garden",
                    primaryHex: 0x571233, accentHex: 0xFDA4AF, textHex: 0xFFF1F2, modeRaw: "dark"),
        ThemeChoice(id: "preset-desert", name: "Desert Dunes",
                    primaryHex: 0x6B4420, accentHex: 0xF2C14E, textHex: 0xFFF8E7, modeRaw: "system"),
        ThemeChoice(id: "preset-forest", name: "Forest Canopy",
                    primaryHex: 0x14532D, accentHex: 0xFDE68A, textHex: 0xF0FDF4, modeRaw: "system"),
        ThemeChoice(id: "preset-charcoal", name: "Charcoal Mono",
                    primaryHex: 0x171717, accentHex: 0xE7E5E4, textHex: 0xFAFAF9, modeRaw: "dark"),
    ]

    /// The user's own saved themes (JSON in the App Group).
    static var savedThemes: [ThemeChoice] {
        get {
            guard let data = sharedDefaults.data(forKey: savedThemesKey),
                  let themes = try? JSONDecoder().decode([ThemeChoice].self, from: data) else { return [] }
            return themes
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                sharedDefaults.set(data, forKey: savedThemesKey)
            }
        }
    }

    /// A snapshot of the current look, ready to save or apply.
    static var currentTheme: ThemeChoice {
        ThemeChoice(
            id: UUID().uuidString, name: "Current",
            primaryHex: primaryHex, accentHex: accentHex, textHex: textHex,
            modeRaw: mode.rawValue
        )
    }

    static func apply(_ theme: ThemeChoice) {
        primaryHex = theme.primaryHex
        accentHex = theme.accentHex
        textHex = theme.textHex
        mode = theme.mode
    }

    /// Appearance back to the shipped defaults (mode System, signature
    /// green + gold, white text, default icon). Saved themes are kept.
    static func resetToDefaults() {
        for key in [modeKey, accentKey, primaryKey, textKey, iconKey] {
            sharedDefaults.removeObject(forKey: key)
        }
    }
}

// MARK: - Per-prayer alert settings (v1.0.5)

/// Which prayers raise an Adhan notification. Stored per prayer in the
/// App Group; the five prayers default ON and Sunrise defaults OFF
/// (Sunrise is not a prayer, but many people like a wake-up marker for
/// the end of Fajr time, so it can be turned on).
enum PrayerAlertSettings {
    static func key(for prayer: Prayer) -> String { "alerts.prayer.\(prayer.rawValue)" }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: PrayerProvider.appGroupIdentifier) ?? .standard
    }

    static func isEnabled(_ prayer: Prayer) -> Bool {
        if let value = sharedDefaults.object(forKey: key(for: prayer)) as? Bool { return value }
        return prayer != .sunrise
    }

    static func setEnabled(_ enabled: Bool, for prayer: Prayer) {
        sharedDefaults.set(enabled, forKey: key(for: prayer))
    }

    static func reset() {
        for prayer in Prayer.allCases {
            sharedDefaults.removeObject(forKey: key(for: prayer))
        }
    }
}

extension UIColor {
    /// WCAG relative luminance (0 = black, 1 = white).
    var relativeLuminance: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return 0 }
        func channel(_ c: CGFloat) -> CGFloat {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    /// WCAG contrast ratio against another color (1...21).
    func contrastRatio(against other: UIColor) -> CGFloat {
        let mine = relativeLuminance
        let theirs = other.relativeLuminance
        return (max(mine, theirs) + 0.05) / (min(mine, theirs) + 0.05)
    }

    /// Blends this color toward `target` in 10% steps until it reaches
    /// the minimum contrast against `background` (or the target itself).
    func ensuringContrast(against background: UIColor, minimum: CGFloat, blendToward target: UIColor) -> UIColor {
        if contrastRatio(against: background) >= minimum { return self }
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a),
              target.getRed(&tr, green: &tg, blue: &tb, alpha: &ta) else { return self }
        for step in 1...10 {
            let fraction = CGFloat(step) / 10.0
            let blended = UIColor(
                red: r + (tr - r) * fraction,
                green: g + (tg - g) * fraction,
                blue: b + (tb - b) * fraction,
                alpha: 1
            )
            if blended.contrastRatio(against: background) >= minimum { return blended }
        }
        return target
    }

    /// HSB lightening (fraction = amount of the way toward full brightness).
    func lightened(by fraction: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        return UIColor(hue: h, saturation: s * (1 - fraction * 0.35),
                       brightness: b + (1 - b) * fraction, alpha: 1)
    }

    /// HSB darkening (fraction = amount of the way toward black).
    func darkened(by fraction: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        return UIColor(hue: h, saturation: s, brightness: b * (1 - fraction), alpha: 1)
    }

    /// Brighten (in HSB) until the color reads clearly on black/dark
    /// surfaces: same hue, brightness at least 0.82.
    func adjustedForDarkSurface() -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        return UIColor(hue: h, saturation: min(s, 0.9), brightness: max(b, 0.82), alpha: 1)
    }

    /// Deepen (in HSB) until the color reads clearly on white: same hue,
    /// brightness at most 0.42 and saturation at least 0.55.
    func adjustedForLightSurface() -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        return UIColor(hue: h, saturation: min(max(s, 0.55), 1.0), brightness: min(b, 0.42), alpha: 1)
    }
}

extension Color {
    /// sRGB hex value of a (solid) color, for persisting picker choices.
    var hexValue: UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (UInt32((r * 255).rounded()) << 16)
            | (UInt32((g * 255).rounded()) << 8)
            | UInt32((b * 255).rounded())
    }
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

/// App-card surface (v1.0.5): in Dark Mode a rich gradient of the user's
/// main color (the signature green by default) with soft light and accent
/// glows; in Light Mode a clean white card with only a whisper of the
/// main color, so cards stay bright and text stays high-contrast.
struct CardSurfaceBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if colorScheme == .dark {
            ZStack {
                LinearGradient(
                    colors: [Theme.primaryBright, Theme.primary, Theme.primaryDeep],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                RadialGradient(colors: [Color.white.opacity(0.16), Color.clear], center: .topLeading, startRadius: 0, endRadius: 260)
                RadialGradient(colors: [Theme.adaptiveGold.opacity(0.15), Color.clear], center: .bottomTrailing, startRadius: 0, endRadius: 240)
                LinearGradient(colors: [Color.white.opacity(0.06), Color.clear], startPoint: .top, endPoint: .center)
            }
        } else {
            ZStack {
                Color.white
                RadialGradient(colors: [Theme.primary.opacity(0.05), Color.clear], center: .topLeading, startRadius: 0, endRadius: 260)
                RadialGradient(colors: [Theme.adaptiveGold.opacity(0.06), Color.clear], center: .bottomTrailing, startRadius: 0, endRadius: 240)
            }
        }
    }
}

/// Surface background for widgets and the Live Activity (v1.0.5, per the
/// user's request): the background stays PURE BLACK in Dark Mode and PURE
/// WHITE in Light Mode, with only a whisper of the accent color glowing
/// in one corner so it still feels like the same app.
struct AdaptiveSurfaceBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var showsWatermark: Bool = false

    var body: some View {
        ZStack {
            colorScheme == .dark ? Color.black : Color.white
            RadialGradient(
                colors: [Theme.adaptiveGold.opacity(colorScheme == .dark ? 0.13 : 0.08), Color.clear],
                center: .bottomTrailing, startRadius: 0, endRadius: 260
            )
            if showsWatermark {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 120, weight: .regular))
                    .foregroundStyle(Theme.adaptiveGold.opacity(0.06))
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
            .tint(Theme.adaptiveGold)
    }
}

// MARK: - Live Activity attributes

/// Live Activity (Lock Screen + Dynamic Island) showing the countdown to
/// the next prayer. The attributes type lives in this shared file so both
/// the app (which starts/updates the activity) and the widget extension
/// (which renders it) see the same definition.
struct PrayerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var prayerName: String
        var symbolName: String
        var adhan: Date
        var iqamah: Date?
        var iqamahLabel: String
        var hijri: String
        var isTomorrow: Bool
        /// The prayer after this one, pre-staged (v1.0.4) so the Lock Screen
        /// can already show "Then: …" before the automatic rollover update
        /// lands. Optional so v1.0.3 activity payloads still decode.
        var followingName: String? = nil
        var followingAdhan: Date? = nil
    }

    var mosqueName: String
}
