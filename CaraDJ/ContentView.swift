import SwiftUI
import UIKit

/// The whole app: four tabs, the mini player above the tab bar, and the big player that slides up.
struct ContentView: View {
    @Environment(Engine.self) private var engine
    @Environment(Router.self) private var router
    @Environment(Library.self) private var library
    @Environment(Toasts.self) private var toasts
    @EnvironmentObject private var cfg: Config
    @Environment(\.scenePhase) private var phase
    @State private var opened: Set<AppTab> = [.home]

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
        .overlay { ToastOverlay() }
        .tint(Theme.accent)
        .preferredColorScheme(router.showPlayer ? ColorScheme.dark : cfg.colorScheme)
        .sheet(isPresented: $router.showSettings) {
            SettingsView()
                .environment(engine)
                .environment(router)
                .environment(library)
                .environment(toasts)
                .environmentObject(cfg)
                .preferredColorScheme(cfg.colorScheme)
        }
        .sheet(item: $router.addToPlaylist) { t in
            AddToPlaylistSheet(track: t)
                .environment(engine)
                .environment(router)
                .environment(library)
                .environment(toasts)
                .presentationDetents([.medium, .large])
                .preferredColorScheme(cfg.colorScheme)
        }
        .fullScreenCover(isPresented: Binding(get: { !cfg.welcomed }, set: { v in if !v { cfg.welcomed = true } })) {
            WelcomeView()
                .environment(engine)
                .environment(library)
                .environment(toasts)
                .environmentObject(cfg)
        }
        .onChange(of: router.tab) { _, t in _ = opened.insert(t) }
        .onChange(of: phase) { _, p in
            engine.foreground = (p == .active)
            if p == .active {
                engine.poke()
                Task { await library.loadAll() }
            }
        }
        .task {
            engine.boot()
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

// MARK: - Mini player + tab bar
struct BottomChrome: View {
    @Environment(Engine.self) private var engine

    var body: some View {
        VStack(spacing: 6) {
            if engine.displayItem != nil || engine.speaking {
                MiniPlayer()
                    .padding(.horizontal, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            TabBar()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: engine.displayItem == nil)
    }
}

struct TabBar: View {
    @Environment(Router.self) private var router

    var body: some View {
        HStack(spacing: 0) {
            item(.home, "Home", "house.fill")
            item(.cara, "Cara", "dot.radiowaves.left.and.right")
            item(.library, "Library", "square.stack.fill")
            item(.search, "Search", "magnifyingglass")
        }
        .padding(.top, 7)
        .frame(height: Theme.tabBarHeight, alignment: .top)
        .background(alignment: .top) {
            Rectangle()
                .fill(.bar)
                .overlay(alignment: .top) { Divider() }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func item(_ t: AppTab, _ title: String, _ icon: String) -> some View {
        let on = router.tab == t
        return Button {
            if !on { Haptics.soft() }
            withAnimation(.easeInOut(duration: 0.15)) { router.select(t) }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .semibold))
                    .frame(height: 25)
                Text(title).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(on ? Theme.accent : Color(.secondaryLabel))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct MiniPlayer: View {
    @Environment(Engine.self) private var engine
    @Environment(Router.self) private var router

    var body: some View {
        let item = engine.displayItem
        HStack(spacing: 12) {
            Artwork(item?.artMid, px: 150, corner: 6)
                .frame(width: 42, height: 42)
                .shadow(color: Color.black.opacity(0.2), radius: 3, y: 1)
            VStack(alignment: .leading, spacing: 1) {
                if engine.speaking {
                    HStack(spacing: 6) {
                        EqualizerBars(playing: true, height: 11)
                        Text("Cara is on the mic").font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    }
                    Text(item?.title ?? "Non Stop Pop").font(.system(size: 13)).foregroundStyle(Color.secondary).lineLimit(1)
                } else {
                    Text(item?.title ?? "Not Playing").font(.system(size: 15, weight: .medium)).lineLimit(1)
                    if let a = item?.artistLine, !a.isEmpty {
                        Text(a).font(.system(size: 13)).foregroundStyle(Color.secondary).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 6)
            Button {
                Haptics.tap()
                Task { await engine.togglePlay() }
            } label: {
                Image(systemName: engine.now.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.85))
            Button {
                Haptics.tap()
                Task { await engine.next() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 20))
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.85))
        }
        .foregroundStyle(Color.primary)
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(height: Theme.miniHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .bottom) { progressLine }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.22), radius: 14, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { router.openPlayer() }
        .gesture(
            DragGesture(minimumDistance: 12).onEnded { v in
                if v.translation.height < -24 { router.openPlayer() }
                else if v.translation.width < -60 { Haptics.tap(); Task { await engine.next() } }
                else if v.translation.width > 60 { Haptics.tap(); Task { await engine.previous() } }
            }
        )
    }

    private var progressLine: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            GeometryReader { g in
                Rectangle()
                    .fill(Theme.accent)
                    .frame(width: g.size.width * progressFraction(), height: 2)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(height: 2)
        .padding(.horizontal, 12)
    }

    private func progressFraction() -> CGFloat {
        if engine.pendingItem != nil { return 0 }
        let dur: Double = Double(max(engine.now.durationMs, 1))
        let cur: Double = Double(engine.now.currentProgressMs)
        return CGFloat(min(max(cur / dur, 0), 1))
    }
}
