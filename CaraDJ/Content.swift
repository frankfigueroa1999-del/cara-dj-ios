import Foundation

// MARK: - Small helpers
func pick<T>(_ a: [T]) -> T { a[Int.random(in: 0..<a.count)] }
func randInt(_ lo: Int, _ hi: Int) -> Int { lo >= hi ? lo : Int.random(in: lo...hi) }

func fetchData(_ url: URL, timeout: TimeInterval = 10) async -> Data? {
    var req = URLRequest(url: url)
    req.timeoutInterval = timeout
    req.setValue("Mozilla/5.0 CaraDJ", forHTTPHeaderField: "User-Agent")
    do {
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 { return nil }
        return data
    } catch { return nil }
}

// MARK: - RSS
private final class RSSParser: NSObject, XMLParserDelegate {
    var titles: [String] = []
    private var inItem = false
    private var inTitle = false
    private var buffer = ""
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        if name == "item" || name == "entry" { inItem = true }
        if inItem && name == "title" { inTitle = true; buffer = "" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if inTitle { buffer += string } }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { if inTitle { buffer += String(data: CDATABlock, encoding: .utf8) ?? "" } }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "title" && inTitle { inTitle = false; titles.append(buffer) }
        if name == "item" || name == "entry" { inItem = false }
    }
}

func cleanTitle(_ t: String) -> String {
    var s = t.trimmingCharacters(in: .whitespacesAndNewlines)
    if let r = s.range(of: #"\s+-\s+[^-]+$"#, options: .regularExpression) { s.removeSubrange(r) }   // drop " - Publisher"
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

let skipWords = ["killed", "dead", "death", "died", "dies", "homicide", "murder", "shooting", "shot", "stabbing", "crash", "fatal",
                 "victim", "suicide", "assault", "abuse", "rape", "arrest", "sentenced", "charged", "trial", "manslaughter", "overdose", "missing",
                 "drown", "wildfire", "evacuat", "measles", "outbreak", "cancer", "massacre", "genocide", "famine"]
let skipRegex = #"\b(?:war|wars|attack|attacks|attacked|bomb|bombs|bombing|terror|terrorist|hostage|hostages|airstrike|airstrikes|invasion|troops|missile|missiles|militant|militants|hamas|gaza|ukraine|russia|israel|iran|election|elections|trump|biden|congress|senate|parliament|protest|protests|riot|riots|refugee|refugees|migrant|migrants|abortion|shutdown|sanctions)\b"#
let gossipSkipRegex = #"\b(?:lawsuit|sues|sued|suing|court|divorce|rehab|hospital|hospitalized|hospitalised|affair|cheating|leak|leaked|nude|naked|racist|sexual|allegations|alleged|accused|custody|restraining|lawsuits|scandal|feud|passes|obituary|tribute|mourning|grief|funeral)\b"#

/// Nothing about anyone dying, being hurt, or being remembered after death. Ever.
let deathRegex = #"\b(?:kill|killed|killing|dead|death|deaths|deadly|die|dies|died|dying|fatal|fatally|fatality|fatalities|passed away|passes away|obituary|obituaries|funeral|memorial|vigil|mourn|mourning|mourners|grief|coroner|autopsy|remains|body|bodies|drowned|drowning|perished|lost (?:his|her|their) life|tragic|tragedy|injured|injuries|injury|hospitalized|crash|crashed|collision|rip)\b"#
func mentionsDeath(_ s: String) -> Bool {
    s.range(of: deathRegex, options: [.regularExpression, .caseInsensitive]) != nil
}

let sighRegex = #"(?:[\[\(\*]\s*(?:deep |long |heavy )?(?:sigh|sighs|sighing|exhales?)\s*[\]\)\*]\s*|(?<![\w'])\*?(?:deep |long |heavy )?(?:sigh|sighs|sighing)\*?(?![\w'])[.,!\x{2026}]*\s*)"#
/// Last line of defence on anything Cara is about to say: no sighing.
func tidy(_ s: String) -> String {
    var t = s.replacingOccurrences(of: sighRegex, with: "", options: [.regularExpression, .caseInsensitive])
    t = t.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
    return t.trimmingCharacters(in: .whitespacesAndNewlines)
}

func isSafe(_ title: String, extra: String? = nil) -> Bool {
    if mentionsDeath(title) { return false }
    let low = title.lowercased()
    if skipWords.contains(where: { low.contains($0) }) { return false }
    if title.range(of: skipRegex, options: [.regularExpression, .caseInsensitive]) != nil { return false }
    if let e = extra, title.range(of: e, options: [.regularExpression, .caseInsensitive]) != nil { return false }
    return true
}

func gnews(_ q: String) -> String {
    "https://news.google.com/rss/search?q=" + (q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q) + "&hl=en-US&gl=US&ceid=US:en"
}
func gtopic(_ t: String) -> String { "https://news.google.com/rss/headlines/section/topic/\(t)?hl=en-US&gl=US&ceid=US:en" }

var worldFeeds: [String] {[
    gnews(#"bizarre OR weird OR quirky OR "world record" OR viral"#),
    "https://rss.upi.com/news/odd_news.rss",
    "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml",
]}
var gossipFeeds: [String] {[
    gtopic("ENTERTAINMENT"),
    "https://feeds.bbci.co.uk/news/entertainment_and_arts/rss.xml",
    gnews(#""pop star" OR singer OR "red carpet" OR "new album" OR tour"#),
]}
var musicFeeds: [String] {[
    "https://www.billboard.com/feed/",
    "https://pitchfork.com/feed/feed-news/rss",
    gnews(#""new single" OR "new album" OR "tour dates" OR Billboard OR Grammy OR "chart" music"#),
]}
func localFeeds(city: String) -> [String] {
    var f = [gnews(city.replacingOccurrences(of: ",", with: " "))]
    if city.lowercased().hasPrefix("yakima") { f.append(gnews("Yakima Valley")) }
    return f
}

private var feedCache: [String: (Date, [String])] = [:]

func fetchFeed(_ urlString: String) async -> [String] {
    if let c = feedCache[urlString], Date().timeIntervalSince(c.0) < 600 { return c.1 }
    guard let url = URL(string: urlString), let data = await fetchData(url) else { return [] }
    let parser = RSSParser()
    let xml = XMLParser(data: data)
    xml.delegate = parser
    xml.parse()
    let titles = parser.titles.map(cleanTitle).filter { !$0.isEmpty }
    feedCache[urlString] = (Date(), titles)
    return titles
}

func getHeadlines(_ feeds: [String], extra: String? = nil, perFeed: Int = 6) async -> [String] {
    var out: [String] = []
    for f in feeds {
        let items = await fetchFeed(f)
        out += items.prefix(perFeed).filter { isSafe($0, extra: extra) }
    }
    return out
}

// MARK: - Weather, town lookup
func getWeather(lat: Double, lon: Double) async -> (temp: Int, rain: Bool)? {
    guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,precipitation&temperature_unit=fahrenheit"),
          let data = await fetchData(url, timeout: 8),
          let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let cur = j["current"] as? [String: Any],
          let t = cur["temperature_2m"] as? Double else { return nil }
    let p = cur["precipitation"] as? Double ?? 0
    return (Int(t.rounded()), p > 0)
}

func geocodeCity(_ city: String) async -> (lat: Double, lon: Double)? {
    let parts = city.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    guard let name = parts.first,
          let enc = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
          let url = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(enc)&count=10&language=en&format=json"),
          let data = await fetchData(url, timeout: 8),
          let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let results = j["results"] as? [[String: Any]], !results.isEmpty else { return nil }
    let region = parts.count > 1 ? parts[1].lowercased() : ""
    for r in results {
        let where_ = ((r["admin1"] as? String ?? "") + " " + (r["country"] as? String ?? "")).lowercased()
        if !region.isEmpty && where_.contains(region), let la = r["latitude"] as? Double, let lo = r["longitude"] as? Double { return (la, lo) }
    }
    if let la = results[0]["latitude"] as? Double, let lo = results[0]["longitude"] as? Double { return (la, lo) }
    return nil
}

// MARK: - Song trivia (real facts from Wikipedia)
private var wikiCache: [String: String?] = [:]
private let musicWords = ["singer", "band", "rapper", "musician", "songwriter", "duo", "group", "vocalist", "record producer", "composer", "artist", "song", "single"]

/// Runs on the main thread so the shared cache is never written from two places at once.
/// Only real answers are remembered: a failed or cancelled lookup is tried again next time.
@MainActor
func wikiLookup(_ query: String, must: [String]) async -> String? {
    if let c = wikiCache[query] { return c }
    guard let enc = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
          let url = URL(string: "https://en.wikipedia.org/w/api.php?action=query&format=json&generator=search&gsrlimit=4&prop=extracts&exintro=1&explaintext=1&exsentences=7&redirects=1&gsrsearch=\(enc)") else { return nil }
    guard let data = await fetchData(url, timeout: 8), !Task.isCancelled,
          let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    var result: String? = nil
    if let pages = (j["query"] as? [String: Any])?["pages"] as? [String: [String: Any]] {
        let sorted = pages.values.sorted { ($0["index"] as? Int ?? 99) < ($1["index"] as? Int ?? 99) }
        for pg in sorted {
            let ext = (pg["extract"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let low = ext.lowercased()
            if ext.count > 80 && must.allSatisfy({ low.contains($0.lowercased()) }) && musicWords.contains(where: { low.contains($0) }) {
                result = ext
                break
            }
        }
    }
    wikiCache[query] = result
    return result
}

func getTrivia(_ t: Track) async -> (subject: String, text: String)? {
    var clean = t.title
    if let r = clean.range(of: #"\s*[\(\[-].*$"#, options: .regularExpression) { clean.removeSubrange(r) }
    clean = clean.trimmingCharacters(in: .whitespaces)
    if clean.isEmpty { clean = t.title }
    let firstWord = t.artist.split(separator: " ").first.map(String.init) ?? t.artist
    if let text = await wikiLookup("\"\(clean)\" \(t.artist) song", must: [clean, firstWord]) {
        return ("the song \"\(t.title)\" by \(t.artist)", text)
    }
    if let text = await wikiLookup("\(t.artist) musician band singer", must: [t.artist]) {
        return (t.artist, text)
    }
    return nil
}

// MARK: - Picking and writing (the rest of Cara's brain is in Brain.swift)
func weightedPick(_ entries: [(String, Int)]) -> String {
    var r = Int.random(in: 0..<entries.reduce(0) { $0 + $1.1 })
    for (v, w) in entries { if r < w { return v }; r -= w }
    return entries[0].0
}

func gemini(_ prompt: String, key: String, log: (String) -> Void) async -> String? {
    if key.isEmpty { return nil }
    for model in ["gemini-3.5-flash-lite", "gemini-3.6-flash", "gemini-3.5-flash"] {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else { continue }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 25
        req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["contents": [["parts": [["text": prompt]]]]])
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if status != 200 { log("Gemini \(model) failed: \(status)"); continue }
            if let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let c = (j["candidates"] as? [[String: Any]])?.first,
               let parts = (c["content"] as? [String: Any])?["parts"] as? [[String: Any]],
               let raw = (parts.first?["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                let text = tidy(raw)
                if text.isEmpty { continue }
                return text
            }
        } catch { log("Gemini \(model) failed: \(error.localizedDescription)") }
    }
    return nil
}

/// `voice` reads with a different voice than Cara's (the station announcer); `announcer` gives a steadier, punchier read.
func elevenLabsTTS(_ text: String, cfg: Config, voice other: String? = nil, announcer: Bool = false) async throws -> Data {
    let key = cfg.elevenKey.trimmingCharacters(in: .whitespaces)
    let voice = (other ?? cfg.elevenVoice).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty, !voice.isEmpty else {
        throw NSError(domain: "Cara", code: 10, userInfo: [NSLocalizedDescriptionKey: "Add your ElevenLabs key and Voice ID in Settings."])
    }
    guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voice)?output_format=mp3_44100_128") else {
        throw NSError(domain: "Cara", code: 11, userInfo: [NSLocalizedDescriptionKey: "That Voice ID doesn't look right."])
    }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.timeoutInterval = 30
    req.setValue(key, forHTTPHeaderField: "xi-api-key")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let expressive = cfg.elevenModel.hasPrefix("eleven_v4") || cfg.elevenModel.hasPrefix("eleven_v3")
    var voiceSettings: [String: Any] = [:]
    if expressive {
        voiceSettings["stability"] = announcer ? 0.5 : 0.25
        voiceSettings["similarity_boost"] = announcer ? 0.85 : 1.0
    } else {
        voiceSettings["stability"] = announcer ? 0.45 : 0.35
        voiceSettings["similarity_boost"] = 0.8
        voiceSettings["style"] = announcer ? 0.55 : 0.4
        voiceSettings["use_speaker_boost"] = true
        voiceSettings["speed"] = announcer ? 1.1 : 1.05
    }
    var body: [String: Any] = [:]
    body["text"] = text
    body["model_id"] = cfg.elevenModel
    body["voice_settings"] = voiceSettings
    req.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, resp) = try await URLSession.shared.data(for: req)
    let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else {
        let msg = String(data: data, encoding: .utf8) ?? ""
        var hint = ""
        if msg.contains("invalid_api_key") { hint = " (Use the secret key that starts with sk_, not the key ID.)" }
        throw NSError(domain: "Cara", code: status, userInfo: [NSLocalizedDescriptionKey: "ElevenLabs \(status): \(msg.prefix(120))\(hint)"])
    }
    return data
}
