import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

/// Talks to Spotify: logging in, reading what's playing, your library, search, and the player buttons.
final class Spotify: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = Spotify()
    let redirect = "caradj://callback"
    /// Everything this app asks permission for. Older logins only had the first two, so they get asked once more.
    static let scopeList = [
        "user-read-playback-state", "user-modify-playback-state", "user-read-currently-playing",
        "user-read-recently-played", "user-top-read", "user-library-read", "user-library-modify",
        "playlist-read-private", "playlist-read-collaborative", "playlist-modify-private", "playlist-modify-public",
        "user-follow-read", "user-follow-modify",
    ]
    private let cfg = Config.shared
    private var session: ASWebAuthenticationSession?

    var isLoggedIn: Bool { cfg.refreshToken != nil }
    /// True once the login includes the library / playlist permissions the new screens need.
    var hasAllScopes: Bool {
        let granted = Set(cfg.grantedScopes.split(separator: " ").map(String.init))
        return Spotify.scopeList.allSatisfy { granted.contains($0) }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.windows.first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
    }

    // MARK: login (PKCE, no secret needed)
    @MainActor
    func login() async throws {
        let clientID = cfg.clientID.trimmingCharacters(in: .whitespaces)
        guard !clientID.isEmpty else { throw NSError(domain: "Cara", code: 1, userInfo: [NSLocalizedDescriptionKey: "Add your Spotify Client ID in Settings first."]) }
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let verifier = String((0..<64).map { _ in chars.randomElement()! })
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var comps = URLComponents(string: "https://accounts.spotify.com/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "scope", value: Spotify.scopeList.joined(separator: " ")),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
        ]
        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: comps.url!, callbackURLScheme: "caradj") { url, error in
                if let url = url { cont.resume(returning: url) }
                else { cont.resume(throwing: error ?? NSError(domain: "Cara", code: 2)) }
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = false
            self.session = s
            if !s.start() { cont.resume(throwing: NSError(domain: "Cara", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not open the Spotify login."])) }
        }
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw NSError(domain: "Cara", code: 4, userInfo: [NSLocalizedDescriptionKey: "Spotify did not send back a login code."])
        }
        try await tokenRequest([
            "client_id": clientID, "grant_type": "authorization_code", "code": code,
            "redirect_uri": redirect, "code_verifier": verifier,
        ])
    }

    private func tokenRequest(_ params: [String: String]) async throws {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = (form.percentEncodedQuery ?? "").data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = j["access_token"] as? String else {
            throw NSError(domain: "Cara", code: 5, userInfo: [NSLocalizedDescriptionKey: "Spotify login failed (\(status)): " + (String(data: data, encoding: .utf8) ?? "")])
        }
        cfg.accessToken = access
        if let r = j["refresh_token"] as? String { cfg.refreshToken = r }
        if let sc = j["scope"] as? String, !sc.isEmpty { cfg.grantedScopes = sc }
        cfg.tokenExpiry = Date().timeIntervalSince1970 + (j["expires_in"] as? Double ?? 3600) - 60
    }

    func logout() {
        cfg.accessToken = nil
        cfg.refreshToken = nil
        cfg.tokenExpiry = 0
        cfg.grantedScopes = ""
    }

    /// Only one token refresh at a time, even when lots of screens load at once.
    @MainActor private var refreshTask: Task<Void, Error>? = nil

    @MainActor
    private func validToken() async throws -> String {
        if let t = cfg.accessToken, Date().timeIntervalSince1970 < cfg.tokenExpiry { return t }
        if let running = refreshTask {
            try await running.value
            return cfg.accessToken ?? ""
        }
        guard let r = cfg.refreshToken else { throw NSError(domain: "Cara", code: 6, userInfo: [NSLocalizedDescriptionKey: "Not logged in to Spotify."]) }
        let id = cfg.clientID.trimmingCharacters(in: .whitespaces)
        let task = Task<Void, Error> { try await self.tokenRequest(["client_id": id, "grant_type": "refresh_token", "refresh_token": r]) }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
        return cfg.accessToken ?? ""
    }

    // MARK: Web API
    /// After Spotify says "slow down" (429) the app stays quiet until this time instead of making it worse.
    var blockedUntil = Date.distantPast

    @discardableResult
    func call(_ method: String, _ path: String, query: [String: String] = [:], body: Data? = nil) async -> (status: Int, data: Data) {
        if Date() < blockedUntil { return (429, Data()) }
        do {
            let token = try await validToken()
            guard var comps = URLComponents(string: "https://api.spotify.com/v1" + path) else { return (0, Data()) }
            if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
            guard let url = comps.url else { return (0, Data()) }
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.timeoutInterval = 12
            req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            if let body = body {
                req.httpBody = body
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            } else if method != "GET" { req.setValue("0", forHTTPHeaderField: "Content-Length") }
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 429 {
                let ra = Double((resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 0
                blockedUntil = Date().addingTimeInterval(min(max(ra, 20), 600))
            }
            return (code, data)
        } catch {
            return (0, Data())
        }
    }

    /// GET something and hand back the JSON object (nil unless Spotify said 200).
    func getJSON(_ path: String, _ query: [String: String] = [:]) async -> [String: Any]? {
        let r = await call("GET", path, query: query)
        guard r.status == 200 else { return nil }
        return (try? JSONSerialization.jsonObject(with: r.data)) as? [String: Any]
    }

    private func jsonBody(_ obj: [String: Any]) -> Data? { try? JSONSerialization.data(withJSONObject: obj) }

    // MARK: what's playing
    /// The HTTP status of the most recent playback check, so the app can say WHY it couldn't read playback.
    var lastStatus = 0

    func poll() async -> Playback? {
        let t0 = Date()
        let r = await call("GET", "/me/player")
        let t1 = Date()
        lastStatus = r.status
        guard r.status == 200,
              let j = try? JSONSerialization.jsonObject(with: r.data) as? [String: Any] else {
            if r.status == 204 { return Playback() }   // nothing playing anywhere
            return nil
        }
        var p = Playback()
        p.isPlaying = j["is_playing"] as? Bool ?? false
        p.progressMs = j["progress_ms"] as? Int ?? 0
        p.stamp = Date(timeInterval: t1.timeIntervalSince(t0) / 2, since: t0)
        if let dev = j["device"] as? [String: Any] {
            p.deviceID = dev["id"] as? String
            p.deviceName = dev["name"] as? String ?? ""
            p.deviceType = dev["type"] as? String ?? ""
        }
        if let ctx = j["context"] as? [String: Any] { p.contextURI = ctx["uri"] as? String ?? "" }
        p.shuffle = j["shuffle_state"] as? Bool ?? false
        p.repeatMode = j["repeat_state"] as? String ?? "off"
        if let item = j["item"] as? [String: Any], (j["currently_playing_type"] as? String ?? "track") == "track" {
            p.hasItem = true
            p.uri = Spotify.realURI(item)
            p.durationMs = item["duration_ms"] as? Int ?? 0
            let t = Track.parse(item)
            p.item = t
            if let t = t, t.isMusic { p.track = t }
        }
        return p
    }

    /// Everything waiting to play after the current song.
    /// nil when Spotify couldn't be asked (so the screen keeps what it had).
    func queue() async -> [Track]? {
        guard let j = await getJSON("/me/player/queue") else { return nil }
        let rows: [Any] = j["queue"] as? [Any] ?? []
        var out: [Track] = []
        for row in rows {
            guard var t = Track.parse(row) else { continue }
            if let d = row as? [String: Any] { t.uri = Spotify.realURI(d) }
            out.append(t)
        }
        return out
    }

    /// When Spotify swaps a track for another version of it ("relinking"), the silent track can come back
    /// under a different address; this hands back the one we asked for, so it's still recognised.
    static func realURI(_ item: [String: Any]) -> String {
        let uri = item["uri"] as? String ?? ""
        if let from = (item["linked_from"] as? [String: Any])?["uri"] as? String, Silence.isSilence(from) { return from }
        return uri
    }

    /// The next real song (for Cara to talk about), skipping her own clips, adverts and the silent track.
    func nextTrack() async -> Track? {
        guard let q = await queue(), let first = q.first(where: { !Silence.isSilence($0.uri) }), first.isMusic else { return nil }
        return first
    }

    /// One song's details, and whether this account can play it (some songs aren't available everywhere).
    func trackInfo(_ id: String) async -> (track: Track, playable: Bool)? {
        guard let j = await getJSON("/tracks/" + id, ["market": "from_token"]), let t = Track.parse(j) else { return nil }
        return (t, j["is_playable"] as? Bool ?? true)
    }

    /// Finds a short silent track this account can definitely play (Spotify says so for your country),
    /// preferring the usual ones, and skipping any that Spotify refused before.
    /// nil plus `reached: false` means Spotify couldn't be asked right now.
    func findSilence(excluding bad: [String]) async -> (uri: String?, reached: Bool) {
        var reached = false
        var fallback: String? = nil
        for q in ["30 seconds of silence", "silent track", "1 minute of silence"] {
            guard let j = await getJSON("/search", ["q": q, "type": "track", "limit": "10", "market": "from_token"]) else { continue }
            reached = true
            let rows = (j["tracks"] as? [String: Any])?["items"] as? [[String: Any]] ?? []
            var found: [(uri: String, sure: Bool)] = []
            for row in rows {
                guard let t = Track.parse(row), !t.uri.isEmpty, !bad.contains(t.uri) else { continue }
                let name = t.title.lowercased()
                let looksSilent = name.contains("silen") && (name.contains("second") || name.contains("minute") || name.contains("silent track"))
                guard looksSilent, t.durationMs >= 20000, t.durationMs <= 150000 else { continue }
                let playable = row["is_playable"] as? Bool
                if playable == false { continue }
                found.append((t.uri, playable == true))
            }
            if let known = found.first(where: { f in f.sure && Silence.candidates.contains(f.uri) }) { return (known.uri, true) }
            if let sure = found.first(where: { $0.sure }) { return (sure.uri, true) }
            if fallback == nil { fallback = found.first?.uri }
        }
        return (fallback, reached)
    }

    func devices() async -> [Device] {
        guard let j = await getJSON("/me/player/devices") else { return [] }
        return (j["devices"] as? [Any] ?? []).compactMap { Device.parse($0) }
    }

    /// This phone's Spotify device (type "Smartphone"). The DJ only ever plays here, never on speakers or other devices.
    func phoneDevice() async -> String? {
        let all = await devices()
        let phones = all.filter { $0.type.lowercased() == "smartphone" && !$0.isRestricted }
        return (phones.first(where: { $0.isActive }) ?? phones.first)?.id
    }

    @discardableResult
    func transfer(to id: String) async -> Int {
        await call("PUT", "/me/player", body: jsonBody(["device_ids": [id], "play": true])).status
    }

    /// The name of the album / playlist / artist the music is playing from.
    func contextName(_ uri: String) async -> String? {
        let parts = Station.key(uri).split(separator: ":").map(String.init)
        if parts.last == "collection" { return "Liked Songs" }
        guard parts.count == 3 else { return nil }
        let kind = parts[1], id = parts[2]
        switch kind {
        case "playlist": return (await getJSON("/playlists/" + id, ["fields": "name"]))?["name"] as? String
        case "album": return (await getJSON("/albums/" + id))?["name"] as? String
        case "artist": return (await getJSON("/artists/" + id))?["name"] as? String
        default: return nil
        }
    }

    // MARK: player buttons
    @discardableResult func pause() async -> Int { await call("PUT", "/me/player/pause").status }

    @discardableResult func play(device: String?) async -> Int {
        await call("PUT", "/me/player/play", query: device.map { ["device_id": $0] } ?? [:]).status
    }

    /// Start an album / playlist / artist (optionally at a given song), or a list of songs.
    @discardableResult
    func startPlayback(context: String?, offsetURI: String? = nil, position: Int? = nil, uris: [String]? = nil, device: String?) async -> Int {
        var obj: [String: Any] = [:]
        if let c = context { obj["context_uri"] = c }
        if let u = uris { obj["uris"] = u }
        if let o = offsetURI { obj["offset"] = ["uri": o] }
        else if let p = position { obj["offset"] = ["position": p] }
        return await call("PUT", "/me/player/play", query: device.map { ["device_id": $0] } ?? [:], body: jsonBody(obj)).status
    }

    @discardableResult
    func setShuffle(_ on: Bool, device: String? = nil) async -> Int {
        var q = ["state": on ? "true" : "false"]
        if let d = device { q["device_id"] = d }
        return await call("PUT", "/me/player/shuffle", query: q).status
    }
    @discardableResult func setRepeat(_ mode: String) async -> Int { await call("PUT", "/me/player/repeat", query: ["state": mode]).status }
    @discardableResult func seek(_ ms: Int) async -> Int { await call("PUT", "/me/player/seek", query: ["position_ms": String(ms)]).status }
    @discardableResult func skipNext() async -> Int { await call("POST", "/me/player/next").status }
    @discardableResult func skipPrevious() async -> Int { await call("POST", "/me/player/previous").status }

    @discardableResult
    func addToQueue(_ uri: String, device: String?) async -> Int {
        var q = ["uri": uri]
        if let d = device { q["device_id"] = d }
        return await call("POST", "/me/player/queue", query: q).status
    }

    // MARK: you and your library
    func me() async -> UserProfile? {
        guard let j = await getJSON("/me") else { return nil }
        var u = UserProfile()
        u.id = j["id"] as? String ?? ""
        u.name = j["display_name"] as? String ?? u.id
        u.image = Img.pick(j["images"]).mid
        return u
    }

    func myPlaylists(offset: Int) async -> (items: [Playlist], total: Int)? {
        guard let j = await getJSON("/me/playlists", ["limit": "50", "offset": String(offset)]) else { return nil }
        let items = (j["items"] as? [Any] ?? []).compactMap { Playlist.parse($0) }
        return (items, j["total"] as? Int ?? items.count)
    }

    func savedTracks(offset: Int) async -> (items: [Track], total: Int)? {
        guard let j = await getJSON("/me/tracks", ["limit": "50", "offset": String(offset)]) else { return nil }
        let rows = j["items"] as? [[String: Any]] ?? []
        let items = rows.compactMap { Track.parse($0["track"]) }
        return (items, j["total"] as? Int ?? items.count)
    }

    func savedAlbums(offset: Int) async -> (items: [Album], total: Int)? {
        guard let j = await getJSON("/me/albums", ["limit": "50", "offset": String(offset)]) else { return nil }
        let rows = j["items"] as? [[String: Any]] ?? []
        let items = rows.compactMap { Album.parse($0["album"]) }
        return (items, j["total"] as? Int ?? items.count)
    }

    func followedArtists(after: String?) async -> (items: [Artist], next: String?)? {
        var q = ["type": "artist", "limit": "50"]
        if let a = after { q["after"] = a }
        guard let j = await getJSON("/me/following", q), let page = j["artists"] as? [String: Any] else { return nil }
        let items = (page["items"] as? [Any] ?? []).compactMap { Artist.parse($0) }
        let next = (page["cursors"] as? [String: Any])?["after"] as? String
        return (items, next)
    }

    func topTracks(range: String = "short_term") async -> [Track] {
        guard let j = await getJSON("/me/top/tracks", ["limit": "20", "time_range": range]) else { return [] }
        return (j["items"] as? [Any] ?? []).compactMap { Track.parse($0) }
    }

    func topArtists(range: String = "medium_term") async -> [Artist] {
        guard let j = await getJSON("/me/top/artists", ["limit": "20", "time_range": range]) else { return [] }
        return (j["items"] as? [Any] ?? []).compactMap { Artist.parse($0) }
    }

    func recentlyPlayed() async -> [Track] {
        guard let j = await getJSON("/me/player/recently-played", ["limit": "50"]) else { return [] }
        let rows = j["items"] as? [[String: Any]] ?? []
        return rows.compactMap { Track.parse($0["track"]) }
    }

    /// Are these songs / albums / artists / playlists in your library? (40 at a time at most)
    func contains(_ uris: [String]) async -> [Bool]? {
        let list = Array(uris.filter { !$0.isEmpty }.prefix(40))
        if list.isEmpty { return [] }
        let r = await call("GET", "/me/library/contains", query: ["uris": list.joined(separator: ",")])
        guard r.status == 200 else { return nil }
        return (try? JSONSerialization.jsonObject(with: r.data)) as? [Bool]
    }

    /// Like a song, save an album, follow an artist or playlist.
    func save(_ uris: [String]) async -> Bool {
        let list = Array(uris.filter { !$0.isEmpty }.prefix(40))
        if list.isEmpty { return false }
        let r = await call("PUT", "/me/library", query: ["uris": list.joined(separator: ",")])
        return r.status >= 200 && r.status < 300
    }

    func remove(_ uris: [String]) async -> Bool {
        let list = Array(uris.filter { !$0.isEmpty }.prefix(40))
        if list.isEmpty { return false }
        let r = await call("DELETE", "/me/library", query: ["uris": list.joined(separator: ",")])
        return r.status >= 200 && r.status < 300
    }

    func createPlaylist(_ name: String) async -> Playlist? {
        let r = await call("POST", "/me/playlists", body: jsonBody(["name": name, "public": false, "description": "Made with Cara DJ"]))
        guard r.status == 200 || r.status == 201 else { return nil }
        return Playlist.parse(try? JSONSerialization.jsonObject(with: r.data))
    }

    func addToPlaylist(_ id: String, uris: [String]) async -> Bool {
        let r = await call("POST", "/playlists/" + id + "/items", body: jsonBody(["uris": uris]))
        return r.status == 200 || r.status == 201
    }

    // MARK: albums, artists, playlists
    func album(_ id: String) async -> (album: Album, tracks: [Track], total: Int, copyright: String)? {
        guard let j = await getJSON("/albums/" + id), let al = Album.parse(j) else { return nil }
        let page = j["tracks"] as? [String: Any]
        let tracks = (page?["items"] as? [Any] ?? []).compactMap { Track.parse($0, album: al) }
        let total = page?["total"] as? Int ?? tracks.count
        let copyright = ((j["copyrights"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        return (al, tracks, total, copyright)
    }

    func albumTracks(_ al: Album, offset: Int) async -> [Track] {
        guard let j = await getJSON("/albums/" + al.id + "/tracks", ["limit": "50", "offset": String(offset)]) else { return [] }
        return (j["items"] as? [Any] ?? []).compactMap { Track.parse($0, album: al) }
    }

    func artist(_ id: String) async -> Artist? {
        Artist.parse(await getJSON("/artists/" + id))
    }

    /// Spotify only hands these out 10 at a time now.
    func artistAlbums(_ id: String, groups: String, offset: Int = 0) async -> [Album] {
        guard let j = await getJSON("/artists/" + id + "/albums", ["include_groups": groups, "limit": "10", "offset": String(offset)]) else { return [] }
        return (j["items"] as? [Any] ?? []).compactMap { Album.parse($0) }
    }

    /// Spotify took away "Top Songs" for apps like this one, so search for the artist's best-known songs instead.
    func artistTopTracks(_ artist: Artist) async -> [Track] {
        guard let j = await getJSON("/search", ["q": "artist:\"\(artist.name)\"", "type": "track", "limit": "10"]) else { return [] }
        let items = ((j["tracks"] as? [String: Any])?["items"] as? [Any] ?? []).compactMap { Track.parse($0) }
        let theirs = items.filter { $0.artistIDs.contains(artist.id) }
        return theirs.isEmpty ? items : theirs
    }

    /// A playlist. Spotify only lists the songs of playlists you made or collaborate on.
    func playlist(_ id: String) async -> (playlist: Playlist, tracks: [Track], total: Int, canList: Bool, rows: Int)? {
        guard let j = await getJSON("/playlists/" + id), let p = Playlist.parse(j) else { return nil }
        let page = (j["items"] as? [String: Any]) ?? (j["tracks"] as? [String: Any])
        let rows = page?["items"] as? [[String: Any]]
        let tracks = (rows ?? []).compactMap { Track.parse($0["item"] ?? $0["track"]) }
        let total = page?["total"] as? Int ?? p.total
        return (p, tracks, total, rows != nil, rows?.count ?? 0)
    }

    /// The next page of a playlist. `rows` is how many entries Spotify sent (some may be podcasts or gone, and get skipped).
    func playlistItems(_ id: String, offset: Int) async -> (tracks: [Track], rows: Int)? {
        guard let j = await getJSON("/playlists/" + id + "/items", ["limit": "50", "offset": String(offset)]) else { return nil }
        let rows = j["items"] as? [[String: Any]] ?? []
        return (rows.compactMap { Track.parse($0["item"] ?? $0["track"]) }, rows.count)
    }

    // MARK: search
    func search(_ q: String, types: [String], offset: Int = 0) async -> SearchResults? {
        guard let j = await getJSON("/search", ["q": q, "type": types.joined(separator: ","), "limit": "10", "offset": String(offset)]) else { return nil }
        var r = SearchResults()
        if let t = j["tracks"] as? [String: Any] {
            r.tracks = (t["items"] as? [Any] ?? []).compactMap { Track.parse($0) }
            r.totals["track"] = t["total"] as? Int ?? 0
        }
        if let t = j["artists"] as? [String: Any] {
            r.artists = (t["items"] as? [Any] ?? []).compactMap { Artist.parse($0) }
            r.totals["artist"] = t["total"] as? Int ?? 0
        }
        if let t = j["albums"] as? [String: Any] {
            r.albums = (t["items"] as? [Any] ?? []).compactMap { Album.parse($0) }
            r.totals["album"] = t["total"] as? Int ?? 0
        }
        if let t = j["playlists"] as? [String: Any] {
            r.playlists = (t["items"] as? [Any] ?? []).compactMap { Playlist.parse($0) }
            r.totals["playlist"] = t["total"] as? Int ?? 0
        }
        return r
    }
}
