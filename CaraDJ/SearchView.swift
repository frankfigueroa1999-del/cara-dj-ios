import SwiftUI
import Observation

enum SearchScope: String, CaseIterable, Identifiable {
    case all = "Top Results"
    case songs = "Songs"
    case artists = "Artists"
    case albums = "Albums"
    case playlists = "Playlists"
    var id: String { rawValue }
    var apiType: String {
        switch self {
        case .all: return "track,artist,album,playlist"
        case .songs: return "track"
        case .artists: return "artist"
        case .albums: return "album"
        case .playlists: return "playlist"
        }
    }
}

@MainActor
@Observable
final class SearchModel {
    var text = ""
    var scope: SearchScope = .all
    var results = SearchResults()
    var loading = false
    var searchedFor = ""
    private var offset = 0
    private var reachedEnd = false

    func run() async {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            results = SearchResults()
            searchedFor = ""
            return
        }
        loading = true
        offset = 0
        reachedEnd = false
        let r = await Spotify.shared.search(q, types: scope.apiType.components(separatedBy: ","))
        if q == text.trimmingCharacters(in: .whitespacesAndNewlines) {
            results = r ?? SearchResults()
            searchedFor = q
        }
        loading = false
    }

    /// Spotify only sends 10 results at a time now, so lists grow as you scroll.
    func more() async {
        guard scope != .all, !loading, !reachedEnd, !searchedFor.isEmpty else { return }
        loading = true
        defer { loading = false }
        offset += 10
        guard offset < 1000, let r = await Spotify.shared.search(searchedFor, types: [scope.apiType], offset: offset) else {
            reachedEnd = true
            return
        }
        switch scope {
        case .songs:
            if r.tracks.isEmpty { reachedEnd = true }
            results.tracks += r.tracks
        case .artists:
            if r.artists.isEmpty { reachedEnd = true }
            results.artists += r.artists
        case .albums:
            if r.albums.isEmpty { reachedEnd = true }
            results.albums += r.albums
        case .playlists:
            if r.playlists.isEmpty { reachedEnd = true }
            results.playlists += r.playlists
        case .all:
            break
        }
    }

    func remember(_ term: String) {
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var list = Config.shared.recentSearches.filter { $0.lowercased() != t.lowercased() }
        list.insert(t, at: 0)
        Config.shared.recentSearches = Array(list.prefix(12))
    }
}

/// Search: browse tiles when empty, results as you type.
struct SearchView: View {
    @State private var model = SearchModel()
    @Environment(Engine.self) private var engine
    @Environment(Router.self) private var router
    @EnvironmentObject private var cfg: Config

    var body: some View {
        ScrollView {
            if model.text.trimmingCharacters(in: .whitespaces).isEmpty {
                browse
            } else {
                resultsView
            }
        }
        .chromeInset()
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("Search")
        .searchable(text: $model.text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Artists, Songs, Albums and More")
        .onSubmit(of: .search) { model.remember(model.text) }
        .task(id: model.text + "|" + model.scope.rawValue) {
            try? await Task.sleep(nanoseconds: 320_000_000)
            if Task.isCancelled { return }
            await model.run()
        }
    }

    // MARK: before you type
    private var browse: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !cfg.recentSearches.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Recently Searched").font(.title3.weight(.bold))
                        Spacer()
                        Button("Clear") { cfg.recentSearches = [] }
                            .font(.subheadline)
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.horizontal, Theme.hPad)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(cfg.recentSearches, id: \.self) { term in
                                Button {
                                    model.text = term
                                } label: {
                                    Text(term)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Color.primary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(Color(.tertiarySystemFill), in: Capsule())
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                        .padding(.horizontal, Theme.hPad)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Browse Categories").font(.title3.weight(.bold)).padding(.horizontal, Theme.hPad)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(Genre.all) { g in
                        NavigationLink(value: Route.genre(g)) {
                            GenreTile(genre: g)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, Theme.hPad)
            }
        }
        .padding(.top, 8)
    }

    // MARK: results
    private var resultsView: some View {
        VStack(alignment: .leading, spacing: 18) {
            scopeChips
            if model.loading && model.results.isEmpty {
                LoadingRow()
            } else if model.results.isEmpty && !model.searchedFor.isEmpty {
                EmptyNote(symbol: "magnifyingglass", title: "No Results", message: "Try a different spelling, or search for an artist or album.")
            } else {
                switch model.scope {
                case .all: topResults
                case .songs: songList
                case .artists: artistList
                case .albums: albumList
                case .playlists: playlistList
                }
            }
        }
        .padding(.top, 4)
    }

    private var scopeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchScope.allCases) { s in
                    let on = model.scope == s
                    Button {
                        Haptics.tap()
                        model.scope = s
                    } label: {
                        Text(s.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(on ? Theme.accent : Color(.tertiarySystemFill), in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, Theme.hPad)
        }
    }

    @ViewBuilder
    private var topResults: some View {
        let r = model.results
        if let best = bestMatch {
            bestCard(best)
        }
        if !r.tracks.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Songs") { model.scope = .songs }
                LazyVStack(spacing: 0) {
                    ForEach(Array(r.tracks.prefix(5).enumerated()), id: \.offset) { _, t in
                        TrackRow(track: t) { play(t) }
                    }
                }
            }
        }
        if !r.artists.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Artists") { model.scope = .artists }
                Carousel(spacing: 16) {
                    ForEach(r.artists) { a in
                        NavigationLink(value: Route.artist(a)) { ArtistCircle(artist: a, size: 110) }
                            .buttonStyle(PressableStyle())
                            .simultaneousGesture(TapGesture().onEnded { model.remember(model.text) })
                    }
                }
            }
        }
        if !r.albums.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Albums") { model.scope = .albums }
                Carousel {
                    ForEach(r.albums) { a in
                        NavigationLink(value: Route.album(a)) { AlbumCard(album: a, width: 150, subtitle: a.artist) }
                            .buttonStyle(PressableStyle())
                            .simultaneousGesture(TapGesture().onEnded { model.remember(model.text) })
                    }
                }
            }
        }
        if !r.playlists.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Playlists") { model.scope = .playlists }
                Carousel {
                    ForEach(r.playlists) { p in
                        NavigationLink(value: Route.playlist(p)) { PlaylistCard(playlist: p, width: 150) }
                            .buttonStyle(PressableStyle())
                            .simultaneousGesture(TapGesture().onEnded { model.remember(model.text) })
                    }
                }
            }
        }
    }

    private enum Best {
        case artist(Artist)
        case track(Track)
        case album(Album)
    }

    /// The artist whose name matches what you typed, otherwise the first song.
    private var bestMatch: Best? {
        let q = model.searchedFor.lowercased()
        if let a = model.results.artists.first(where: { $0.name.lowercased() == q }) { return .artist(a) }
        if let al = model.results.albums.first(where: { $0.name.lowercased() == q }) { return .album(al) }
        if let t = model.results.tracks.first { return .track(t) }
        if let a = model.results.artists.first { return .artist(a) }
        return nil
    }

    @ViewBuilder
    private func bestCard(_ b: Best) -> some View {
        switch b {
        case .artist(let a):
            NavigationLink(value: Route.artist(a)) {
                bestBody(art: a.imageMid, circle: true, title: a.name, kind: "Artist")
            }
            .buttonStyle(PressableStyle(scale: 0.98))
            .simultaneousGesture(TapGesture().onEnded { model.remember(model.text) })
        case .album(let al):
            NavigationLink(value: Route.album(al)) {
                bestBody(art: al.artMid, circle: false, title: al.name, kind: "Album · " + al.artist)
            }
            .buttonStyle(PressableStyle(scale: 0.98))
            .simultaneousGesture(TapGesture().onEnded { model.remember(model.text) })
        case .track(let t):
            Button {
                play(t)
            } label: {
                bestBody(art: t.artMid, circle: false, title: t.title, kind: "Song · " + t.artistLine)
            }
            .buttonStyle(PressableStyle(scale: 0.98))
        }
    }

    private func bestBody(art: String, circle: Bool, title: String, kind: String) -> some View {
        HStack(spacing: 16) {
            Artwork(art, px: 300, corner: 8, circle: circle)
                .frame(width: 92, height: 92)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.weight(.bold)).foregroundStyle(Color.primary).lineLimit(2)
                Text(kind).font(.subheadline).foregroundStyle(Color.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "play.circle.fill")
                .font(.system(size: 38))
                .foregroundStyle(Theme.accent)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, Theme.hPad)
    }

    private var songList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(model.results.tracks.enumerated()), id: \.offset) { i, t in
                TrackRow(track: t) { play(t) }
                    .onAppear { if i == model.results.tracks.count - 1 { Task { await model.more() } } }
            }
            if model.loading { LoadingRow() }
        }
    }

    private var artistList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(model.results.artists.enumerated()), id: \.offset) { i, a in
                NavigationLink(value: Route.artist(a)) {
                    MediaRow(title: a.name, subtitle: "Artist", art: a.imageMid, circle: true)
                }
                .buttonStyle(.plain)
                .onAppear { if i == model.results.artists.count - 1 { Task { await model.more() } } }
            }
            if model.loading { LoadingRow() }
        }
    }

    private var albumList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(model.results.albums.enumerated()), id: \.offset) { i, a in
                NavigationLink(value: Route.album(a)) {
                    MediaRow(title: a.name, subtitle: a.typeLabel + " · " + a.artist + (a.year.isEmpty ? "" : " · " + a.year), art: a.artMid)
                }
                .buttonStyle(.plain)
                .onAppear { if i == model.results.albums.count - 1 { Task { await model.more() } } }
            }
            if model.loading { LoadingRow() }
        }
    }

    private var playlistList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(model.results.playlists.enumerated()), id: \.offset) { i, p in
                NavigationLink(value: Route.playlist(p)) {
                    MediaRow(title: p.name, subtitle: "Playlist · " + p.owner, art: p.imageMid)
                }
                .buttonStyle(.plain)
                .onAppear { if i == model.results.playlists.count - 1 { Task { await model.more() } } }
            }
            if model.loading { LoadingRow() }
        }
    }

    private func play(_ t: Track) {
        model.remember(model.text)
        Task { await engine.playTracks([t], startAt: 0) }
    }
}

struct GenreTile: View {
    let genre: Genre

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.tile(genre.hue)
            Image(systemName: genre.symbol)
                .font(.system(size: 46, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.28))
                .rotationEffect(.degrees(18))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(10)
            Text(genre.title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(12)
        }
        .frame(height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// A browse category: songs and playlists that fit it.
struct GenreView: View {
    let genre: Genre
    @State private var tracks: [Track] = []
    @State private var playlists: [Playlist] = []
    @State private var loaded = false
    @Environment(Engine.self) private var engine

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ZStack(alignment: .bottomLeading) {
                    Color.tile(genre.hue)
                    Image(systemName: genre.symbol)
                        .font(.system(size: 90, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.22))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .padding(20)
                    Text(genre.title)
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .padding(20)
                }
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, Theme.hPad)

                if !tracks.isEmpty {
                    PlayShuffleButtons(play: {
                        Task { await engine.playTracks(tracks, startAt: 0) }
                    }, shuffle: {
                        Task { await engine.playTracks(tracks, startAt: 0, shuffle: true) }
                    })
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(title: "Songs")
                        LazyVStack(spacing: 0) {
                            ForEach(Array(tracks.enumerated()), id: \.offset) { i, t in
                                TrackRow(track: t) { Task { await engine.playTracks(tracks, startAt: i) } }
                            }
                        }
                    }
                }
                if !playlists.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Playlists")
                        Carousel {
                            ForEach(playlists) { p in
                                NavigationLink(value: Route.playlist(p)) { PlaylistCard(playlist: p, width: 150) }
                                    .buttonStyle(PressableStyle())
                            }
                        }
                    }
                }
                if !loaded { LoadingRow() }
                if loaded && tracks.isEmpty && playlists.isEmpty {
                    EmptyNote(symbol: "music.note", title: "Nothing here yet", message: "Spotify didn't send anything back for this one. Try again in a bit.")
                }
            }
            .padding(.top, 8)
        }
        .chromeInset()
        .navigationTitle(genre.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if loaded { return }
            async let a = Spotify.shared.search(genre.trackQuery, types: ["track"])
            async let b = Spotify.shared.search(genre.playlistQuery, types: ["playlist"])
            let (ra, rb) = await (a, b)
            tracks = ra?.tracks ?? []
            if tracks.count >= 10, let more = await Spotify.shared.search(genre.trackQuery, types: ["track"], offset: 10) {
                tracks += more.tracks
            }
            playlists = rb?.playlists ?? []
            loaded = true
        }
    }
}
