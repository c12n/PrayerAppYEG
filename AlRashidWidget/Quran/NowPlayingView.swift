//
//  NowPlayingView.swift
//  AlRashid Prayer Widget
//
//  Quran player (v2.2.0-alpha): Now Playing in two switchable
//  styles — Spotify (full-bleed gradient from the surah's color,
//  big white play button, Up Next strip) and Apple Music (app
//  theme background, centered artwork, bottom toolbar with AirPlay)
//  — over the one QuranPlayer engine. The style is picked from the
//  menu in either style and in the library. Lyrics, sleep timer and
//  the queue are shared by both. Target Membership:
//  AlRashidWidget only.
//

import AVKit
import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var player: QuranPlayer

    var body: some View {
        switch player.playerStyle {
        case .spotify:
            SpotifyNowPlayingView()
        case .appleMusic:
            AppleMusicNowPlayingView()
        }
    }
}

// MARK: - Shared pieces

/// Deterministic per-surah colors: a golden-ratio hue walk, so
/// every surah always wears the same gradient / artwork.
enum SurahPalette {
    static func hue(for surahNumber: Int) -> Double {
        (Double(surahNumber) * 0.6180339887).truncatingRemainder(dividingBy: 1)
    }

    static func color(for surahNumber: Int, saturation: Double, brightness: Double) -> Color {
        Color(hue: hue(for: surahNumber), saturation: saturation, brightness: brightness)
    }
}

/// The generated cover tile: the surah's gradient with its Arabic
/// name in large script and its number.
struct SurahArtworkView: View {
    let surah: QuranSurah
    var cornerRadius: CGFloat = 18

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    SurahPalette.color(for: surah.number, saturation: 0.55, brightness: 0.62),
                    SurahPalette.color(for: surah.number, saturation: 0.65, brightness: 0.34),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 8) {
                Text(surah.arabic)
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                Text("SURAH \(surah.number)")
                    .font(.caption.weight(.heavy))
                    .tracking(2.4)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(16)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Swipe left/right on the artwork to change surah (build 29,
/// matching the reference player apps): the artwork follows the
/// finger with resistance and springs back; past the threshold it
/// skips to the next / previous surah in the queue.
private struct TrackSwipeModifier: ViewModifier {
    @EnvironmentObject private var player: QuranPlayer
    @State private var dragX: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: dragX)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        if abs(value.translation.width) > abs(value.translation.height) * 1.5 {
                            dragX = value.translation.width * 0.32
                        }
                    }
                    .onEnded { value in
                        let dx = value.translation.width
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                            dragX = 0
                        }
                        if dx < -70 {
                            player.next()
                        } else if dx > 70 {
                            player.previous()
                        }
                    })
    }
}

/// Style + speed menu, shared by both player styles.
struct PlayerOptionsMenu<MenuLabel: View>: View {
    @EnvironmentObject private var player: QuranPlayer
    @ViewBuilder let label: () -> MenuLabel

    var body: some View {
        Menu {
            Section("Player style") {
                Button {
                    player.playerStyle = .spotify
                } label: {
                    if player.playerStyle == .spotify {
                        Label("Spotify", systemImage: "checkmark")
                    } else {
                        Text("Spotify")
                    }
                }
                Button {
                    player.playerStyle = .appleMusic
                } label: {
                    if player.playerStyle == .appleMusic {
                        Label("Apple Music", systemImage: "checkmark")
                    } else {
                        Text("Apple Music")
                    }
                }
            }
            Section("Speed") {
                ForEach(QuranPlayer.allowedRates, id: \.self) { rateOption in
                    Button {
                        player.setRate(rateOption)
                    } label: {
                        if rateOption == player.rate {
                            Label(quranRateLabel(rateOption), systemImage: "checkmark")
                        } else {
                            Text(quranRateLabel(rateOption))
                        }
                    }
                }
            }
        } label: {
            label()
        }
    }
}

/// "1×", "1.25×", "0.5×" — the player's speed labels.
func quranRateLabel(_ rate: Float) -> String {
    rate == rate.rounded()
        ? "\(Int(rate))×"
        : String(format: "%g×", Double(rate))
}

/// Sleep timer menu (off / minutes / end of surah), tinted by the
/// caller so both styles can share it.
struct SleepMenu<MenuLabel: View>: View {
    @EnvironmentObject private var player: QuranPlayer
    @ViewBuilder let label: () -> MenuLabel

    var body: some View {
        Menu {
            Button("Off") { player.setSleepOption(.off) }
            ForEach(QuranPlayer.sleepMinutes, id: \.self) { minutes in
                Button("\(minutes) minutes") { player.setSleepOption(.minutes(minutes)) }
            }
            Button("End of surah") { player.setSleepOption(.endOfSurah) }
        } label: {
            label()
        }
    }
}

/// "Off" / "30 min" / "End" — the sleep timer's short state.
func quranSleepLabel(_ option: QuranPlayer.SleepOption) -> String {
    switch option {
    case .off: return "Off"
    case .minutes(let minutes): return "\(minutes) min"
    case .endOfSurah: return "End"
    }
}

/// The standard slider scrubber with elapsed / remaining times.
struct PlayerScrubber: View {
    @EnvironmentObject private var player: QuranPlayer
    @State private var scrubValue: Double?
    var tint: Color
    var timeColor: Color

    var body: some View {
        VStack(spacing: 5) {
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
            .tint(tint)
            HStack {
                Text(QuranLibrary.formatDuration(scrubValue ?? player.currentTime))
                Spacer()
                Text("-" + QuranLibrary.formatDuration(
                    max(0, player.duration - (scrubValue ?? player.currentTime))))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(timeColor)
        }
    }
}

/// Spotify's hairline scrubber: a thin bar, dragged to seek.
struct ThinScrubber: View {
    @EnvironmentObject private var player: QuranPlayer
    @State private var dragFraction: Double?
    var foreground: Color
    var timeColor: Color

    private var fraction: Double {
        if let dragFraction { return dragFraction }
        guard player.duration > 0 else { return 0 }
        return min(1, max(0, player.currentTime / player.duration))
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(foreground.opacity(0.3))
                    Capsule().fill(foreground)
                        .frame(width: proxy.size.width * fraction)
                }
                .frame(height: 4)
                .contentShape(Rectangle().inset(by: -8))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard proxy.size.width > 0 else { return }
                            dragFraction = min(1, max(0, value.location.x / proxy.size.width))
                        }
                        .onEnded { value in
                            guard proxy.size.width > 0 else { return }
                            let target = min(1, max(0, value.location.x / proxy.size.width))
                            dragFraction = nil
                            player.seek(to: target * player.duration)
                        })
            }
            .frame(height: 4)
            HStack {
                Text(QuranLibrary.formatDuration(displayedTime))
                Spacer()
                Text("-" + QuranLibrary.formatDuration(max(0, player.duration - displayedTime)))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(timeColor)
        }
    }

    private var displayedTime: TimeInterval {
        if let dragFraction { return dragFraction * player.duration }
        return player.currentTime
    }
}

// MARK: - Spotify style

private struct SpotifyNowPlayingView: View {
    @EnvironmentObject private var player: QuranPlayer
    @EnvironmentObject private var downloads: QuranDownloads
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showQueue = false
    @State private var showLyrics = false

    private var isDark: Bool { colorScheme == .dark }

    private func gradientColors(for surah: QuranSurah) -> [Color] {
        let number = surah.number
        return [
            SurahPalette.color(for: number, saturation: 0.6,
                               brightness: isDark ? 0.55 : 0.72),
            SurahPalette.color(for: number, saturation: 0.65,
                               brightness: isDark ? 0.30 : 0.52),
            SurahPalette.color(for: number, saturation: 0.7,
                               brightness: isDark ? 0.16 : 0.38),
        ]
    }

    private var onGradient: Color { .white }
    private var onGradientMuted: Color { .white.opacity(0.72) }

    var body: some View {
        ZStack {
            if let surah = player.currentSurah {
                LinearGradient(colors: gradientColors(for: surah),
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    SurahArtworkView(surah: surah, cornerRadius: 12)
                        .id(surah.number)
                        .transition(.opacity)
                        .shadow(color: .black.opacity(0.35), radius: 22, y: 12)
                        .padding(.top, 14)
                        .modifier(TrackSwipeModifier())
                    titleRow(surah)
                    ThinScrubber(foreground: .white, timeColor: onGradientMuted)
                        .padding(.top, 18)
                    transport
                    extrasRow
                    upNextStrip
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 18)
                .animation(.easeInOut(duration: 0.28), value: surah.number)
            } else {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                Text("Nothing playing").foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showQueue) { QueueView() }
        .sheet(isPresented: $showLyrics) { QuranLyricsView() }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(onGradient)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Playing from \(player.contextLabel)")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(onGradientMuted)
                .lineLimit(1)
            Spacer()
            PlayerOptionsMenu {
                Image(systemName: "ellipsis")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(onGradient)
                    .frame(width: 40, height: 40)
            }
        }
    }

    private func titleRow(_ surah: QuranSurah) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(surah.english)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(onGradient)
                    .lineLimit(1)
                Text(player.currentReciter?.name ?? "")
                    .font(.body)
                    .foregroundStyle(onGradientMuted)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                player.toggleFavorite(surah.number)
            } label: {
                Image(systemName: player.isFavorite(surah.number)
                      ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title2)
                    .foregroundStyle(player.isFavorite(surah.number)
                                     ? Color(red: 0.11, green: 0.73, blue: 0.33) : onGradient)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 22)
    }

    private var transport: some View {
        HStack {
            spotifyIcon("shuffle", active: player.shuffle) { player.toggleShuffle() }
            Spacer()
            spotifyIcon("backward.end.fill", active: false, size: 30) { player.previous() }
            Spacer()
            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 72, height: 72)
                    .background(.white, in: Circle())
            }
            .buttonStyle(.plain)
            Spacer()
            spotifyIcon("forward.end.fill", active: false, size: 30) { player.next() }
            Spacer()
            spotifyIcon(player.repeatMode == .one ? "repeat.1" : "repeat",
                        active: player.repeatMode != .off) { player.cycleRepeatMode() }
        }
        .padding(.top, 10)
    }

    private func spotifyIcon(_ systemImage: String, active: Bool,
                             size: CGFloat = 21,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(active
                                 ? Color(red: 0.11, green: 0.73, blue: 0.33)
                                 : onGradient.opacity(0.9))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }

    private var extrasRow: some View {
        HStack {
            extraButton(icon: "text.quote", label: "Lyrics") { showLyrics = true }
            Spacer()
            SleepMenu {
                extraLabel(icon: "moon.fill", label: "Sleep",
                           value: quranSleepLabel(player.sleepOption))
            }
            Spacer()
            extraButton(icon: "list.bullet", label: "Queue",
                        value: "\(player.queue.count)") { showQueue = true }
        }
        .padding(.top, 16)
    }

    private func extraButton(icon: String, label: String, value: String? = nil,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            extraLabel(icon: icon, label: label, value: value)
        }
        .buttonStyle(.plain)
    }

    private func extraLabel(icon: String, label: String, value: String?) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(onGradient)
                .frame(height: 24)
            Text(value ?? label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(onGradientMuted)
                .lineLimit(1)
        }
        .frame(width: 58)
    }

    @ViewBuilder
    private var upNextStrip: some View {
        if let next = player.upNextSurah {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Up next")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(onGradientMuted)
                    Text(next.english)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(onGradient)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    showQueue = true
                } label: {
                    Text("Open queue")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color(red: 0.11, green: 0.73, blue: 0.33))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.black.opacity(0.28),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 18)
        }
    }
}

// MARK: - Apple Music style

private struct AppleMusicNowPlayingView: View {
    @EnvironmentObject private var player: QuranPlayer
    @EnvironmentObject private var downloads: QuranDownloads
    @Environment(\.dismiss) private var dismiss
    @State private var showQueue = false
    @State private var showLyrics = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            if let surah = player.currentSurah {
                VStack(spacing: 0) {
                    header
                    SurahArtworkView(surah: surah, cornerRadius: 16)
                        .id(surah.number)
                        .transition(.opacity)
                        .frame(maxWidth: 320)
                        .shadow(color: .black.opacity(0.28), radius: 24, y: 14)
                        .padding(.top, 10)
                        .modifier(TrackSwipeModifier())
                    titleBlock(surah)
                    PlayerScrubber(tint: Theme.adaptiveGold, timeColor: .secondary)
                        .padding(.top, 16)
                    transport
                    Spacer(minLength: 12)
                    bottomToolbar(surah)
                }
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .padding(.bottom, 20)
                .animation(.easeInOut(duration: 0.28), value: surah.number)
            } else {
                Text("Nothing playing").foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showQueue) { QueueView() }
        .sheet(isPresented: $showLyrics) { QuranLyricsView() }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            Spacer()
            Text(player.contextLabel)
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            PlayerOptionsMenu {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
            }
        }
    }

    private func titleBlock(_ surah: QuranSurah) -> some View {
        VStack(spacing: 4) {
            Text(surah.english)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(player.currentReciter?.name ?? "")
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Button {
                player.toggleFavorite(surah.number)
            } label: {
                Image(systemName: player.isFavorite(surah.number) ? "heart.fill" : "heart")
                    .font(.title3)
                    .foregroundStyle(player.isFavorite(surah.number)
                                     ? Color(red: 0.9, green: 0.28, blue: 0.3) : .secondary)
                    .frame(width: 44, height: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 20)
    }

    private var transport: some View {
        HStack {
            appleIcon("shuffle", active: player.shuffle) { player.toggleShuffle() }
            Spacer()
            appleIcon("backward.end.fill", active: false, size: 30) { player.previous() }
            Spacer()
            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 76, height: 76)
            }
            .buttonStyle(.plain)
            Spacer()
            appleIcon("forward.end.fill", active: false, size: 30) { player.next() }
            Spacer()
            appleIcon(player.repeatMode == .one ? "repeat.1" : "repeat",
                      active: player.repeatMode != .off) { player.cycleRepeatMode() }
        }
        .padding(.top, 8)
    }

    private func appleIcon(_ systemImage: String, active: Bool,
                           size: CGFloat = 20,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(active ? Theme.adaptiveGold : .primary.opacity(0.8))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }

    private func bottomToolbar(_ surah: QuranSurah) -> some View {
        HStack {
            toolbarButton(icon: "text.quote") { showLyrics = true }
            Spacer()
            AirPlayButton()
                .frame(width: 34, height: 34)
            Spacer()
            toolbarButton(icon: "list.bullet") { showQueue = true }
            Spacer()
            SleepMenu {
                Image(systemName: "moon.fill")
                    .font(.title3)
                    .foregroundStyle(player.sleepOption == .off ? .secondary : Theme.adaptiveGold)
                    .frame(width: 44, height: 44)
            }
        }
    }

    private func toolbarButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }
}

/// AirPlay route picker for the Apple Music style toolbar.
private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .secondaryLabel
        view.activeTintColor = .systemYellow
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

// MARK: - Queue

struct QueueView: View {
    @EnvironmentObject private var player: QuranPlayer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !player.contextLabel.isEmpty {
                    Section {
                        Text("Playing from \(player.contextLabel)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    ForEach(Array(player.queue.enumerated()), id: \.offset) { _, number in
                        if let surah = QuranLibrary.surah(number) {
                            queueRow(surah)
                        }
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

    private func queueRow(_ surah: QuranSurah) -> some View {
        let isCurrent = surah.number == player.currentSurah?.number
        return Button {
            player.playFromQueue(surahNumber: surah.number)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text("\(surah.number)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.adaptiveGold)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(surah.english)
                        .font(.body.weight(isCurrent ? .bold : .regular))
                        .foregroundStyle(.primary)
                    Text(surah.meaning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isCurrent {
                    Image(systemName: player.isPlaying
                          ? "speaker.wave.2.fill" : "pause.fill")
                        .foregroundStyle(Theme.green)
                }
                if let seconds = player.displayDuration(for: surah) {
                    Text(QuranLibrary.formatDuration(seconds))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(surah.arabic)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
