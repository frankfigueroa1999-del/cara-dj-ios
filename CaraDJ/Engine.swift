import Foundation
import SwiftUI
import UIKit

struct Prepared {
    var file: URL
    var style: String
    var forUri: String
    var pauseMs: Int
    var talkMs: Int
    var introAtMs: Int
}

/// The DJ brain: watches Spotify, writes the lines, and jumps in at the right moment.
@MainActor
final class Engine: ObservableObject {
    let cfg = Config.shared
    let spotify = Spotify.shared
    private let audio = DJAudio()

    @Published var log: [String] = []
    @Published var now = Playback()
    @Published var running = false
    @Published var busy = false
    @Published var connected = false
    @Published var queued: String? = nil
    @Published var line = ""

    private var loop: Task<Void, Never>?
    private var lastPoll = Date.distantPast
    func lastPollReset() { lastPoll = Date.distantPast }
    private var lastUri = ""
    private var songsSince = 0
    private var nextAfter = 3
    private var lastStyle: String? = nil
    private var prepared: Prepared? = nil
    private var building = false
    private var forceBreak = false
    private var lastSting = -1

    // MARK: logging
    func addLog(_ s: String) {
        log.append(s)
        if log.count > 80 { log.removeFirst(log.count - 80) }
        print(s)
    }
    private func logger() -> (String) -> Void {
        return { [weak self] msg in Task { @MainActor in self?.addLog(msg) } }
    }

    // MARK: connecting
    func connect() async {
        do {
            if !spotify.isLoggedIn { try await spotify.login() }
            if let p = await spotify.poll() { now = p; connected = true; addLog("Connected to Spotify.") }
            else {
                connected = false
                switch spotify.lastStatus {
                case 403: addLog("Spotify refused this account (error 403). Spotify apps in development mode only work for accounts added under User Management in the developer dashboard. Add your Spotify email there (or use your own Client ID in Settings), then log out and back in.")
                case 401: addLog("Spotify login expired or was rejected (error 401). Open Settings, log out of Spotify, and connect again.")
                case 429: addLog("Spotify says slow down (error 429). Wait a minute and try again.")
                case 0: addLog("Couldn't reach Spotify. Check the internet connection.")
                default: addLog("Couldn't read playback (Spotify error \(spotify.lastStatus)). Play something in the Spotify app, then try again.")
                }
            }
        } catch {
            connected = false
            addLog("Could not connect: \(error.localizedDescription)")
        }
    }

    func startBackgroundPolling() {
        // keeps the "now playing" card fresh even when the DJ is off
        Task { @MainActor in
            while true {
                if !running, spotify.isLoggedIn {
                    if let p = await spotify.poll() { now = p; connected = true }
                }
                try? await Task.sleep(nanoseconds: 12_000_000_000)
            }
        }
    }

    // MARK: start / stop
    func start() {
        guard connected else { addLog("Connect Spotify first."); return }
        guard !running else { return }
        running = true
        songsSince = 0; lastUri = ""; prepared = nil; lastStyle = nil; queued = nil
        nextAfter = rollInterval()
        audio.startIdle()
        UIApplication.shared.isIdleTimerDisabled = false
        addLog("DJ is live. You can lock the screen: it keeps working in the background.")
        loop = Task { @MainActor in
            while self.running {
                await self.tick()
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }

    func stop() {
        running = false
        loop?.cancel(); loop = nil
        if let p = prepared { try? FileManager.default.removeItem(at: p.file) }
        prepared = nil
        audio.stopIdle()
        addLog("DJ stopped.")
    }

    private func rollInterval() -> Int {
        let lo = max(1, cfg.breakMin), hi = max(lo, cfg.breakMax)
        let n = randInt(lo, hi)
        addLog("Next DJ break after \(n) song\(n == 1 ? "" : "s").")
        return n
    }

    // MARK: queue / test buttons
    func queue(_ style: String) {
        guard running, now.isPlaying else { addLog("Start the DJ and play a song first."); return }
        queued = style
        addLog("Queued: \(style) transition, coming up at the end of this song.")
    }

    func testBreak() {
        guard running, now.isPlaying else { addLog("Start the DJ and play a song first."); return }
        forceBreak = true
    }

    func testStinger() async {
        guard let url = pickStinger() else { addLog("No stingers found in the app."); return }
        if !running { audio.startIdle() }
        await audio.speak([(url, Float(cfg.stingerVolume / 100))])
        if !running { audio.stopIdle() }
    }

    // MARK: the loop
    private func pickStinger() -> URL? {
        let all = (Bundle.main.urls(forResourcesWithExtension: "mp3", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.lowercased().contains("stinger") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !all.isEmpty else { return nil }
        var i = randInt(0, all.count - 1)
        if all.count > 1 { while i == lastSting { i = randInt(0, all.count - 1) } }
        lastSting = i
        return all[i]
    }

    private func tick() async {
        if busy { return }
        let remainingEst = now.remainingMs
        let near = remainingEst != Int.max && (remainingEst < 12000 || prepared?.style == "intro")
        let interval: TimeInterval = near ? 1.2 : 6
        if Date().timeIntervalSince(lastPoll) >= interval {
            lastPoll = Date()
            if let p = await spotify.poll() {
                now = p
                connected = true
                if p.hasItem && p.uri != lastUri {
                    lastUri = p.uri
                    songsSince += 1
                }
            } else { return }
        }
        guard running, now.isPlaying, now.hasItem else { return }
        let remaining = now.remainingMs
        let progress = now.currentProgressMs
        let forced = queued
        let due = songsSince >= nextAfter || forced != nil

        if let f = forced, let p = prepared, p.style != f {           // a different style was already written: redo it
            try? FileManager.default.removeItem(at: p.file)
            prepared = nil
        }

        if forceBreak && !building {
            forceBreak = false
            addLog("Testing a DJ break...")
            await buildBreak(style: "intro", forUri: now.uri, immediate: true)
            return
        }

        if due && prepared == nil && !building && (remaining < 90000 || forced != nil) {
            let style = forced ?? pickStyle()
            Task { @MainActor in await self.buildBreak(style: style, forUri: self.now.uri, immediate: false) }
        }

        if due, let p = prepared {
            var go = false
            switch p.style {
            case "silent":   go = now.uri == p.forUri && remaining <= p.pauseMs
            // if the clip finished after its song ended, talk over the start of the next song instead of losing the break
            case "talkover": go = now.uri == p.forUri ? remaining <= p.talkMs : progress >= 1200
            default:         go = now.uri != p.forUri && progress >= p.introAtMs
            }
            if go {
                let late = p.style == "talkover" && now.uri != p.forUri
                prepared = nil
                songsSince = 0
                lastStyle = p.style
                queued = nil
                nextAfter = rollInterval()
                addLog(late ? "[transition: talkover (late, over the start of this song)]" : "[transition: \(p.style)]")
                await perform(p)
            } else if p.style != "intro" && now.uri != p.forUri {
                try? FileManager.default.removeItem(at: p.file)
                prepared = nil                                      // missed its moment; it will be rebuilt
            }
        }
    }

    private func pickStyle() -> String {
        let all: [String] = ["talkover", "intro", "silent"].filter { $0 != lastStyle }
        return weightedStyle(all)
    }
    private func weightedStyle(_ names: [String]) -> String {
        let w: [String: Int] = ["talkover": 4, "intro": 3, "silent": 2]
        return weightedPick(names.map { ($0, w[$0] ?? 1) })
    }

    private func buildBreak(style: String, forUri: String, immediate: Bool) async {
        building = true
        defer { building = false }
        let ctx = Ctx(last: now.track, next: await spotify.nextTrack())
        let topic = await pickTopic(ctx: ctx, cfg: cfg)
        let mood = currentMood(cfg)
        addLog("[topic: \(topic.label)] [mood: \(mood)]")
        let text = await writeBreak(style: style, topic: topic, ctx: ctx, cfg: cfg, mood: mood, log: logger())
        addLog("[DJ:\(style)] \(text)")
        line = text
        do {
            let data = try await elevenLabsTTS(text, cfg: cfg)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("dj_\(Int(Date().timeIntervalSince1970))_\(Int.random(in: 0..<999)).mp3")
            try data.write(to: file)
            let ms = Int(DJAudio.duration(of: file) * 1000)
            let p = Prepared(file: file, style: style, forUri: forUri,
                             pauseMs: randInt(700, 1100),
                             talkMs: max(4000, min(12000, ms - randInt(2000, 4500))),
                             introAtMs: randInt(500, 2500))
            if immediate {
                busy = true
                await perform(p)
            } else {
                prepared = p
            }
        } catch {
            addLog("Could not make her voice: \(error.localizedDescription)")
            if queued != nil { queued = nil }
        }
    }

    // MARK: doing the transition
    private func perform(_ p: Prepared) async {
        busy = true
        defer { busy = false; lastPoll = Date.distantPast }
        let voiceVol = Float(cfg.djVolume / 100)
        var items: [(url: URL, volume: Float)] = []
        switch p.style {
        case "silent":
            let device = now.deviceID
            let uri = now.uri
            await spotify.pause()
            if Double(randInt(0, 99)) < Double(cfg.stingerChance), let s = pickStinger() {
                addLog("[stinger before Cara]")
                items.append((s, Float(cfg.stingerVolume / 100)))
            }
            items.append((p.file, voiceVol))
            await audio.speak(items)
            try? await Task.sleep(nanoseconds: 200_000_000)
            if let cur = await spotify.poll(), cur.uri == uri { await spotify.skipNext(); try? await Task.sleep(nanoseconds: 300_000_000) }
            await resumeMusic(device: device)
        default:
            items.append((p.file, voiceVol))
            await audio.speak(items)      // iOS turns the Spotify app down while she talks
        }
        try? FileManager.default.removeItem(at: p.file)
    }

    /// Gets the music going again, retrying: Spotify is often busy for a second right after a skip.
    private func resumeMusic(device: String?) async {
        for attempt in 0..<6 {
            let cur = await spotify.poll()
            if let c = cur, c.isPlaying { return }
            // only ever this phone: never another device such as a speaker or soundbar
            let found = await spotify.phoneDevice()
            guard let dev = found ?? device else {
                addLog("Can't find this phone in Spotify. Open the Spotify app, then tap PLAY.")
                return
            }
            if attempt >= 3 {
                await spotify.transfer(to: dev)          // last resort: wake the Spotify app on this phone
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            } else {
                await spotify.play(device: dev)
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
        addLog("Spotify didn't restart by itself. Tap PLAY.")
    }

    // MARK: player buttons
    func togglePlay() async {
        if now.isPlaying { await spotify.pause() } else { await resumeMusic(device: now.deviceID) }
        lastPoll = Date.distantPast
        if let p = await spotify.poll() { now = p }
    }
    func toggleShuffle() async {
        let on = !now.shuffle
        now.shuffle = on
        await spotify.setShuffle(on)
        lastPoll = Date.distantPast
    }
    func cycleRepeat() async {
        var next = "off"
        if now.repeatMode == "off" { next = "context" } else if now.repeatMode == "context" { next = "track" }
        now.repeatMode = next
        await spotify.setRepeat(next)
        lastPoll = Date.distantPast
    }
    func seek(_ ms: Int) async {
        now.progressMs = ms
        now.stamp = Date()
        await spotify.seek(ms)
        lastPoll = Date.distantPast
    }
    func next() async { await spotify.skipNext(); lastPoll = Date.distantPast }
    func previous() async { await spotify.skipPrevious(); lastPoll = Date.distantPast }

    func changeCity(_ city: String) async {
        let c = city.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty, c != cfg.city else { return }
        cfg.city = c
        if let g = await geocodeCity(c) { cfg.lat = g.lat; cfg.lon = g.lon }
        else { addLog("Couldn't find that town's location; weather may be for the old town.") }
    }
}
