//
//  NowPlayingView.swift
//  AlRashid Prayer Widget
//
//  Quran player (v2.1.0-private): the full player, per the approved
//  mockup — a dark mosque-green gradient, a gold Arabic cover tile,
//  scrubber, transport with shuffle/repeat, and an extras row
//  (speed, download, sleep timer, queue). Presented as a sheet from
//  the mini player. Target Membership: AlRashidWidget only.
//

import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var player: QuranPlayer
    @EnvironmentObject private var downloads: QuranDownloads
    @Environment(\.dismiss) private var dismiss
    @State private var scrubValue: Double?
    @State private var showQueue = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [QuranTheme.midGreen, QuranTheme.deepGreen, QuranTheme.darkestGreen],
                startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if let surah = player.currentSurah {
                ScrollView {
                    VStack(spacing: 0) {
                        header
                        cover(surah)
                        titleRow(surah)
                        scrubber
                        transport
                        extras(surah)
                    }
                    .padding(.horizontal, 26)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            } else {
                Text("Nothing playing")
                    .foregroundStyle(QuranTheme.mutedOnGreen)
            }
        }
        .sheet(isPresented: $showQueue) {
            QueueView()
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Playing from \(player.contextLabel)")
                .font(.caption.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(QuranTheme.mutedOnGreen)
                .lineLimit(1)
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
    }

    private func cover(_ surah: QuranSurah) -> some View {
        VStack(spacing: 10) {
            Text(surah.arabic)
                .font(.system(size: 96, weight: .semibold))
                .foregroundStyle(QuranTheme.lightGold)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            Text("Surah \(surah.english)")
                .font(.caption.weight(.bold))
                .tracking(2.2)
                .foregroundStyle(QuranTheme.mutedOnGreen)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(
            LinearGradient(colors: [QuranTheme.midGreen, QuranTheme.deepGreen],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(QuranTheme.lightGold.opacity(0.45), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
        .padding(.top, 18)
    }

    private func titleRow(_ surah: QuranSurah) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(surah.english)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text(player.currentReciter?.name ?? "")
                    .font(.body)
                    .foregroundStyle(QuranTheme.mutedOnGreen)
            }
            Spacer()
            Button {
                player.toggleFavorite(surah.number)
            } label: {
                Image(systemName: player.isFavorite(surah.number) ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundStyle(player.isFavorite(surah.number)
                                     ? QuranTheme.heartRed : QuranTheme.mutedOnGreen)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 26)
    }

    private var scrubber: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { scrubValue ?? player.currentTime },
                    set: { scrubValue = $0 }
                ),
                in: 0...max(player.duration, 1)
            ) { editing in
                if !editing, let value = scrubValue {
                    player.seek(to: value)
                    scrubValue = nil
                }
            }
            .tint(.white)
            HStack {
                Text(QuranLibrary.formatDuration(scrubValue ?? player.currentTime))
                Spacer()
                Text("-" + QuranLibrary.formatDuration(
                    max(0, player.duration - (scrubValue ?? player.currentTime))))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(QuranTheme.mutedOnGreen)
        }
        .padding(.top, 20)
    }

    private var transport: some View {
        HStack {
            transportIcon("shuffle", active: player.shuffle) { player.toggleShuffle() }
            Spacer()
            transportIcon("backward.end.fill", active: false) { player.previous() }
            Spacer()
            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(QuranTheme.deepGreen)
                    .frame(width: 76, height: 76)
                    .background(.white, in: Circle())
            }
            .buttonStyle(.plain)
            Spacer()
            transportIcon("forward.end.fill", active: false) { player.next() }
            Spacer()
            transportIcon(player.repeatMode == .one ? "repeat.1" : "repeat",
                          active: player.repeatMode != .off) { player.cycleRepeatMode() }
        }
        .padding(.top, 14)
    }

    private func transportIcon(_ systemImage: String, active: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(active ? QuranTheme.lightGold : .white.opacity(0.85))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }

    private func extras(_ surah: QuranSurah) -> some View {
        HStack(alignment: .top) {
            Menu {
                ForEach(QuranPlayer.allowedRates, id: \.self) { rateOption in
                    Button {
                        player.setRate(rateOption)
                    } label: {
                        if rateOption == player.rate {
                            Label(rateLabel(rateOption), systemImage: "checkmark")
                        } else {
                            Text(rateLabel(rateOption))
                        }
                    }
                }
            } label: {
                extraItem(icon: "gauge.with.dots.needle.33percent",
                          label: "Speed", value: rateLabel(player.rate))
            }
            Spacer()
            downloadExtra(surah)
            Spacer()
            Menu {
                Button("Off") { player.setSleepOption(.off) }
                ForEach(QuranPlayer.sleepMinutes, id: \.self) { minutes in
                    Button("\(minutes) minutes") { player.setSleepOption(.minutes(minutes)) }
                }
                Button("End of surah") { player.setSleepOption(.endOfSurah) }
            } label: {
                extraItem(icon: "moon.fill", label: "Sleep", value: sleepLabel)
            }
            Spacer()
            Button {
                showQueue = true
            } label: {
                extraItem(icon: "list.bullet", label: "Queue",
                          value: "\(player.queue.count)")
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 26)
    }

    @ViewBuilder
    private func downloadExtra(_ surah: QuranSurah) -> some View {
        let reciterId = player.reciterId
        if let progress = downloads.progress(reciterId: reciterId, surahNumber: surah.number) {
            Button {
                downloads.cancel(surahNumber: surah.number, reciterId: reciterId)
            } label: {
                VStack(spacing: 5) {
                    ZStack {
                        CircularProgressView(fraction: progress)
                            .frame(width: 26, height: 26)
                        Image(systemName: "stop.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.white)
                    }
                    Text("Cancel")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(QuranTheme.mutedOnGreen)
                }
                .frame(width: 62)
            }
            .buttonStyle(.plain)
        } else if downloads.isDownloaded(reciterId: reciterId, surahNumber: surah.number) {
            Button {
                downloads.delete(surahNumber: surah.number, reciterId: reciterId)
            } label: {
                extraItem(icon: "checkmark.circle.fill", label: "Saved", value: "On device")
            }
            .buttonStyle(.plain)
        } else {
            Button {
                downloads.download(surahNumber: surah.number, reciterId: reciterId)
            } label: {
                extraItem(icon: "arrow.down.circle", label: "Download", value: "Stream")
            }
            .buttonStyle(.plain)
        }
    }

    private func extraItem(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(height: 26)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(QuranTheme.mutedOnGreen)
                .lineLimit(1)
        }
        .frame(width: 62)
    }

    private func rateLabel(_ rate: Float) -> String {
        rate == rate.rounded()
            ? "\(Int(rate))×"
            : String(format: "%g×", Double(rate))
    }

    private var sleepLabel: String {
        switch player.sleepOption {
        case .off: return "Off"
        case .minutes(let minutes): return "\(minutes) min"
        case .endOfSurah: return "End"
        }
    }
}

// MARK: - Circular download progress

private struct CircularProgressView: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, fraction)))
                .stroke(QuranTheme.lightGold,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Queue

private struct QueueView: View {
    @EnvironmentObject private var player: QuranPlayer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(player.queue, id: \.self) { number in
                    if let surah = QuranLibrary.surah(number) {
                        Button {
                            player.playFromQueue(surahNumber: number)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Text("\(number)")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(QuranTheme.gold)
                                    .frame(width: 34)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(surah.english)
                                        .font(.body.weight(number == player.currentSurah?.number ? .bold : .regular))
                                        .foregroundStyle(.primary)
                                    Text(surah.meaning)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if number == player.currentSurah?.number {
                                    Image(systemName: player.isPlaying
                                          ? "speaker.wave.2.fill" : "pause.fill")
                                        .foregroundStyle(QuranTheme.accentGreen)
                                }
                                Text(surah.arabic)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Up Next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
