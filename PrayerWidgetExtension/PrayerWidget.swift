//
//  PrayerWidget.swift
//  PrayerWidgetExtension
//
//  Widget extension target: PrayerWidgetExtension (com.c12n.alrashidwidget.widget), iOS 17.0+
//  Target Membership: PrayerWidgetExtension only.
//  Shared files (also in this target): PrayerCalculator.swift, PrayerModels.swift
//  Capability: App Groups -> group.com.c12n.alrashidwidget
//

import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Timeline entry

struct PrayerEntry: TimelineEntry, Sendable {
    let date: Date
    let snapshot: PrayerSnapshot

    init(snapshot: PrayerSnapshot) {
        self.date = snapshot.date
        self.snapshot = snapshot
    }
}

// MARK: - Timeline provider

struct PrayerTimelineProvider: TimelineProvider {
    private let provider = PrayerProvider.standard

    func placeholder(in context: Context) -> PrayerEntry {
        PrayerEntry(snapshot: provider.snapshot(at: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (PrayerEntry) -> Void) {
        completion(PrayerEntry(snapshot: provider.snapshot(at: .now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerEntry>) -> Void) {
        let plan = provider.timelinePlan(from: .now)
        let entries = plan.snapshots.map { PrayerEntry(snapshot: $0) }
        completion(Timeline(entries: entries, policy: .after(plan.reloadDate)))
    }
}

// MARK: - Entry view (family router)

struct PrayerWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var systemColorScheme
    let entry: PrayerEntry

    /// Accessory (Lock Screen) families belong to the Lock part; the
    /// system families belong to Home (v2.0.0 widget colors).
    private var part: AppAppearance.WidgetPart {
        switch family {
        case .accessoryRectangular, .accessoryCircular, .accessoryInline:
            return .lock
        default:
            return .home
        }
    }

    private var palette: PartPalette {
        PartPalette(theme: AppAppearance.effectiveTheme(for: part))
    }

    var body: some View {
        // The user's Light/Dark choice in Settings wins over the system
        // appearance (v1.0.5): the stored mode is resolved against the
        // system scheme and applied to the whole widget, background
        // included, so widgets always match the app.
        content
            .environment(\.colorScheme, AppAppearance.resolvedColorScheme(system: systemColorScheme))
            .environment(\.partPalette, palette)
            .environment(\.layoutDirection, AppLanguage.current.isRTL ? .rightToLeft : .leftToRight)
            .environment(\.locale, AppLanguage.current.locale)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            SmallPrayerWidgetView(snapshot: entry.snapshot)
                .homeScreenGlass(watermark: false)
        case .systemMedium:
            MediumPrayerWidgetView(snapshot: entry.snapshot)
                .homeScreenGlass(watermark: true)
        case .systemLarge:
            LargePrayerWidgetView(snapshot: entry.snapshot)
                .homeScreenGlass(watermark: true)
        case .accessoryRectangular:
            RectangularPrayerWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryCircular:
            CircularPrayerWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { Color.clear }
        default:
            SmallPrayerWidgetView(snapshot: entry.snapshot)
                .homeScreenGlass(watermark: false)
        }
    }
}

private extension View {
    /// Home Screen widget surface (v2.0.0): the Home part's palette as
    /// a full-color gradient, per the approved colored-widgets design.
    /// (v1.0.4–v1.8.0 used the black/white AdaptiveSurfaceBackground.)
    func homeScreenGlass(watermark: Bool) -> some View {
        modifier(HomeColoredBackground(watermark: watermark))
    }
}

private struct HomeColoredBackground: ViewModifier {
    @Environment(\.partPalette) private var palette
    let watermark: Bool

    func body(content: Content) -> some View {
        content
            .containerBackground(for: .widget) {
                ColoredSurfaceBackground(palette: palette, showsWatermark: watermark)
            }
    }
}

// MARK: - Widget text size (v1.8.0)

/// Home Screen widget text scales with the in-app text-size setting
/// (Settings → Text Size) — the same AppTextSize the phone UI honors.
/// Lock Screen accessory widgets keep their fixed sizes: their
/// canvases are system-fixed and already minimal.
enum WidgetTextScale {
    static var factor: CGFloat {
        switch AppTextSize.current {
        case .standard: 1.0
        case .large: 1.12
        case .extraLarge: 1.25
        }
    }

    static func size(_ base: CGFloat) -> CGFloat { base * factor }
}

// MARK: - Small

struct SmallPrayerWidgetView: View {
    @Environment(\.partPalette) private var palette
    let snapshot: PrayerSnapshot

    var body: some View {
        let next = snapshot.next
        // Iqamah-first (v2.0.0): in the iqamah phase the small
        // widget counts down to the Iqamah, like the app hero.
        // Minimal Mode (v2.0.0): plain next-prayer variant — no
        // iqamah phase, no Ramadan dressing.
        let phase = MinimalMode.enabled ? nil : PrayerProvider.standard.iqamahPhase(at: snapshot.date)
        let hero = phase ?? next
        let heroTarget = phase?.iqamah ?? next.adhan
        let heroRange = phase.map { $0.adhan...($0.iqamah ?? $0.adhan) } ?? snapshot.countdownRange
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: hero.symbolName)
                    .font(.system(size: WidgetTextScale.size(13), weight: .semibold))
                    .foregroundStyle(palette.accent)
                Text(phase != nil ? L10n.t("iqamahNow").uppercased()
                     : !MinimalMode.enabled && RamadanMode.isRamadan(on: snapshot.date, timeZone: PrayerProvider.standard.calendar.timeZone) && hero.prayer == .maghrib ? L10n.t("iftar").uppercased()
                     : !MinimalMode.enabled && RamadanMode.isRamadan(on: snapshot.date, timeZone: PrayerProvider.standard.calendar.timeZone) && hero.prayer == .fajr ? L10n.t("suhoor").uppercased()
                     : (snapshot.isShowingTomorrow ? L10n.t("tomorrow") : L10n.t("nextPrayerCaps")))
                    .font(.system(size: WidgetTextScale.size(11.5), weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(palette.textMuted)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(PrayerFormat.shortDate(snapshot.day.date))
                    .font(.system(size: WidgetTextScale.size(11.5), weight: .semibold))
                    .foregroundStyle(palette.textMuted)
                    .lineLimit(1)
            }
            Text(hero.name)
                .font(.system(size: WidgetTextScale.size(27), weight: .bold))
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(PrayerFormat.time(heroTarget))
                .font(.system(size: WidgetTextScale.size(18), weight: .semibold).monospacedDigit())
                .foregroundStyle(palette.text)
                .lineLimit(1)
            if phase == nil, let iqamah = next.iqamah {
                Text("\(next.iqamahLabel) \(PrayerFormat.time(iqamah))")
                    .font(.system(size: WidgetTextScale.size(13), weight: .semibold).monospacedDigit())
                    .foregroundStyle(palette.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            Text(timerInterval: heroRange, countsDown: true)
                .font(.system(size: WidgetTextScale.size(25), weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(palette.accent)
                .multilineTextAlignment(.leading)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
            GoldProgressBar(range: phase != nil ? heroRange : snapshot.progressRange, tint: palette.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Medium

struct MediumPrayerWidgetView: View {
    @Environment(\.partPalette) private var palette
    let snapshot: PrayerSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            WidgetHeaderView(snapshot: snapshot, nameSize: WidgetTextScale.size(14), detailSize: WidgetTextScale.size(11.5))
            HStack(alignment: .top, spacing: 8) {
                CompactNextPrayerPanel(snapshot: snapshot)
                    .frame(width: 100)
                PrayerTableView(snapshot: snapshot, fontSize: WidgetTextScale.size(12), timeColumnWidth: WidgetTextScale.size(56), rowVerticalPadding: 0.75)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct WidgetHeaderView: View {
    @Environment(\.partPalette) private var palette
    let snapshot: PrayerSnapshot
    let nameSize: CGFloat
    let detailSize: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: nameSize - 1, weight: .semibold))
                .foregroundStyle(palette.accent)
            Text(MosqueInfo.name)
                .font(.system(size: nameSize, weight: .bold))
                .foregroundStyle(palette.text)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(hijriText)
                .font(.system(size: detailSize, weight: .semibold))
                .foregroundStyle(palette.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var hijriText: String {
        snapshot.isShowingTomorrow ? L10n.f("tomorrowHijri", snapshot.day.hijriDate) : snapshot.day.hijriDate
    }
}

struct CompactNextPrayerPanel: View {
    @Environment(\.partPalette) private var palette
    let snapshot: PrayerSnapshot

    var body: some View {
        let next = snapshot.next
        let phase = PrayerProvider.standard.iqamahPhase(at: snapshot.date)
        let hero = phase ?? next
        let heroTarget = phase?.iqamah ?? next.adhan
        let heroRange = phase.map { $0.adhan...($0.iqamah ?? $0.adhan) } ?? snapshot.countdownRange
        VStack(alignment: .leading, spacing: 1.5) {
            Text(phase != nil ? L10n.t("iqamahNow").uppercased() : L10n.t("nextPrayerCaps"))
                .font(.system(size: WidgetTextScale.size(10), weight: .bold))
                .tracking(0.7)
                .foregroundStyle(palette.textMuted)
                .lineLimit(1)
            Text(hero.name)
                .font(.system(size: WidgetTextScale.size(19), weight: .bold))
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(PrayerFormat.time(heroTarget))
                .font(.system(size: WidgetTextScale.size(13.5), weight: .semibold).monospacedDigit())
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if phase == nil, let iqamah = next.iqamah {
                Text("\(next.iqamahLabel) \(PrayerFormat.time(iqamah))")
                    .font(.system(size: WidgetTextScale.size(11), weight: .semibold).monospacedDigit())
                    .foregroundStyle(palette.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
            Text(timerInterval: heroRange, countsDown: true)
                .font(.system(size: WidgetTextScale.size(18), weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(palette.accent)
                .multilineTextAlignment(.leading)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.panelFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.hairline, lineWidth: 0.5)
        }
    }
}

// MARK: - Shared table (medium & large)

struct PrayerTableView: View {
    @Environment(\.partPalette) private var palette
    let snapshot: PrayerSnapshot
    let fontSize: CGFloat
    let timeColumnWidth: CGFloat
    let rowVerticalPadding: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(L10n.t("colPrayer")).frame(maxWidth: .infinity, alignment: .leading)
                Text(L10n.t("colAdhan")).frame(width: timeColumnWidth, alignment: .trailing)
                Text(L10n.t("colIqamah")).frame(width: timeColumnWidth, alignment: .trailing)
            }
            .font(.system(size: max(fontSize - 3, 8.5), weight: .bold))
            .tracking(0.5)
            .foregroundStyle(palette.textMuted)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.bottom, 2)
            ForEach(snapshot.day.slots) { slot in
                let isNext = snapshot.isNext(slot)
                PrayerTableRow(slot: slot, isNext: isNext, fontSize: fontSize, timeColumnWidth: timeColumnWidth)
                    .padding(.horizontal, 6)
                    .padding(.vertical, rowVerticalPadding)
                    .frame(maxHeight: .infinity)
                    .background {
                        if isNext {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(palette.accent.opacity(0.22))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(palette.accent.opacity(0.65), lineWidth: 0.6)
                                }
                        }
                    }
            }
        }
    }
}

struct PrayerTableRow: View {
    @Environment(\.partPalette) private var palette
    let slot: PrayerSlot
    let isNext: Bool
    let fontSize: CGFloat
    let timeColumnWidth: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: slot.symbolName)
                    .font(.system(size: fontSize - 1.5, weight: .semibold))
                    .frame(width: fontSize + 2)
                Text(slot.name)
                    .font(.system(size: fontSize, weight: isNext ? .bold : .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(PrayerFormat.time(slot.adhan))
                .frame(width: timeColumnWidth, alignment: .trailing)
            Text(slot.iqamah.map { PrayerFormat.time($0) } ?? "—")
                .frame(width: timeColumnWidth, alignment: .trailing)
        }
        .font(.system(size: fontSize, weight: isNext ? .bold : .medium).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .foregroundStyle(foreground)
    }

    private var foreground: Color {
        if isNext { return palette.accent }
        return slot.prayer == .sunrise ? palette.textMuted : palette.text
    }
}

// MARK: - Large

struct LargePrayerWidgetView: View {
    @Environment(\.partPalette) private var palette
    let snapshot: PrayerSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LargeHeaderView(snapshot: snapshot)
            LargeNextPrayerBanner(snapshot: snapshot)
            PrayerTableView(snapshot: snapshot, fontSize: WidgetTextScale.size(15), timeColumnWidth: WidgetTextScale.size(74), rowVerticalPadding: 2)
                .frame(maxHeight: .infinity)
            LargeVerseView(snapshot: snapshot)
            LargeFooterView(snapshot: snapshot)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The Quran quote of the day, under the prayer table (v1.5).
struct LargeVerseView: View {
    @Environment(\.partPalette) private var palette
    let snapshot: PrayerSnapshot

    var body: some View {
        let verse = DailyVerses.verse(for: snapshot.date)
        VStack(spacing: 2) {
            Text(verse.arabic)
                .font(.system(size: WidgetTextScale.size(13.5), weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(palette.text)
            Text(verse.reference(for: AppLanguage.current))
                .font(.system(size: WidgetTextScale.size(11), weight: .semibold))
                .foregroundStyle(palette.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }
}

struct LargeHeaderView: View {
    @Environment(\.partPalette) private var palette
    let snapshot: PrayerSnapshot

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: WidgetTextScale.size(14), weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 28, height: 28)
                .background(palette.accent.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(MosqueInfo.name)
                    .font(.system(size: WidgetTextScale.size(18), weight: .bold))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(snapshot.day.hijriDate)
                        .foregroundStyle(palette.accent)
                    Text("·")
                        .foregroundStyle(palette.textMuted)
                    Text(PrayerFormat.shortDate(snapshot.day.date))
                        .foregroundStyle(palette.textSecondary)
                }
                .font(.system(size: WidgetTextScale.size(12.5), weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            if snapshot.isShowingTomorrow {
                WidgetPill(text: "TOMORROW")
            } else if snapshot.day.isFriday {
                WidgetPill(text: "JUMU'AH")
            }
        }
    }
}

struct WidgetPill: View {
    @Environment(\.partPalette) private var palette
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: WidgetTextScale.size(10.5), weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(palette.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(palette.accent.opacity(0.22), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(palette.accent.opacity(0.5), lineWidth: 0.5)
            }
    }
}

struct LargeNextPrayerBanner: View {
    @Environment(\.partPalette) private var palette
    let snapshot: PrayerSnapshot

    var body: some View {
        let next = snapshot.next
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: next.symbolName)
                    .font(.system(size: WidgetTextScale.size(18), weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .frame(width: 34, height: 34)
                    .background(palette.panelFill, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(snapshot.isShowingTomorrow ? L10n.t("nextPrayerTomorrowCaps") : L10n.t("nextPrayerCaps"))
                        .font(.system(size: WidgetTextScale.size(10.5), weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(palette.textMuted)
                        .lineLimit(1)
                    Text(next.name)
                        .font(.system(size: WidgetTextScale.size(21), weight: .bold))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(detailText)
                        .font(.system(size: WidgetTextScale.size(12.5), weight: .medium).monospacedDigit())
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 4)
                Text(timerInterval: snapshot.countdownRange, countsDown: true)
                    .font(.system(size: WidgetTextScale.size(28), weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(palette.accent)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: 110, alignment: .trailing)
            }
            GoldProgressBar(range: snapshot.progressRange, tint: palette.accent)
        }
        .padding(10)
        .background(palette.panelFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.hairline, lineWidth: 0.75)
        }
    }

    private var detailText: String {
        let next = snapshot.next
        let adhan = L10n.f("adhanAt", PrayerFormat.time(next.adhan))
        guard let iqamah = next.iqamah else { return adhan }
        return "\(adhan) · \(next.iqamahLabel) \(PrayerFormat.time(iqamah))"
    }
}

struct LargeFooterView: View {
    @Environment(\.partPalette) private var palette
    let snapshot: PrayerSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Rectangle()
                .fill(palette.hairline)
                .frame(height: 0.5)
                .padding(.bottom, 2)
            HStack(spacing: 5) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(palette.accent)
                Text(MosqueInfo.address)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            HStack(spacing: 5) {
                Image(systemName: "building.columns.fill")
                    .foregroundStyle(palette.accent)
                Text(jumuahNote)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .font(.system(size: WidgetTextScale.size(12), weight: .medium))
        .foregroundStyle(palette.textSecondary)
    }

    private var jumuahNote: String {
        let khutbah = PrayerFormat.khutbahTime(on: snapshot.day.date)
        let label = snapshot.day.slots.first(where: { $0.isJumuah })?.iqamahLabel ?? "Khutbah"
        return snapshot.day.isFriday
            ? "\(L10n.t("jumuahToday")) · \(label) \(khutbah)"
            : "\(L10n.t("jumuahWeekly")) · \(label) \(khutbah)"
    }
}

// MARK: - Lock Screen: rectangular

struct RectangularPrayerWidgetView: View {
    @Environment(\.partPalette) private var palette
    let snapshot: PrayerSnapshot

    var body: some View {
        let next = snapshot.next
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: next.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                Text(next.name)
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                Text(PrayerFormat.time(next.adhan))
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .widgetAccentable()
            if let iqamah = next.iqamah {
                Text("\(next.iqamahLabel) \(PrayerFormat.time(iqamah))")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            HStack(spacing: 3) {
                Image(systemName: "hourglass")
                    .font(.system(size: 11, weight: .semibold))
                Text(timerInterval: snapshot.countdownRange, countsDown: true)
                    .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Lock Screen: circular

struct CircularPrayerWidgetView: View {
    @Environment(\.partPalette) private var palette
    let snapshot: PrayerSnapshot

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: snapshot.next.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .widgetAccentable()
                Text(snapshot.next.shortName)
                    .font(.system(size: 10, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
                Text(PrayerFormat.compactTime(snapshot.next.adhan))
                    .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Widget & bundle

struct PrayerWidget: Widget {
    let kind: String = PrayerProvider.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PrayerTimelineProvider()) { entry in
            PrayerWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(L10n.t("widgetName"))
        .description(L10n.t("widgetDescription"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular])
    }
}

// MARK: - Continue Listening widget (v2.3.0)

/// Reads the session snapshot the app mirrors into the App Group
/// (QuranPlayer.writeWidgetSnapshot). Tapping opens the app via
/// the alrashid://resume-quran deep link, which resumes playback
/// and presents the full player.
struct ContinueListeningEntry: TimelineEntry {
    let date: Date
    let has: Bool
    let surah: String
    let arabic: String
    let reciter: String
    let fraction: Double
}

struct ContinueListeningProvider: TimelineProvider {
    private func readEntry() -> ContinueListeningEntry {
        let suite = UserDefaults(suiteName: PrayerProvider.appGroupIdentifier)
        let has = suite?.bool(forKey: "quran.widget.has") ?? false
        let position = suite?.double(forKey: "quran.widget.position") ?? 0
        let duration = suite?.double(forKey: "quran.widget.duration") ?? 0
        return ContinueListeningEntry(
            date: .now,
            has: has,
            surah: suite?.string(forKey: "quran.widget.surah") ?? "",
            arabic: suite?.string(forKey: "quran.widget.arabic") ?? "",
            reciter: suite?.string(forKey: "quran.widget.reciter") ?? "",
            fraction: duration > 0 ? min(1, max(0, position / duration)) : 0)
    }

    func placeholder(in context: Context) -> ContinueListeningEntry {
        ContinueListeningEntry(date: .now, has: true, surah: "An-Nisaa",
                               arabic: "النساء",
                               reciter: "Mishary Rashid Alafasy", fraction: 0.35)
    }

    func getSnapshot(in context: Context,
                     completion: @escaping (ContinueListeningEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context,
                     completion: @escaping (Timeline<ContinueListeningEntry>) -> Void) {
        // Reloads are driven by the app (WidgetCenter.reloadTimelines
        // on pause / position saves), so the policy is .never.
        completion(Timeline(entries: [readEntry()], policy: .never))
    }
}

struct ContinueListeningWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ContinueListeningEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(entry.arabic.isEmpty ? "﷽" : entry.arabic)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color(red: 0.04, green: 0.24, blue: 0.18))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: 40, height: 40)
                    .background(
                        LinearGradient(colors: [Color(red: 0.93, green: 0.80, blue: 0.47),
                                                Color(red: 0.79, green: 0.64, blue: 0.15)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.t("continueListening"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color(red: 0.93, green: 0.80, blue: 0.47))
                    Text(entry.has ? entry.surah : "Quran")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            if entry.has {
                if !entry.reciter.isEmpty {
                    Text(entry.reciter)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.22))
                        Capsule()
                            .fill(Color(red: 0.93, green: 0.80, blue: 0.47))
                            .frame(width: proxy.size.width * entry.fraction)
                    }
                }
                .frame(height: 3)
                Text(L10n.t("tapToResume"))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 0.05, green: 0.30, blue: 0.22),
                                    Color(red: 0.03, green: 0.20, blue: 0.15)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .widgetURL(URL(string: "alrashid://resume-quran"))
    }
}

struct ContinueListeningWidget: Widget {
    let kind: String = "ContinueListeningWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ContinueListeningProvider()) { entry in
            ContinueListeningWidgetView(entry: entry)
        }
        .configurationDisplayName(L10n.t("continueListening"))
        .description(L10n.t("tapToResume"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct PrayerWidgetBundle: WidgetBundle {
    var body: some Widget {
        PrayerWidget()
        ContinueListeningWidget()
        PrayerLiveActivity()
        if #available(iOS 18.0, *) {
            SilenceNextAlertControl()
        }
    }
}

/// iOS 18 Control Center / Lock Screen control (v2.0.0, feature 7):
/// one tap silences only the next Adhan alert. Runs
/// SilenceNextAlertIntent from this extension; the flag lands in the
/// App Group and the app's scheduler applies it on its next rebuild.
@available(iOS 18.0, *)
struct SilenceNextAlertControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.c12n.alrashidwidget.silenceNextAlert") {
            ControlWidgetButton(action: SilenceNextAlertIntent()) {
                Label("Silence Next Alert", systemImage: "bell.slash.fill")
            }
        }
        .displayName("Silence Next Alert")
        .description("Silence only the next Adhan alert from Al Rashid Prayer.")
    }
}

// MARK: - Previews

#Preview(as: .systemSmall) { PrayerWidget() } timeline: {
    PrayerEntry(snapshot: PrayerProvider.standard.snapshot(at: .now))
}
#Preview(as: .systemMedium) { PrayerWidget() } timeline: {
    PrayerEntry(snapshot: PrayerProvider.standard.snapshot(at: .now))
}
#Preview(as: .systemLarge) { PrayerWidget() } timeline: {
    PrayerEntry(snapshot: PrayerProvider.standard.snapshot(at: .now))
}
#Preview(as: .accessoryRectangular) { PrayerWidget() } timeline: {
    PrayerEntry(snapshot: PrayerProvider.standard.snapshot(at: .now))
}
#Preview(as: .accessoryCircular) { PrayerWidget() } timeline: {
    PrayerEntry(snapshot: PrayerProvider.standard.snapshot(at: .now))
}

// MARK: - Live Activity (Lock Screen + Dynamic Island)

/// One prayer as staged in the activity's ContentState, resolved for
/// display: the current next prayer, the one after it, and (v1.1.2)
/// the one after that.
private struct StagedPrayer {
    var name: String
    var symbolName: String
    var adhan: Date
    var iqamah: Date?
    var iqamahLabel: String
    var isTomorrow: Bool
}

private func stagedPrayers(for state: PrayerActivityAttributes.ContentState) -> [StagedPrayer] {
    var prayers = [StagedPrayer(
        name: state.prayerName, symbolName: state.symbolName, adhan: state.adhan,
        iqamah: state.iqamah, iqamahLabel: state.iqamahLabel, isTomorrow: state.isTomorrow
    )]
    if let name = state.followingName, let adhan = state.followingAdhan {
        let followingTomorrow = state.isTomorrow
            || !Calendar.current.isDate(adhan, inSameDayAs: state.adhan)
        prayers.append(StagedPrayer(
            name: name, symbolName: state.followingSymbolName ?? state.symbolName,
            adhan: adhan, iqamah: state.followingIqamah,
            iqamahLabel: state.followingIqamahLabel ?? state.iqamahLabel,
            isTomorrow: followingTomorrow
        ))
        if let thirdName = state.thirdName, let thirdAdhan = state.thirdAdhan {
            let thirdTomorrow = followingTomorrow
                || !Calendar.current.isDate(thirdAdhan, inSameDayAs: adhan)
            prayers.append(StagedPrayer(
                name: thirdName, symbolName: state.thirdSymbolName ?? state.symbolName,
                adhan: thirdAdhan, iqamah: state.thirdIqamah,
                iqamahLabel: state.thirdIqamahLabel ?? state.iqamahLabel,
                isTomorrow: thirdTomorrow
            ))
        }
    }
    return prayers
}

/// Which staged prayer the activity displays, decided by `isStale`
/// (v1.1.2). The activity's staleDate is the next prayer's Adhan
/// (see LiveActivityController): before it, the system renders the
/// activity as fresh and shows the next prayer counting down; when
/// the Adhan passes, the system re-renders it as stale and this
/// promotes the pre-staged following prayer, whose own countdown is
/// a self-updating timer text — no app process needs to run, and no
/// TimelineView is involved (Apple doesn't document TimelineView
/// inside Live Activities, and developer reports show its closure
/// runs only a couple of times there). The countdown interval runs
/// from the previous boundary to the displayed prayer's Adhan, so it
/// holds at zero instead of counting up if a render lands late.
private func displayedPrayers(
    state: PrayerActivityAttributes.ContentState,
    isStale: Bool
) -> (current: StagedPrayer, then: StagedPrayer?, countdown: ClosedRange<Date>) {
    let prayers = stagedPrayers(for: state)
    var index = isStale && prayers.count > 1 ? 1 : 0
    // v1.5.2: also advance by the clock. If a render lands after the
    // displayed prayer's Adhan (the stale re-render can arrive late),
    // show the prayer that is actually next instead of a frozen 0:00
    // on the finished one. Only comparisons use the clock — the
    // countdown range below is still built purely from staged dates.
    let now = Date()
    while index + 1 < prayers.count, prayers[index].adhan <= now {
        // Jumu'ah mode holds the Jumu'ah prayer until the Khutbah.
        if !MinimalMode.enabled,
           prayers[index].symbolName == "building.columns.fill",
           let khutbah = prayers[index].iqamah, now < khutbah {
            break
        }
        index += 1
    }
    let current = prayers[index]
    // Minimal Mode (v2.0.0): the activity reduces to the basic
    // next-prayer countdown — no following-prayer line, no
    // Iqamah-first or Jumu'ah dressing.
    if MinimalMode.enabled {
        let plainStart = index == 0
            ? (state.stagedAt ?? current.adhan.addingTimeInterval(-6 * 3600))
            : prayers[index - 1].adhan
        return (current, nil, plainStart...current.adhan)
    }
    let then = index + 1 < prayers.count ? prayers[index + 1] : nil
    let start = index == 0
        ? (state.stagedAt ?? state.adhan.addingTimeInterval(-6 * 3600))
        : prayers[index - 1].adhan
    // Jumu'ah mode (v2.0.0, workstream 9): on Fridays from midday
    // the displayed Jumu'ah prayer counts down to the 1:30 PM
    // Khutbah (its iqamah slot) — labelled Jumu'ah, never Dhuhr —
    // then the normal flow resumes after the Khutbah.
    if current.symbolName == "building.columns.fill",
       let khutbah = current.iqamah, now < khutbah,
       Calendar.current.component(.hour, from: now) >= 12 {
        let jumuahStart = index == 0
            ? (state.stagedAt ?? current.adhan.addingTimeInterval(-6 * 3600))
            : prayers[index - 1].adhan
        return (current, then, jumuahStart...khutbah)
    }
    // Iqamah-first (v2.0.0): if the displayed prayer's Adhan has
    // passed but its Iqamah is still ahead, count down to the
    // Iqamah instead of the Adhan (which would sit at 0:00).
    if IqamahCountdownSettings.enabled, let iqamah = current.iqamah,
       current.adhan <= now, now < iqamah {
        return (current, then, current.adhan...iqamah)
    }
    return (current, then, start...current.adhan)
}

struct PrayerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PrayerActivityAttributes.self) { context in
            // The Live Activity part's palette (v2.0.0 widget colors).
            let palette = PartPalette(theme: AppAppearance.effectiveTheme(for: .liveActivity))
            LiveActivityRootView(state: context.state, isStale: context.isStale, palette: palette)
                .activityBackgroundTint(palette.primaryDeep)
                .activitySystemActionForegroundColor(palette.text)
        } dynamicIsland: { context in
            let palette = PartPalette(theme: AppAppearance.effectiveTheme(for: .liveActivity))
            let state = context.state
            let display = displayedPrayers(state: state, isStale: context.isStale)
            let phase = display.current
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: phase.symbolName)
                            .foregroundStyle(palette.accent)
                        Text(phase.name)
                            .font(.headline)
                            .foregroundStyle(palette.text)
                    }
                    .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: display.countdown, countsDown: true)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(palette.accent)
                        .frame(maxWidth: 92, alignment: .trailing)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(L10n.f("adhanAt", PrayerFormat.time(phase.adhan)))
                        Spacer()
                        if let iqamah = phase.iqamah {
                            Text("\(phase.iqamahLabel) \(PrayerFormat.time(iqamah))")
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                Image(systemName: phase.symbolName)
                    .foregroundStyle(palette.accent)
            } compactTrailing: {
                Text(timerInterval: display.countdown, countsDown: true)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(palette.accent)
                    .frame(maxWidth: 64, alignment: .trailing)
            } minimal: {
                Image(systemName: phase.symbolName)
                    .foregroundStyle(palette.accent)
            }
            .keylineTint(palette.accent)
        }
    }
}

/// Applies the user's Settings Light/Dark choice to the Live Activity,
/// resolved against the system appearance (v1.0.5).
private struct LiveActivityRootView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    let state: PrayerActivityAttributes.ContentState
    let isStale: Bool
    let palette: PartPalette

    var body: some View {
        LiveActivityLockScreenView(state: state, isStale: isStale)
            .environment(\.partPalette, palette)
            .environment(\.colorScheme, AppAppearance.resolvedColorScheme(system: systemColorScheme))
            .environment(\.layoutDirection, AppLanguage.current.isRTL ? .rightToLeft : .leftToRight)
            .environment(\.locale, AppLanguage.current.locale)
    }
}

private struct LiveActivityLockScreenView: View {
    @Environment(\.partPalette) private var palette
    let state: PrayerActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        let display = displayedPrayers(state: state, isStale: isStale)
        let phase = display.current
        let then = display.then
        ZStack {
            ColoredSurfaceBackground(palette: palette)
            VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "moon.stars.fill")
                            .foregroundStyle(palette.accent)
                        Text(MosqueInfo.name)
                            .font(.caption.weight(.bold))
                            .tracking(0.6)
                            .foregroundStyle(palette.textSecondary)
                        Spacer()
                        Text("\(PrayerFormat.shortDate(phase.adhan)) · \(hijri(for: phase))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: phase.symbolName)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(palette.accent)
                        Text(phase.isTomorrow ? L10n.f("nameTomorrow", phase.name) : phase.name)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(palette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Spacer(minLength: 8)
                        Text(PrayerFormat.time(phase.adhan))
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .foregroundStyle(palette.text)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(timerInterval: display.countdown, countsDown: true)
                            .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(palette.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Spacer(minLength: 8)
                        if let iqamah = phase.iqamah {
                            Text("\(phase.iqamahLabel) \(PrayerFormat.time(iqamah))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                    if let then {
                        Text(L10n.f("thenPattern", then.name, PrayerFormat.time(then.adhan)))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(palette.textMuted)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
        }
    }

    /// The Hijri date for the DISPLAYED prayer's day — after the stale
    /// flip promotes tomorrow's Fajr the staged `state.hijri` (the day
    /// the state was built for) would be a day behind, so compute it
    /// for the displayed prayer's own date.
    private func hijri(for phase: StagedPrayer) -> String {
        PrayerProvider.hijriString(
            for: phase.adhan,
            timeZone: PrayerProvider.standard.calendar.timeZone
        )
    }
}

/// How rollover works (v1.1.2): the activity's staleDate is the next
/// prayer's Adhan. Before it, the Lock Screen shows that prayer with
/// a self-updating countdown; when the Adhan passes, the system
/// re-renders the activity with isStale = true and displayedPrayers
/// promotes the pre-staged following prayer — the switch no longer
/// waits for the background refresh, whose earliestBeginDate Apple
/// documents as a floor rather than a promise (on this phone it was
/// landing far too late, so the Lock Screen sat on the finished
/// prayer). This is the one date-triggered view change ActivityKit
/// documents; TimelineView inside a Live Activity is not documented
/// and developer reports show it barely re-runs — v1.0.6 tried it and
/// promoted the following prayer hours early. Each app open or
/// background run re-stages the prayers and moves the stale date to
/// the new next Adhan, buying the next on-time switch. Apple also
/// caps an activity at ~8 hours active (up to 4 more on the Lock
/// Screen), so a long winter Isha→Fajr gap can still outlive one
/// activity until the next re-stage.
