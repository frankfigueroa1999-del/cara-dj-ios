import Foundation
import AVFoundation

// MARK: - Station stingers
// Your six Non Stop Pop stingers, remade for whatever station is playing. The music, swooshes and hits are the
// originals (the voice was lifted out of each one); a separate announcer reads new lines written for the station,
// with the same radio EQ, compression and echo, dropped in where the original lines sat.

/// Where each line sits in the six originals, and what kind of line it is.
enum StingerScript {
    enum Kind {
        /// A line the writer comes up with: at most `words` words, in the spirit of `hint`.
        case write(words: Int, hint: String)
        case freq, onFreq, name, thisIs, love, freqName
    }
    struct Line {
        let at: Double
        let kind: Kind
        let echo: Bool
    }
    struct Template {
        let id: Int
        let lines: [Line]
        /// How loud the original voice sat in the music (dBFS while talking), so the new one sits the same.
        let voiceDB: Float
        /// What the original says, as a style guide for the writer.
        let original: String
    }

    static let templates: [Template] = [
        Template(id: 1, lines: [
            Line(at: 0.10, kind: .write(words: 7, hint: "what this station plays, wry, like 'Classic pop hits from the last thirty years.'"), echo: false),
            Line(at: 2.45, kind: .write(words: 4, hint: "a smug little boast, like 'It's the best music.'"), echo: false),
            Line(at: 3.60, kind: .freq, echo: false),
            Line(at: 4.90, kind: .name, echo: true),
        ], voiceDB: -21.5, original: "Classic pop hits from the last thirty years. It's the best music. One hundred point seven FM. Non Stop Pop! (echoed)"),
        Template(id: 2, lines: [
            Line(at: 0.10, kind: .write(words: 8, hint: "starts a list and ends with a comma, like 'All your favourite pop hits from the eighties,'"), echo: false),
            Line(at: 3.30, kind: .write(words: 2, hint: "the next item on the list, like 'nineties,'"), echo: true),
            Line(at: 4.00, kind: .write(words: 2, hint: "another item, like 'noughties,'"), echo: true),
            Line(at: 5.20, kind: .write(words: 3, hint: "the last item, a little punchline, like 'and today.'"), echo: false),
            Line(at: 6.40, kind: .freq, echo: false),
            Line(at: 8.40, kind: .name, echo: false),
        ], voiceDB: -21.6, original: "All your favourite pop hits from the eighties, nineties (echoed), noughties (echoed), and today. One hundred point seven FM. Non Stop Pop."),
        Template(id: 3, lines: [
            Line(at: 0.05, kind: .write(words: 5, hint: "a lead-in that runs straight into the hook, like 'Dance pop classics that'"), echo: false),
            Line(at: 2.85, kind: .write(words: 3, hint: "a short hook that gets echoed three times, ideally a pun on the station's name, like 'never stop'"), echo: true),
            Line(at: 4.85, kind: .onFreq, echo: false),
            Line(at: 7.00, kind: .write(words: 5, hint: "a deadpan verdict, like 'That music is awesome.'"), echo: false),
            Line(at: 8.60, kind: .name, echo: false),
        ], voiceDB: -23.0, original: "Dance pop classics that never stop, never stop, never stop (echoed), on one hundred point seven FM. That music is awesome. Non Stop Pop."),
        Template(id: 4, lines: [
            Line(at: 0.15, kind: .write(words: 3, hint: "the start of a sentence, echoed, like 'The music'"), echo: true),
            Line(at: 2.40, kind: .write(words: 6, hint: "finishes that sentence, like 'that has really moved you.'"), echo: false),
            Line(at: 4.60, kind: .thisIs, echo: false),
            Line(at: 6.60, kind: .write(words: 4, hint: "a deadpan boast, echoed, like 'They're the best.'"), echo: true),
        ], voiceDB: -22.5, original: "The music (echoed) that has really moved you. This is Non Stop Pop. They're the best (echoed)."),
        Template(id: 5, lines: [
            Line(at: 0.10, kind: .write(words: 8, hint: "a wistful little roast, like 'Everyone was happy once in their lives.'"), echo: false),
            Line(at: 3.10, kind: .write(words: 10, hint: "what the music is, like 'This is music from that special time for you.'"), echo: false),
            Line(at: 6.20, kind: .freqName, echo: false),
            Line(at: 8.70, kind: .write(words: 5, hint: "a deadpan slogan, like 'Contemporary nostalgia is the best.'"), echo: false),
        ], voiceDB: -22.4, original: "Everyone was happy once in their lives. This is music from that special time for you. One hundred point seven FM, Non Stop Pop. Contemporary nostalgia is the best."),
        Template(id: 6, lines: [
            Line(at: 0.10, kind: .write(words: 5, hint: "a cheeky order, echoed, like 'Get into the music.'"), echo: true),
            Line(at: 3.20, kind: .write(words: 7, hint: "a nostalgic jab, like 'This is when you were happy.'"), echo: false),
            Line(at: 4.60, kind: .love, echo: false),
            Line(at: 7.10, kind: .write(words: 6, hint: "a playful roast of the listener, echoed, like 'Don't be an elitist snob.'"), echo: true),
        ], voiceDB: -20.6, original: "Get into the music (echoed). This is when you were happy. You know you love Non Stop Pop FM. Don't be an elitist snob (echoed)."),
    ]

    /// Stock lines, for when the writer can't be reached.
    static let fallback: [Int: [String]] = [
        1: ["Your favourite songs, played on purpose.", "Still the best music."],
        2: ["All your favourite songs from the good years,", "the better years,", "the best years,", "and today."],
        3: ["Big pop songs that", "keep on going,", "That music is great."],
        4: ["The songs", "that get you every single time.", "They're the best."],
        5: ["Everybody was happy once.", "This is the music from back then, just for you.", "Nostalgia, but louder."],
        6: ["Turn it up.", "This is when you were happy.", "Don't be a snob about it."],
    ]

    static func writeCount(_ t: Template) -> Int {
        t.lines.filter { if case .write = $0.kind { return true } else { return false } }.count
    }

    /// Every line of one stinger, ready to be read out.
    static func texts(for t: Template, written: [String], station: String) -> [String] {
        let mine = written.count == writeCount(t) ? written : (fallback[t.id] ?? [])
        var next = 0
        var out: [String] = []
        for line in t.lines {
            switch line.kind {
            case .write:
                out.append(next < mine.count ? mine[next] : "")
                next += 1
            case .freq: out.append("One hundred point seven FM.")
            case .onFreq: out.append("On one hundred point seven FM.")
            case .name: out.append(station + "!")
            case .thisIs: out.append("This is \(station).")
            case .love: out.append("You know you love \(Station.full(station)).")
            case .freqName: out.append("One hundred point seven FM, \(station).")
            }
        }
        return out
    }

    /// Asks the writer for all six at once, in the originals' shape.
    static func prompt(station: String, note: String, artists: [String]) -> String {
        var asks: [String] = []
        for t in templates {
            var parts: [String] = []
            for line in t.lines {
                if case let .write(words, hint) = line.kind { parts.append("\(hint) (\(words) words at most)") }
            }
            asks.append("\(t.id). Old: \"\(t.original)\"\n   Write \(parts.count) line\(parts.count == 1 ? "" : "s"), in order: " + parts.enumerated().map { "(\($0.offset + 1)) \($0.element)" }.joined(separator: "; "))
        }
        let shape = "{" + templates.map { t in
            "\"\(t.id)\": [" + Array(repeating: "\"...\"", count: writeCount(t)).joined(separator: ", ") + "]"
        }.joined(separator: ", ") + "}"
        let what = note.isEmpty ? "" : " It's named after \(note)."
        let onIt = artists.isEmpty ? "" : " Some of what's on it: \(artists.prefix(6).joined(separator: ", "))."
        return """
        You write station IDs ("stingers") for a radio station that takes the name of whatever the listener is playing. Right now it's called "\(Station.full(station))".\(what)\(onIt)

        The station's six old stingers (from when it was Non Stop Pop FM) set the style: deadpan, cheesy and nostalgic, quietly roasting the listener's taste, read by a cool, unimpressed announcer. Keep each one's shape but write completely new words that fit "\(station)". The station name and the frequency are added for you, so only write the lines asked for.

        \(asks.joined(separator: "\n"))

        Rules: fresh wording (never reuse the old lines), roasts are playful and affectionate (nothing about looks, bodies or identity), nothing about death, politics, crime or drinking, no swearing, numbers spelled out, no emojis, hashtags or stage directions.
        Answer with JSON only, one list of lines per stinger: \(shape)
        """
    }
}

/// Makes and keeps the stingers for each station.
@MainActor
final class StationStingers {
    static let shared = StationStingers()
    /// The announcer when you haven't picked one (one of ElevenLabs' own voices).
    static let defaultVoice = "EXAVITQu4vr4xnSDxMaL"

    private var making: Set<String> = []
    private var lastPlayed: [String: String] = [:]
    private var failedAt: Date? = nil

    private struct Meta: Codable {
        var station: String
        var lines: [String: [String]]
        var made: [Int]
    }

    static func voice(_ cfg: Config) -> String {
        let v = cfg.stationVoice.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? defaultVoice : v
    }

    /// Making them has gone wrong in the last ten minutes (the original stingers stand in meanwhile).
    var failingLately: Bool {
        guard let f = failedAt else { return false }
        return Date().timeIntervalSince(f) < 600
    }

    private var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("StationStingers", isDirectory: true)
    }

    /// One folder per station, voice and model.
    private func folder(_ station: String, cfg: Config) -> URL {
        let slug = String(station.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }.prefix(24))
        var h: UInt64 = 5381
        for b in (station + "|" + Self.voice(cfg) + "|" + cfg.elevenModel).utf8 { h = (h &* 33) &+ UInt64(b) }
        return root.appendingPathComponent(slug + "-" + String(h, radix: 36), isDirectory: true)
    }

    private func made(in dir: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "wav" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func isMaking(_ station: String, cfg: Config) -> Bool { making.contains(folder(station, cfg: cfg).lastPathComponent) }

    /// A finished stinger for this station (never the same one twice in a row), or nil if none is made yet.
    func ready(for station: String, cfg: Config) -> URL? {
        let dir = folder(station, cfg: cfg)
        let all = made(in: dir)
        guard !all.isEmpty else { return nil }
        let last = lastPlayed[dir.lastPathComponent]
        let pick = all.filter { $0.lastPathComponent != last }.randomElement() ?? all[0]
        lastPlayed[dir.lastPathComponent] = pick.lastPathComponent
        return pick
    }

    /// Makes one more for this station in the background, if it still needs one.
    func warm(station: String, note: String, artists: [String], cfg: Config, log: @escaping (String) -> Void) {
        guard cfg.stationStingers, station != Station.fallback, !failingLately else { return }
        let dir = folder(station, cfg: cfg)
        guard !making.contains(dir.lastPathComponent), made(in: dir).count < StingerScript.templates.count else { return }
        Task { await self.make(station: station, note: note, artists: artists, cfg: cfg, log: log) }
    }

    /// Starts over: every station writes and records new ones.
    func clearAll() {
        try? FileManager.default.removeItem(at: root)
        lastPlayed = [:]
        failedAt = nil
    }

    /// Makes one more stinger for this station right now. Returns it (nil if it couldn't).
    @discardableResult
    func make(station: String, note: String, artists: [String], cfg: Config, log: @escaping (String) -> Void) async -> URL? {
        let dir = folder(station, cfg: cfg)
        let key = dir.lastPathComponent
        guard !making.contains(key) else { return nil }
        making.insert(key)
        defer { making.remove(key) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var meta = loadMeta(dir) ?? Meta(station: station, lines: [:], made: [])
        meta.made = meta.made.filter { id in FileManager.default.fileExists(atPath: dir.appendingPathComponent("stinger_\(id).wav").path) }
        let todo = StingerScript.templates.filter { !meta.made.contains($0.id) }
        guard let t = todo.randomElement() else { return ready(for: station, cfg: cfg) }

        // the words: written once per station, for all six (stock lines are never kept, so the writer gets another go)
        var lines = meta.lines
        if lines.isEmpty {
            let w = await writeLines(station: station, note: note, artists: artists, cfg: cfg, log: log)
            lines = w.lines
            if w.fresh > 0 {
                meta.lines = w.lines
                saveMeta(meta, dir)
            }
        }
        let texts = StingerScript.texts(for: t, written: lines[String(t.id)] ?? [], station: station)
        log("[making a \(Station.full(station)) stinger: \(texts.joined(separator: " "))]")

        // the announcer, one line at a time
        var clips: [StingerMixer.Clip] = []
        let voice = Self.voice(cfg)
        let stamp = Int(Date().timeIntervalSince1970)
        do {
            for (i, line) in t.lines.enumerated() where !texts[i].isEmpty {
                let data = try await elevenLabsTTS(texts[i], cfg: cfg, voice: voice, announcer: true)
                let f = FileManager.default.temporaryDirectory.appendingPathComponent("sting_\(stamp)_\(t.id)_\(i).mp3")
                try data.write(to: f)
                clips.append(StingerMixer.Clip(file: f, at: line.at, echo: line.echo))
            }
        } catch {
            failedAt = Date()
            log("[couldn't make the stinger: \(error.localizedDescription)]")
            for c in clips { try? FileManager.default.removeItem(at: c.file) }
            return nil
        }
        guard let bed = Bundle.main.url(forResource: "stationbed_\(t.id)", withExtension: "m4a") else {
            log("[the stinger music is missing from the app]")
            return nil
        }

        // mix it away from the main thread
        let out = dir.appendingPathComponent("stinger_\(t.id).wav")
        let target = t.voiceDB
        let problem: String? = await Task.detached(priority: .utility) { () -> String? in
            do {
                try StingerMixer.render(bed: bed, clips: clips, voiceDB: target, to: out)
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
        for c in clips { try? FileManager.default.removeItem(at: c.file) }
        if let p = problem {
            failedAt = Date()
            log("[couldn't mix the stinger: \(p)]")
            return nil
        }
        failedAt = nil
        meta.made.append(t.id)
        saveMeta(meta, dir)
        prune()
        log("[stinger ready: \(made(in: dir).count) of 6 for \(Station.full(station))]")
        return out
    }

    // MARK: inside
    private func writeLines(station: String, note: String, artists: [String], cfg: Config, log: @escaping (String) -> Void) async -> (lines: [String: [String]], fresh: Int) {
        var out: [String: [String]] = [:]
        for (id, lines) in StingerScript.fallback { out[String(id)] = lines }
        guard !cfg.geminiKey.isEmpty else { return (out, 0) }
        let ask = StingerScript.prompt(station: station, note: note, artists: artists)
        guard let raw = await gemini(ask, key: cfg.geminiKey, log: log),
              let open = raw.firstIndex(of: "{"), let close = raw.lastIndex(of: "}"), open < close,
              let data = String(raw[open...close]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            log("[stinger lines: using the stock ones this time]")
            return (out, 0)
        }
        var got = 0
        for t in StingerScript.templates {
            guard let arr = (obj[String(t.id)] ?? obj["t\(t.id)"]) as? [String] else { continue }
            let lines = arr.map { Self.clean($0) }
            if lines.count == StingerScript.writeCount(t), lines.allSatisfy({ !$0.isEmpty && !mentionsDeath($0) }) {
                out[String(t.id)] = lines
                got += 1
            }
        }
        if got < StingerScript.templates.count { log("[stinger lines: \(got) of 6 written fresh, the rest stock]") }
        return (out, got)
    }

    /// Only words: no brackets, asterisks, emojis or quote marks around the line.
    private static func clean(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"\[[^\]]*\]"#, with: " ", options: .regularExpression)
        t = String(t.unicodeScalars.filter { !($0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0xFF)) }.map(Character.init))
        t = t.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "#", with: "")
        t = t.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”")))
    }

    private func loadMeta(_ dir: URL) -> Meta? {
        guard let d = try? Data(contentsOf: dir.appendingPathComponent("meta.json")) else { return nil }
        return try? JSONDecoder().decode(Meta.self, from: d)
    }

    private func saveMeta(_ m: Meta, _ dir: URL) {
        if let d = try? JSONEncoder().encode(m) { try? d.write(to: dir.appendingPathComponent("meta.json"), options: .atomic) }
    }

    /// Keeps the twenty stations used most recently.
    private func prune() {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]), dirs.count > 20 else { return }
        let dated = dirs.map { u -> (URL, Date) in
            let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return (u, d)
        }
        for (u, _) in dated.sorted(by: { $0.1 > $1.1 }).dropFirst(20) { try? fm.removeItem(at: u) }
    }
}

/// The mixing desk: EQ, compression and echo on the new voice, laid over the original music.
enum StingerMixer {
    struct Clip: Sendable {
        let file: URL
        let at: Double
        let echo: Bool
    }

    static let rate: Double = 44100

    static func render(bed: URL, clips: [Clip], voiceDB: Float, to out: URL) throws {
        let music = try read(bed)
        let bedL = music.first ?? []
        let bedR = music.count > 1 ? music[1] : bedL
        let bedSeconds = Double(bedL.count) / rate
        var placed: [(start: Int, samples: [Float])] = []
        var prevEnd = 0.0
        for (i, c) in clips.enumerated() {
            var v = try trim(mono(read(c.file)))
            if v.isEmpty { continue }
            // a line much longer than its spot in the original gets read a touch faster
            let nextAt = i + 1 < clips.count ? clips[i + 1].at : bedSeconds
            let room = max(0.4, nextAt - c.at - 0.05)
            let length = Double(v.count) / rate
            if length > room * 1.08 { v = stretch(v, by: Float(min(1.3, length / room))) }
            voiceChain(&v)
            let dry = Double(v.count) / rate
            let start = max(c.at, prevEnd + 0.04)
            if c.echo { v = echo(v, delay: dry <= 0.75 ? dry + 0.04 : 0.42) }
            placed.append((Int(start * rate), v))
            prevEnd = start + dry
        }
        guard !placed.isEmpty else { throw failure("there was no voice to mix") }
        let lastEnd = placed.map { $0.start + $0.samples.count }.max() ?? 0
        let total = max(bedL.count, lastEnd + Int(0.05 * rate))
        var voice = [Float](repeating: 0, count: total)
        for p in placed {
            for k in 0..<p.samples.count where p.start + k < total { voice[p.start + k] += p.samples[k] }
        }
        // the new voice sits in the music exactly as loud as the old one did
        let gain = powf(10, (voiceDB - activeDB(voice)) / 20)
        var left = [Float](repeating: 0, count: total)
        var right = [Float](repeating: 0, count: total)
        var peak: Float = 0
        for k in 0..<total {
            let v = voice[k] * gain
            left[k] = (k < bedL.count ? bedL[k] : 0) + v
            right[k] = (k < bedR.count ? bedR[k] : 0) + v
            peak = max(peak, abs(left[k]), abs(right[k]))
        }
        if peak > 0.97 {
            let s = 0.97 / peak
            for k in 0..<total { left[k] *= s; right[k] *= s }
        }
        let fade = min(total, Int(0.03 * rate))
        for k in 0..<fade {
            let f = Float(k) / Float(fade)
            left[total - 1 - k] *= f
            right[total - 1 - k] *= f
        }
        try writeWAV(left, right, to: out)
    }

    // MARK: reading and writing
    static func read(_ url: URL) throws -> [[Float]] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(max(0, file.length))
        guard frames > 0, let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { throw failure("an empty sound file") }
        try file.read(into: buf)
        guard let data = buf.floatChannelData else { throw failure("a sound file it couldn't read") }
        let n = Int(buf.frameLength)
        var chans: [[Float]] = []
        for c in 0..<Int(format.channelCount) { chans.append(Array(UnsafeBufferPointer(start: data[c], count: n))) }
        if format.sampleRate != rate { chans = chans.map { resample($0, from: format.sampleRate) } }
        return chans
    }

    static func writeWAV(_ l: [Float], _ r: [Float], to url: URL) throws {
        let n = min(l.count, r.count)
        var d = Data(capacity: 44 + n * 4)
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + n * 4)); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(2); u32(UInt32(rate)); u32(UInt32(rate) * 4); u16(4); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(n * 4))
        var pcm = [Int16](repeating: 0, count: n * 2)
        for k in 0..<n {
            pcm[2 * k] = Int16(max(-1, min(1, l[k])) * 32767)
            pcm[2 * k + 1] = Int16(max(-1, min(1, r[k])) * 32767)
        }
        pcm.withUnsafeBufferPointer { d.append($0) }
        try d.write(to: url, options: .atomic)
    }

    // MARK: the effects
    static func mono(_ chans: [[Float]]) -> [Float] {
        guard let first = chans.first else { return [] }
        if chans.count == 1 { return first }
        var out = [Float](repeating: 0, count: first.count)
        for c in chans { for k in 0..<min(out.count, c.count) { out[k] += c[k] } }
        let s = 1 / Float(chans.count)
        for k in out.indices { out[k] *= s }
        return out
    }

    /// Cuts the quiet before and after the words.
    static func trim(_ x: [Float]) -> [Float] {
        guard let peak = x.map({ abs($0) }).max(), peak > 0 else { return [] }
        let gate = peak * powf(10, -45 / 20)
        guard let first = x.firstIndex(where: { abs($0) > gate }), let last = x.lastIndex(where: { abs($0) > gate }) else { return [] }
        let s = max(0, first - Int(0.01 * rate)), e = min(x.count, last + Int(0.03 * rate))
        return Array(x[s..<e])
    }

    static func resample(_ x: [Float], from r: Double) -> [Float] {
        guard r > 0, r != rate, x.count > 1 else { return x }
        let step = r / rate
        let n = Int(Double(x.count) / step)
        var y = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let p = Double(i) * step
            let j = Int(p)
            let f = Float(p - Double(j))
            y[i] = j + 1 < x.count ? x[j] * (1 - f) + x[j + 1] * f : x[min(j, x.count - 1)]
        }
        return y
    }

    /// The radio sound the original voice has: less mud, more sparkle, evened out.
    static func voiceChain(_ x: inout [Float]) {
        var hp = Biquad.highPass(100)
        var mud = Biquad.peak(400, db: -4, q: 0.8)
        var air = Biquad.highShelf(2500, db: 4.5)
        hp.run(&x)
        mud.run(&x)
        air.run(&x)
        compress(&x)
    }

    static func compress(_ x: inout [Float], thresholdDB: Float = -20, ratio: Float = 3, attack: Double = 0.004, release: Double = 0.09) {
        let ca = Float(exp(-1 / (attack * rate)))
        let cr = Float(exp(-1 / (release * rate)))
        var env: Float = 0
        for i in x.indices {
            let a = abs(x[i])
            env = a > env ? ca * env + (1 - ca) * a : cr * env + (1 - cr) * a
            let level = 20 * log10f(env + 1e-9)
            if level > thresholdDB { x[i] *= powf(10, (thresholdDB - level) * (1 - 1 / ratio) / 20) }
        }
    }

    /// The echo on the key words: repeats that fade and darken.
    static func echo(_ x: [Float], delay: Double, feedback: Float = 0.45, wet: Float = 0.55, lowPass: Double = 4500) -> [Float] {
        let d = max(1, Int(delay * rate))
        let n = x.count + d * 6
        var line = [Float](repeating: 0, count: n)
        var y = [Float](repeating: 0, count: n)
        let c = Float(exp(-2 * Double.pi * lowPass / rate))
        var z: Float = 0
        for i in 0..<n {
            let o: Float = i >= d ? line[i - d] : 0
            z = (1 - c) * o + c * z
            let input: Float = i < x.count ? x[i] : 0
            line[i] = input + feedback * z
            y[i] = input + wet * z
        }
        return y
    }

    /// How loud it is while there's talking (dBFS).
    static func activeDB(_ x: [Float]) -> Float {
        let hop = Int(0.02 * rate)
        var frames: [Float] = []
        var k = 0
        while k + hop <= x.count {
            var s: Float = 0
            for i in k..<(k + hop) { s += x[i] * x[i] }
            frames.append(sqrtf(s / Float(hop)))
            k += hop
        }
        guard let top = frames.max(), top > 0 else { return -120 }
        let gate = top * powf(10, -35 / 20)
        let loud = frames.filter { $0 > gate }
        let ms = loud.reduce(Float(0)) { $0 + $1 * $1 } / Float(max(1, loud.count))
        return 10 * log10f(ms + 1e-12)
    }

    /// Reads a line faster without making it squeaky.
    static func stretch(_ x: [Float], by speed: Float) -> [Float] {
        guard speed > 1.01, !x.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(x.count)),
              let dest = input.floatChannelData else { return x }
        input.frameLength = AVAudioFrameCount(x.count)
        x.withUnsafeBufferPointer { src in
            if let base = src.baseAddress { dest[0].update(from: base, count: x.count) }
        }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        timePitch.rate = speed
        engine.attach(player)
        engine.attach(timePitch)
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        do {
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
            try engine.start()
        } catch {
            return x
        }
        player.scheduleBuffer(input, completionHandler: nil)
        player.play()
        let want = Int(Double(x.count) / Double(speed))
        guard let chunk = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096) else { return x }
        var out: [Float] = []
        out.reserveCapacity(want)
        while out.count < want {
            let ask = AVAudioFrameCount(min(4096, want - out.count))
            guard let status = try? engine.renderOffline(ask, to: chunk), status == .success,
                  let data = chunk.floatChannelData else { break }
            out.append(contentsOf: UnsafeBufferPointer(start: data[0], count: Int(chunk.frameLength)))
        }
        player.stop()
        engine.stop()
        return out.count > want / 2 ? out : x
    }

    struct Biquad {
        var b0: Float, b1: Float, b2: Float, a1: Float, a2: Float
        var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0

        init(_ b0: Double, _ b1: Double, _ b2: Double, _ a0: Double, _ a1: Double, _ a2: Double) {
            self.b0 = Float(b0 / a0)
            self.b1 = Float(b1 / a0)
            self.b2 = Float(b2 / a0)
            self.a1 = Float(a1 / a0)
            self.a2 = Float(a2 / a0)
        }

        static func highPass(_ f: Double, q: Double = 0.707) -> Biquad {
            let w = 2 * Double.pi * f / StingerMixer.rate, c = cos(w), al = sin(w) / (2 * q)
            return Biquad((1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + al, -2 * c, 1 - al)
        }

        static func peak(_ f: Double, db: Double, q: Double) -> Biquad {
            let a = pow(10, db / 40), w = 2 * Double.pi * f / StingerMixer.rate, c = cos(w), al = sin(w) / (2 * q)
            return Biquad(1 + al * a, -2 * c, 1 - al * a, 1 + al / a, -2 * c, 1 - al / a)
        }

        static func highShelf(_ f: Double, db: Double) -> Biquad {
            let a = pow(10, db / 40), w = 2 * Double.pi * f / StingerMixer.rate, c = cos(w), s = sin(w)
            let al = s / 2 * sqrt(2.0), sq = 2 * sqrt(a) * al
            return Biquad(a * ((a + 1) + (a - 1) * c + sq), -2 * a * ((a - 1) + (a + 1) * c), a * ((a + 1) + (a - 1) * c - sq),
                          (a + 1) - (a - 1) * c + sq, 2 * ((a - 1) - (a + 1) * c), (a + 1) - (a - 1) * c - sq)
        }

        mutating func run(_ x: inout [Float]) {
            for i in x.indices {
                let v = x[i]
                let o = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
                x2 = x1; x1 = v
                y2 = y1; y1 = o
                x[i] = o
            }
        }
    }

    static func failure(_ why: String) -> NSError {
        NSError(domain: "Cara", code: 40, userInfo: [NSLocalizedDescriptionKey: "Stinger: " + why])
    }
}
