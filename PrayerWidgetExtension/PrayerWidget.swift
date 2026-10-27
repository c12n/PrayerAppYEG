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
    let entry: PrayerEntry

    var body: some View {
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
    func homeScreenGlass(watermark: Bool) -> some View {
        self
            .environment(\.colorScheme, .dark)
            .containerBackground(for: .widget) {
                GlassGreenBackground(showsWatermark: watermark)
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.lightGold)
                Text(snapshot.isShowingTomorrow ? "TOMORROW" : "NEXT PRAYER")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(next.name)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(PrayerFormat.time(next.adhan))
                .font(.system(size: 16.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)
            if let iqamah = next.iqamah {
                Text("\(next.iqamahLabel) \(PrayerFormat.time(iqamah))")
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.lightGold.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            Text(timerInterval: snapshot.countdownRange, countsDown: true)
                .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.lightGold)
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
            WidgetHeaderView(snapshot: snapshot, nameSize: 13, detailSize: 10.5)
            HStack(alignment: .top, spacing: 8) {
                CompactNextPrayerPanel(snapshot: snapshot)
                    .frame(width: 96)
                PrayerTableView(snapshot: snapshot, fontSize: 11, timeColumnWidth: 52, rowVerticalPadding: 0.75)
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
                .foregroundStyle(Theme.lightGold)
            Text(MosqueInfo.name)
                .font(.system(size: nameSize, weight: .bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(hijriText)
                .font(.system(size: detailSize, weight: .semibold))
                .foregroundStyle(Theme.lightGold)
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
                .font(.system(size: 9, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(Color.white.opacity(0.6))
                .lineLimit(1)
            Text(next.name)
                .font(.system(size: 17.5, weight: .bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(PrayerFormat.time(next.adhan))
                .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let iqamah = next.iqamah {
                Text("\(next.iqamahLabel) \(PrayerFormat.time(iqamah))")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.lightGold.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
            Text(timerInterval: snapshot.countdownRange, countsDown: true)
                .font(.system(size: 16.5, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.lightGold)
                .multilineTextAlignment(.leading)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
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
            .font(.system(size: max(fontSize - 3, 7.5), weight: .bold))
            .tracking(0.5)
            .foregroundStyle(Color.white.opacity(0.55))
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
                                .fill(Theme.gold.opacity(0.22))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(Theme.lightGold.opacity(0.55), lineWidth: 0.6)
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
        if isNext { return Theme.lightGold }
        return slot.prayer == .sunrise ? Color.white.opacity(0.6) : Color.white.opacity(0.95)
    }
}

// MARK: - Large

struct LargePrayerWidgetView: View {
    let snapshot: PrayerSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LargeHeaderView(snapshot: snapshot)
            LargeNextPrayerBanner(snapshot: snapshot)
            PrayerTableView(snapshot: snapshot, fontSize: 14, timeColumnWidth: 68, rowVerticalPadding: 2)
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
                .foregroundStyle(Theme.lightGold)
                .frame(width: 28, height: 28)
                .background(Theme.gold.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(MosqueInfo.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(snapshot.day.hijriDate)
                        .foregroundStyle(Theme.lightGold)
                    Text("·")
                        .foregroundStyle(Color.white.opacity(0.5))
                    Text(PrayerFormat.shortDate(snapshot.day.date))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                .font(.system(size: 11.5, weight: .semibold))
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
            .font(.system(size: 9.5, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(Theme.lightGold)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Theme.gold.opacity(0.22), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Theme.lightGold.opacity(0.4), lineWidth: 0.5)
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
                    .foregroundStyle(Theme.lightGold)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.1), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(snapshot.isShowingTomorrow ? "NEXT PRAYER · TOMORROW" : "NEXT PRAYER")
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(Color.white.opacity(0.6))
                        .lineLimit(1)
                    Text(next.name)
                        .font(.system(size: 19.5, weight: .bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(detailText)
                        .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 4)
                Text(timerInterval: snapshot.countdownRange, countsDown: true)
                    .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.lightGold)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: 104, alignment: .trailing)
            }
            GoldProgressBar(range: snapshot.progressRange)
        }
        .padding(10)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Theme.lightGold.opacity(0.5), Color.white.opacity(0.08)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
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
                .fill(Color.white.opacity(0.15))
                .frame(height: 0.5)
                .padding(.bottom, 2)
            HStack(spacing: 5) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(Theme.lightGold)
                Text(MosqueInfo.address)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            HStack(spacing: 5) {
                Image(systemName: "building.columns.fill")
                    .foregroundStyle(Theme.lightGold)
                Text(jumuahNote)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color.white.opacity(0.78))
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
            LiveActivityLockScreenView(state: context.state)
                .activityBackgroundTint(Theme.deepGreen)
                .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: state.symbolName)
                            .foregroundStyle(Theme.lightGold)
                        Text(state.prayerName)
                            .font(.headline)
                            .foregroundStyle(Color.white)
                    }
                    .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(state.adhan, style: .timer)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.lightGold)
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
                    .foregroundStyle(Theme.lightGold)
            } compactTrailing: {
                Text(state.adhan, style: .timer)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.lightGold)
                    .frame(maxWidth: 64, alignment: .trailing)
            } minimal: {
                Image(systemName: state.symbolName)
                    .foregroundStyle(Theme.lightGold)
            }
            .keylineTint(Theme.gold)
        }
    }
}

private struct LiveActivityLockScreenView: View {
    let state: PrayerActivityAttributes.ContentState

    var body: some View {
        ZStack {
            GlassGreenBackground()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "moon.stars.fill")
                        .foregroundStyle(Theme.lightGold)
                    Text(MosqueInfo.name)
                        .font(.caption.weight(.bold))
                        .tracking(0.6)
                        .foregroundStyle(Color.white.opacity(0.85))
                    Spacer()
                    Text(state.hijri)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: state.symbolName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.lightGold)
                    Text(state.isTomorrow ? "\(state.prayerName) · Tomorrow" : state.prayerName)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 8)
                    Text(PrayerFormat.time(state.adhan))
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.92))
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(state.adhan, style: .timer)
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.lightGold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 8)
                    if let iqamah = state.iqamah {
                        Text("\(state.iqamahLabel) \(PrayerFormat.time(iqamah))")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.white.opacity(0.8))
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }
}
