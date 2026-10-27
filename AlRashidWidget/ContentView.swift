//
//  ContentView.swift
//  AlRashid Prayer Widget
//
//  Target Membership: AlRashidWidget only.
//

import SwiftUI
import UIKit
import WidgetKit

struct ContentView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    private let provider = PrayerProvider.standard

    var body: some View {
        TimelineView(.everyMinute) { context in
            let snapshot = provider.snapshot(at: context.date)
            let todaySchedule = provider.day(for: context.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HeaderView(today: todaySchedule, now: context.date)
                    NextPrayerCard(snapshot: snapshot)
                    ScheduleCard(snapshot: snapshot)
                    actionButtons
                    FooterView()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .background { AppBackground() }
        .onAppear { refreshWidgets() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { refreshWidgets() }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                openURL(MosqueInfo.directionsURL)
            } label: {
                Label("Directions", systemImage: "car.fill")
            }
            .buttonStyle(ThemeButtonStyle(prominent: true))

            Button {
                openURL(MosqueInfo.websiteURL)
            } label: {
                Label("Website", systemImage: "globe")
            }
            .buttonStyle(ThemeButtonStyle(prominent: false))
        }
    }

    private func refreshWidgets() {
        provider.refreshCache()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Header

private struct HeaderView: View {
    let today: PrayerDay
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "moon.stars.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.adaptiveGold)
                Text("Assalamu Alaikum")
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Next prayer card

private struct NextPrayerCard: View {
    let snapshot: PrayerSnapshot

    var body: some View {
        let next = snapshot.next
        let caption = snapshot.isShowingTomorrow ? "Next prayer · Tomorrow" : "Next prayer"
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(caption, systemImage: next.symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.lightGold)
                Spacer()
                if next.isJumuah {
                    Text("JUMU'AH")
                        .font(.caption2.weight(.heavy))
                        .tracking(0.8)
                        .foregroundStyle(Theme.lightGold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.gold.opacity(0.25), in: Capsule())
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(next.name)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 8)
                Text(PrayerFormat.time(next.adhan))
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
            }
            if let iqamah = next.iqamah {
                Label("\(next.iqamahLabel) at \(PrayerFormat.time(iqamah))", systemImage: "person.3.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.8))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(timerInterval: snapshot.countdownRange, countsDown: true)
                    .font(.system(size: 46, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.lightGold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                GoldProgressBar(range: snapshot.progressRange)
                Text("until \(next.name) Adhan")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.65))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .greenGlassCard(cornerRadius: 26)
    }
}

// MARK: - Schedule card

private struct ScheduleCard: View {
    let snapshot: PrayerSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.isShowingTomorrow ? "Tomorrow's Prayer Times" : "Today's Prayer Times")
                    .font(.headline)
                    .foregroundStyle(Color.white)
                Spacer(minLength: 8)
                Text(PrayerFormat.shortDate(snapshot.day.date))
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            HStack(spacing: 8) {
                Text("PRAYER").frame(maxWidth: .infinity, alignment: .leading)
                Text("ADHAN").frame(width: 86, alignment: .trailing)
                Text("IQAMAH").frame(width: 86, alignment: .trailing)
            }
            .font(.caption2.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(Color.white.opacity(0.55))
            .padding(.horizontal, 12)
            VStack(spacing: 4) {
                ForEach(snapshot.day.slots) { slot in
                    ScheduleRow(slot: slot, isNext: snapshot.isNext(slot))
                }
            }
            if snapshot.day.isFriday {
                Label("Jumu'ah replaces Dhuhr · Khutbah at \(PrayerFormat.khutbahTime(on: snapshot.day.date))", systemImage: "building.columns.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.lightGold)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .greenGlassCard(cornerRadius: 26)
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
                        Text("Khutbah time shown")
                            .font(.caption2)
                            .foregroundStyle(Color.white.opacity(0.6))
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
                    .fill(Theme.gold.opacity(0.2))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Theme.lightGold.opacity(0.55), lineWidth: 1)
                    }
            }
        }
    }

    private var rowColor: Color {
        if isNext { return Theme.lightGold }
        return slot.prayer == .sunrise ? Color.white.opacity(0.6) : Color.white
    }
}

// MARK: - Footer

private struct FooterView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(MosqueInfo.address, systemImage: "mappin.and.ellipse")
            Label("Jumu'ah Khutbah every Friday at \(PrayerFormat.khutbahTime(on: .now))", systemImage: "building.columns")
            Text("Adhan times are calculated on-device and calibrated to AlRashid Mosque's published timetable. Iqamah times are fixed offsets from Adhan — please confirm with the mosque's official timetable.")
                .font(.caption)
                .padding(.top, 4)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Styling

private struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            Color(uiColor: .systemGroupedBackground)
            LinearGradient(
                colors: [Theme.green.opacity(colorScheme == .dark ? 0.45 : 0.16), Color.clear],
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
            .foregroundStyle(prominent ? Theme.deepGreen : Theme.lightGold)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(prominent
                        ? AnyShapeStyle(LinearGradient(colors: [Theme.lightGold, Theme.gold], startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(LinearGradient(colors: [Theme.green, Theme.deepGreen], startPoint: .top, endPoint: .bottom)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.gold.opacity(prominent ? 0 : 0.6), lineWidth: 1)
            }
            .shadow(color: Theme.deepGreen.opacity(0.25), radius: 8, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private extension View {
    func greenGlassCard(cornerRadius: CGFloat) -> some View {
        self.background {
            GlassGreenBackground()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Theme.lightGold.opacity(0.45), Color.white.opacity(0.08)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: Theme.deepGreen.opacity(0.35), radius: 16, x: 0, y: 8)
    }
}

extension Theme {
    /// Gold that stays readable on light backgrounds (darker) and dark backgrounds (brighter).
    static var adaptiveGold: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.949, green: 0.804, blue: 0.361, alpha: 1)
                : UIColor(red: 0.549, green: 0.427, blue: 0.071, alpha: 1)
        })
    }
}

#Preview {
    ContentView()
}
