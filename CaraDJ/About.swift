import SwiftUI
import Observation

/// "About this song": the story of the song and the artist (from Wikipedia), plus the credits.
@MainActor
@Observable
final class AboutStore {
    var song = ""
    var bio = ""
    var genres: [String] = []
    var artistImage = ""
    var copyright = ""
    var ready = false
    private var key = ""

    func load(_ t: Track?) async {
        guard let t = t, !t.uri.isEmpty, t.uri != key else { return }
        key = t.uri
        ready = false; song = ""; bio = ""; genres = []; artistImage = ""; copyright = ""
        let sp = Spotify.shared
        var clean = t.title
        if let r = clean.range(of: #"\s*[\(\[-].*$"#, options: .regularExpression) { clean.removeSubrange(r) }
        clean = clean.trimmingCharacters(in: .whitespaces)
        if clean.isEmpty { clean = t.title }
        let first = t.artist.split(separator: " ").first.map(String.init) ?? t.artist

        async let songTxt = wikiLookup("\"\(clean)\" \(t.artist) song", must: [clean, first])
        async let bioTxt = wikiLookup("\(t.artist) musician band singer", must: [t.artist])
        async let artistR = sp.call("GET", t.artistID.isEmpty ? "/me" : "/artists/" + t.artistID)
        async let albumR = sp.call("GET", t.albumID.isEmpty ? "/me" : "/albums/" + t.albumID)
        let (s, b, a, al) = await (songTxt, bioTxt, artistR, albumR)
        guard key == t.uri else { return }

        bio = b ?? ""
        song = (s ?? "") == bio ? "" : (s ?? "")
        if !t.artistID.isEmpty, a.status == 200, let j = (try? JSONSerialization.jsonObject(with: a.data)) as? [String: Any] {
            genres = Array((j["genres"] as? [String] ?? []).prefix(4))
            artistImage = Img.pick(j["images"]).large
        }
        if !t.albumID.isEmpty, al.status == 200, let j = (try? JSONSerialization.jsonObject(with: al.data)) as? [String: Any] {
            copyright = ((j["copyrights"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
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
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
