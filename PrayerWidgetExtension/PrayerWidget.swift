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

    var body: some View {
        // The user's Light/Dark choice in Settings wins over the system
        // appearance (v1.0.5): the stored mode is resolved against the
        // system scheme and applied to the whole widget, background
        // included, so widgets always match the app.
        content
            .environment(\.colorScheme, AppAppearance.resolvedColorScheme(system: systemColorScheme))
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
    /// Widget surface that follows the system appearance (v1.0.4): warm
    /// white in Light Mode, green glass in Dark Mode. (Before v1.0.4 the
    /// widgets forced Dark Mode in both appearances.)
    func homeScreenGlass(watermark: Bool) -> some View {
        self
            .containerBackground(for: .widget) {
                AdaptiveSurfaceBackground(showsWatermark: watermark)
            }
    }
}

// MARK: - Small

struct SmallPrayerWidgetView: View {
    let snapshot: PrayerSnapshot

    var body: some View {
        let next = snapshot.next
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: next.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.adaptiveGold)
                Text(snapshot.isShowingTomorrow ? "TOMORROW" : "NEXT PRAYER")
                    .font(.system(size: 11.5, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.onSurfaceMuted)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(PrayerFormat.shortDate(snapshot.day.date))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.onSurfaceMuted)
                    .lineLimit(1)
            }
            Text(next.name)
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(Theme.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(PrayerFormat.time(next.adhan))
                .font(.system(size: 18, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.onSurface)
                .lineLimit(1)
            if let iqamah = next.iqamah {
                Text("\(next.iqamahLabel) \(PrayerFormat.time(iqamah))")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.adaptiveGold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            Text(timerInterval: snapshot.countdownRange, countsDown: true)
                .font(.system(size: 25, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.adaptiveGold)
                .multilineTextAlignment(.leading)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
            GoldProgressBar(range: snapshot.progressRange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Medium

struct MediumPrayerWidgetView: View {
    let snapshot: PrayerSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            WidgetHeaderView(snapshot: snapshot, nameSize: 14, detailSize: 11.5)
            HStack(alignment: .top, spacing: 8) {
                CompactNextPrayerPanel(snapshot: snapshot)
                    .frame(width: 100)
                PrayerTableView(snapshot: snapshot, fontSize: 12, timeColumnWidth: 56, rowVerticalPadding: 0.75)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct WidgetHeaderView: View {
    let snapshot: PrayerSnapshot
    let nameSize: CGFloat
    let detailSize: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: nameSize - 1, weight: .semibold))
                .foregroundStyle(Theme.adaptiveGold)
            Text(MosqueInfo.name)
                .font(.system(size: nameSize, weight: .bold))
                .foregroundStyle(Theme.onSurface)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(hijriText)
                .font(.system(size: detailSize, weight: .semibold))
                .foregroundStyle(Theme.adaptiveGold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var hijriText: String {
        snapshot.isShowingTomorrow ? "Tomorrow · \(snapshot.day.hijriDate)" : snapshot.day.hijriDate
    }
}

struct CompactNextPrayerPanel: View {
    let snapshot: PrayerSnapshot

    var body: some View {
        let next = snapshot.next
        VStack(alignment: .leading, spacing: 1.5) {
            Text("NEXT PRAYER")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(Theme.onSurfaceMuted)
                .lineLimit(1)
            Text(next.name)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(PrayerFormat.time(next.adhan))
                .font(.system(size: 13.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let iqamah = next.iqamah {
                Text("\(next.iqamahLabel) \(PrayerFormat.time(iqamah))")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.adaptiveGold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
            Text(timerInterval: snapshot.countdownRange, countsDown: true)
                .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.adaptiveGold)
                .multilineTextAlignment(.leading)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.panelFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        }
    }
}

// MARK: - Shared table (medium & large)

struct PrayerTableView: View {
    let snapshot: PrayerSnapshot
    let fontSize: CGFloat
    let timeColumnWidth: CGFloat
    let rowVerticalPadding: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text("PRAYER").frame(maxWidth: .infinity, alignment: .leading)
                Text("ADHAN").frame(width: timeColumnWidth, alignment: .trailing)
                Text("IQAMAH").frame(width: timeColumnWidth, alignment: .trailing)
            }
            .font(.system(size: max(fontSize - 3, 8.5), weight: .bold))
            .tracking(0.5)
            .foregroundStyle(Theme.onSurfaceMuted)
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
                                .fill(Theme.adaptiveGold.opacity(0.22))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(Theme.adaptiveGold.opacity(0.65), lineWidth: 0.6)
                                }
                        }
                    }
            }
        }
    }
}

struct PrayerTableRow: View {
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
        if isNext { return Theme.adaptiveGold }
        return slot.prayer == .sunrise ? Theme.onSurfaceMuted : Theme.onSurface
    }
}

// MARK: - Large

struct LargePrayerWidgetView: View {
    let snapshot: PrayerSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LargeHeaderView(snapshot: snapshot)
            LargeNextPrayerBanner(snapshot: snapshot)
            PrayerTableView(snapshot: snapshot, fontSize: 15, timeColumnWidth: 74, rowVerticalPadding: 2)
                .frame(maxHeight: .infinity)
            LargeFooterView(snapshot: snapshot)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct LargeHeaderView: View {
    let snapshot: PrayerSnapshot

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.adaptiveGold)
                .frame(width: 28, height: 28)
                .background(Theme.adaptiveGold.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(MosqueInfo.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.onSurface)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(snapshot.day.hijriDate)
                        .foregroundStyle(Theme.adaptiveGold)
                    Text("·")
                        .foregroundStyle(Theme.onSurfaceMuted)
                    Text(PrayerFormat.shortDate(snapshot.day.date))
                        .foregroundStyle(Theme.onSurfaceSecondary)
                }
                .font(.system(size: 12.5, weight: .semibold))
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
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(Theme.adaptiveGold)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Theme.adaptiveGold.opacity(0.22), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Theme.adaptiveGold.opacity(0.5), lineWidth: 0.5)
            }
    }
}

struct LargeNextPrayerBanner: View {
    let snapshot: PrayerSnapshot

    var body: some View {
        let next = snapshot.next
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: next.symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.adaptiveGold)
                    .frame(width: 34, height: 34)
                    .background(Theme.panelFill, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(snapshot.isShowingTomorrow ? "NEXT PRAYER · TOMORROW" : "NEXT PRAYER")
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(Theme.onSurfaceMuted)
                        .lineLimit(1)
                    Text(next.name)
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(Theme.onSurface)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(detailText)
                        .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.onSurfaceSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 4)
                Text(timerInterval: snapshot.countdownRange, countsDown: true)
                    .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.adaptiveGold)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: 110, alignment: .trailing)
            }
            GoldProgressBar(range: snapshot.progressRange)
        }
        .padding(10)
        .background(Theme.panelFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.75)
        }
    }

    private var detailText: String {
        let next = snapshot.next
        let adhan = "Adhan \(PrayerFormat.time(next.adhan))"
        guard let iqamah = next.iqamah else { return adhan }
        return "\(adhan) · \(next.iqamahLabel) \(PrayerFormat.time(iqamah))"
    }
}

struct LargeFooterView: View {
    let snapshot: PrayerSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 0.5)
                .padding(.bottom, 2)
            HStack(spacing: 5) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(Theme.adaptiveGold)
                Text(MosqueInfo.address)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            HStack(spacing: 5) {
                Image(systemName: "building.columns.fill")
                    .foregroundStyle(Theme.adaptiveGold)
                Text(jumuahNote)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Theme.onSurfaceSecondary)
    }

    private var jumuahNote: String {
        let khutbah = PrayerFormat.khutbahTime(on: snapshot.day.date)
        return snapshot.day.isFriday
            ? "Jumu'ah today · Khutbah \(khutbah)"
            : "Jumu'ah every Friday · Khutbah \(khutbah)"
    }
}

// MARK: - Lock Screen: rectangular

struct RectangularPrayerWidgetView: View {
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
        .configurationDisplayName("Al Rashid Prayer Times")
        .description("Next prayer with a live countdown, plus today's Adhan and Iqamah times for Al Rashid Mosque.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular])
    }
}

@main
struct PrayerWidgetBundle: WidgetBundle {
    var body: some Widget {
        PrayerWidget()
        PrayerLiveActivity()
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

struct PrayerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PrayerActivityAttributes.self) { context in
            LiveActivityRootView(state: context.state)
                .activityBackgroundTint(Theme.activityTint)
                .activitySystemActionForegroundColor(Theme.onSurface)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: state.symbolName)
                            .foregroundStyle(Theme.adaptiveGold)
                        Text(state.prayerName)
                            .font(.headline)
                            .foregroundStyle(Color.white)
                    }
                    .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(state.adhan, style: .timer)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.adaptiveGold)
                        .frame(maxWidth: 92, alignment: .trailing)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("Adhan \(PrayerFormat.time(state.adhan))")
                        Spacer()
                        if let iqamah = state.iqamah {
                            Text("\(state.iqamahLabel) \(PrayerFormat.time(iqamah))")
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                Image(systemName: state.symbolName)
                    .foregroundStyle(Theme.adaptiveGold)
            } compactTrailing: {
                Text(state.adhan, style: .timer)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.adaptiveGold)
                    .frame(maxWidth: 64, alignment: .trailing)
            } minimal: {
                Image(systemName: state.symbolName)
                    .foregroundStyle(Theme.adaptiveGold)
            }
            .keylineTint(Theme.adaptiveGold)
        }
    }
}

/// Applies the user's Settings Light/Dark choice to the Live Activity,
/// resolved against the system appearance (v1.0.5).
private struct LiveActivityRootView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    let state: PrayerActivityAttributes.ContentState

    var body: some View {
        LiveActivityLockScreenView(state: state)
            .environment(\.colorScheme, AppAppearance.resolvedColorScheme(system: systemColorScheme))
    }
}

private struct LiveActivityLockScreenView: View {
    let state: PrayerActivityAttributes.ContentState

    var body: some View {
        ZStack {
            AdaptiveSurfaceBackground()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "moon.stars.fill")
                        .foregroundStyle(Theme.adaptiveGold)
                    Text(MosqueInfo.name)
                        .font(.caption.weight(.bold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.onSurfaceSecondary)
                    Spacer()
                    Text("\(PrayerFormat.shortDate(state.adhan)) · \(state.hijri)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.onSurfaceMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: state.symbolName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.adaptiveGold)
                    Text(state.isTomorrow ? "\(state.prayerName) · Tomorrow" : state.prayerName)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(Theme.onSurface)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 8)
                    Text(PrayerFormat.time(state.adhan))
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.onSurface)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(state.adhan, style: .timer)
                        .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.adaptiveGold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 8)
                    if let iqamah = state.iqamah {
                        Text("\(state.iqamahLabel) \(PrayerFormat.time(iqamah))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.onSurfaceSecondary)
                    }
                }
                if let followingName = state.followingName, let followingAdhan = state.followingAdhan {
                    Text("Then \(followingName) · \(PrayerFormat.time(followingAdhan))")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.onSurfaceMuted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }
}
