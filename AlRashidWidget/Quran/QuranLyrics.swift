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

struct QuranLyricsView: View {
    @EnvironmentObject private var player: QuranPlayer
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = QuranTextStore()
    /// "both" | "arabic" | "english"
    @AppStorage("quran.lyricsMode") private var lyricsMode = "both"
    @State private var liveScroll = true

    private var surah: QuranSurah? { player.currentSurah }

    private var ayahs: [QuranAyahText] {
        guard let surah else { return [] }
        return store.ayahsBySurah[surah.number] ?? []
    }

    /// Estimated current ayah index: playback fraction applied
    /// across the ayahs weighted by Arabic character count (longer
    /// ayahs take proportionally longer to recite).
    private var currentAyahIndex: Int {
        let list = ayahs
        guard !list.isEmpty, player.duration > 0 else { return 0 }
        let weights = list.map { Double(max($0.ar.count, 1)) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return 0 }
        var target = (player.currentTime / player.duration) * total
        for (index, weight) in weights.enumerated() {
            if target < weight { return index }
            target -= weight
        }
        return list.count - 1
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
            .background(Color(uiColor: .systemBackground))
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
            }
        }
        .onAppear { store.loadIfNeeded() }
    }

    private var ayahList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(ayahs.enumerated()), id: \.element.id) { index, ayah in
                        ayahRow(ayah, isCurrent: index == currentAyahIndex)
                            .id(ayah.id)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
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

    private func ayahRow(_ ayah: QuranAyahText, isCurrent: Bool) -> some View {
        // In English-audio mode the translation is what is being
        // heard, so it takes the primary emphasis.
        let englishPrimary = player.audioLanguage == .english
        return VStack(alignment: .leading, spacing: 6) {
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
                    .fontWeight(englishPrimary ? .regular : .semibold)
                    .foregroundStyle(englishPrimary ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
            }
            if lyricsMode != "arabic" {
                Text(ayah.en)
                    .font(englishPrimary ? .body : .subheadline)
                    .fontWeight(englishPrimary ? .semibold : .regular)
                    .foregroundStyle(englishPrimary ? .primary : .secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            isCurrent ? Theme.adaptiveGold.opacity(0.16) : Color.clear,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
