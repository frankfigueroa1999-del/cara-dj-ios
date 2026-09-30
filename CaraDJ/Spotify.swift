import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

struct Track {
    var title: String
    var artist: String
    var album: String
    var year: String
    var art: String = ""
    var describe: String { "\(title) by \(artist)" }
}

struct Playback {
    var isPlaying = false
    var hasItem = false
    var uri = ""
    var track: Track? = nil
    var durationMs = 0
    var progressMs = 0
    var stamp = Date()
    var deviceID: String? = nil
    var deviceName = ""
    var shuffle = false
    var repeatMode = "off"

    /// Milliseconds left in the song, estimated from the last check.
    var remainingMs: Int {
        guard isPlaying else { return Int.max }
        let elapsed = Int(Date().timeIntervalSince(stamp) * 1000)
        return durationMs - (progressMs + elapsed)
    }
    var currentProgressMs: Int {
        let elapsed = isPlaying ? Int(Date().timeIntervalSince(stamp) * 1000) : 0
        return min(durationMs, progressMs + elapsed)
    }
}

final class Spotify: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = Spotify()
    let redirect = "caradj://callback"
    let scopes = "user-read-playback-state user-modify-playback-state"
    private let cfg = Config.shared
    private var session: ASWebAuthenticationSession?

    var isLoggedIn: Bool { cfg.refreshToken != nil }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.windows.first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
    }

    // MARK: login (PKCE, no secret needed)
    @MainActor
    func login() async throws {
        let clientID = cfg.clientID.trimmingCharacters(in: .whitespaces)
        guard !clientID.isEmpty else { throw NSError(domain: "Cara", code: 1, userInfo: [NSLocalizedDescriptionKey: "Add your Spotify Client ID in Settings first."]) }
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let verifier = String((0..<64).map { _ in chars.randomElement()! })
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var comps = URLComponents(string: "https://accounts.spotify.com/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
        ]
        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: comps.url!, callbackURLScheme: "caradj") { url, error in
                if let url = url { cont.resume(returning: url) }
                else { cont.resume(throwing: error ?? NSError(domain: "Cara", code: 2)) }
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = false
            self.session = s
            if !s.start() { cont.resume(throwing: NSError(domain: "Cara", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not open the Spotify login."])) }
        }
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw NSError(domain: "Cara", code: 4, userInfo: [NSLocalizedDescriptionKey: "Spotify did not send back a login code."])
        }
        try await tokenRequest([
            "client_id": clientID, "grant_type": "authorization_code", "code": code,
            "redirect_uri": redirect, "code_verifier": verifier,
        ])
    }

    private func tokenRequest(_ params: [String: String]) async throws {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = (form.percentEncodedQuery ?? "").data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = j["access_token"] as? String else {
            throw NSError(domain: "Cara", code: 5, userInfo: [NSLocalizedDescriptionKey: "Spotify login failed (\(status)): " + (String(data: data, encoding: .utf8) ?? "")])
        }
        cfg.accessToken = access
        if let r = j["refresh_token"] as? String { cfg.refreshToken = r }
        cfg.tokenExpiry = Date().timeIntervalSince1970 + (j["expires_in"] as? Double ?? 3600) - 60
    }

    func logout() {
        cfg.accessToken = nil; cfg.refreshToken = nil; cfg.tokenExpiry = 0
    }

    private func validToken() async throws -> String {
        if let t = cfg.accessToken, Date().timeIntervalSince1970 < cfg.tokenExpiry { return t }
        guard let r = cfg.refreshToken else { throw NSError(domain: "Cara", code: 6, userInfo: [NSLocalizedDescriptionKey: "Not logged in to Spotify."]) }
        try await tokenRequest(["client_id": cfg.clientID.trimmingCharacters(in: .whitespaces), "grant_type": "refresh_token", "refresh_token": r])
        return cfg.accessToken ?? ""
    }

    // MARK: Web API
    /// After Spotify says "slow down" (429) the app stays quiet until this time instead of making it worse.
    var blockedUntil = Date.distantPast

    @discardableResult
    func call(_ method: String, _ path: String, query: [String: String] = [:], body: Data? = nil) async -> (status: Int, data: Data) {
        if Date() < blockedUntil { return (429, Data()) }
        do {
            let token = try await validToken()
            var comps = URLComponents(string: "https://api.spotify.com/v1" + path)!
            if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
            var req = URLRequest(url: comps.url!)
            req.httpMethod = method
            req.timeoutInterval = 12
            req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            if let body = body {
                req.httpBody = body
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            } else if method != "GET" { req.setValue("0", forHTTPHeaderField: "Content-Length") }
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 429 {
                let ra = Double((resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 0
                blockedUntil = Date().addingTimeInterval(min(max(ra, 45), 600))
            }
            return (code, data)
        } catch {
            return (0, Data())
        }
    }

    /// The HTTP status of the most recent playback check, so the app can say WHY it couldn't read playback.
    var lastStatus = 0

    func poll() async -> Playback? {
        let t0 = Date()
        let r = await call("GET", "/me/player")
        let t1 = Date()
        lastStatus = r.status
        guard r.status == 200,
              let j = try? JSONSerialization.jsonObject(with: r.data) as? [String: Any] else {
            if r.status == 204 { return Playback() }   // nothing playing anywhere
            return nil
        }
        var p = Playback()
        p.isPlaying = j["is_playing"] as? Bool ?? false
        p.progressMs = j["progress_ms"] as? Int ?? 0
        p.stamp = Date(timeInterval: t1.timeIntervalSince(t0) / 2, since: t0)
        p.deviceID = (j["device"] as? [String: Any])?["id"] as? String
        p.deviceName = (j["device"] as? [String: Any])?["name"] as? String ?? ""
        p.shuffle = j["shuffle_state"] as? Bool ?? false
        p.repeatMode = j["repeat_state"] as? String ?? "off"
        if let item = j["item"] as? [String: Any], (j["currently_playing_type"] as? String ?? "track") == "track" {
            p.hasItem = true
            p.uri = item["uri"] as? String ?? ""
            p.durationMs = item["duration_ms"] as? Int ?? 0
            p.track = Spotify.trackInfo(item)
        }
        return p
    }

    static let notMusic = ["cara", "non stop pop", "non-stop", "advert", "commercial", "sponsor", "jingle"]

    static func trackInfo(_ item: [String: Any]?) -> Track? {
        guard let item = item, (item["is_local"] as? Bool) != true,
              let name = item["name"] as? String else { return nil }
        let artists = (item["artists"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        guard let first = artists.first else { return nil }
        let albumObj = item["album"] as? [String: Any]
        let album = albumObj?["name"] as? String ?? ""
        let year = String((albumObj?["release_date"] as? String ?? "").prefix(4))
        let blob = ([name, album] + artists).joined(separator: " ").lowercased()
        if notMusic.contains(where: { blob.contains($0) }) { return nil }
        let imgs = albumObj?["images"] as? [[String: Any]] ?? []
        var art = ""
        if let first = imgs.first { art = first["url"] as? String ?? "" }
        return Track(title: name, artist: first, album: album, year: year, art: art)
    }

    func nextTrack() async -> Track? {
        let r = await call("GET", "/me/player/queue")
        guard r.status == 200, let j = try? JSONSerialization.jsonObject(with: r.data) as? [String: Any],
              let q = j["queue"] as? [[String: Any]], let first = q.first else { return nil }
        return Spotify.trackInfo(first)
    }

    /// This phone's Spotify device (type "Smartphone"). The DJ only ever plays here, never on speakers or other devices.
    func phoneDevice() async -> String? {
        let r = await call("GET", "/me/player/devices")
        guard r.status == 200, let j = try? JSONSerialization.jsonObject(with: r.data) as? [String: Any],
              let devs = j["devices"] as? [[String: Any]] else { return nil }
        var phones: [[String: Any]] = []
        for d in devs {
            let type = (d["type"] as? String ?? "").lowercased()
            let restricted = (d["is_restricted"] as? Bool) == true
            if type == "smartphone" && !restricted { phones.append(d) }
        }
        var pick: [String: Any]? = phones.first
        for d in phones where (d["is_active"] as? Bool) == true { pick = d; break }
        return pick?["id"] as? String
    }
    func transfer(to id: String) async {
        let body = try? JSONSerialization.data(withJSONObject: ["device_ids": [id], "play": true] as [String: Any])
        await call("PUT", "/me/player", body: body)
    }

    func pause() async { await call("PUT", "/me/player/pause") }
    func play(device: String?) async { await call("PUT", "/me/player/play", query: device.map { ["device_id": $0] } ?? [:]) }
    func setShuffle(_ on: Bool) async { await call("PUT", "/me/player/shuffle", query: ["state": on ? "true" : "false"]) }
    func setRepeat(_ mode: String) async { await call("PUT", "/me/player/repeat", query: ["state": mode]) }
    func seek(_ ms: Int) async { await call("PUT", "/me/player/seek", query: ["position_ms": String(ms)]) }
    func skipNext() async { await call("POST", "/me/player/next") }
    func skipPrevious() async { await call("POST", "/me/player/previous") }
}
