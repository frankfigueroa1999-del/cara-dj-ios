import Foundation

// MARK: - Picking the right picture size out of Spotify's image lists
enum Img {
    /// (biggest picture, a ~300px one for lists and small cards)
    static func pick(_ any: Any?) -> (large: String, mid: String) {
        var found: [(url: String, width: Int)] = []
        for item in (any as? [[String: Any]] ?? []) {
            if let u = item["url"] as? String { found.append((u, item["width"] as? Int ?? 0)) }
        }
        found.sort { $0.width > $1.width }
        guard let first = found.first else { return ("", "") }
        var mid = first.url
        for f in found where f.width >= 250 { mid = f.url }
        return (first.url, mid)
    }
}

// MARK: - A song
struct Track: Identifiable, Hashable, Codable {
    var sid: String = ""
    var uri: String = ""
    var title: String = ""
    var artist: String = ""
    var artists: [String] = []
    var artistID: String = ""
    var artistIDs: [String] = []
    var album: String = ""
    var albumID: String = ""
    var year: String = ""
    var release: String = ""
    var art: String = ""
    var artMid: String = ""
    var durationMs: Int = 0
    var explicit: Bool = false
    var isLocal: Bool = false
    var trackNumber: Int = 0

    var id: String { uri.isEmpty ? title + "|" + artist : uri }
    var describe: String { "\(title) by \(artist)" }
    var artistLine: String { artists.isEmpty ? artist : artists.joined(separator: ", ") }
    var shareURL: URL? { sid.isEmpty ? nil : URL(string: "https://open.spotify.com/track/" + sid) }

    /// Cara clips, station adverts and jingles in your playlist are not songs she should talk about.
    static let notMusic = ["cara", "non stop pop", "non-stop", "advert", "commercial", "sponsor", "jingle"]
    var isMusic: Bool {
        if isLocal || artist.isEmpty || Silence.isSilence(uri) { return false }
        let blob = ([title, album] + artists).joined(separator: " ").lowercased()
        return !Track.notMusic.contains(where: { blob.contains($0) })
    }

    var albumRef: Album {
        var a = Album()
        a.id = albumID
        a.uri = albumID.isEmpty ? "" : "spotify:album:" + albumID
        a.name = album
        a.artist = artist
        a.artistID = artistID
        a.art = art
        a.artMid = artMid
        a.year = year
        a.release = release
        return a
    }
    var artistRef: Artist {
        var a = Artist()
        a.id = artistID
        a.uri = artistID.isEmpty ? "" : "spotify:artist:" + artistID
        a.name = artist
        return a
    }

    static func parse(_ any: Any?, album: Album? = nil) -> Track? {
        guard let d = any as? [String: Any], let name = d["name"] as? String else { return nil }
        if let type = d["type"] as? String, type != "track" { return nil }
        var t = Track()
        t.title = name
        t.uri = d["uri"] as? String ?? ""
        t.sid = d["id"] as? String ?? ""
        let arts = d["artists"] as? [[String: Any]] ?? []
        for a in arts {
            if let n = a["name"] as? String { t.artists.append(n) }
            if let i = a["id"] as? String { t.artistIDs.append(i) }
        }
        t.artist = t.artists.first ?? ""
        t.artistID = t.artistIDs.first ?? ""
        if let al = d["album"] as? [String: Any] {
            t.album = al["name"] as? String ?? ""
            t.albumID = al["id"] as? String ?? ""
            t.release = al["release_date"] as? String ?? ""
            let im = Img.pick(al["images"])
            t.art = im.large
            t.artMid = im.mid
        } else if let al = album {
            t.album = al.name
            t.albumID = al.id
            t.release = al.release
            t.art = al.art
            t.artMid = al.artMid
        }
        t.year = String(t.release.prefix(4))
        t.durationMs = d["duration_ms"] as? Int ?? 0
        t.explicit = d["explicit"] as? Bool ?? false
        t.isLocal = d["is_local"] as? Bool ?? false
        t.trackNumber = d["track_number"] as? Int ?? 0
        return t
    }
}

// MARK: - The silent track behind silent breaks
/// Right before a silent break the app lines up a short silent track in Spotify, and Cara talks over it.
/// The music really stops, yet Spotify never pauses (so it can't fall asleep in the background),
/// and as soon as she's done the app skips on to the next song.
enum Silence {
    /// Short silent tracks on Spotify, tried in this order.
    static let candidates = [
        "spotify:track:4KPym5ynDxNeAsgMqubgAt",     // "30 Seconds of Silence! (Silent Track)"
        "spotify:track:0OBG3xvk92jhezHTuyrnSo",     // "30 Seconds of Silence (Reflexion)"
    ]
    /// The made-up "cover" address for Cara's own artwork.
    static let logo = "cara:logo"

    static func isSilence(_ uri: String) -> Bool {
        if uri.isEmpty { return false }
        let cfg = Config.shared
        return candidates.contains(uri) || uri == cfg.silenceURI || cfg.silenceBad.contains(uri)
    }

    /// What the screens show while it plays: Cara on the air, not "30 Seconds of Silence".
    static func caraItem(uri: String, durationMs: Int, station: String = Station.fallback) -> Track {
        var t = Track()
        t.uri = uri
        t.title = "Cara"
        t.artist = Station.full(station)
        t.artists = [t.artist]
        t.album = "On the air"
        t.art = logo
        t.artMid = logo
        t.durationMs = durationMs
        t.isLocal = true          // nothing to like, share or open
        return t
    }
}

// MARK: - The station's name
/// The station takes the name of whatever's playing: the playlist, album or artist (or Liked Songs).
/// Non Stop Pop is only the fallback, for when nothing nameable is playing (and it's where Cara started out, back in Los Santos).
enum Station {
    static let fallback = "Non Stop Pop"

    /// A name that looks right on screen and sounds right out loud: no emojis or odd symbols, not too long.
    static func clean(_ raw: String) -> String {
        var out = ""
        for ch in raw {
            let emoji = ch.unicodeScalars.contains { s in
                s.properties.isEmojiPresentation || (s.properties.isEmoji && s.value > 0xFF) || s.value == 0xFE0F || s.value == 0x200D
            }
            if !emoji && (ch.isLetter || ch.isNumber || "'’&!?.,-+:/()$#@%".contains(ch)) {
                out.append(ch == "’" ? "'" : ch)
            } else {
                out.append(" ")
            }
        }
        var name = out.split(whereSeparator: { $0 == " " }).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " -:/.,+"))
        if name.count > 40 {
            var kept: [String] = []
            for w in name.split(separator: " ").map(String.init) {
                if (kept + [w]).joined(separator: " ").count > 36 { break }
                kept.append(w)
            }
            name = kept.isEmpty ? String(name.prefix(36)) : kept.joined(separator: " ")
        }
        return name.contains(where: { $0.isLetter || $0.isNumber }) ? name : ""
    }

    /// On air: "Late Night Drives" becomes "Late Night Drives FM"; names that already sound like a station keep theirs.
    static func full(_ name: String) -> String {
        let last = name.split(separator: " ").last.map { $0.lowercased() } ?? ""
        return ["fm", "am", "radio", "station"].contains(last) ? name : name + " FM"
    }

    /// One spelling per playlist / album / artist ("spotify:user:x:playlist:ID" and "spotify:playlist:ID" are the same).
    static func key(_ uri: String) -> String {
        let parts = uri.split(separator: ":").map(String.init)
        if parts.contains("collection") { return "spotify:collection" }
        for kind in ["playlist", "album", "artist", "show"] {
            if let i = parts.firstIndex(of: kind), i + 1 < parts.count { return "spotify:\(kind):\(parts[i + 1])" }
        }
        return uri
    }

    /// What kind of thing the station's named after: "playlist", "album", "artist", "collection" or "".
    static func kind(_ uri: String) -> String {
        let k = key(uri)
        if k == "spotify:collection" { return "collection" }
        let parts = k.split(separator: ":").map(String.init)
        return parts.count == 3 ? parts[1] : ""
    }
}

// MARK: - An album
struct Album: Identifiable, Hashable, Codable {
    var id: String = ""
    var uri: String = ""
    var name: String = ""
    var artist: String = ""
    var artistID: String = ""
    var art: String = ""
    var artMid: String = ""
    var year: String = ""
    var release: String = ""
    var type: String = "album"
    var totalTracks: Int = 0

    var typeLabel: String {
        switch type {
        case "single": return totalTracks > 3 ? "EP" : "Single"
        case "compilation": return "Compilation"
        default: return "Album"
        }
    }
    var shareURL: URL? { id.isEmpty ? nil : URL(string: "https://open.spotify.com/album/" + id) }

    static func parse(_ any: Any?) -> Album? {
        guard let d = any as? [String: Any], let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
        var a = Album()
        a.id = id
        a.uri = d["uri"] as? String ?? "spotify:album:" + id
        a.name = name
        let arts = d["artists"] as? [[String: Any]] ?? []
        a.artist = arts.compactMap { $0["name"] as? String }.joined(separator: ", ")
        a.artistID = arts.first?["id"] as? String ?? ""
        let im = Img.pick(d["images"])
        a.art = im.large
        a.artMid = im.mid
        a.release = d["release_date"] as? String ?? ""
        a.year = String(a.release.prefix(4))
        a.type = (d["album_type"] as? String ?? "album").lowercased()
        a.totalTracks = d["total_tracks"] as? Int ?? 0
        return a
    }
}

// MARK: - An artist
struct Artist: Identifiable, Hashable, Codable {
    var id: String = ""
    var uri: String = ""
    var name: String = ""
    var image: String = ""
    var imageMid: String = ""
    var genres: [String] = []

    var shareURL: URL? { id.isEmpty ? nil : URL(string: "https://open.spotify.com/artist/" + id) }

    static func parse(_ any: Any?) -> Artist? {
        guard let d = any as? [String: Any], let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
        var a = Artist()
        a.id = id
        a.uri = d["uri"] as? String ?? "spotify:artist:" + id
        a.name = name
        let im = Img.pick(d["images"])
        a.image = im.large
        a.imageMid = im.mid
        a.genres = d["genres"] as? [String] ?? []
        return a
    }
}

// MARK: - A playlist
struct Playlist: Identifiable, Hashable, Codable {
    var id: String = ""
    var uri: String = ""
    var name: String = ""
    var owner: String = ""
    var ownerID: String = ""
    var image: String = ""
    var imageMid: String = ""
    var about: String = ""
    var total: Int = 0
    var collaborative: Bool = false

    var shareURL: URL? { id.isEmpty ? nil : URL(string: "https://open.spotify.com/playlist/" + id) }

    static func parse(_ any: Any?) -> Playlist? {
        guard let d = any as? [String: Any], let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
        var p = Playlist()
        p.id = id
        p.uri = d["uri"] as? String ?? "spotify:playlist:" + id
        p.name = name
        if let o = d["owner"] as? [String: Any] {
            p.ownerID = o["id"] as? String ?? ""
            p.owner = o["display_name"] as? String ?? p.ownerID
        }
        let im = Img.pick(d["images"])
        p.image = im.large
        p.imageMid = im.mid
        p.about = Playlist.plain(d["description"] as? String ?? "")
        // Spotify renamed "tracks" to "items" in 2026; read whichever is there
        let ref = (d["items"] as? [String: Any]) ?? (d["tracks"] as? [String: Any])
        p.total = ref?["total"] as? Int ?? 0
        p.collaborative = d["collaborative"] as? Bool ?? false
        return p
    }

    /// Playlist descriptions come with HTML bits in them.
    static func plain(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&quot;": "\"", "&#x27;": "'", "&#39;": "'", "&lt;": "<", "&gt;": ">", "&#x2F;": "/", "&nbsp;": " "]
        for (k, v) in entities { t = t.replacingOccurrences(of: k, with: v) }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Somewhere Spotify can play
struct Device: Identifiable, Hashable {
    var id: String = ""
    var name: String = ""
    var type: String = ""
    var isActive: Bool = false
    var isRestricted: Bool = false

    var symbol: String {
        switch type.lowercased() {
        case "smartphone": return "iphone"
        case "computer": return "laptopcomputer"
        case "tablet": return "ipad"
        case "speaker": return "hifispeaker.fill"
        case "tv": return "tv"
        case "automobile": return "car.fill"
        case "gameconsole": return "gamecontroller.fill"
        case "castvideo", "castaudio": return "tv.and.hifispeaker.fill"
        default: return "speaker.wave.2.fill"
        }
    }

    static func parse(_ any: Any?) -> Device? {
        guard let d = any as? [String: Any], let id = d["id"] as? String else { return nil }
        var v = Device()
        v.id = id
        v.name = d["name"] as? String ?? "Device"
        v.type = d["type"] as? String ?? ""
        v.isActive = d["is_active"] as? Bool ?? false
        v.isRestricted = d["is_restricted"] as? Bool ?? false
        return v
    }
}

// MARK: - You
struct UserProfile: Codable, Hashable {
    var id: String = ""
    var name: String = ""
    var image: String = ""
}

// MARK: - What's playing right now
struct Playback {
    var isPlaying = false
    var hasItem = false
    var uri = ""
    /// What's playing, for the screen (songs, Cara clips, adverts, everything).
    var item: Track? = nil
    /// The same thing, but only when it's a real song: the DJ never talks about her own clips or adverts.
    var track: Track? = nil
    var durationMs = 0
    var progressMs = 0
    var stamp = Date()
    var deviceID: String? = nil
    var deviceName = ""
    var deviceType = ""
    var contextURI = ""
    var shuffle = false
    var repeatMode = "off"

    /// Milliseconds left in the song, estimated from the last check.
    var remainingMs: Int {
        guard isPlaying else { return Int.max }
        let elapsed = Int(Date().timeIntervalSince(stamp) * 1000)
        return durationMs - (progressMs + elapsed)
    }
    var currentProgressMs: Int {
        let elapsed = isPlaying ? Int(Date().timeIntervalSince(stamp) * 1000) : 0
        return min(durationMs, progressMs + elapsed)
    }
    var onThisPhone: Bool { deviceType.isEmpty || deviceType.lowercased() == "smartphone" }
}

// MARK: - Search results
struct SearchResults {
    var tracks: [Track] = []
    var artists: [Artist] = []
    var albums: [Album] = []
    var playlists: [Playlist] = []
    var totals: [String: Int] = [:]
    var isEmpty: Bool { tracks.isEmpty && artists.isEmpty && albums.isEmpty && playlists.isEmpty }
}

// MARK: - Browse tiles on the Search page (Spotify no longer shares its own categories with apps like this)
struct Genre: Identifiable, Hashable {
    var id: String
    var title: String
    var trackQuery: String
    var playlistQuery: String
    var symbol: String
    var hue: Double

    static let all: [Genre] = [
        Genre(id: "pop", title: "Pop", trackQuery: "genre:pop", playlistQuery: "pop hits", symbol: "sparkles", hue: 0.93),
        Genre(id: "hiphop", title: "Hip-Hop", trackQuery: "genre:hip-hop", playlistQuery: "hip hop", symbol: "music.mic", hue: 0.08),
        Genre(id: "dance", title: "Dance", trackQuery: "genre:dance", playlistQuery: "dance hits", symbol: "figure.dance", hue: 0.78),
        Genre(id: "rnb", title: "R&B", trackQuery: "genre:r-n-b", playlistQuery: "r&b", symbol: "heart.fill", hue: 0.62),
        Genre(id: "rock", title: "Rock", trackQuery: "genre:rock", playlistQuery: "rock classics", symbol: "guitars.fill", hue: 0.02),
        Genre(id: "indie", title: "Indie", trackQuery: "genre:indie", playlistQuery: "indie", symbol: "leaf.fill", hue: 0.33),
        Genre(id: "latin", title: "Latin", trackQuery: "genre:latin", playlistQuery: "latin hits", symbol: "sun.max.fill", hue: 0.12),
        Genre(id: "kpop", title: "K-Pop", trackQuery: "genre:k-pop", playlistQuery: "k-pop", symbol: "star.fill", hue: 0.85),
        Genre(id: "country", title: "Country", trackQuery: "genre:country", playlistQuery: "country hits", symbol: "music.quarternote.3", hue: 0.1),
        Genre(id: "2000s", title: "2000s", trackQuery: "year:2000-2009", playlistQuery: "2000s pop", symbol: "opticaldisc.fill", hue: 0.55),
        Genre(id: "2010s", title: "2010s", trackQuery: "year:2010-2019", playlistQuery: "2010s hits", symbol: "headphones", hue: 0.7),
        Genre(id: "chill", title: "Chill", trackQuery: "genre:chill", playlistQuery: "chill vibes", symbol: "moon.stars.fill", hue: 0.5),
        Genre(id: "workout", title: "Workout", trackQuery: "genre:work-out", playlistQuery: "workout", symbol: "flame.fill", hue: 0.04),
        Genre(id: "party", title: "Party", trackQuery: "genre:party", playlistQuery: "party", symbol: "balloon.2.fill", hue: 0.9),
    ]
}

// MARK: - Little helpers for times
func formatClock(_ ms: Int) -> String {
    let s = max(0, ms / 1000)
    return "\(s / 60):" + String(format: "%02d", s % 60)
}

func formatLength(_ ms: Int) -> String {
    let mins = max(0, ms / 60000)
    if mins >= 60 { return "\(mins / 60) hr \(mins % 60) min" }
    return "\(mins) min"
}

func prettyDate(_ s: String) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    guard let d = f.date(from: s) else { return s }
    let o = DateFormatter()
    o.dateStyle = .long
    return o.string(from: d)
}
