import SwiftUI
import UIKit

/// Home: Cara's station card, what you've been playing, your favourites and your playlists.
struct HomeView: View {
    @Environment(Engine.self) private var engine
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @EnvironmentObject private var cfg: Config

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
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
                    VStack(alignment: .leading, spacing: 12) {
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
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "On Repeat", subtitle: "Your most played lately")
                        SongGrid(tracks: library.topTracks)
                    }
                }
                if !library.topArtists.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
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
                    VStack(alignment: .leading, spacing: 12) {
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
            .padding(.top, 6)
        }
        .chromeInset()
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AvatarButton()
            }
        }
        .refreshable {
            await library.loadAll(force: true)
            engine.poke()
        }
    }

    private var likedCard: some View {
        NavigationLink(value: Route.liked) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    LinearGradient(colors: [Theme.accent, Theme.caraPurple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
                .frame(width: 160, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Liked Songs").font(.system(size: 14, weight: .medium)).foregroundStyle(Color.primary)
                    Text("\(library.likedTotal) songs").font(.system(size: 14)).foregroundStyle(Color.secondary)
                }
            }
            .frame(width: 160, alignment: .leading)
        }
        .buttonStyle(PressableStyle())
    }
}

/// Top-right picture of you; opens Settings.
struct AvatarButton: View {
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        Button {
            Haptics.tap()
            router.showSettings = true
        } label: {
            if let img = library.me?.image, !img.isEmpty {
                Artwork(img, px: 120, circle: true)
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.accent)
            }
        }
        .accessibilityLabel("Settings")
    }
}

/// Songs in a sideways-swiping grid of four rows, like Apple Music's "Top Songs".
struct SongGrid: View {
    let tracks: [Track]
    @Environment(Engine.self) private var engine

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: Array(repeating: GridItem(.fixed(58), spacing: 4), count: 4), spacing: 18) {
                ForEach(Array(tracks.enumerated()), id: \.offset) { i, t in
                    GridSongRow(track: t) {
                        Task { await engine.playTracks(tracks, startAt: i) }
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
            Artwork(track.artMid, px: 150, corner: 5)
                .frame(width: 48, height: 48)
                .overlay {
                    if current {
                        RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.black.opacity(0.45))
                        EqualizerBars(playing: engine.now.isPlaying, color: .white)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 15))
                    .foregroundStyle(current ? Theme.accent : Color.primary)
                    .lineLimit(1)
                Text(track.artistLine)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Menu {
                TrackMenuItems(track: track)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary)
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

/// Cara's station card at the top of Home.
struct CaraHeroCard: View {
    @Environment(Engine.self) private var engine
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NON STOP POP")
                        .font(.system(size: 12, weight: .heavy))
                        .tracking(2)
                        .foregroundStyle(Color.white.opacity(0.8))
                    Text("Cara")
                        .font(.system(size: 36, weight: .heavy))
                        .foregroundStyle(Color.white)
                    HStack(spacing: 8) {
                        if engine.running { LiveBadge(text: engine.speaking ? "ON AIR" : "LIVE") }
                        Text(engine.statusLine)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.9))
                    }
                }
                Spacer()
                StationLogo(active: engine.running)
                    .frame(width: 64, height: 46)
                    .padding(.top, 6)
            }
            if !engine.line.isEmpty {
                Text("\u{201C}" + engine.line.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression) + "\u{201D}")
                    .font(.system(size: 15, weight: .medium))
                    .italic()
                    .foregroundStyle(Color.white.opacity(0.88))
                    .lineLimit(3)
            } else {
                Text("Your own radio host. She talks between your songs about your town, the news, the music, and you.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            HStack(spacing: 10) {
                Button {
                    Haptics.firm()
                    if engine.running { engine.stop() } else { engine.start() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: engine.running ? "stop.fill" : "dot.radiowaves.left.and.right")
                        Text(engine.running ? "End Show" : "Go Live")
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(engine.running ? Color.white : Color.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(engine.running ? Color.white.opacity(0.2) : Color.white, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                Button {
                    Haptics.tap()
                    router.select(.cara)
                } label: {
                    Text("Her Settings")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.16), in: Capsule())
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.caraGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Theme.accent.opacity(0.25), radius: 18, y: 8)
        .padding(.horizontal, Theme.hPad)
        .animation(.easeInOut(duration: 0.3), value: engine.running)
    }
}

/// Shown when Spotify isn't connected yet.
struct ConnectCard: View {
    @Environment(Engine.self) private var engine
    @Environment(Router.self) private var router
    @EnvironmentObject private var cfg: Config

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect Spotify").font(.title3.weight(.bold))
            Text(cfg.clientID.isEmpty
                 ? "Add your Spotify Client ID in Settings, then connect. Your music plays through the Spotify app."
                 : "Log in once and your library, playlists and the player all show up here.")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
            Button {
                Haptics.tap()
                if cfg.clientID.isEmpty { router.showSettings = true }
                else { Task { await engine.connect(forceLogin: true) } }
            } label: {
                Text(cfg.clientID.isEmpty ? "Open Settings" : "Connect Spotify")
                    .font(.headline)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, Theme.hPad)
    }
}

/// Older logins don't include the library permissions; one quick reconnect fixes that.
struct ReconnectBanner: View {
    @Environment(Engine.self) private var engine

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Unlock your library").font(.subheadline.weight(.semibold))
                Text("Reconnect Spotify once so Cara DJ can show your playlists, albums and liked songs.")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
            Spacer(minLength: 4)
            Button("Reconnect") {
                Haptics.tap()
                Task { await engine.connect(forceLogin: true) }
            }
            .font(.subheadline.weight(.bold))
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, Theme.hPad)
    }
}

/// Logged in, but Spotify won't play along (wrong account, expired login, no internet).
struct ProblemBanner: View {
    @Environment(Engine.self) private var engine
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.orange)
                Text("Spotify isn't connecting").font(.subheadline.weight(.semibold))
            }
            Text(engine.problem)
                .font(.footnote)
                .foregroundStyle(Color.secondary)
            HStack(spacing: 10) {
                Button("Try Again") {
                    Haptics.tap()
                    Task { await engine.connect() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                Button("Reconnect") {
                    Haptics.tap()
                    Task { await engine.connect(forceLogin: true) }
                }
                .buttonStyle(.bordered)
                Button("Settings") { router.showSettings = true }
                    .buttonStyle(.bordered)
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                .font(.footnote)
            Spacer(minLength: 4)
            Button("Open") {
                if let u = URL(string: "spotify:") { UIApplication.shared.open(u) }
            }
            .font(.subheadline.weight(.bold))
            .buttonStyle(.bordered)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, Theme.hPad)
    }
}
