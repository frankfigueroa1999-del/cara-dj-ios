import Foundation
import SwiftUI

/// All your settings, saved on the phone.
final class Config: ObservableObject {
    static let shared = Config()
    private let d = UserDefaults.standard

    @Published var clientID: String { didSet { d.set(clientID, forKey: "clientID") } }
    @Published var elevenKey: String { didSet { d.set(elevenKey, forKey: "elevenKey") } }
    @Published var elevenVoice: String { didSet { d.set(elevenVoice, forKey: "elevenVoice") } }
    @Published var elevenModel: String { didSet { d.set(elevenModel, forKey: "elevenModel") } }
    @Published var geminiKey: String { didSet { d.set(geminiKey, forKey: "geminiKey") } }
    @Published var city: String { didSet { d.set(city, forKey: "city") } }
    @Published var lat: Double { didSet { d.set(lat, forKey: "lat") } }
    @Published var lon: Double { didSet { d.set(lon, forKey: "lon") } }
    @Published var breakMin: Int { didSet { d.set(breakMin, forKey: "breakMin") } }
    @Published var breakMax: Int { didSet { d.set(breakMax, forKey: "breakMax") } }
    @Published var mood: String { didSet { d.set(mood, forKey: "mood") } }
    @Published var djVolume: Double { didSet { d.set(djVolume, forKey: "djVolume") } }
    @Published var stingerVolume: Double { didSet { d.set(stingerVolume, forKey: "stingerVolume") } }
    @Published var stingerChance: Int { didSet { d.set(stingerChance, forKey: "stingerChance") } }
    /// Stingers are remade with the station's name (whenever something nameable is playing).
    @Published var stationStingers: Bool { didSet { d.set(stationStingers, forKey: "stationStingers") } }
    /// Ray Vega, Cara's co-host, joins some breaks.
    @Published var coHost: Bool { didSet { d.set(coHost, forKey: "coHost") } }
    /// How often (percent of breaks) Cara and Ray talk together.
    @Published var coHostChance: Int { didSet { d.set(coHostChance, forKey: "coHostChance") } }
    /// Ray's ElevenLabs voice ("" for the default).
    @Published var coVoice: String { didSet { d.set(coVoice, forKey: "coVoice") } }
    /// The ElevenLabs voice that reads the station stingers ("" for the default announcer).
    @Published var stationVoice: String { didSet { d.set(stationVoice, forKey: "stationVoice") } }
    @Published var popinEnabled: Bool { didSet { d.set(popinEnabled, forKey: "popinEnabled") } }
    @Published var popinChance: Int { didSet { d.set(popinChance, forKey: "popinChance") } }
    @Published var popinSeconds: Int { didSet { d.set(popinSeconds, forKey: "popinSeconds") } }
    @Published var popinTest: Bool { didSet { d.set(popinTest, forKey: "popinTest") } }
    /// How much Cara says in each break: "quick", "normal" or "chatty".
    @Published var chattiness: String { didSet { d.set(chattiness, forKey: "chattiness") } }
    /// The one-time welcome / setup screens have been shown.
    @Published var welcomed: Bool { didSet { d.set(welcomed, forKey: "welcomed") } }
    /// "dark", "light" or "system".
    @Published var appearance: String { didSet { d.set(appearance, forKey: "appearance") } }
    @Published var recentSearches: [String] { didSet { d.set(recentSearches, forKey: "recentSearches") } }

    // Spotify login (saved so you only log in once)
    var accessToken: String? { get { d.string(forKey: "accessToken") } set { d.set(newValue, forKey: "accessToken") } }
    var refreshToken: String? { get { d.string(forKey: "refreshToken") } set { d.set(newValue, forKey: "refreshToken") } }
    var tokenExpiry: Double { get { d.double(forKey: "tokenExpiry") } set { d.set(newValue, forKey: "tokenExpiry") } }
    /// The permissions Spotify actually granted at the last login.
    var grantedScopes: String { get { d.string(forKey: "grantedScopes") ?? "" } set { d.set(newValue, forKey: "grantedScopes") } }
    /// The short silent Spotify track silent breaks talk over ("" when none can be played on this account).
    var silenceURI: String { get { d.string(forKey: "silenceURI") ?? "" } set { d.set(newValue, forKey: "silenceURI") } }
    /// When that was last checked with Spotify.
    var silenceCheckedAt: Double { get { d.double(forKey: "silenceCheckedAt") } set { d.set(newValue, forKey: "silenceCheckedAt") } }
    /// Silent tracks Spotify wouldn't play on this account (never tried again, but still skipped if they turn up).
    var silenceBad: [String] { get { d.stringArray(forKey: "silenceBad") ?? [] } set { d.set(newValue, forKey: "silenceBad") } }

    /// The frosted look is made for the dark.
    var colorScheme: ColorScheme? { .dark }

    init() {
        func str(_ k: String, _ def: String) -> String { UserDefaults.standard.string(forKey: k) ?? def }
        func num(_ k: String, _ def: Double) -> Double { UserDefaults.standard.object(forKey: k) as? Double ?? def }
        func int(_ k: String, _ def: Int) -> Int { UserDefaults.standard.object(forKey: k) as? Int ?? def }
        func bool(_ k: String, _ def: Bool) -> Bool { UserDefaults.standard.object(forKey: k) as? Bool ?? def }
        let savedClientID = str("clientID", "")
        let savedElevenKey = str("elevenKey", "")
        clientID = savedClientID
        elevenKey = savedElevenKey
        elevenVoice = str("elevenVoice", "")
        elevenModel = str("elevenModel", "eleven_v4")
        geminiKey = str("geminiKey", "")
        city = str("city", "Yakima, Washington")
        lat = num("lat", 46.60)
        lon = num("lon", -120.51)
        breakMin = int("breakMin", 2)
        breakMax = int("breakMax", 5)
        mood = str("mood", "normal")
        djVolume = num("djVolume", 100)
        stingerVolume = num("stingerVolume", 80)
        stingerChance = int("stingerChance", 50)
        stationStingers = bool("stationStingers", true)
        stationVoice = str("stationVoice", "")
        coHost = bool("coHost", true)
        coHostChance = int("coHostChance", 40)
        coVoice = str("coVoice", "")
        popinEnabled = bool("popinEnabled", true)
        popinChance = int("popinChance", 35)
        popinSeconds = int("popinSeconds", 15)
        popinTest = bool("popinTest", false)
        chattiness = str("chattiness", "chatty")
        appearance = str("appearance", "dark")
        recentSearches = UserDefaults.standard.stringArray(forKey: "recentSearches") ?? []
        // anyone who already set the app up never sees the welcome screens
        let already = !savedClientID.isEmpty && !savedElevenKey.isEmpty
        welcomed = bool("welcomed", false) || already
        if already { UserDefaults.standard.set(true, forKey: "welcomed") }
    }
}
