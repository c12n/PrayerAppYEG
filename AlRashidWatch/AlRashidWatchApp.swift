//
//  AlRashidWatchApp.swift
//  AlRashid Prayer — Apple Watch app (v1.8.0)
//
//  Target Membership: AlRashidWatch only.
//  Shared files (also in this target): PrayerCalculator.swift, PrayerModels.swift
//
//  A small standalone watch app: today's prayer times plus the next
//  prayer with a live countdown, computed on the watch from the same
//  shared calculator and mosque timetable as the phone app. It reads
//  the watch's own App Group suite, so it works with the phone away.
//

import SwiftUI

@main
struct AlRashidWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchHomeView()
        }
    }
}

struct WatchHomeView: View {
    private let provider = PrayerProvider.standard

    var body: some View {
        TimelineView(.everyMinute) { context in
            let snapshot = provider.snapshot(at: context.date)
            let next = snapshot.next
            List {
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(next.name, systemImage: next.symbolName)
                            .font(.headline)
                            .lineLimit(1)
                        Text(PrayerFormat.time(next.adhan))
                            .font(.title3.weight(.bold))
                        Text(timerInterval: snapshot.countdownRange, countsDown: true)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 2)
                }
                Section {
                    ForEach(snapshot.day.slots) { slot in
                        HStack {
                            Text(slot.name)
                                .foregroundStyle(snapshot.isNext(slot) ? .primary : .secondary)
                            Spacer()
                            Text(PrayerFormat.time(slot.adhan))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .navigationTitle("Prayer YEG")
        }
    }
}
