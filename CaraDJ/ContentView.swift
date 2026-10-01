import SwiftUI
import UIKit

/// The whole app: four tabs, the floating mini player and tab bar, and the big player that slides up.
struct ContentView: View {
    @Environment(Engine.self) private var engine
    @Environment(Router.self) private var router
    @Environment(Library.self) private var library
    @Environment(Toasts.self) private var toasts
    @EnvironmentObject private var cfg: Config
    @Environment(\.scenePhase) private var phase
    @State private var opened: Set<AppTab> = [.home]
    /// The app rises into view once the welcome setup is put away.
    @State private var revealed = Config.shared.welcomed

    var body: some View {
        @Bindable var router = router
        ZStack(alignment: .bottom) {
            ZStack {
                tabPage(.home)
                tabPage(.cara)
                tabPage(.library)
                tabPage(.search)
            }
            BottomChrome()
                .ignoresSafeArea(.keyboard, edges: .bottom)
            if router.showPlayer {
                NowPlayingView()
                    .transition(.move(edge: .bottom))
                    .zIndex(2)
            }
        }
        .scaleEffect(revealed ? 1 : 0.94)
        .opacity(revealed ? 1 : 0)
        .background(Theme.ink.ignoresSafeArea())
        .overlay { ToastOverlay() }
        .overlay {
            if !cfg.welcomed {
                WelcomeView()
                    .transition(.opacity)
            }
        }
        .tint(Color.white)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $router.showSettings) {
            SettingsView()
                .environment(engine)
                .environment(router)
                .environment(library)
                .environment(toasts)
                .environmentObject(cfg)
                .preferredColorScheme(.dark)
        }
        .sheet(item: $router.addToPlaylist) { t in
            AddToPlaylistSheet(track: t)
                .environment(engine)
                .environment(router)
                .environment(library)
                .environment(toasts)
                .presentationDetents([.medium, .large])
                .preferredColorScheme(.dark)
        }
        .onChange(of: cfg.welcomed) { _, done in
            if done {
                withAnimation(.spring(response: 1.1, dampingFraction: 0.9)) { revealed = true }
            } else {
                revealed = false
            }
        }
        .onChange(of: router.tab) { _, t in _ = opened.insert(t) }
        .onChange(of: phase) { _, p in
            engine.foreground = (p == .active)
            if p == .active {
                engine.poke()
                Task { await library.loadAll() }
            }
        }
        // every page takes its colour from the cover of what's playing
        .task(id: engine.displayItem?.artMid ?? "") {
            await Ambience.shared.follow(engine.displayItem?.artMid ?? "")
        }
        .task {
            engine.boot()
            if let why = CrashLog.lastCrash() {
                engine.addLog("Cara DJ closed unexpectedly last time: " + why)
                Toasts.shared.show("Cara DJ closed unexpectedly last time. The reason is in Cara, Activity", "exclamationmark.triangle.fill")
            }
            if Spotify.shared.isLoggedIn {
                await engine.connect()
            }
        }
    }

    @ViewBuilder
    private func tabPage(_ t: AppTab) -> some View {
        let shown = router.tab == t
        if opened.contains(t) || shown {
            TabStack(tab: t)
                .opacity(shown ? 1 : 0)
                .allowsHitTesting(shown)
                .accessibilityHidden(!shown)
        }
    }
}

/// One tab's pages, with its own back-and-forth history.
struct TabStack: View {
    let tab: AppTab
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        switch tab {
        case .home:
            NavigationStack(path: $router.home) { HomeView().routes() }
        case .cara:
            NavigationStack(path: $router.cara) { CaraView().routes() }
        case .library:
            NavigationStack(path: $router.library) { LibraryView().routes() }
        case .search:
            NavigationStack(path: $router.search) { SearchView().routes() }
        }
    }
}

extension View {
    /// Lets any page open albums, artists, playlists and the rest.
    func routes() -> some View {
        self.navigationDestination(for: Route.self) { r in
            RouteView(route: r)
        }
    }
}

struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .album(let a): AlbumView(seed: a)
        case .artist(let a): ArtistView(seed: a)
        case .playlist(let p): PlaylistView(seed: p)
        case .liked: LikedSongsView()
        case .playlists: PlaylistsListView()
        case .albums: AlbumsGridView()
        case .artists: ArtistsListView()
        case .genre(let g): GenreView(genre: g)
        }
    }
}

// MARK: - The floating mini player + tab bar
struct BottomChrome: View {
    @Environment(Engine.self) private var engine

    var body: some View {
        VStack(spacing: 8) {
            if engine.displayItem != nil || engine.speaking {
                MiniPlayer()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            TabBar()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
        .background(alignment: .bottom) {
            // the page softly dissolves under the floating bars
            LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                .frame(height: 180)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
        .animation(Theme.spring, value: engine.displayItem == nil)
    }
}

struct TabBar: View {
    @Environment(Router.self) private var router
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            item(.home, "Home", "house.fill")
            item(.cara, "Cara", "dot.radiowaves.left.and.right")
            item(.library, "Library", "square.stack.fill")
            item(.search, "Search", "magnifyingglass")
        }
        .padding(5)
        .frame(height: Theme.tabBarHeight)
        .frosted(Theme.tabBarHeight / 2)
        .shadow(color: Color.black.opacity(0.35), radius: 18, y: 8)
        .animation(Theme.spring, value: router.tab)
    }

    private func item(_ t: AppTab, _ title: String, _ icon: String) -> some View {
        let on = router.tab == t
        return Button {
            if !on { Haptics.soft() }
            withAnimation(.easeInOut(duration: 0.18)) { router.select(t) }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: on ? .semibold : .regular))
                    .frame(height: 22)
                Text(title).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(on ? Color.white : Theme.text2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if on {
                    Capsule()
                        .fill(Color.white.opacity(0.14))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.6))
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct MiniPlayer: View {
    @Environment(Engine.self) private var engine
    @Environment(Router.self) private var router

    var body: some View {
        let item = engine.displayItem
        let cara = Silence.isSilence(item?.uri ?? "")
        HStack(spacing: 12) {
            Artwork(item?.artMid, px: 150, corner: 11)
                .frame(width: 44, height: 44)
                .shadow(color: Color.black.opacity(0.3), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 1) {
                if engine.speaking {
                    HStack(spacing: 6) {
                        EqualizerBars(playing: true, color: .white, height: 10)
                        Text("Cara is on the mic").font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    }
                    Text(cara ? engine.stationFull : (item?.title ?? engine.stationName))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text2)
                        .lineLimit(1)
                } else {
                    Text(item?.title ?? "Not Playing").font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    if let a = item?.artistLine, !a.isEmpty {
                        Text(a).font(.system(size: 13)).foregroundStyle(Theme.text2).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 6)
            playButton
            Button {
                Haptics.tap()
                Task { await engine.next() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 18))
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.85))
            .accessibilityLabel("Next")
        }
        .foregroundStyle(Color.white)
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .frame(height: Theme.miniHeight)
        .frosted(22)
        .shadow(color: Color.black.opacity(0.3), radius: 16, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture { router.openPlayer() }
        .gesture(
            DragGesture(minimumDistance: 12).onEnded { v in
                if v.translation.height < -24 { router.openPlayer() }
                else if v.translation.width < -60 { Haptics.tap(); Task { await engine.next() } }
                else if v.translation.width > 60 { Haptics.tap(); Task { await engine.previous() } }
            }
        )
    }

    /// Play / pause, ringed by how far into the song you are.
    private var playButton: some View {
        Button {
            Haptics.tap()
            Task { await engine.togglePlay() }
        } label: {
            ZStack {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    ring(progressFraction())
                }
                Image(systemName: engine.now.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                    .offset(x: engine.now.isPlaying ? 0 : 1)
            }
            .frame(width: 36, height: 36)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.85))
        .accessibilityLabel(engine.now.isPlaying ? "Pause" : "Play")
    }

    private func ring(_ f: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.18), lineWidth: 2)
            Circle()
                .trim(from: 0, to: f)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }

    private func progressFraction() -> CGFloat {
        if engine.pendingItem != nil { return 0 }
        let dur: Double = Double(max(engine.now.durationMs, 1))
        let cur: Double = Double(engine.now.currentProgressMs)
        return CGFloat(min(max(cur / dur, 0), 1))
    }
}
