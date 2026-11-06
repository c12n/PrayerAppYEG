//
//  MiniPlayerView.swift
//  AlRashid Prayer Widget
//
//  Quran player (v2.1.0-private): the persistent mini player — a
//  deep-green bar with the surah's Arabic tile, names, a hairline
//  progress track and transport controls. Tapping the bar (outside
//  the buttons) opens Now Playing via `onOpen`. Used at the bottom
//  of the Quran library and as the app-wide overlay above the home
//  layouts. Target Membership: AlRashidWidget only.
//

import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var player: QuranPlayer
    let onOpen: () -> Void

    var body: some View {
        if let surah = player.currentSurah {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button(action: onOpen) {
                        HStack(spacing: 12) {
                            Text(surah.arabic)
                                .font(.headline)
                                .foregroundStyle(QuranTheme.deepGreen)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .frame(width: 42, height: 42)
                                .background(
                                    LinearGradient(colors: [QuranTheme.lightGold, QuranTheme.gold],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(surah.english)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(player.currentReciter?.name ?? "")
                                    .font(.caption)
                                    .foregroundStyle(QuranTheme.mutedOnGreen)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 4)

                    transportButton("backward.end.fill") { player.previous() }
                    transportButton(player.isPlaying ? "pause.fill" : "play.fill") {
                        player.togglePlayPause()
                    }
                    transportButton("forward.end.fill") { player.next() }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.22))
                        Capsule().fill(QuranTheme.lightGold)
                            .frame(width: proxy.size.width * progressFraction)
                    }
                }
                .frame(height: 3)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
            .background(QuranTheme.deepGreen,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        }
    }

    private var progressFraction: CGFloat {
        guard player.duration > 0 else { return 0 }
        return CGFloat(min(1, max(0, player.currentTime / player.duration)))
    }

    private func transportButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
    }
}
