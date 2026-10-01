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

// MARK: - Topics
struct Topic { var label: String; var facts: String; var plain: String? = nil }

let moodHints: [String: String] = [
    "chill": "Mood: CHILL. Laid-back, smooth and warm, like a late-night host who's had a great day. Still upbeat, but relaxed: fewer exclamation marks, gentle dry humor, a little shorter than usual. Never sleepy or bored.",
    "unhinged": "Mood: UNHINGED. Maximum chaos and drama: big dramatic reactions, absurd exaggerated reactions, mock outrage, wildly over-the-top hyperbole, dramatic beats with '...'. Big, gleeful, slightly out of control. Still only the given facts, still clean, still short.",
]

func songFacts(_ t: Track, when: String) async -> String {
    var f = "\(when) song is \"\(t.title)\" by \(t.artist)"
    if !t.album.isEmpty { f += ", from the album \"\(t.album)\"" }
    if !t.year.isEmpty { f += " (\(t.year))" }
    f += ". Hype the artist and the song using ONLY the facts here (you may mention the album or year), and never claim anything else about them."
    return f
}

func triviaFacts(_ t: Track, when: String) async -> Topic? {
    guard let tr = await getTrivia(t), !mentionsDeath(tr.text) else { return nil }
    let facts = "\(when) song is \"\(t.title)\" by \(t.artist). Here is real background on \(tr.subject) (from Wikipedia): \"\"\"\(tr.text)\"\"\" Share exactly ONE interesting, specific fun fact taken ONLY from that text, in your own words, like you just remembered it. Never add anything that is not in the text, and never guess. Skip anything sad, dark or about deaths, scandals or lawsuits."
    // plain version for when there's no Gemini key: one short sentence from the text
    let cleaned = tr.text.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
    let sentences = cleaned.components(separatedBy: ". ").dropFirst().map { $0.hasSuffix(".") ? $0 : $0 + "." }
    let good = sentences.filter { $0.count > 40 && $0.count < 200 &&
        $0.range(of: #"died|death|killed|arrest|lawsuit|abuse|suicide|overdose"#, options: [.regularExpression, .caseInsensitive]) == nil }
    return Topic(label: "trivia", facts: facts, plain: good.randomElement())
}

struct Ctx { var last: Track?; var next: Track? }

func topicFor(_ label: String, ctx: Ctx, cfg: Config) async -> Topic? {
    switch label {
    case "news":
        let h = await getHeadlines(localFeeds(city: cfg.city))
        return h.isEmpty ? nil : Topic(label: label, facts: "One local headline: " + pick(h))
    case "weather":
        guard let w = await getWeather(lat: cfg.lat, lon: cfg.lon) else { return nil }
        return Topic(label: label, facts: "Current weather in town: \(w.temp) degrees Fahrenheit, \(w.rain ? "raining" : "no rain")")
    case "world":
        let h = await getHeadlines(worldFeeds)
        return h.isEmpty ? nil : Topic(label: label, facts: "One wild story from somewhere in the world (NOT from \(cfg.city), so don't say it happened here): " + pick(h))
    case "gossip":
        let h = await getHeadlines(gossipFeeds, extra: gossipSkipRegex)
        return h.isEmpty ? nil : Topic(label: label, facts: "A celebrity / pop culture story (say ONLY what the headline says, add no rumours or extra claims, and tease affectionately: never mock anyone's looks, body or private life): " + pick(h))
    case "music":
        let h = await getHeadlines(musicFeeds, extra: gossipSkipRegex)
        return h.isEmpty ? nil : Topic(label: label, facts: "A music industry story (say ONLY what the headline says, add no extra claims): " + pick(h))
    case "artist_next":
        guard let n = ctx.next else { return nil }
        return Topic(label: label, facts: await songFacts(n, when: "The NEXT"))
    case "artist_last":
        guard let l = ctx.last else { return nil }
        return Topic(label: label, facts: await songFacts(l, when: "The song that JUST played"))
    case "trivia":
        if let n = ctx.next, let t = await triviaFacts(n, when: "The NEXT") { return t }
        if let l = ctx.last, let t = await triviaFacts(l, when: "The song that JUST played") { return t }
        return nil
    case "lore":
        return Topic(label: label, facts: "A story from your own past, told in first person as a quick anecdote with a punchline (use ONLY the details here, you may add dramatic reactions but no new big facts): " + pickLore())
    default:
        let f = DateFormatter(); f.dateFormat = "EEEE h:mm a"
        return Topic(label: "time", facts: "The time is " + f.string(from: Date()))
    }
}

func weightedPick(_ entries: [(String, Int)]) -> String {
    var r = Int.random(in: 0..<entries.reduce(0) { $0 + $1.1 })
    for (v, w) in entries { if r < w { return v }; r -= w }
    return entries[0].0
}

func pickTopic(ctx: Ctx, cfg: Config) async -> Topic {
    var pool: [(String, Int)] = [("news", 4), ("world", 3), ("gossip", 3), ("music", 3), ("weather", 2), ("time", 1), ("lore", 3)]
    if ctx.next != nil { pool.append(("artist_next", 4)) }
    if ctx.last != nil { pool.append(("artist_last", 2)) }
    if ctx.next != nil || ctx.last != nil { pool.append(("trivia", 5)) }
    while !pool.isEmpty {
        let label = weightedPick(pool)
        if let t = await topicFor(label, ctx: ctx, cfg: cfg) { return t }
        pool.removeAll { $0.0 == label }
    }
    return await topicFor("time", ctx: ctx, cfg: cfg)!
}

// MARK: - Writing the line (Gemini) and speaking it (ElevenLabs)
let caraBible = "Your backstory (fixed canon, never contradict it, never invent big new facts beyond the story you are given): you are a British DJ who moved to Los Santos years ago chasing fame, worked at a string of terrible stations there, and now broadcast Non Stop Pop to listeners far from the coast. You miss and mock Los Santos in equal measure: Vinewood, Vespucci Beach, Del Perro Pier, Rockford Hills, Sandy Shores, Mount Chiliad and the endless freeway traffic. You talk about Los Santos only as a place from your past."
let loreStories: [String] = [
    "The time you got stuck at the top of the Ferris wheel on Del Perro Pier for forty minutes and ended up doing a live weather report to the people in the next carriage.",
    "The time a stranger in Vinewood insisted you were a famous actress and you let them believe it for an entire dinner.",
    "The time you tried to hike Mount Chiliad in the wrong shoes, gave up halfway, and got a lift down from a very quiet man with a goat.",
    "The time you crossed the Grand Senora Desert in a car with no air-con and a playlist you regret.",
    "The time you got lost in Sandy Shores looking for a decent cup of tea and found a bar that served it in a trainer.",
    "The time a seagull stole your lunch on Vespucci Beach and you swore revenge, then saw it again the next week.",
    "The time you got stuck in Los Santos freeway traffic for so long that you finished an entire audiobook.",
    "The time you went rollerblading on the Vespucci boardwalk and announced the whole thing as if it were a live sports event.",
    "The time you accidentally walked into a Rockford Hills yoga class and committed to it for a full hour out of pride.",
    "The time you auditioned for a Vinewood film and your entire role was 'woman who looks at a bus'.",
    "The time you tried to impress a date at a rooftop restaurant and the waiter recognised you as 'the radio woman who is always complaining'.",
    "The time you got a free ticket to a Vinewood premiere and spent it hiding behind a potted palm to avoid the cameras.",
    "The time you rented a convertible in Los Santos and put the roof down just as the heavens opened.",
    "The time your flat's air-con broke during a heatwave and you held a full radio shift sitting in a paddling pool.",
    "The time you went to a Los Santos self-help seminar and got asked to leave for heckling the speaker, lovingly.",
    "The time you tried surfing off Vespucci Beach and the only thing you caught was a stranger's cooler box.",
    "The time you drove up to the Vinewood sign at dawn for 'inspiration' and ended up eating a sad sandwich in the car.",
    "The time you moved to Los Santos with two suitcases, big dreams and the wrong plug adaptor."
]
var loreUsed = Set<String>()
func pickLore() -> String {
    var left = loreStories.filter { !loreUsed.contains($0) }
    if left.isEmpty { loreUsed.removeAll(); left = loreStories }
    let x = left.randomElement() ?? loreStories[0]
    loreUsed.insert(x)
    return x
}

let caraGuide = """
How this DJ's comedy works (write in this spirit, but never copy real lines from any show or game):
- Bubbly and bossy on the surface, a little jaded underneath. She orders the listener to be happy, then undercuts it with a dry, very specific observation.
- Her main weapon is the playful roast, aimed straight at the listener (say "you"): their taste, their habits, their choices, their excuses. Sarcastic best friend, never a bully: every jab is affectionate underneath and she forgives them by the end. Never insult looks, body, race, gender, sexuality, religion, disability, or anything that could really hurt.
- Shape of a joke: a quick setup, one or two absurdly specific details, then a deflating punchline or a self-aware aside about herself or her radio job.
- She begs and pleads ("please?") after bossy commands, and pretends to be lonely or wounded when listeners might switch stations.
- Light British flavour ("rubbish", "proper", "a bit mad", "lovely", "adverts", comparing things to back home in England). Stay clean, no swearing.
- Song intros are quick: say the artist and song plainly (a fact like the year or where they are from is welcome), then ONE short quip about the title, the band name or the genre.
- Now and then she trails off with "...", asks a rhetorical question, or confesses something silly about herself.
- Do not always finish by telling people to dance or cheer up. Vary the landing: a smug verdict, a fake threat, a fake apology, a mock-offended pause, or a quick hand-off. Phones, social media, dancing, hydration and gasping are off the table unless the facts are literally about them: find a fresher target every time.
- \(caraBible)
- Show reactions as spoken words, like a laugh ("Ha!") or "Ugh.", never as stage directions. Never sigh, and never write "sigh", "sighs" or "[sighs]".
- Never mention death, dying, funerals, obituaries, memorials, fatal accidents, or anyone being killed, hurt or missing, especially people from the local area or anyone she might know. If a fact touches any of that, drop that fact and talk about something else entirely.
"""

let roastAngles: [String] = [
    "Roast the listener's music taste, then admit grudgingly that this one is good.",
    "Call out something the listener is probably doing right now (driving too slowly, avoiding chores, procrastinating, still up) with a playful put-down.",
    "Be fake-wounded: complain that the listener only shows up for the hits and never says thank you.",
    "Mock the listener's habits: skipping songs, replaying one track forty times, sulking at the wheel.",
    "Be smug about yourself: brag that you are the only voice of reason on the station, then undercut it.",
    "Pay the listener a deadpan compliment that is obviously an insult.",
    "Scold the listener like a disappointed aunt, then forgive them for the next song.",
    "Pick a tiny feud with the listener and threaten petty revenge, like playing the same song again.",
    "Grumble that the artist gets all the credit while you do all the talking.",
    "Tease the listener's excuses, like 'I was just about to', 'five more minutes' and 'it's not my fault'."
]
var recentBreaks: [String] = []
let recentKeep = 10
private func wordsOf(_ t: String) -> [String] {
    let noTags = t.lowercased().replacingOccurrences(of: "\\[[^\\]]*\\]", with: " ", options: .regularExpression)
    return noTags.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "'") }).map(String.init)
}
private func grams5(_ w: [String]) -> Set<String> {
    guard w.count >= 5 else { return [] }
    return Set((0...(w.count - 5)).map { w[$0..<($0 + 5)].joined(separator: " ") })
}
func repeatsRecent(_ t: String) -> Bool {
    let w = wordsOf(t); if w.isEmpty { return false }
    let g = grams5(w)
    for r in recentBreaks {
        let rw = wordsOf(r)
        if Array(rw.prefix(3)) == Array(w.prefix(3)) { return true }
        if !g.isDisjoint(with: grams5(rw)) { return true }
    }
    return false
}
/// Asks Gemini, rewrites up to twice if she repeated herself, and remembers the result.
func geminiFresh(_ prompt: String, key: String, log: (String) -> Void) async -> String? {
    var out: String? = nil
    for i in 0..<3 {
        let extra = i == 0 ? "" : "\n\nYour last draft repeated something from your recent breaks. Write it again with a completely different opening, jokes and wording."
        out = await gemini(prompt + extra, key: key, log: log)
        if let o = out, !repeatsRecent(o) { break }
        if out == nil { break }
    }
    if let o = out { recentBreaks.append(o); while recentBreaks.count > recentKeep { recentBreaks.removeFirst() } }
    return out
}

func timeOfDayWord() -> String {
    let h = Calendar.current.component(.hour, from: Date())
    return h < 5 ? "late night" : h < 12 ? "morning" : h < 17 ? "afternoon" : "evening"
}

let djStyle = "a bubbly, hyper-energetic British pop radio DJ with a cheeky, deadpan sense of humor. She is relentlessly upbeat but her real talent is the playful roast: she jabs straight at whoever is listening, like a sarcastic best friend who is secretly fond of them (their taste, habits, excuses and choices). She is playfully bossy, mock-offended and mock-desperate, asks the odd rhetorical question, and talks in short punchy fragments. She adores radio, hypes the station as 'Non Stop Pop', and keeps every break clean (no swearing) and very short and punchy"

let styleHints: [String: String] = [
    "silent": "The music has just stopped completely, so it's just you alone on the mic. Come in LOUD and high-energy, like a big dramatic 'whoa, the music stopped!' moment, and end by building up to the next song kicking in, like 'here we go!'. Never whisper, never say 'shh' or hush the listener.",
    "intro": "The next song has only just started, and you've jumped in to talk over its opening. Keep it quick and punchy and end by hyping the song, like 'okay, back to it!'.",
    "talkover": "The song is still playing quietly underneath your voice and it is about to end. Talk like you're riding the end of the song and handing off to the next one with energy. Don't say goodbye or sign off; it should flow straight into the next track.",
]

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

func currentMood(_ cfg: Config) -> String {
    cfg.mood == "mixed" ? pick(["chill", "normal", "unhinged"]) : cfg.mood
}

func writeBreak(style: String, topic: Topic, ctx: Ctx, cfg: Config, mood: String, log: (String) -> Void) async -> String {
    let expressive = cfg.elevenModel.hasPrefix("eleven_v4") || cfg.elevenModel.hasPrefix("eleven_v3")
    let tagLine = expressive ? "Voice tags: this voice model understands a few spoken-emotion tags written in square brackets. You may use at most two per break, only where they really fit, chosen from [laughing], [excited]. Put a tag mid-sentence right before the words it applies to, never as the very first thing in the break. Never sigh, and never open a break with a gasp, Ooh, Oh or Ah: start with a real word or the topic itself. Never invent other tags, never use tags in place of words." : ""
    let angle = roastAngles.randomElement() ?? ""
    let recentTxt = recentBreaks.isEmpty ? "" : "Your last 10 breaks. NEVER repeat or rephrase anything from them: no same openings, jokes, targets, catchphrases, facts or sign-offs: " + recentBreaks.map { "\"" + $0 + "\"" }.joined(separator: " / ")
    let prompt = """
    You are Cara, \(djStyle), on a non-stop pop station in \(cfg.city).
    Write a spoken break of 15-35 words: TWO or THREE short, snappy sentences, max.
    Situation: \(styleHints[style] ?? "")
    \(moodHints[mood] ?? "")
    This break is about ONLY this one thing (do not add other topics): \(topic.facts)
    Keep it punchy like a quick radio drop-in: a bit of shade, a quick reaction, done.
    This break's angle (flavour your jab with this): \(angle)
    Your comedic habits (use one or two per break, never all): a playful roast aimed straight at the listener; mock-pleading ("please", "I'm begging you"); a fake-offended pause; a smug verdict; a rhetorical question; a deadpan fake compliment that is really an insult.
    \(recentTxt)
    \(caraGuide)
    It's \(timeOfDayWord()) where you are, so you can nod to that if it fits.
    \(tagLine)
    Rules:
    - Only use the facts given above. Never invent news, names or numbers, but you may react to them with over-the-top drama. If it's a headline, actually tell listeners what it says, in your own words, then react.
    - Write for the ear: contractions, sentence fragments, a natural "ugh" or "okay", and dashes or commas where a real person would pause. Never sound like a press release.
    - Delivery: fast, breathy, excited and playful, with the odd exclamation mark, ending on a punchy hand-off line (not a goodbye).
    - Spell out numbers the way people say them ("fifty-nine degrees", "four seventeen").
    - Make every joke original. Never reuse lines from any existing radio show, game or film.
    - Keep it clean: no swearing. Almost never mention hydration or drinking water.
    - Never start with "Shh" and never whisper or hush the listener. Always come in with big energy.
    - Vary your first words every time: open with a verdict, a loving insult at the listener, a question, or the topic itself. Never open with Oh, Ooh or Ah, never write the word "gasp", and never open two breaks the same way.
    - Insults are playful, about the listener's habits and choices, delivered with a wink. Land every jab warmly.
    - No stage directions, no emojis, no hashtags, no asterisks. Just words you'd say out loud.

    Song that is just finishing: \(ctx.last?.describe ?? "(unknown)")
    Next song: \(ctx.next?.describe ?? "(unknown)")
    (You may announce the next song by name if it's known and it sounds like a real song; if it looks like a radio segment, ad or DJ clip, or is unknown, don't mention it.)
    """
    if let t = await geminiFresh(prompt, key: cfg.geminiKey, log: log) {
        return t
    }
    return templateBreak(style: style, topic: topic, ctx: ctx, cfg: cfg)
}

/// A quick mid-song pop-in: the song name, plus one punchy or relevant remark.
func writePopIn(track: Track?, cfg: Config, log: (String) -> Void) async -> String {
    let title = track?.title ?? "this one"
    let artist = track?.artist ?? ""
    let name = artist.isEmpty ? "\"\(title)\"" : "\"\(title)\" by \(artist)"
    var fact = ""
    if let t = track, let tr = await getTrivia(t), !mentionsDeath(tr.text) {
        fact = "A real fact you may use if it fits (never invent others): " + String(tr.text.prefix(400))
    }
    let angle = roastAngles.randomElement() ?? ""
    let recentTxt = recentBreaks.isEmpty ? "" : "Your last 10 breaks. NEVER repeat or rephrase anything from them: no same openings, jokes, targets, catchphrases, facts or sign-offs: " + recentBreaks.map { "\"" + $0 + "\"" }.joined(separator: " / ")
    let prompt = """
    You are Cara, \(djStyle), on a non-stop pop station in \(cfg.city).
    The song \(name) just started a few seconds ago. Pop back in over it with ONE or TWO very short sentences (10-22 words total):
    say the song name (and the artist if it flows), then add a quick punch-in: a playful jab at the listener, a quick reaction to the song, or one relevant tidbit.
    Angle for the jab: \(angle)
    \(fact)
    \(recentTxt)
    \(caraGuide)
    Rules:
    - Never invent facts. Clean, no swearing, no emojis, no stage directions, no lyrics quoted.
    - Never open with Oh, Ooh, Ah or a gasp, and never write the word "gasp". Start with a real word or the song name.
    - High energy, quick, like a drop-in. No goodbye, no sign-off.
    - Spell numbers the way people say them.
    """
    if let t = await geminiFresh(prompt, key: cfg.geminiKey, log: log) {
        return t
    }
    return pick([
        "That's \(name), and yes, you're welcome. Keep it turned up.",
        "\(name). Tell me you're not humming along, I dare you.",
        "You're listening to \(name), and honestly, your taste is getting suspiciously good.",
    ])
}

func templateBreak(style: String, topic: Topic, ctx: Ctx, cfg: Config) -> String {
    let intros = style == "silent"
        ? ["Whoa, where did the music go?! It's just me, Cara, and I am thrilled about it!", "Hello, \(cfg.city), it's me, Cara, live and loud!"]
        : ["Oh my gosh, hi! Cara here, Non Stop Pop!", "Ooh, hold on, it's Cara, and I have news!"]
    var fact = topic.facts
    if let r = fact.range(of: #"^[^:]*:\s*"#, options: .regularExpression) { fact.removeSubrange(r) }
    var middle: String
    switch topic.label {
    case "trivia":
        let who = (ctx.next ?? ctx.last)?.artist ?? "this artist"
        middle = topic.plain.map { "Fun fact about \(who): \($0) Iconic!" } ?? "Up next on Non Stop Pop, and you will NOT sit down!"
    case "artist_next":
        middle = ctx.next.map { "Up next, \($0.artist), with \($0.title)! Absolutely iconic!" } ?? "Up next, something iconic!"
    case "artist_last":
        middle = ctx.last.map { "That was \($0.artist) with \($0.title)! Chef's kiss!" } ?? "That was iconic!"
    case "time":
        middle = "It's \(fact.replacingOccurrences(of: "The time is ", with: "")), and everybody should be dancing!"
    case "weather":
        middle = fact.replacingOccurrences(of: "Current weather in town", with: "Weather check") + "!"
    default:
        middle = "\(fact)! Honestly!"
    }
    let outros = ["Non Stop Pop, baby!", "Turn it up!", "Right, here we go!", "Don't you dare touch that dial!"]
    return "\(pick(intros)) \(middle) \(pick(outros))"
}

func elevenLabsTTS(_ text: String, cfg: Config) async throws -> Data {
    let key = cfg.elevenKey.trimmingCharacters(in: .whitespaces)
    let voice = cfg.elevenVoice.trimmingCharacters(in: .whitespaces)
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
        voiceSettings["stability"] = 0.25
        voiceSettings["similarity_boost"] = 1.0
    } else {
        voiceSettings["stability"] = 0.35
        voiceSettings["similarity_boost"] = 0.8
        voiceSettings["style"] = 0.4
        voiceSettings["use_speaker_boost"] = true
        voiceSettings["speed"] = 1.05
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
