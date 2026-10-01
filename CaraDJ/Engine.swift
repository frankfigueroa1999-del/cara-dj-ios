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
    /// What the app calls a list of songs it started itself with no playlist behind it (Liked Songs, an artist's top songs, a mood).
    var localStation = ""
    var currentLiked: Bool? = nil
    var devices: [Device] = []
    /// Shown straight away after you tap a song or skip, until Spotify confirms it.
    var pendingItem: Track? = nil
    var sleepAt: Date? = nil
    var sleepAtTrackEnd = false
    /// Spotify couldn't find anywhere to play (the Spotify app is closed).
    var noDevice = false
    var foreground = true
    /// Logged in to Spotify (kept here so every screen notices the moment it changes).
    var loggedIn: Bool = Spotify.shared.isLoggedIn
    /// Why Spotify isn't working right now, in plain words ("" when all is well).
    var problem = ""

    var displayItem: Track? { pendingItem ?? now.item }

    /// Where the music's coming from, as Spotify names it ("" when it isn't from anything in particular).
    var playingFrom: String { now.contextURI.isEmpty ? localStation : contextName }
    /// The station takes the name of whatever's playing ("Late Night Drives"); Non Stop Pop when nothing nameable is.
    var stationName: String {
        let n = Station.clean(playingFrom)
        return n.isEmpty ? Station.fallback : n
    }
    /// On air: "Late Night Drives FM".
    var stationFull: String { Station.full(stationName) }
    /// What the station's named after, in Cara's words ("" for plain old Non Stop Pop).
    var stationNote: String {
        let name = stationName
        if name == Station.fallback { return "" }
        if now.contextURI.isEmpty { return "\"\(name)\"" }
        switch Station.kind(now.contextURI) {
        case "playlist": return "the playlist \"\(name)\""
        case "album": return "the album \"\(name)\""
        case "artist": return "songs by \(name)"
        case "collection": return "the listener's Liked Songs"
        default: return "\"\(name)\""
        }
    }

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
    /// Names of playlists / albums / artists we've seen, so the station is named the moment one starts.
    @ObservationIgnored private var contextNames: [String: String] = (UserDefaults.standard.dictionary(forKey: "contextNames") as? [String: String]) ?? [:]
    @ObservationIgnored private var contextTries = 0
    @ObservationIgnored private var contextRetryAt = Date.distantPast
    @ObservationIgnored private var loggedStation = ""
    @ObservationIgnored private var stationAtLastBreak = ""
    // right after you press a button Spotify can still report the old state for a moment; keep ours briefly
    private var holdUntil = Date.distantPast
    private var heldPlaying: Bool? = nil
    private var heldShuffle: Bool? = nil
    private var heldRepeat: String? = nil
    private var heldProgress = false
    private(set) var songsSince = 0
    private(set) var nextAfter = 3
    private var lastStyle: String? = nil
    private(set) var prepared: Prepared? = nil
    private var building = false
    private var forceBreak = false
    private var lastSting = -1

    // silent breaks: a short silent track is lined up in Spotify for her to talk over
    private var silenceQueued = false          // it's sitting right at the front of Spotify's queue
    private var silenceTried = false           // already tried to line one up for this break
    private var silenceLeadMs = 0              // how long before the song's end it went in
    private var silenceMisses = 0              // times in a row Spotify played something else instead
    private var lastStraySkip = Date.distantPast

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
            loggedIn = spotify.isLoggedIn
            if let p = await spotify.poll() {
                apply(p)
                problem = ""
                addLog("Connected to Spotify.")
            } else {
                connected = false
                switch spotify.lastStatus {
                case 403: problem = "Spotify refused this account (error 403). In your Spotify developer dashboard, add this account's email under User Management (5 people at most), then reconnect."
                case 401: problem = "Your Spotify login expired or was rejected (error 401). Reconnect to fix it."
                case 429: problem = "Spotify says slow down (error 429). Wait a minute, then try again."
                case 0: problem = "Couldn't reach Spotify. Check the internet connection, then try again."
                default: problem = "Couldn't read playback (Spotify error \(spotify.lastStatus)). Open the Spotify app, then try again."
                }
                addLog(problem)
            }
            await Library.shared.loadAll(force: true)
        } catch {
            connected = false
            loggedIn = spotify.isLoggedIn
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
                // Cara is off air, so a silent track left in the queue has nothing to do: move on
                if Silence.isSilence(now.uri) && now.isPlaying { await skipStraySilence() }
            }
        }
        await checkSleep()
        if pendingItem != nil && Date().timeIntervalSince(pendingSince) > 5 { pendingItem = nil }
    }

    /// Take in a fresh reading from Spotify, and react when the song changes.
    /// Keep what the buttons just set for a moment, even if Spotify still reports the old state.
    private func hold(playing: Bool? = nil, shuffle: Bool? = nil, repeatMode: String? = nil, progress: Bool = false) {
        holdUntil = Date().addingTimeInterval(1.8)
        if let v = playing { heldPlaying = v }
        if let v = shuffle { heldShuffle = v }
        if let v = repeatMode { heldRepeat = v }
        if progress { heldProgress = true }
    }

    private func dropHold() {
        holdUntil = Date.distantPast
        heldPlaying = nil
        heldShuffle = nil
        heldRepeat = nil
        heldProgress = false
    }

    private func apply(_ fresh: Playback) {
        var p = fresh
        if Silence.isSilence(p.uri) {
            // the silent track behind a silent break: show Cara on the air instead of "30 Seconds of Silence"
            p.item = Silence.caraItem(uri: p.uri, durationMs: p.durationMs, station: stationName)
            p.track = nil
        }
        if Date() < holdUntil {
            let sameSong = p.uri == now.uri
            if let v = heldPlaying, p.isPlaying != v, sameSong {
                p.isPlaying = v
                p.progressMs = now.currentProgressMs
                p.stamp = Date()
            }
            if let v = heldShuffle { p.shuffle = v }
            if let v = heldRepeat { p.repeatMode = v }
            if heldProgress && sameSong {
                p.progressMs = now.currentProgressMs
                p.stamp = Date()
            }
        } else if heldPlaying != nil || heldShuffle != nil || heldRepeat != nil || heldProgress {
            dropHold()
        }
        now = p
        connected = true
        problem = ""
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
            contextTries = 0
            contextRetryAt = Date.distantPast
            contextName = knownName(p.contextURI) ?? ""
            if contextName.isEmpty && !p.contextURI.isEmpty { Task { await self.loadContextName() } }
        } else if !lastContext.isEmpty && contextName.isEmpty && contextTries < 4 && Date() >= contextRetryAt {
            // Spotify didn't answer last time (or the library hadn't loaded yet): try again now and then
            Task { await self.loadContextName() }
        }
        let st = stationFull
        if st != loggedStation {
            loggedStation = st
            if running {
                addLog("[station: \(st)]")
                Task {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    self.warmStingers()
                }
            }
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
        if let q = await spotify.queue() { upNext = q }
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
        if let n = knownName(c) { contextName = n; return }
        contextTries += 1
        contextRetryAt = Date().addingTimeInterval(contextTries < 3 ? 15 : 120)
        let name = await spotify.contextName(c)
        guard c == lastContext, let n = name, !n.isEmpty else { return }
        contextName = n
        rememberName(n, for: c)
    }

    /// A name we already know for this playlist / album / artist, without asking Spotify.
    private func knownName(_ uri: String) -> String? {
        guard !uri.isEmpty else { return nil }
        let k = Station.key(uri)
        if k == "spotify:collection" { return "Liked Songs" }
        if let n = contextNames[k], !n.isEmpty { return n }
        let lib = Library.shared
        if let n = lib.playlists.first(where: { Station.key($0.uri) == k })?.name, !n.isEmpty { return n }
        if let n = lib.albums.first(where: { Station.key($0.uri) == k })?.name, !n.isEmpty { return n }
        if let n = lib.artists.first(where: { Station.key($0.uri) == k })?.name, !n.isEmpty { return n }
        return nil
    }

    /// Remembers what something's called, so the station is named the moment it starts playing.
    private func rememberName(_ name: String, for uri: String) {
        let k = Station.key(uri)
        guard !k.isEmpty, !name.isEmpty, contextNames[k] != name else { return }
        if contextNames.count >= 150 { contextNames = [:] }
        contextNames[k] = name
        UserDefaults.standard.set(contextNames, forKey: "contextNames")
    }

    // MARK: start / stop the DJ
    func start() {
        guard connected else { addLog("Connect Spotify first."); Toasts.shared.show("Connect Spotify first", "exclamationmark.triangle.fill"); return }
        guard !running else { return }
        running = true
        songsSince = 0; lastUri = ""; prepared = nil; lastStyle = nil; queued = nil
        silenceQueued = false; silenceTried = false
        dropPopin()
        nextAfter = rollInterval()
        audio.startIdle()
        UIApplication.shared.isIdleTimerDisabled = false
        loggedStation = stationFull
        addLog("DJ is live on \(stationFull). You can lock the screen: it keeps working in the background.")
        lastPoll = Date.distantPast
        Task { await self.ensureSilenceTrack() }
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            self.warmStingers()
        }
    }

    func stop() {
        running = false
        if let p = prepared { try? FileManager.default.removeItem(at: p.file) }
        prepared = nil
        queued = nil
        silenceQueued = false; silenceTried = false
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
        if style == "silent" && !silenceQueued {
            silenceTried = true
            Task { await self.lineUpSilence() }          // the earlier Spotify knows, the surer it is
        }
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
        var station: URL? = nil
        let name = stationName
        if cfg.stationStingers && name != Station.fallback {
            let maker = StationStingers.shared
            // one may already be on its way
            var waited = 0
            while maker.isMaking(name, cfg: cfg) && waited < 60 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                waited += 1
            }
            station = maker.ready(for: name, cfg: cfg)
            if station == nil {
                Toasts.shared.show("Making a \(Station.full(name)) stinger…", "bolt.fill")
                station = await maker.make(station: name, cfg: cfg, log: logger())
            }
        }
        guard let url = station ?? originalStinger() else { addLog("No stingers found in the app."); return }
        if !running { audio.startIdle() }
        speaking = true
        await audio.speak([(url, Float(cfg.stingerVolume / 100))])
        speaking = false
        if !running && sleepAt == nil && !sleepAtTrackEnd { audio.stopIdle() }
    }

    // MARK: the DJ loop
    /// The stinger before a silent break: one made for this station, or one of your originals on plain Non Stop Pop.
    private func pickStinger() -> URL? {
        let name = stationName
        if cfg.stationStingers && name != Station.fallback && !StationStingers.shared.failingLately {
            if let u = StationStingers.shared.ready(for: name, cfg: cfg) { return u }
            addLog("[no \(Station.full(name)) stinger made yet, so none this time]")
            warmStingers()
            return nil
        }
        return originalStinger()
    }

    /// Gets another stinger made for the station that's playing, in the background.
    private func warmStingers() {
        guard cfg.stationStingers, cfg.stingerChance > 0, stationName != Station.fallback else { return }
        StationStingers.shared.warm(station: stationName, cfg: cfg, log: logger())
    }

    /// One of your six original stingers.
    private func originalStinger() -> URL? {
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
        let interval: TimeInterval = (near || Date() < fastUntil || Silence.isSilence(now.uri)) ? 1.2 : 6
        if Date().timeIntervalSince(lastPoll) >= interval {
            lastPoll = Date()
            if let p = await spotify.poll() {
                apply(p)
                // a new song (the silent track between songs doesn't count as one)
                if p.hasItem && p.uri != lastUri && !Silence.isSilence(p.uri) {
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
        let onSilence = Silence.isSilence(now.uri)

        if let f = forced, let p = prepared, p.style != f {           // a different style was already written: redo it
            try? FileManager.default.removeItem(at: p.file)
            prepared = nil
        }

        // the silent track is on, but no break is waiting for it (you skipped around, or a break went another way): move on
        if onSilence {
            let waiting = due && (prepared != nil || (building && progress < 15000))
            if !waiting {
                await skipStraySilence()
                return
            }
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

        if due && prepared == nil && !building && !onSilence && Date() >= buildRetryAt && (remaining < 150000 || forced != nil) {
            let style = forced ?? pickStyle()
            Task { @MainActor in await self.buildBreak(style: style, forUri: self.now.uri, immediate: false) }
            if style == "silent" && !silenceQueued && !silenceTried && remaining > 4000 {
                silenceTried = true
                Task { @MainActor in await self.lineUpSilence() }
            }
        }

        // a silent break: line the silent track up shortly before this song ends, so the music really stops while she talks
        if due, let p = prepared, p.style == "silent", now.uri == p.forUri, !silenceQueued, !silenceTried,
           remaining < 40000, remaining > 2500, now.repeatMode != "track", !cfg.silenceURI.isEmpty {
            silenceTried = true
            await lineUpSilence()
        }

        if due, let p = prepared {
            var go = false
            if onSilence {
                go = true                                       // the music has stopped: her moment
            } else {
                switch p.style {
                // with the silent track lined up she waits for it; without one she goes right at the end of the song.
                // A silent break that missed its moment (a different song started) talks over its start instead of being thrown away
                case "silent":   go = now.uri == p.forUri ? (!silenceQueued && remaining <= p.pauseMs) : progress >= 1200
                // if the clip finished after its song ended, talk over the start of the next song instead of losing the break
                case "talkover": go = now.uri == p.forUri ? remaining <= p.talkMs : progress >= 1200
                default:         go = now.uri != p.forUri && progress >= p.introAtMs
                }
            }
            if go {
                let late = !onSilence && (p.style == "talkover" || p.style == "silent") && now.uri != p.forUri
                if late && p.style == "silent" && silenceQueued { silenceMissed() }
                prepared = nil
                silenceQueued = false
                silenceTried = false
                songsSince = 0
                lastStyle = p.style
                queued = nil
                nextAfter = rollInterval()
                let silentNow = onSilence || (p.style == "silent" && (!late || foreground))
                if onSilence {
                    addLog(p.style == "silent" ? "[transition: silent (the music has stopped)]" : "[transition: \(p.style), over the silent track]")
                } else if late && silentNow {
                    addLog("[transition: silent (the next song had started, so it's paused for her and starts again after)]")
                } else {
                    addLog(late ? "[transition: talkover (late, over the start of this song)]" : "[transition: \(p.style)]")
                }
                if cfg.popinEnabled && !silentNow {
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
                silenceQueued = false; silenceTried = false
            }
        }
    }

    // MARK: the silent track (makes silent breaks really silent)
    /// Makes sure a silent track this account can definitely play is known (checked about once a week,
    /// and straight away after Spotify refuses one).
    private func ensureSilenceTrack() async {
        let nowSec = Date().timeIntervalSince1970
        if !cfg.silenceURI.isEmpty && nowSec - cfg.silenceCheckedAt < 7 * 86400 { return }
        let r = await spotify.findSilence(excluding: cfg.silenceBad)
        guard r.reached else {
            // couldn't ask Spotify right now: use the usual one if it hasn't been refused, and check again next time
            if cfg.silenceURI.isEmpty, let first = Silence.candidates.first(where: { !cfg.silenceBad.contains($0) }) {
                cfg.silenceURI = first
            }
            return
        }
        cfg.silenceURI = r.uri ?? ""
        cfg.silenceCheckedAt = nowSec
        if let u = r.uri {
            addLog("[silent track ready: \(u)]")
        } else {
            addLog("Spotify has no silent track this account can play, so silent breaks pause the music while the app is open.")
        }
    }

    /// Puts the silent track at the front of Spotify's queue for her silent break, then checks where it landed.
    private func lineUpSilence() async {
        guard running, !silenceQueued else { return }
        if cfg.silenceURI.isEmpty { await ensureSilenceTrack() }
        guard !cfg.silenceURI.isEmpty else { return }
        guard now.repeatMode != "track" else {
            addLog("[repeat-one is on, so this break can't use the silent track]")
            return
        }
        let before = await spotify.queue()
        if let q = before { upNext = q }
        if let i = before?.firstIndex(where: { Silence.isSilence($0.uri) }), i == 0 {
            silenceQueued = true
            silenceLeadMs = now.remainingMs
            addLog("[the silent track is already next in Spotify's queue]")
            return
        }
        let st = await spotify.addToQueue(cfg.silenceURI, device: now.deviceID)
        guard ok(st) else {
            addLog("[couldn't line up the silent track (Spotify said \(st)), so this break stops the music another way]")
            return
        }
        try? await Task.sleep(nanoseconds: 900_000_000)
        guard let q = await spotify.queue() else {
            silenceQueued = true                     // couldn't check; trust it
            silenceLeadMs = now.remainingMs
            addLog("[silent track lined up]")
            return
        }
        upNext = q
        let left = max(0, now.remainingMs / 1000)
        if let i = q.firstIndex(where: { Silence.isSilence($0.uri) }) {
            if i == 0 {
                silenceQueued = true
                silenceLeadMs = now.remainingMs
                addLog("[silent track is next in Spotify's queue, \(left)s before the end: the music will stop for her]")
            } else {
                addLog("[the silent track landed behind \(i) song\(i == 1 ? "" : "s") you queued in Spotify, so this break can't be silent]")
            }
        } else {
            addLog("[Spotify took the silent track but didn't queue it, so it can't play on this account. Finding another one.]")
            markSilenceBad()
        }
    }

    /// The silent track was next in the queue, but Spotify played a different song.
    private func silenceMissed() {
        silenceMisses += 1
        let early = silenceLeadMs > 20000
        addLog("[Spotify skipped the silent track (lined up \(max(0, silenceLeadMs / 1000))s before the end)]")
        // lined up in good time and still skipped, or skipped twice: this one doesn't play here, try another
        if early || silenceMisses >= 2 {
            markSilenceBad()
            silenceMisses = 0
        }
    }

    private func markSilenceBad() {
        let u = cfg.silenceURI
        if !u.isEmpty {
            var bad = cfg.silenceBad
            if !bad.contains(u) { bad.append(u) }
            cfg.silenceBad = bad
        }
        cfg.silenceURI = ""
        cfg.silenceCheckedAt = 0
        Task { await self.ensureSilenceTrack() }
    }

    /// A silent track came up with nothing waiting for it: skip on to the next song.
    private func skipStraySilence() async {
        guard Date().timeIntervalSince(lastStraySkip) > 4 else { return }
        lastStraySkip = Date()
        addLog("[skipping a leftover silent track]")
        let st = await spotify.skipNext()
        if ok(st) { silenceQueued = false }
        poke()
    }

    /// While she talks over the silent track, keeps it from running out (jumps it back to its start).
    private func keepSilenceGoing() -> Task<Void, Never> {
        let length = now.durationMs
        let startAt = now.currentProgressMs
        return Task { @MainActor [weak self] in
            var pos = startAt
            var mark = Date()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { return }
                let at = pos + Int(Date().timeIntervalSince(mark) * 1000)
                if length > 0 && length - at < 4000 {
                    _ = await self?.spotify.seek(0)
                    pos = 0
                    mark = Date()
                }
            }
        }
    }

    /// After a silent break: on to the next song (only if the silent track is still the one playing).
    private func leaveSilence() async {
        for attempt in 0..<4 {
            if let cur = await spotify.poll() {
                apply(cur)
                if !Silence.isSilence(cur.uri) { return }          // Spotify already moved on
                let next = upNext.first(where: { !Silence.isSilence($0.uri) })
                let st = await spotify.skipNext()
                if ok(st) {
                    if let n = next {
                        pendingItem = n
                        pendingSince = Date()
                    }
                    poke()
                    return
                }
            }
            try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 700_000_000)
        }
        addLog("[couldn't skip the silent track; Spotify moves on by itself when it ends]")
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
        if style == "silent" { warmStingers() }
        // the station's named after whatever's playing; if that changed since her last break, she welcomes you to the new one
        let station = stationName
        let before = stationAtLastBreak
        stationAtLastBreak = station
        let switched: String? = (!before.isEmpty && before != station && before != Station.fallback && station != Station.fallback) ? before : nil
        let ctx = Ctx(last: now.track, next: await spotify.nextTrack(), station: station, stationNote: stationNote, switchedFrom: switched)
        let topic = await pickTopic(ctx: ctx, cfg: cfg)
        let mood = currentMood(cfg)
        addLog("[segment: \(topic.name.isEmpty ? topic.label : topic.name)] [mood: \(mood)] [\(cfg.chattiness)]")
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
        let onSilence = Silence.isSilence(now.uri)
        // a silent break that missed its moment (the next song already started) can still be silent while the app is open
        let silentBreak = onSilence || (p.style == "silent" && (!late || foreground))
        var items: [(url: URL, volume: Float)] = []
        if silentBreak, Double(randInt(0, 99)) < Double(cfg.stingerChance), let s = pickStinger() {
            addLog("[stinger before Cara]")
            items.append((s, Float(cfg.stingerVolume / 100)))
        }
        items.append((p.file, voiceVol))

        if onSilence {
            // the silent track is playing, so the music has really stopped: a beat of quiet, she talks, then on to the next song
            let into = now.currentProgressMs
            if into < 600 { try? await Task.sleep(nanoseconds: UInt64(600 - into) * 1_000_000) }
            let keeper = keepSilenceGoing()
            speaking = true
            await audio.speak(items)
            speaking = false
            keeper.cancel()
            await leaveSilence()
        } else if silentBreak {
            // no silent track this time. With the app open, iOS can pause Spotify while she talks;
            // in the background it can't, so she talks over the music instead (never leaving Spotify stuck on pause)
            let device = now.deviceID
            let uri = now.uri
            var interrupted = false
            speaking = true
            if foreground { interrupted = await audio.speakInterrupting(items) }
            if !interrupted {
                addLog("[no silent track this time, so she talks over the music]")
                await audio.speak(items)
            }
            speaking = false
            if interrupted {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if late {
                    // the next song had only just started when she cut in: play it again from the top
                    await spotify.seek(0)
                    try? await Task.sleep(nanoseconds: 300_000_000)
                } else if let cur = await spotify.poll(), cur.uri == uri {
                    // the old song was about a second from its end: if it's still the one playing, jump on to the next song
                    await spotify.skipNext()
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
                await resumeMusic(device: device)          // only does anything if Spotify didn't carry on by itself
            }
        } else {
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
        let text = await writePopIn(track: t, station: stationName, cfg: cfg, log: logger())
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

    private func ok(_ status: Int) -> Bool { status >= 200 && status < 300 }

    /// Explain a failed Spotify command in plain words.
    private func report(_ status: Int) {
        switch status {
        case 200..<300:
            return
        case 404:
            noDevice = true
            Toasts.shared.show("Open Spotify on this iPhone first", "exclamationmark.triangle.fill")
        case 403:
            Toasts.shared.show("Spotify said no. Premium is needed for this", "exclamationmark.triangle.fill")
        case 401:
            Toasts.shared.show("Spotify login expired. Reconnect in Settings", "exclamationmark.triangle.fill")
        case 429:
            Toasts.shared.show("Spotify says slow down. Try again in a moment", "hourglass")
        case 0:
            Toasts.shared.show("Couldn't reach Spotify. Check your connection", "wifi.exclamationmark")
        default:
            Toasts.shared.show("Spotify couldn't do that (\(status))", "exclamationmark.triangle.fill")
        }
    }

    func togglePlay() async {
        if now.isPlaying {
            now.progressMs = now.currentProgressMs; now.stamp = Date(); now.isPlaying = false
            hold(playing: false)
            let st = await spotify.pause()
            if !ok(st) && st != 403 {          // 403 here usually just means it was already paused
                dropHold()
                now.isPlaying = true
                report(st)
            }
        } else {
            now.progressMs = now.currentProgressMs; now.stamp = Date(); now.isPlaying = true
            hold(playing: true)
            var st = await spotify.play(device: now.deviceID)
            if st == 404 || st == 0 {
                if let phone = await spotify.phoneDevice() {
                    st = await spotify.play(device: phone)
                }
            }
            if !ok(st) {
                dropHold()
                now.isPlaying = false
                report(st)
            }
        }
        poke()
    }

    func next() async {
        let before = upNext
        if let n = upNext.first {
            pendingItem = Silence.isSilence(n.uri) ? Silence.caraItem(uri: n.uri, durationMs: n.durationMs, station: stationName) : n
            pendingSince = Date()
            upNext.removeFirst()
        }
        let st = await spotify.skipNext()
        if !ok(st) {
            pendingItem = nil
            upNext = before
            report(st)
        }
        poke()
    }

    func previous() async {
        if now.currentProgressMs > 4000 {
            await seek(0)
            return
        }
        let st = await spotify.skipPrevious()
        if !ok(st) { report(st) }
        poke()
    }

    func toggleShuffle() async {
        let on = !now.shuffle
        now.shuffle = on
        hold(shuffle: on)
        let st = await spotify.setShuffle(on)
        if !ok(st) {
            dropHold()
            now.shuffle = !on
            report(st)
            return
        }
        poke()
        try? await Task.sleep(nanoseconds: 700_000_000)
        await refreshQueue()
    }

    func cycleRepeat() async {
        let old = now.repeatMode
        var next = "off"
        if old == "off" { next = "context" } else if old == "context" { next = "track" }
        now.repeatMode = next
        hold(repeatMode: next)
        let st = await spotify.setRepeat(next)
        if !ok(st) {
            dropHold()
            now.repeatMode = old
            report(st)
        }
        poke()
    }

    func seek(_ ms: Int) async {
        now.progressMs = ms
        now.stamp = Date()
        hold(progress: true)
        let st = await spotify.seek(ms)
        if !ok(st) {
            dropHold()
            report(st)
        }
        poke()
    }

    /// Play an album / playlist / artist, optionally starting at a song, or shuffled.
    func playContext(_ uri: String, name: String? = nil, startAt trackURI: String? = nil, shuffle: Bool = false, count: Int = 0, preview: Track? = nil) async {
        if let n = name { rememberName(n, for: uri) }
        if let p = preview { pendingItem = p; pendingSince = Date() }
        let dev = await playTarget()
        // set shuffle first, so where it starts isn't decided by the old setting
        if dev != nil { await spotify.setShuffle(shuffle, device: dev) }
        // only albums and playlists can start at a chosen song
        let canOffset = uri.contains(":album:") || uri.contains(":playlist:")
        var offsetURI: String? = nil
        var position: Int? = nil
        if canOffset {
            if let t = trackURI { offsetURI = t }
            else if shuffle && count > 1 { position = Int.random(in: 0..<count) }
            else { position = 0 }
        }
        let st = await spotify.startPlayback(context: uri, offsetURI: offsetURI, position: position, device: dev)
        if ok(st) {
            if dev == nil { await spotify.setShuffle(shuffle) }
            now.shuffle = shuffle
            hold(shuffle: shuffle)
        } else {
            pendingItem = nil
            report(st)
        }
        poke()
    }

    /// Play a list of songs (Liked Songs, search results, top songs), starting at one of them.
    func playTracks(_ list: [Track], startAt index: Int, shuffle: Bool = false, context: String? = nil, name: String? = nil) async {
        if let c = context, let n = name { rememberName(n, for: c) }
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
            if dev != nil { await spotify.setShuffle(shuffle, device: dev) }
            let st = await spotify.startPlayback(context: c, offsetURI: first.uri, device: dev)
            if ok(st) {
                if dev == nil { await spotify.setShuffle(shuffle) }
                now.shuffle = shuffle
                hold(shuffle: shuffle)
                localStation = name ?? ""
                poke()
                return
            }
        }
        // otherwise hand Spotify the list itself, already in the right order
        var uris: [String] = []
        if shuffle {
            uris = [first.uri] + playable.filter { $0.uri != first.uri }.shuffled().map { $0.uri }
        } else {
            let k = playable.firstIndex(where: { $0.uri == first.uri }) ?? 0
            uris = playable[k...].map { $0.uri }
        }
        if dev != nil { await spotify.setShuffle(false, device: dev) }
        let st = await spotify.startPlayback(context: nil, uris: Array(uris.prefix(100)), device: dev)
        if ok(st) {
            if dev == nil { await spotify.setShuffle(false) }
            now.shuffle = false
            hold(shuffle: false)
            // no playlist behind a list of songs, so the station takes the list's name (or Non Stop Pop)
            localStation = name ?? ""
        } else {
            pendingItem = nil
            report(st)
        }
        poke()
    }

    func addToQueue(_ t: Track) async {
        let st = await spotify.addToQueue(t.uri, device: now.deviceID)
        if ok(st) {
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
        let target = upNext[index]
        pendingItem = Silence.isSilence(target.uri) ? Silence.caraItem(uri: target.uri, durationMs: target.durationMs, station: stationName) : target
        pendingSince = Date()
        for _ in 0...index {
            let st = await spotify.skipNext()
            if !ok(st) {
                pendingItem = nil
                report(st)
                break
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        poke()
    }

    func toggleLikeCurrent() async {
        guard pendingItem == nil, let it = now.item, !it.uri.isEmpty, !it.isLocal else { return }
        let want = !(currentLiked ?? false)
        currentLiked = want
        let done = await Library.shared.setLiked(it, want)
        if !done { currentLiked = !want }
    }

    func loadDevices() async {
        devices = await spotify.devices()
    }

    func transfer(to d: Device) async {
        let st = await spotify.transfer(to: d.id)
        if !ok(st) { report(st) }
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
        loggedIn = false
        problem = ""
        connected = false
        now = Playback()
        upNext = []
        shownUri = ""
        Library.shared.clear()
    }
}
