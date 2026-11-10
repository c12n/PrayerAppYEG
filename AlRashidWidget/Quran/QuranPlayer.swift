//
//  QuranPlayer.swift
//  AlRashid Prayer Widget
//
//  Quran player (v2.1.0-private): the AVPlayer engine. Streams one
//  MP3 per surah from the catalogue CDN (or plays the downloaded
//  file), drives the Lock Screen / Control Center through
//  MPNowPlayingInfoCenter + MPRemoteCommandCenter, and persists the
//  session (last surah, position, reciter, favorites, repeat,
//  shuffle, rate) under quran.* keys in UserDefaults.standard.
//
//  Threading: every mutation happens on the main queue — the time
//  observer, item-end and audio-session observers are all registered
//  on .main, UI calls arrive on the main actor's queue by
//  construction, and remote-command handlers hop to main first.
//  Target Membership: AlRashidWidget only.
//

import AVFoundation
import Foundation
import MediaPlayer
import UIKit

final class QuranPlayer: ObservableObject {

    enum RepeatMode: Int, CaseIterable {
        case off, all, one
    }

    enum SleepOption: Equatable {
        case off
        case minutes(Int)
        case endOfSurah
    }

    /// Now Playing appearance (v2.2.0-alpha), switchable in the
    /// player and in the library menu. Raw values are the persisted
    /// `quran.playerStyle` strings.
    enum PlayerStyle: String, CaseIterable {
        case spotify = "spotify"
        case appleMusic = "applemusic"
    }

    /// Recitation language (v2.2.0-alpha): the Arabic reciters, or
    /// the English translation (Ibrahim Walk).
    enum AudioLanguage: String, CaseIterable {
        case arabic
        case english
    }

    /// Listening statistics (v2.2.0-alpha), persisted as JSON under
    /// `quran.stats.v1` and shown in the prayer tracker.
    struct ListeningStats: Codable, Equatable {
        var completedTotal: Int = 0
        /// Completion counts keyed by surah number (as a string).
        var perSurah: [String: Int] = [:]
        var secondsListened: Double = 0
    }

    // MARK: Published state

    @Published private(set) var currentSurah: QuranSurah?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    /// Duration of the loaded player item, once AVFoundation knows it.
    @Published private(set) var itemDuration: TimeInterval?
    @Published private(set) var queue: [Int] = []
    @Published private(set) var contextLabel: String = ""
    @Published private(set) var favorites: Set<Int> = []
    @Published private(set) var reciterId: String = ""
    @Published var repeatMode: RepeatMode = .off {
        didSet { defaults.set(repeatMode.rawValue, forKey: Keys.repeatMode) }
    }
    @Published var shuffle: Bool = false {
        didSet {
            defaults.set(shuffle, forKey: Keys.shuffle)
            rebuildTraversal(keepingCurrentFirst: true)
        }
    }
    @Published var rate: Float = 1.0 {
        didSet {
            defaults.set(Double(rate), forKey: Keys.rate)
            if isPlaying { player.rate = rate }
        }
    }
    @Published private(set) var sleepOption: SleepOption = .off
    @Published var playerStyle: PlayerStyle = .spotify {
        didSet { defaults.set(playerStyle.rawValue, forKey: Keys.playerStyle) }
    }
    @Published var audioLanguage: AudioLanguage = .arabic {
        didSet { defaults.set(audioLanguage.rawValue, forKey: Keys.audioLanguage) }
    }
    @Published private(set) var stats = ListeningStats()

    /// The best duration known for the current surah: the player
    /// item's own duration once loaded, else the bundled stream
    /// duration for the active language / reciter.
    var duration: TimeInterval {
        if let itemDuration, itemDuration > 0 { return itemDuration }
        guard let currentSurah else { return 0 }
        if audioLanguage == .english {
            return QuranLibrary.englishDuration(surahNumber: currentSurah.number) ?? 0
        }
        return QuranLibrary.duration(surahNumber: currentSurah.number,
                                     reciterId: reciterId) ?? 0
    }

    /// The reciter whose audio is actually playing: the English
    /// translation voice while the language is English.
    var currentReciter: QuranReciter? {
        audioLanguage == .english
            ? QuranLibrary.englishReciter
            : QuranLibrary.reciter(reciterId)
    }

    /// The id downloads and file lookups key on for the active
    /// language ("english" in English mode).
    var activeReciterId: String {
        audioLanguage == .english ? QuranLibrary.englishReciterId : reciterId
    }

    /// Duration to display for a surah in lists: follows the active
    /// language, like playback does.
    func displayDuration(for surah: QuranSurah) -> TimeInterval? {
        audioLanguage == .english
            ? QuranLibrary.englishDuration(surahNumber: surah.number)
            : QuranLibrary.duration(surahNumber: surah.number, reciterId: reciterId)
    }

    /// The surah that plays after the current one, if any.
    var upNextSurah: QuranSurah? {
        guard traversalPos + 1 < traversal.count else { return nil }
        return QuranLibrary.surah(queue[traversal[traversalPos + 1]])
    }

    var hasQueue: Bool { !queue.isEmpty }

    // MARK: Persistence keys

    private enum Keys {
        static let lastSurah = "quran.lastSurah"
        static let lastPosition = "quran.lastPosition"
        static let reciter = "quran.reciterId"
        static let favorites = "quran.favorites"
        static let repeatMode = "quran.repeatMode"
        static let shuffle = "quran.shuffle"
        static let rate = "quran.rate"
        static let playerStyle = "quran.playerStyle"
        static let audioLanguage = "quran.audioLanguage"
        static let stats = "quran.stats.v1"
    }

    private var defaults: UserDefaults { .standard }

    // MARK: Engine

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var interruptionWasPlaying = false
    private var sleepTimer: Timer?
    /// Seek to apply once the current item is ready (restore, or a
    /// seek requested while the stream is still loading).
    private var pendingSeek: TimeInterval?
    private var lastSavedSecond = -1
    private var lastInfoSecond = -1
    /// Listening-stats accumulation (v2.2.0-alpha): playback position
    /// at the last time-observer tick, and seconds not yet flushed
    /// into the persisted stats.
    private var lastObservedPlaybackTime: TimeInterval = 0
    private var unflushedListenSeconds: Double = 0

    /// Play order: indices into `queue`. Natural order, or shuffled
    /// (with the current surah first) while shuffle is on.
    private var traversal: [Int] = []
    private var traversalPos: Int = 0

    init() {
        let storedReciter = defaults.string(forKey: Keys.reciter) ?? ""
        reciterId = QuranLibrary.reciter(storedReciter) != nil
            ? storedReciter
            : (QuranLibrary.defaultReciter?.id ?? "")
        favorites = Set(defaults.array(forKey: Keys.favorites) as? [Int] ?? [])
        repeatMode = RepeatMode(rawValue: defaults.integer(forKey: Keys.repeatMode)) ?? .off
        shuffle = defaults.bool(forKey: Keys.shuffle)
        let storedRate = defaults.double(forKey: Keys.rate)
        rate = Self.allowedRates.contains(Float(storedRate)) ? Float(storedRate) : 1.0
        playerStyle = PlayerStyle(
            rawValue: defaults.string(forKey: Keys.playerStyle) ?? "") ?? .spotify
        audioLanguage = AudioLanguage(
            rawValue: defaults.string(forKey: Keys.audioLanguage) ?? "") ?? .arabic
        if let data = defaults.data(forKey: Keys.stats),
           let decoded = try? JSONDecoder().decode(ListeningStats.self, from: data) {
            stats = decoded
        }

        installTimeObserver()
        installRemoteCommands()
        installAudioSessionObservers()
        restoreLastSession()
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    static let allowedRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    static let sleepMinutes: [Int] = [5, 10, 15, 30, 45, 60]

    // MARK: - Loading & playback

    /// Starts a surah as part of a queue (surah numbers, in display
    /// order) under a context label ("All Surahs", "Favorites", ...).
    func play(surahNumber: Int, queue newQueue: [Int], contextLabel newContext: String) {
        guard let surah = QuranLibrary.surah(surahNumber) else { return }
        queue = newQueue.isEmpty ? [surahNumber] : newQueue
        contextLabel = newContext
        rebuildTraversal(keepingCurrentFirst: false)
        if let pos = traversal.firstIndex(where: { queue[$0] == surahNumber }) {
            traversalPos = pos
        } else {
            traversalPos = 0
        }
        load(surah, startAt: 0, autoplay: true)
    }

    /// Jumps to a surah already in the current queue (Queue sheet).
    func playFromQueue(surahNumber: Int) {
        guard queue.contains(surahNumber),
              let pos = traversal.firstIndex(where: { queue[$0] == surahNumber }),
              let surah = QuranLibrary.surah(surahNumber) else { return }
        traversalPos = pos
        load(surah, startAt: 0, autoplay: true)
    }

    /// Inserts a surah into the queue immediately after the current
    /// one (v2.2.0-alpha), in both the display queue and the play
    /// traversal, so it plays next whether shuffle is on or off.
    func playNext(_ surahNumber: Int) {
        guard QuranLibrary.surah(surahNumber) != nil else { return }
        guard !queue.isEmpty, !traversal.isEmpty, currentSurah != nil else {
            play(surahNumber: surahNumber, queue: [surahNumber],
                 contextLabel: contextLabel.isEmpty ? "All Surahs" : contextLabel)
            return
        }
        let insertAt = traversal[traversalPos] + 1
        queue.insert(surahNumber, at: insertAt)
        traversal = traversal.map { $0 >= insertAt ? $0 + 1 : $0 }
        traversal.insert(insertAt, at: traversalPos + 1)
    }

    /// Appends a surah to the end of the queue (v2.2.0-alpha), in
    /// both the display queue and the play traversal.
    func enqueue(_ surahNumber: Int) {
        guard QuranLibrary.surah(surahNumber) != nil else { return }
        guard !queue.isEmpty, currentSurah != nil else {
            play(surahNumber: surahNumber, queue: [surahNumber],
                 contextLabel: contextLabel.isEmpty ? "All Surahs" : contextLabel)
            return
        }
        queue.append(surahNumber)
        traversal.append(queue.count - 1)
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func resume() {
        guard currentSurah != nil else { return }
        activateSession()
        applyPlay()
        isPlaying = true
        persistPosition()
        updateNowPlaying()
    }

    func pause() {
        player.pause()
        isPlaying = false
        flushListenStats()
        persistPosition()
        updateNowPlaying()
    }

    func next() {
        advance(manual: true)
    }

    func previous() {
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        if traversalPos > 0 {
            traversalPos -= 1
            load(queueSurah, startAt: 0, autoplay: true)
        } else if repeatMode == .all, !traversal.isEmpty {
            traversalPos = traversal.count - 1
            load(queueSurah, startAt: 0, autoplay: true)
        } else {
            seek(to: 0)
        }
    }

    func seek(to seconds: TimeInterval) {
        let target = max(0, seconds)
        currentTime = target
        lastObservedPlaybackTime = target
        if player.currentItem?.status == .readyToPlay {
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                        toleranceBefore: CMTime(seconds: 0.5, preferredTimescale: 600),
                        toleranceAfter: CMTime(seconds: 0.5, preferredTimescale: 600))
            pendingSeek = nil
        } else {
            pendingSeek = target
        }
        persistPosition()
        updateNowPlaying()
    }

    func setRate(_ newRate: Float) {
        guard Self.allowedRates.contains(newRate) else { return }
        rate = newRate
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    func toggleShuffle() {
        shuffle.toggle()
    }

    /// Changes the reciter; a loaded surah reloads at the same
    /// position, playing or paused as it was.
    func setReciter(_ newReciterId: String) {
        guard newReciterId != reciterId,
              QuranLibrary.reciter(newReciterId) != nil else { return }
        reciterId = newReciterId
        defaults.set(newReciterId, forKey: Keys.reciter)
        itemDuration = nil
        if let surah = currentSurah {
            load(surah, startAt: currentTime, autoplay: isPlaying)
        }
    }

    /// Switches between the Arabic reciters and the English
    /// translation; a loaded surah reloads at the same position,
    /// playing or paused as it was (v2.2.0-alpha).
    func setAudioLanguage(_ newLanguage: AudioLanguage) {
        guard newLanguage != audioLanguage else { return }
        audioLanguage = newLanguage
        itemDuration = nil
        if let surah = currentSurah {
            load(surah, startAt: currentTime, autoplay: isPlaying)
        }
    }

    // MARK: Listening stats (v2.2.0-alpha)

    var completedSurahsTotal: Int { stats.completedTotal }

    var totalSecondsListened: TimeInterval { stats.secondsListened }

    func completionCount(for surahNumber: Int) -> Int {
        stats.perSurah["\(surahNumber)"] ?? 0
    }

    private func flushListenStats() {
        guard unflushedListenSeconds > 0 else { return }
        stats.secondsListened += unflushedListenSeconds
        unflushedListenSeconds = 0
        saveStats()
    }

    /// A surah reached its natural end (not a skip): count it.
    private func recordCompletion(of surah: QuranSurah) {
        flushListenStats()
        stats.completedTotal += 1
        stats.perSurah["\(surah.number)", default: 0] += 1
        saveStats()
    }

    private func saveStats() {
        if let data = try? JSONEncoder().encode(stats) {
            defaults.set(data, forKey: Keys.stats)
        }
    }

    // MARK: Sleep timer

    func setSleepOption(_ option: SleepOption) {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepOption = option
        if case .minutes(let minutes) = option {
            sleepTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes) * 60,
                                              repeats: false) { [weak self] _ in
                guard let self else { return }
                self.pause()
                self.sleepOption = .off
            }
        }
    }

    // MARK: Favorites

    func isFavorite(_ surahNumber: Int) -> Bool {
        favorites.contains(surahNumber)
    }

    func toggleFavorite(_ surahNumber: Int) {
        if favorites.contains(surahNumber) {
            favorites.remove(surahNumber)
        } else {
            favorites.insert(surahNumber)
        }
        defaults.set(favorites.sorted(), forKey: Keys.favorites)
    }

    // MARK: - Queue traversal

    private var queueSurah: QuranSurah {
        let number = queue[traversal[traversalPos]]
        return QuranLibrary.surah(number) ?? QuranLibrary.surahs[0]
    }

    private func rebuildTraversal(keepingCurrentFirst: Bool) {
        let currentNumber = currentSurah?.number
        var indices = Array(queue.indices)
        if shuffle {
            indices.shuffle()
            if keepingCurrentFirst,
               let currentNumber,
               let at = indices.firstIndex(where: { queue[$0] == currentNumber }) {
                indices.remove(at: at)
                indices.insert(at, at: 0)
            }
        }
        traversal = indices
        if let currentNumber,
           let pos = traversal.firstIndex(where: { queue[$0] == currentNumber }) {
            traversalPos = pos
        } else {
            traversalPos = 0
        }
    }

    private func advance(manual: Bool) {
        guard !traversal.isEmpty else { return }
        if traversalPos + 1 < traversal.count {
            traversalPos += 1
            load(queueSurah, startAt: 0, autoplay: true)
        } else if repeatMode == .all {
            traversalPos = 0
            load(queueSurah, startAt: 0, autoplay: true)
        } else if manual {
            // At the end of the queue with repeat off: nowhere to go.
        } else {
            finishPlayback()
        }
    }

    private func finishPlayback() {
        player.pause()
        isPlaying = false
        flushListenStats()
        persistPosition()
        updateNowPlaying()
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Item loading

    private func load(_ surah: QuranSurah, startAt: TimeInterval, autoplay: Bool) {
        let url = QuranDownloads.localFileURL(reciterId: activeReciterId, surahNumber: surah.number)
            ?? QuranLibrary.audioURL(surahNumber: surah.number, reciterId: activeReciterId)
        guard let url else { return }

        if let existingEndObserver = endObserver {
            NotificationCenter.default.removeObserver(existingEndObserver)
            endObserver = nil
        }
        let item = AVPlayerItem(url: url)
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            self?.handleItemEnd()
        }
        player.replaceCurrentItem(with: item)

        currentSurah = surah
        itemDuration = nil
        currentTime = startAt
        lastObservedPlaybackTime = startAt
        pendingSeek = startAt > 0 ? startAt : nil
        lastSavedSecond = -1
        lastInfoSecond = -1
        defaults.set(surah.number, forKey: Keys.lastSurah)
        persistPosition()

        if autoplay {
            activateSession()
            applyPlay()
            isPlaying = true
        } else {
            isPlaying = false
        }
        updateNowPlaying()
    }

    private func handleItemEnd() {
        // The item played to its natural end: a completion, however
        // playback continues from here (sleep stop, repeat, advance).
        if let finished = currentSurah {
            recordCompletion(of: finished)
        }
        if sleepOption == .endOfSurah {
            sleepOption = .off
            finishPlayback()
            return
        }
        if repeatMode == .one {
            seek(to: 0)
            applyPlay()
            isPlaying = true
            updateNowPlaying()
            return
        }
        advance(manual: false)
    }

    private func applyPlay() {
        if rate == 1.0 {
            player.play()
        } else {
            player.rate = rate
        }
    }

    // MARK: - Session restore

    private func restoreLastSession() {
        let number = defaults.integer(forKey: Keys.lastSurah)
        guard number > 0, let surah = QuranLibrary.surah(number) else { return }
        queue = QuranLibrary.surahs.map(\.number)
        contextLabel = "All Surahs"
        rebuildTraversal(keepingCurrentFirst: false)
        if let pos = traversal.firstIndex(where: { queue[$0] == number }) {
            traversalPos = pos
        }
        let position = defaults.double(forKey: Keys.lastPosition)
        load(surah, startAt: position, autoplay: false)
    }

    private func persistPosition() {
        defaults.set(currentTime, forKey: Keys.lastPosition)
        lastSavedSecond = Int(currentTime)
    }

    // MARK: - Observers & system integration

    private func installTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 2)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval,
                                                      queue: .main) { [weak self] time in
            guard let self else { return }
            self.currentTime = max(0, time.seconds.isFinite ? time.seconds : 0)
            // Listening stats: credit the position delta while
            // playing (small, forward only, so seeks and stalls
            // never inflate it).
            let delta = self.currentTime - self.lastObservedPlaybackTime
            if self.isPlaying, delta > 0, delta <= 2 {
                self.unflushedListenSeconds += delta
            }
            self.lastObservedPlaybackTime = self.currentTime
            if self.unflushedListenSeconds >= 10 {
                self.flushListenStats()
            }
            if let item = self.player.currentItem {
                if item.status == .failed, self.isPlaying {
                    self.isPlaying = false
                    self.updateNowPlaying()
                }
                let itemSeconds = item.duration.seconds
                if itemSeconds.isFinite, itemSeconds > 0,
                   self.itemDuration != itemSeconds {
                    self.itemDuration = itemSeconds
                }
                if let pending = self.pendingSeek, item.status == .readyToPlay {
                    self.pendingSeek = nil
                    self.player.seek(
                        to: CMTime(seconds: pending, preferredTimescale: 600),
                        toleranceBefore: CMTime(seconds: 0.5, preferredTimescale: 600),
                        toleranceAfter: CMTime(seconds: 0.5, preferredTimescale: 600))
                }
            }
            let whole = Int(self.currentTime)
            if whole != self.lastInfoSecond {
                self.lastInfoSecond = whole
                self.updateNowPlaying()
            }
            if abs(whole - self.lastSavedSecond) >= 5 {
                self.persistPosition()
            }
        }
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
    }

    private func installAudioSessionObservers() {
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification,
                           object: nil, queue: .main) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw)
            else { return }
            switch type {
            case .began:
                self.interruptionWasPlaying = self.isPlaying
                if self.isPlaying { self.pause() }
            case .ended:
                let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
                if self.interruptionWasPlaying, options.contains(.shouldResume) {
                    self.resume()
                }
                self.interruptionWasPlaying = false
            @unknown default:
                break
            }
        }
        center.addObserver(forName: AVAudioSession.routeChangeNotification,
                           object: nil, queue: .main) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
            else { return }
            // Headphones unplugged / Bluetooth device gone: pause
            // rather than blasting from the speaker.
            if reason == .oldDeviceUnavailable, self.isPlaying {
                self.pause()
            }
        }
    }

    // MARK: Now Playing / remote commands

    private func updateNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        guard let surah = currentSurah else {
            center.nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = surah.english
        info[MPMediaItemPropertyArtist] = currentReciter?.name ?? ""
        info[MPMediaItemPropertyAlbumTitle] = "Quran"
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? rate : 0.0
        center.nowPlayingInfo = info
    }

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func installRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.onMain { self.resume() }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.onMain { self.pause() }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.onMain { self.togglePlayPause() }
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.onMain { self.next() }
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.onMain { self.previous() }
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent
            else { return .commandFailed }
            let position = positionEvent.positionTime
            self.onMain { self.seek(to: position) }
            return .success
        }
    }
}
