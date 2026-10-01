import Foundation
import Darwin

/// If the app ever crashes, this keeps the reason so it can be shown the next time it opens
/// (there's no Mac here to read crash reports on). Swift writes the reason to the app's error output
/// just before it stops; this sends that output to a small file instead of nowhere.
enum CrashLog {
    private static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
    }
    private static var thisRun: URL { folder.appendingPathComponent("cara-run.log") }
    private static var lastRun: URL { folder.appendingPathComponent("cara-last-run.log") }

    /// Call once, as the app starts.
    static func start() {
        let fm = FileManager.default
        try? fm.removeItem(at: lastRun)
        if fm.fileExists(atPath: thisRun.path) { try? fm.moveItem(at: thisRun, to: lastRun) }
        let fd = open(thisRun.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        if fd >= 0 {
            dup2(fd, STDERR_FILENO)
            close(fd)
        }
        NSSetUncaughtExceptionHandler { e in
            let line = "Uncaught exception: " + e.name.rawValue + ": " + (e.reason ?? "") + "\n"
            FileHandle.standardError.write(Data(line.utf8))
        }
    }

    /// Why the app stopped last time, if it crashed (nil when it closed normally).
    static func lastCrash() -> String? {
        guard let h = try? FileHandle(forReadingFrom: lastRun) else { return nil }
        defer { try? h.close() }
        let size: UInt64 = (try? h.seekToEnd()) ?? 0
        let from: UInt64 = size > 65536 ? size - 65536 : 0
        try? h.seek(toOffset: from)
        guard let data = try? h.readToEnd(), let text = String(data: data, encoding: .utf8) else { return nil }
        let markers = ["Fatal error", "fatal error", "Uncaught exception", "precondition failure",
                       "Precondition failed", "Assertion failed", "Terminating app"]
        let lines = text.split(separator: "\n").map(String.init)
        guard let hit = lines.last(where: { line in markers.contains(where: { line.contains($0) }) }) else { return nil }
        return String(hit.trimmingCharacters(in: .whitespaces).prefix(300))
    }
}
