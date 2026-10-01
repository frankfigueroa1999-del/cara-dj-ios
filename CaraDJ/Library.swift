import Foundation
import Observation

/// Your Spotify library: playlists, albums, artists, liked songs, plus what you've been playing lately.
/// Kept on the phone too, so the app opens straight to your stuff.
@MainActor
@Observable
final class Library {
    static let shared = Library()

    var me: UserProfile? = nil
    var playlists: [Playlist] = []
    var playlistsTotal = 0
    var albums: [Album] = []
    var albumsTotal = 0
    var artists: [Artist] = []
    var artistsNext: String? = nil
    var liked: [Track] = []
    var likedTotal = 0
    var recent: [Track] = []
    var topTracks: [Track] = []
    var topArtists: [Artist] = []
    /// uri -> is it a liked song
    var likedState: [String: Bool] = [:]
    /// album / artist / playlist uri -> is it saved / followed
    var savedState: [String: Bool] = [:]
    var loaded = false
    var refreshing = false
    var needsReconnect = false
    private var lastLoad = Date.distantPast
    private var busyLoading: Set<String> = []

    init() {
        loadCache()
        needsReconnect = Spotify.shared.isLoggedIn && !Spotify.shared.hasAllScopes
    }

    // MARK: handy lists for the screens
    /// Albums you've been playing lately (newest first, no repeats).
    var recentAlbums: [Album] {
        var seen = Set<String>()
        var out: [Album] = []
        for t in recent where !t.albumID.isEmpty && !seen.contains(t.albumID) {
            seen.insert(t.albumID)
            out.append(t.albumRef)
            if out.count >= 14 { break }
        }
        return out
    }

    /// Playlists you can add songs to.
    var editablePlaylists: [Playlist] {
        let mine = me?.id ?? ""
        return playlists.filter { $0.ownerID == mine || $0.collaborative }
    }

    func owns(_ p: Playlist) -> Bool {
        let mine = me?.id ?? ""
        return !mine.isEmpty && (p.ownerID == mine || p.collaborative)
    }

    // MARK: loading
    func loadAll(force: Bool = false) async {
        let sp = Spotify.shared
        guard sp.isLoggedIn else { return }
        needsReconnect = !sp.hasAllScopes
        if refreshing { return }
        if !force && loaded && Date().timeIntervalSince(lastLoad) < 300 { return }
        refreshing = true
        defer { refreshing = false }
        lastLoad = Date()

        async let meR = sp.me()
        async let plR = sp.myPlaylists(offset: 0)
        async let ttR = sp.topTracks()
        async let taR = sp.topArtists()
        async let rpR = sp.recentlyPlayed()
        let (m, pl, tt, ta, rp) = await (meR, plR, ttR, taR, rpR)
        if let m = m { me = m }
        if let pl = pl { playlists = pl.items; playlistsTotal = pl.total }
        if !tt.isEmpty { topTracks = tt }
        if !ta.isEmpty { topArtists = ta }
        if !rp.isEmpty { recent = rp }

        async let alR = sp.savedAlbums(offset: 0)
        async let arR = sp.followedArtists(after: nil)
        async let lkR = sp.savedTracks(offset: 0)
        let (al, ar, lk) = await (alR, arR, lkR)
        if let al = al {
            albums = al.items
            albumsTotal = al.total
            for a in al.items { savedState[a.uri] = true }
        }
        if let ar = ar {
            artists = ar.items
            artistsNext = ar.next
            for a in ar.items { savedState[a.uri] = true }
        }
        if let lk = lk {
            liked = lk.items
            likedTotal = lk.total
            for t in lk.items { likedState[t.uri] = true }
        }
        loaded = true
        saveCache()
    }

    func loadMorePlaylists() async {
        guard playlists.count < playlistsTotal, !busyLoading.contains("pl") else { return }
        busyLoading.insert("pl")
        defer { busyLoading.remove("pl") }
        if let r = await Spotify.shared.myPlaylists(offset: playlists.count) {
            let have = Set(playlists.map { $0.id })
            playlists += r.items.filter { !have.contains($0.id) }
            playlistsTotal = r.total
        }
    }

    /// Every page of your playlists (the "Add to a Playlist" list needs them all).
    func loadAllPlaylists() async {
        var guardCount = 0
        while playlists.count < playlistsTotal && guardCount < 20 {
            let before = playlists.count
            await loadMorePlaylists()
            if playlists.count == before { break }
            guardCount += 1
        }
    }

    func loadMoreLiked() async {
        guard liked.count < likedTotal, !busyLoading.contains("lk") else { return }
        busyLoading.insert("lk")
        defer { busyLoading.remove("lk") }
        if let r = await Spotify.shared.savedTracks(offset: liked.count) {
            liked += r.items
            likedTotal = r.total
            for t in r.items { likedState[t.uri] = true }
        }
    }

    func loadMoreAlbums() async {
        guard albums.count < albumsTotal, !busyLoading.contains("al") else { return }
        busyLoading.insert("al")
        defer { busyLoading.remove("al") }
        if let r = await Spotify.shared.savedAlbums(offset: albums.count) {
            let have = Set(albums.map { $0.id })
            albums += r.items.filter { !have.contains($0.id) }
            albumsTotal = r.total
        }
    }

    func loadMoreArtists() async {
        guard let next = artistsNext, !busyLoading.contains("ar") else { return }
        busyLoading.insert("ar")
        defer { busyLoading.remove("ar") }
        if let r = await Spotify.shared.followedArtists(after: next) {
            let have = Set(artists.map { $0.id })
            artists += r.items.filter { !have.contains($0.id) }
            artistsNext = r.next
        }
    }

    // MARK: liking and saving
    @discardableResult
    func setLiked(_ t: Track, _ on: Bool) async -> Bool {
        guard !t.uri.isEmpty else { return false }
        likedState[t.uri] = on
        var ok = false
        if on { ok = await Spotify.shared.save([t.uri]) } else { ok = await Spotify.shared.remove([t.uri]) }
        if ok {
            if on {
                if !liked.contains(where: { $0.uri == t.uri }) { liked.insert(t, at: 0); likedTotal += 1 }
            } else {
                liked.removeAll { $0.uri == t.uri }
                likedTotal = max(0, likedTotal - 1)
            }
            Toasts.shared.show(on ? "Added to Liked Songs" : "Removed from Liked Songs", on ? "heart.fill" : "heart.slash")
            saveCache()
        } else {
            likedState[t.uri] = !on
            Toasts.shared.show(needsReconnect ? "Reconnect Spotify in Settings first" : "Spotify didn't save that", "exclamationmark.triangle.fill")
        }
        return ok
    }

    /// Ask Spotify which of these songs are liked (so the menus say the right thing).
    func checkLiked(_ tracks: [Track]) async {
        let uris = tracks.map { $0.uri }.filter { !$0.isEmpty && likedState[$0] == nil }
        var i = 0
        while i < uris.count {
            let chunk = Array(uris[i..<min(i + 40, uris.count)])
            if let r = await Spotify.shared.contains(chunk), r.count == chunk.count {
                for (u, v) in zip(chunk, r) { likedState[u] = v }
            }
            i += 40
        }
    }

    func checkSaved(_ uri: String) async {
        guard !uri.isEmpty else { return }
        if let r = await Spotify.shared.contains([uri]), let v = r.first { savedState[uri] = v }
    }

    /// Save / unsave an album, follow / unfollow an artist or playlist.
    func toggleSaved(uri: String, album: Album? = nil, artist: Artist? = nil, playlist: Playlist? = nil) async {
        guard !uri.isEmpty else { return }
        let want = !(savedState[uri] ?? false)
        savedState[uri] = want
        var ok = false
        if want { ok = await Spotify.shared.save([uri]) } else { ok = await Spotify.shared.remove([uri]) }
        guard ok else {
            savedState[uri] = !want
            Toasts.shared.show(needsReconnect ? "Reconnect Spotify in Settings first" : "Spotify didn't save that", "exclamationmark.triangle.fill")
            return
        }
        if let a = album {
            if want { if !albums.contains(where: { $0.id == a.id }) { albums.insert(a, at: 0); albumsTotal += 1 } }
            else { albums.removeAll { $0.id == a.id }; albumsTotal = max(0, albumsTotal - 1) }
            Toasts.shared.show(want ? "Added to Library" : "Removed from Library", want ? "checkmark" : "minus.circle")
        }
        if let a = artist {
            if want { if !artists.contains(where: { $0.id == a.id }) { artists.insert(a, at: 0) } }
            else { artists.removeAll { $0.id == a.id } }
            Toasts.shared.show(want ? "Following \(a.name)" : "Unfollowed \(a.name)", want ? "checkmark" : "minus.circle")
        }
        if let p = playlist {
            if want { if !playlists.contains(where: { $0.id == p.id }) { playlists.insert(p, at: 0); playlistsTotal += 1 } }
            else { playlists.removeAll { $0.id == p.id }; playlistsTotal = max(0, playlistsTotal - 1) }
            Toasts.shared.show(want ? "Added to Library" : "Removed from Library", want ? "checkmark" : "minus.circle")
        }
        saveCache()
    }

    func createPlaylist(_ name: String) async -> Playlist? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        guard var p = await Spotify.shared.createPlaylist(clean) else {
            Toasts.shared.show(needsReconnect ? "Reconnect Spotify in Settings first" : "Couldn't make that playlist", "exclamationmark.triangle.fill")
            return nil
        }
        if p.ownerID.isEmpty { p.ownerID = me?.id ?? "" }
        playlists.insert(p, at: 0)
        playlistsTotal += 1
        saveCache()
        return p
    }

    func add(_ t: Track, to p: Playlist) async -> Bool {
        let ok = await Spotify.shared.addToPlaylist(p.id, uris: [t.uri])
        if ok {
            if let i = playlists.firstIndex(where: { $0.id == p.id }) { playlists[i].total += 1 }
            Toasts.shared.show("Added to \(p.name)", "text.badge.plus")
        } else {
            Toasts.shared.show("Couldn't add to \(p.name)", "exclamationmark.triangle.fill")
        }
        return ok
    }

    func clear() {
        me = nil; playlists = []; albums = []; artists = []; liked = []; recent = []; topTracks = []; topArtists = []
        likedState = [:]; savedState = [:]; loaded = false; needsReconnect = false
        try? FileManager.default.removeItem(at: cacheURL)
    }

    // MARK: kept on the phone between launches
    private struct Cache: Codable {
        var me: UserProfile?
        var playlists: [Playlist]
        var playlistsTotal: Int
        var albums: [Album]
        var albumsTotal: Int
        var artists: [Artist]
        var liked: [Track]
        var likedTotal: Int
        var recent: [Track]
        var topTracks: [Track]
        var topArtists: [Artist]
    }

    private var cacheURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("cara-library-v2.json")
    }

    private func saveCache() {
        let c = Cache(me: me, playlists: playlists, playlistsTotal: playlistsTotal, albums: Array(albums.prefix(100)),
                      albumsTotal: albumsTotal, artists: Array(artists.prefix(100)), liked: Array(liked.prefix(100)),
                      likedTotal: likedTotal, recent: recent, topTracks: topTracks, topArtists: topArtists)
        if let data = try? JSONEncoder().encode(c) { try? data.write(to: cacheURL, options: .atomic) }
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL), let c = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        me = c.me
        playlists = c.playlists
        playlistsTotal = c.playlistsTotal
        albums = c.albums
        albumsTotal = c.albumsTotal
        artists = c.artists
        liked = c.liked
        likedTotal = c.likedTotal
        recent = c.recent
        topTracks = c.topTracks
        topArtists = c.topArtists
        for t in c.liked { likedState[t.uri] = true }
        for a in c.albums { savedState[a.uri] = true }
        for a in c.artists { savedState[a.uri] = true }
    }
}
