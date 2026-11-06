//
//  QuranLibraryView.swift
//  AlRashid Prayer Widget
//
//  Quran player (v2.1.0-private): the library, per the approved
//  mockup — "Quran" title with the reciter, search, Favorites /
//  Downloaded / Continue chips, and every surah as a track row with
//  a number tile, names, duration, favorite heart and download
//  state. Tapping a row plays it with the displayed order as the
//  queue; the mini player rides at the bottom and opens Now
//  Playing. Presented as the app's Quran full-screen cover.
//  Target Membership: AlRashidWidget only.
//

import SwiftUI

struct QuranLibraryView: View {
    @EnvironmentObject private var player: QuranPlayer
    @EnvironmentObject private var downloads: QuranDownloads
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var favoritesOnly = false
    @State private var downloadedOnly = false
    @State private var showNowPlaying = false

    private var displayedSurahs: [QuranSurah] {
        var list = QuranLibrary.surahs
        if favoritesOnly {
            list = list.filter { player.isFavorite($0.number) }
        }
        if downloadedOnly {
            list = list.filter {
                downloads.isDownloaded(reciterId: player.reciterId, surahNumber: $0.number)
            }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            list = list.filter {
                $0.english.lowercased().contains(query)
                    || $0.meaning.lowercased().contains(query)
                    || $0.arabic.contains(searchText.trimmingCharacters(in: .whitespaces))
                    || "\($0.number)" == query
            }
        }
        return list
    }

    private var contextLabel: String {
        if favoritesOnly { return "Favorites" }
        if downloadedOnly { return "Downloaded" }
        return "All Surahs"
    }

    var body: some View {
        NavigationStack {
            List {
                headerSection
                chipsSection
                if favoritesOnly, !displayedSurahs.isEmpty {
                    playAllSection
                }
                surahSection
            }
            .listStyle(.plain)
            .background(QuranTheme.pageTint)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    reciterMenu
                }
                if player.currentSurah != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showNowPlaying = true
                        } label: {
                            Label("Now Playing", systemImage: "music.note")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search surahs")
            .safeAreaInset(edge: .bottom) {
                if player.currentSurah != nil, !showNowPlaying {
                    MiniPlayerView { showNowPlaying = true }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
            }
        }
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingView()
        }
    }

    // MARK: Header & chips

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 3) {
                Text("Quran")
                    .font(.largeTitle.weight(.bold))
                Text("114 surahs | \(player.currentReciter?.name ?? "")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .padding(.top, 4)
        }
    }

    private var chipsSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    chip(title: "Favorites",
                         systemImage: "heart.fill",
                         iconColor: QuranTheme.heartRed,
                         count: player.favorites.count,
                         isOn: favoritesOnly) {
                        favoritesOnly.toggle()
                    }
                    chip(title: "Downloaded",
                         systemImage: "arrow.down.circle.fill",
                         iconColor: QuranTheme.accentGreen,
                         count: downloads.downloadedCount,
                         isOn: downloadedOnly) {
                        downloadedOnly.toggle()
                    }
                    if player.currentSurah != nil {
                        chip(title: "Continue",
                             systemImage: "arrow.counterclockwise",
                             iconColor: QuranTheme.accentGreen,
                             count: nil,
                             isOn: false) {
                            player.resume()
                            showNowPlaying = true
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 0))
        }
    }

    private func chip(title: String, systemImage: String, iconColor: Color,
                      count: Int?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let count {
                    Text("\(count)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(QuranTheme.accentGreen)
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(
                isOn ? QuranTheme.accentGreen.opacity(0.18) : Color.white,
                in: Capsule())
            .overlay {
                Capsule().strokeBorder(
                    isOn ? QuranTheme.accentGreen : Color.gray.opacity(0.25),
                    lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var playAllSection: some View {
        Section {
            Button {
                guard let first = displayedSurahs.first else { return }
                player.play(surahNumber: first.number,
                            queue: displayedSurahs.map(\.number),
                            contextLabel: "Favorites")
                showNowPlaying = true
            } label: {
                Label("Play all favorites", systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        LinearGradient(colors: [QuranTheme.midGreen, QuranTheme.deepGreen],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 2, trailing: 16))
        }
    }

    // MARK: Surah rows

    private var surahSection: some View {
        Section {
            if displayedSurahs.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(displayedSurahs) { surah in
                SurahRow(surah: surah,
                         isCurrent: surah.number == player.currentSurah?.number,
                         onPlay: {
                             player.play(surahNumber: surah.number,
                                         queue: displayedSurahs.map(\.number),
                                         contextLabel: contextLabel)
                         })
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Color.gray.opacity(0.18))
                    .contextMenu {
                        Button {
                            player.play(surahNumber: surah.number,
                                        queue: displayedSurahs.map(\.number),
                                        contextLabel: contextLabel)
                        } label: {
                            Label("Play", systemImage: "play.fill")
                        }
                        Button {
                            player.toggleFavorite(surah.number)
                        } label: {
                            Label(player.isFavorite(surah.number)
                                  ? "Remove from Favorites" : "Add to Favorites",
                                  systemImage: player.isFavorite(surah.number)
                                  ? "heart.slash" : "heart")
                        }
                        downloadMenuItems(surah)
                    }
            }
        } header: {
            if !favoritesOnly, !downloadedOnly, searchText.isEmpty {
                Text("All Surahs")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyMessage: String {
        if favoritesOnly { return "No favorites yet. Tap the heart on any surah." }
        if downloadedOnly { return "Nothing downloaded for this reciter yet." }
        return "No surahs match your search."
    }

    @ViewBuilder
    private func downloadMenuItems(_ surah: QuranSurah) -> some View {
        let reciterId = player.reciterId
        if downloads.isDownloading(reciterId: reciterId, surahNumber: surah.number) {
            Button {
                downloads.cancel(surahNumber: surah.number, reciterId: reciterId)
            } label: {
                Label("Cancel download", systemImage: "xmark.circle")
            }
        } else if downloads.isDownloaded(reciterId: reciterId, surahNumber: surah.number) {
            Button(role: .destructive) {
                downloads.delete(surahNumber: surah.number, reciterId: reciterId)
            } label: {
                Label("Delete download", systemImage: "trash")
            }
        } else {
            Button {
                downloads.download(surahNumber: surah.number, reciterId: reciterId)
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
        }
    }

    // MARK: Reciter picker

    private var reciterMenu: some View {
        Menu {
            ForEach(QuranLibrary.reciters) { reciter in
                Button {
                    player.setReciter(reciter.id)
                } label: {
                    if reciter.id == player.reciterId {
                        Label(reciter.name, systemImage: "checkmark")
                    } else {
                        Text(reciter.name)
                    }
                }
            }
        } label: {
            Label("Reciter", systemImage: "person.wave.2")
                .font(.subheadline.weight(.semibold))
        }
    }
}

// MARK: - Surah row

private struct SurahRow: View {
    @EnvironmentObject private var player: QuranPlayer
    @EnvironmentObject private var downloads: QuranDownloads
    let surah: QuranSurah
    let isCurrent: Bool
    /// Plays this surah. Bound to the tile + names area only, so the
    /// heart and download buttons never double as play taps.
    let onPlay: () -> Void

    private var isFridayPick: Bool { surah.number == 18 }

    var body: some View {
        HStack(spacing: 13) {
            HStack(spacing: 13) {
                numberTile
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(surah.english)
                            .font(.body.weight(.bold))
                            .foregroundStyle(isCurrent ? QuranTheme.accentGreen : .primary)
                        Text(surah.arabic)
                            .font(.body)
                            .foregroundStyle(QuranTheme.deepGreen)
                        if isFridayPick {
                            Text("FRIDAY PICK")
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(0.6)
                                .foregroundStyle(QuranTheme.accentGreen)
                        }
                        if isCurrent {
                            Image(systemName: player.isPlaying
                                  ? "speaker.wave.2.fill" : "pause.circle.fill")
                                .font(.caption)
                                .foregroundStyle(QuranTheme.accentGreen)
                        }
                    }
                    Text("\(surah.meaning) | \(surah.ayahs) ayahs | \(surah.revelation)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if let seconds = surah.duration(for: player.reciterId) {
                    Text(QuranLibrary.formatDuration(TimeInterval(seconds)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onPlay)

            downloadControl
            favoriteButton
        }
        .padding(.vertical, 4)
    }

    private var numberTile: some View {
        Text("\(surah.number)")
            .font(.subheadline.weight(.heavy))
            .foregroundStyle(isFridayPick ? QuranTheme.deepGreen : QuranTheme.lightGold)
            .frame(width: 46, height: 46)
            .background(
                LinearGradient(
                    colors: isFridayPick
                        ? [QuranTheme.lightGold, QuranTheme.gold]
                        : [QuranTheme.deepGreen, QuranTheme.midGreen],
                    startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var favoriteButton: some View {
        Button {
            player.toggleFavorite(surah.number)
        } label: {
            Image(systemName: player.isFavorite(surah.number) ? "heart.fill" : "heart")
                .font(.body)
                .foregroundStyle(player.isFavorite(surah.number)
                                 ? QuranTheme.heartRed : Color.gray.opacity(0.45))
                .frame(width: 34, height: 40)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var downloadControl: some View {
        let reciterId = player.reciterId
        if let progress = downloads.progress(reciterId: reciterId, surahNumber: surah.number) {
            Button {
                downloads.cancel(surahNumber: surah.number, reciterId: reciterId)
            } label: {
                ZStack {
                    Circle().stroke(Color.gray.opacity(0.25), lineWidth: 2.5)
                        .frame(width: 22, height: 22)
                    Circle()
                        .trim(from: 0, to: max(0.02, progress))
                        .stroke(QuranTheme.accentGreen,
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: 22, height: 22)
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "stop.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(QuranTheme.accentGreen)
                }
                .frame(width: 34, height: 40)
            }
            .buttonStyle(.plain)
        } else if downloads.isDownloaded(reciterId: reciterId, surahNumber: surah.number) {
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(QuranTheme.accentGreen)
                .frame(width: 34, height: 40)
        } else {
            Button {
                downloads.download(surahNumber: surah.number, reciterId: reciterId)
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.body)
                    .foregroundStyle(Color.gray.opacity(0.55))
                    .frame(width: 34, height: 40)
            }
            .buttonStyle(.plain)
        }
    }
}
