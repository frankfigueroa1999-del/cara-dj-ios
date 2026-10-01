import SwiftUI

/// Library: your playlists, artists, albums and liked songs.
struct LibraryView: View {
    @Environment(Library.self) private var library
    @Environment(Engine.self) private var engine
    @State private var askName = false
    @State private var newName = ""

    var body: some View {
        ScrollView {
            if !Spotify.shared.isLoggedIn {
                ConnectCard().padding(.top, 12)
            } else {
                VStack(alignment: .leading, spacing: 26) {
                    if library.needsReconnect { ReconnectBanner() }
                    VStack(spacing: 0) {
                        row(.playlists, "Playlists", "music.note.list", library.playlistsTotal)
                        row(.artists, "Artists", "music.mic", library.artists.count)
                        row(.albums, "Albums", "square.stack", library.albumsTotal)
                        row(.liked, "Liked Songs", "heart", library.likedTotal)
                    }
                    if !library.albums.isEmpty || !library.playlists.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Recently Added")
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 18) {
                                ForEach(recentItems, id: \.self) { r in
                                    NavigationLink(value: r) { tile(r) }
                                        .buttonStyle(PressableStyle())
                                }
                            }
                            .padding(.horizontal, Theme.hPad)
                        }
                    }
                    if !library.loaded && library.playlists.isEmpty { LoadingRow() }
                }
                .padding(.top, 6)
            }
        }
        .chromeInset()
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        newName = ""
                        askName = true
                    } label: {
                        Label("New Playlist", systemImage: "music.note.list")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                AvatarButton()
            }
        }
        .alert("New Playlist", isPresented: $askName) {
            TextField("Name", text: $newName)
            Button("Create") {
                let name = newName
                Task {
                    if let p = await library.createPlaylist(name) {
                        Toasts.shared.show("Made \(p.name)", "music.note.list")
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        }
        .refreshable { await library.loadAll(force: true) }
        .task { await library.loadAll() }
    }

    /// Albums you saved recently, then your newest playlists.
    private var recentItems: [Route] {
        var out: [Route] = []
        for a in library.albums.prefix(8) { out.append(.album(a)) }
        for p in library.playlists.prefix(max(0, 8 - out.count)) { out.append(.playlist(p)) }
        return out
    }

    @ViewBuilder
    private func tile(_ r: Route) -> some View {
        switch r {
        case .album(let a): AlbumTile(title: a.name, subtitle: a.artist, art: a.artMid)
        case .playlist(let p): AlbumTile(title: p.name, subtitle: p.owner, art: p.imageMid)
        default: EmptyView()
        }
    }

    private func row(_ r: Route, _ title: String, _ icon: String, _ count: Int) -> some View {
        NavigationLink(value: r) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 30)
                Text(title).font(.system(size: 20)).foregroundStyle(Color.primary)
                Spacer()
                if count > 0 {
                    Text("\(count)").font(.system(size: 15)).foregroundStyle(Color.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.horizontal, Theme.hPad)
            .frame(height: 52)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Divider().padding(.leading, Theme.hPad + 44) }
        }
        .buttonStyle(.plain)
    }
}

struct PlaylistsListView: View {
    @Environment(Library.self) private var library
    @State private var askName = false
    @State private var newName = ""

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                Button {
                    newName = ""
                    askName = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 56, height: 56)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        Text("New Playlist…").font(.system(size: 16)).foregroundStyle(Theme.accent)
                        Spacer()
                    }
                    .padding(.horizontal, Theme.hPad)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                NavigationLink(value: Route.liked) {
                    MediaRow(title: "Liked Songs", subtitle: "\(library.likedTotal) songs", art: "")
                        .overlay(alignment: .leading) {
                            ZStack {
                                LinearGradient(colors: [Theme.accent, Theme.caraPurple], startPoint: .topLeading, endPoint: .bottomTrailing)
                                Image(systemName: "heart.fill").foregroundStyle(Color.white)
                            }
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .padding(.leading, Theme.hPad)
                        }
                }
                .buttonStyle(.plain)
                ForEach(Array(library.playlists.enumerated()), id: \.element.id) { i, p in
                    NavigationLink(value: Route.playlist(p)) {
                        MediaRow(title: p.name, subtitle: "Playlist · " + (p.owner.isEmpty ? "You" : p.owner), art: p.imageMid)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if i == library.playlists.count - 1 { Task { await library.loadMorePlaylists() } }
                    }
                }
            }
            .padding(.top, 6)
        }
        .chromeInset()
        .navigationTitle("Playlists")
        .alert("New Playlist", isPresented: $askName) {
            TextField("Name", text: $newName)
            Button("Create") {
                let name = newName
                Task { _ = await library.createPlaylist(name) }
            }
            Button("Cancel", role: .cancel) { }
        }
        .refreshable { await library.loadAll(force: true) }
    }
}

struct AlbumsGridView: View {
    @Environment(Library.self) private var library

    var body: some View {
        ScrollView {
            if library.albums.isEmpty {
                EmptyNote(symbol: "square.stack", title: "No Saved Albums", message: "Albums you save on Spotify (or with the + on an album page) show up here.")
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 18) {
                    ForEach(Array(library.albums.enumerated()), id: \.element.id) { i, a in
                        NavigationLink(value: Route.album(a)) {
                            AlbumTile(title: a.name, subtitle: a.artist, art: a.artMid)
                        }
                        .buttonStyle(PressableStyle())
                        .onAppear {
                            if i == library.albums.count - 1 { Task { await library.loadMoreAlbums() } }
                        }
                    }
                }
                .padding(.horizontal, Theme.hPad)
                .padding(.top, 8)
            }
        }
        .chromeInset()
        .navigationTitle("Albums")
        .refreshable { await library.loadAll(force: true) }
    }
}

struct ArtistsListView: View {
    @Environment(Library.self) private var library

    var body: some View {
        ScrollView {
            if library.artists.isEmpty {
                EmptyNote(symbol: "music.mic", title: "No Artists Yet", message: "Artists you follow on Spotify show up here.")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(library.artists.enumerated()), id: \.element.id) { i, a in
                        NavigationLink(value: Route.artist(a)) {
                            MediaRow(title: a.name, subtitle: "Artist", art: a.imageMid, circle: true)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if i == library.artists.count - 1 { Task { await library.loadMoreArtists() } }
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
        .chromeInset()
        .navigationTitle("Artists")
        .refreshable { await library.loadAll(force: true) }
    }
}

struct LikedSongsView: View {
    @Environment(Library.self) private var library
    @Environment(Engine.self) private var engine

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    ZStack {
                        LinearGradient(colors: [Theme.accent, Theme.caraPurple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "heart.fill")
                            .font(.system(size: 80, weight: .semibold))
                            .foregroundStyle(Color.white)
                    }
                    .frame(width: 230, height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: Theme.accent.opacity(0.3), radius: 20, y: 10)
                    Text("Liked Songs").font(.title2.weight(.bold))
                    Text("\(library.likedTotal) songs").font(.subheadline).foregroundStyle(Color.secondary)
                }
                .padding(.top, 8)
                .padding(.bottom, 18)
                PlayShuffleButtons(play: {
                    play(at: 0, shuffle: false)
                }, shuffle: {
                    play(at: 0, shuffle: true)
                })
                .padding(.bottom, 12)
                if library.liked.isEmpty && library.loaded {
                    EmptyNote(symbol: "heart", title: "No Liked Songs", message: "Tap the heart in the player to save songs here.")
                }
                LazyVStack(spacing: 0) {
                    ForEach(Array(library.liked.enumerated()), id: \.offset) { i, t in
                        TrackRow(track: t) { play(at: i, shuffle: false) }
                            .onAppear {
                                if i == library.liked.count - 1 { Task { await library.loadMoreLiked() } }
                            }
                    }
                }
            }
        }
        .chromeInset()
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await library.loadAll(force: true) }
    }

    private func play(at i: Int, shuffle: Bool) {
        let ctx = (library.me?.id).map { "spotify:user:\($0):collection" }
        Task { await engine.playTracks(library.liked, startAt: i, shuffle: shuffle, context: ctx) }
    }
}
