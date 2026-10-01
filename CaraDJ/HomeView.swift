import SwiftUI
import UIKit

/// Home: a greeting, Cara's station card, what you've been playing, your favourites and your playlists.
struct HomeView: View {
    @Environment(Engine.self) private var engine
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @EnvironmentObject private var cfg: Config
    @State private var scrolled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header
                if !engine.loggedIn {
                    ConnectCard()
                } else if !engine.problem.isEmpty && !engine.connected {
                    ProblemBanner()
                } else if library.needsReconnect {
                    ReconnectBanner()
                }
                if engine.noDevice {
                    OpenSpotifyBanner()
                }
                CaraHeroCard()
                if !library.recentAlbums.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Recently Played")
                        Carousel {
                            ForEach(library.recentAlbums) { a in
                                NavigationLink(value: Route.album(a)) {
                                    AlbumCard(album: a)
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }
                }
                if !library.topTracks.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "On Repeat", subtitle: "Your most played lately")
                        SongGrid(tracks: library.topTracks, station: "On Repeat")
                    }
                }
                if !library.topArtists.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Artists You Love")
                        Carousel(spacing: 16) {
                            ForEach(library.topArtists) { a in
                                NavigationLink(value: Route.artist(a)) {
                                    ArtistCircle(artist: a)
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }
                }
                if !library.playlists.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Your Playlists") { router.open(.playlists) }
                        Carousel {
                            likedCard
                            ForEach(library.playlists.prefix(20)) { p in
                                NavigationLink(value: Route.playlist(p)) {
                                    PlaylistCard(playlist: p)
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }
                }
                if engine.loggedIn && !library.loaded && library.playlists.isEmpty {
                    LoadingRow()
                }
            }
            .padding(.top, 4)
        }
        .chromeInset()
        .frostedPage()
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            // frosts the status bar once the page scrolls under it
            Color.clear
                .frame(height: 0)
                .background(Material.ultraThin.opacity(scrolled ? 1 : 0), ignoresSafeAreaEdges: .top)
                .animation(.easeInOut(duration: 0.2), value: scrolled)
        }
        .refreshable {
            await library.loadAll(force: true)
            engine.poke()
        }
    }

    // MARK: the greeting at the top
    private var header: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(dateLine)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Theme.text2)
                Text(greeting)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            AvatarButton(size: 38)
                .padding(.bottom, 2)
        }
        .padding(.horizontal, Theme.hPad)
        .padding(.top, 10)
        .background(
            GeometryReader { g in
                Color.clear
                    .onChange(of: g.frame(in: .global).minY) { _, y in
                        let past = y < 24
                        if past != scrolled { scrolled = past }
                    }
            }
        )
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let part: String
        if h < 5 { part = "Good night" }
        else if h < 12 { part = "Good morning" }
        else if h < 17 { part = "Good afternoon" }
        else { part = "Good evening" }
        if let n = library.me?.name.split(separator: " ").first.map(String.init), !n.isEmpty {
            return part + ", " + n
        }
        return part
    }

    private var dateLine: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date()).uppercased()
    }

    private var likedCard: some View {
        NavigationLink(value: Route.liked) {
            VStack(alignment: .leading, spacing: 6) {
                LikedArt(size: 160, corner: 12)
                    .shadow(color: Color.black.opacity(0.28), radius: 10, y: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Liked Songs").font(.system(size: 14, weight: .medium)).foregroundStyle(Color.white)
                    Text("\(library.likedTotal) songs").font(.system(size: 14)).foregroundStyle(Theme.text2)
                }
            }
            .frame(width: 160, alignment: .leading)
        }
        .buttonStyle(PressableStyle())
    }
}

/// The Liked Songs "cover": a glowing heart on Cara's colours.
struct LikedArt: View {
    var size: CGFloat
    var corner: CGFloat = 12

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.accent, Theme.caraPurple, Theme.caraNight], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color.white.opacity(0.25), .clear], center: .center, startRadius: 0, endRadius: size * 0.5)
            Image(systemName: "heart.fill")
                .font(.system(size: size * 0.3, weight: .semibold))
                .foregroundStyle(Color.white)
                .shadow(color: Color.black.opacity(0.2), radius: 8, y: 4)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
    }
}

/// Your picture; opens Settings.
struct AvatarButton: View {
    var size: CGFloat = 32
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        Button {
            Haptics.tap()
            router.showSettings = true
        } label: {
            if let img = library.me?.image, !img.isEmpty {
                Artwork(img, px: 120, circle: true)
                    .frame(width: size, height: size)
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.7))
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(Color.white)
                    .frame(width: size, height: size)
                    .glass(size / 2, tint: 0.1)
            }
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel("Settings")
    }
}

/// Songs in a sideways-swiping grid of four rows, like Apple Music's "Top Songs".
struct SongGrid: View {
    let tracks: [Track]
    /// What the station's called when these play (there's no playlist behind them).
    var station: String? = nil
    @Environment(Engine.self) private var engine

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: Array(repeating: GridItem(.fixed(58), spacing: 4), count: 4), spacing: 18) {
                ForEach(Array(tracks.enumerated()), id: \.offset) { i, t in
                    GridSongRow(track: t) {
                        Task { await engine.playTracks(tracks, startAt: i, name: station) }
                    }
                    .containerRelativeFrame(.horizontal) { w, _ in w * 0.86 }
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, Theme.hPad, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .frame(height: 58 * 4 + 4 * 3)
    }
}

struct GridSongRow: View {
    let track: Track
    var action: () -> Void
    @Environment(Engine.self) private var engine

    var body: some View {
        let current = !track.uri.isEmpty && engine.displayItem?.uri == track.uri
        HStack(spacing: 12) {
            Artwork(track.artMid, px: 150, corner: 8)
                .frame(width: 48, height: 48)
                .overlay {
                    if current {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.45))
                        EqualizerBars(playing: engine.now.isPlaying, color: .white)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 15, weight: current ? .semibold : .regular))
                    .foregroundStyle(current ? Theme.accent : Color.white)
                    .lineLimit(1)
                Text(track.artistLine)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Menu {
                TrackMenuItems(track: track)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text2)
                    .frame(width: 30, height: 40)
                    .contentShape(Rectangle())
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.tap()
            action()
        }
        .contextMenu {
            TrackMenuItems(track: track)
        }
    }
}

/// Cara's station card on Home.
struct CaraHeroCard: View {
    @Environment(Engine.self) private var engine
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.caraGradient)
                    StationLogo(active: engine.running)
                        .frame(width: 32, height: 24)
                }
                .frame(width: 56, height: 56)
                .shadow(color: Theme.accent.opacity(0.35), radius: 12, y: 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.stationFull.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(Theme.text2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.3), value: engine.stationFull)
                    Text("Cara")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Color.white)
                    Text(engine.statusLine)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.text2)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if engine.running {
                    LiveBadge(text: engine.speaking ? "ON AIR" : "LIVE")
                        .transition(.scale.combined(with: .opacity))
                }
            }
            if !engine.line.isEmpty {
                Text("\u{201C}" + engine.line.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression) + "\u{201D}")
                    .font(.system(size: 15))
                    .italic()
                    .foregroundStyle(Color.white.opacity(0.86))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Your own radio host. She talks between your songs about your town, the news, the music, and you.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button {
                    Haptics.firm()
                    if engine.running { engine.stop() } else { engine.start() }
                } label: {
                    PillLabel(title: engine.running ? "End Show" : "Go Live",
                              icon: engine.running ? "stop.fill" : "dot.radiowaves.left.and.right",
                              primary: !engine.running, height: 44, fill: false)
                }
                .buttonStyle(PressableStyle())
                Button {
                    Haptics.tap()
                    router.select(.cara)
                } label: {
                    PillLabel(title: "Her Settings", primary: false, height: 44, fill: false)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // her colours, glowing faintly through the glass
            ZStack {
                RadialGradient(colors: [Theme.accent.opacity(engine.running ? 0.38 : 0.24), .clear], center: .topTrailing, startRadius: 0, endRadius: 280)
                RadialGradient(colors: [Theme.caraPurple.opacity(0.3), .clear], center: .bottomLeading, startRadius: 0, endRadius: 260)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .glass(26, tint: 0.06)
        .padding(.horizontal, Theme.hPad)
        .animation(.easeInOut(duration: 0.35), value: engine.running)
    }
}

/// Shown when Spotify isn't connected yet.
struct ConnectCard: View {
    @Environment(Engine.self) private var engine
    @Environment(Router.self) private var router
    @EnvironmentObject private var cfg: Config

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect Spotify").font(.system(size: 20, weight: .bold)).foregroundStyle(Color.white)
            Text(cfg.clientID.isEmpty
                 ? "Add your Spotify Client ID in Settings, then connect. Your music plays through the Spotify app."
                 : "Log in once and your library, playlists and the player all show up here.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.text2)
            Button {
                Haptics.tap()
                if cfg.clientID.isEmpty { router.showSettings = true }
                else { Task { await engine.connect(forceLogin: true) } }
            } label: {
                PillLabel(title: cfg.clientID.isEmpty ? "Open Settings" : "Connect Spotify", primary: true, height: 46)
            }
            .buttonStyle(PressableStyle())
            .padding(.top, 4)
        }
        .padding(20)
        .glass(24)
        .padding(.horizontal, Theme.hPad)
    }
}

/// Older logins don't include the library permissions; one quick reconnect fixes that.
struct ReconnectBanner: View {
    @Environment(Engine.self) private var engine

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 40, height: 40)
                .glass(20, tint: 0.1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Unlock your library").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.white)
                Text("Reconnect Spotify once so Cara DJ can show your playlists, albums and liked songs.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text2)
            }
            Spacer(minLength: 4)
            Button {
                Haptics.tap()
                Task { await engine.connect(forceLogin: true) }
            } label: {
                PillLabel(title: "Reconnect", primary: true, height: 34, fill: false)
            }
            .buttonStyle(PressableStyle())
        }
        .padding(16)
        .glass(22)
        .padding(.horizontal, Theme.hPad)
    }
}

/// Logged in, but Spotify won't play along (wrong account, expired login, no internet).
struct ProblemBanner: View {
    @Environment(Engine.self) private var engine
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.orange)
                Text("Spotify isn't connecting").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.white)
            }
            Text(engine.problem)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text2)
            HStack(spacing: 8) {
                Button {
                    Haptics.tap()
                    Task { await engine.connect() }
                } label: {
                    PillLabel(title: "Try Again", primary: true, height: 36, fill: false)
                }
                Button {
                    Haptics.tap()
                    Task { await engine.connect(forceLogin: true) }
                } label: {
                    PillLabel(title: "Reconnect", primary: false, height: 36, fill: false)
                }
                Button {
                    router.showSettings = true
                } label: {
                    PillLabel(title: "Settings", primary: false, height: 36, fill: false)
                }
            }
            .buttonStyle(PressableStyle())
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(22)
        .padding(.horizontal, Theme.hPad)
    }
}

/// Spotify had nowhere to play (the Spotify app is closed).
struct OpenSpotifyBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
            Text("Spotify isn't open on this iPhone. Open it once, then come back.")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.85))
            Spacer(minLength: 4)
            Button {
                if let u = URL(string: "spotify:") { UIApplication.shared.open(u) }
            } label: {
                PillLabel(title: "Open", primary: true, height: 34, fill: false)
            }
            .buttonStyle(PressableStyle())
        }
        .padding(16)
        .glass(22)
        .padding(.horizontal, Theme.hPad)
    }
}
