import SwiftUI
import Observation

// MARK: - Album page
@MainActor
@Observable
final class AlbumModel {
    var album: Album
    var tracks: [Track] = []
    var total = 0
    var copyright = ""
    var loaded = false
    var failed = false

    init(_ seed: Album) { album = seed }

    func load() async {
        if loaded { return }
        guard let r = await Spotify.shared.album(album.id) else { failed = true; return }
        album = r.album
        tracks = r.tracks
        total = r.total
        copyright = r.copyright
        while tracks.count < total {
            let more = await Spotify.shared.albumTracks(album, offset: tracks.count)
            if more.isEmpty { break }
            tracks += more
        }
        loaded = true
        await Library.shared.checkLiked(tracks)
        await Library.shared.checkSaved(album.uri)
    }

    var lengthMs: Int { tracks.reduce(0) { $0 + $1.durationMs } }
}

struct AlbumView: View {
    @State private var model: AlbumModel
    @Environment(Engine.self) private var engine
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router

    init(seed: Album) {
        _model = State(initialValue: AlbumModel(seed))
    }

    var body: some View {
        let a = model.album
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Artwork(a.art.isEmpty ? a.artMid : a.art, px: 800, corner: 10)
                        .frame(width: 250, height: 250)
                        .shadow(color: Color.black.opacity(0.3), radius: 18, y: 10)
                        .padding(.bottom, 10)
                    Text(a.name)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                    Button {
                        if !a.artistID.isEmpty {
                            var ar = Artist()
                            ar.id = a.artistID
                            ar.uri = "spotify:artist:" + a.artistID
                            ar.name = a.artist
                            router.open(.artist(ar))
                        }
                    } label: {
                        Text(a.artist).font(.title3).foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    Text([a.typeLabel, a.year].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                }
                .padding(.horizontal, 30)
                .padding(.top, 4)
                .padding(.bottom, 18)

                PlayShuffleButtons(play: {
                    Task { await engine.playContext(a.uri, preview: model.tracks.first) }
                }, shuffle: {
                    Task { await engine.playContext(a.uri, shuffle: true, count: max(model.tracks.count, a.totalTracks)) }
                })
                .padding(.bottom, 14)

                if !model.loaded && !model.failed { LoadingRow() }
                if model.failed {
                    EmptyNote(symbol: "wifi.exclamationmark", title: "Couldn't load this album", message: "Pull down to try again.")
                }
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.tracks.enumerated()), id: \.offset) { i, t in
                        TrackRow(track: t, number: t.trackNumber > 0 ? t.trackNumber : i + 1, showAlbumInMenu: false) {
                            Task { await engine.playContext(a.uri, startAt: t.uri, preview: t) }
                        }
                    }
                }
                if model.loaded {
                    VStack(alignment: .leading, spacing: 4) {
                        if a.release.count > 4 { Text(prettyDate(a.release)) }
                        Text("\(model.tracks.count) song\(model.tracks.count == 1 ? "" : "s"), \(formatLength(model.lengthMs))")
                        if !model.copyright.isEmpty { Text(model.copyright).lineLimit(2) }
                    }
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.hPad)
                    .padding(.top, 16)
                }
            }
        }
        .chromeInset()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                let saved = library.savedState[a.uri] ?? false
                Button {
                    Haptics.tap()
                    Task { await library.toggleSaved(uri: a.uri, album: a) }
                } label: {
                    Image(systemName: saved ? "checkmark.circle.fill" : "plus.circle")
                        .font(.system(size: 20))
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let u = a.shareURL {
                    ShareLink(item: u) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
        .refreshable {
            model.loaded = false
            await model.load()
        }
        .task { await model.load() }
    }
}

// MARK: - Artist page
@MainActor
@Observable
final class ArtistModel {
    var artist: Artist
    var top: [Track] = []
    var albums: [Album] = []
    var singles: [Album] = []
    var bio = ""
    var loaded = false

    init(_ seed: Artist) { artist = seed }

    func load() async {
        if loaded { return }
        let sp = Spotify.shared
        if let full = await sp.artist(artist.id) { artist = full }
        let a = artist
        async let topR = sp.artistTopTracks(a)
        async let albR = sp.artistAlbums(a.id, groups: "album")
        async let sngR = sp.artistAlbums(a.id, groups: "single")
        async let bioR = wikiLookup("\(a.name) musician band singer", must: [a.name])
        let (t, al, sg, b) = await (topR, albR, sngR, bioR)
        top = t
        albums = al
        singles = sg
        bio = b ?? ""
        loaded = true
        await Library.shared.checkSaved(artist.uri)
        await Library.shared.checkLiked(top)
    }
}

struct ArtistView: View {
    @State private var model: ArtistModel
    @State private var scrolledPast = false
    @State private var bioOpen = false
    @Environment(Engine.self) private var engine
    @Environment(Library.self) private var library

    init(seed: Artist) {
        _model = State(initialValue: ArtistModel(seed))
    }

    var body: some View {
        let a = model.artist
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header(a)
                if !model.top.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(title: "Top Songs")
                        LazyVStack(spacing: 0) {
                            ForEach(Array(model.top.prefix(10).enumerated()), id: \.offset) { i, t in
                                TrackRow(track: t) {
                                    Task { await engine.playTracks(model.top, startAt: i) }
                                }
                            }
                        }
                    }
                }
                if !model.albums.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Albums")
                        Carousel {
                            ForEach(model.albums) { al in
                                NavigationLink(value: Route.album(al)) { AlbumCard(album: al, subtitle: al.year) }
                                    .buttonStyle(PressableStyle())
                            }
                        }
                    }
                }
                if !model.singles.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Singles & EPs")
                        Carousel {
                            ForEach(model.singles) { al in
                                NavigationLink(value: Route.album(al)) { AlbumCard(album: al, width: 140, subtitle: al.year) }
                                    .buttonStyle(PressableStyle())
                            }
                        }
                    }
                }
                if !model.bio.isEmpty || !a.genres.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("About").font(.title2.weight(.bold))
                        if !a.genres.isEmpty {
                            Text(a.genres.prefix(4).map { $0.capitalized }.joined(separator: " · "))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        if !model.bio.isEmpty {
                            Text(model.bio)
                                .font(.body)
                                .foregroundStyle(Color.secondary)
                                .lineLimit(bioOpen ? nil : 5)
                            if model.bio.count > 260 {
                                Button(bioOpen ? "Less" : "More") {
                                    withAnimation(.easeInOut(duration: 0.25)) { bioOpen.toggle() }
                                }
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, Theme.hPad)
                }
                if !model.loaded { LoadingRow() }
            }
        }
        .chromeInset()
        .ignoresSafeArea(edges: .top)
        .navigationTitle(scrolledPast ? a.name : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(scrolledPast ? .visible : .hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                let following = library.savedState[a.uri] ?? false
                Button {
                    Haptics.tap()
                    Task { await library.toggleSaved(uri: a.uri, artist: a) }
                } label: {
                    Text(following ? "Following" : "Follow")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
        }
        .task { await model.load() }
    }

    private func header(_ a: Artist) -> some View {
        ZStack(alignment: .bottomLeading) {
            Artwork(a.image.isEmpty ? a.imageMid : a.image, px: 1000, corner: 0)
                .frame(height: 380)
                .frame(maxWidth: .infinity)
                .clipped()
                .visualEffect { content, geo in
                    let y = geo.frame(in: .scrollView).minY
                    return content
                        .scaleEffect(y > 0 ? 1 + y / 380 : 1, anchor: .bottom)
                }
            LinearGradient(colors: [Color.clear, Color.black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
            HStack(alignment: .bottom) {
                Text(a.name)
                    .font(.system(size: 36, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 10)
                Button {
                    Haptics.firm()
                    Task { await engine.playContext(a.uri, preview: model.top.first) }
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 54, height: 54)
                        .background(Theme.accent, in: Circle())
                        .shadow(color: Color.black.opacity(0.3), radius: 8, y: 4)
                }
                .buttonStyle(PressableStyle(scale: 0.9))
            }
            .padding(.horizontal, Theme.hPad)
            .padding(.bottom, 18)
        }
        .frame(height: 380)
        .background(
            GeometryReader { g in
                Color.clear
                    .onChange(of: g.frame(in: .global).maxY) { _, maxY in
                        let past = maxY < 110
                        if past != scrolledPast { scrolledPast = past }
                    }
            }
        )
    }
}

// MARK: - Playlist page
@MainActor
@Observable
final class PlaylistModel {
    var playlist: Playlist
    var tracks: [Track] = []
    var total = 0
    var canList = true
    var loaded = false
    var failed = false
    private var loadingMore = false

    init(_ seed: Playlist) {
        playlist = seed
        total = seed.total
    }

    func load() async {
        if loaded { return }
        guard let r = await Spotify.shared.playlist(playlist.id) else {
            failed = true
            canList = false
            loaded = true
            return
        }
        playlist = r.playlist
        tracks = r.tracks
        total = r.total
        canList = r.canList
        loaded = true
        await Library.shared.checkSaved(playlist.uri)
        await Library.shared.checkLiked(Array(tracks.prefix(40)))
    }

    func more() async {
        guard canList, !loadingMore, tracks.count < total else { return }
        loadingMore = true
        defer { loadingMore = false }
        if let more = await Spotify.shared.playlistItems(playlist.id, offset: tracks.count), !more.isEmpty {
            tracks += more
        } else {
            total = tracks.count
        }
    }
}

struct PlaylistView: View {
    @State private var model: PlaylistModel
    @Environment(Engine.self) private var engine
    @Environment(Library.self) private var library

    init(seed: Playlist) {
        _model = State(initialValue: PlaylistModel(seed))
    }

    var body: some View {
        let p = model.playlist
        let mine = library.owns(p)
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Artwork(p.image.isEmpty ? p.imageMid : p.image, px: 800, corner: 10)
                        .frame(width: 250, height: 250)
                        .shadow(color: Color.black.opacity(0.3), radius: 18, y: 10)
                        .padding(.bottom, 10)
                    Text(p.name)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(p.owner.isEmpty ? "Playlist" : p.owner)
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                    if !p.about.isEmpty {
                        Text(p.about)
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.top, 2)
                    }
                    if model.total > 0 {
                        Text("\(model.total) songs")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.secondary)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 4)
                .padding(.bottom, 18)

                PlayShuffleButtons(play: {
                    Task { await engine.playContext(p.uri, preview: model.tracks.first) }
                }, shuffle: {
                    Task { await engine.playContext(p.uri, shuffle: true, count: max(model.total, model.tracks.count)) }
                })
                .padding(.bottom, 14)

                if !model.loaded { LoadingRow() }
                if model.loaded && !model.canList {
                    VStack(spacing: 8) {
                        Image(systemName: "lock.fill").font(.system(size: 22)).foregroundStyle(Color.secondary)
                        Text("Spotify only lets apps like this one list the songs in playlists you made or collaborate on. You can still play this one.")
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 36)
                    .padding(.vertical, 24)
                }
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.tracks.enumerated()), id: \.offset) { i, t in
                        TrackRow(track: t) {
                            Task { await engine.playContext(p.uri, startAt: t.uri, preview: t) }
                        }
                        .onAppear {
                            if i == model.tracks.count - 1 { Task { await model.more() } }
                        }
                    }
                }
                if model.loaded && model.canList && model.tracks.isEmpty {
                    EmptyNote(symbol: "music.note.list", title: "Empty Playlist", message: "Add songs from any song's ••• menu.")
                }
            }
        }
        .chromeInset()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !mine {
                ToolbarItem(placement: .topBarTrailing) {
                    let saved = library.savedState[p.uri] ?? false
                    Button {
                        Haptics.tap()
                        Task { await library.toggleSaved(uri: p.uri, playlist: p) }
                    } label: {
                        Image(systemName: saved ? "checkmark.circle.fill" : "plus.circle")
                            .font(.system(size: 20))
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let u = p.shareURL {
                    ShareLink(item: u) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
        .refreshable {
            model.loaded = false
            await model.load()
        }
        .task { await model.load() }
    }
}
