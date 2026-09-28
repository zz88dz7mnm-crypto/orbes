import SwiftUI

/// Página "Música" de la isla: portada, título, progreso y controles.
struct MusicPageView: View {
    @ObservedObject private var store = MusicStore.shared
    @Environment(\.orbexTheme) private var theme

    var body: some View {
        Group {
            if let t = store.track { player(t) } else { empty }
        }
        .frame(width: 270, height: 230)
        .background(Color.black)
        .onAppear { store.start() }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(theme.tertiaryText)
            Text("No suena nada 🎧")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.text)
            Text("Abrí Spotify o Música")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(theme.secondaryText)
        }
    }

    private func player(_ t: NowPlaying) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                artwork(t)
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.text).lineLimit(2)
                    Text(t.artist)
                        .font(.system(size: 11.5, design: .rounded))
                        .foregroundStyle(theme.secondaryText).lineLimit(1)
                    if !t.album.isEmpty {
                        Text(t.album)
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(theme.tertiaryText).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let pos = store.livePosition(at: ctx.date)
                VStack(spacing: 3) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.15))
                            Capsule().fill(theme.accent)
                                .frame(width: g.size.width * (t.duration > 0 ? min(pos / t.duration, 1) : 0))
                        }
                    }
                    .frame(height: 4)
                    HStack {
                        Text(Self.clock(pos))
                        Spacer()
                        Text(Self.clock(t.duration))
                    }
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.tertiaryText)
                }
            }

            HStack(spacing: 26) {
                control("backward.fill", size: 15) { store.previous() }
                control(store.isPlaying ? "pause.fill" : "play.fill", size: 22) { store.playPause() }
                control("forward.fill", size: 15) { store.next() }
            }

            HStack(spacing: 4) {
                Circle().fill(t.source == "Spotify" ? Color.green : Color.pink).frame(width: 5, height: 5)
                Text(t.source)
            }
            .font(.system(size: 9.5, weight: .medium, design: .rounded))
            .foregroundStyle(theme.tertiaryText)
        }
        .padding(14)
    }

    private func artwork(_ t: NowPlaying) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08))
            if let url = t.artworkURL {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "music.note").foregroundStyle(theme.tertiaryText)
                }
            } else {
                Image(systemName: "music.note").font(.system(size: 24)).foregroundStyle(theme.tertiaryText)
            }
        }
        .frame(width: 76, height: 76)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func control(_ symbol: String, size: CGFloat, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(theme.text)
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static func clock(_ s: Double) -> String {
        let v = Int(max(s, 0).rounded(.down))
        return String(format: "%d:%02d", v / 60, v % 60)
    }
}
