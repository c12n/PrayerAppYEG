//
//  QuranLibraryView.swift
//  AlRashid Prayer Widget
//
//  Quran player (v2.2.0-alpha): the library — "Quran" title with
//  the reciter and listening stats, search, Favorites / Downloaded
//  chips, Ramadan + Eid collections, and every surah as a track row
//  with a number tile, names, duration, favorite heart and download
//  state. Hosted either as the app's Quran cover (2.1.0 style) or
//  in the Quran tab of the phone tab shell (embeddedInTab), where
//  the app-wide mini player takes over the bottom inset.
//  Target Membership: AlRashidWidget only.
//

import SwiftUI

struct QuranLibraryView: View {
    /// True when hosted in the phone tab shell: no close button and
    /// no own mini player (the shell floats one above the tab bar).
    var embeddedInTab: Bool = false

    @EnvironmentObject private var player: QuranPlayer
    @EnvironmentObject private var downloads: QuranDownloads
    @EnvironmentObject private var bookmarks: QuranBookmarks
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var favoritesOnly = false
    @State private var downloadedOnly = false
    @State private var bookmarksOnly = false
    @State private var showNowPlaying = false
    @State private var showDownloadsManager = false
    @State private var showLibraryOptions = false

    private var displayedSurahs: [QuranSurah] {
        var list = QuranLibrary.surahs
        if favoritesOnly {
            list = list.filter { player.isFavorite($0.number) }
        }
        if downloadedOnly {
            list = list.filter {
                downloads.isDownloaded(reciterId: player.activeReciterId, surahNumber: $0.number)
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
                if bookmarksOnly {
                    bookmarksSection
                } else {
                    if searchText.isEmpty, !favoritesOnly, !downloadedOnly {
                        collectionsSection
                    }
                    if favoritesOnly, !displayedSurahs.isEmpty {
                        playAllSection
                    }
                    surahSection
                }
            }
            .listStyle(.plain)
            .background(Color(uiColor: .systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: QuranCollection.self) { collection in
                CollectionDetailView(collection: collection)
            }
            .toolbar {
                if !embeddedInTab {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.subheadline.weight(.bold))
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    optionsMenu
                }
                // (Build 38: the standalone Now Playing music-note
                // button is gone at Youssef's call — the mini player
                // at the bottom and tapping the surah artwork open
                // the full player. Removing it also removes the
                // build-29 toolbar-pill flicker concern entirely.)
            }
            .searchable(text: $searchText, prompt: "Search surahs")
            .safeAreaInset(edge: .bottom) {
                if !embeddedInTab, player.currentSurah != nil, !showNowPlaying {
                    MiniPlayerView { showNowPlaying = true }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
            }
        }
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingView()
        }
        .sheet(isPresented: $showDownloadsManager) {
            QuranDownloadsManagerView()
        }
        .sheet(isPresented: $showLibraryOptions) {
            libraryOptionsSheet
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
                Text("\(player.completedSurahsTotal) surahs completed • \(listenedLabel) listened")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.green)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .padding(.top, 4)
        }
    }

    /// "12h 5m" / "45m" / "0m" of accumulated listening time.
    private var listenedLabel: String {
        let total = Int(player.totalSecondsListened.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private var chipsSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    chip(title: "Favorites",
                         systemImage: "heart.fill",
                         iconColor: Color(red: 0.9, green: 0.28, blue: 0.3),
                         count: player.favorites.count,
                         isOn: favoritesOnly) {
                        favoritesOnly.toggle()
                        if favoritesOnly { bookmarksOnly = false }
                    }
                    chip(title: "Downloaded",
                         systemImage: "arrow.down.circle.fill",
                         iconColor: Theme.green,
                         count: downloads.downloadedCount,
                         isOn: downloadedOnly) {
                        downloadedOnly.toggle()
                        if downloadedOnly { bookmarksOnly = false }
                    }
                    chip(title: "Bookmarks",
                         systemImage: "bookmark.fill",
                         iconColor: Theme.adaptiveGold,
                         count: bookmarks.bookmarks.count,
                         isOn: bookmarksOnly) {
                        bookmarksOnly.toggle()
                        if bookmarksOnly {
                            favoritesOnly = false
                            downloadedOnly = false
                        }
                    }
                    if player.currentSurah != nil {
                        chip(title: "Continue",
                             systemImage: "arrow.counterclockwise",
                             iconColor: Theme.green,
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
                        .foregroundStyle(Theme.green)
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(
                isOn ? Theme.green.opacity(0.16) : Color(uiColor: .secondarySystemBackground),
                in: Capsule())
            .overlay {
                Capsule().strokeBorder(
                    isOn ? Theme.green : Color.gray.opacity(0.25),
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
                        LinearGradient(colors: [Theme.green, Theme.deepGreen],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 2, trailing: 16))
        }
    }

    // MARK: Bookmarks (build 31)

    private var bookmarksSection: some View {
        Section {
            if bookmarks.bookmarks.isEmpty {
                Text("No bookmarks yet. In the lyrics, long-press any ayah to bookmark it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(bookmarks.bookmarks) { bookmark in
                Button {
                    playBookmark(bookmark)
                } label: {
                    bookmarkRow(bookmark)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(Color.gray.opacity(0.18))
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        bookmarks.remove(bookmark)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text("Bookmarks")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
    }

    private func bookmarkRow(_ bookmark: QuranBookmark) -> some View {
        let surah = QuranLibrary.surah(bookmark.surah)
        let ayahText = QuranTextData.ayahsBySurah[bookmark.surah]?
            .first { $0.n == bookmark.ayah }
        return HStack(spacing: 12) {
            Image(systemName: "bookmark.fill")
                .font(.subheadline)
                .foregroundStyle(Theme.adaptiveGold)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(surah?.english ?? "Surah \(bookmark.surah)") · Ayah \(bookmark.ayah)")
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let ayahText {
                    Text(ayahText.en)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Image(systemName: "play.circle.fill")
                .font(.title3)
                .foregroundStyle(Theme.green)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// Plays the bookmarked surah and seeks to the ayah's
    /// estimated start, then opens the player.
    private func playBookmark(_ bookmark: QuranBookmark) {
        guard QuranLibrary.surah(bookmark.surah) != nil else { return }
        player.play(surahNumber: bookmark.surah,
                    queue: QuranLibrary.surahs.map(\.number),
                    contextLabel: "Bookmarks")
        let ayahs = QuranTextData.ayahsBySurah[bookmark.surah] ?? []
        if let index = ayahs.firstIndex(where: { $0.n == bookmark.ayah }) {
            player.seek(to: quranAyahStartTime(ayahs, index: index,
                                               duration: player.duration))
        }
        showNowPlaying = true
    }

    // MARK: Collections

    private var collectionsSection: some View {
        Section {
            ForEach(QuranLibrary.collections) { collection in
                NavigationLink(value: collection) {
                    CollectionCard(collection: collection)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .contextMenu {
                    Button {
                        playCollection(collection, shuffle: false)
                    } label: {
                        Label("Play All", systemImage: "play.fill")
                    }
                    Button {
                        playCollection(collection, shuffle: true)
                    } label: {
                        Label("Shuffle Play", systemImage: "shuffle")
                    }
                }
            }
        } header: {
            Text("Collections")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
    }

    private func playCollection(_ collection: QuranCollection, shuffle: Bool) {
        guard let first = collection.surahNumbers.first else { return }
        player.play(surahNumber: first,
                    queue: collection.surahNumbers,
                    contextLabel: collection.title)
        if shuffle, !player.shuffle { player.toggleShuffle() }
        if !shuffle, player.shuffle { player.toggleShuffle() }
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
                        surahMenuItems(surah) {
                            player.play(surahNumber: surah.number,
                                        queue: displayedSurahs.map(\.number),
                                        contextLabel: contextLabel)
                        }
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
        if downloadedOnly { return "Nothing downloaded for this voice yet." }
        return "No surahs match your search."
    }

    /// The context menu shared by library rows and collection rows:
    /// Play, Play Next, Add to Queue, Favorite, Download.
    @ViewBuilder
    func surahMenuItems(_ surah: QuranSurah, onPlay: @escaping () -> Void) -> some View {
        Button {
            onPlay()
        } label: {
            Label("Play", systemImage: "play.fill")
        }
        Button {
            player.playNext(surah.number)
        } label: {
            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }
        Button {
            player.enqueue(surah.number)
        } label: {
            Label("Add to Queue", systemImage: "list.bullet")
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

    @ViewBuilder
    private func downloadMenuItems(_ surah: QuranSurah) -> some View {
        let reciterId = player.activeReciterId
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
                Label("Remove download", systemImage: "trash")
            }
        } else {
            Button {
                downloads.download(surahNumber: surah.number, reciterId: reciterId)
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
        }
    }

    // MARK: Options (language / reciter / player style)

    /// Library options (build 38): a dedicated sheet with native
    /// pickers. This was a UIMenu before — too tall for its popover,
    /// it refused to scroll and jittered as the player state kept
    /// re-rendering it mid-gesture. A sheet scrolls normally and
    /// picker selections apply live without re-laying the menu out.
    private var optionsMenu: some View {
        Button {
            showLibraryOptions = true
        } label: {
            Label("Options", systemImage: "ellipsis.circle")
                .font(.subheadline.weight(.semibold))
        }
    }

    private var libraryOptionsSheet: some View {
        NavigationStack {
            Form {
                Section("Player style") {
                    Picker("Player style", selection: Binding(
                        get: { player.playerStyle },
                        set: { player.playerStyle = $0 }
                    )) {
                        Text("Spotify").tag(QuranPlayer.PlayerStyle.spotify)
                        Text("Apple Music").tag(QuranPlayer.PlayerStyle.appleMusic)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Audio language") {
                    Picker("Audio language", selection: Binding(
                        get: { player.audioLanguage },
                        set: { player.setAudioLanguage($0) }
                    )) {
                        Text("Arabic").tag(QuranPlayer.AudioLanguage.arabic)
                        Text("English (Ibrahim Walk)").tag(QuranPlayer.AudioLanguage.english)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                if player.audioLanguage == .arabic {
                    Section("Reciter") {
                        Picker("Reciter", selection: Binding(
                            get: { player.reciterId },
                            set: { player.setReciter($0) }
                        )) {
                            ForEach(QuranLibrary.reciters) { reciter in
                                Text(reciter.name).tag(reciter.id)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }
                Section {
                    Button {
                        showLibraryOptions = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            showDownloadsManager = true
                        }
                    } label: {
                        Label("Manage downloads", systemImage: "arrow.down.circle")
                    }
                }
            }
            .navigationTitle("Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showLibraryOptions = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Collection card & detail

private struct CollectionCard: View {
    let collection: QuranCollection

    private var isRamadan: Bool { collection.id == "ramadan" }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: isRamadan ? "moon.stars.fill" : "sparkles")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    LinearGradient(
                        colors: isRamadan
                            ? [Theme.green, Theme.deepGreen]
                            : [Theme.gold, Theme.deepGreen],
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(collection.title)
                    .font(.body.weight(.bold))
                    .foregroundStyle(.primary)
                Text(collection.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(collection.surahNumbers.count) surahs")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.green)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct CollectionDetailView: View {
    @EnvironmentObject private var player: QuranPlayer
    @EnvironmentObject private var downloads: QuranDownloads
    let collection: QuranCollection
    @State private var showNowPlaying = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Button {
                        play(shuffle: false)
                    } label: {
                        Label("Play All", systemImage: "play.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.deepGreen,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    Button {
                        play(shuffle: true)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .font(.headline)
                            .foregroundStyle(Theme.deepGreen)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.adaptiveGold.opacity(0.25),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
            }
            Section {
                ForEach(collection.surahs) { surah in
                    SurahRow(surah: surah,
                             isCurrent: surah.number == player.currentSurah?.number,
                             onPlay: { playSurah(surah) })
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Color.gray.opacity(0.18))
                        .contextMenu {
                            Button {
                                playSurah(surah)
                            } label: {
                                Label("Play", systemImage: "play.fill")
                            }
                            Button {
                                player.playNext(surah.number)
                            } label: {
                                Label("Play Next",
                                      systemImage: "text.line.first.and.arrowtriangle.forward")
                            }
                            Button {
                                player.enqueue(surah.number)
                            } label: {
                                Label("Add to Queue", systemImage: "list.bullet")
                            }
                            Button {
                                player.toggleFavorite(surah.number)
                            } label: {
                                Label(player.isFavorite(surah.number)
                                      ? "Remove from Favorites" : "Add to Favorites",
                                      systemImage: player.isFavorite(surah.number)
                                      ? "heart.slash" : "heart")
                            }
                        }
                }
            }
        }
        .listStyle(.plain)
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(collection.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingView()
        }
    }

    private func play(shuffle: Bool) {
        guard let first = collection.surahNumbers.first else { return }
        player.play(surahNumber: first,
                    queue: collection.surahNumbers,
                    contextLabel: collection.title)
        if shuffle, !player.shuffle { player.toggleShuffle() }
        if !shuffle, player.shuffle { player.toggleShuffle() }
        showNowPlaying = true
    }

    private func playSurah(_ surah: QuranSurah) {
        player.play(surahNumber: surah.number,
                    queue: collection.surahNumbers,
                    contextLabel: collection.title)
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
                            .foregroundStyle(isCurrent ? Theme.green : .primary)
                        Text(surah.arabic)
                            .font(.body)
                            .foregroundStyle(Theme.deepGreen)
                        if isFridayPick {
                            Text("FRIDAY PICK")
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(0.6)
                                .foregroundStyle(Theme.green)
                        }
                        if isCurrent {
                            Image(systemName: player.isPlaying
                                  ? "speaker.wave.2.fill" : "pause.circle.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.green)
                        }
                    }
                    Text("\(surah.meaning) | \(surah.ayahs) ayahs | \(surah.revelation)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if let seconds = player.displayDuration(for: surah) {
                    Text(QuranLibrary.formatDuration(seconds))
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
            .foregroundStyle(isFridayPick ? Theme.deepGreen : Theme.lightGold)
            .frame(width: 46, height: 46)
            .background(
                LinearGradient(
                    colors: isFridayPick
                        ? [Theme.lightGold, Theme.gold]
                        : [Theme.deepGreen, Theme.green],
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
                                 ? Color(red: 0.9, green: 0.28, blue: 0.3) : Color.gray.opacity(0.45))
                .frame(width: 34, height: 40)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var downloadControl: some View {
        let reciterId = player.activeReciterId
        if let progress = downloads.progress(reciterId: reciterId, surahNumber: surah.number) {
            Button {
                downloads.cancel(surahNumber: surah.number, reciterId: reciterId)
            } label: {
                ZStack {
                    Circle().stroke(Color.gray.opacity(0.25), lineWidth: 2.5)
                        .frame(width: 22, height: 22)
                    Circle()
                        .trim(from: 0, to: max(0.02, progress))
                        .stroke(Theme.green,
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: 22, height: 22)
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "stop.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(Theme.green)
                }
                .frame(width: 34, height: 40)
            }
            .buttonStyle(.plain)
        } else if downloads.isDownloaded(reciterId: reciterId, surahNumber: surah.number) {
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(Theme.green)
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

// MARK: - Downloads manager (build 31)

/// Bulk downloads + storage per voice: download all 114 surahs,
/// cancel in-flight downloads, delete a voice's files, and see how
/// much space each voice uses.
private struct QuranDownloadsManagerView: View {
    @EnvironmentObject private var downloads: QuranDownloads
    @Environment(\.dismiss) private var dismiss

    private var voices: [(id: String, name: String)] {
        QuranLibrary.reciters.map { (id: $0.id, name: $0.name) }
            + [(id: QuranLibrary.englishReciterId,
                name: QuranLibrary.englishReciter.name)]
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Downloaded surahs",
                                   value: "\(downloads.downloadedCount)")
                    LabeledContent("Storage used",
                                   value: byteLabel(downloads.totalBytes))
                }
                ForEach(voices, id: \.id) { voice in
                    Section {
                        let count = downloads.downloadedCount(reciterId: voice.id)
                        let active = downloads.activeDownloadCount(reciterId: voice.id)
                        LabeledContent("On device", value: "\(count) of 114")
                        if active > 0 {
                            LabeledContent("Downloading now",
                                           value: "\(active) in progress")
                        }
                        LabeledContent("Storage",
                                       value: byteLabel(downloads.bytes(reciterId: voice.id)))
                        if active > 0 {
                            Button("Cancel downloads", role: .destructive) {
                                downloads.cancelAll(reciterId: voice.id)
                            }
                        } else if count < 114 {
                            Button("Download all 114 surahs") {
                                downloads.downloadAll(reciterId: voice.id)
                            }
                        }
                        if count > 0 {
                            Button("Delete all downloads", role: .destructive) {
                                downloads.deleteAll(reciterId: voice.id)
                            }
                        }
                    } header: {
                        Text(voice.name)
                    }
                }
            }
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func byteLabel(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
