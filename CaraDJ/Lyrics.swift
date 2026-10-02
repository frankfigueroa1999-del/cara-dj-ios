import Foundation
import Observation

struct LyricLine: Identifiable {
    let id: Int
    let timeMs: Int
    let text: String
}

/// Looks up lyrics for the current song on LRCLIB (a free, open lyrics database; no key needed).
@MainActor
@Observable
final class LyricsStore {
    var lines: [LyricLine] = []
    var plain: String = ""
    var status: String = ""
    private var loadedKey = ""

    var hasSynced: Bool { !lines.isEmpty }
    var hasAny: Bool { !lines.isEmpty || !plain.isEmpty }

    func load(_ track: Track?, durationMs: Int) async {
        guard let t = track, t.isMusic else {
            loadedKey = ""; lines = []; plain = ""
            let cara = track.map { Silence.isSilence($0.uri) } ?? false
            status = track == nil ? "Nothing playing." : (cara ? "Cara's on the air." : "No lyrics for this one.")
            return
        }
        let key = t.title + "|" + t.artist
        if key == loadedKey { return }
        loadedKey = key
        lines = []; plain = ""; status = "Finding lyrics..."

        var synced = ""
        var unsynced = ""
        let secs = max(1, durationMs / 1000)
        if let obj = await fetchObject("https://lrclib.net/api/get", [
            "track_name": t.title, "artist_name": t.artist, "album_name": t.album, "duration": String(secs)
        ]) {
            synced = obj["syncedLyrics"] as? String ?? ""
            unsynced = obj["plainLyrics"] as? String ?? ""
        }
        if synced.isEmpty && unsynced.isEmpty {
            if let arr = await fetchArray("https://lrclib.net/api/search", ["track_name": t.title, "artist_name": t.artist]) {
                for item in arr {
                    let s = item["syncedLyrics"] as? String ?? ""
                    let p = item["plainLyrics"] as? String ?? ""
                    if !s.isEmpty { synced = s; break }
                    if unsynced.isEmpty && !p.isEmpty { unsynced = p }
                }
            }
        }
        if key != loadedKey { return }          // the song changed while we were looking
        if !synced.isEmpty {
            lines = LyricsStore.parse(synced)
            status = ""
        } else if !unsynced.isEmpty {
            plain = unsynced
            status = ""
        } else {
            status = "No lyrics found for this song."
        }
    }

    /// Which line is being sung at this moment (-1 before the first one).
    func index(at ms: Int) -> Int {
        let pos = ms + 250
        var lo = 0, hi = lines.count - 1, found = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].timeMs <= pos { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return found
    }

    private func fetchObject(_ base: String, _ q: [String: String]) async -> [String: Any]? {
        guard let url = LyricsStore.url(base, q), let data = await fetchData(url, timeout: 12) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func fetchArray(_ base: String, _ q: [String: String]) async -> [[String: Any]]? {
        guard let url = LyricsStore.url(base, q), let data = await fetchData(url, timeout: 12) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
    }

    private static func url(_ base: String, _ q: [String: String]) -> URL? {
        var c = URLComponents(string: base)
        var items: [URLQueryItem] = []
        for (k, v) in q { items.append(URLQueryItem(name: k, value: v)) }
        c?.queryItems = items
        return c?.url
    }

    /// Turns "[01:23.45] some words" lines into timed lines.
    static func parse(_ lrc: String) -> [LyricLine] {
        var out: [(Int, String)] = []
        for raw in lrc.components(separatedBy: "\n") {
            var rest = Substring(raw)
            var stamps: [Int] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let inner = rest[rest.index(after: rest.startIndex)..<close]
                let parts = inner.split(separator: ":")
                if parts.count == 2, let m = Int(parts[0]), let s = Double(parts[1]) {
                    stamps.append(m * 60000 + Int(s * 1000))
                }
                rest = rest[rest.index(after: close)...]
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            for ms in stamps { out.append((ms, text)) }
        }
        out.sort { $0.0 < $1.0 }
        var lines: [LyricLine] = []
        for (i, item) in out.enumerated() { lines.append(LyricLine(id: i, timeMs: item.0, text: item.1)) }
        return lines
    }
}

/// A song's lyrics as plain text, so the DJs can tell what it's about when they read the room.
/// They're never shown, read out or quoted on air. Looked up once per song (LRCLIB, like the player).
@MainActor
enum SongWords {
    private static var cache: [String: String] = [:]          // "title|artist" -> lyrics ("" when there are none)

    static func text(for t: Track) async -> String? {
        guard t.isMusic else { return nil }
        let key = t.title + "|" + t.artist
        if let c = cache[key] { return c.isEmpty ? nil : c }
        var synced = ""
        var plain = ""
        let secs = max(1, t.durationMs / 1000)
        if let obj = await object("https://lrclib.net/api/get", ["track_name": t.title, "artist_name": t.artist, "album_name": t.album, "duration": String(secs)]) {
            synced = obj["syncedLyrics"] as? String ?? ""
            plain = obj["plainLyrics"] as? String ?? ""
        }
        if synced.isEmpty && plain.isEmpty, let arr = await array("https://lrclib.net/api/search", ["track_name": t.title, "artist_name": t.artist]) {
            for item in arr {
                let p = item["plainLyrics"] as? String ?? ""
                let s = item["syncedLyrics"] as? String ?? ""
                if !p.isEmpty { plain = p; break }
                if synced.isEmpty && !s.isEmpty { synced = s }
            }
        }
        let out = !plain.isEmpty ? plain : LyricsStore.parse(synced).map { $0.text }.filter { !$0.isEmpty }.joined(separator: "\n")
        cache[key] = out
        if cache.count > 200 { cache.removeAll() }
        return out.isEmpty ? nil : out
    }

    private static func url(_ base: String, _ q: [String: String]) -> URL? {
        var c = URLComponents(string: base)
        c?.queryItems = q.map { URLQueryItem(name: $0.key, value: $0.value) }
        return c?.url
    }

    private static func object(_ base: String, _ q: [String: String]) async -> [String: Any]? {
        guard let u = url(base, q), let data = await fetchData(u, timeout: 8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func array(_ base: String, _ q: [String: String]) async -> [[String: Any]]? {
        guard let u = url(base, q), let data = await fetchData(u, timeout: 8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
    }
}
