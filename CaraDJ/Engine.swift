import Foundation
import SwiftUI
import UIKit
import Observation

struct Prepared {
    var file: URL
    var style: String
    var forUri: String
    var pauseMs: Int
    var talkMs: Int
    var introAtMs: Int
}

/// The heart of the app: keeps an eye on Spotify for the screens, runs the player buttons,
/// and (when Cara is live) writes her lines and jumps in at the right moment.
@MainActor
@Observable
final class Engine {
    let cfg = Config.shared
    let spotify = Spotify.shared
    private let audio = DJAudio()

    // MARK: what the screens show
    var log: [String] = []
    var now = Playback()
    var running = false
    var busy = false
    /// Cara (or a stinger) is coming out of the speaker right now.
    var speaking = false
    var connected = false
    var queued: String? = nil
    var line = ""
    var lineStyle = ""
    var upNext: [Track] = []
    var contextName = ""
    var currentLiked: Bool? = nil
    var devices: [Device] = []
    /// Shown straight away after you tap a song or skip, until Spotify confirms it.
    var pendingItem: Track? = nil
    var sleepAt: Date? = nil
    var sleepAtTrackEnd = false
    /// Spotify couldn't find anywhere to play (the Spotify app is closed).
    var noDevice = false
    var foreground = true

    var displayItem: Track? { pendingItem ?? now.item }

    // MARK: inside
    private var loop: Task<Void, Never>? = nil
    private var lastPoll = Date.distantPast
    private var fastUntil = Date.distantPast
    private var lastOfflineLog = Date.distantPast
    private var buildRetryAt = Date.distantPast
    private var pendingSince = Date.distantPast
    private var lastUri = ""          // the DJ's idea of the current song
    private var shownUri = ""         // the screen's idea of the current song
    private var lastContext = ""
    private(set) var songsSince = 0
    private(set) var nextAfter = 3
    private var lastStyle: String? = nil
    private(set) var prepared: Prepared? = nil
    private var building = false
    private var forceBreak = false
    private var lastSting = -1

    // pop-in: a quick second drop-in a few seconds into the song after a talk-over / intro break
    private var popinArmed = false
    private var popinUri: String? = nil
    private var popinAt = 0
    private var popinFile: URL? = nil
    private var popinBuilding = false
    private var popinForce = false
    private var popinTestNow = false

    var popinWaiting: Bool { popinFile != nil || popinBuilding }

    /// Where Cara will talk in "Playing Next": just before upNext[slot]. nil when she's off air.
    var breakSlot: Int? {
        guard running else { return nil }
        if queued != nil { return 0 }
        return max(0, nextAfter - songsSince)
    }

    var statusLine: String {
        if speaking { return "On the mic right now" }
        if !running { return "Off air" }
        if busy { return "Getting ready to talk" }
        if let s = breakSlot {
            if s == 0 { return prepared != nil ? "Ready to talk after this song" : "Back after this song" }
            return "Next break in \(s + 1) songs"
        }
        return "Live"
    }

    // MARK: logging
    func addLog(_ s: String) {
        log.append(s)
        if log.count > 120 { log.removeFirst(log.count - 120) }
        print(s)
    }
    private func logger() -> (String) -> Void {
        return { [weak self] msg in Task { @MainActor in self?.addLog(msg) } }
    }

    // MARK: connecting
    func connect(forceLogin: Bool = false) async {
        do {
            if forceLogin || !spotify.isLoggedIn { try await spotify.login() }
            if let p = await spotify.poll() {
                apply(p)
                addLog("Connected to Spotify.")
            } else {
                connected = false
                switch spotify.lastStatus {
                case 403: addLog("Spotify refused this account (error 403). Spotify apps in development mode only work for accounts added under User Management in the developer dashboard (5 people at most). Add your Spotify email there, then log out and back in.")
                case 401: addLog("Spotify login expired or was rejected (error 401). Open Settings, log out of Spotify, and connect again.")
                case 429: addLog("Spotify says slow down (error 429). Wait a minute and try again.")
                case 0: addLog("Couldn't reach Spotify. Check the internet connection.")
                default: addLog("Couldn't read playback (Spotify error \(spotify.lastStatus)). Play something in the Spotify app, then try again.")
                }
            }
            await Library.shared.loadAll(force: true)
        } catch {
            connected = false
            addLog("Could not connect: \(error.localizedDescription)")
            Toasts.shared.show("Couldn't connect to Spotify", "exclamationmark.triangle.fill")
        }
    }

    /// Starts the one loop that keeps everything up to date. Safe to call more than once.
    func boot() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                await self.cycle()
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }

    /// Check Spotify again right away (and quickly for a few seconds), e.g. after a button press.
    func poke() {
        lastPoll = Date.distantPast
        fastUntil = Date().addingTimeInterval(4)
    }

    private func cycle() async {
        if running {
            await tick()
        } else if spotify.isLoggedIn {
            let near = now.isPlaying && now.hasItem && now.remainingMs < 3500
            var interval: TimeInterval = foreground ? 5 : 30
            if sleepAt != nil || sleepAtTrackEnd { interval = min(interval, 10) }
            if foreground && (near || Date() < fastUntil) { interval = 1 }
            if Date().timeIntervalSince(lastPoll) >= interval {
                lastPoll = Date()
                if let p = await spotify.poll() { apply(p) }
            }
        }
        await checkSleep()
        if pendingItem != nil && Date().timeIntervalSince(pendingSince) > 5 { pendingItem = nil }
    }

    /// Take in a fresh reading from Spotify, and react when the song changes.
    private func apply(_ p: Playback) {
        now = p
        connected = true
        if p.hasItem { noDevice = false }
        if p.uri != shownUri {
            shownUri = p.uri
            pendingItem = nil
            songChanged()
        } else if let pend = pendingItem, pend.uri == p.uri {
            pendingItem = nil
        }
        if p.contextURI != lastContext {
            lastContext = p.contextURI
            Task { await self.loadContextName() }
        }
    }

    private func songChanged() {
        currentLiked = nil
        Task {
            await self.refreshQueue()
            await self.refreshLiked()
        }
    }

    func refreshQueue() async {
        upNext = await spotify.queue()
    }

    func refreshLiked() async {
        guard let it = now.item, !it.uri.isEmpty, !it.isLocal else { currentLiked = nil; return }
        let uri = it.uri
        if let known = Library.shared.likedState[uri] { currentLiked = known }
        if let r = await spotify.contains([uri]), let v = r.first, now.item?.uri == uri {
            currentLiked = v
            Library.shared.likedState[uri] = v
        }
    }

    private func loadContextName() async {
        let c = lastContext
        if c.isEmpty { contextName = ""; return }
        let name = await spotify.contextName(c)
        if c == lastContext { contextName = name ?? "" }
    }

    // MARK: start / stop the DJ
    func start() {
        guard connected else { addLog("Connect Spotify first."); Toasts.shared.show("Connect Spotify first", "exclamationmark.triangle.fill"); return }
        guard !running else { return }
        running = true
        songsSince = 0; lastUri = ""; prepared = nil; lastStyle = nil; queued = nil
        dropPopin()
        nextAfter = rollInterval()
        audio.startIdle()
        UIApplication.shared.isIdleTimerDisabled = false
        addLog("DJ is live. You can lock the screen: it keeps working in the background.")
        lastPoll = Date.distantPast
    }

    func stop() {
        running = false
        if let p = prepared { try? FileManager.default.removeItem(at: p.file) }
        prepared = nil
        queued = nil
        dropPopin()
        if sleepAt == nil && !sleepAtTrackEnd { audio.stopIdle() }
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
        guard running, now.isPlaying else { addLog("Start the DJ and play a song first."); Toasts.shared.show("Go live and play a song first", "dot.radiowaves.left.and.right"); return }
        queued = style
        addLog("Queued: \(style) transition, coming up at the end of this song.")
        Toasts.shared.show("Cara's on after this song", "dot.radiowaves.left.and.right")
    }

    func testBreak() {
        guard running, now.isPlaying else { addLog("Start the DJ and play a song first."); Toasts.shared.show("Go live and play a song first", "dot.radiowaves.left.and.right"); return }
        forceBreak = true
    }

    func testPopin() {
        guard running, now.isPlaying else { addLog("Start the DJ and play a song first."); Toasts.shared.show("Go live and play a song first", "dot.radiowaves.left.and.right"); return }
        popinTestNow = true
    }

    func testStinger() async {
        guard let url = pickStinger() else { addLog("No stingers found in the app."); return }
        if !running { audio.startIdle() }
        speaking = true
        await audio.speak([(url, Float(cfg.stingerVolume / 100))])
        speaking = false
        if !running && sleepAt == nil && !sleepAtTrackEnd { audio.stopIdle() }
    }

    // MARK: the DJ loop
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
        let interval: TimeInterval = (near || Date() < fastUntil) ? 1.2 : 6
        if Date().timeIntervalSince(lastPoll) >= interval {
            lastPoll = Date()
            if let p = await spotify.poll() {
                apply(p)
                if p.hasItem && p.uri != lastUri {
                    lastUri = p.uri
                    songsSince += 1
                    if popinFile != nil, popinUri != p.uri, !popinForce { dropPopin() }
                    if popinArmed {
                        popinArmed = false
                        if cfg.popinEnabled && !popinBuilding && popinFile == nil {
                            planPopin(p.track, uri: p.uri, duration: p.durationMs)
                        } else {
                            addLog("[pop-in skipped: " + (cfg.popinEnabled ? "still busy with the last one" : "turned off") + "]")
                        }
                    }
                }
            } else {
                // can't reach Spotify for a moment (busy, rate limit, bad signal): carry on with our own clock so the break isn't missed
                if !(running && now.isPlaying && now.hasItem && now.remainingMs > -2000) { return }
                if Date().timeIntervalSince(lastOfflineLog) > 30 { lastOfflineLog = Date(); addLog("Spotify isn't answering, using my own clock for now.") }
            }
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

        // test button: make a pop-in for the current song and play it as soon as it is ready
        if popinTestNow && !popinBuilding && popinFile == nil {
            popinTestNow = false
            addLog("Testing pop-in...")
            popinUri = now.uri; popinAt = 0; popinForce = true
            let t = now.track, u = now.uri
            Task { @MainActor in await self.buildPopin(t, uri: u) }
        }

        // pop-in: once its clip is ready and we are a few seconds into the song, and a break isn't about to start
        if let file = popinFile {
            if popinForce || (now.uri == popinUri && progress >= popinAt && remaining > 25000) {
                popinFile = nil; popinUri = nil; popinForce = false
                addLog("[pop-in]")
                await playPopin(file)
                return
            }
            if now.uri != popinUri { dropPopin() }
        }

        if due && prepared == nil && !building && Date() >= buildRetryAt && (remaining < 150000 || forced != nil) {
            let style = forced ?? pickStyle()
            Task { @MainActor in await self.buildBreak(style: style, forUri: self.now.uri, immediate: false) }
        }

        if due, let p = prepared {
            var go = false
            switch p.style {
            // a silent break that missed its moment (song changed first) talks over the start of the next song instead of being thrown away
            case "silent":   go = now.uri == p.forUri ? remaining <= p.pauseMs : progress >= 1200
            // if the clip finished after its song ended, talk over the start of the next song instead of losing the break
            case "talkover": go = now.uri == p.forUri ? remaining <= p.talkMs : progress >= 1200
            default:         go = now.uri != p.forUri && progress >= p.introAtMs
            }
            if go {
                let late = (p.style == "talkover" || p.style == "silent") && now.uri != p.forUri
                prepared = nil
                songsSince = 0
                lastStyle = p.style
                queued = nil
                nextAfter = rollInterval()
                addLog(late ? "[transition: talkover (late, over the start of this song)]" : "[transition: \(p.style)]")
                if cfg.popinEnabled && (p.style != "silent" || late) {
                    if cfg.popinTest || randInt(0, 99) < cfg.popinChance {
                        if late || p.style == "intro" {          // already inside the new song
                            planPopin(now.track, uri: now.uri, duration: now.durationMs)
                        } else {
                            popinArmed = true
                            addLog("[pop-in lined up for the next song]")
                        }
                    } else {
                        addLog("[no pop-in after this one (\(cfg.popinChance)% chance each time)]")
                    }
                }
                await perform(p, late: late)
            } else if p.style != "intro" && now.uri != p.forUri && progress > 20000 {
                try? FileManager.default.removeItem(at: p.file)
                addLog("[a break missed its moment, rebuilding it]")
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
        lineStyle = style
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
                await perform(p, late: false)
            } else {
                prepared = p
            }
        } catch {
            addLog("Could not make her voice: \(error.localizedDescription). Trying again in a few seconds.")
            buildRetryAt = Date().addingTimeInterval(20)
            if queued != nil { queued = nil }
        }
    }

    // MARK: doing the transition
    private func perform(_ p: Prepared, late: Bool = false) async {
        busy = true
        defer { busy = false; lastPoll = Date.distantPast }
        let voiceVol = Float(cfg.djVolume / 100)
        var items: [(url: URL, volume: Float)] = []
        switch p.style {
        case "silent" where !late:
            let device = now.deviceID
            let uri = now.uri
            if Double(randInt(0, 99)) < Double(cfg.stingerChance), let s = pickStinger() {
                addLog("[stinger before Cara]")
                items.append((s, Float(cfg.stingerVolume / 100)))
            }
            items.append((p.file, voiceVol))
            // iOS pauses the Spotify app itself while she talks, and lets it carry on when she's done
            speaking = true
            await audio.speakPausing(items)
            speaking = false
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            // if the old song is still the current one (it was about a second from its end), jump on to the next song
            if let cur = await spotify.poll(), cur.uri == uri {
                await spotify.skipNext()
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
            await resumeMusic(device: device)          // only does anything if Spotify didn't carry on by itself
        default:
            items.append((p.file, voiceVol))
            speaking = true
            await audio.speak(items)      // iOS turns the Spotify app down while she talks
            speaking = false
        }
        try? FileManager.default.removeItem(at: p.file)
    }

    // MARK: pop-in
    private func planPopin(_ t: Track?, uri: String, duration: Int) {
        if popinBuilding || popinFile != nil { return }
        let after = max(5, cfg.popinSeconds)
        let jitter = min(5, after / 2)
        let at = after * 1000 + randInt(-jitter * 1000, jitter * 1000)
        guard duration >= at + 40000 else { addLog("[pop-in skipped: this song is too short for one]"); return }
        popinUri = uri; popinAt = at; popinForce = false
        addLog("[pop-in planned about \(at / 1000)s into this song]")
        Task { @MainActor in await self.buildPopin(t, uri: uri) }
    }

    private func buildPopin(_ t: Track?, uri: String) async {
        popinBuilding = true
        defer { popinBuilding = false }
        let text = await writePopIn(track: t, cfg: cfg, log: logger())
        addLog("[POP-IN] \(text)")
        do {
            let data = try await elevenLabsTTS(text, cfg: cfg)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("popin_\(Int(Date().timeIntervalSince1970))_\(Int.random(in: 0..<999)).mp3")
            try data.write(to: file)
            popinFile = file
            line = text
            lineStyle = "pop-in"
            addLog("[pop-in ready, waiting for its moment]")
        } catch {
            addLog("Could not make the pop-in voice: \(error.localizedDescription)")
            popinUri = nil
            popinForce = false
        }
    }

    private func playPopin(_ file: URL) async {
        busy = true
        defer { busy = false; lastPoll = Date.distantPast }
        speaking = true
        await audio.speak([(file, Float(cfg.djVolume / 100))])      // iOS turns the Spotify app down while she talks
        speaking = false
        try? FileManager.default.removeItem(at: file)
    }

    private func dropPopin() {
        if let f = popinFile { try? FileManager.default.removeItem(at: f) }
        popinFile = nil; popinUri = nil; popinArmed = false; popinForce = false
    }

    /// Gets the music going again, and keeps trying for up to two minutes: Spotify is often busy for a second right after a skip, or asks us to slow down.
    private func resumeMusic(device: String?) async {
        let started = Date()
        var attempt = 0
        var warned = false
        var noDeviceLogged = false
        while Date().timeIntervalSince(started) < 120 {
            let cur = await spotify.poll()
            if let c = cur, c.isPlaying { return }
            // only ever this phone: never another device such as a speaker or soundbar
            let found = await spotify.phoneDevice()
            if let dev = found ?? device {
                var status = 0
                if attempt % 4 == 3 {
                    await spotify.transfer(to: dev)          // every few tries: wake the Spotify app on this phone
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                } else {
                    status = await spotify.play(device: dev)
                    try? await Task.sleep(nanoseconds: 800_000_000)
                }
                if status >= 400 && status != 403 && !warned {
                    warned = true
                    addLog("Spotify said \(status) when restarting the music. Still trying...")
                }
            } else {
                if !noDeviceLogged { noDeviceLogged = true; addLog("Can't find this phone in Spotify yet. Open the Spotify app, then tap PLAY.") }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
            let wait = spotify.blockedUntil.timeIntervalSinceNow          // Spotify asked us to slow down: wait it out
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(min(wait + 0.3, 8) * 1_000_000_000)) }
            attempt += 1
        }
        addLog("Spotify didn't restart by itself. Tap PLAY.")
    }

    // MARK: player buttons
    /// Where to send "play": whatever is playing now, otherwise this phone.
    private func playTarget() async -> String? {
        if let d = now.deviceID, !d.isEmpty { return d }
        return await spotify.phoneDevice()
    }

    private func report(_ status: Int) {
        if status == 404 || status == 0 && !spotify.isLoggedIn {
            noDevice = true
            Toasts.shared.show("Open Spotify on this iPhone first", "exclamationmark.triangle.fill")
        } else if status == 403 {
            Toasts.shared.show("Spotify Premium is needed for that", "exclamationmark.triangle.fill")
        } else if status == 429 {
            Toasts.shared.show("Spotify says slow down. Try again in a moment", "hourglass")
        } else if status >= 400 || status == 0 {
            Toasts.shared.show("Spotify couldn't do that (\(status))", "exclamationmark.triangle.fill")
        }
    }

    func togglePlay() async {
        if now.isPlaying {
            now.progressMs = now.currentProgressMs; now.stamp = Date(); now.isPlaying = false
            await spotify.pause()
        } else {
            now.progressMs = now.currentProgressMs; now.stamp = Date(); now.isPlaying = true
            var st = await spotify.play(device: now.deviceID)
            if st == 404 || st == 0 {
                if let phone = await spotify.phoneDevice() {
                    st = await spotify.play(device: phone)
                }
            }
            if st >= 400 || st == 0 { now.isPlaying = false; report(st == 0 ? 404 : st) }
        }
        poke()
    }

    func next() async {
        if let n = upNext.first {
            pendingItem = n
            pendingSince = Date()
            upNext.removeFirst()
        }
        await spotify.skipNext()
        poke()
    }

    func previous() async {
        if now.currentProgressMs > 4000 {
            await seek(0)
            return
        }
        await spotify.skipPrevious()
        poke()
    }

    func toggleShuffle() async {
        let on = !now.shuffle
        now.shuffle = on
        await spotify.setShuffle(on)
        poke()
        try? await Task.sleep(nanoseconds: 700_000_000)
        await refreshQueue()
    }

    func cycleRepeat() async {
        var next = "off"
        if now.repeatMode == "off" { next = "context" } else if now.repeatMode == "context" { next = "track" }
        now.repeatMode = next
        await spotify.setRepeat(next)
        poke()
    }

    func seek(_ ms: Int) async {
        now.progressMs = ms
        now.stamp = Date()
        await spotify.seek(ms)
        poke()
    }

    /// Play an album / playlist / artist, optionally starting at a song, or shuffled.
    func playContext(_ uri: String, startAt trackURI: String? = nil, shuffle: Bool = false, count: Int = 0, preview: Track? = nil) async {
        if let p = preview { pendingItem = p; pendingSince = Date() }
        let dev = await playTarget()
        var position: Int? = nil
        if shuffle && trackURI == nil && count > 1 { position = Int.random(in: 0..<count) }
        let st = await spotify.startPlayback(context: uri, offsetURI: trackURI, position: position, device: dev)
        if st >= 200 && st < 300 {
            await spotify.setShuffle(shuffle, device: dev)
            now.shuffle = shuffle
        } else {
            pendingItem = nil
            report(st)
        }
        poke()
    }

    /// Play a list of songs (Liked Songs, search results, top songs), starting at one of them.
    func playTracks(_ list: [Track], startAt index: Int, shuffle: Bool = false, context: String? = nil) async {
        let playable = list.filter { !$0.uri.isEmpty && !$0.isLocal }
        guard !playable.isEmpty else { return }
        var first: Track = playable[0]
        if shuffle {
            first = playable.randomElement() ?? playable[0]
        } else if index >= 0 && index < list.count {
            let picked = list[index]
            if !picked.uri.isEmpty && !picked.isLocal { first = picked }
        }
        pendingItem = first
        pendingSince = Date()
        let dev = await playTarget()
        // first try the real collection (Liked Songs), so Spotify carries on through all of it
        if let c = context {
            let st = await spotify.startPlayback(context: c, offsetURI: first.uri, device: dev)
            if st >= 200 && st < 300 {
                await spotify.setShuffle(shuffle, device: dev)
                now.shuffle = shuffle
                poke()
                return
            }
        }
        var uris: [String] = []
        if shuffle {
            uris = [first.uri] + playable.filter { $0.uri != first.uri }.shuffled().map { $0.uri }
        } else {
            let k = playable.firstIndex(where: { $0.uri == first.uri }) ?? 0
            uris = playable[k...].map { $0.uri }
        }
        let st = await spotify.startPlayback(context: nil, uris: Array(uris.prefix(100)), device: dev)
        if st >= 200 && st < 300 {
            await spotify.setShuffle(false, device: dev)
            now.shuffle = false
        } else {
            pendingItem = nil
            report(st)
        }
        poke()
    }

    func addToQueue(_ t: Track) async {
        let st = await spotify.addToQueue(t.uri, device: now.deviceID)
        if st >= 200 && st < 300 {
            Toasts.shared.show("Added to Queue", "text.line.last.and.arrowtriangle.forward")
            try? await Task.sleep(nanoseconds: 700_000_000)
            await refreshQueue()
        } else {
            report(st)
        }
    }

    /// Skip ahead to a song further down "Playing Next".
    func skip(to index: Int) async {
        guard index >= 0, index < upNext.count, index < 15 else { return }
        pendingItem = upNext[index]
        pendingSince = Date()
        for _ in 0...index {
            await spotify.skipNext()
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        poke()
    }

    func toggleLikeCurrent() async {
        guard let it = now.item, !it.uri.isEmpty, !it.isLocal else { return }
        let want = !(currentLiked ?? false)
        currentLiked = want
        let ok = await Library.shared.setLiked(it, want)
        if !ok { currentLiked = !want }
    }

    func loadDevices() async {
        devices = await spotify.devices()
    }

    func transfer(to d: Device) async {
        await spotify.transfer(to: d.id)
        poke()
        try? await Task.sleep(nanoseconds: 900_000_000)
        await loadDevices()
    }

    // MARK: sleep timer
    func setSleep(minutes: Int?) {
        sleepAtTrackEnd = false
        if let m = minutes {
            sleepAt = Date().addingTimeInterval(Double(m) * 60)
            audio.startIdle()                  // keeps the app awake in the background so the timer can fire
            Toasts.shared.show("Sleep timer: \(m) minutes", "moon.zzz.fill")
        } else {
            sleepAt = nil
            if !running { audio.stopIdle() }
            Toasts.shared.show("Sleep timer off", "moon.zzz")
        }
    }

    func setSleepAtEndOfSong() {
        sleepAt = nil
        sleepAtTrackEnd = true
        audio.startIdle()
        Toasts.shared.show("Stopping after this song", "moon.zzz.fill")
    }

    private func checkSleep() async {
        if let s = sleepAt, Date() >= s {
            sleepAt = nil
            await sleepNow()
        } else if sleepAtTrackEnd, now.isPlaying, now.hasItem, now.remainingMs < 1500 {
            sleepAtTrackEnd = false
            await sleepNow()
        }
    }

    private func sleepNow() async {
        addLog("Sleep timer: goodnight.")
        if running { stop() }
        await spotify.pause()
        now.progressMs = now.currentProgressMs
        now.stamp = Date()
        now.isPlaying = false
        audio.stopIdle()
        poke()
    }

    func changeCity(_ city: String) async {
        let c = city.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty, c != cfg.city else { return }
        cfg.city = c
        if let g = await geocodeCity(c) { cfg.lat = g.lat; cfg.lon = g.lon }
        else { addLog("Couldn't find that town's location; weather may be for the old town.") }
    }

    func logout() {
        if running { stop() }
        spotify.logout()
        connected = false
        now = Playback()
        upNext = []
        shownUri = ""
        Library.shared.clear()
    }
}
