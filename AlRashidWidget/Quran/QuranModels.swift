//
//  QuranModels.swift
//  AlRashid Prayer Widget
//
//  Quran player (v2.1.0-private): the bundled surah catalogue
//  (surahs.json) — every surah's names, ayah count, revelation place
//  and per-reciter stream durations — plus the player's shared
//  brand colors. Audio itself is streamed per surah from the CDN in
//  the catalogue (or played from a local download, see
//  QuranDownloads). Target Membership: AlRashidWidget only.
//

import Foundation
import SwiftUI

// MARK: - Catalogue (surahs.json)

struct QuranReciter: Codable, Identifiable, Equatable {
    let id: String
    let name: String
}

struct QuranSurah: Codable, Identifiable, Equatable {
    let number: Int
    let arabic: String
    let english: String
    let meaning: String
    let ayahs: Int
    /// "Makki" or "Madani".
    let revelation: String
    /// Stream duration in seconds, keyed by reciter id.
    let durations: [String: Int]

    var id: Int { number }

    func duration(for reciterId: String) -> Int? {
        durations[reciterId]
    }
}

private struct QuranCatalogue: Codable {
    let reciters: [QuranReciter]
    let audioBase: String
    let surahs: [QuranSurah]
}

/// The bundled catalogue, loaded once from surahs.json.
enum QuranLibrary {
    private static let catalogue: QuranCatalogue = {
        guard let url = Bundle.main.url(forResource: "surahs", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(QuranCatalogue.self, from: data)
        else {
            assertionFailure("surahs.json missing or undecodable")
            return QuranCatalogue(reciters: [], audioBase: "", surahs: [])
        }
        return decoded
    }()

    static var reciters: [QuranReciter] { catalogue.reciters }
    static var surahs: [QuranSurah] { catalogue.surahs }
    static var audioBase: String { catalogue.audioBase }

    static func surah(_ number: Int) -> QuranSurah? {
        catalogue.surahs.first { $0.number == number }
    }

    static func reciter(_ id: String) -> QuranReciter? {
        catalogue.reciters.first { $0.id == id }
    }

    /// The first reciter in the catalogue (Alafasy) — the default.
    static var defaultReciter: QuranReciter? { catalogue.reciters.first }

    /// "{audioBase}/{reciterId}/{number}.mp3" — a 128 kbps stream.
    static func streamURL(surahNumber: Int, reciterId: String) -> URL? {
        URL(string: "\(catalogue.audioBase)/\(reciterId)/\(surahNumber).mp3")
    }

    /// Bundled stream duration for a surah under a reciter, if known.
    static func duration(surahNumber: Int, reciterId: String) -> TimeInterval? {
        guard let seconds = surah(surahNumber)?.duration(for: reciterId) else { return nil }
        return TimeInterval(seconds)
    }

    // MARK: English audio (v2.2.0-alpha)

    /// The pseudo-reciter id for the English translation audio. It
    /// keys the downloads folder (QuranAudio/english/) exactly like a
    /// reciter id, so the downloads machinery needs no special case.
    static let englishReciterId = "english"

    static let englishReciter = QuranReciter(
        id: englishReciterId, name: "Ibrahim Walk (English)")

    /// Full-surah English translation MP3s (Ibrahim Walk), hosted by
    /// QuranicAudio; surah number zero-padded to three digits.
    static func englishStreamURL(surahNumber: Int) -> URL? {
        URL(string: String(format: "https://download.quranicaudio.com/quran/ibrahim_walk/%03d.mp3",
                           surahNumber))
    }

    /// The stream URL for any reciter id, English included.
    static func audioURL(surahNumber: Int, reciterId: String) -> URL? {
        reciterId == englishReciterId
            ? englishStreamURL(surahNumber: surahNumber)
            : streamURL(surahNumber: surahNumber, reciterId: reciterId)
    }

    /// Bundled English durations (en_durations.json, measured from
    /// the hosted files), keyed by surah number.
    static let englishDurations: [Int: Int] = {
        guard let url = Bundle.main.url(forResource: "en_durations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return [:] }
        return decoded.reduce(into: [Int: Int]()) { result, pair in
            if let number = Int(pair.key) { result[number] = pair.value }
        }
    }()

    static func englishDuration(surahNumber: Int) -> TimeInterval? {
        englishDurations[surahNumber].map(TimeInterval.init)
    }

    /// "7:02" under an hour, "2:05:40" above it.
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Collections (v2.2.0-alpha)

/// A named playlist of surahs, shown as a card in the library.
struct QuranCollection: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let surahNumbers: [Int]

    var surahs: [QuranSurah] { surahNumbers.compactMap(QuranLibrary.surah) }

    static func == (lhs: QuranCollection, rhs: QuranCollection) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension QuranLibrary {
    static var collections: [QuranCollection] {
        [
            QuranCollection(
                id: "ramadan",
                title: "Ramadan",
                subtitle: "For the nights of Ramadan",
                surahNumbers: [2, 36, 18, 55, 67, 97, 12, 19, 78, 112, 113, 114]),
            QuranCollection(
                id: "eid",
                title: "Eid",
                subtitle: "Recited in the Eid prayers",
                surahNumbers: [87, 88, 50, 54, 109, 112, 113, 114]),
        ]
    }
}

// MARK: - Player brand colors (per the approved mockup)

/// Fixed mosque-green / gold palette for the Quran player surfaces.
/// The library sits on the app's light background; the mini player
/// and Now Playing wear the deep green from the mockup regardless of
/// the user's theme, like a record sleeve.
enum QuranTheme {
    /// #0B3D2E
    static let deepGreen = Color(red: 0.043, green: 0.239, blue: 0.180)
    /// #0E5A3F
    static let midGreen = Color(red: 0.055, green: 0.353, blue: 0.247)
    /// #06231A — the Now Playing gradient's foot.
    static let darkestGreen = Color(red: 0.024, green: 0.137, blue: 0.102)
    /// #0B7A55
    static let accentGreen = Color(red: 0.043, green: 0.478, blue: 0.333)
    /// #D4AF37
    static let gold = Color(red: 0.831, green: 0.686, blue: 0.216)
    /// #E9D48A
    static let lightGold = Color(red: 0.914, green: 0.831, blue: 0.541)
    /// #BFD8CC — soft green-white for secondary text on deep green.
    static let mutedOnGreen = Color(red: 0.749, green: 0.847, blue: 0.800)
    /// #E5484D — the favorite heart.
    static let heartRed = Color(red: 0.898, green: 0.282, blue: 0.302)
    /// #F6F7F4 — the library's page tint.
    static let pageTint = Color(red: 0.965, green: 0.969, blue: 0.957)
}
