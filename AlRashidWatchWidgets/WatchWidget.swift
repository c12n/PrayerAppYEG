//
//  WatchWidget.swift
//  AlRashid Prayer — Apple Watch complication (v1.8.0)
//
//  Target Membership: AlRashidWatchWidgets only.
//  Shared files (also in this target): PrayerCalculator.swift, PrayerModels.swift
//
//  A WidgetKit complication in the three accessory families: the
//  next prayer and its time, with a live countdown in the
//  rectangular family. Timelines come from the shared provider's
//  plan, so the face flips at each Adhan on its own.
//

import SwiftUI
import WidgetKit

@main
struct AlRashidWatchWidgets: WidgetBundle {
    var body: some Widget {
        NextPrayerComplication()
    }
}

struct NextPrayerComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextPrayerComplication", provider: ComplicationProvider()) { entry in
            ComplicationView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Next Prayer")
        .description("The next prayer in Edmonton, with its time.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: PrayerSnapshot
}

struct ComplicationProvider: TimelineProvider {
    private let provider = PrayerProvider.standard

    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: .now, snapshot: provider.snapshot(at: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(ComplicationEntry(date: .now, snapshot: provider.snapshot(at: .now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let plan = provider.timelinePlan(from: .now)
        let entries = plan.snapshots.map { ComplicationEntry(date: $0.date, snapshot: $0) }
        completion(Timeline(entries: entries, policy: .after(plan.reloadDate)))
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: PrayerSnapshot

    var body: some View {
        let next = snapshot.next
        Group {
            switch family {
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Image(systemName: next.symbolName)
                        .font(.system(size: 13, weight: .semibold))
                    Text(PrayerFormat.time(next.adhan))
                        .font(.system(size: 10.5, weight: .bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Label(next.name, systemImage: next.symbolName)
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(PrayerFormat.time(next.adhan))
                        Text("·")
                        Text(timerInterval: snapshot.countdownRange, countsDown: true)
                            .monospacedDigit()
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default: // .accessoryInline
                Text("\(next.name) \(PrayerFormat.time(next.adhan))")
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}
