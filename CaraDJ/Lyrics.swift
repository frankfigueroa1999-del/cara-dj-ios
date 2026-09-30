import Foundation
import SwiftUI

struct LyricLine: Identifiable {
    let id: Int
    let timeMs: Int
    let text: String
}

/// Looks up lyrics for the current song on LRCLIB (a free, open lyrics database; no key needed).
@MainActor
final class LyricsStore: ObservableObject {
    @Published var lines: [LyricLine] = []
    @Published var plain: String = ""
    @Published var status: String = ""
    private var loadedKey = ""

    func load(_ track: Track?, durationMs: Int) async {
        guard let t = track else {
            loadedKey = ""; lines = []; plain = ""; status = "Nothing playing."
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
