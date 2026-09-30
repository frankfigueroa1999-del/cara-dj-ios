import SwiftUI

/// The cards under the lyrics: about the song, about the artist, popular tracks, credits.
struct PopTrack: Identifiable { let id: String; let name: String; let artists: String; let uri: String; let art: String }

@MainActor
final class AboutStore: ObservableObject {
    @Published var song = ""
    @Published var bio = ""
    @Published var followers = 0
    @Published var genres: [String] = []
    @Published var artistImage = ""
    @Published var artistURL = ""
    @Published var label = ""
    @Published var copyright = ""
    @Published var pop: [PopTrack] = []
    @Published var ready = false
    private var key = ""

    private func fetch(_ sp: Spotify, _ path: String?, _ q: [String: String]) async -> (status: Int, data: Data)? {
        guard let path = path else { return nil }
        return await sp.call("GET", path, query: q)
    }

    func load(_ t: Track?) async {
        guard let t = t, !t.uri.isEmpty, t.uri != key else { return }
        key = t.uri
        ready = false; song = ""; bio = ""; followers = 0; genres = []; artistImage = ""; artistURL = ""; label = ""; copyright = ""; pop = []
        let sp = Spotify.shared
        var clean = t.title
        if let r = clean.range(of: #"\s*[\(\[-].*$"#, options: .regularExpression) { clean.removeSubrange(r) }
        clean = clean.trimmingCharacters(in: .whitespaces)
        if clean.isEmpty { clean = t.title }
        let first = t.artist.split(separator: " ").first.map(String.init) ?? t.artist

        async let songTxt = wikiLookup("\"\(clean)\" \(t.artist) song", must: [clean, first])
        async let bioTxt = wikiLookup("\(t.artist) musician band singer", must: [t.artist])
        async let artistR = fetch(sp, t.artistID.isEmpty ? nil : "/artists/" + t.artistID, [:])
        async let albumR = fetch(sp, t.albumID.isEmpty ? nil : "/albums/" + t.albumID, [:])
        async let topR = fetch(sp, t.artistID.isEmpty ? nil : "/artists/" + t.artistID + "/top-tracks", ["market": "US"])
        let (s, b, a, al, top) = await (songTxt, bioTxt, artistR, albumR, topR)
        guard key == t.uri else { return }

        bio = b ?? ""
        song = (s ?? "") == bio ? "" : (s ?? "")
        if let a = a, a.status == 200, let j = try? JSONSerialization.jsonObject(with: a.data) as? [String: Any] {
            followers = (j["followers"] as? [String: Any])?["total"] as? Int ?? 0
            genres = Array((j["genres"] as? [String] ?? []).prefix(4))
            artistImage = ((j["images"] as? [[String: Any]])?.first?["url"] as? String) ?? ""
            artistURL = (j["external_urls"] as? [String: Any])?["spotify"] as? String ?? ""
        }
        if let al = al, al.status == 200, let j = try? JSONSerialization.jsonObject(with: al.data) as? [String: Any] {
            label = j["label"] as? String ?? ""
            copyright = ((j["copyrights"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        }
        if let top = top, top.status == 200, let j = try? JSONSerialization.jsonObject(with: top.data) as? [String: Any] {
            pop = (j["tracks"] as? [[String: Any]] ?? []).prefix(5).compactMap { x in
                guard let id = x["id"] as? String, let n = x["name"] as? String, let u = x["uri"] as? String else { return nil }
                let ar = (x["artists"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.joined(separator: ", ")
                let img = (((x["album"] as? [String: Any])?["images"] as? [[String: Any]])?.last?["url"] as? String) ?? ""
                return PopTrack(id: id, name: n, artists: ar, uri: u, art: img)
            }
        }
        ready = true
    }
}

struct InfoCard<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 18, weight: .bold))
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 12)
    }
}
