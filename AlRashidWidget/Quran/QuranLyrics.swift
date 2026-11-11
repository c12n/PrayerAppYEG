//
//  QuranLyrics.swift
//  AlRashid Prayer Widget
//
//  Quran player (v2.2.0-alpha): the lyrics view — every ayah of the
//  playing surah, Arabic (Uthmani) with the Saheeh International
//  English translation, from the bundled quran_text.json. The
//  current ayah is estimated from playback progress across the
//  ayahs, weighted by Arabic character count, and highlighted while
//  the view auto-scrolls with it. Target Membership:
//  AlRashidWidget only.
//

import Foundation
import SwiftUI

// MARK: - Text store

struct QuranAyahText: Codable, Identifiable {
    /// Ayah number within the surah.
    let n: Int
    let ar: String
    let en: String

    var id: Int { n }
}

/// Loads quran_text.json once, off the main thread, and caches it.
final class QuranTextStore: ObservableObject {
    @Published private(set) var ayahsBySurah: [Int: [QuranAyahText]] = [:]
    @Published private(set) var isLoaded = false
    private var isLoading = false

    func ayahs(for surahNumber: Int) -> [QuranAyahText]? {
        loadIfNeeded()
        return ayahsBySurah[surahNumber]
    }

    func loadIfNeeded() {
        guard !isLoaded, !isLoading else { return }
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var parsed: [Int: [QuranAyahText]] = [:]
            if let url = Bundle.main.url(forResource: "quran_text", withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode([String: [QuranAyahText]].self,
                                                       from: data) {
                for (key, ayahs) in decoded {
                    if let number = Int(key) { parsed[number] = ayahs }
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.ayahsBySurah = parsed
                self.isLoaded = true
                self.isLoading = false
            }
        }
    }
}

// MARK: - Lyrics view

/// Estimated current ayah index: playback fraction applied across
/// the ayahs weighted by Arabic character count (longer ayahs take
/// proportionally longer to recite). Shared by the full lyrics view
/// and the Now Playing preview strip.
func quranCurrentAyahIndex(_ ayahs: [QuranAyahText],
                           time: Double, duration: Double) -> Int {
    guard !ayahs.isEmpty, duration > 0 else { return 0 }
    let weights = ayahs.map { Double(max($0.ar.count, 1)) }
    let total = weights.reduce(0, +)
    guard total > 0 else { return 0 }
    var target = (time / duration) * total
    for (index, weight) in weights.enumerated() {
        if target < weight { return index }
        target -= weight
    }
    return ayahs.count - 1
}

/// Start time of an ayah under the same weighted estimate.
func quranAyahStartTime(_ ayahs: [QuranAyahText],
                        index: Int, duration: Double) -> Double {
    guard ayahs.indices.contains(index), duration > 0 else { return 0 }
    let weights = ayahs.map { Double(max($0.ar.count, 1)) }
    let total = weights.reduce(0, +)
    guard total > 0 else { return 0 }
    let before = weights[..<index].reduce(0, +)
    return duration * before / total
}

/// End time of an ayah under the same weighted estimate.
func quranAyahEndTime(_ ayahs: [QuranAyahText],
                      index: Int, duration: Double) -> Double {
    guard ayahs.indices.contains(index), duration > 0 else { return 0 }
    let next = index + 1
    if next >= ayahs.count { return duration }
    return quranAyahStartTime(ayahs, index: next, duration: duration)
}

/// Synchronous, parse-once access to the bundled ayah text, for
/// the player engine (ayah loop boundaries). The view layer keeps
/// using QuranTextStore's async load for its first paint.
enum QuranTextData {
    static let ayahsBySurah: [Int: [QuranAyahText]] = {
        guard let url = Bundle.main.url(forResource: "quran_text",
                                        withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(
                  [String: [QuranAyahText]].self, from: data)
        else { return [:] }
        var parsed: [Int: [QuranAyahText]] = [:]
        for (key, ayahs) in decoded {
            if let number = Int(key) { parsed[number] = ayahs }
        }
        return parsed
    }()
}

struct QuranLyricsView: View {
    @EnvironmentObject private var player: QuranPlayer
    @EnvironmentObject private var bookmarks: QuranBookmarks
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = QuranTextStore()
    /// "both" | "arabic" | "english"
    @AppStorage("quran.lyricsMode") private var lyricsMode = "both"
    @State private var liveScroll = true
    /// Ayah-range loop picking (build 31): while on, taps choose
    /// the loop's first and last ayah instead of seeking.
    @State private var loopPicking = false
    @State private var loopStart: Int?
    @State private var loopEnd: Int?

    private var surah: QuranSurah? { player.currentSurah }

    private var ayahs: [QuranAyahText] {
        guard let surah else { return [] }
        return store.ayahsBySurah[surah.number] ?? []
    }

    private var currentAyahIndex: Int {
        quranCurrentAyahIndex(ayahs, time: player.currentTime,
                              duration: player.duration)
    }

    var body: some View {
        NavigationStack {
            Group {
                if surah == nil {
                    Text("Nothing playing")
                        .foregroundStyle(.secondary)
                } else if !store.isLoaded {
                    ProgressView("Loading text…")
                } else if ayahs.isEmpty {
                    Text("No text available for this surah.")
                        .foregroundStyle(.secondary)
                } else {
                    ayahList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if isSpotifyStyle, let surah {
                    // Spotify style: the lyrics card floats on a dark
                    // wash of the surah's own color.
                    LinearGradient(
                        colors: [
                            SurahPalette.color(for: surah.number, saturation: 0.62, brightness: 0.26),
                            .black,
                        ],
                        startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                } else {
                    Color(uiColor: .systemBackground)
                        .ignoresSafeArea()
                }
            }
            .navigationTitle(surah.map { "Surah \($0.english)" } ?? "Lyrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Picker("Text", selection: $lyricsMode) {
                        Text("Both").tag("both")
                        Text("Arabic").tag("arabic")
                        Text("English").tag("english")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }
                ToolbarItem(placement: .bottomBar) {
                    loopBar
                }
            }
        }
        .onAppear {
            store.loadIfNeeded()
            // Lyrics are read along with the recitation: keep the
            // screen awake while this view is open (build 31).
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    /// Bottom bar for the ayah-range loop: enter picking, show the
    /// picking progress, or show / stop the armed loop.
    @ViewBuilder
    private var loopBar: some View {
        if loopPicking {
            HStack(spacing: 10) {
                Image(systemName: "repeat")
                    .foregroundStyle(Theme.adaptiveGold)
                Text(loopStart == nil
                     ? "Tap the first ayah of the loop"
                     : "Tap the last ayah of the loop")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Cancel") {
                    loopPicking = false
                    loopStart = nil
                    loopEnd = nil
                }
            }
        } else if let label = player.ayahLoopLabel {
            HStack(spacing: 10) {
                Image(systemName: "repeat")
                    .foregroundStyle(Theme.adaptiveGold)
                Text("Looping: \(label)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Stop") { player.clearAyahLoop() }
            }
        } else {
            HStack {
                Spacer()
                Button {
                    loopPicking = true
                    loopStart = nil
                    loopEnd = nil
                } label: {
                    Label("Loop ayahs", systemImage: "repeat")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
            }
        }
    }

    /// Row tap: pick a loop boundary while picking, else seek to
    /// the ayah's estimated start (build 31).
    private func handleAyahTap(index: Int) {
        if loopPicking {
            if loopStart == nil {
                loopStart = index
            } else {
                let start = min(loopStart!, index)
                let end = max(loopStart!, index)
                player.loopAyahs(fromIndex: start, toIndex: end)
                loopStart = start
                loopEnd = end
                loopPicking = false
            }
            return
        }
        player.seek(to: quranAyahStartTime(ayahs, index: index,
                                           duration: player.duration))
    }

    /// Lyrics look (build 29, Spotify style kept as the only style
    /// in build 39): a vivid surah-colored card, big bold lines, the
    /// current ayah bright white, upcoming ayahs dark on the card.
    private var isSpotifyStyle: Bool { true }

    private enum RowState {
        case previous, current, upcoming
    }

    private func rowState(for index: Int) -> RowState {
        if index == currentAyahIndex { return .current }
        return index < currentAyahIndex ? .previous : .upcoming
    }

    private var ayahList: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if isSpotifyStyle {
                    HStack {
                        Text("Lyrics")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                        Spacer()
                        Text(surah?.english ?? "")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 6)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: isSpotifyStyle ? 4 : 10) {
                        ForEach(Array(ayahs.enumerated()), id: \.element.id) { index, ayah in
                            ayahRow(ayah, index: index, state: rowState(for: index))
                                .id(ayah.id)
                        }
                    }
                    .padding(.horizontal, isSpotifyStyle ? 20 : 18)
                    .padding(.vertical, 14)
                    .animation(.easeInOut(duration: 0.35), value: currentAyahIndex)
                }
                .simultaneousGesture(
                    DragGesture().onChanged { _ in
                        if liveScroll { liveScroll = false }
                    })
                .onChange(of: currentAyahIndex) { _, newIndex in
                    guard liveScroll, ayahs.indices.contains(newIndex) else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(ayahs[newIndex].id, anchor: .center)
                    }
                }
            }
            .background {
                if isSpotifyStyle, let surah {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(SurahPalette.color(for: surah.number, saturation: 0.72, brightness: 0.52))
                }
            }
            .padding(isSpotifyStyle ? 14 : 0)
            .overlay(alignment: .bottom) {
                if !liveScroll {
                    Button {
                        liveScroll = true
                        if ayahs.indices.contains(currentAyahIndex) {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                proxy.scrollTo(ayahs[currentAyahIndex].id, anchor: .center)
                            }
                        }
                    } label: {
                        Label("Live scroll", systemImage: "arrow.down.to.line")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Theme.deepGreen, in: Capsule())
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    @ViewBuilder
    private func ayahRow(_ ayah: QuranAyahText, index: Int,
                         state: RowState) -> some View {
        // In English-audio mode the translation is what is being
        // heard, so it takes the primary emphasis.
        let englishPrimary = player.audioLanguage == .english
        let bookmarked = surah.map {
            bookmarks.isBookmarked(surah: $0.number, ayah: ayah.n)
        } ?? false
        Group {
            if isSpotifyStyle {
                spotifyRow(ayah, state: state)
            } else {
                appleRow(ayah, state: state, englishPrimary: englishPrimary)
            }
        }
        .background {
            if loopPicking, loopStart == index {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.adaptiveGold.opacity(0.18))
            }
        }
        .overlay(alignment: .topTrailing) {
            if bookmarked {
                Image(systemName: "bookmark.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.adaptiveGold)
                    .padding(4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { handleAyahTap(index: index) }
        .contextMenu {
            if let surahNumber = surah?.number {
                Button {
                    bookmarks.toggle(surah: surahNumber, ayah: ayah.n)
                } label: {
                    Label(bookmarked ? "Remove bookmark" : "Bookmark ayah",
                          systemImage: bookmarked ? "bookmark.slash" : "bookmark")
                }
            }
            Menu("Repeat this ayah") {
                Button("2 times") { player.repeatAyah(index: index, plays: 2) }
                Button("3 times") { player.repeatAyah(index: index, plays: 3) }
                Button("5 times") { player.repeatAyah(index: index, plays: 5) }
                Button("Keep repeating") { player.repeatAyah(index: index, plays: nil) }
            }
            Button {
                player.seek(to: quranAyahStartTime(
                    ayahs, index: index, duration: player.duration))
            } label: {
                Label("Play from here", systemImage: "play.fill")
            }
        }
    }

    @ViewBuilder
    private func spotifyRow(_ ayah: QuranAyahText, state: RowState) -> some View {
        // Spotify card: bold lines; the current ayah is bright
        // white, ayahs still to come are dark on the vivid card,
        // ayahs already recited fade back.
        let arabicColor: Color = switch state {
        case .current: .white
        case .upcoming: .black.opacity(0.85)
        case .previous: .white.opacity(0.55)
        }
        let englishColor: Color = switch state {
        case .current: .white
        case .upcoming: .black.opacity(0.62)
        case .previous: .white.opacity(0.42)
        }
        VStack(alignment: .leading, spacing: 6) {
            if lyricsMode != "english" {
                Text(ayah.ar)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(arabicColor)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
            }
            if lyricsMode != "arabic" {
                Text(ayah.en)
                    .font(.body.weight(.bold))
                    .foregroundStyle(englishColor)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func appleRow(_ ayah: QuranAyahText, state: RowState,
                          englishPrimary: Bool) -> some View {
        // Karaoke row (unused since build 39 removed the Apple
        // Music layout): current ayah sharp; all others blurred.
        let isCurrent = state == .current
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("\(ayah.n)")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Theme.adaptiveGold)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Theme.adaptiveGold.opacity(0.15), in: Capsule())
                Spacer()
            }
            if lyricsMode != "english" {
                Text(ayah.ar)
                    .font(.title3)
                    .fontWeight(englishPrimary ? .regular : .bold)
                    .foregroundStyle(englishPrimary ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
            }
            if lyricsMode != "arabic" {
                Text(ayah.en)
                    .font(englishPrimary ? .body : .subheadline)
                    .fontWeight(englishPrimary ? .semibold : .bold)
                    .foregroundStyle(englishPrimary ? .primary : .secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .opacity(isCurrent ? 1 : 0.38)
        .blur(radius: isCurrent ? 0 : 3)
    }
}
