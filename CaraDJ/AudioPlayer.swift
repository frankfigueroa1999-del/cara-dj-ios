import Foundation
import AVFoundation

/// Plays Cara's clips and your stingers, and makes iOS turn the Spotify app down while they play.
final class DJAudio: NSObject, AVAudioPlayerDelegate {
    private let session = AVAudioSession.sharedInstance()
    private var keepAlive: AVAudioPlayer?
    private var current: AVAudioPlayer?
    private var finish: (() -> Void)?

    // MARK: staying alive in the background
    /// A silent loop keeps iOS from freezing the app when the screen is off.
    func startIdle() {
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch { }
        if keepAlive == nil, let p = try? AVAudioPlayer(data: DJAudio.silentWav()) {
            p.numberOfLoops = -1
            p.volume = 1.0
            p.prepareToPlay()
            keepAlive = p
        }
        keepAlive?.play()
    }

    func stopIdle() {
        keepAlive?.stop()
        keepAlive = nil
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: speaking (with the Spotify app turned down)
    /// Plays each file in order (never overlapping), with other apps ducked while it happens.
    func speak(_ items: [(url: URL, volume: Float)]) async {
        keepAlive?.stop()
        do {
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
        } catch { }
        for item in items {
            await play(item.url, volume: item.volume)
        }
        // let go of the ducking, then go back to the quiet background mode
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        startIdle()
    }

    /// For SILENT breaks: iOS itself pauses the Spotify app while she talks (no Spotify API pause needed),
    /// then tells Spotify it may carry on when she's done. Much more reliable than pausing and restarting through the API.
    func speakPausing(_ items: [(url: URL, volume: Float)]) async {
        keepAlive?.stop()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
        } catch { }
        try? await Task.sleep(nanoseconds: 350_000_000)          // let Spotify stop before she starts
        for item in items {
            await play(item.url, volume: item.volume)
        }
        try? session.setActive(false, options: .notifyOthersOnDeactivation)   // "Spotify, you can carry on now"
        startIdle()
    }

    private func play(_ url: URL, volume: Float) async {
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.delegate = self
        p.volume = max(0, min(1, volume))
        p.prepareToPlay()
        current = p
        let seconds = p.duration
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var resumed = false
            let done = {
                if !resumed { resumed = true; cont.resume() }
            }
            self.finish = done
            if !p.play() { done(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 3) { done() }   // safety net
        }
        current = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finish?()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        finish?()
    }

    static func duration(of url: URL) -> Double {
        (try? AVAudioPlayer(contentsOf: url))?.duration ?? 8
    }

    /// One second of silence as a WAV file, built in memory.
    static func silentWav() -> Data {
        let sampleRate: UInt32 = 8000
        let count = Int(sampleRate)
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + count * 2))
        d.append("WAVE".data(using: .ascii)!); d.append("fmt ".data(using: .ascii)!)
        u32(16); u16(1); u16(1); u32(sampleRate); u32(sampleRate * 2); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(UInt32(count * 2))
        d.append(Data(count: count * 2))
        return d
    }
}
