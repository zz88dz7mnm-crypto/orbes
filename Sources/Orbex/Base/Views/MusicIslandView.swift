import SwiftUI

/// Vista "Música" de la isla: tema actual (Spotify o Música), progreso y play/pausa/siguiente.
struct MusicIslandView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store = MusicStore.shared

    var body: some View {
        CardBackground(wash: nil) {
            Group {
                if let t = store.track { player(t) } else { empty }
            }
            .padding(.leading, IslandPalette.botGutter)
            .padding(.trailing, 14)
            .padding(.vertical, 10)
        }
        .onAppear { store.start() }
    }

    private var empty: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(IslandPalette.tertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text("No suena nada 🎧")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(IslandPalette.text)
                Text("Poné algo en Spotify o en Música y lo manejás desde acá.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(IslandPalette.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }

    private func player(_ t: NowPlaying) -> some View {
        HStack(spacing: 12) {
            artwork(t)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(IslandPalette.text)
                            .lineLimit(1)
                        Text(t.album.isEmpty ? t.artist : "\(t.artist) · \(t.album)")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(IslandPalette.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        Circle().fill(t.source == "Spotify" ? Color(hex: "#1DB954") : Color(hex: "#FA2D48"))
                            .frame(width: 5, height: 5)
                        Text(t.source)
                    }
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundColor(IslandPalette.tertiary)
                }

                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let pos = store.livePosition(at: ctx.date)
                    HStack(spacing: 6) {
                        Text(Self.clock(pos))
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.15))
                                Capsule().fill(IslandPalette.text.opacity(0.85))
                                    .frame(width: g.size.width * (t.duration > 0 ? min(pos / t.duration, 1) : 0))
                            }
                        }
                        .frame(height: 3)
                        Text(Self.clock(t.duration))
                    }
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundColor(IslandPalette.tertiary)
                }
                .frame(height: 12)

                HStack(spacing: 18) {
                    Spacer(minLength: 0)
                    control("backward.fill", size: 13, help: "Anterior") { store.previous() }
                    control(store.isPlaying ? "pause.fill" : "play.fill", size: 19,
                            help: store.isPlaying ? "Pausa" : "Reproducir") { store.playPause() }
                    control("forward.fill", size: 13, help: "Siguiente") { store.next() }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func artwork(_ t: NowPlaying) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08))
            if let url = t.artworkURL {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "music.note").foregroundColor(IslandPalette.tertiary)
                }
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 20))
                    .foregroundColor(IslandPalette.tertiary)
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func control(_ symbol: String, size: CGFloat, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(IslandPalette.text)
                .frame(width: 32, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private static func clock(_ s: Double) -> String {
        let v = Int(max(s, 0).rounded(.down))
        return String(format: "%d:%02d", v / 60, v % 60)
    }
}
