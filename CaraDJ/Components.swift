import SwiftUI
import UIKit

// MARK: - The "..." menu for a song (also shown when you press and hold a song)
struct TrackMenuItems: View {
    let track: Track
    var showAlbum = true
    var showArtist = true
    /// Set this when the menu lives inside a sheet (the big player), which shows its own playlist picker.
    var onAddToPlaylist: ((Track) -> Void)? = nil
    @Environment(Engine.self) private var engine
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        let liked = library.likedState[track.uri] ?? false
        Button {
            Task { await engine.addToQueue(track) }
        } label: {
            Label("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward")
        }
        Button {
            Task { await library.setLiked(track, !liked) }
        } label: {
            Label(liked ? "Remove from Liked Songs" : "Add to Liked Songs", systemImage: liked ? "heart.slash" : "heart")
        }
        Button {
            if let f = onAddToPlaylist { f(track) } else { router.addToPlaylist = track }
        } label: {
            Label("Add to a Playlist…", systemImage: "text.badge.plus")
        }
        Divider()
        if showAlbum && !track.albumID.isEmpty {
            Button {
                router.open(.album(track.albumRef))
            } label: {
                Label("Go to Album", systemImage: "square.stack")
            }
        }
        if showArtist && !track.artistID.isEmpty {
            Button {
                router.open(.artist(track.artistRef))
            } label: {
                Label("Go to Artist", systemImage: "music.mic")
            }
        }
        if let u = track.shareURL {
            ShareLink(item: u) {
                Label("Share Song", systemImage: "square.and.arrow.up")
            }
        }
    }
}

// MARK: - One song in a list
struct TrackRow: View {
    let track: Track
    /// Show the track number instead of the cover (album pages).
    var number: Int? = nil
    var showAlbumInMenu = true
    var action: () -> Void
    @Environment(Engine.self) private var engine

    var body: some View {
        let current = !track.uri.isEmpty && engine.displayItem?.uri == track.uri
        let sub = number == nil ? track.artistLine : (track.artists.count > 1 ? track.artistLine : "")
        HStack(spacing: 12) {
            leading(current)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 16))
                    .foregroundStyle(current ? Theme.accent : Color.primary)
                    .lineLimit(1)
                if track.explicit || !sub.isEmpty {
                    HStack(spacing: 5) {
                        if track.explicit { ExplicitBadge() }
                        if !sub.isEmpty {
                            Text(sub)
                                .font(.system(size: 14))
                                .foregroundStyle(Color.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            Spacer(minLength: 6)
            Menu {
                TrackMenuItems(track: track, showAlbum: showAlbumInMenu)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 34, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(.leading, Theme.hPad)
        .padding(.trailing, 10)
        .frame(minHeight: number == nil ? 64 : 52)
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.tap()
            action()
        }
        .contextMenu {
            TrackMenuItems(track: track, showAlbum: showAlbumInMenu)
        }
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, number == nil ? Theme.hPad + 60 : Theme.hPad + 38)
        }
    }

    @ViewBuilder
    private func leading(_ current: Bool) -> some View {
        if let n = number {
            ZStack {
                if current {
                    EqualizerBars(playing: engine.now.isPlaying)
                } else {
                    Text("\(n)").font(.system(size: 16)).monospacedDigit().foregroundStyle(Color.secondary)
                }
            }
            .frame(width: 26)
        } else {
            Artwork(track.artMid, px: 150, corner: 5)
                .frame(width: 48, height: 48)
                .overlay {
                    if current {
                        RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.black.opacity(0.45))
                        EqualizerBars(playing: engine.now.isPlaying, color: .white)
                    }
                }
        }
    }
}

// MARK: - Cards for carousels and grids
struct AlbumCard: View {
    let album: Album
    var width: CGFloat = 160
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Artwork(album.artMid, px: 420, corner: 8)
                .frame(width: width, height: width)
            VStack(alignment: .leading, spacing: 1) {
                Text(album.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Color.primary).lineLimit(1)
                Text(subtitle ?? album.artist).font(.system(size: 14)).foregroundStyle(Color.secondary).lineLimit(1)
            }
        }
        .frame(width: width, alignment: .leading)
    }
}

struct PlaylistCard: View {
    let playlist: Playlist
    var width: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Artwork(playlist.imageMid, px: 420, corner: 8)
                .frame(width: width, height: width)
            VStack(alignment: .leading, spacing: 1) {
                Text(playlist.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Color.primary).lineLimit(1)
                Text(playlist.owner.isEmpty ? "Playlist" : playlist.owner).font(.system(size: 14)).foregroundStyle(Color.secondary).lineLimit(1)
            }
        }
        .frame(width: width, alignment: .leading)
    }
}

struct ArtistCircle: View {
    let artist: Artist
    var size: CGFloat = 120

    var body: some View {
        VStack(spacing: 8) {
            Artwork(artist.imageMid, px: 360, circle: true)
                .frame(width: size, height: size)
            Text(artist.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .frame(width: size)
        }
    }
}

/// A grid tile that fills whatever width the grid gives it.
struct AlbumTile: View {
    let title: String
    let subtitle: String
    let art: String
    var circle = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { Artwork(art, px: 420, corner: 8, circle: circle) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Color.primary).lineLimit(1)
                Text(subtitle).font(.system(size: 14)).foregroundStyle(Color.secondary).lineLimit(1)
            }
        }
    }
}

/// A playlist / artist / album as a list row.
struct MediaRow: View {
    let title: String
    let subtitle: String
    let art: String
    var circle = false

    var body: some View {
        HStack(spacing: 12) {
            Artwork(art, px: 180, corner: 6, circle: circle)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16)).foregroundStyle(Color.primary).lineLimit(1)
                Text(subtitle).font(.system(size: 14)).foregroundStyle(Color.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(.horizontal, Theme.hPad)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Divider().padding(.leading, Theme.hPad + 68) }
    }
}

/// A horizontal row of cards that snaps to each card as you swipe.
struct Carousel<Content: View>: View {
    var spacing: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: spacing) {
                content
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, Theme.hPad, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
    }
}

// MARK: - Toasts
struct ToastOverlay: View {
    @Environment(Toasts.self) private var toasts

    var body: some View {
        VStack {
            if let t = toasts.current {
                HStack(spacing: 8) {
                    Image(systemName: t.symbol).font(.system(size: 15, weight: .semibold))
                    Text(t.text).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                }
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: Color.black.opacity(0.2), radius: 12, y: 6)
                .padding(.top, 8)
                .padding(.horizontal, 24)
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(t.id)
            }
            Spacer()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: toasts.current)
        .allowsHitTesting(false)
    }
}

// MARK: - "Add to a Playlist"
struct AddToPlaylistSheet: View {
    let track: Track
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var askName = false
    @State private var working = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Artwork(track.artMid, px: 150, corner: 5).frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title).font(.headline).lineLimit(1)
                            Text(track.artistLine).font(.subheadline).foregroundStyle(Color.secondary).lineLimit(1)
                        }
                    }
                }
                Section {
                    Button {
                        askName = true
                    } label: {
                        Label("New Playlist…", systemImage: "plus")
                            .foregroundStyle(Theme.accent)
                    }
                    ForEach(library.editablePlaylists) { p in
                        Button {
                            add(to: p)
                        } label: {
                            HStack(spacing: 12) {
                                Artwork(p.imageMid, px: 150, corner: 5).frame(width: 44, height: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).foregroundStyle(Color.primary).lineLimit(1)
                                    Text("\(p.total) songs").font(.caption).foregroundStyle(Color.secondary)
                                }
                            }
                        }
                        .disabled(working)
                    }
                } footer: {
                    Text("Only playlists you made (or collaborate on) can take new songs.")
                }
            }
            .navigationTitle("Add to a Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("New Playlist", isPresented: $askName) {
                TextField("Name", text: $newName)
                Button("Create") {
                    let name = newName
                    Task {
                        if let p = await library.createPlaylist(name) { add(to: p) }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This song goes straight into it.")
            }
        }
        .task { await library.loadAll() }
    }

    private func add(to p: Playlist) {
        working = true
        Task {
            let ok = await library.add(track, to: p)
            working = false
            if ok {
                Haptics.success()
                dismiss()
            }
        }
    }
}
