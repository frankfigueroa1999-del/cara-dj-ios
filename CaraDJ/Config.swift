import Foundation
import SwiftUI

/// All your settings, saved on the phone.
final class Config: ObservableObject {
    static let shared = Config()
    private let d = UserDefaults.standard

    @Published var clientID: String { didSet { d.set(clientID, forKey: "clientID") } }
    @Published var elevenKey: String { didSet { d.set(elevenKey, forKey: "elevenKey") } }
    @Published var elevenVoice: String { didSet { d.set(elevenVoice, forKey: "elevenVoice") } }
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

    // Spotify login (saved so you only log in once)
    var accessToken: String? { get { d.string(forKey: "accessToken") } set { d.set(newValue, forKey: "accessToken") } }
    var refreshToken: String? { get { d.string(forKey: "refreshToken") } set { d.set(newValue, forKey: "refreshToken") } }
    var tokenExpiry: Double { get { d.double(forKey: "tokenExpiry") } set { d.set(newValue, forKey: "tokenExpiry") } }

    init() {
        func str(_ k: String, _ def: String) -> String { UserDefaults.standard.string(forKey: k) ?? def }
        func num(_ k: String, _ def: Double) -> Double { UserDefaults.standard.object(forKey: k) as? Double ?? def }
        func int(_ k: String, _ def: Int) -> Int { UserDefaults.standard.object(forKey: k) as? Int ?? def }
        clientID = str("clientID", "")
        elevenKey = str("elevenKey", "")
        elevenVoice = str("elevenVoice", "")
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
    }
}
