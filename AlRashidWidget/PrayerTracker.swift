//
//  PrayerTracker.swift
//  AlRashid Prayer Widget
//
//  Prayer tracker (v2.2.0-alpha): a daily check-off of the five
//  obligatory prayers, persisted as JSON under `tracker.prayers.v1`
//  in UserDefaults.standard — [yyyy-MM-dd: [prayerName]] — plus the
//  card on the Prayer tab and a detail view with the last 7 days,
//  totals, the full-day streak, and the Quran listening stats.
//  Target Membership: AlRashidWidget only.
//

import Foundation
import SwiftUI

// MARK: - Store

final class TrackerStore: ObservableObject {
    /// The tracked prayers, in day order. Friday's Dhuhr (Jumu'ah)
    /// is tracked as "Dhuhr".
    static let prayerNames = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
    static let storageKey = "tracker.prayers.v1"

    @Published private(set) var prayersByDay: [String: [String]] = [:]

    private var defaults: UserDefaults { .standard }

    init() {
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            prayersByDay = decoded
        }
    }

    // MARK: Day keys

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func dayKey(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    // MARK: Queries

    func prayers(on date: Date) -> Set<String> {
        Set(prayersByDay[Self.dayKey(for: date)] ?? [])
    }

    func isDone(_ prayer: String, on date: Date) -> Bool {
        prayers(on: date).contains(prayer)
    }

    func count(on date: Date) -> Int {
        prayers(on: date).count
    }

    func isFullDay(_ date: Date) -> Bool {
        Self.prayerNames.allSatisfy { prayers(on: date).contains($0) }
    }

    /// Total prayers checked off in the 7 days ending today.
    func countThisWeek(today: Date = Date()) -> Int {
        (0..<7).reduce(0) { sum, offset in
            let day = Calendar.current.date(byAdding: .day, value: -offset, to: today) ?? today
            return sum + count(on: day)
        }
    }

    /// Consecutive full days ending today — or ending yesterday
    /// while today is still in progress.
    func fullDayStreak(today: Date = Date()) -> Int {
        let calendar = Calendar.current
        var streak = 0
        var day = today
        if !isFullDay(day) {
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        while isFullDay(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day)
            else { break }
            day = previous
        }
        return streak
    }

    // MARK: Mutation

    func toggle(_ prayer: String, on date: Date = Date()) {
        let key = Self.dayKey(for: date)
        var set = Set(prayersByDay[key] ?? [])
        if set.contains(prayer) {
            set.remove(prayer)
        } else {
            set.insert(prayer)
        }
        prayersByDay[key] = Self.prayerNames.filter { set.contains($0) }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(prayersByDay) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

// MARK: - Card (Prayer tab)

/// "Today's Prayers": five tappable chips on the Prayer tab.
struct PrayerTrackerCard: View {
    @EnvironmentObject private var tracker: TrackerStore
    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Today's Prayers", systemImage: "checklist")
                    .font(.headline)
                    .foregroundStyle(Theme.onSurface)
                Spacer()
                Text("\(tracker.count(on: Date())) of 5")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.adaptiveGold)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.onSurfaceMuted)
            }
            HStack(spacing: 8) {
                ForEach(TrackerStore.prayerNames, id: \.self) { name in
                    chip(name)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panelFill,
                    in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Chip taps consume their own gestures; a tap anywhere
            // else on the card opens the detail view.
            showDetail = true
        }
        .sheet(isPresented: $showDetail) {
            PrayerTrackerDetailView()
        }
    }

    private func chip(_ name: String) -> some View {
        let done = tracker.isDone(name, on: Date())
        return Button {
            tracker.toggle(name)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(done ? Theme.green : Theme.onSurfaceMuted)
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(done ? Theme.onSurface : Theme.onSurfaceSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                done ? Theme.green.opacity(0.14) : Theme.panelFill,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Detail

struct PrayerTrackerDetailView: View {
    @EnvironmentObject private var tracker: TrackerStore
    @EnvironmentObject private var player: QuranPlayer
    @Environment(\.dismiss) private var dismiss

    private var lastSevenDays: [Date] {
        (0..<7).map { offset in
            Calendar.current.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Last 7 days") {
                    ForEach(lastSevenDays, id: \.self) { day in
                        dayRow(day)
                    }
                }
                Section("Totals") {
                    LabeledContent("Prayers this week",
                                   value: "\(tracker.countThisWeek())")
                    LabeledContent("Full-day streak",
                                   value: "\(tracker.fullDayStreak()) days")
                }
                Section("Quran listening") {
                    LabeledContent("Surahs completed",
                                   value: "\(player.completedSurahsTotal)")
                    LabeledContent("Time listened", value: listenedLabel)
                }
            }
            .navigationTitle("Prayer Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var listenedLabel: String {
        let total = Int(player.totalSecondsListened.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private func dayRow(_ day: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(day)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(isToday ? "Today" : day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.body.weight(.semibold))
                Text(day.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 74, alignment: .leading)
            Spacer()
            ForEach(TrackerStore.prayerNames, id: \.self) { name in
                Image(systemName: tracker.isDone(name, on: day)
                      ? "circle.fill" : "circle")
                    .font(.caption)
                    .foregroundStyle(tracker.isDone(name, on: day)
                                     ? Theme.green : Color.gray.opacity(0.4))
            }
            Text("\(tracker.count(on: day))/5")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}
